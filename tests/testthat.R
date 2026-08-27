# =============================================================================
# tests/testthat.R — test runner
# -----------------------------------------------------------------------------
# Run from the project root:
#   Rscript tests/testthat.R
#
# These tests are DATA tests, not unit tests of pure functions. They assert
# properties of the built artefacts in data/processed/, because that is where
# this project's errors actually live: a silently wrong province assignment or a
# denominator inflated threefold by a name-shadowing bug will never be caught by
# testing a helper in isolation.
#
# Tests that depend on a built artefact SKIP rather than fail when it is absent,
# so a fresh clone that has not run the pipeline yet still gets a clean run.
# =============================================================================

library(testthat)

# The tests locate the project root themselves; see tests/testthat/helper-paths.R
test_dir(file.path("tests", "testthat"), reporter = "summary", stop_on_failure = TRUE)
