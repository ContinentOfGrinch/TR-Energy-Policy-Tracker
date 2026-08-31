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

  # Facilities whose location is unambiguous and publicly documented. The two
  # Ereğli entries are the point of this test: a name-based method would confuse
  # Karadeniz Ereğli (Zonguldak) with Marmara Ereğlisi (Tekirdağ).
  #
  # Patterns are matched within an asset class. Once the energy layer arrived,
  # bare name fragments started colliding — "Yesilyurt" and "Colakoglu" each
  # name both a steel plant and the captive power station beside it, which is
  # the co-location pattern recorded in ROADMAP E5, not an error.
  truth <- tibble::tribble(
    ~pattern,               ~province,     ~class,
    "Isdemir Payas",        "Hatay",       "industrial",
    "Erdemir Eregli",       "Zonguldak",   "industrial",
    "Kaptan Ereglisi",      "Tekirdağ",    "industrial",
    "Habas Aliaga steel",   "İzmir",       "industrial",
    "İÇDAŞ Biga steel",     "Çanakkale",   "industrial",
    "Kardemir Merkez",      "Karabük",     "industrial",
    "Colakoglu Metallurgical", "Kocaeli",  "industrial",
    "Kroman Steel Darica",  "Kocaeli",     "industrial",
    "Asil Celik Orhangazi", "Bursa",       "industrial",
    "Yesilyurt Iron",       "Samsun",      "industrial",
    "Mescier",              "Bartın",      "industrial",
    "Seydisehir Eti",       "Konya",       "industrial",
    "Cerkezkoy Aluminum",   "Tekirdağ",    "industrial",
    "Doğubayazıt Cement",   "Ağrı",        "industrial",
    "Toscelik Toprakkale",  "Osmaniye",    "industrial",
    "Tosyali Toprakkale",   "Osmaniye",    "industrial",
    # Energy assets, to prove the same machinery works on the second population.
    "Tupras Izmit Refinery", "Kocaeli",    "energy",
    "Tupras Batman",         "Batman",     "energy"
  )

  for (i in seq_len(nrow(truth))) {
    hit <- f |> filter(asset_class == truth$class[i],
                       str_detect(facility_name_tr, fixed(truth$pattern[i])))
    expect_equal(nrow(hit), 1L,
                 info = paste0("'", truth$pattern[i], "' matched ", nrow(hit),
                               " ", truth$class[i], " facilities, expected 1"))
    if (nrow(hit) == 1L) {
      expect_equal(hit$province_name_tr, truth$province[i],
                   info = paste0(truth$pattern[i], " assigned to ",
                                 hit$province_name_tr))
    }
  }
})


test_that("the two populations are distinguishable and correctly classified", {
  f <- read_processed("facilities.rds")

  expect_true(all(f$asset_class %in% c("industrial", "energy")))

  # liability_class is no longer reserved: it now carries the distinction the
  # grid factor and the CBAM calculation both depend on (§6).
  expect_true(all(f$liability_class[f$asset_class == "industrial"] == "direct"))
  expect_true(all(f$liability_class[f$asset_class == "energy"] %in%
                    c("indirect_driver", "neutral")))

  # Electricity generation drives grid intensity; mines and oil & gas sit
  # outside both the CBAM calculation and the grid factor.
  power <- f |> filter(sector == "electricity-generation")
  expect_true(all(power$liability_class == "indirect_driver"))
  expect_true(all(f$liability_class[grepl("coal-mining|oil-and-gas", f$sector)]
                  == "neutral"))

  # The two gas bases must stay separable, because they are never summed.
  expect_setequal(unique(f$gas_basis[f$asset_class == "industrial"]), "co2")
  expect_setequal(unique(f$gas_basis[f$asset_class == "energy"]), "co2e_100yr")

  # fuel_type belongs to energy assets only.
  expect_true(all(is.na(f$fuel_type[f$asset_class == "industrial"])))
})


test_that("geocode quality is declared for every facility and bounded", {
  f <- read_processed("facilities.rds")

  expect_true(all(f$geocode_quality %in% VALID_GEOCODE))

  rep <- read_processed("facilities_geocode_report.csv")
  expect_equal(nrow(rep), nrow(f))

  # A facility snapped a few hundred metres from a coarse coastline is a
  # geometry artefact; one snapped tens of kilometres is genuinely at sea. They
  # are checked separately, because a single threshold either rejects Türkiye's
  # Black Sea gas production or waves through a bad coordinate.
  onshore_snapped <- rep |>
    filter(!is.na(snap_distance_m), geocode_quality == "snapped_to_nearest")
  if (nrow(onshore_snapped) > 0) {
    expect_lt(max(onshore_snapped$snap_distance_m), 10000)
  }

  offshore <- rep |> filter(geocode_quality == "offshore")
  if (nrow(offshore) > 0) {
    # Offshore assets are assigned to the nearest coastal province, which is an
    # administrative convenience. The assertion is only that they are still in
    # Turkish waters rather than another country's.
    expect_lt(max(offshore$snap_distance_m, na.rm = TRUE), 400000)
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
