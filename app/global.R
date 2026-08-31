# =============================================================================
# global.R — libraries, data and constants shared by ui.R and server.R
# -----------------------------------------------------------------------------
# Sourced once at app startup, before ui.R and server.R. Anything expensive
# belongs here so it runs once per process rather than once per session.
#
# SCOPE OF THIS VERSION
#   Both populations on one map: 88 industrial installations and 212 energy
#   assets. No time slider and no CBAM liability figure yet —
#   `facility_panel.rds` does not exist, because the direct/indirect
#   decomposition is author work (KARBON_ATLASI.md §9). Nothing here fabricates
#   a value to fill that gap.
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
    "  Rscript scripts/01c_ingest_gem.R      # needs a manual GEM download\n",
    "  Rscript scripts/02_build_facilities.R",
    call. = FALSE
  )
}

facilities <- readRDS(FACILITIES_PATH)

# Optional: the grid intensity comparison, if 01d has run. The app degrades
# rather than failing when it is absent.
GRID_PATH <- file.path(PROJECT_ROOT, "data", "processed", "grid_intensity.csv")
grid_intensity <- if (file.exists(GRID_PATH)) {
  utils::read.csv(GRID_PATH, fileEncoding = "UTF-8")
} else NULL


# =============================================================================
# 2. DISPLAY VOCABULARY
# =============================================================================
# Code and data stay in English; everything the user reads is Turkish (§2).
# Keeping the translation in one named vector means a label is never hardcoded
# at a call site, where it would drift out of sync with its twin.

ASSET_CLASS_LABELS <- c(
  "industrial" = "Sanayi tesisleri",
  "energy"     = "Enerji varlıkları"
)

SECTOR_LABELS <- c(
  # Industrial — the CBAM population
  "iron-and-steel"         = "Demir-Çelik",
  "cement"                 = "Çimento",
  "aluminum"               = "Alüminyum",
  # Energy
  "electricity-generation" = "Elektrik Üretimi",
  "coal-mining"            = "Kömür Madenciliği",
  "oil-and-gas-production" = "Petrol-Gaz Üretimi",
  "oil-and-gas-refining"   = "Rafineri",
  "oil-and-gas-transport"  = "Petrol-Gaz Taşıma"
)

# Warm hues for the CBAM subjects, cool for the energy fleet, so the two
# populations separate at a glance before any legend is read. Colour-blind-safe
# and legible on the light Positron basemap.
SECTOR_COLOURS <- c(
  "iron-and-steel"         = "#B2182B",
  "cement"                 = "#D6604D",
  "aluminum"               = "#F4A582",
  "electricity-generation" = "#2166AC",
  "coal-mining"            = "#4D4D4D",
  "oil-and-gas-production" = "#35978F",
  "oil-and-gas-refining"   = "#01665E",
  "oil-and-gas-transport"  = "#80CDC1"
)

# liability_class is the field the whole merge turns on, so it is shown to the
# user rather than kept as an internal code.
LIABILITY_LABELS <- c(
  "direct"          = "Doğrudan — SKDM yükümlülüğü doğuran gömülü emisyon",
  "indirect_driver" = "Dolaylı sürücü — şebeke yoğunluğunu belirler, kendisi SKDM yükümlüsü değil",
  "neutral"         = "Nötr — haritalanır ve sayılır, SKDM hesabının ve şebeke faktörünün dışında"
)

LIABILITY_SHORT <- c(
  "direct"          = "Doğrudan",
  "indirect_driver" = "Dolaylı sürücü",
  "neutral"         = "Nötr"
)

# Geocode quality is shown to the user rather than hidden: a facility whose
# province was inferred by snapping from offshore is a weaker claim than one
# sitting well inside a polygon, and the interface should say so (§8.4).
GEOCODE_LABELS <- c(
  "within_province"    = "İl sınırları içinde",
  "boundary_proximate" = "İl sınırına yakın — atama belirsiz",
  "snapped_to_nearest" = "Poligon dışında — en yakın ile atandı",
  "offshore"           = "Açık deniz — en yakın kıyı iline atandı"
)

GEOCODE_BADGE <- c(
  "within_province"    = "#4C9A2A",
  "boundary_proximate" = "#E8A33D",
  "snapped_to_nearest" = "#C0392B",
  "offshore"           = "#2166AC"
)

# The two populations are denominated in different gases and must never be
# summed. The label travels with every figure that carries a gas basis.
GAS_LABELS <- c(
  "co2"        = "CO₂",
  "co2e_100yr" = "CO₂e (100 yıl)"
)


# =============================================================================
# 3. DERIVED CONSTANTS
# =============================================================================
# Computed once here rather than inside a reactive, because they never change.

sector_counts <- table(facilities$sector)

# Choices are grouped by asset class so the sector list reads as two
# populations rather than eight unrelated categories.
SECTOR_CHOICES_BY_CLASS <- lapply(names(ASSET_CLASS_LABELS), function(cls) {
  secs <- facilities |> filter(asset_class == cls) |> pull(sector) |> unique()
  secs <- secs[order(match(secs, names(SECTOR_LABELS)))]
  setNames(secs,
           paste0(unname(SECTOR_LABELS[secs]), " (",
                  as.integer(sector_counts[secs]), ")"))
})
names(SECTOR_CHOICES_BY_CLASS) <- unname(ASSET_CLASS_LABELS)

ALL_SECTORS <- unlist(unname(SECTOR_CHOICES_BY_CLASS), use.names = FALSE)

PROVINCE_CHOICES <- facilities |>
  count(province_name_tr, name = "n") |>
  arrange(province_name_tr) |>
  with(setNames(province_name_tr, paste0(province_name_tr, " (", n, ")")))

# Data vintage, surfaced in the UI. A figure without a vintage is not auditable.
SOURCE_RELEASE <- unique(facilities$source_release)[1]
N_FACILITIES   <- nrow(facilities)

# Records and places are different numbers: Climate TRACE lists each oil and gas
# field twice, under production and under transport, at one location. Both are
# shown so neither is quoted by accident.
N_SITES <- nrow(dplyr::distinct(facilities, lat, lon))

N_WITH_YEAR   <- sum(!is.na(facilities$commissioning_year))
COMMISSION_PCT <- round(100 * N_WITH_YEAR / N_FACILITIES)

YEAR_RANGE <- range(facilities$commissioning_year, na.rm = TRUE)
