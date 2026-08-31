# =============================================================================
# 00_coverage_audit.R — data availability audit
# -----------------------------------------------------------------------------
# PURPOSE
#   Establish, from evidence rather than assumption, what Climate TRACE actually
#   provides for Turkish CBAM-sector facilities, and derive t0 — the earliest
#   year at which the panel can support a CBAM liability calculation.
#
#   t0 is an OUTPUT of this script. The rule that produces it is fixed in
#   section 1 BEFORE the data is inspected, so the start year cannot be quietly
#   tuned to flatter the result.
#
# WHY THE BULK PACKAGE AND NOT THE API
#   An earlier version of this script used the Climate TRACE REST API. The
#   /v6/assets/{id} endpoint returns a single year (the latest) and silently
#   ignores every year parameter tried — `year`, `years`, `since`/`to`,
#   `startDate`/`endDate`. A panel cannot be built from it, and an audit run
#   against it reports the endpoint's limit rather than the data's.
#
#   The country package at downloads.climatetrace.org carries monthly,
#   facility-level records from 2021 onward plus the `other1..other10` fields
#   that the API omits entirely. It is the only viable source for this project.
#
# WHAT THIS SCRIPT DELIBERATELY DOES NOT DO
#   It does not aggregate months into years, and it does not decompose the
#   `other*` fields into direct and indirect emissions. Both are analytical
#   decisions and belong to the author (KARBON_ATLASI.md §9). The audit measures
#   availability and reports diagnostics; it does not choose a formula.
#
# OUTPUTS (committed as evidence, per KARBON_ATLASI.md §11)
#   data/processed/coverage_matrix_panel.csv     sector x year x variable
#   data/processed/coverage_matrix_facility.csv  time-invariant attributes
#   data/processed/coverage_other_fields.csv     other1..other10 diagnostics
#   data/processed/coverage_audit_summary.md     human-readable verdict
#
# RUN
#   Rscript scripts/00_coverage_audit.R
#   (Use Rscript, not R — in PowerShell `R` collides with the Invoke-History alias.)
# =============================================================================

options(encoding = "UTF-8")           # Windows default is not UTF-8; see §2
options(timeout = 600)                # the package is ~45 MB

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(tibble)
  library(readr)
  library(stringr)
})

# Acquisition, integrity and archive inspection live in a shared helper so that
# this script and 01_fetch_climate_trace.R cannot drift apart. See §3 of
# KARBON_ATLASI.md for the approved exception to the numbering convention.
source(file.path("scripts", "_sources.R"))


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

# --- Source -----------------------------------------------------------------
# Country packages are published per gas. Verified available for TUR:
# co2, co2e_100yr, co2e_20yr, n2o, ch4, bc, co. There is NO pfc package.
CT_COUNTRY <- "TUR"

# --- The two populations, and why they use different gas bases ---------------
#
# INDUSTRIAL — CO2. CBAM is a CO2-denominated instrument for cement and iron &
#   steel, and CO2 plus PFCs for aluminium. The PFC component is UNAVAILABLE
#   (no pfc package), so aluminium exposure is an underestimate carried as a
#   documented gap, never silently filled (§8.1).
#
#   Fertilisers are absent by design, not omission: Climate TRACE publishes no
#   fertiliser-PRODUCTION subsector. `synthetic-fertilizer-application` is N2O
#   from fertiliser applied to soils — a different emission source, and not what
#   CBAM regulates. See ROADMAP.md, "Closed questions".
#
# ENERGY — CO2e over 100 years. Measured 2026-08-28, only 18% of Turkish coal
#   mining's footprint is CO2; the other 82% is fugitive methane. Rendering coal
#   mines on a CO2 basis would show them at roughly one sixth of their actual
#   climate impact, which is not a rounding difference but a systematic erasure
#   of Türkiye's methane emissions. Oil and gas production is likewise only 55%
#   CO2.
#
# THE TWO BASES ARE NEVER SUMMED. Every figure carries its unit, and any total
# spanning both populations is refused rather than computed. Mixing a
# CO2-denominated CBAM liability with a CO2e fleet total would be meaningless.
CT_ASSET_CLASSES <- list(
  industrial = list(
    gas        = "co2",
    subsectors = c("iron-and-steel", "cement", "aluminum")
  ),
  energy = list(
    gas        = "co2e_100yr",
    # Note the US spelling of "aluminum" above — Climate TRACE's vocabulary,
    # passed through verbatim.
    subsectors = c("electricity-generation", "coal-mining",
                   "oil-and-gas-production", "oil-and-gas-refining",
                   "oil-and-gas-transport")
  )
)

# Subsectors whose `activity` and `capacity` are withheld upstream as
# "license restricted". Their emissions are published; their production is not.
# They are retained with activity NA and flagged, rather than dropped (§8.1).
CT_ACTIVITY_RESTRICTED <- c("oil-and-gas-production", "oil-and-gas-transport")

# Retained for backwards compatibility with the sections below that predate the
# energy layer and still speak only of the CBAM population.
CT_GAS        <- CT_ASSET_CLASSES$industrial$gas
CT_SUBSECTORS <- CT_ASSET_CLASSES$industrial$subsectors


# --- t0 decision rule — FIXED IN ADVANCE ------------------------------------
# A CBAM liability figure needs BOTH a production quantity (tonnes of good) and
# an emissions quantity. A year carrying only one cannot support the
# calculation, so both are required.
#
# t0 = the earliest year in which EVERY retained sector has at least
#      T0_MIN_COVERAGE of its facilities carrying non-missing values for BOTH
#      `activity` and `emissions_quantity`.
#
# Deliberately strict. If unreachable, the correct response is to report that
# and change the threshold in an explicit, reviewable commit — never to tune it
# downward until an agreeable year appears.
T0_MIN_COVERAGE  <- 0.90
T0_REQUIRED_VARS <- c("activity", "emissions_quantity")

# A year is only treated as a candidate for t0 if it is temporally complete.
# 2026 is partial at the time of writing (5 of 12 months) and must not compete
# with full years on coverage percentages.
T0_REQUIRE_FULL_YEAR <- TRUE
MONTHS_IN_FULL_YEAR  <- 12

# Tolerance for the arithmetic consistency checks in section 6. Relative, not
# absolute, because the quantities span several orders of magnitude.
ARITHMETIC_TOLERANCE <- 0.01


# --- Paths ------------------------------------------------------------------
DIR_RAW       <- file.path("data", "raw", "climate_trace")
DIR_EXTRACT   <- file.path(DIR_RAW, "extracted")
DIR_PROCESSED <- file.path("data", "processed")

for (d in c(DIR_RAW, DIR_EXTRACT, DIR_PROCESSED)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}


# =============================================================================
# 2. ACQUIRE
# =============================================================================
# The archive is cached under data/raw/, which is gitignored. Reproducibility
# comes from this script re-downloading it, not from committing 45 MB (§8.6).

message("[1/6] Acquiring Climate TRACE country package")

# `pkg` is a provenance record, not just a path: URL, byte count, SHA-256 and
# retrieval time travel with it into the summary below.
pkg <- ct_download_package(gas = CT_GAS, country = CT_COUNTRY, dir = DIR_RAW)

sector_members <- ct_sector_files(pkg$path, CT_SUBSECTORS)

# The `latest` URL alias does not say which release you received; the archive's
# own filenames do. Cite this tag, never the REST API's version.
package_version_tag <- ct_release_tag(sector_members)

message("      release: ", package_version_tag,
        ", sha256 ", substr(pkg$sha256, 1, 16), "...")

sector_files <- ct_extract(pkg$path, sector_members, DIR_EXTRACT)


# =============================================================================
# 3. READ AND NORMALISE
# =============================================================================
# The `other1..other10` columns hold mixed types — other6 carries a methodology
# STRING ("extrapolation (national)") while its neighbours carry numerics. They
# are read as character throughout and coerced only where a number is needed.

message("[2/6] Reading sector files")

OTHER_VALUE_COLS <- paste0("other", 1:10)
OTHER_DEF_COLS   <- paste0("other", 1:10, "_def")

read_sector <- function(subsector, path) {
  raw <- read_csv(
    path,
    locale    = locale(encoding = "UTF-8"),   # §2: never rely on the OS default
    col_types = cols(
      .default          = col_character(),
      lat               = col_double(),
      lon               = col_double(),
      emissions_quantity = col_double(),
      activity          = col_double(),
      emissions_factor  = col_double(),
      capacity          = col_double(),
      capacity_factor   = col_double(),
      start_time        = col_datetime(),
      end_time          = col_datetime()
    ),
    progress = FALSE
  )

  raw |>
    mutate(
      subsector_queried = subsector,
      year  = as.integer(format(start_time, "%Y")),
      month = as.integer(format(start_time, "%m"))
    )
}

panel_raw <- imap(sector_files, ~ read_sector(.y, .x)) |> list_rbind()

stopifnot("No rows read — the package layout has changed" = nrow(panel_raw) > 0)

# Guard the gas assumption rather than trusting it. If the package ever bundles
# multiple gases, silently averaging across them would corrupt every downstream
# figure.
gases_present <- sort(unique(panel_raw$gas))
if (!identical(gases_present, CT_GAS)) {
  warning("Expected only gas '", CT_GAS, "' but found: ",
          paste(gases_present, collapse = ", "),
          ". Filtering to ", CT_GAS, " — verify this is correct.")
  panel_raw <- panel_raw |> filter(gas == CT_GAS)
}

# Granularity check. The audit's month-counting logic assumes monthly records.
gran <- sort(unique(panel_raw$temporal_granularity))
if (!identical(gran, "month")) {
  warning("Expected monthly granularity, found: ", paste(gran, collapse = ", "),
          ". The months_observed logic below assumes months.")
}

message("      ", nrow(panel_raw), " monthly rows, ",
        n_distinct(panel_raw$source_id), " facilities, years ",
        min(panel_raw$year), "-", max(panel_raw$year))


# =============================================================================
# 4. FACILITY REGISTRY (time-invariant attributes)
# =============================================================================

message("[3/6] Building facility registry")

facilities <- panel_raw |>
  group_by(source_id) |>
  summarise(
    name        = first(source_name),
    # source_type is the technology field (e.g. "EAF", "BF/BOF").
    source_type = first(source_type),
    sector      = first(subsector),
    subsector_queried = first(subsector_queried),
    lat         = first(lat),
    lon         = first(lon),
    iso3        = first(iso3_country),
    n_months    = n(),
    .groups = "drop"
  )

# Assert the geography instead of trusting it. Türkiye spans roughly 25.5-45.0 E
# and 35.5-42.5 N; a lon/lat inversion would place these facilities in the
# Indian Ocean and would be invisible until the map was drawn.
geo_suspect <- facilities |>
  filter(!is.na(lat), !is.na(lon)) |>
  filter(lon < 25 | lon > 46 | lat < 35 | lat > 43)

if (nrow(geo_suspect) > 0) {
  warning(nrow(geo_suspect), " facilities fall outside Türkiye's bounding box — ",
          "possible lon/lat inversion. Inspect before building facilities.rds.")
}

message("      ", nrow(facilities), " facilities")


# =============================================================================
# 5. COVERAGE MATRIX
# =============================================================================
# "Coverage" = of the facilities present in a given sector-year, what share
# carry at least one non-missing monthly value for this variable?
#
# NOTE ON THE DENOMINATOR: it is the facilities observed in that sector-year,
# not the full registry. A facility that does not yet exist is not a data gap,
# and conflating the two would understate coverage.
#
# NOTE ON AGGREGATION: this collapses months to a boolean "any value present".
# It does NOT sum, average, or annualise. Choosing an annual aggregation rule is
# an analytical decision reserved for the author (§9).

message("[4/6] Building coverage matrix")

PANEL_VARS <- c("activity", "emissions_quantity", "emissions_factor",
                "capacity", "capacity_factor")

facility_year <- panel_raw |>
  group_by(subsector, year, source_id) |>
  summarise(
    across(all_of(PANEL_VARS), ~ any(!is.na(.x))),
    months_observed = n_distinct(month),
    .groups = "drop"
  )

coverage_panel <- facility_year |>
  pivot_longer(all_of(PANEL_VARS), names_to = "variable", values_to = "has_value") |>
  group_by(sector = subsector, year, variable) |>
  summarise(
    n_facilities  = n(),
    n_available   = sum(has_value),
    pct_available = n_available / n(),
    .groups = "drop"
  ) |>
  arrange(sector, variable, year)

# Temporal completeness per sector-year, reported separately because a year can
# be fully covered across facilities yet cover only part of the calendar.
completeness <- facility_year |>
  group_by(sector = subsector, year) |>
  summarise(
    n_facilities    = n(),
    months_min      = min(months_observed),
    months_max      = max(months_observed),
    is_full_year    = months_max >= MONTHS_IN_FULL_YEAR,
    .groups = "drop"
  ) |>
  arrange(sector, year)

# Time-invariant attribute coverage.
FACILITY_VARS <- c("name", "source_type", "lat", "lon")

coverage_facility <- facilities |>
  mutate(across(all_of(FACILITY_VARS),
                ~ !is.na(.x) & as.character(.x) != "",
                .names = "has_{.col}")) |>
  group_by(sector) |>
  summarise(n_facilities = n(),
            across(starts_with("has_"), sum),
            .groups = "drop") |>
  pivot_longer(starts_with("has_"), names_to = "variable", values_to = "n_available") |>
  mutate(variable      = str_remove(variable, "^has_"),
         pct_available = n_available / n_facilities) |>
  arrange(sector, variable)


# =============================================================================
# 6. other1..other10 DIAGNOSTICS — REPORT ONLY
# =============================================================================
# These columns carry the direct/indirect split, the grid emission intensity,
# the scrap share and a model-methodology flag. They are the reason the bulk
# package is worth using over the API.
#
# This section measures WHAT IS THERE. It deliberately does not decompose direct
# from indirect emissions — that formula is the analytical core and belongs to
# the author (§9). What follows gives them the evidence to write it against.

message("[5/6] Profiling other1..other10 and checking arithmetic")

other_long <- panel_raw |>
  select(source_id, subsector, year, all_of(OTHER_VALUE_COLS), all_of(OTHER_DEF_COLS)) |>
  # The raw columns pair as `other1` / `other1_def`. pivot_longer's `.value`
  # sentinel cannot produce an empty column name, so the unsuffixed half is
  # renamed to `other1_val` first — then one pattern captures both halves.
  rename_with(~ paste0(.x, "_val"), all_of(OTHER_VALUE_COLS)) |>
  pivot_longer(
    cols          = matches("^other\\d+_(val|def)$"),
    names_to      = c("slot", ".value"),
    names_pattern = "^(other\\d+)_(val|def)$"
  )

other_profile <- other_long |>
  filter(!is.na(def), def != "", def != "field_not_included") |>
  group_by(sector = subsector, year, slot, label = def) |>
  summarise(
    n_rows        = n(),
    n_available   = sum(!is.na(val) & val != ""),
    pct_available = n_available / n(),
    .groups = "drop"
  ) |>
  arrange(sector, year, slot)

# The slot -> meaning mapping turns out to be SECTOR-SPECIFIC: cement's `other2`
# is a calcination emissions factor while iron & steel's `other2` is a total
# emissions quantity. Surfacing this map is the audit's most consequential
# output, because a parser that keys on the slot number rather than the `_def`
# label would silently mix a factor with a quantity.
slot_map <- other_profile |>
  distinct(sector, slot, label) |>
  # `other10` sorts before `other2` lexicographically; order numerically instead.
  mutate(slot_n = as.integer(str_remove(slot, "other")),
         label  = str_replace_all(label, "\\|", "/")) |>   # keep the md table intact
  arrange(sector, slot_n) |>
  select(-slot_n)

# Arithmetic consistency. Two identities are checked against the data rather
# than assumed:
#
#   (A)  activity x emissions_factor  ==  emissions_quantity
#   (B)  activity x other1            ==  other2
#
# If (A) holds, `emissions_quantity` is the product of the headline factor.
# If (B) holds and other1 is labelled as a direct-AND-indirect factor, then
# other2 is the combined total — which would make the indirect component
# recoverable. Whether it IS recoverable is the author's call; this only reports
# how often the identities hold.
arithmetic_check <- panel_raw |>
  mutate(
    other1_num = suppressWarnings(as.numeric(other1)),
    other2_num = suppressWarnings(as.numeric(other2)),
    check_a_ok = !is.na(activity) & !is.na(emissions_factor) & !is.na(emissions_quantity) &
      emissions_quantity != 0 &
      abs(activity * emissions_factor - emissions_quantity) / abs(emissions_quantity) < ARITHMETIC_TOLERANCE,
    check_b_ok = !is.na(activity) & !is.na(other1_num) & !is.na(other2_num) &
      other2_num != 0 &
      abs(activity * other1_num - other2_num) / abs(other2_num) < ARITHMETIC_TOLERANCE,
    # If both hold, other2 >= emissions_quantity is what a combined total should
    # look like. A violation would falsify the interpretation.
    combined_ge_direct = !is.na(other2_num) & !is.na(emissions_quantity) &
      other2_num >= emissions_quantity
  ) |>
  group_by(sector = subsector) |>
  summarise(
    n_rows                = n(),
    pct_identity_a        = mean(check_a_ok, na.rm = TRUE),
    pct_identity_b        = mean(check_b_ok, na.rm = TRUE),
    pct_combined_ge_direct = mean(combined_ge_direct, na.rm = TRUE),
    .groups = "drop"
  )


# =============================================================================
# 7. t0 DETERMINATION
# =============================================================================
# Applies the rule fixed in section 1. No discretion is exercised here.

message("[6/6] Determining t0")

full_years <- completeness |>
  group_by(year) |>
  summarise(all_full = all(is_full_year), .groups = "drop")

year_passes <- coverage_panel |>
  filter(variable %in% T0_REQUIRED_VARS) |>
  group_by(year, sector) |>
  summarise(sector_ok = all(pct_available >= T0_MIN_COVERAGE), .groups = "drop") |>
  group_by(year) |>
  summarise(
    n_sectors_ok = sum(sector_ok),
    coverage_ok  = n_sectors_ok == length(CT_SUBSECTORS),
    .groups = "drop"
  ) |>
  left_join(full_years, by = "year") |>
  mutate(passes = coverage_ok & (!T0_REQUIRE_FULL_YEAR | all_full)) |>
  arrange(year)

t0 <- year_passes |> filter(passes) |> slice_min(year, n = 1) |> pull(year)
t0 <- if (length(t0) == 0) NA_integer_ else as.integer(t0[1])

# The last year that is both fully covered and temporally complete. Years beyond
# it are estimates or partial and must carry value_type != observed.
t_last_full <- year_passes |> filter(passes) |> slice_max(year, n = 1) |> pull(year)
t_last_full <- if (length(t_last_full) == 0) NA_integer_ else as.integer(t_last_full[1])
t_max       <- max(panel_raw$year, na.rm = TRUE)

partial_years <- completeness |>
  filter(!is_full_year) |>
  distinct(year, months_max) |>
  arrange(year)

if (is.na(t0)) {
  warning("No year satisfies the t0 rule. Do NOT lower the threshold ad hoc — ",
          "inspect coverage_matrix_panel.csv and change T0_MIN_COVERAGE in an ",
          "explicit, reviewable commit if the rule itself was wrong.")
}


# =============================================================================
# 7b. ENERGY ASSET AUDIT
# =============================================================================
# Everything above concerns the CBAM population and its t0, which is what the
# liability calculation depends on. The energy assets are a separate population
# with a separate purpose — they set the grid carbon intensity that produces the
# industrial installations' indirect emissions, and they carry the fleet
# timeline — so they are audited alongside rather than folded in.
#
# They are read on the CO2e(100yr) basis for the reason given in section 1. The
# two bases are never combined; this section reports its own totals in its own
# unit and the summary labels them.

message("[7b] Auditing energy assets (CO2e basis)")

energy_cfg   <- CT_ASSET_CLASSES$energy
energy_pkg   <- ct_download_package(energy_cfg$gas, CT_COUNTRY, DIR_RAW)
energy_mem   <- ct_sector_files(energy_pkg$path, energy_cfg$subsectors)
energy_files <- ct_extract(energy_pkg$path, energy_mem,
                           file.path(DIR_EXTRACT, energy_cfg$gas))

energy_raw <- energy_files |>
  imap(function(path, subsector_key) {
    read_csv(path,
             locale    = locale(encoding = "UTF-8"),
             col_types = cols(.default = col_character(),
                              lat = col_double(), lon = col_double(),
                              emissions_quantity = col_double(),
                              activity = col_double(),
                              emissions_factor = col_double(),
                              capacity = col_double(),
                              capacity_factor = col_double()),
             progress  = FALSE) |>
      # `subsector_key` rather than `subsector`: the CSV has its own `sector`
      # and `subsector` columns, and assigning to a name a column already holds
      # resolves to the column instead of the argument. That exact mistake
      # tripled a denominator earlier in this project.
      mutate(subsector_key = .env$subsector_key,
             year  = as.integer(str_sub(start_time, 1, 4)),
             month = as.integer(str_sub(start_time, 6, 7)))
  }) |>
  list_rbind()

stopifnot("No energy rows read" = nrow(energy_raw) > 0)

energy_summary <- energy_raw |>
  group_by(subsector = subsector_key) |>
  summarise(
    facilities     = n_distinct(source_id),
    rows           = n(),
    year_min       = min(year, na.rm = TRUE),
    year_max       = max(year, na.rm = TRUE),
    activity_units = paste(unique(na.omit(activity_units)), collapse = "; "),
    has_activity   = any(!is.na(activity) & activity > 0),
    .groups = "drop"
  ) |>
  mutate(
    activity_restricted = subsector %in% CT_ACTIVITY_RESTRICTED
  ) |>
  arrange(desc(facilities))

# Emissions on the CO2e basis for the last complete year, so the summary can
# state magnitudes rather than only counts.
energy_emissions <- energy_raw |>
  filter(year == max(energy_raw$year[energy_raw$month == 12], na.rm = TRUE)) |>
  group_by(subsector = subsector_key) |>
  summarise(co2e_Mt = sum(emissions_quantity, na.rm = TRUE) / 1e6,
            .groups = "drop") |>
  arrange(desc(co2e_Mt))

# Fuel/technology composition. For electricity this is the fleet mix that the
# grid factor and the policy narrative both rest on.
energy_types <- energy_raw |>
  distinct(subsector = subsector_key, source_id, source_type) |>
  count(subsector, source_type, name = "facilities") |>
  arrange(subsector, desc(facilities))

energy_year_max <- max(energy_raw$year, na.rm = TRUE)

message("      ", sum(energy_summary$facilities), " energy assets across ",
        nrow(energy_summary), " subsectors, ",
        min(energy_summary$year_min), "-", energy_year_max)


# =============================================================================
# 8. WRITE OUTPUTS
# =============================================================================
# write_csv emits UTF-8 without BOM, which §2 requires and which R on Windows
# reads back correctly.

write_csv(coverage_panel,    file.path(DIR_PROCESSED, "coverage_matrix_panel.csv"))
write_csv(coverage_facility, file.path(DIR_PROCESSED, "coverage_matrix_facility.csv"))
write_csv(other_profile,     file.path(DIR_PROCESSED, "coverage_other_fields.csv"))
write_csv(energy_summary,    file.path(DIR_PROCESSED, "coverage_energy_assets.csv"))
write_csv(energy_types,      file.path(DIR_PROCESSED, "coverage_energy_types.csv"))

md <- c(
  "# Coverage audit — Climate TRACE",
  "",
  paste0("Generated by `scripts/00_coverage_audit.R` on ", format(Sys.Date(), "%Y-%m-%d"), "."),
  "This file is generated. Do not edit by hand — re-run the script.",
  "",
  "## Source",
  "",
  paste0("- Package: `", pkg$url, "`"),
  paste0("- Release: **", package_version_tag, "**"),
  paste0("- SHA-256: `", pkg$sha256, "`"),
  paste0("- Retrieved: ", pkg$retrieved_at),
  paste0("- Gas: `", CT_GAS, "`"),
  paste0("- Subsectors: ", paste(CT_SUBSECTORS, collapse = ", ")),
  paste0("- Facilities: ", nrow(facilities)),
  paste0("- Monthly rows: ", nrow(panel_raw)),
  paste0("- Years present: ", min(panel_raw$year), "-", t_max),
  "",
  "The REST API is **not** used. `/v6/assets/{id}` returns a single year and",
  "ignores all year parameters, so no panel can be built from it.",
  "",
  "## t0 rule (fixed before inspecting the data)",
  "",
  paste0("t0 = earliest year in which every sector has at least ",
         T0_MIN_COVERAGE * 100, "% of its facilities carrying non-missing ",
         paste(T0_REQUIRED_VARS, collapse = " and "),
         if (T0_REQUIRE_FULL_YEAR) ", and the year is temporally complete." else "."),
  "",
  paste0("**Result: t0 = ", ifelse(is.na(t0), "NOT REACHED", t0), "**"),
  paste0("**Last fully covered complete year: ",
         ifelse(is.na(t_last_full), "none", t_last_full), "**"),
  "",
  "## Year-by-year verdict",
  "",
  "| year | sectors meeting coverage threshold | full calendar year | passes |",
  "|---|---|---|---|",
  paste0("| ", year_passes$year, " | ", year_passes$n_sectors_ok, " / ",
         length(CT_SUBSECTORS), " | ", ifelse(year_passes$all_full, "yes", "no"),
         " | ", ifelse(year_passes$passes, "yes", "no"), " |"),
  "",
  "## Partial years",
  "",
  if (nrow(partial_years) == 0) "None — every year is temporally complete." else
    c("| year | months observed |", "|---|---|",
      paste0("| ", partial_years$year, " | ", partial_years$months_max, " |"),
      "",
      "Partial years must enter the panel with `value_type = projected` and a",
      "`months_observed` field. They must never be annualised by scaling: cement",
      "production is seasonal, so a 12/n multiplier would bias the result",
      "systematically rather than randomly."),
  "",
  "## Facilities per sector",
  "",
  "| sector | facilities |",
  "|---|---|",
  paste0("| ", names(table(facilities$sector)), " | ",
         as.integer(table(facilities$sector)), " |"),
  "",
  "## Energy assets — a separate population on a separate gas basis",
  "",
  paste0("Read from the `", energy_cfg$gas, "` country package, not `",
         CT_GAS, "`. Only 18% of Turkish coal mining's footprint is CO2; the rest"),
  "is fugitive methane. A CO2-denominated map would show coal mines at roughly one",
  "sixth of their climate impact, which erases Türkiye's methane emissions rather",
  "than rounding them.",
  "",
  "**The two bases are never summed.** CBAM liability is CO2 because the instrument",
  "is; the fleet is CO2e because the physics is. Any total spanning both",
  "populations is refused rather than computed.",
  "",
  "| subsector | facilities | years | activity units | activity published |",
  "|---|---|---|---|---|",
  paste0("| ", energy_summary$subsector, " | ", energy_summary$facilities, " | ",
         energy_summary$year_min, "-", energy_summary$year_max, " | ",
         ifelse(nzchar(energy_summary$activity_units),
                energy_summary$activity_units, "—"), " | ",
         ifelse(energy_summary$activity_restricted,
                "**no — licence restricted**",
                ifelse(energy_summary$has_activity, "yes", "no")), " |"),
  "",
  paste0("Total energy assets: **", sum(energy_summary$facilities), "**. ",
         "With ", nrow(facilities), " industrial installations that is **",
         sum(energy_summary$facilities) + nrow(facilities), "** facilities."),
  "",
  "### Emissions by subsector, last complete year, CO2e(100yr)",
  "",
  "| subsector | Mt CO2e |",
  "|---|---|",
  paste0("| ", energy_emissions$subsector, " | ",
         sprintf("%.2f", energy_emissions$co2e_Mt), " |"),
  "",
  "### Known limits of this population",
  "",
  "- **Renewables are absent.** `electricity-generation` lists combustion plants",
  "  only — no hydro, wind, solar, geothermal or nuclear. A grid emission factor",
  "  computed as emissions divided by generation over this fleet omits roughly a",
  "  third of Turkish output from its denominator and overstates the factor by",
  "  about 57%. The denominator must be completed from TEİAŞ; see ROADMAP.md, E1.",
  "- **Oil and gas production and transport publish no activity or capacity.**",
  "  Upstream marks them `license restricted`. Emissions are published, production",
  "  is not. They are retained with activity NA and flagged, never imputed (§8.1).",
  "- **No commissioning years.** Neither the power nor the coal-mining records",
  "  carry a start year, so the 2000–2026 fleet timeline still depends on GEM.",
  "  Coal mining does already carry GEM-derived metadata — coal type, reserves,",
  "  mine depth, even a GEM Wiki link — but not a start year. See ROADMAP.md, E2.",
  "",
  "## other* slot semantics — SECTOR-SPECIFIC",
  "",
  "**The `other1..other10` slots do not carry the same meaning across sectors.**",
  "This is the single most important structural finding of the audit. Writing",
  "`other2` into a shared column without branching on sector would silently mix",
  "a calcination emissions *factor* (cement) with a total emissions *quantity*",
  "(iron & steel, aluminium). Any parser must key on the `_def` label, never on",
  "the slot number.",
  "",
  "| sector | slot | label |",
  "|---|---|---|",
  paste0("| ", slot_map$sector, " | ", slot_map$slot, " | ", slot_map$label, " |"),
  "",
  "## Arithmetic identities (reported, not applied)",
  "",
  "- **(A)** `activity x emissions_factor == emissions_quantity`",
  "- **(B)** `activity x other1 == other2`",
  "",
  "| sector | rows | (A) holds | (B) holds | other2 >= emissions_quantity |",
  "|---|---|---|---|---|",
  paste0("| ", arithmetic_check$sector, " | ", arithmetic_check$n_rows, " | ",
         sprintf("%.1f%%", 100 * arithmetic_check$pct_identity_a), " | ",
         sprintf("%.1f%%", 100 * arithmetic_check$pct_identity_b), " | ",
         sprintf("%.1f%%", 100 * arithmetic_check$pct_combined_ge_direct), " |"),
  "",
  "Identity (B) is only meaningful where `other2` holds a quantity. It fails for",
  "cement by construction, not by data error: cement's `other2` is the",
  "calcination emissions *factor*. Read the table above before drawing any",
  "conclusion from the percentages here.",
  "",
  "Interpreting these identities — in particular whether an indirect component",
  "is recoverable, and by what expression in each sector — is an analytical",
  "decision reserved for the author (KARBON_ATLASI.md §9). This audit only",
  "reports how often each identity holds.",
  "",
  "## Known gaps",
  "",
  "- **Aluminium PFCs are unavailable.** Climate TRACE publishes no `pfc`",
  "  country package. CBAM covers CO2 *and* PFCs for aluminium, so aluminium",
  "  exposure computed from this source is an underestimate. The gap is carried",
  "  as NA and must be shown in the UI, never filled with a substitute (§8.1).",
  "- **Fertilisers are absent.** No fertiliser-production subsector exists;",
  "  `synthetic-fertilizer-application` is agricultural N2O and is not a",
  "  substitute. See ROADMAP.md.",
  paste0("- **Release mismatch.** The bulk package is tagged `", package_version_tag,
         "` while the REST API serves v6. They may not be the same release; cite"),
  "  the package version in SOURCES.md, not the API version.",
  "- All emissions figures are modelled estimates, not verified reports (§8.3).",
  "- Climate TRACE is CC BY 4.0; attribution is a licence condition."
)

writeLines(md, file.path(DIR_PROCESSED, "coverage_audit_summary.md"), useBytes = TRUE)


# =============================================================================
# 9. CONSOLE REPORT
# =============================================================================

cat("\n", strrep("=", 72), "\n", sep = "")
cat("COVERAGE AUDIT COMPLETE — release ", package_version_tag, "\n", sep = "")
cat(strrep("=", 72), "\n\n", sep = "")

cat("Facilities: ", nrow(facilities), "   Monthly rows: ", nrow(panel_raw), "\n\n", sep = "")
print(facilities |> count(sector, name = "facilities"))

cat("\nTemporal completeness:\n")
print(completeness |> select(sector, year, n_facilities, months_max, is_full_year), n = Inf)

cat("\nt0 verdict:\n")
print(year_passes, n = Inf)
cat("\n  t0 = ", ifelse(is.na(t0), "NOT REACHED — see warning", t0), "\n", sep = "")
cat("  last full covered year = ", ifelse(is.na(t_last_full), "none", t_last_full), "\n\n", sep = "")

cat("Arithmetic identities:\n")
print(arithmetic_check)

cat("\nother* fields discovered:\n")
print(other_profile |> distinct(sector, slot, label) |> arrange(sector, slot), n = Inf)

cat("\n", strrep("-", 72), "\n", sep = "")
cat("ENERGY ASSETS — ", energy_cfg$gas, " basis, NOT summable with the above\n", sep = "")
cat(strrep("-", 72), "\n", sep = "")
print(energy_summary |>
        select(subsector, facilities, year_min, year_max, activity_restricted))

cat("\nEmissions, last complete year (Mt CO2e):\n")
print(energy_emissions |> mutate(co2e_Mt = round(co2e_Mt, 2)))

cat("\nElectricity fleet composition:\n")
print(energy_types |> filter(subsector == "electricity-generation") |>
        select(source_type, facilities), n = Inf)

cat("\nTOTAL POPULATION: ", nrow(facilities), " industrial + ",
    sum(energy_summary$facilities), " energy = ",
    nrow(facilities) + sum(energy_summary$facilities), " facilities\n", sep = "")

cat("\nWritten:\n",
    "  ", file.path(DIR_PROCESSED, "coverage_matrix_panel.csv"), "\n",
    "  ", file.path(DIR_PROCESSED, "coverage_matrix_facility.csv"), "\n",
    "  ", file.path(DIR_PROCESSED, "coverage_other_fields.csv"), "\n",
    "  ", file.path(DIR_PROCESSED, "coverage_energy_assets.csv"), "\n",
    "  ", file.path(DIR_PROCESSED, "coverage_energy_types.csv"), "\n",
    "  ", file.path(DIR_PROCESSED, "coverage_audit_summary.md"), "\n", sep = "")
