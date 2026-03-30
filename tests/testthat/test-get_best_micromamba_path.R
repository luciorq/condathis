testthat::test_that("getOption override takes highest priority", {
  withr::local_options(condathis.micromamba_path = "/mock/opt/micromamba")
  testthat::local_mocked_bindings(
    is_umamba_version_available = function(path) {
      identical(as.character(path), "/mock/opt/micromamba")
    }
  )
  result <- get_best_micromamba_path()
  testthat::expect_equal(as.character(result), "/mock/opt/micromamba")
})

testthat::test_that("CONDATHIS_MICROMAMBA_PATH env var works", {
  withr::local_envvar(CONDATHIS_MICROMAMBA_PATH = "/env-var/micromamba")
  testthat::local_mocked_bindings(
    is_umamba_version_available = function(path) {
      identical(as.character(path), "/env-var/micromamba")
    }
  )
  result <- get_best_micromamba_path()
  testthat::expect_equal(as.character(result), "/env-var/micromamba")
})

testthat::test_that("getOption takes priority over env var", {
  withr::local_options(condathis.micromamba_path = "/opt-path/micromamba")
  withr::local_envvar(CONDATHIS_MICROMAMBA_PATH = "/env-path/micromamba")
  testthat::local_mocked_bindings(
    is_umamba_version_available = function(path) {
      # Both paths are "valid", but the option should come first
      as.character(path) %in% c("/opt-path/micromamba", "/env-path/micromamba")
    }
  )
  result <- get_best_micromamba_path()
  # Should pick the option, not the env var (higher priority)
  testthat::expect_equal(as.character(result), "/opt-path/micromamba")
})

testthat::test_that("returns NULL when no valid path found", {
  withr::local_options(condathis.micromamba_path = NULL)
  withr::local_envvar(
    CONDATHIS_MICROMAMBA_PATH = NA,
    CONDA_PREFIX = NA
  )
  testthat::local_mocked_bindings(
    is_umamba_version_available = function(...) FALSE
  )
  result <- get_best_micromamba_path()
  testthat::expect_null(result)
})

testthat::test_that("no error when CONDA_PREFIX is unset", {
  withr::local_options(condathis.micromamba_path = NULL)
  withr::local_envvar(
    CONDATHIS_MICROMAMBA_PATH = NA,
    CONDA_PREFIX = NA
  )
  testthat::local_mocked_bindings(
    is_umamba_version_available = function(...) FALSE
  )
  # Should not error — the old "fake_path" sentinel is gone
  testthat::expect_no_error(get_best_micromamba_path())
})

testthat::test_that("internal path is checked when no user override", {
  withr::local_options(condathis.micromamba_path = NULL)
  withr::local_envvar(
    CONDATHIS_MICROMAMBA_PATH = NA,
    CONDA_PREFIX = NA
  )
  internal_path <- as.character(micromamba_bin_path())
  testthat::local_mocked_bindings(
    is_umamba_version_available = function(path) {
      identical(as.character(path), internal_path)
    }
  )
  result <- get_best_micromamba_path()
  testthat::expect_equal(as.character(result), internal_path)
})
