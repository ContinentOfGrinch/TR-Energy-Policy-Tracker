# =============================================================================
# 04_build_fleet_timeline.R — the 2000–2026 fleet development series
# -----------------------------------------------------------------------------
# PURPOSE
#   Produce `data/processed/fleet_timeline.csv`: one row per year per group,
#   carrying cumulative commissioned capacity, cumulative plant count, and the
#   share of that group that could be dated at all.
#
#   This is analysis, not display formatting, so it belongs in the pipeline
#   rather than in `app/global.R`. The app reads only from data/processed/ and
#   never computes a pipeline step (KARBON_ATLASI.md §1 architecture). Putting
#   it here also means the gates and tests can see it.
#
# WHAT THIS SERIES IS, AND IS NOT
#   It is CUMULATIVE COMMISSIONING: everything ever built, up to and including
#   year Y. It is NOT the operating fleet, and it cannot be, because GEM records
#   a retirement year for 2 of 4,174 Turkish rows. A plant that closed in 2015
#   stays on this curve for ever.
#
#   Ember's actual installed capacity is carried alongside so the gap is visible.
#   Read that gap carefully: it is COVERAGE MINUS RETIREMENT and the two work in
#   opposite directions. Incomplete coverage pulls our curve down; unmodelled
#   retirement pushes it up. Measured, coverage dominates — our cumulative sits
#   BELOW Ember's installed capacity throughout — so the honest reading is "how
#   much of the real fleet this atlas can see", not "how much retired".
#
# PREREQUISITES
#   scripts/02_build_facilities.R   -> facilities.rds, fleet_renewables.rds
#   scripts/03_build_panel.R        -> facility_panel.rds  (for MW capacity)
#   scripts/01d_fetch_ember.R       -> ember_capacity_summary.csv  (optional)
#
# OUTPUTS
#   data/processed/fleet_timeline.csv
#   data/processed/fleet_timeline_coverage.csv
#
# RUN
#   Rscript scripts/04_build_fleet_timeline.R
# =============================================================================

options(encoding = "UTF-8")

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(readr)
  library(purrr)
})

source(file.path("scripts", "_validate.R"))

DIR_PROCESSED <- file.path("data", "processed")

# The window the timeline is drawn over. 2000 because that is where Ember's
# national series starts and where the policy story the project set out to tell
# begins; 2026 to meet the emissions panel at its own last year.
YEAR_FROM <- 2000
YEAR_TO   <- 2026

need <- function(f) {
  p <- file.path(DIR_PROCESSED, f)
  if (!file.exists(p)) {
    stop(f, " not found. Run the pipeline in order; see the header.",
         call. = FALSE)
  }
  p
}

facilities <- readRDS(need("facilities.rds"))
fleet      <- readRDS(need("fleet_renewables.rds"))
panel      <- readRDS(need("facility_panel.rds"))


# =============================================================================
# 1. CAPACITY FOR THE MODELLED POWER PLANTS
# =============================================================================
# Climate TRACE publishes capacity per facility-year, but only from 2021. A
# plant commissioned in 1975 has no 1975 capacity anywhere in this project, so
# its EARLIEST AVAILABLE figure is attributed to its commissioning year.
#
# That assumption is stated rather than hidden: every later expansion is written
# back to the first year, so early years are somewhat overstated and the curve
# is smoother than reality. It is the same assumption GEM forces on the
# renewable half, which carries a single current capacity per plant, so at least
# the two halves are wrong in the same direction.

message("[1/4] Attributing capacity to commissioning year")

ct_capacity <- panel |>
  filter(sector == "electricity-generation", !is.na(capacity_mw_or_capacity_t)) |>
  group_by(facility_id) |>
  slice_min(year, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(facility_id, mw = capacity_mw_or_capacity_t)

# --- Group 1: Climate TRACE combustion plants --------------------------------
ct_power <- facilities |>
  filter(sector == "electricity-generation") |>
  left_join(ct_capacity, by = "facility_id") |>
  transmute(group = "ct_combustion",
            year  = commissioning_year,
            mw,
            dated = !is.na(commissioning_year) & !is.na(mw))

# --- Group 2: the renewable fleet from GEM -----------------------------------
ren <- fleet |>
  transmute(group = "renewable",
            year  = commissioning_year,
            mw    = capacity_mw,
            dated = !is.na(commissioning_year) & !is.na(capacity_mw))

# --- Group 3: industrial installations ---------------------------------------
# Counted, never summed. Their capacity is in tonnes of product — tonnes of
# cement, tonnes of steel — which cannot be added to megawatts or to each other.
# `mw` is NA by construction so that any future attempt to sum this group
# produces NA rather than a number.
industrial <- facilities |>
  filter(asset_class == "industrial") |>
  transmute(group = "industrial",
            year  = commissioning_year,
            mw    = NA_real_,
            dated = !is.na(commissioning_year))

# --- Group 4: the rest of the energy assets ----------------------------------
# Coal mines and oil and gas. Also counted only: mines are measured in tonnes
# per annum and refineries in barrels per day.
energy_other <- facilities |>
  filter(asset_class == "energy", sector != "electricity-generation") |>
  transmute(group = "energy_other",
            year  = commissioning_year,
            mw    = NA_real_,
            dated = !is.na(commissioning_year))

all_units <- bind_rows(ct_power, ren, industrial, energy_other)


# =============================================================================
# 2. COVERAGE — WHAT SHARE OF EACH GROUP CAN BE DATED AT ALL
# =============================================================================
# The single most important number on the chart, and the reason the timeline
# needs a coverage band rather than a footnote. Combustion plants and renewables
# are datable at very different rates, so drawing their curves together without
# showing this would make the transition look sharper than the data supports.

message("[2/4] Measuring coverage")

coverage <- all_units |>
  group_by(group) |>
  summarise(
    n_total   = n(),
    n_dated   = sum(dated),
    share     = n_dated / n(),
    mw_dated  = sum(mw[dated], na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(mw_dated = if_else(group %in% c("ct_combustion", "renewable"),
                            mw_dated, NA_real_))

for (i in seq_len(nrow(coverage))) {
  message(sprintf("      %-14s %4d / %4d dated (%.0f%%)",
                  coverage$group[i], coverage$n_dated[i],
                  coverage$n_total[i], 100 * coverage$share[i]))
}

write_csv(coverage, file.path(DIR_PROCESSED, "fleet_timeline_coverage.csv"))


# =============================================================================
# 3. THE CUMULATIVE SERIES
# =============================================================================
# Cumulative, and every year in the window present even where nothing was
# commissioned — a missing row would break a line chart into segments and read
# as missing data rather than as a flat year.

message("[3/4] Building the cumulative series")

dated <- all_units |> filter(dated)

# Anything commissioned before the window still counts toward the cumulative
# total at YEAR_FROM; it is folded into the first year rather than dropped.
# 89 of the modelled facilities predate 2000, so dropping them would understate
# the starting fleet by more than a third.
dated <- dated |> mutate(year = pmax(year, YEAR_FROM))

grid <- expand_grid(group = unique(all_units$group),
                    year  = YEAR_FROM:YEAR_TO)

annual <- dated |>
  filter(year <= YEAR_TO) |>
  group_by(group, year) |>
  summarise(added_mw = sum(mw, na.rm = TRUE),
            added_n  = n(),
            .groups = "drop")

timeline <- grid |>
  left_join(annual, by = c("group", "year")) |>
  mutate(added_mw = coalesce(added_mw, 0),
         added_n  = coalesce(added_n, 0L)) |>
  arrange(group, year) |>
  group_by(group) |>
  mutate(cum_mw = cumsum(added_mw),
         cum_n  = cumsum(added_n)) |>
  ungroup() |>
  # Megawatts are meaningless for the counted-only groups and must never appear
  # as a zero, which would read as "no capacity" rather than "not measured here".
  mutate(across(c(added_mw, cum_mw),
                ~ if_else(group %in% c("ct_combustion", "renewable"),
                          .x, NA_real_)))

# Undated facilities, carried as their own row per year. They are constant
# across the axis by design: §6 requires a facility with no commissioning year
# to be visibly excluded rather than assumed to have always existed, and a flat
# line that never changes is exactly what "we do not know when this arrived"
# looks like.
undated_counts <- all_units |>
  filter(!dated) |>
  count(group, name = "undated_n")

timeline <- timeline |> left_join(undated_counts, by = "group") |>
  mutate(undated_n = coalesce(undated_n, 0L))


# =============================================================================
# 4. THE NATIONAL REFERENCE LINE
# =============================================================================
# Optional. Without it the timeline still works; with it, the reader can see how
# much of the real fleet this atlas accounts for.

message("[4/4] Joining the Ember reference")

ember_path <- file.path(DIR_PROCESSED, "ember_capacity_summary.csv")

if (file.exists(ember_path)) {
  ember <- read_csv(ember_path, show_col_types = FALSE, progress = FALSE) |>
    select(year, ember_total_gw = total_gw,
           ember_renewable_gw = renewable_gw, ember_fossil_gw = fossil_gw)

  timeline <- timeline |> left_join(ember, by = "year")
  message("      Ember capacity joined for ",
          sum(!is.na(unique(timeline$ember_total_gw))), " years")
} else {
  timeline <- timeline |>
    mutate(ember_total_gw = NA_real_, ember_renewable_gw = NA_real_,
           ember_fossil_gw = NA_real_)
  warning("ember_capacity_summary.csv not found — the timeline will carry no ",
          "national reference line. Run scripts/01d_fetch_ember.R.",
          immediate. = TRUE)
}

timeline <- gate_fleet_timeline(timeline, coverage)

write_csv(timeline, file.path(DIR_PROCESSED, "fleet_timeline.csv"))

message("\nWrote fleet_timeline.csv: ", nrow(timeline), " rows, ",
        YEAR_FROM, "-", YEAR_TO, ", ", n_distinct(timeline$group), " groups")

last <- timeline |> filter(year == YEAR_TO)
for (i in seq_len(nrow(last))) {
  message(sprintf("  %-14s %s  %d tesis (+%d tarihsiz)",
                  last$group[i],
                  if (is.na(last$cum_mw[i])) "        —"
                  else sprintf("%6.1f GW", last$cum_mw[i] / 1000),
                  last$cum_n[i], last$undated_n[i]))
}
