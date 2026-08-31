# =============================================================================
# 01c_ingest_gem.R — commissioning years from the Global Energy Monitor
# -----------------------------------------------------------------------------
# PURPOSE
#   Supply the one field neither Climate TRACE package carries: the year a power
#   plant or coal mine entered service. Without it the 2000–2026 fleet timeline
#   cannot exist, because Climate TRACE begins at 2021.
#
# WHY THIS STEP IS MANUAL — AND WHY THAT WAS ACCEPTED
#   GEM publishes no direct download URL; the tracker file sits behind a form.
#   The openly fetchable alternative was measured and rejected: WRI's Global
#   Power Plant Database v1.3 populates `commissioning_year` for 25 of 163
#   Turkish plants — 15% — and stops at 2017, while reporting 695 MW of solar
#   against a real figure more than an order of magnitude larger. A timeline
#   built on 15% coverage would show 18 plants appearing and 145 staying
#   invisible, which is worse than no timeline. See ROADMAP.md, E2.
#
#   The cost is real and is not hidden: a fresh clone cannot run the pipeline
#   end to end without one manual download. This script refuses to proceed
#   without the file rather than silently producing a table full of NA.
#
# WHAT THIS SCRIPT DOES ON FIRST RUN
#   It PROFILES the file before parsing it — sheets, columns, row counts — and
#   prints what it found. GEM's column names differ between trackers and change
#   between releases, so the extraction below matches on patterns rather than
#   fixed names, and the profile is what lets a human confirm the match was
#   right. If a required field cannot be located the script stops and shows the
#   available columns instead of guessing.
#
# OUTPUT
#   data/processed/gem_commissioning.csv
#
# RUN
#   Rscript scripts/01c_ingest_gem.R
#   Rscript scripts/01c_ingest_gem.R --profile-only    # inspect, do not extract
# =============================================================================

options(encoding = "UTF-8")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(tibble)
  library(readr)
  library(stringr)
})

ARGS         <- commandArgs(trailingOnly = TRUE)
PROFILE_ONLY <- "--profile-only" %in% ARGS


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

DIR_GEM       <- file.path("data", "raw", "gem")
DIR_PROCESSED <- file.path("data", "processed")
dir.create(DIR_GEM,       recursive = TRUE, showWarnings = FALSE)
dir.create(DIR_PROCESSED, recursive = TRUE, showWarnings = FALSE)

GEM_INSTRUCTIONS <- paste(
  "",
  strrep("=", 72),
  "GEM TRACKER FILE NOT FOUND",
  strrep("=", 72),
  "",
  "This step needs the Global Integrated Power Tracker, which GEM distributes",
  "through a form rather than a download URL. Fetch it once:",
  "",
  "  1. https://globalenergymonitor.org/projects/global-integrated-power-tracker/download-data/",
  "  2. Complete the form. GEM emails a .zip containing the datasets chosen.",
  "  3. Drop the .zip, unrenamed and unextracted, into:",
  paste0("       ", normalizePath(DIR_GEM, winslash = "/", mustWork = FALSE)),
  "",
  "This script unpacks the archive itself and searches inside it, so there is",
  "nothing to extract by hand. Loose .xlsx or .csv files in that folder are",
  "picked up too.",
  "",
  "Cite the release you actually downloaded, e.g. 'Global Integrated Power",
  "Tracker, Global Energy Monitor, August 2026 release.' The script records the",
  "file name and SHA-256 so the citation can be checked later.",
  "",
  "data/raw/ is gitignored, so the file stays on this machine.",
  strrep("=", 72),
  sep = "\n"
)

# --- Tracker specifications --------------------------------------------------
# The first version of this script guessed column names with regex patterns,
# because the workbooks had not been seen. They have now, so the guessing is
# gone: each tracker is read against its actual schema. Pattern matching across
# an unknown schema is a reasonable way to survive first contact and a bad way
# to build a pipeline — a near-miss silently returns the wrong column.
#
# The `--profile-only` mode remains, because GEM revises these workbooks between
# releases and the profile is how a mismatch gets caught rather than absorbed.
# Every specification below is checked against the sheet before use, and a
# missing column stops the script naming the column and the file.
TRACKER_SPECS <- list(

  power = list(
    match  = "Global Integrated Power",
    sheet  = "Power facilities",
    label  = "Global Integrated Power Tracker",
    cols   = c(
      gem_id       = "GEM unit/phase ID",
      location_id  = "GEM location ID",
      country      = "Country/area",
      name         = "Plant / Project name",
      unit         = "Unit / Phase name",
      capacity_mw  = "Capacity (MW)",
      status       = "Status",
      start_year   = "Start year",
      retired_year = "Retired year",
      type         = "Type",
      technology   = "Technology",
      fuel         = "Fuel (combustion only)",
      # GEM states outright which plants serve an industrial host. This settles
      # ROADMAP E5 far better than the 1.5 km spatial heuristic that was going
      # to stand in for it: a declared attribute rather than an inferred one.
      captive_type = "Captive Industry Type",
      captive_use  = "Captive Industry Use",
      operator     = "Operator(s)",
      owner        = "Owner(s)",
      lat          = "Latitude",
      lon          = "Longitude",
      loc_accuracy = "Location accuracy",
      province     = "Subnational unit (state, province)"
    )
  ),

  # Two sheets, and both are needed. A mine that closed in 2011 belongs in a
  # 2000-2026 timeline exactly as much as one still operating; omitting closures
  # would show a fleet that only ever grows.
  coal_open = list(
    match = "Global Coal Mine Tracker",
    sheet = "Non-closed mines",
    label = "Global Coal Mine Tracker (non-closed)",
    cols  = c(
      gem_id        = "GEM Mine ID",
      country       = "Country / Area",
      name          = "Mine Name",
      status        = "Status",
      capacity_mtpa = "Capacity (Mtpa)",
      start_year    = "Opening Year",
      retired_year  = "Closing Year",
      mine_type     = "Mine Type",
      coal_type     = "Coal Type",
      owner         = "Owners",
      parent        = "Parent Company",
      lat           = "Latitude",
      lon           = "Longitude",
      province      = "State, Province",
      # Independent check on the E4 finding that only 18% of Turkish coal
      # mining's CO2e is CO2.
      ch4_reported  = "Reported Coal Mine Methane Emissions (thousand tonnes CH4)",
      cmm_co2e_100  = "CMM Emissions (CO2e 100 years)"
    )
  ),

  coal_closed = list(
    match = "Global Coal Mine Tracker",
    sheet = "Closed mines",
    label = "Global Coal Mine Tracker (closed)",
    cols  = c(
      gem_id        = "GEM Mine ID",
      country       = "Country / Area",
      name          = "Mine Name",
      status        = "Mine Site Status",
      capacity_mtpa = "Capacity (Mtpa)",
      start_year    = "Opening Year",
      retired_year  = "Closing Year",
      mine_type     = "Mine Type",
      coal_type     = "Coal Type",
      owner         = "Owners",
      parent        = "Parent Company",
      lat           = "Latitude",
      lon           = "Longitude",
      province      = "State, Province"
    )
  )
)

# Cross-validation trackers. These do NOT feed the panel — ROADMAP scope
# decision 3 keeps Climate TRACE as the single source there. They exist to
# check capacity and technology independently, with the disagreement rate
# reported rather than silently reconciled.
CROSSCHECK_SPECS <- list(

  steel = list(
    match = "Iron_and_Steel_Tracker",
    sheet = "Plant capacities and status",
    label = "Global Iron and Steel Tracker",
    cols  = c(
      gem_id       = "GEM plant ID",
      name         = "Plant name (English)",
      country      = "Country/area",
      equipment    = "Main production equipment",
      status       = "Status",
      start_date   = "Start date",
      cap_crude    = "Nominal crude steel capacity (ttpa)",
      cap_bof      = "Nominal BOF steel capacity (ttpa)",
      cap_eaf      = "Nominal EAF steel capacity (ttpa)",
      cap_bf       = "Nominal BF capacity (ttpa)",
      cap_dri      = "Nominal DRI capacity (ttpa)"
    )
  ),

  cement = list(
    match = "Cement and Concrete Tracker",
    sheet = "Final data",
    label = "Global Cement and Concrete Tracker",
    cols  = c(
      gem_id        = "GEM plant ID",
      name          = "Plant name (English)",
      country       = "Country/area",
      # CBAM's cement benchmarks are defined on clinker, so clinker capacity is
      # the number that matters here, not cement capacity.
      cap_cement    = "Cement capacity (million metric tonnes per annum)",
      cap_clinker   = "Clinker capacity (million metric tonnes per annum)",
      production    = "2024-2025 Cement production (million metric tonnes)",
      clinker_ratio = "Clinker substitution rate",
      status        = "Operating status",
      start_date    = "Start date",
      kiln_method   = "Clinker production method",
      # A single "lat, lon" string rather than two columns; split on read.
      coordinates   = "Coordinates"
    )
  )
)

# GEM writes country names, not ISO codes, and spells Türkiye either way
# depending on release vintage.
TR_NAMES <- c("Turkey", "Türkiye", "Turkiye", "TUR")


# =============================================================================
# 2. LOCATE THE FILE
# =============================================================================

message("[1/4] Locating GEM data in ", DIR_GEM)

# GEM's form delivers a zip. Unpack it here rather than making the download a
# two-step manual chore — the fewer hand operations between the form and the
# pipeline, the fewer ways this step goes wrong on someone else's machine.
DIR_GEM_UNPACKED <- file.path(DIR_GEM, "unpacked")

zips <- list.files(DIR_GEM, pattern = "\\.zip$", full.names = TRUE,
                   ignore.case = TRUE)

for (z in zips) {
  target <- file.path(DIR_GEM_UNPACKED, tools::file_path_sans_ext(basename(z)))
  if (!dir.exists(target)) {
    message("      unpacking: ", basename(z))
    dir.create(target, recursive = TRUE, showWarnings = FALSE)
    unzip(z, exdir = target)
  } else {
    message("      already unpacked: ", basename(z))
  }
}

# Search recursively: GEM's archives nest workbooks inside per-tracker folders,
# and the depth differs between bundles.
candidates <- list.files(DIR_GEM, pattern = "\\.(xlsx|xls|csv)$",
                         full.names = TRUE, ignore.case = TRUE,
                         recursive = TRUE)

# Excel writes lock files as ~$name.xlsx when a workbook is open. They are not
# data and readxl chokes on them.
candidates <- candidates[!grepl("^~\\$", basename(candidates))]

if (length(candidates) == 0) {
  stop(GEM_INSTRUCTIONS, call. = FALSE)
}

for (f in candidates) {
  message("      found: ", basename(f), " (",
          round(file.info(f)$size / 1024^2, 2), " MB)")
}

if (!requireNamespace("readxl", quietly = TRUE)) {
  stop("Package `readxl` is required to read GEM's Excel workbooks.\n",
       "Install it with: renv::install('readxl')", call. = FALSE)
}


# =============================================================================
# 3. PROFILE
# =============================================================================
# Print the structure before parsing. GEM's schema is not stable across
# releases, so this is the evidence that the pattern matching below latched onto
# the right columns — and the first thing to look at if it did not.

message("[2/4] Profiling")

profile_file <- function(path) {
  is_excel <- grepl("\\.xlsx?$", path, ignore.case = TRUE)

  sheets <- if (is_excel) readxl::excel_sheets(path) else NA_character_

  cat("\n", strrep("-", 72), "\n", sep = "")
  cat("FILE: ", basename(path), "\n", sep = "")
  cat(strrep("-", 72), "\n", sep = "")
  if (is_excel) cat("sheets: ", paste(sheets, collapse = " | "), "\n\n", sep = "")

  read_sheet <- function(sheet = NULL) {
    if (is_excel) {
      readxl::read_excel(path, sheet = sheet, n_max = 2000,
                         .name_repair = "minimal")
    } else {
      read_csv(path, n_max = 2000, locale = locale(encoding = "UTF-8"),
               show_col_types = FALSE, name_repair = "minimal")
    }
  }

  out <- list()
  for (sh in if (is_excel) sheets else NA) {
    d <- tryCatch(read_sheet(if (is.na(sh)) NULL else sh),
                  error = function(e) NULL)
    if (is.null(d) || ncol(d) == 0) next
    cat(if (is.na(sh)) "  (csv)" else paste0("  sheet '", sh, "'"),
        " — ", ncol(d), " columns\n", sep = "")
    cat("    ", paste(names(d), collapse = " | "), "\n\n", sep = "")
    out[[if (is.na(sh)) "csv" else sh]] <- names(d)
  }
  out
}

profiles <- map(candidates, profile_file) |> set_names(basename(candidates))

if (PROFILE_ONLY) {
  message("\n--profile-only: stopping before extraction.")
  quit(save = "no", status = 0)
}


# =============================================================================
# 4. EXTRACT
# =============================================================================

message("[3/4] Extracting Turkish records")

#' Read one tracker sheet against its declared schema.
#'
#' Every column in the spec must exist. A missing one stops the script naming
#' both the column and the file, because the alternative — carrying on with an
#' NA column — produces a table that looks complete and is not. GEM revises
#' these workbooks between releases, so this is a live risk rather than a
#' theoretical one.
read_tracker <- function(spec, files) {
  path <- files[grepl(spec$match, basename(files), fixed = TRUE)]
  if (length(path) == 0) return(NULL)
  path <- path[1]

  sheets <- readxl::excel_sheets(path)
  if (!spec$sheet %in% sheets) {
    stop("Sheet '", spec$sheet, "' not found in ", basename(path), ".\n",
         "Sheets present: ", paste(sheets, collapse = ", "), "\n",
         "GEM has renamed or restructured this workbook; update TRACKER_SPECS.",
         call. = FALSE)
  }

  d <- suppressWarnings(
    readxl::read_excel(path, sheet = spec$sheet, .name_repair = "minimal",
                       guess_max = 20000)
  )

  missing <- setdiff(unname(spec$cols), names(d))
  if (length(missing) > 0) {
    stop("In ", basename(path), " / '", spec$sheet, "', these columns are absent:\n",
         paste0("  - ", missing, collapse = "\n"), "\n\n",
         "Columns present:\n  ",
         paste(names(d), collapse = " | "), "\n\n",
         "Update TRACKER_SPECS to match this release rather than letting the\n",
         "field silently become NA.", call. = FALSE)
  }

  out <- d |>
    select(all_of(unname(spec$cols))) |>
    rlang::set_names(names(spec$cols)) |>
    filter(as.character(country) %in% TR_NAMES)

  message("      ", spec$label, ": ", nrow(out), " Turkish rows")

  out |>
    mutate(gem_tracker   = spec$label,
           gem_source_file = basename(path))
}

as_year <- function(x) {
  # GEM writes years as numbers, as text, and occasionally as ranges or with
  # qualifiers. Extract the first four-digit run and leave anything else NA
  # rather than coercing a range to its lower bound.
  suppressWarnings(as.integer(str_extract(as.character(x), "\\b(19|20)\\d{2}\\b")))
}

# --- Assets that carry a commissioning year ---------------------------------

power <- read_tracker(TRACKER_SPECS$power, candidates)
coal_open   <- read_tracker(TRACKER_SPECS$coal_open, candidates)
coal_closed <- read_tracker(TRACKER_SPECS$coal_closed, candidates)

if (is.null(power) && is.null(coal_open)) {
  stop("Neither the power tracker nor the coal mine tracker was found in ",
       DIR_GEM, ".\n", GEM_INSTRUCTIONS, call. = FALSE)
}

gem_power <- if (!is.null(power)) {
  power |>
    transmute(
      gem_tracker, gem_source_file,
      asset_group  = "power",
      gem_id       = as.character(gem_id),
      location_id  = as.character(location_id),
      name         = as.character(name),
      unit         = as.character(unit),
      capacity_mw  = suppressWarnings(as.numeric(capacity_mw)),
      status       = as.character(status),
      start_year   = as_year(start_year),
      retired_year = as_year(retired_year),
      fuel_type    = as.character(type),
      technology   = as.character(technology),
      fuel_detail  = as.character(fuel),
      # A plant declared captive serves an industrial host rather than the grid.
      # ROADMAP E5 excludes these from both sides of the grid emission factor.
      captive_type = as.character(captive_type),
      captive_use  = as.character(captive_use),
      is_captive   = !is.na(captive_type) & nzchar(trimws(captive_type)),
      operator     = as.character(operator),
      owner        = as.character(owner),
      lat          = suppressWarnings(as.numeric(lat)),
      lon          = suppressWarnings(as.numeric(lon)),
      province_gem = as.character(province),
      ch4_reported = NA_real_,
      cmm_co2e_100 = NA_real_
    )
} else NULL

harmonise_coal <- function(d) {
  if (is.null(d)) return(NULL)
  d |>
    transmute(
      gem_tracker, gem_source_file,
      asset_group  = "coal_mine",
      gem_id       = as.character(gem_id),
      location_id  = NA_character_,
      name         = as.character(name),
      unit         = NA_character_,
      # Mine capacity is Mtpa of coal, not MW. Kept in its own column so it can
      # never be summed with generating capacity.
      capacity_mw  = NA_real_,
      capacity_mtpa = suppressWarnings(as.numeric(capacity_mtpa)),
      status       = as.character(status),
      start_year   = as_year(start_year),
      retired_year = as_year(retired_year),
      fuel_type    = "coal",
      technology   = as.character(mine_type),
      fuel_detail  = as.character(coal_type),
      captive_type = NA_character_,
      captive_use  = NA_character_,
      is_captive   = FALSE,
      operator     = NA_character_,
      owner        = as.character(owner),
      lat          = suppressWarnings(as.numeric(lat)),
      lon          = suppressWarnings(as.numeric(lon)),
      province_gem = as.character(province),
      ch4_reported = if ("ch4_reported" %in% names(d))
        suppressWarnings(as.numeric(ch4_reported)) else NA_real_,
      cmm_co2e_100 = if ("cmm_co2e_100" %in% names(d))
        suppressWarnings(as.numeric(cmm_co2e_100)) else NA_real_
    )
}

gem <- bind_rows(
  gem_power |> mutate(capacity_mtpa = NA_real_),
  harmonise_coal(coal_open),
  harmonise_coal(coal_closed)
)

if (nrow(gem) == 0) {
  stop("No Turkish records found in the GEM workbooks. Check that the country\n",
       "column spells Türkiye as one of: ",
       paste(TR_NAMES, collapse = ", "), call. = FALSE)
}


# --- Cross-validation tables, not panel inputs ------------------------------
# ROADMAP scope decision 3: Climate TRACE remains the single source for the
# panel. These exist to check it independently and to report the disagreement
# rate in METHODOLOGY, not to be merged in.

crosscheck <- map(CROSSCHECK_SPECS, function(spec) {
  d <- tryCatch(read_tracker(spec, candidates), error = function(e) {
    message("      ", spec$label, ": SKIPPED — ", conditionMessage(e))
    NULL
  })
  if (is.null(d)) return(NULL)

  # Cement gives one "lat, lon" string where steel gives none; normalise both to
  # explicit columns so the tables can be compared on the same terms.
  if ("coordinates" %in% names(d)) {
    parts <- str_split_fixed(as.character(d$coordinates), ",", 2)
    d <- d |> mutate(lat = suppressWarnings(as.numeric(trimws(parts[, 1]))),
                     lon = suppressWarnings(as.numeric(trimws(parts[, 2]))))
  }
  d |> mutate(start_year = as_year(start_date))
}) |> compact()


# =============================================================================
# 5. REPORT AND WRITE
# =============================================================================
# The headline number is start-year coverage, because that is the field this
# entire step exists to obtain. If it is thin the timeline claim has to shrink,
# and that must be visible rather than discovered later.

message("[4/4] Writing outputs")

coverage <- gem |>
  summarise(
    records          = n(),
    with_start_year  = sum(!is.na(start_year)),
    with_coordinates = sum(!is.na(lat) & !is.na(lon)),
    with_capacity    = sum(!is.na(capacity_mw))
  ) |>
  mutate(start_year_pct = with_start_year / records)

write_csv(gem, file.path(DIR_PROCESSED, "gem_commissioning.csv"))

# Cross-validation tables are written separately and named so nobody mistakes
# them for panel inputs.
for (nm in names(crosscheck)) {
  write_csv(crosscheck[[nm]],
            file.path(DIR_PROCESSED, paste0("gem_crosscheck_", nm, ".csv")))
}

# Provenance: GEM's licence requires citing the release, and the digest lets a
# reader confirm which file produced these numbers.
prov <- tibble(
  file   = basename(candidates),
  bytes  = file.info(candidates)$size,
  sha256 = vapply(candidates,
                  function(p) digest::digest(p, algo = "sha256", file = TRUE),
                  character(1)),
  ingested = format(Sys.Date(), "%Y-%m-%d")
)
write_csv(prov, file.path(DIR_PROCESSED, "gem_provenance.csv"))


# --- Attribution — a licence condition, emitted rather than remembered -------
# GEM publishes under CC BY 4.0. Section 3(1)(a) requires more than naming the
# source: the creator, a licence notice, the warranty disclaimer and a URI must
# all travel with any redistribution. Section 3(1)(a)(ii) additionally requires
# stating THAT the material was modified — the clause most projects miss, and
# one this project cannot claim ignorance of because it modifies heavily:
# filtering to Türkiye, joining to Climate TRACE, deriving province and İBBS-2.
#
# Section 4 matters too. GEM's tracker is a database, so Sui Generis Database
# Rights apply: incorporating a substantial portion into `facilities.rds` makes
# that table Adapted Material, and the attribution condition attaches to it.
#
# This block is GENERATED on every ingest so it cannot drift from the file
# actually used, and so nobody has to remember to write it.

gem_attribution <- c(
  "# GEM attribution — Global Energy Monitor",
  "",
  paste0("Generated by `scripts/01c_ingest_gem.R` on ",
         format(Sys.Date(), "%Y-%m-%d"), "."),
  "This file is generated. Do not edit by hand — re-run the script.",
  "",
  "## Required notice",
  "",
  "> Data from Global Energy Monitor, licensed under the Creative Commons",
  "> Attribution 4.0 International Public License (CC BY 4.0).",
  "> <https://creativecommons.org/licenses/by/4.0/>",
  "> <https://globalenergymonitor.org/>",
  "",
  "## Files ingested",
  "",
  "| file | bytes | SHA-256 | ingested |",
  "|---|---|---|---|",
  paste0("| `", prov$file, "` | ", prov$bytes, " | `",
         substr(prov$sha256, 1, 32), "...` | ", prov$ingested, " |"),
  "",
  "Cite the release that was actually downloaded, e.g. \"Global Integrated Power",
  "Tracker, Global Energy Monitor, August 2026 release.\" The digests above",
  "identify the exact files these figures came from.",
  "",
  "## Modifications — required by CC BY 4.0 §3(1)(a)(ii)",
  "",
  "The licence requires stating that the material was modified. It was:",
  "",
  "- Filtered to Turkish records only",
  "- Columns renamed to this project's schema; a subset of fields retained",
  "- Joined to Climate TRACE facility records by name and coordinate proximity",
  "- Province and İBBS-2 region derived from coordinates against Natural Earth",
  "",
  "Match rates and any disagreement between GEM and Climate TRACE on capacity or",
  "technology are reported in METHODOLOGY.md rather than silently reconciled.",
  "",
  "## Database rights — CC BY 4.0 §4",
  "",
  "GEM's tracker is a database. Incorporating a substantial portion of it into",
  "`data/processed/facilities.rds` makes that table Adapted Material under §4(2),",
  "and the attribution condition in §3(1) attaches to it. Anyone redistributing",
  "this project's derived data must carry this notice forward.",
  "",
  "## Disclaimer and endorsement",
  "",
  "The material is provided as-is and as-available, without warranties of any",
  "kind (CC BY 4.0 §5).",
  "",
  "Global Energy Monitor does not endorse this project and no such endorsement is",
  "implied (CC BY 4.0 §2(5)(c))."
)

writeLines(gem_attribution, file.path(DIR_PROCESSED, "SOURCES_GEM.md"),
           useBytes = TRUE)


cat("\n", strrep("=", 72), "\n", sep = "")
cat("GEM INGEST COMPLETE\n")
cat(strrep("=", 72), "\n\n", sep = "")
print(as.data.frame(coverage))

cat("\nBy fuel — NOTE these are units/phases, not plants:\n")
print(gem |> count(asset_group, fuel_type, sort = TRUE, name = "units") |>
        head(20) |> as.data.frame())

# GIPT is one row per unit or phase, and it covers every status from announced
# to cancelled. Both facts inflate a naive total: Türkiye's rows sum to 242 GW,
# of which 99.5 GW is CANCELLED projects that were never built. The operating
# subset is the fleet; everything else is pipeline or history.
cat("\nBy status — the operating row is the fleet, the rest is not:\n")
print(gem |>
        filter(asset_group == "power") |>
        mutate(plant_key = coalesce(location_id, name)) |>
        group_by(status) |>
        summarise(units = n(), plants = n_distinct(plant_key),
                  GW = round(sum(capacity_mw, na.rm = TRUE) / 1000, 1),
                  .groups = "drop") |>
        arrange(desc(GW)) |> as.data.frame())

operating <- gem |> filter(asset_group == "power",
                           tolower(status) == "operating")

cat("\nOPERATING FLEET — fuel mix:\n")
print(operating |>
        mutate(plant_key = coalesce(location_id, name)) |>
        group_by(fuel_type) |>
        summarise(plants = n_distinct(plant_key),
                  GW = round(sum(capacity_mw, na.rm = TRUE) / 1000, 2),
                  .groups = "drop") |>
        arrange(desc(GW)) |> as.data.frame())

renewable_gw <- operating |>
  filter(fuel_type %in% c("hydropower", "utility-scale solar", "wind",
                          "geothermal")) |>
  summarise(gw = sum(capacity_mw, na.rm = TRUE) / 1000) |> pull(gw)
total_gw <- sum(operating$capacity_mw, na.rm = TRUE) / 1000

cat(sprintf(
  "\n  operating total: %.1f GW across %d plants\n  renewable: %.1f GW (%.0f%%)\n",
  total_gw, n_distinct(coalesce(operating$location_id, operating$name)),
  renewable_gw, 100 * renewable_gw / total_gw))
cat("  ^ this is the generation Climate TRACE's power register cannot see,\n")
cat("    and the reason a grid factor computed from that register alone is wrong.\n")

cat("\nCaptive plants — declared by GEM, excluded from the grid factor:\n")
print(gem |> filter(is_captive) |>
        count(captive_type, sort = TRUE, name = "units") |> as.data.frame())

cat("\nStart-year coverage by asset group:\n")
print(gem |> group_by(asset_group) |>
        summarise(rows = n(),
                  with_year = sum(!is.na(start_year)),
                  pct = round(100 * mean(!is.na(start_year))),
                  earliest = suppressWarnings(min(start_year, na.rm = TRUE)),
                  latest = suppressWarnings(max(start_year, na.rm = TRUE)),
                  .groups = "drop") |> as.data.frame())

cat("\nUnits commissioned 2000 or later: ",
    sum(gem$start_year >= 2000, na.rm = TRUE), " of ",
    sum(!is.na(gem$start_year)), " dated\n", sep = "")

if (length(crosscheck) > 0) {
  cat("\nCross-validation tables (NOT panel inputs — ROADMAP decision 3):\n")
  for (nm in names(crosscheck)) {
    cat("  ", nm, ": ", nrow(crosscheck[[nm]]), " Turkish plants\n", sep = "")
  }
}

if (coverage$start_year_pct < 0.5) {
  warning("\n", strrep("!", 72), "\n",
          "Start year is populated for only ",
          sprintf("%.0f%%", 100 * coverage$start_year_pct), " of records.\n",
          "The 2000-2026 fleet timeline rests on this field. Below roughly half,\n",
          "an animation shows a minority of plants appearing while the rest stay\n",
          "invisible, which misrepresents the fleet. Check the column map above\n",
          "before accepting this, and if it is genuine, scale the timeline claim\n",
          "back in ROADMAP.md rather than shipping a misleading animation.\n",
          strrep("!", 72), immediate. = TRUE)
}

cat("\nWritten:\n",
    "  ", file.path(DIR_PROCESSED, "gem_commissioning.csv"), "\n",
    "  ", file.path(DIR_PROCESSED, "gem_provenance.csv"), "\n",
    "  ", file.path(DIR_PROCESSED, "SOURCES_GEM.md"), "  <- attribution, a licence condition\n",
    sep = "")
