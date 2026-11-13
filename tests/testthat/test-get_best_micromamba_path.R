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
  # Should not error - the old "fake_path" sentinel is gone
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

testthat::test_that("a broken discovery candidate is skipped, not fatal", {
  # Regression test: only the "not executable" condition was caught, so a
  # candidate that was a directory, not executable, or printed no version
  # aborted discovery instead of falling through to the next candidate.
  tmp <- withr::local_tempdir()
  # A runnable program that prints no version: a batch file on Windows, a
  # shell script elsewhere.
  if (isTRUE(is_windows())) {
    no_version <- fs::path(tmp, "micromamba.bat")
    writeLines(c("@echo off", "echo no version here"), no_version)
  } else {
    no_version <- fs::path(tmp, "micromamba")
    writeLines(c("#!/bin/sh", "echo no version here"), no_version)
    fs::file_chmod(no_version, "u+x")
  }
  not_exec <- fs::path(tmp, "not-exec")
  writeLines("data", not_exec)
  for (candidate in c(tmp, not_exec, no_version)) {
    testthat::expect_false(
      is_umamba_version_available(candidate),
      info = candidate
    )
  }
  withr::local_options(condathis.micromamba_path = NULL)
  # Without the micromamba binaries of this machine: after the broken
  # candidate, discovery would run one that `CONDA_PREFIX` or `PATH` has,
  # also on CRAN.
  path_dirs <- strsplit(
    Sys.getenv("PATH"),
    .Platform$path.sep,
    fixed = TRUE
  )[[1L]]
  umamba_names <- paste0("micromamba", c("", ".exe", ".bat", ".cmd", ".com"))
  has_umamba <- vapply(
    path_dirs,
    function(dir) any(file.exists(file.path(dir, umamba_names))),
    logical(1L)
  )
  withr::local_envvar(
    CONDATHIS_MICROMAMBA_PATH = as.character(no_version),
    CONDA_PREFIX = NA,
    PATH = paste(path_dirs[!has_umamba], collapse = .Platform$path.sep)
  )
  testthat::expect_no_error(get_best_micromamba_path())
})
