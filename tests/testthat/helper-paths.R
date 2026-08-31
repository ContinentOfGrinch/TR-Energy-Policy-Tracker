# =============================================================================
# helper-paths.R — locate the project root and load shared fixtures
# -----------------------------------------------------------------------------
# testthat may set the working directory to tests/testthat/, to tests/, or leave
# it at the project root depending on how it is invoked. Rather than guess,
# every test resolves paths through here.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(stringr)
})

#' Walk upwards until the project marker file is found.
project_root <- function(marker = "KARBON_ATLASI.md", max_up = 4) {
  path <- normalizePath(".", winslash = "/", mustWork = FALSE)
  for (i in seq_len(max_up + 1)) {
    if (file.exists(file.path(path, marker))) return(path)
    parent <- dirname(path)
    if (identical(parent, path)) break
    path <- parent
  }
  stop("Could not locate the project root (no ", marker, " above ", getwd(), ")")
}

ROOT      <- project_root()
PROCESSED <- file.path(ROOT, "data", "processed")
POLICIES  <- file.path(ROOT, "policies")

#' Read a processed artefact, or skip the test if the pipeline has not run.
#'
#' Skipping rather than failing keeps a fresh clone green: absence of a built
#' artefact is a "not run yet" state, not a defect.
read_processed <- function(file) {
  path <- file.path(PROCESSED, file)
  skip_if_not(file.exists(path),
              paste0(file, " not built — run the pipeline first"))
  if (grepl("\\.rds$", file)) readRDS(path)
  else read_csv(path, locale = locale(encoding = "UTF-8"), show_col_types = FALSE)
}

#' Türkiye's bounding box INCLUDING maritime jurisdiction. Used to catch
#' lon/lat inversion, which is otherwise invisible until someone looks at the
#' map. The northern bound is 43.5 rather than the 42.5 of the land border
#' because Turkish offshore gas production sits in the Black Sea at about
#' 42.94°N. Widening it does not weaken the check: swapping those coordinates
#' gives 31.3°N / 42.9°E, in Saudi Arabia, still far outside.
TR_BBOX <- list(lon = c(25.5, 45.5), lat = c(35.5, 43.5))

#' Values `geocode_quality` may take. `offshore` distinguishes a facility at sea
#' from one nudged a few hundred metres by a coarse coastline — different
#' situations that would otherwise be conflated.
VALID_GEOCODE <- c("within_province", "boundary_proximate",
                   "snapped_to_nearest", "offshore")

#' The 26 İBBS-2 (NUTS-2) region codes.
NUTS2_PATTERN <- "^TR[0-9ABC][0-9]$"
