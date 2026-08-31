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


# =============================================================================
# The panel gate
# =============================================================================
# Same principle, different failure mode. A corrupt facilities table usually
# looks wrong; a corrupt panel looks like a number. Each corruption below is one
# that would render without complaint on a chart.

#' A minimal but valid panel, used as the base for each corruption.
valid_panel <- function() {
  tibble::tibble(
    facility_id               = c("CT1", "CT1", "CT2", "CT2"),
    year                      = c(2023L, 2024L, 2023L, 2024L),
    status                    = "operating",
    gas_basis                 = "co2",
    emissions_reported_t      = c(1000, 1100, 2000, 2200),
    capacity_mw_or_capacity_t = c(500, 500, 800, 800),
    capacity_month_max        = c(500, 500, 800, 800),
    production_activity       = c(4000, 4400, 8000, 8800),
    co2_direct_t              = NA_real_,
    co2_indirect_t            = NA_real_,
    emission_intensity        = c(0.25, 0.25, 0.25, 0.25),
    eu_export_share           = NA_real_,
    months_covered            = 12L,
    value_type                = "observed",
    vintage                   = "v5_9_0",
    source                    = "climate_trace"
  )
}


test_that("a valid panel passes the gate", {
  expect_no_error(suppressMessages(gate_panel(valid_panel())))
})


test_that("panel gate STOPS on a duplicate facility-year", {
  # The key is the PAIR. A duplicate silently doubles that facility in every
  # aggregate, and the resulting total looks entirely plausible.
  bad <- valid_panel()
  bad$year[2] <- bad$year[1]

  expect_error(suppressMessages(gate_panel(bad)), "not unique")
})


test_that("panel gate STOPS when capacity was summed instead of averaged", {
  # The twelve-times trap, reproduced exactly. Nothing about 6000 MW is
  # malformed — it is the right shape, the right type and the wrong number.
  bad <- valid_panel()
  bad$capacity_mw_or_capacity_t <- bad$capacity_mw_or_capacity_t * 12

  expect_error(suppressMessages(gate_panel(bad)),
               "must be averaged, not summed")
})


test_that("panel gate STOPS on months_covered above twelve", {
  bad <- valid_panel()
  bad$months_covered[1] <- 13L

  expect_error(suppressMessages(gate_panel(bad)), "months_covered outside")
})


test_that("panel gate STOPS on a facility absent from the register", {
  bad <- valid_panel()
  facilities <- tibble::tibble(facility_id = "CT1")

  expect_error(
    suppressMessages(gate_panel(bad, facilities = facilities)),
    "absent from facilities.rds")
})


test_that("panel gate STOPS on negative emissions", {
  bad <- valid_panel()
  bad$emissions_reported_t[3] <- -50

  expect_error(suppressMessages(gate_panel(bad)), "negative values")
})


test_that("panel gate STOPS on a value_type outside the vocabulary", {
  bad <- valid_panel()
  bad$value_type[1] <- "estimated"   # plausible, and not one of the six

  expect_error(suppressMessages(gate_panel(bad)), "outside the allowed set")
})


test_that("panel gate WARNS but does not stop on a partial year", {
  # A partial year is a property of the upstream release, not a defect. It must
  # be visible and must not halt the build.
  warn <- valid_panel()
  warn$months_covered[c(2, 4)] <- 6L

  expect_no_error(suppressMessages(gate_panel(warn)))
  expect_message(gate_panel(warn), "partial")
})


test_that("panel gate WARNS when the two populations mix releases", {
  warn <- valid_panel()
  warn$vintage[3:4] <- "v5_10_0"

  expect_no_error(suppressMessages(gate_panel(warn)))
  expect_message(gate_panel(warn), "upstream releases")
})


test_that("panel gate WARNS on emissions before commissioning", {
  # GEM and Climate TRACE disagreeing is a finding, not a build failure. The
  # count must surface on every build so it cannot quietly become normal.
  warn <- valid_panel()
  warn$status[1] <- "pre_commissioning"

  expect_no_error(suppressMessages(gate_panel(warn)))
  expect_message(gate_panel(warn), "before their GEM")
})

