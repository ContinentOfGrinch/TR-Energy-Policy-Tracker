# =============================================================================
# 01d_fetch_ember.R — national electricity generation and grid carbon intensity
# -----------------------------------------------------------------------------
# PURPOSE
#   Supply the denominator that Climate TRACE cannot. Its Turkish power register
#   lists combustion plants only — no hydro, wind, solar, geothermal or nuclear
#   — so a grid emission factor computed as its emissions divided by its
#   generation omits 43% of national output and overstates the factor by 57%.
#   See ROADMAP.md, E1.
#
# WHY EMBER RATHER THAN TEİAŞ
#   TEİAŞ is the national authority and publishes PDF and spreadsheet reports.
#   Ember compiles national data, publishes CC BY 4.0, exposes a single CSV, and
#   carries a fuel-level series back to 2000. Having already accepted one manual
#   download for GEM, a second was not worth the reproducibility cost when the
#   numbers agree: Ember's published 2024 intensity is 471 gCO2/kWh against
#   Climate TRACE's independently reported 477, a 1.3% gap between two unrelated
#   methods.
#
#   Ember is therefore the operational source and TEİAŞ the cross-check, the
#   same arrangement used for GEM against Climate TRACE. The TEİAŞ comparison is
#   a manual verification recorded in METHODOLOGY, not a pipeline step.
#
# WHAT THIS SCRIPT DOES NOT DO
#   It does not choose the grid emission factor. It writes three independent
#   estimates side by side and reports their spread. Which one enters the
#   indirect-emissions calculation, and how captive generation is netted out, is
#   analytical core work reserved for the author (KARBON_ATLASI.md §9).
#
# OUTPUTS
#   data/processed/ember_generation.csv    generation by fuel by year, 2000+
#   data/processed/grid_intensity.csv      the three estimates, side by side
#   data/processed/SOURCES_EMBER.md        attribution — a licence condition
#
# RUN
#   Rscript scripts/01d_fetch_ember.R
#   Rscript scripts/01d_fetch_ember.R --force     # re-download
# =============================================================================

options(encoding = "UTF-8")
options(timeout = 1800)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(tibble)
  library(readr)
  library(stringr)
})

FORCE <- "--force" %in% commandArgs(trailingOnly = TRUE)


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

EMBER_URL <- paste0("https://storage.googleapis.com/emb-prod-bkt-publicdata/",
                    "public-downloads/yearly_full_release_long_format.csv")

COUNTRY_ISO3 <- "TUR"
YEAR_MIN     <- 2000

DIR_RAW       <- file.path("data", "raw", "ember")
DIR_PROCESSED <- file.path("data", "processed")
dir.create(DIR_RAW,       recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_PROCESSED, recursive = TRUE, showWarnings = FALSE)

EMBER_CSV <- file.path(DIR_RAW, "ember_yearly_full_long.csv")

# Climate TRACE's own reported grid intensity, taken from the `other*` fields of
# the INDUSTRIAL data — it is the value its indirect-emissions estimate already
# uses. Recomputed here from source rather than hardcoded, so it tracks the
# package if that is re-fetched.
CT_MANUFACTURING_DIR <- file.path("data", "raw", "climate_trace", "extracted",
                                  "DATA", "manufacturing")

# Climate TRACE's power register, for the deliberately-wrong third estimate.
CT_POWER_GLOB <- "electricity-generation_emissions_sources_v"


# =============================================================================
# 2. FETCH
# =============================================================================

message("[1/4] Fetching Ember yearly electricity data")

if (!file.exists(EMBER_CSV) || FORCE) {
  message("      downloading ~47 MB: ", EMBER_URL)
  download.file(EMBER_URL, destfile = EMBER_CSV, mode = "wb", quiet = TRUE)
} else {
  message("      cached: ", EMBER_CSV)
}

ember_all <- read_csv(EMBER_CSV, locale = locale(encoding = "UTF-8"),
                      show_col_types = FALSE, progress = FALSE)

# Fail loudly if Ember renames a column rather than silently producing NA.
required_cols <- c("ISO 3 code", "Year", "Category", "Subcategory",
                   "Variable", "Unit", "Value")
missing <- setdiff(required_cols, names(ember_all))
if (length(missing) > 0) {
  stop("Ember's schema has changed. Missing: ", paste(missing, collapse = ", "),
       "\nColumns present: ", paste(names(ember_all), collapse = " | "),
       call. = FALSE)
}

tr <- ember_all |>
  filter(.data[["ISO 3 code"]] == COUNTRY_ISO3, Year >= YEAR_MIN)

stopifnot("No Turkish rows in the Ember release" = nrow(tr) > 0)

message("      ", nrow(tr), " Turkish rows, ",
        min(tr$Year), "-", max(tr$Year))


# =============================================================================
# 3. GENERATION BY FUEL, AND THE PUBLISHED INTENSITY
# =============================================================================

message("[2/4] Extracting generation series")

generation <- tr |>
  filter(Category == "Electricity generation", Subcategory == "Fuel",
         Unit == "TWh") |>
  transmute(year = Year, fuel = Variable, generation_twh = Value) |>
  arrange(year, fuel)

# Ember's "Total" subcategory names the variable differently across releases, so
# the total is summed from the fuel rows. Summing what we already hold also
# guarantees the parts and the whole agree.
totals <- generation |>
  group_by(year) |>
  summarise(total_twh = sum(generation_twh, na.rm = TRUE), .groups = "drop")

RENEWABLE_FUELS <- c("Hydro", "Wind", "Solar", "Other Renewables")

renewable_share <- generation |>
  group_by(year) |>
  summarise(renewable_twh = sum(generation_twh[fuel %in% RENEWABLE_FUELS],
                                na.rm = TRUE),
            .groups = "drop") |>
  left_join(totals, by = "year") |>
  mutate(renewable_share = renewable_twh / total_twh)

ember_intensity <- tr |>
  filter(Category == "Power sector emissions", Variable == "CO2 intensity") |>
  transmute(year = Year, ember_g_per_kwh = Value)

ember_emissions <- tr |>
  filter(Category == "Power sector emissions", Variable == "Total emissions",
         Unit == "mtCO2") |>
  transmute(year = Year, ember_emissions_mt = Value)

write_csv(generation, file.path(DIR_PROCESSED, "ember_generation.csv"))


# =============================================================================
# 4. THREE INDEPENDENT ESTIMATES, SIDE BY SIDE
# =============================================================================
# The point of this table is the spread, not any single row. Two unrelated
# methods agreeing to within a couple of percent is evidence; the third figure
# is included precisely because it is wrong, and showing why it is wrong is what
# stops someone recomputing it later.

message("[3/4] Assembling grid intensity comparison")

read_ct_grid_intensity <- function() {
  files <- list.files(CT_MANUFACTURING_DIR,
                      pattern = "(iron-and-steel|cement|aluminum)_emissions_sources_v",
                      full.names = TRUE)
  if (length(files) == 0) return(tibble(year = integer(), ct_reported_g_per_kwh = numeric()))

  map(files, function(p) {
    d <- read_csv(p, locale = locale(encoding = "UTF-8"),
                  col_types = cols(.default = col_character()), progress = FALSE)
    # Locate the slot whose *_def label is grid_emissions_intensity. The slot
    # NUMBER differs by sector, so keying on the number rather than the label
    # would mix a factor with a quantity — the structural trap recorded in the
    # coverage audit.
    slot <- NA_character_
    for (i in 1:10) {
      lab <- unique(d[[paste0("other", i, "_def")]])
      lab <- lab[!is.na(lab) & nzchar(lab)]
      if (any(lab == "grid_emissions_intensity")) { slot <- paste0("other", i); break }
    }
    if (is.na(slot)) return(NULL)
    d |> transmute(year = as.integer(str_sub(start_time, 1, 4)),
                   v = suppressWarnings(as.numeric(.data[[slot]])))
  }) |>
    compact() |> list_rbind() |> filter(!is.na(v)) |>
    group_by(year) |>
    # Median across facilities and months: Climate TRACE applies a national
    # figure, so the spread is rounding rather than real variation.
    summarise(ct_reported_g_per_kwh = median(v) * 1000, .groups = "drop")
}

read_ct_power_naive <- function() {
  f <- list.files(file.path("data", "raw", "climate_trace", "extracted"),
                  pattern = CT_POWER_GLOB, recursive = TRUE, full.names = TRUE)
  f <- f[grepl("co2/|/co2/", f)]
  if (length(f) == 0) {
    f <- list.files(file.path("data", "raw", "climate_trace", "extracted"),
                    pattern = CT_POWER_GLOB, recursive = TRUE, full.names = TRUE)
  }
  if (length(f) == 0) return(tibble(year = integer(), ct_naive_g_per_kwh = numeric()))

  read_csv(f[1], locale = locale(encoding = "UTF-8"),
           col_types = cols(.default = col_character(),
                            emissions_quantity = col_double(),
                            activity = col_double()),
           progress = FALSE) |>
    mutate(year = as.integer(str_sub(start_time, 1, 4))) |>
    group_by(year) |>
    summarise(
      # tonnes CO2 / MWh -> grams per kWh is a factor of 1000.
      ct_naive_g_per_kwh = 1000 * sum(emissions_quantity, na.rm = TRUE) /
                                  sum(activity, na.rm = TRUE),
      ct_covered_twh = sum(activity, na.rm = TRUE) / 1e6,
      .groups = "drop")
}

ct_reported <- read_ct_grid_intensity()
ct_naive    <- read_ct_power_naive()

grid_intensity <- totals |>
  left_join(ember_intensity,  by = "year") |>
  left_join(ember_emissions,  by = "year") |>
  left_join(renewable_share |> select(year, renewable_twh, renewable_share),
            by = "year") |>
  left_join(ct_reported, by = "year") |>
  left_join(ct_naive,    by = "year") |>
  mutate(
    ct_coverage_share = ct_covered_twh / total_twh,
    ember_vs_ct_pct   = 100 * (ct_reported_g_per_kwh - ember_g_per_kwh) /
                              ember_g_per_kwh
  ) |>
  arrange(year)

write_csv(grid_intensity, file.path(DIR_PROCESSED, "grid_intensity.csv"))


# =============================================================================
# 5. ATTRIBUTION — a licence condition, generated not remembered
# =============================================================================
# Ember publishes CC BY 4.0, like Climate TRACE and GEM. The same three clauses
# apply: §3(1)(a) requires creator, licence notice, disclaimer and URI;
# §3(1)(a)(ii) requires stating that the material was modified; §2(5)(c) forbids
# implying endorsement. See KARBON_ATLASI.md §10.

message("[4/4] Writing attribution")

ember_sha <- digest::digest(EMBER_CSV, algo = "sha256", file = TRUE)

writeLines(c(
  "# Ember attribution",
  "",
  paste0("Generated by `scripts/01d_fetch_ember.R` on ",
         format(Sys.Date(), "%Y-%m-%d"), "."),
  "This file is generated. Do not edit by hand — re-run the script.",
  "",
  "## Required notice",
  "",
  "> Data from Ember (Ember Energy Research CIC), licensed under the Creative",
  "> Commons Attribution 4.0 International Public License (CC BY 4.0).",
  "> <https://creativecommons.org/licenses/by/4.0/>",
  "> <https://ember-energy.org/data/yearly-electricity-data/>",
  "",
  "| field | value |",
  "|---|---|",
  paste0("| Dataset | Yearly Electricity Data, full release, long format |"),
  paste0("| URL | `", EMBER_URL, "` |"),
  paste0("| Retrieved | ", format(file.info(EMBER_CSV)$mtime, "%Y-%m-%d"), " |"),
  paste0("| Size | ", round(file.info(EMBER_CSV)$size / 1024^2, 2), " MB |"),
  paste0("| SHA-256 | `", ember_sha, "` |"),
  paste0("| Years used | ", min(generation$year), "-", max(generation$year), " |"),
  "",
  "## Modifications — required by CC BY 4.0 §3(1)(a)(ii)",
  "",
  "- Filtered to Türkiye (ISO 3 code TUR) and to years from 2000 onward",
  "- Restricted to Electricity generation / Fuel rows in TWh, and to the",
  "  Power sector emissions CO2 intensity and total emissions series",
  "- Totals recomputed by summing the fuel rows rather than reading Ember's own",
  "  total, so that the parts and the whole are guaranteed to agree",
  "- Joined against Climate TRACE figures for comparison",
  "",
  "## Why Ember and not only TEİAŞ",
  "",
  "TEİAŞ is the national authority but publishes PDF and spreadsheet reports.",
  "Ember compiles national data, is machine-readable, and carries a fuel-level",
  "series back to 2000. Its published intensity agrees with Climate TRACE's",
  "independently reported figure to within about 1%, which is the evidence that",
  "using it does not distort the result. TEİAŞ remains the cross-check, recorded",
  "in METHODOLOGY.",
  "",
  "## Disclaimer and endorsement",
  "",
  "Provided as-is and as-available, without warranties of any kind",
  "(CC BY 4.0 §5). Ember does not endorse this project and no endorsement is",
  "implied (CC BY 4.0 §2(5)(c))."
), file.path(DIR_PROCESSED, "SOURCES_EMBER.md"), useBytes = TRUE)


# =============================================================================
# 6. CONSOLE REPORT
# =============================================================================

cat("\n", strrep("=", 74), "\n", sep = "")
cat("EMBER FETCH COMPLETE\n")
cat(strrep("=", 74), "\n\n", sep = "")

cat("Generation by fuel, most recent year (TWh):\n")
print(generation |> filter(year == max(year)) |>
        arrange(desc(generation_twh)) |>
        mutate(generation_twh = round(generation_twh, 2)) |> as.data.frame())

cat("\nTHREE INDEPENDENT GRID INTENSITY ESTIMATES (gCO2/kWh):\n")
print(grid_intensity |>
        filter(year >= 2021) |>
        transmute(year,
                  ember = round(ember_g_per_kwh),
                  climate_trace_reported = round(ct_reported_g_per_kwh),
                  ct_power_fleet_naive = round(ct_naive_g_per_kwh),
                  ember_vs_ct = sprintf("%+.1f%%", ember_vs_ct_pct)) |>
        as.data.frame())

cat("\nWhy the third column is wrong — Climate TRACE power register coverage:\n")
print(grid_intensity |> filter(year >= 2021) |>
        transmute(year,
                  total_twh      = round(total_twh, 1),
                  ct_covered_twh = round(ct_covered_twh, 1),
                  coverage       = sprintf("%.0f%%", 100 * ct_coverage_share),
                  renewable      = sprintf("%.0f%%", 100 * renewable_share)) |>
        as.data.frame())

cat("\nThe first two columns come from unrelated methods and agree closely.\n")
cat("The third divides real emissions by an incomplete denominator.\n")
cat("Choosing between them, and netting out captive generation, is author work.\n")

cat("\nWritten:\n",
    "  ", file.path(DIR_PROCESSED, "ember_generation.csv"), "\n",
    "  ", file.path(DIR_PROCESSED, "grid_intensity.csv"), "\n",
    "  ", file.path(DIR_PROCESSED, "SOURCES_EMBER.md"), "  <- licence condition\n",
    sep = "")
