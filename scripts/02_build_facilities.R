# =============================================================================
# 02_build_facilities.R — build the time-invariant facility table
# -----------------------------------------------------------------------------
# PURPOSE
#   Produce `data/processed/facilities.rds`: one row per facility, carrying only
#   attributes that do not change over time. Anything that varies by year lives
#   in the panel (SKDM_TURKIYE.md §6) — putting capacity or status here would
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


# =============================================================================
# 1. CONFIGURATION
# =============================================================================

CT_GAS        <- "co2"
CT_COUNTRY    <- "TUR"
CT_SUBSECTORS <- c("iron-and-steel", "cement", "aluminum")

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

pkg            <- ct_download_package(CT_GAS, CT_COUNTRY, DIR_RAW)
sector_members <- ct_sector_files(pkg$path, CT_SUBSECTORS)
release_tag    <- ct_release_tag(sector_members)
sector_files   <- ct_extract(pkg$path, sector_members, DIR_EXTRACT)

read_sector <- function(path) {
  read_csv(path,
           locale    = locale(encoding = "UTF-8"),
           col_types = cols(.default = col_character(),
                            lat = col_double(), lon = col_double()),
           progress  = FALSE)
}

# Collapse the monthly records to one row per facility. `first()` is safe only
# for genuinely time-invariant fields — that is the entire point of this table.
# A field that varies within a facility would be silently truncated here, so the
# invariance is asserted rather than assumed, immediately below.
raw <- map(sector_files, read_sector) |> list_rbind()

varying <- raw |>
  group_by(source_id) |>
  summarise(across(c(source_name, source_type, subsector, lat, lon),
                   n_distinct),
            .groups = "drop") |>
  filter(if_any(-source_id, ~ .x > 1))

if (nrow(varying) > 0) {
  warning(nrow(varying), " facilities have time-varying values in fields ",
          "assumed invariant. Inspect before trusting facilities.rds.")
}

facilities_base <- raw |>
  group_by(source_id) |>
  summarise(
    source_name = first(source_name),
    source_type = first(source_type),
    sector      = first(subsector),
    lat         = first(lat),
    lon         = first(lon),
    .groups = "drop"
  )

message("      ", nrow(facilities_base), " facilities")


# --- Operator, from the ownership file ---------------------------------------
# `immediate_source_owner` is the operating company. The ownership file has one
# row per parent shareholder, so a facility appears several times; the immediate
# owner is constant across them.

message("[2/5] Reading ownership")

ownership_members <- ct_ownership_files(pkg$path, CT_SUBSECTORS)
ownership_members <- ownership_members[!is.na(ownership_members)]

operators <- if (length(ownership_members) > 0) {
  ct_extract(pkg$path, ownership_members, DIR_EXTRACT) |>
    map(read_sector) |>
    list_rbind() |>
    group_by(source_id) |>
    summarise(operator_name = first(na.omit(immediate_source_owner)),
              .groups = "drop")
} else {
  warning("No ownership files found; operator_name will be NA throughout.")
  tibble(source_id = character(), operator_name = character())
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

geocoded <- joined |>
  st_drop_geometry() |>
  left_join(provinces_ref, by = "iso_3166_2") |>
  mutate(
    geocode_quality = case_when(
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
# Column set fixed by SKDM_TURKIYE.md §6. Fields that v1 does not vary are still
# present, because adding them later would break every downstream layer.

message("[4/5] Assembling facilities table")

facilities <- geocoded |>
  left_join(operators, by = "source_id") |>
  transmute(
    # Prefixed with the source so a second register (v2 adds power assets) can
    # never collide with Climate TRACE ids.
    facility_id      = paste0("CT", source_id),

    # HONESTY NOTE: these are Climate TRACE's own labels, a mix of Turkish place
    # names and English descriptors ("Adıyaman Merkez Cement Plant"). They are
    # NOT verified Turkish facility names. Normalising them against a Turkish
    # register is future work; inventing names here would violate §8.1.
    facility_name_tr = source_name,

    operator_name,
    sector,
    technology       = source_type,

    # v1 is entirely direct-liability industry. The field exists from day one
    # because v2 adds power assets, which are `indirect_driver`.
    liability_class  = "direct",

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
  arrange(sector, province_code, facility_name_tr)

stopifnot(
  "facility_id must be unique" = !any(duplicated(facilities$facility_id)),
  "No facility may lack a sector" = !any(is.na(facilities$sector))
)


# =============================================================================
# 5. WRITE
# =============================================================================

message("[5/5] Writing outputs")

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

cat("By sector:\n")
print(facilities |> count(sector, name = "facilities"))

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
