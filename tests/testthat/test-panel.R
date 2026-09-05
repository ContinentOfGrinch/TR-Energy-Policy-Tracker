# =============================================================================
# test-panel.R — properties of the facility x year panel
# -----------------------------------------------------------------------------
# These are data tests, not unit tests, and the panel is where that choice pays
# off most. A panel defect does not raise: a capacity summed instead of averaged
# is exactly twelve times too large and still renders as a plausible megawatt
# figure on a plausible chart. The assertions below therefore recompute key
# quantities from the raw monthly files and compare, rather than checking that
# functions were called.
#
# Skips rather than fails when the pipeline has not been run, so a fresh clone
# is green before `03_build_panel.R` has ever executed.
# =============================================================================

test_that("the panel is one row per facility per year", {
  panel <- read_processed("facility_panel.rds")

  expect_gt(nrow(panel), 0)
  expect_equal(anyDuplicated(panel[c("facility_id", "year")]), 0)
  expect_false(any(is.na(panel$facility_id)))
  expect_false(any(is.na(panel$year)))
})


test_that("every panel facility exists in the facilities register", {
  panel      <- read_processed("facility_panel.rds")
  facilities <- read_processed("facilities.rds")

  # An orphan facility_id means the join dropped or invented rows. Every
  # downstream aggregate keys on this, so it must be exact in both directions.
  expect_setequal(unique(panel$facility_id), facilities$facility_id)
})


test_that("the panel carries the documented schema", {
  panel <- read_processed("facility_panel.rds")

  required <- c("facility_id", "year", "status", "gas_basis",
                "emissions_reported_t", "capacity_mw_or_capacity_t",
                "production_activity", "co2_direct_t", "co2_indirect_t",
                "emission_intensity", "eu_export_share", "months_covered",
                "value_type", "vintage", "source")

  expect_true(all(required %in% names(panel)),
              info = paste("missing:",
                           paste(setdiff(required, names(panel)),
                                 collapse = ", ")))
})


test_that("value_type and gas_basis stay inside their vocabularies", {
  panel <- read_processed("facility_panel.rds")

  # §6 fixes these vocabularies. A new value appearing means someone widened the
  # concept without widening the UI that has to render it differently.
  expect_true(all(panel$value_type %in%
                    c("observed", "legislated", "scenario", "projected",
                      "assumption", "diagnostic_not_for_use")))
  expect_true(all(panel$gas_basis %in% c("co2", "co2e_100yr")))
  expect_true(all(panel$status %in%
                    c("operating", "pre_commissioning", "planned",
                      "construction", "retired", "cancelled", NA)))
})


test_that("the two populations never share a gas basis", {
  panel <- read_processed("facility_panel.rds")

  # The central correctness rule of this project: industrial figures are CO2
  # because CBAM is a CO2 instrument, energy figures are CO2e because only 18%
  # of coal mining's footprint is CO2. If a row ever carried the wrong one, a
  # total spanning both would look summable.
  by_class <- panel |>
    dplyr::distinct(asset_class, gas_basis)

  expect_equal(nrow(by_class), 2)
  expect_equal(by_class$gas_basis[by_class$asset_class == "industrial"], "co2")
  expect_equal(by_class$gas_basis[by_class$asset_class == "energy"],
               "co2e_100yr")
})


test_that("no emissions, activity or capacity is negative", {
  panel <- read_processed("facility_panel.rds")

  # None of these subsectors can remove carbon or produce negative tonnes, so a
  # negative here is an aggregation defect, not a property of the world.
  for (col in c("emissions_reported_t", "production_activity",
                "capacity_mw_or_capacity_t")) {
    expect_false(any(panel[[col]] < 0, na.rm = TRUE),
                 info = paste("negative values in", col))
  }
})


test_that("months_covered is counted, not assumed, and never exceeds twelve", {
  panel <- read_processed("facility_panel.rds")

  expect_true(all(panel$months_covered >= 1))
  expect_true(all(panel$months_covered <= 12))

  # A complete year must actually be complete. If a year silently lost months,
  # its totals would be understated with nothing to show for it.
  complete_years <- panel |>
    dplyr::filter(year >= 2021, year <= 2024) |>
    dplyr::pull(months_covered) |>
    unique()

  expect_equal(complete_years, 12)
})


test_that("capacity was averaged over months, not summed", {
  panel <- read_processed("facility_panel.rds")

  # THE TWELVE-TIMES TEST. Capacity is a stock. The annual value is the mean of
  # the monthly values, so it can never exceed the largest single month. If the
  # aggregation is ever changed to sum(), a complete year jumps by roughly 12x
  # and this is what catches it — the gate checks the same property at build
  # time, and this checks it on the artefact.
  cmp <- panel |>
    dplyr::filter(!is.na(capacity_mw_or_capacity_t),
                  !is.na(capacity_month_max))

  skip_if(nrow(cmp) == 0, "no capacity values in the panel")

  expect_true(all(cmp$capacity_mw_or_capacity_t <=
                    cmp$capacity_month_max * 1.001))
})


test_that("annual emissions equal the sum of the monthly source records", {
  panel <- read_processed("facility_panel.rds")

  raw_path <- file.path(
    ROOT, "data", "raw", "climate_trace", "extracted", "co2",
    "DATA", "manufacturing", "cement_emissions_sources_v5_9_0.csv")
  skip_if_not(file.exists(raw_path), "raw cement file not extracted")

  # Recomputed from the upstream file rather than from anything the pipeline
  # produced. A test that reuses the pipeline's own aggregation would pass even
  # if that aggregation were wrong.
  raw <- read_csv(raw_path, locale = locale(encoding = "UTF-8"),
                  show_col_types = FALSE, progress = FALSE) |>
    dplyr::filter(iso3_country == "TUR") |>
    dplyr::mutate(
      year        = as.integer(format(as.Date(start_time), "%Y")),
      facility_id = paste0("CT", source_id)) |>
    dplyr::group_by(facility_id, year) |>
    dplyr::summarise(expected = sum(as.numeric(emissions_quantity)),
                     .groups = "drop")

  joined <- dplyr::inner_join(
    raw, panel |> dplyr::select(facility_id, year, emissions_reported_t),
    by = c("facility_id", "year"))

  expect_gt(nrow(joined), 100)
  expect_equal(joined$emissions_reported_t, joined$expected, tolerance = 1e-8)
})


test_that("intensity is recomputed from annual totals, not averaged", {
  panel <- read_processed("facility_panel.rds")

  # Averaging twelve monthly ratios weights a low-output month equally with a
  # high-output one, which for a seasonal industry biases the result
  # systematically rather than randomly. The panel must satisfy the identity
  # intensity = emissions / activity exactly.
  cmp <- panel |>
    dplyr::filter(!is.na(emission_intensity), production_activity > 0)

  skip_if(nrow(cmp) == 0, "no rows with an intensity")

  expect_equal(cmp$emission_intensity,
               cmp$emissions_reported_t / cmp$production_activity,
               tolerance = 1e-9)

  # And it must be absent wherever there is nothing to divide by, rather than
  # carrying a zero or an Inf that would average into a sector figure.
  none <- panel |>
    dplyr::filter(is.na(production_activity) | production_activity == 0)
  expect_true(all(is.na(none$emission_intensity)))
})


test_that("columns reserved for author decisions are NA, not guessed", {
  panel <- read_processed("facility_panel.rds")

  # These await B1 (the direct/indirect decomposition) and B7 (eu_export_share).
  # Filling them by inference would be exactly the fabrication §8.1 forbids, and
  # the failure would be invisible: a plausible number in a documented column.
  # When B1 lands this test is expected to be updated deliberately, not to start
  # failing silently.
  expect_true(all(is.na(panel$co2_direct_t)))
  expect_true(all(is.na(panel$co2_indirect_t)))
  expect_true(all(is.na(panel$eu_export_share)))
})


test_that("a year exists that is both observed and complete", {
  panel <- read_processed("facility_panel.rds")

  # The app opens the time slider on the most recent year that is BOTH observed
  # and twelve months long, so that a first-time reader never meets a projection
  # or a partial year as though it were a year (§5). If a future data refresh
  # left no such year, `max()` over an empty set would give -Inf and the slider
  # would open somewhere meaningless. This asserts the property the default
  # depends on rather than the default itself.
  complete <- panel |>
    dplyr::group_by(year) |>
    dplyr::summarise(all_full = all(months_covered == 12),
                     any_obs  = any(value_type == "observed"),
                     .groups = "drop") |>
    dplyr::filter(all_full, any_obs)

  expect_gt(nrow(complete), 0)
})


test_that("observed and projected years do not interleave", {
  panel <- read_processed("facility_panel.rds")

  # The series is drawn as a solid segment then a dashed one, joined at the last
  # observed year. That rendering assumes the observed years form an unbroken
  # block at the start. An observed year appearing after a projected one would
  # draw a line that silently misrepresents which points are which.
  yrs <- panel |>
    dplyr::distinct(year, value_type) |>
    dplyr::arrange(year)

  obs <- yrs$year[yrs$value_type == "observed"]
  prj <- yrs$year[yrs$value_type == "projected"]

  if (length(obs) > 0 && length(prj) > 0) {
    expect_lt(max(obs), min(prj))
  }
})


test_that("vintage records the upstream release for every row", {
  panel <- read_processed("facility_panel.rds")

  # A release tag is not decoration here. The same Turkish fleet carries 12%
  # more generation in v5_10_0 than in v5_9_0, so a figure without its release
  # is not reproducible. Every row must name its own.
  expect_false(any(is.na(panel$vintage)))
  expect_true(all(grepl("^v[0-9]+_[0-9]+_[0-9]+$", panel$vintage)))
})
