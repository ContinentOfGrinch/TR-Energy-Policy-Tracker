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
  "  2. Complete the form and download the Excel workbook.",
  "  3. Save it, unrenamed, into:",
  paste0("       ", normalizePath(DIR_GEM, winslash = "/", mustWork = FALSE)),
  "",
  "  Optional, for coal mines:",
  "  4. https://globalenergymonitor.org/projects/global-coal-mine-tracker/download-data/",
  "     Save the workbook into the same folder.",
  "",
  "Cite the release you actually downloaded, e.g. 'Global Integrated Power",
  "Tracker, Global Energy Monitor, August 2026 release.' The script records the",
  "file name and SHA-256 so the citation can be checked later.",
  "",
  "data/raw/ is gitignored, so the file stays on this machine.",
  strrep("=", 72),
  sep = "\n"
)

# Column patterns. GEM renames fields between trackers and releases, so each
# target is matched case-insensitively against several candidates and the first
# hit wins. The profile printed below is what confirms the match was correct.
COLUMN_PATTERNS <- list(
  gem_id        = c("^gem\\s*unit\\s*id", "^gem\\s*location\\s*id", "^gem.*id$"),
  name          = c("^plant\\s*/?\\s*project\\s*name", "^plant\\s*name",
                    "^project\\s*name", "^mine\\s*name", "^name$"),
  country       = c("^country\\s*/?\\s*area", "^country$"),
  capacity_mw   = c("^capacity\\s*\\(mw\\)", "^capacity\\s*mw", "^capacity$"),
  fuel          = c("^type$", "^fuel$", "^technology$", "^primary\\s*fuel"),
  status        = c("^status$", "^operating\\s*status"),
  start_year    = c("^start\\s*year", "^commissioning\\s*year",
                    "^year\\s*of\\s*commissioning", "^opening\\s*year",
                    "^production\\s*start\\s*year"),
  retired_year  = c("^retired\\s*year", "^closure\\s*year", "^closing\\s*year"),
  lat           = c("^latitude$", "^lat$"),
  lon           = c("^longitude$", "^lon$", "^lng$"),
  owner         = c("^owner", "^parent")
)

# GEM writes country names, not ISO codes, and spells Türkiye either way
# depending on release vintage.
TR_NAMES <- c("Turkey", "Türkiye", "Turkiye", "TUR")


# =============================================================================
# 2. LOCATE THE FILE
# =============================================================================

message("[1/4] Locating GEM workbook in ", DIR_GEM)

candidates <- list.files(DIR_GEM, pattern = "\\.(xlsx|xls|csv)$",
                         full.names = TRUE, ignore.case = TRUE)

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

#' Find the first column whose name matches any of `patterns`.
match_column <- function(cols, patterns) {
  norm <- tolower(trimws(cols))
  for (p in patterns) {
    hit <- which(str_detect(norm, regex(p, ignore_case = TRUE)))
    if (length(hit) > 0) return(cols[hit[1]])
  }
  NA_character_
}

extract_one <- function(path) {
  is_excel <- grepl("\\.xlsx?$", path, ignore.case = TRUE)
  sheets   <- if (is_excel) readxl::excel_sheets(path) else NA_character_

  best <- NULL
  for (sh in sheets) {
    d <- tryCatch(
      if (is_excel) readxl::read_excel(path, sheet = sh, .name_repair = "minimal")
      else read_csv(path, locale = locale(encoding = "UTF-8"),
                    show_col_types = FALSE, name_repair = "minimal"),
      error = function(e) NULL)
    if (is.null(d) || nrow(d) == 0) next

    cols    <- names(d)
    mapping <- map_chr(COLUMN_PATTERNS, ~ match_column(cols, .x))

    # A usable sheet is one that identifies a country and a name. Without those
    # the rest cannot be filtered or joined.
    if (is.na(mapping[["country"]]) || is.na(mapping[["name"]])) next

    tr <- d |> filter(as.character(.data[[mapping[["country"]]]]) %in% TR_NAMES)
    if (nrow(tr) == 0) next

    if (is.null(best) || nrow(tr) > nrow(best$data)) {
      best <- list(sheet = sh, mapping = mapping, data = tr, cols = cols)
    }
  }

  if (is.null(best)) return(NULL)

  m <- best$mapping
  message("      ", basename(path), " / sheet '", best$sheet, "': ",
          nrow(best$data), " Turkish rows")
  message("        column map: ",
          paste(names(m)[!is.na(m)], unname(m)[!is.na(m)],
                sep = " -> ", collapse = ", "))

  missing_key <- names(m)[is.na(m)]
  if (length(missing_key) > 0) {
    message("        NOT FOUND: ", paste(missing_key, collapse = ", "))
  }

  pull_col <- function(key, cast = as.character) {
    if (is.na(m[[key]])) return(rep(NA, nrow(best$data)))
    suppressWarnings(cast(best$data[[m[[key]]]]))
  }

  tibble(
    source_file     = basename(path),
    sheet           = best$sheet,
    gem_id          = pull_col("gem_id"),
    name            = pull_col("name"),
    capacity_mw     = pull_col("capacity_mw", as.numeric),
    fuel            = pull_col("fuel"),
    status          = pull_col("status"),
    start_year      = pull_col("start_year", as.integer),
    retired_year    = pull_col("retired_year", as.integer),
    lat             = pull_col("lat", as.numeric),
    lon             = pull_col("lon", as.numeric),
    owner           = pull_col("owner")
  )
}

gem <- map(candidates, extract_one) |> compact() |> list_rbind()

if (is.null(gem) || nrow(gem) == 0) {
  stop("No Turkish records could be extracted. The profile above lists the\n",
       "columns that were found; if the country or name column is named\n",
       "something unexpected, add its pattern to COLUMN_PATTERNS.", call. = FALSE)
}


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


cat("\n", strrep("=", 72), "\n", sep = "")
cat("GEM INGEST COMPLETE\n")
cat(strrep("=", 72), "\n\n", sep = "")
print(as.data.frame(coverage))

cat("\nBy fuel:\n")
print(gem |> count(fuel, sort = TRUE, name = "records") |> head(15) |> as.data.frame())

cat("\nStart-year distribution:\n")
print(summary(gem$start_year))

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
    "  ", file.path(DIR_PROCESSED, "gem_provenance.csv"), "\n", sep = "")
