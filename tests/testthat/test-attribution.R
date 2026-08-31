# =============================================================================
# test-attribution.R — licence conditions are conditions, not courtesies
# -----------------------------------------------------------------------------
# Climate TRACE and GEM both publish under CC BY 4.0. Attribution is a term of
# that licence, so redistributing derived data without it is a breach, not an
# oversight. These tests exist because "remember to credit GEM" is exactly the
# kind of obligation that survives a conversation and not a codebase.
#
# Each test skips when the artefact it guards has not been produced yet, so a
# fresh clone stays green before the pipeline has run.
# =============================================================================

test_that("Climate TRACE attribution travels with the processed data", {
  path <- file.path(PROCESSED, "SOURCES.md")
  skip_if_not(file.exists(path), "SOURCES.md not generated yet")

  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  expect_match(txt, "Climate TRACE", fixed = TRUE)
  expect_match(txt, "CC BY 4.0", fixed = TRUE)
  # The release tag is what makes a figure checkable years later.
  expect_match(txt, "v\\d+_\\d+_\\d+")
  expect_match(txt, "SHA-256", fixed = TRUE)
})


test_that("GEM attribution exists whenever GEM data has been ingested", {
  gem_data <- file.path(PROCESSED, "gem_commissioning.csv")
  skip_if_not(file.exists(gem_data), "GEM not ingested yet")

  path <- file.path(PROCESSED, "SOURCES_GEM.md")

  # If GEM data is in data/processed/ then its attribution must be too. This is
  # the assertion that turns a licence obligation into a build failure.
  expect_true(file.exists(path),
              info = paste("gem_commissioning.csv exists but SOURCES_GEM.md",
                           "does not — re-run scripts/01c_ingest_gem.R"))

  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  # CC BY 4.0 §3(1)(a): creator, licence notice, URI, warranty disclaimer.
  expect_match(txt, "Global Energy Monitor", fixed = TRUE)
  expect_match(txt, "CC BY 4.0", fixed = TRUE)
  expect_match(txt, "creativecommons.org/licenses/by/4.0", fixed = TRUE)
  expect_match(txt, "without warranties", fixed = TRUE)

  # §3(1)(a)(ii): the clause requiring a statement THAT the material was
  # modified. This project filters, renames, joins and derives, so the statement
  # is not optional.
  expect_match(txt, "Modifications", ignore.case = TRUE)

  # §2(5)(c): no implied endorsement.
  expect_match(txt, "does not endorse", fixed = TRUE)

  # §4: the tracker is a database, so Sui Generis Database Rights attach to the
  # derived table.
  expect_match(txt, "Database rights", ignore.case = TRUE)
})


test_that("derived-data licence is compatible with every upstream licence", {
  path <- file.path(ROOT, "README.md")
  skip_if_not(file.exists(path), "README.md missing")

  txt <- paste(readLines(path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

  # The chain is CC BY 4.0 (Climate TRACE) + CC BY 4.0 (GEM) + public domain
  # (Natural Earth) -> CC BY 4.0 derived. No ShareAlike anywhere, which is why
  # geoBoundaries was rejected for boundaries; see ROADMAP.md.
  expect_match(txt, "CC BY 4.0", fixed = TRUE)
  expect_false(grepl("CC BY-SA", txt, fixed = TRUE),
               label = "README must not claim a ShareAlike upstream")
})
