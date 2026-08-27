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


# =============================================================================
# The policy parameter gate
# =============================================================================
# Policy files are hand-edited, and hand-edited JSON drifts. A renamed field, a
# date typed as 19-08-2026, a scope_status quietly changed to something the
# fetch script does not recognise — none of these raise an error at read time.
# They produce NULL, and NULL propagates into a figure.
#
# Two layers, because they catch different things:
#   1. JSON Schema, in policies/_schema/, validates STRUCTURE.
#   2. R checks below validate RELATIONSHIPS between elements, which JSON Schema
#      cannot express — monotonicity of the phase-in, the factor and free
#      allocation summing to one, a scenario having either a source or an
#      admission that it needs one.

POLICY_SCHEMA_DIR <- file.path("policies", "_schema")

#' Read a file as a single UTF-8 string.
#'
#' Explicit about encoding because these files carry Turkish characters and the
#' Windows default is not UTF-8 (§2). Returning one string rather than a path
#' also keeps jsonvalidate from having to guess what it was handed.
.read_utf8 <- function(path) {
  raw <- readBin(path, "raw", file.info(path)$size)
  s <- rawToChar(raw)
  Encoding(s) <- "UTF-8"
  s
}

#' Escape every non-ASCII character as a \uXXXX JSON escape.
#'
#' WHY THIS EXISTS. jsonvalidate runs ajv inside V8, and handing V8 a string
#' containing raw UTF-8 Turkish characters fails intermittently on Windows with
#' `SyntaxError: Invalid or unexpected token` — a message that names neither the
#' file nor the field. It reproduced under `testthat` and not outside it, which
#' makes it an encoding-handoff problem somewhere in the R → V8 boundary rather
#' than a defect in the documents.
#'
#' `\uXXXX` escaping is part of the JSON specification, so the escaped text is
#' the same document by any conforming parser. Escaping removes the ambiguity
#' instead of depending on every layer agreeing about encoding.
#'
#' Handles the Basic Multilingual Plane, which covers all Turkish characters.
#' Anything above U+FFFF would need surrogate pairs; if such a character ever
#' appears in a policy file this must be extended rather than silently mangling.
.ascii_escape <- function(s) {
  cp <- utf8ToInt(s)
  if (all(cp < 128L)) return(s)

  if (any(cp > 0xFFFFL)) {
    stop("Policy JSON contains a character above U+FFFF; .ascii_escape() ",
         "handles the BMP only and must be extended before this can be validated.",
         call. = FALSE)
  }

  out <- ifelse(cp < 128L, intToUtf8(cp, multiple = TRUE),
                sprintf("\\u%04x", cp))
  paste(out, collapse = "")
}

#' Validate every policy file against its schema and its internal relationships.
#'
#' @param dir       directory holding the policy JSON files
#' @param schema_dir directory holding `<name>.schema.json`
gate_policies <- function(dir = "policies", schema_dir = POLICY_SCHEMA_DIR) {

  files <- list.files(dir, pattern = "\\.json$", full.names = TRUE)

  .gate_header(sprintf("policies (%d files)", length(files)))

  if (length(files) == 0) {
    stop("No policy files found in ", dir, call. = FALSE)
  }

  failures <- character(0)

  for (f in files) {
    nm     <- tools::file_path_sans_ext(basename(f))
    schema <- file.path(schema_dir, paste0(nm, ".schema.json"))

    # An unschema'd policy file is itself a failure. Otherwise the way to bypass
    # validation is simply to add a new file, which defeats the gate entirely.
    if (!file.exists(schema)) {
      failures <- c(failures, sprintf(
        "%s has no schema at %s — every policy file must be schema-backed",
        basename(f), schema))
      next
    }

    # Read both sides as explicit UTF-8 strings rather than handing jsonvalidate
    # a path. jsonvalidate decides whether an argument is a filename or a JSON
    # literal, and on Windows that guess interacts badly with backslash paths
    # and with the Turkish characters inside these files — the symptom is a V8
    # "SyntaxError: Invalid or unexpected token" that says nothing about which
    # file or which field. Passing strings removes the guess.
    ok <- jsonvalidate::json_validate(
      json    = .ascii_escape(.read_utf8(f)),
      schema  = .ascii_escape(.read_utf8(schema)),
      engine  = "ajv",
      verbose = TRUE
    )
    if (!ok) {
      errs <- attr(ok, "errors")
      detail <- if (is.data.frame(errs) && nrow(errs) > 0) {
        paste0(errs$instancePath, " ", errs$message, collapse = "; ")
      } else "schema validation failed"
      failures <- c(failures, sprintf("%s: %s", basename(f), detail))
    }
  }

  # --- Relationship checks JSON Schema cannot express ------------------------

  phase_in_path <- file.path(dir, "cbam_phase_in.json")
  if (file.exists(phase_in_path)) {
    p <- jsonlite::fromJSON(phase_in_path)$phase_in

    if (!all(abs(p$cbam_factor + p$free_allocation_share - 1) < 1e-9)) {
      failures <- c(failures,
        "cbam_phase_in.json: cbam_factor and free_allocation_share must sum to 1")
    }
    if (!all(diff(p$cbam_factor) > 0)) {
      failures <- c(failures,
        "cbam_phase_in.json: cbam_factor must increase monotonically — the obligation phases in, it never reverses")
    }
    if (!isTRUE(p$cbam_factor[p$year == 2034] == 1)) {
      failures <- c(failures,
        "cbam_phase_in.json: full application in 2034 is the legislated endpoint and must equal 1")
    }
  }

  prices_path <- file.path(dir, "carbon_price_scenarios.json")
  if (file.exists(prices_path)) {
    j <- jsonlite::fromJSON(prices_path, simplifyVector = FALSE)
    for (nm in names(j$scenarios)) {
      s <- j$scenarios[[nm]]
      has_source <- !is.null(s$source_url) && nzchar(s$source_url)
      admits_gap <- isTRUE(s$citation_required)
      user_set   <- identical(nm, "custom")
      if (!(has_source || admits_gap || user_set)) {
        failures <- c(failures, sprintf(
          "carbon_price_scenarios.json: scenario '%s' has neither a source_url nor citation_required — section 7 forbids an uncited regulatory number",
          nm))
      }
    }
  }

  .gate_stop(failures, "policies")
  message("  STOP tier: passed (", length(files), " files, all schema-backed)")

  # --- WARN tier -------------------------------------------------------------
  observations <- character(0)

  if (file.exists(prices_path)) {
    j <- jsonlite::fromJSON(prices_path, simplifyVector = FALSE)
    needy <- names(j$scenarios)[vapply(j$scenarios,
                                       function(s) isTRUE(s$citation_required),
                                       logical(1))]
    if (length(needy) > 0) {
      observations <- c(observations, sprintf(
        "scenario(s) still awaiting a citation: %s", paste(needy, collapse = ", ")))
    }
  }

  codes_path <- file.path(dir, "cbam_goods_cn_codes.json")
  if (file.exists(codes_path)) {
    st <- jsonlite::fromJSON(codes_path, simplifyVector = FALSE)$meta$scope_status
    if (!identical(st, "annex_i_verified")) {
      observations <- c(observations,
        "cbam_goods_cn_codes.json is still PROVISIONAL_AGGREGATE — derived shares are upper bounds")
    }
  }

  .gate_warn(observations, "policies")
  invisible(TRUE)
}
