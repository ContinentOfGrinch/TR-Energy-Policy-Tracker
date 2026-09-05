# =============================================================================
# test-fleet-timeline.R — properties of the 2000–2026 development series
# -----------------------------------------------------------------------------
# A cumulative series has one failure mode that renders perfectly: it goes down.
# Nothing about a falling line is malformed, and on this chart it would read as
# plants closing — which is precisely the thing this data cannot express, since
# GEM records a retirement year for 2 of 4,174 Turkish rows.
#
# The other assertions guard the unit discipline. Three of the four groups are
# measured in incompatible units (tonnes of cement, tonnes of coal, barrels per
# day), and a megawatt appearing on one of them would be added to a real
# megawatt axis without complaint.
# =============================================================================

MW_GROUPS <- c("ct_combustion", "renewable")

test_that("the series is rectangular: every group has every year", {
  tl <- read_processed("fleet_timeline.csv")

  # A missing year breaks a line chart into segments, which a reader interprets
  # as missing data rather than as a year in which nothing was commissioned.
  per_group <- tl |> dplyr::count(group, name = "years")
  expect_equal(dplyr::n_distinct(per_group$years), 1)
  expect_equal(anyDuplicated(tl[c("group", "year")]), 0)

  yrs <- sort(unique(tl$year))
  expect_equal(yrs, seq(min(yrs), max(yrs)))
})


test_that("cumulative columns never decrease", {
  tl <- read_processed("fleet_timeline.csv")

  for (col in c("cum_mw", "cum_n")) {
    falls <- tl |>
      dplyr::filter(!is.na(.data[[col]])) |>
      dplyr::arrange(group, year) |>
      dplyr::group_by(group) |>
      dplyr::mutate(prev = dplyr::lag(.data[[col]])) |>
      dplyr::filter(!is.na(prev), .data[[col]] < prev) |>
      dplyr::ungroup()

    expect_equal(nrow(falls), 0,
                 info = paste(col, "falls at",
                              paste(falls$group, falls$year, collapse = "; ")))
  }
})


test_that("megawatts appear only for the groups measured in megawatts", {
  tl <- read_processed("fleet_timeline.csv")

  # Industrial capacity is tonnes of cement or steel; coal mines are tonnes per
  # annum; refineries are barrels per day. None of those can join a megawatt
  # axis, and a zero would read as "no capacity" rather than "not measured".
  leaked <- tl |>
    dplyr::filter(!group %in% MW_GROUPS,
                  !is.na(cum_mw) | !is.na(added_mw))
  expect_equal(nrow(leaked), 0)

  present <- tl |> dplyr::filter(group %in% MW_GROUPS)
  expect_true(all(!is.na(present$cum_mw)))
})


test_that("the cumulative total equals the sum of the annual additions", {
  tl <- read_processed("fleet_timeline.csv")

  # Recomputed independently of how the pipeline built it. If cumsum were ever
  # applied over an unsorted frame, this is what would catch it.
  recomputed <- tl |>
    dplyr::arrange(group, year) |>
    dplyr::group_by(group) |>
    dplyr::mutate(check_n = cumsum(added_n)) |>
    dplyr::ungroup()

  expect_equal(recomputed$cum_n, recomputed$check_n)
})


test_that("the undated count is constant across the axis", {
  tl <- read_processed("fleet_timeline.csv")

  # Undated facilities belong to no year, so their count must not move with the
  # slider. A varying figure would mean they had been silently assigned a year
  # somewhere, which §8.1 forbids.
  per_group <- tl |>
    dplyr::group_by(group) |>
    dplyr::summarise(distinct_values = dplyr::n_distinct(undated_n),
                     .groups = "drop")

  expect_true(all(per_group$distinct_values == 1))
})


test_that("the series accounts for every facility exactly once", {
  tl <- read_processed("fleet_timeline.csv")
  facilities <- read_processed("facilities.rds")

  last <- tl |> dplyr::filter(year == max(year))
  total <- sum(last$cum_n) + sum(last$undated_n)

  fleet_path <- file.path(PROCESSED, "fleet_renewables.rds")
  n_fleet <- if (file.exists(fleet_path)) nrow(readRDS(fleet_path)) else 0

  # Dated plus undated must equal the two registers combined. A facility lost
  # between them would quietly shrink the fleet; one counted twice would inflate
  # it, and neither shows on the chart.
  expect_equal(total, nrow(facilities) + n_fleet)
})


test_that("coverage is reported for every group and stays a proportion", {
  cv <- read_processed("fleet_timeline_coverage.csv")
  tl <- read_processed("fleet_timeline.csv")

  expect_setequal(cv$group, unique(tl$group))
  expect_true(all(cv$share >= 0 & cv$share <= 1))
  expect_equal(cv$n_dated + (cv$n_total - cv$n_dated), cv$n_total)

  # The asymmetry that forces the coverage band into the interface rather than
  # into a footnote. If a future data refresh ever closed this gap the band
  # could be reconsidered — this records why it exists.
  mw <- cv |> dplyr::filter(group %in% MW_GROUPS)
  expect_gt(diff(range(mw$share)), 0.15)
})


test_that("the atlas never claims more capacity than Ember reports installed", {
  tl <- read_processed("fleet_timeline.csv")
  skip_if(all(is.na(tl$ember_total_gw)), "Ember capacity not fetched")

  # Cumulative commissioning ignores retirement, so in principle it could exceed
  # actual installed capacity. Measured, it does not: incomplete coverage
  # dominates, and our curve sits below Ember's throughout. If that ever
  # reverses, the gap changes meaning entirely and the interface copy — which
  # currently says "how much of the real fleet this atlas sees" — becomes wrong.
  by_year <- tl |>
    dplyr::group_by(year) |>
    dplyr::summarise(ours_gw = sum(cum_mw, na.rm = TRUE) / 1000,
                     ember_gw = dplyr::first(ember_total_gw),
                     .groups = "drop") |>
    dplyr::filter(!is.na(ember_gw))

  expect_true(all(by_year$ours_gw <= by_year$ember_gw),
              info = paste("exceeds Ember in:",
                           paste(by_year$year[by_year$ours_gw > by_year$ember_gw],
                                 collapse = ", ")))
})
