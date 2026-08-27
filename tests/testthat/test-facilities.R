# =============================================================================
# test-facilities.R — properties of data/processed/facilities.rds
# -----------------------------------------------------------------------------
# These began as an ad-hoc verification script run once by hand. Made permanent
# because the two worst bugs found in this project so far — a name-shadowing
# mutate() that tripled a denominator, and a project-root marker that silently
# broke the app after a rename — both produced correct-looking output and no
# error. Assertions are the only thing that catches that class of failure.
# =============================================================================

test_that("facilities.rds carries the full schema from KARBON_ATLASI.md section 6", {
  f <- read_processed("facilities.rds")

  required <- c("facility_id", "facility_name_tr", "operator_name",
                "sector", "technology", "liability_class",
                "lat", "lon", "province_code", "nuts2_code",
                "country_iso3", "regime_id", "source", "source_id",
                "geocode_quality")

  missing <- setdiff(required, names(f))
  expect_equal(missing, character(0),
               info = paste("missing columns:", paste(missing, collapse = ", ")))
})


test_that("facility keys are unique and complete", {
  f <- read_processed("facilities.rds")

  expect_false(any(duplicated(f$facility_id)))
  expect_false(any(duplicated(f$source_id)))
  expect_false(any(is.na(f$sector)))
  expect_false(any(is.na(f$province_code)))
  expect_false(any(is.na(f$facility_id)))
})


test_that("invariant columns hold their declared constants", {
  f <- read_processed("facilities.rds")

  expect_true(all(f$country_iso3 == "TUR"))
  expect_true(all(f$regime_id == "EU_CBAM"))
  # Once energy assets land, liability_class will also carry indirect_driver and
  # neutral. Until then every row is a CBAM-liable industrial installation.
  expect_true(all(f$liability_class %in% c("direct", "indirect_driver", "neutral")))
})


test_that("coordinates fall inside Türkiye — catches lon/lat inversion", {
  f <- read_processed("facilities.rds")

  expect_true(all(f$lat > TR_BBOX$lat[1] & f$lat < TR_BBOX$lat[2]),
              info = sprintf("lat range %.3f-%.3f", min(f$lat), max(f$lat)))
  expect_true(all(f$lon > TR_BBOX$lon[1] & f$lon < TR_BBOX$lon[2]),
              info = sprintf("lon range %.3f-%.3f", min(f$lon), max(f$lon)))
})


test_that("administrative codes are well formed", {
  f <- read_processed("facilities.rds")

  expect_true(all(f$province_code %in% 1:81))
  expect_true(all(str_detect(f$nuts2_code, NUTS2_PATTERN)))

  # A province must not map to two different İBBS-2 regions. This is the check
  # that would catch a corrupted reference table.
  mapping <- f |> distinct(province_code, nuts2_code)
  expect_equal(nrow(mapping), n_distinct(mapping$province_code))
})


test_that("province assignment matches publicly known facility locations", {
  f <- read_processed("facilities.rds")

  # Sixteen facilities whose location is unambiguous and publicly documented.
  # The two Ereğli entries are the point of this test: a name-based method would
  # confuse Karadeniz Ereğli (Zonguldak) with Marmara Ereğlisi (Tekirdağ).
  truth <- tibble::tribble(
    ~pattern,               ~province,
    "Isdemir Payas",        "Hatay",
    "Erdemir Eregli",       "Zonguldak",
    "Kaptan Ereglisi",      "Tekirdağ",
    "Habas Aliaga",         "İzmir",
    "İÇDAŞ Biga",           "Çanakkale",
    "Kardemir Merkez",      "Karabük",
    "Colakoglu",            "Kocaeli",
    "Kroman Steel Darica",  "Kocaeli",
    "Asil Celik Orhangazi", "Bursa",
    "Yesilyurt",            "Samsun",
    "Mescier",              "Bartın",
    "Seydisehir Eti",       "Konya",
    "Cerkezkoy Aluminum",   "Tekirdağ",
    "Doğubayazıt Cement",   "Ağrı",
    "Toscelik Toprakkale",  "Osmaniye",
    "Tosyali Toprakkale",   "Osmaniye"
  )

  for (i in seq_len(nrow(truth))) {
    hit <- f |> filter(str_detect(facility_name_tr, fixed(truth$pattern[i])))
    expect_equal(nrow(hit), 1L,
                 info = paste0("'", truth$pattern[i], "' matched ", nrow(hit),
                               " facilities, expected exactly 1"))
    if (nrow(hit) == 1L) {
      expect_equal(hit$province_name_tr, truth$province[i],
                   info = paste0(truth$pattern[i], " assigned to ",
                                 hit$province_name_tr))
    }
  }
})


test_that("geocode quality is declared for every facility and bounded", {
  f <- read_processed("facilities.rds")

  expect_true(all(f$geocode_quality %in%
                    c("within_province", "boundary_proximate", "snapped_to_nearest")))

  rep <- read_processed("facilities_geocode_report.csv")
  expect_equal(nrow(rep), nrow(f))

  # A facility snapped from further than 2 km offshore is not a coastline
  # artefact any more; it is a bad coordinate and must be investigated.
  snapped <- rep$snap_distance_m[!is.na(rep$snap_distance_m)]
  if (length(snapped) > 0) {
    expect_lt(max(snapped), 2000)
  }
})


test_that("Turkish characters survive the pipeline", {
  f <- read_processed("facilities.rds")

  # Encoding damage on Windows is silent and shows up as mojibake in the browser
  # rather than as an error, so it is asserted here.
  expect_true(any(str_detect(f$province_name_tr, "[çğıİöşüÇĞÖŞÜ]")))

  # Mojibake signatures. � is the Unicode replacement character; it is
  # written as an escape rather than pasted literally, because a raw U+FFFD in
  # source is itself the kind of encoding damage being tested for.
  expect_false(any(str_detect(f$province_name_tr, "Ã|Â|�")))
})
