# =============================================================================
# test-validate-gates.R — do the gates actually stop a bad build?
# -----------------------------------------------------------------------------
# An untested gate is theatre. These tests deliberately corrupt a known-good
# table one property at a time and assert that gate_facilities() refuses it.
#
# Equally important: the WARN tier must NOT stop the build. A gate that halts on
# every data-quality observation gets switched off within a week, and then the
# structural checks go with it.
# =============================================================================

source(file.path(ROOT, "scripts", "_validate.R"))

#' A minimal but valid facilities table, used as the base for each corruption.
valid_facilities <- function(n = 3) {
  tibble::tibble(
    facility_id      = paste0("CT", seq_len(n)),
    facility_name_tr = paste("Tesis", seq_len(n)),
    operator_name    = paste("İşletmeci", seq_len(n)),
    sector           = "cement",
    technology       = "integrated dry",
    liability_class  = "direct",
    lat              = seq(37, 40, length.out = n),
    lon              = seq(28, 35, length.out = n),
    province_code    = c(1L, 6L, 34L)[seq_len(n)],
    province_name_tr = c("Adana", "Ankara", "İstanbul")[seq_len(n)],
    nuts2_code       = c("TR62", "TR51", "TR10")[seq_len(n)],
    country_iso3     = "TUR",
    regime_id        = "EU_CBAM",
    source           = "climate_trace",
    source_id        = as.character(seq_len(n)),
    geocode_quality  = "within_province"
  )
}


test_that("a valid table passes the gate", {
  expect_no_error(suppressMessages(gate_facilities(valid_facilities())))
})


test_that("gate STOPS on a duplicate facility_id", {
  bad <- valid_facilities()
  bad$facility_id[2] <- bad$facility_id[1]

  expect_error(suppressMessages(gate_facilities(bad)), "duplicate")
})


test_that("gate STOPS on a missing schema column", {
  bad <- valid_facilities() |> select(-nuts2_code)

  expect_error(suppressMessages(gate_facilities(bad)), "missing required columns")
})


test_that("gate STOPS on a coordinate outside Türkiye — the lon/lat swap guard", {
  bad <- valid_facilities()
  # Swap lon and lat on one row: 37N/28E becomes 28N/37E, which is in Saudi
  # Arabia. This is the error that stays invisible until the map is drawn.
  tmp <- bad$lat[1]; bad$lat[1] <- bad$lon[1]; bad$lon[1] <- tmp

  expect_error(suppressMessages(gate_facilities(bad)), "bounding box")
})


test_that("gate STOPS when a province maps to two NUTS-2 regions", {
  bad <- valid_facilities()
  bad <- bind_rows(bad, bad[1, ] |>
                     mutate(facility_id = "CT99", source_id = "99",
                            nuts2_code = "TR10"))

  expect_error(suppressMessages(gate_facilities(bad)),
               "more than one NUTS-2")
})


test_that("gate STOPS on mojibake in a province name", {
  bad <- valid_facilities()
  bad$province_name_tr[1] <- "Ãdana"

  expect_error(suppressMessages(gate_facilities(bad)), "mojibake")
})


test_that("gate STOPS on an out-of-set liability_class", {
  bad <- valid_facilities()
  bad$liability_class[1] <- "taxable"

  expect_error(suppressMessages(gate_facilities(bad)), "allowed set")
})


test_that("gate STOPS on NA in a required column", {
  bad <- valid_facilities()
  bad$province_code[2] <- NA_integer_

  expect_error(suppressMessages(gate_facilities(bad)), "NA values")
})


test_that("WARN tier does NOT stop the build", {
  # Border-proximate assignments, unresolved operators and near-coincident
  # facilities are properties of the data, not defects in the code. They must be
  # reported and survived — a gate that halts on these gets disabled.
  warnable <- valid_facilities()
  warnable$geocode_quality[1] <- "boundary_proximate"
  warnable$geocode_quality[2] <- "snapped_to_nearest"
  warnable$operator_name[3]   <- NA_character_

  expect_no_error(suppressMessages(gate_facilities(warnable)))
})


test_that("gate returns the table unchanged so it can be piped into saveRDS", {
  f <- valid_facilities()
  out <- suppressMessages(gate_facilities(f))
  expect_equal(out, f)
})


# =============================================================================
# The policy gate
# =============================================================================

test_that("the real policy files pass their schemas", {
  expect_no_error(suppressMessages(
    gate_policies(dir        = file.path(ROOT, "policies"),
                  schema_dir = file.path(ROOT, "policies", "_schema"))
  ))
})


test_that("a policy file with no schema is refused", {
  # Otherwise the way to bypass validation is simply to add a new file, which
  # defeats the gate entirely.
  tmp <- withr::local_tempdir()
  file.copy(file.path(ROOT, "policies", "cbam_phase_in.json"), tmp)
  writeLines('{"meta":{}}', file.path(tmp, "unschemad_parameters.json"))

  expect_error(
    suppressMessages(gate_policies(
      dir = tmp, schema_dir = file.path(ROOT, "policies", "_schema"))),
    "has no schema"
  )
})


test_that("a phase-in factor that reverses is refused", {
  # JSON Schema cannot express a relationship between array elements, so this
  # check lives in R. The obligation phases in; it never goes backwards.
  tmp <- withr::local_tempdir()
  j <- jsonlite::fromJSON(file.path(ROOT, "policies", "cbam_phase_in.json"),
                          simplifyVector = FALSE)
  j$phase_in[[3]]$cbam_factor          <- 0.01
  j$phase_in[[3]]$free_allocation_share <- 0.99
  jsonlite::write_json(j, file.path(tmp, "cbam_phase_in.json"),
                       auto_unbox = TRUE, pretty = TRUE)

  expect_error(
    suppressMessages(gate_policies(
      dir = tmp, schema_dir = file.path(ROOT, "policies", "_schema"))),
    "monotonic"
  )
})


test_that("a price scenario with neither source_url nor citation_required is refused", {
  # This is the section 7 rule the project already broke once.
  tmp <- withr::local_tempdir()
  j <- jsonlite::fromJSON(
    file.path(ROOT, "policies", "carbon_price_scenarios.json"),
    simplifyVector = FALSE)
  j$scenarios$low$citation_required <- FALSE
  j$scenarios$low$source_url        <- NULL
  jsonlite::write_json(j, file.path(tmp, "carbon_price_scenarios.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null")

  expect_error(
    suppressMessages(gate_policies(
      dir = tmp, schema_dir = file.path(ROOT, "policies", "_schema"))),
    "citation_required"
  )
})


test_that("a malformed retrieval date is refused by the schema", {
  tmp <- withr::local_tempdir()
  j <- jsonlite::fromJSON(file.path(ROOT, "policies", "tr_ets.json"),
                          simplifyVector = FALSE)
  j$meta$retrieved_date <- "19-08-2026"   # not ISO; reads fine, means nothing
  # null = "null" matters: jsonlite drops NULL entries by default, which would
  # silently remove first_compliance_period$free_allocation_share and change
  # what this test is testing.
  jsonlite::write_json(j, file.path(tmp, "tr_ets.json"),
                       auto_unbox = TRUE, pretty = TRUE, null = "null")

  expect_error(
    suppressMessages(gate_policies(
      dir = tmp, schema_dir = file.path(ROOT, "policies", "_schema"))),
    "tr_ets"
  )
})
