# =============================================================================
# 02_build_facilities.R — build the time-invariant facility table
# -----------------------------------------------------------------------------
# PURPOSE
#   Produce `data/processed/facilities.rds`: one row per facility, carrying only
#   attributes that do not change over time. Anything that varies by year lives
#   in the panel (KARBON_ATLASI.md §6) — putting capacity or status here would
#   break the panel structure.
#
#   The substantive work is deriving province and İBBS-2 (NUTS-2) region from
#   coordinates, since Climate TRACE supplies latitude and longitude but no
#   administrative geography.
#
# PREREQUISITE
#   Rscript scripts/01_fetch_climate_trace.R
#
# OUTPUTS
#   data/processed/facilities.rds
#   data/processed/facilities_geocode_report.csv   assignment diagnostics
#
# RUN
#   Rscript scripts/02_build_facilities.R
# =============================================================================

options(encoding = "UTF-8")
options(timeout = 600)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(tibble)
  library(readr)
  library(stringr)
  library(sf)
})

source(file.path("scripts", "_sources.R"))
source(file.path("scripts", "_validate.R"))


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

CT_COUNTRY <- "TUR"

# Two populations, two gas bases. Mirrors the configuration in
# 00_coverage_audit.R; see ROADMAP.md E4 for why they are not the same.
CT_ASSET_CLASSES <- list(
  industrial = list(
    gas        = "co2",
    subsectors = c("iron-and-steel", "cement", "aluminum")
  ),
  energy = list(
    gas        = "co2e_100yr",
    subsectors = c("electricity-generation", "coal-mining",
                   "oil-and-gas-production", "oil-and-gas-refining",
                   "oil-and-gas-transport")
  )
)

CT_GAS        <- CT_ASSET_CLASSES$industrial$gas
CT_SUBSECTORS <- CT_ASSET_CLASSES$industrial$subsectors

# liability_class, now live rather than reserved (KARBON_ATLASI.md §6).
#   direct          — holds CBAM-relevant embedded emissions
#   indirect_driver — sets the grid intensity that produces industrial indirect
#                     emissions, but is not CBAM-liable itself
#   neutral         — mapped and counted, outside both the CBAM calculation and
#                     the grid factor
LIABILITY_BY_SUBSECTOR <- c(
  "iron-and-steel"         = "direct",
  "cement"                 = "direct",
  "aluminum"               = "direct",
  "electricity-generation" = "indirect_driver",
  "coal-mining"            = "neutral",
  "oil-and-gas-production" = "neutral",
  "oil-and-gas-refining"   = "neutral",
  "oil-and-gas-transport"  = "neutral"
)

# GEM enrichment. Optional: if 01c has not been run the build still completes,
# with commissioning_year NA and the gap reported rather than hidden.
GEM_COMMISSIONING <- file.path("data", "processed", "gem_commissioning.csv")

# How close a Climate TRACE facility and a GEM plant must be, in metres, to be
# treated as the same site. A judgement call, stated here rather than buried:
# GEM and Climate TRACE geocode independently, so exact agreement is not
# expected, but 2 km is wide enough to be wrong in a dense industrial zone. The
# match rate and the distance distribution are both reported.
GEM_MATCH_RADIUS_M <- 2000

DIR_RAW       <- file.path("data", "raw", "climate_trace")
DIR_EXTRACT   <- file.path(DIR_RAW, "extracted")
DIR_NE        <- file.path("data", "raw", "natural_earth")
DIR_PROCESSED <- file.path("data", "processed")

dir.create(DIR_PROCESSED, recursive = TRUE, showWarnings = FALSE)

# All geometry must reach leaflet in EPSG:4326. Transforming explicitly rather
# than assuming is a hard rule (§4): a Turkish national CRS such as EPSG:5254
# would misplace every point silently, with no error to catch it.
CRS_TARGET <- 4326

# A facility this close to a province boundary is flagged, because Natural
# Earth's 10m geometry is not precise enough to adjudicate it. 2 km is a
# judgement call, not a standard — it is recorded in the output so a reader can
# apply their own threshold.
BOUNDARY_PROXIMITY_M <- 2000


# --- Province reference table ------------------------------------------------
# Natural Earth's `iso_3166_2` field was verified against plate codes at eleven
# points (TR-01 Adana, TR-06 Ankara, TR-34 İstanbul, TR-41 Kocaeli, ...) and is
# clean. Its `name` field is NOT: it contains "Kinkkale" for Kırıkkale,
# "Zinguldak" for Zonguldak, "K. Maras" for Kahramanmaraş, and double-encoded
# mojibake that no ENCODING= option repairs. Names therefore come from here,
# keyed on the ISO code, and Natural Earth's own names are discarded.
#
# ISO 3166-2:TR codes are the vehicle plate codes, so `province_code` is simply
# the numeric part.
#
# NUTS-2 assignments follow TÜİK's İstatistiki Bölge Birimleri Sınıflandırması
# (İBBS) Level 2: 26 regions over 81 provinces.
#
#   >>> VERIFY BEFORE PUBLICATION <<<
#   This mapping is transcribed, not fetched from an authoritative file. Before
#   any figure keyed on nuts2_code is published, check it against TÜİK's
#   official İBBS classification and record the source URL and retrieval date in
#   data/processed/SOURCES.md. A classification without a citation is not usable
#   in this project (§7).
#
# Format: "plate|Turkish name|NUTS-2 code"
TR_PROVINCE_RAW <- c(
  "01|Adana|TR62",          "02|Adıyaman|TRC1",       "03|Afyonkarahisar|TR33",
  "04|Ağrı|TRA2",           "05|Amasya|TR83",         "06|Ankara|TR51",
  "07|Antalya|TR61",        "08|Artvin|TR90",         "09|Aydın|TR32",
  "10|Balıkesir|TR22",      "11|Bilecik|TR41",        "12|Bingöl|TRB1",
  "13|Bitlis|TRB2",         "14|Bolu|TR42",           "15|Burdur|TR61",
  "16|Bursa|TR41",          "17|Çanakkale|TR22",      "18|Çankırı|TR82",
  "19|Çorum|TR83",          "20|Denizli|TR32",        "21|Diyarbakır|TRC2",
  "22|Edirne|TR21",         "23|Elazığ|TRB1",         "24|Erzincan|TRA1",
  "25|Erzurum|TRA1",        "26|Eskişehir|TR41",      "27|Gaziantep|TRC1",
  "28|Giresun|TR90",        "29|Gümüşhane|TR90",      "30|Hakkâri|TRB2",
  "31|Hatay|TR63",          "32|Isparta|TR61",        "33|Mersin|TR62",
  "34|İstanbul|TR10",       "35|İzmir|TR31",          "36|Kars|TRA2",
  "37|Kastamonu|TR82",      "38|Kayseri|TR72",        "39|Kırklareli|TR21",
  "40|Kırşehir|TR71",       "41|Kocaeli|TR42",        "42|Konya|TR52",
  "43|Kütahya|TR33",        "44|Malatya|TRB1",        "45|Manisa|TR33",
  "46|Kahramanmaraş|TR63",  "47|Mardin|TRC3",         "48|Muğla|TR32",
  "49|Muş|TRB2",            "50|Nevşehir|TR71",       "51|Niğde|TR71",
  "52|Ordu|TR90",           "53|Rize|TR90",           "54|Sakarya|TR42",
  "55|Samsun|TR83",         "56|Siirt|TRC3",          "57|Sinop|TR82",
  "58|Sivas|TR72",          "59|Tekirdağ|TR21",       "60|Tokat|TR83",
  "61|Trabzon|TR90",        "62|Tunceli|TRB1",        "63|Şanlıurfa|TRC2",
  "64|Uşak|TR33",           "65|Van|TRB2",            "66|Yozgat|TR72",
  "67|Zonguldak|TR81",      "68|Aksaray|TR71",        "69|Bayburt|TRA1",
  "70|Karaman|TR52",        "71|Kırıkkale|TR71",      "72|Batman|TRC3",
  "73|Şırnak|TRC3",         "74|Bartın|TR81",         "75|Ardahan|TRA2",
  "76|Iğdır|TRA2",          "77|Yalova|TR42",         "78|Karabük|TR81",
  "79|Kilis|TRC1",          "80|Osmaniye|TR63",       "81|Düzce|TR42"
)

# İBBS-2 region display names, for UI labels and aggregation headings.
TR_NUTS2_NAMES <- c(
  TR10 = "İstanbul",   TR21 = "Tekirdağ",  TR22 = "Balıkesir", TR31 = "İzmir",
  TR32 = "Aydın",      TR33 = "Manisa",    TR41 = "Bursa",     TR42 = "Kocaeli",
  TR51 = "Ankara",     TR52 = "Konya",     TR61 = "Antalya",   TR62 = "Adana",
  TR63 = "Hatay",      TR71 = "Kırıkkale", TR72 = "Kayseri",   TR81 = "Zonguldak",
  TR82 = "Kastamonu",  TR83 = "Samsun",    TR90 = "Trabzon",   TRA1 = "Erzurum",
  TRA2 = "Ağrı",       TRB1 = "Malatya",   TRB2 = "Van",       TRC1 = "Gaziantep",
  TRC2 = "Şanlıurfa",  TRC3 = "Mardin"
)

provinces_ref <- TR_PROVINCE_RAW |>
  str_split_fixed("\\|", 3) |>
  as_tibble(.name_repair = ~ c("plate", "province_name_tr", "nuts2_code")) |>
  mutate(
    province_code = as.integer(plate),
    iso_3166_2    = paste0("TR-", plate),
    nuts2_name_tr = unname(TR_NUTS2_NAMES[nuts2_code])
  ) |>
  select(iso_3166_2, province_code, province_name_tr, nuts2_code, nuts2_name_tr)

# Fail loudly rather than silently mis-assigning: 81 provinces, 26 regions, and
# every region name resolvable.
stopifnot(
  "Province reference must have 81 rows"      = nrow(provinces_ref) == 81,
  "Province codes must be 1..81 with no gaps" =
    identical(sort(provinces_ref$province_code), 1:81),
  "NUTS-2 reference must have 26 regions"     =
    n_distinct(provinces_ref$nuts2_code) == 26,
  "Every NUTS-2 code needs a display name"    =
    !any(is.na(provinces_ref$nuts2_name_tr))
)


# =============================================================================
# 2. READ FACILITY ATTRIBUTES
# =============================================================================

message("[1/5] Reading Climate TRACE sector files")

read_sector <- function(path) {
  read_csv(path,
           locale    = locale(encoding = "UTF-8"),
           col_types = cols(.default = col_character(),
                            lat = col_double(), lon = col_double()),
           progress  = FALSE)
}

#' Read one asset class from its own gas package.
#'
#' The two populations use different gas bases and this is deliberate: CBAM is a
#' CO2 instrument, while only 18% of coal mining's footprint is CO2. Reading
#' them from separate packages keeps the bases from ever being summed by
#' accident — there is no single table in which both appear as "emissions".
#' See ROADMAP.md, E4.
read_asset_class <- function(cfg, class_name) {
  pkg     <- ct_download_package(cfg$gas, CT_COUNTRY, DIR_RAW)
  members <- ct_sector_files(pkg$path, cfg$subsectors)
  files   <- ct_extract(pkg$path, members, file.path(DIR_EXTRACT, cfg$gas))

  raw <- map(files, read_sector) |> list_rbind()

  # Collapse the monthly records to one row per facility. `first()` is safe only
  # for genuinely time-invariant fields — that is the entire point of this
  # table. A field that varies within a facility would be silently truncated
  # here, so the invariance is asserted rather than assumed.
  varying <- raw |>
    group_by(source_id) |>
    summarise(across(c(source_name, source_type, subsector, lat, lon),
                     n_distinct),
              .groups = "drop") |>
    filter(if_any(-source_id, ~ .x > 1))

  if (nrow(varying) > 0) {
    warning(nrow(varying), " ", class_name, " facilities have time-varying ",
            "values in fields assumed invariant. Inspect before trusting ",
            "facilities.rds.")
  }

  base <- raw |>
    group_by(source_id) |>
    summarise(
      source_name = first(source_name),
      source_type = first(source_type),
      sector      = first(subsector),
      lat         = first(lat),
      lon         = first(lon),
      .groups = "drop"
    ) |>
    mutate(asset_class = class_name,
           gas_basis   = cfg$gas)

  message("      ", class_name, ": ", nrow(base), " facilities (",
          cfg$gas, ")")

  list(base = base, pkg = pkg, members = members, files = files)
}

industrial <- read_asset_class(CT_ASSET_CLASSES$industrial, "industrial")
energy     <- read_asset_class(CT_ASSET_CLASSES$energy,     "energy")

# The release tag is taken from the industrial package because that is the one
# the CBAM figures come from; both packages carry the same tag in practice, and
# a divergence is worth knowing about.
release_tag        <- ct_release_tag(industrial$members)
energy_release_tag <- ct_release_tag(energy$members)
if (!identical(release_tag, energy_release_tag)) {
  warning("Gas packages carry different release tags: industrial ", release_tag,
          ", energy ", energy_release_tag,
          ". Cite both separately in SOURCES.md.")
}

# Kept under their original names so the sections below, written before the
# energy layer existed, continue to mean what they did.
pkg            <- industrial$pkg
sector_members <- industrial$members
sector_files   <- industrial$files

facilities_base <- bind_rows(industrial$base, energy$base)

message("      total: ", nrow(facilities_base), " facilities")


# --- Operator, from the ownership file ---------------------------------------
# `immediate_source_owner` is the operating company. The ownership file has one
# row per parent shareholder, so a facility appears several times; the immediate
# owner is constant across them.

message("[2/5] Reading ownership")

read_owners <- function(cfg, pkg_obj) {
  members <- ct_ownership_files(pkg_obj$path, cfg$subsectors)
  members <- members[!is.na(members)]
  if (length(members) == 0) return(NULL)

  ct_extract(pkg_obj$path, members,
             file.path(DIR_EXTRACT, cfg$gas, "ownership")) |>
    map(read_sector) |>
    list_rbind() |>
    group_by(source_id) |>
    summarise(operator_name = first(na.omit(immediate_source_owner)),
              .groups = "drop")
}

operators <- bind_rows(
  read_owners(CT_ASSET_CLASSES$industrial, industrial$pkg),
  read_owners(CT_ASSET_CLASSES$energy,     energy$pkg)
) |>
  distinct(source_id, .keep_all = TRUE)

if (nrow(operators) == 0) {
  warning("No ownership files found; operator_name will be NA throughout.")
  operators <- tibble(source_id = character(), operator_name = character())
}

message("      operator resolved for ", sum(!is.na(operators$operator_name)),
        " of ", nrow(facilities_base))


# =============================================================================
# 3. ASSIGN PROVINCE AND NUTS-2 REGION
# =============================================================================

message("[3/5] Assigning administrative geography")

ne <- ne_download_admin1(DIR_NE)

# `name` is deliberately dropped here — see the warning in _sources.R.
provinces_sf <- st_read(ne$shp, quiet = TRUE) |>
  filter(adm0_a3 == "TUR") |>
  select(iso_3166_2) |>
  st_transform(CRS_TARGET)

stopifnot("Expected 81 Turkish provinces from Natural Earth" =
            nrow(provinces_sf) == 81)

# Guard against a lon/lat swap before it becomes an invisible map bug.
stopifnot("Facility coordinates are missing" =
            !any(is.na(facilities_base$lat) | is.na(facilities_base$lon)))

facilities_sf <- facilities_base |>
  st_as_sf(coords = c("lon", "lat"), crs = CRS_TARGET, remove = FALSE)

# Point-in-polygon first. Coastal facilities can fall just outside a coarse
# polygon, so unmatched points are snapped to the nearest province afterwards
# with the distance recorded — never silently.
joined <- st_join(facilities_sf, provinces_sf, join = st_within)

n_unmatched <- sum(is.na(joined$iso_3166_2))

if (n_unmatched > 0) {
  message("      ", n_unmatched, " outside all polygons; snapping to nearest")
  idx_missing <- which(is.na(joined$iso_3166_2))
  nearest     <- st_nearest_feature(joined[idx_missing, ], provinces_sf)
  dist_m      <- st_distance(joined[idx_missing, ], provinces_sf[nearest, ],
                             by_element = TRUE) |> as.numeric()
  joined$iso_3166_2[idx_missing] <- provinces_sf$iso_3166_2[nearest]
  joined$snap_distance_m <- NA_real_
  joined$snap_distance_m[idx_missing] <- dist_m
} else {
  joined$snap_distance_m <- NA_real_
}

# Distance to the assigned province's boundary. Natural Earth's 10m geometry
# cannot adjudicate a facility sitting on a border, so proximity is measured and
# reported rather than glossed over.
province_borders <- st_cast(st_geometry(provinces_sf), "MULTILINESTRING")
border_idx       <- match(joined$iso_3166_2, provinces_sf$iso_3166_2)

joined$boundary_distance_m <- st_distance(
  st_geometry(joined), province_borders[border_idx], by_element = TRUE
) |> as.numeric()

# A facility snapped a few hundred metres from a coarse coastline is a geometry
# artefact. One snapped tens of kilometres is at sea — Türkiye's Black Sea gas
# production sits roughly 150 km offshore. They are different situations and
# conflating them would either hide the offshore assets or make every coastal
# port look like a data error.
OFFSHORE_THRESHOLD_M <- 10000

geocoded <- joined |>
  st_drop_geometry() |>
  left_join(provinces_ref, by = "iso_3166_2") |>
  mutate(
    geocode_quality = case_when(
      !is.na(snap_distance_m) &
        snap_distance_m >= OFFSHORE_THRESHOLD_M     ~ "offshore",
      !is.na(snap_distance_m)                       ~ "snapped_to_nearest",
      boundary_distance_m < BOUNDARY_PROXIMITY_M    ~ "boundary_proximate",
      TRUE                                          ~ "within_province"
    )
  )

stopifnot("Every facility must resolve to a province" =
            !any(is.na(geocoded$province_code)))

message("      ", sum(geocoded$geocode_quality == "within_province"), " clean, ",
        sum(geocoded$geocode_quality == "boundary_proximate"), " near a border, ",
        sum(geocoded$geocode_quality == "snapped_to_nearest"), " snapped")


# =============================================================================
# 4. ASSEMBLE THE SCHEMA
# =============================================================================
# Column set fixed by KARBON_ATLASI.md §6. Fields that v1 does not vary are still
# present, because adding them later would break every downstream layer.

message("[4/5] Assembling facilities table")

# --- GEM enrichment: commissioning year and captive status -------------------
# Climate TRACE begins at 2021 and carries no start year, so the fleet timeline
# depends on matching its facilities to GEM's. Matching is by proximity, and
# proximity is not identity — the match rate and the distance distribution are
# both reported so the join can be judged rather than trusted.
#
# Only combustion plants and coal mines are matched. GEM's renewables have no
# Climate TRACE counterpart by construction, which is the whole of finding E1.

gem_matched <- tibble(source_id = character(), commissioning_year = integer(),
                      commissioning_source = character(),
                      is_captive = logical(), captive_industry = character(),
                      gem_id = character(), gem_match_distance_m = numeric())

if (file.exists(GEM_COMMISSIONING)) {
  message("      joining GEM commissioning years")

  gem <- read_csv(GEM_COMMISSIONING, locale = locale(encoding = "UTF-8"),
                  show_col_types = FALSE, progress = FALSE) |>
    filter(!is.na(lat), !is.na(lon), !is.na(start_year))

  # The power and coal trackers cover the energy half. The steel and cement
  # trackers carry `Start date` for the industrial half, and without them
  # industrial commissioning coverage sits at 45% against 75% for energy — the
  # timeline would be lopsided for no reason other than which files were read.
  #
  # These are the same tables written for cross-validation. Using them for a
  # commissioning year does not make GEM a panel source: capacity and emissions
  # still come from Climate TRACE alone (scope decision 3). A date is not a
  # measurement of the thing being modelled.
  crosscheck_years <- list("steel", "cement") |>
    map(function(nm) {
      p <- file.path(DIR_PROCESSED, paste0("gem_crosscheck_", nm, ".csv"))
      if (!file.exists(p)) return(NULL)
      read_csv(p, locale = locale(encoding = "UTF-8"),
               show_col_types = FALSE, progress = FALSE) |>
        filter(!is.na(lat), !is.na(lon), !is.na(start_year)) |>
        transmute(location_id = NA_character_,
                  name        = as.character(name),
                  gem_id      = as.character(gem_id),
                  start_year  = as.integer(start_year),
                  is_captive  = FALSE,
                  captive_type = NA_character_,
                  lat, lon)
    }) |>
    compact() |>
    list_rbind()

  if (nrow(crosscheck_years) > 0) {
    message("      + ", nrow(crosscheck_years),
            " industrial sites from the steel and cement trackers")
    gem <- bind_rows(
      gem |> select(location_id, name, gem_id, start_year, is_captive,
                    captive_type, lat, lon),
      crosscheck_years)
  }

  # One row per GEM site: GIPT is unit-level, and a plant built in phases would
  # otherwise match several times. The earliest start year is the site's.
  gem_sites <- gem |>
    mutate(site_key = coalesce(location_id, name)) |>
    group_by(site_key) |>
    summarise(gem_id        = first(gem_id),
              start_year    = min(start_year, na.rm = TRUE),
              is_captive    = any(is_captive, na.rm = TRUE),
              captive_type  = first(na.omit(captive_type)),
              lat = first(lat), lon = first(lon),
              .groups = "drop")

  ct_pts  <- st_as_sf(geocoded, coords = c("lon", "lat"), crs = CRS_TARGET,
                      remove = FALSE)
  gem_pts <- st_as_sf(gem_sites, coords = c("lon", "lat"), crs = CRS_TARGET,
                      remove = FALSE)

  nearest <- st_nearest_feature(ct_pts, gem_pts)
  dist_m  <- st_distance(ct_pts, gem_pts[nearest, ], by_element = TRUE) |>
    as.numeric()

  gem_matched <- tibble(
    source_id            = geocoded$source_id,
    gem_id               = gem_sites$gem_id[nearest],
    gem_match_distance_m = dist_m,
    commissioning_year   = gem_sites$start_year[nearest],
    is_captive           = gem_sites$is_captive[nearest],
    captive_industry     = gem_sites$captive_type[nearest]
  ) |>
    # Beyond the radius the nearest GEM site is simply a different plant.
    # Carrying its year would be worse than carrying none.
    mutate(across(c(gem_id, commissioning_year, captive_industry),
                  ~ if_else(gem_match_distance_m <= GEM_MATCH_RADIUS_M, .x,
                            .x[NA_integer_])),
           is_captive = if_else(gem_match_distance_m <= GEM_MATCH_RADIUS_M,
                                is_captive, NA),
           commissioning_source = if_else(
             !is.na(commissioning_year),
             paste0("GEM (matched at ", round(gem_match_distance_m), " m)"),
             NA_character_))

  n_match <- sum(!is.na(gem_matched$commissioning_year))
  message("      matched ", n_match, " of ", nrow(geocoded),
          " (", round(100 * n_match / nrow(geocoded)), "%) within ",
          GEM_MATCH_RADIUS_M, " m")
} else {
  warning("GEM data not found at ", GEM_COMMISSIONING, ".\n",
          "commissioning_year will be NA for every facility and the 2000-2026 ",
          "fleet timeline cannot be drawn. Run scripts/01c_ingest_gem.R.",
          immediate. = TRUE)
}

facilities <- geocoded |>
  left_join(operators, by = "source_id") |>
  left_join(gem_matched, by = "source_id") |>
  transmute(
    # Prefixed with the source so a second register can never collide with
    # Climate TRACE ids.
    facility_id      = paste0("CT", source_id),

    # HONESTY NOTE: these are Climate TRACE's own labels, a mix of Turkish place
    # names and English descriptors ("Adıyaman Merkez Cement Plant"). They are
    # NOT verified Turkish facility names. Normalising them against a Turkish
    # register is future work; inventing names here would violate §8.1.
    facility_name_tr = source_name,

    operator_name,

    # The top-level split between the two populations. Everything in the UI that
    # filters, colours or aggregates keys on this first (§6).
    asset_class,
    sector,
    technology       = source_type,

    # Energy assets only; NA for industrial. Drives the fleet-composition view.
    fuel_type        = if_else(asset_class == "energy", source_type,
                               NA_character_),

    # Now live, not reserved. Industrial installations hold CBAM-relevant
    # embedded emissions; power stations set the grid intensity that produces
    # industrial indirect emissions without being CBAM-liable themselves; coal
    # mines and oil & gas sit outside both.
    liability_class  = unname(LIABILITY_BY_SUBSECTOR[sector]),

    # The field that makes the 2000-2026 timeline possible. Sourced from GEM,
    # NOT Climate TRACE, which starts at 2021. `commissioning_source` records
    # which register supplied it so a GEM-derived year is never mistaken for an
    # observation (§6).
    commissioning_year,
    commissioning_source,
    gem_id,
    gem_match_distance_m,

    # Declared by GEM rather than inferred from distance. A captive plant serves
    # an industrial host, so it is excluded from both sides of the grid emission
    # factor. See ROADMAP.md E5.
    is_captive,
    captive_industry,

    # The gas basis each figure is denominated in. Carried on every row because
    # the two are never summed and a total without a unit is meaningless.
    gas_basis,

    lat, lon,
    province_code,
    province_name_tr,
    nuts2_code,
    nuts2_name_tr,

    # Present from day one even though v1 is Türkiye and CBAM only. Retrofitting
    # them later would break every downstream layer; cost now is zero.
    country_iso3     = "TUR",
    regime_id        = "EU_CBAM",

    source           = "climate_trace",
    source_id        = as.character(source_id),
    source_release   = release_tag,
    geocode_quality
  ) |>
  arrange(asset_class, sector, province_code, facility_name_tr)

# =============================================================================
# 5. VALIDATE, THEN WRITE
# =============================================================================
# The gate runs BEFORE saveRDS. A structural failure — duplicate key, coordinate
# outside Türkiye, a province mapped to two NUTS-2 regions, mojibake in a name —
# stops the build and writes nothing, rather than leaving a plausible-looking
# but wrong artefact on disk for the app to read.
#
# Quality observations (border-proximate assignments, unresolved operators,
# facilities close enough together to be one site recorded twice) are reported
# and the build continues: those are properties of the data, not defects in the
# code. See scripts/_validate.R for why that distinction is enforced.

message("[5/5] Validating and writing outputs")

facilities <- gate_facilities(
  facilities,
  report = file.path(DIR_PROCESSED, "facilities_validation.html")
)

saveRDS(facilities, file.path(DIR_PROCESSED, "facilities.rds"))

# Diagnostics travel separately so the main table stays clean, but they are
# committed: a province assignment nobody can check is not evidence.
geocoded |>
  transmute(
    facility_id = paste0("CT", source_id),
    facility_name_tr = source_name,
    sector, lat, lon,
    province_code, province_name_tr, nuts2_code,
    boundary_distance_m = round(boundary_distance_m),
    snap_distance_m     = round(snap_distance_m),
    geocode_quality
  ) |>
  arrange(geocode_quality, boundary_distance_m) |>
  write_csv(file.path(DIR_PROCESSED, "facilities_geocode_report.csv"))


cat("\n", strrep("=", 72), "\n", sep = "")
cat("FACILITIES BUILT — ", nrow(facilities), " rows\n", sep = "")
cat(strrep("=", 72), "\n\n", sep = "")

# Records and sites are not the same number. Climate TRACE lists each oil and
# gas field twice, once under production and once under transport, at identical
# coordinates — different emission sources at one place. That is correct
# accounting and misleading cartography: six fields would draw as twelve dots.
# Reporting both counts keeps the difference visible instead of letting whichever
# number is quoted first become the claim.
n_sites <- nrow(distinct(facilities, lat, lon))
cat("Records: ", nrow(facilities), "   Distinct coordinates: ", n_sites,
    if (n_sites < nrow(facilities))
      paste0("   (", nrow(facilities) - n_sites,
             " records share a location with another)") else "",
    "\n\n", sep = "")

cat("By asset class:\n")
print(facilities |> count(asset_class, liability_class, name = "facilities"))

cat("\nBy sector:\n")
print(facilities |> count(sector, name = "facilities"))

cat("\nCommissioning year coverage — the fleet timeline depends on this:\n")
print(facilities |> group_by(asset_class) |>
        summarise(facilities = n(),
                  with_year  = sum(!is.na(commissioning_year)),
                  pct        = round(100 * mean(!is.na(commissioning_year))),
                  earliest   = suppressWarnings(min(commissioning_year, na.rm = TRUE)),
                  .groups = "drop") |> as.data.frame())

if (any(!is.na(facilities$is_captive) & facilities$is_captive)) {
  cat("\nCaptive generation, declared by GEM — excluded from the grid factor:\n")
  print(facilities |> filter(!is.na(is_captive), is_captive) |>
          count(captive_industry, sort = TRUE, name = "facilities") |>
          as.data.frame())
}

cat("\nGeocode quality:\n")
print(facilities |> count(geocode_quality, name = "facilities"))

cat("\nTop provinces:\n")
print(facilities |> count(province_name_tr, sort = TRUE, name = "facilities") |> head(10))

cat("\nNUTS-2 regions covered: ", n_distinct(facilities$nuts2_code),
    " of 26\n", sep = "")

cat("\nOperator resolved: ", sum(!is.na(facilities$operator_name)), " of ",
    nrow(facilities), "\n", sep = "")

cat("\nWritten:\n",
    "  ", file.path(DIR_PROCESSED, "facilities.rds"), "\n",
    "  ", file.path(DIR_PROCESSED, "facilities_geocode_report.csv"), "\n", sep = "")
