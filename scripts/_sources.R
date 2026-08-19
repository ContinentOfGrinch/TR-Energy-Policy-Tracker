# =============================================================================
# _sources.R — shared source-acquisition helpers
# -----------------------------------------------------------------------------
# NOT a numbered pipeline step. The underscore prefix marks this as a library
# sourced by other scripts rather than something run on its own. Approved as an
# explicit exception to the numbering convention in SKDM_TURKIYE.md §3, because
# `00_coverage_audit.R` and `01_fetch_climate_trace.R` both need to acquire the
# same archive and duplicated download logic would drift apart.
#
# Everything here is about PROVENANCE. A downloaded file that nobody can prove
# is the same file the results were computed from is not reproducible, so every
# acquisition records its URL, release tag, retrieval date, byte count and
# SHA-256 digest.
#
# Usage:
#   source(file.path("scripts", "_sources.R"))
# =============================================================================

suppressPackageStartupMessages({
  library(digest)
  library(stringr)
  library(purrr)
})


# --- Constants ---------------------------------------------------------------

# Climate TRACE publishes per-gas country packages under a `latest` alias. The
# alias is convenient but NOT stable: it silently advances when a new release
# lands. That is precisely why the release tag is extracted from the archive's
# own filenames and recorded — see ct_release_tag() below.
CT_DOWNLOAD_BASE <- "https://downloads.climatetrace.org/latest"

# Verified available for TUR: co2, co2e_100yr, co2e_20yr, n2o, ch4, bc, co.
# There is no `pfc` package, which is why aluminium PFC emissions cannot be
# covered — see ROADMAP.md.
CT_GASES_AVAILABLE <- c("co2", "co2e_100yr", "co2e_20yr", "n2o", "ch4", "bc", "co")


# --- URL and path construction ----------------------------------------------

ct_package_url <- function(gas, country) {
  sprintf("%s/country_packages/%s/%s.zip", CT_DOWNLOAD_BASE, gas, country)
}

ct_package_path <- function(dir, gas, country) {
  file.path(dir, sprintf("%s_%s.zip", country, gas))
}

ct_docs_url <- function(file = "about_the_data.pdf") {
  sprintf("%s/about_the_data/%s", CT_DOWNLOAD_BASE, file)
}


# --- Integrity ---------------------------------------------------------------

#' SHA-256 digest of a file.
#'
#' md5 would be shorter but is unsuitable for an integrity claim. This digest is
#' what lets a future reader confirm they hold the same bytes that produced the
#' committed results.
ct_sha256 <- function(path) {
  digest::digest(path, algo = "sha256", file = TRUE)
}


# --- Acquisition -------------------------------------------------------------

#' Download a Climate TRACE country package, skipping if already present.
#'
#' Returns a one-row provenance record. The record is the point of this
#' function — the file on disk is a side effect.
#'
#' @param force Re-download even when the file exists. Use when upstream has
#'   published a new release; the digest in the returned record will differ.
ct_download_package <- function(gas, country, dir, force = FALSE) {

  if (!gas %in% CT_GASES_AVAILABLE) {
    stop("Gas '", gas, "' is not published as a country package. Available: ",
         paste(CT_GASES_AVAILABLE, collapse = ", "),
         ". Do not substitute a different gas silently.")
  }

  dir.create(dir, recursive = TRUE, showWarnings = FALSE)

  url  <- ct_package_url(gas, country)
  path <- ct_package_path(dir, gas, country)

  if (file.exists(path) && !force) {
    message("      cached: ", path)
  } else {
    message("      downloading: ", url)
    # mode = "wb" is mandatory on Windows; the default text mode corrupts zips.
    download.file(url, destfile = path, mode = "wb", quiet = TRUE)
  }

  info <- file.info(path)

  list(
    source        = "Climate TRACE",
    gas           = gas,
    country       = country,
    url           = url,
    path          = path,
    bytes         = as.integer(info$size),
    sha256        = ct_sha256(path),
    # file.mtime for a cached file is when it was fetched, which is the fact we
    # want to record — not when this script happened to run.
    retrieved_at  = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
    licence       = "CC BY 4.0",
    attribution   = "Climate TRACE (climatetrace.org), licensed CC BY 4.0"
  )
}


#' Download an auxiliary documentation file from the package's docs directory.
#'
#' Kept separate from the data download because a failure here is not fatal:
#' documentation is valuable but the pipeline can proceed without it.
ct_download_doc <- function(file, dir) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  url  <- ct_docs_url(file)
  path <- file.path(dir, file)

  if (!file.exists(path)) {
    ok <- tryCatch({
      download.file(url, destfile = path, mode = "wb", quiet = TRUE)
      TRUE
    }, error = function(e) {
      warning("Could not fetch ", url, ": ", conditionMessage(e))
      FALSE
    })
    if (!ok) return(NULL)
  }

  list(url = url, path = path, sha256 = ct_sha256(path))
}


# --- Archive inspection ------------------------------------------------------

#' Locate the asset-level emissions CSV for each subsector inside the archive.
#'
#' Matches on pattern rather than a hardcoded filename, because the filenames
#' embed a release version (e.g. `_v5_9_0`) that changes upstream. A hardcoded
#' name would break silently on the next release; this raises instead.
ct_sector_files <- function(zip_path, subsectors) {
  index <- unzip(zip_path, list = TRUE)

  find_one <- function(subsector) {
    hits <- index$Name |>
      keep(~ str_detect(.x, fixed(paste0(subsector, "_emissions_sources_"))) &&
             str_ends(.x, ".csv") &&
             !str_detect(.x, "confidence|ownership"))
    if (length(hits) == 0) {
      stop("No emissions_sources file for subsector '", subsector,
           "' in ", zip_path,
           " — the package layout has changed and the pipeline must be updated.")
    }
    hits[[1]]
  }

  set_names(map_chr(subsectors, find_one), subsectors)
}


#' Extract the upstream release tag (e.g. "v5_9_0") from a member filename.
#'
#' The `latest` URL alias does not tell you which release you got. This does,
#' and it is the version that must be cited — not the REST API's v6, which is a
#' different artefact and may be a different release.
ct_release_tag <- function(member_names) {
  tag <- member_names |> str_extract("v\\d+_\\d+_\\d+") |> discard(is.na)
  if (length(tag) == 0) "unknown" else tag[[1]]
}


#' Extract selected members into a directory, returning their paths.
ct_extract <- function(zip_path, members, exdir) {
  dir.create(exdir, recursive = TRUE, showWarnings = FALSE)
  unzip(zip_path, files = unname(members), exdir = exdir, overwrite = TRUE)
  set_names(file.path(exdir, unname(members)), names(members))
}


#' Locate the ownership CSV for a subsector inside the archive.
#'
#' Separate from ct_sector_files() because ownership is an optional enrichment:
#' the pipeline still works without it, it just loses `operator_name`.
ct_ownership_files <- function(zip_path, subsectors) {
  index <- unzip(zip_path, list = TRUE)

  find_one <- function(subsector) {
    hits <- index$Name |>
      keep(~ str_detect(.x, fixed(paste0(subsector, "_emissions_sources_ownership_"))) &&
             str_ends(.x, ".csv"))
    if (length(hits) == 0) NA_character_ else hits[[1]]
  }

  set_names(map_chr(subsectors, find_one), subsectors)
}


# =============================================================================
# Natural Earth — administrative boundaries
# =============================================================================
# Used to assign each facility to a Turkish province from its coordinates.
#
# WHY NATURAL EARTH AND NOT geoBoundaries: geoBoundaries' Turkey ADM1 layer is
# CC BY-SA 2.0 (derived from OpenStreetMap). ShareAlike would propagate to this
# project's derived data, which is published CC BY 4.0, and would attach as soon
# as the polygons were redistributed for province-level choropleths — which the
# scope requires. Natural Earth is public domain, so both the lookup and the
# rendering are unencumbered. The trade is coarser geometry; see the
# border-proximity diagnostic in 02_build_facilities.R.
#
# WARNING: do NOT use this layer's `name` field. Natural Earth's Turkish
# province names are corrupted at source — "Kinkkale" for Kırıkkale,
# "Zinguldak" for Zonguldak, "K. Maras" for Kahramanmaraş, plus double-encoded
# mojibake that no ENCODING= option repairs. Key on `iso_3166_2` instead, which
# was verified against plate codes and is clean.

NE_ADM1_URL <- paste0("https://naciscdn.org/naturalearth/10m/cultural/",
                      "ne_10m_admin_1_states_provinces.zip")

#' Download and unpack the Natural Earth admin-1 layer.
#'
#' Returns a provenance record whose `shp` element is the path to the shapefile.
ne_download_admin1 <- function(dir, force = FALSE) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  zip_path <- file.path(dir, basename(NE_ADM1_URL))

  if (file.exists(zip_path) && !force) {
    message("      cached: ", zip_path)
  } else {
    message("      downloading: ", NE_ADM1_URL)
    download.file(NE_ADM1_URL, destfile = zip_path, mode = "wb", quiet = TRUE)
  }

  unzip(zip_path, exdir = dir, overwrite = TRUE)
  shp <- list.files(dir, pattern = "\\.shp$", full.names = TRUE)
  if (length(shp) == 0) stop("No .shp found after unpacking ", zip_path)

  info <- file.info(zip_path)

  list(
    source       = "Natural Earth",
    dataset      = "10m Admin 1 - States, Provinces",
    url          = NE_ADM1_URL,
    path         = zip_path,
    shp          = shp[[1]],
    bytes        = as.integer(info$size),
    sha256       = ct_sha256(zip_path),
    retrieved_at = format(info$mtime, "%Y-%m-%d %H:%M:%S"),
    licence      = "Public domain",
    attribution  = "Made with Natural Earth (naturalearthdata.com), public domain"
  )
}
