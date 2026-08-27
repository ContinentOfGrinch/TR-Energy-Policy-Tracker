# =============================================================================
# global.R — libraries, data and constants shared by ui.R and server.R
# -----------------------------------------------------------------------------
# Sourced once at app startup, before ui.R and server.R. Anything expensive
# belongs here so it runs once per process rather than once per session.
#
# SCOPE OF THIS VERSION
#   Facility map only. `facility_panel.rds` does not exist yet, so there is no
#   time slider and no CBAM liability figure. Both arrive once the panel is
#   built — see ROADMAP.md. Nothing here fabricates a value to fill the gap.
# =============================================================================

# Windows defaults to a non-UTF-8 encoding. Turkish UI labels break silently
# without this, and the failure shows up as mojibake in the browser rather than
# as an error. See KARBON_ATLASI.md §2.
options(encoding = "UTF-8")

suppressPackageStartupMessages({
  library(shiny)
  library(shinydashboard)
  library(leaflet)
  library(dplyr)
})


# =============================================================================
# 1. DATA
# =============================================================================
# The app reads only from data/processed/. It never fetches, never computes a
# pipeline step, and never writes. If the file is missing, fail with an
# instruction rather than an obscure error 40 lines later.

# shiny::runApp() sets the working directory to the app folder, so a path
# relative to the project root resolves to app/data/... and fails. Locate the
# root by its marker file instead, so the app runs identically whether launched
# from the project root, from app/, or by RStudio's Run App button.
find_project_root <- function(marker = "KARBON_ATLASI.md", max_up = 3) {
  path <- normalizePath(".", winslash = "/", mustWork = FALSE)
  for (i in seq_len(max_up + 1)) {
    if (file.exists(file.path(path, marker))) return(path)
    parent <- dirname(path)
    if (identical(parent, path)) break        # reached the filesystem root
    path <- parent
  }
  stop("Could not locate the project root (no ", marker, " found above ",
       normalizePath(".", winslash = "/", mustWork = FALSE), ").", call. = FALSE)
}

PROJECT_ROOT    <- find_project_root()
FACILITIES_PATH <- file.path(PROJECT_ROOT, "data", "processed", "facilities.rds")

if (!file.exists(FACILITIES_PATH)) {
  stop(
    "facilities.rds not found.\n",
    "Run the pipeline first:\n",
    "  Rscript scripts/01_fetch_climate_trace.R\n",
    "  Rscript scripts/02_build_facilities.R",
    call. = FALSE
  )
}

facilities <- readRDS(FACILITIES_PATH)


# =============================================================================
# 2. DISPLAY VOCABULARY
# =============================================================================
# Code and data stay in English; everything the user reads is Turkish (§2).
# Keeping the translation in one named vector means a label is never hardcoded
# at a call site, where it would drift out of sync with its twin.

SECTOR_LABELS <- c(
  "iron-and-steel" = "Demir-Çelik",
  "cement"         = "Çimento",
  "aluminum"       = "Alüminyum"
)

# Colour-blind-safe and distinguishable on the light Positron basemap.
SECTOR_COLOURS <- c(
  "iron-and-steel" = "#B2182B",
  "cement"         = "#2166AC",
  "aluminum"       = "#F4A460"
)

# Geocode quality is shown to the user rather than hidden: a facility whose
# province was inferred by snapping from offshore is a weaker claim than one
# sitting well inside a polygon, and the interface should say so (§8.4).
GEOCODE_LABELS <- c(
  "within_province"    = "İl sınırları içinde",
  "boundary_proximate" = "İl sınırına yakın — atama belirsiz",
  "snapped_to_nearest" = "Poligon dışında — en yakın ile atandı"
)

GEOCODE_BADGE <- c(
  "within_province"    = "#4C9A2A",
  "boundary_proximate" = "#E8A33D",
  "snapped_to_nearest" = "#C0392B"
)


# =============================================================================
# 3. DERIVED CONSTANTS
# =============================================================================
# Computed once here rather than inside a reactive, because they never change.

SECTOR_CHOICES <- setNames(
  names(SECTOR_LABELS),
  paste0(unname(SECTOR_LABELS), " (",
         as.integer(table(facilities$sector)[names(SECTOR_LABELS)]), ")")
)

PROVINCE_CHOICES <- facilities |>
  count(province_name_tr, name = "n") |>
  arrange(province_name_tr) |>
  with(setNames(province_name_tr, paste0(province_name_tr, " (", n, ")")))

# Data vintage, surfaced in the UI. A figure without a vintage is not auditable.
SOURCE_RELEASE <- unique(facilities$source_release)[1]
N_FACILITIES   <- nrow(facilities)
