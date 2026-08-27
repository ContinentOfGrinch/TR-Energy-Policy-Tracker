# =============================================================================
# _validate.R — data quality gates for the pipeline
# -----------------------------------------------------------------------------
# NOT a numbered pipeline step. Approved as the second exception to the
# numbering convention in KARBON_ATLASI.md §3, alongside `_sources.R`.
# Acquisition and validation are different jobs and belong in different files.
#
# WHY GATES AND NOT ONLY TESTS
#   `tests/` asserts properties of artefacts AFTER they are written. That is
#   useful but late: a bad `facilities.rds` still lands on disk, still gets read
#   by the app, and is only caught if someone remembers to run the suite. These
#   gates run INSIDE the pipeline, before `saveRDS()`, so a build that violates
#   a hard rule produces no artefact at all.
#
# TIERING — the important design decision
#   Not every problem should stop a build.
#
#   STOP   structural impossibilities. A duplicate key, a coordinate outside
#          Türkiye, a missing schema column. These mean the code is wrong, and
#          writing the file would propagate a silent error downstream.
#
#   WARN   data-quality observations. A facility 129 m from a province border,
#          an operator name that could not be resolved. These are properties of
#          the world, not bugs. They must be visible and recorded — never
#          silently swallowed, never fatal.
#
#   The distinction matters because a gate that stops on everything gets
#   disabled within a week, and a gate that warns on everything is ignored.
#
# Usage:
#   source(file.path("scripts", "_validate.R"))
#   gate_facilities(facilities)      # stops on structural failure
# =============================================================================

suppressPackageStartupMessages({
  library(pointblank)
  library(dplyr)
  library(stringr)
})


# --- Constants ---------------------------------------------------------------

# Padded bounding box for Türkiye. Its job is catching a lon/lat swap, which
# produces coordinates in the Indian Ocean and is invisible until the map draws.
TR_LON <- c(25.5, 45.5)
TR_LAT <- c(35.5, 42.5)

VALID_ASSET_CLASS     <- c("industrial", "energy")
VALID_LIABILITY_CLASS <- c("direct", "indirect_driver", "neutral")
VALID_GEOCODE_QUALITY <- c("within_province", "boundary_proximate",
                           "snapped_to_nearest")

# Boundary distance below which a province assignment is reported as uncertain.
# A judgement call, not a standard — recorded here so it is visible and tunable
# in one place rather than buried in a script.
BOUNDARY_WARN_M <- 2000


# --- Reporting ---------------------------------------------------------------

.gate_header <- function(label) {
  message("\n", strrep("-", 68))
  message("GATE: ", label)
  message(strrep("-", 68))
}

#' Stop the build, printing every structural failure rather than only the first.
#'
#' Reporting all of them at once matters: fixing one, re-running a five-minute
#' pipeline, and discovering the next is how a validation layer becomes hated.
.gate_stop <- function(failures, label) {
  if (length(failures) == 0) return(invisible(TRUE))
  stop("\n", strrep("!", 68), "\n",
       "GATE FAILED: ", label, "\n",
       paste0("  - ", failures, collapse = "\n"), "\n",
       strrep("!", 68),
       "\nNo artefact was written. Fix the pipeline, do not relax the gate.",
       call. = FALSE)
}

.gate_warn <- function(observations, label) {
  if (length(observations) == 0) {
    message("  (no quality observations)")
    return(invisible(TRUE))
  }
  for (o in observations) message("  WARN  ", o)
  invisible(TRUE)
}


# --- Generic checks ----------------------------------------------------------

#' Assert that a data frame carries every required column.
require_columns <- function(df, required, what = "table") {
  missing <- setdiff(required, names(df))
  if (length(missing) > 0) {
    sprintf("%s is missing required columns: %s",
            what, paste(missing, collapse = ", "))
  } else character(0)
}

#' Assert a column has no NA.
require_complete <- function(df, cols) {
  cols |>
    purrr::keep(~ .x %in% names(df) && any(is.na(df[[.x]]))) |>
    purrr::map_chr(~ sprintf("column `%s` contains %d NA values",
                             .x, sum(is.na(df[[.x]]))))
}

#' Assert a column is unique.
require_unique <- function(df, cols) {
  cols |>
    purrr::keep(~ .x %in% names(df) && any(duplicated(df[[.x]]))) |>
    purrr::map_chr(~ sprintf("column `%s` has %d duplicate values",
                             .x, sum(duplicated(df[[.x]]))))
}

#' Assert a column's values are drawn from a closed set.
require_in_set <- function(df, col, allowed) {
  if (!col %in% names(df)) return(character(0))
  bad <- setdiff(unique(df[[col]]), c(allowed, NA))
  if (length(bad) > 0) {
    sprintf("column `%s` contains values outside the allowed set: %s",
            col, paste(bad, collapse = ", "))
  } else character(0)
}


# --- The facilities gate -----------------------------------------------------

#' Validate a facilities table before it is written.
#'
#' Returns the table invisibly so it can be used inline:
#'   facilities |> gate_facilities() |> saveRDS(path)
#'
#' @param df       the assembled facilities table
#' @param report   optional path; writes a pointblank agent report as HTML
gate_facilities <- function(df, report = NULL) {

  .gate_header(sprintf("facilities (%d rows)", nrow(df)))

  # ---- STOP tier: structural impossibilities -------------------------------
  required <- c("facility_id", "facility_name_tr", "sector", "technology",
                "liability_class", "lat", "lon", "province_code",
                "nuts2_code", "country_iso3", "regime_id",
                "source", "source_id", "geocode_quality")

  failures <- c(
    require_columns(df, required, "facilities"),
    require_unique(df, c("facility_id", "source_id")),
    require_complete(df, c("facility_id", "sector", "lat", "lon",
                           "province_code", "nuts2_code")),
    require_in_set(df, "liability_class", VALID_LIABILITY_CLASS),
    require_in_set(df, "geocode_quality", VALID_GEOCODE_QUALITY),
    require_in_set(df, "country_iso3", "TUR")
  )

  if ("asset_class" %in% names(df)) {
    failures <- c(failures, require_in_set(df, "asset_class", VALID_ASSET_CLASS))
  }

  # Geography. A lon/lat inversion is the single most consequential silent error
  # available here, so it is checked explicitly rather than trusted.
  if (all(c("lat", "lon") %in% names(df))) {
    out_lat <- sum(df$lat < TR_LAT[1] | df$lat > TR_LAT[2], na.rm = TRUE)
    out_lon <- sum(df$lon < TR_LON[1] | df$lon > TR_LON[2], na.rm = TRUE)
    if (out_lat > 0 || out_lon > 0) {
      failures <- c(failures, sprintf(
        paste("%d facilities fall outside Türkiye's bounding box",
              "(%d by latitude, %d by longitude) — check for a lon/lat swap"),
        max(out_lat, out_lon), out_lat, out_lon))
    }
  }

  if ("province_code" %in% names(df)) {
    bad <- setdiff(unique(df$province_code), 1:81)
    if (length(bad) > 0) {
      failures <- c(failures, sprintf("province_code outside 1..81: %s",
                                      paste(bad, collapse = ", ")))
    }
  }

  # A province mapping to two different İBBS-2 regions means the reference table
  # is corrupted, and every regional aggregate downstream would be wrong.
  if (all(c("province_code", "nuts2_code") %in% names(df))) {
    dup <- df |>
      distinct(province_code, nuts2_code) |>
      count(province_code) |>
      filter(n > 1)
    if (nrow(dup) > 0) {
      failures <- c(failures, sprintf(
        "province(s) mapped to more than one NUTS-2 region: %s",
        paste(dup$province_code, collapse = ", ")))
    }
  }

  # Encoding damage is silent on Windows and surfaces as mojibake in the browser.
  if ("province_name_tr" %in% names(df)) {
    mojibake <- df |> filter(str_detect(province_name_tr, "Ã|Â|�"))
    if (nrow(mojibake) > 0) {
      failures <- c(failures, sprintf(
        "%d province names show mojibake — the file was read or written with the wrong encoding",
        nrow(mojibake)))
    }
  }

  .gate_stop(failures, "facilities")
  message("  STOP tier: passed (", length(required), " columns, ",
          nrow(df), " rows)")

  # ---- WARN tier: observations about the world, not the code ---------------
  observations <- character(0)

  if ("geocode_quality" %in% names(df)) {
    q <- table(factor(df$geocode_quality, levels = VALID_GEOCODE_QUALITY))
    if (q[["boundary_proximate"]] > 0) {
      observations <- c(observations, sprintf(
        "%d facilities lie within %d m of a province border — assignment uncertain",
        q[["boundary_proximate"]], BOUNDARY_WARN_M))
    }
    if (q[["snapped_to_nearest"]] > 0) {
      observations <- c(observations, sprintf(
        "%d facilities fell outside every polygon and were snapped to the nearest province",
        q[["snapped_to_nearest"]]))
    }
  }

  if ("operator_name" %in% names(df)) {
    n_na <- sum(is.na(df$operator_name))
    if (n_na > 0) {
      observations <- c(observations,
                        sprintf("%d facilities have no resolved operator", n_na))
    }
  }

  # Facilities closer together than this are plausibly one site recorded twice —
  # exactly the open question standing over the two Kars cement records.
  if (all(c("lat", "lon") %in% names(df)) && nrow(df) > 1 &&
      requireNamespace("sf", quietly = TRUE)) {
    pts <- sf::st_as_sf(df, coords = c("lon", "lat"), crs = 4326)
    d <- sf::st_distance(pts); units(d) <- NULL; diag(d) <- Inf
    near <- which(d < 500, arr.ind = TRUE)
    near <- near[near[, 1] < near[, 2], , drop = FALSE]
    if (nrow(near) > 0) {
      for (i in seq_len(nrow(near))) {
        observations <- c(observations, sprintf(
          "possible duplicate site: %s and %s are %.0f m apart",
          df$facility_name_tr[near[i, 1]], df$facility_name_tr[near[i, 2]],
          d[near[i, 1], near[i, 2]]))
      }
    }
  }

  .gate_warn(observations, "facilities")

  # ---- Optional pointblank report ------------------------------------------
  # The gates above are the enforcement. pointblank adds a shareable HTML
  # artefact for the record, which is useful evidence for METHODOLOGY but is not
  # what stops a bad build.
  if (!is.null(report)) {
    agent <- create_agent(tbl = df, tbl_name = "facilities",
                          label = "Facility table validation") |>
      col_exists(all_of(required)) |>
      rows_distinct(vars(facility_id)) |>
      col_vals_between(vars(lat), TR_LAT[1], TR_LAT[2]) |>
      col_vals_between(vars(lon), TR_LON[1], TR_LON[2]) |>
      col_vals_between(vars(province_code), 1, 81) |>
      col_vals_in_set(vars(liability_class), VALID_LIABILITY_CLASS) |>
      col_vals_in_set(vars(geocode_quality), VALID_GEOCODE_QUALITY) |>
      col_vals_not_null(vars(facility_id, sector, lat, lon)) |>
      interrogate()

    export_report(agent, filename = report, quiet = TRUE)
    message("  pointblank report: ", report)
  }

  invisible(df)
}
