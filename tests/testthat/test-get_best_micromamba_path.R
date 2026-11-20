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

testthat::test_that("a pixi trampoline is resolved to the binary it starts", {
  home <- normalizePath(withr::local_tempdir(), winslash = "/")
  real <- file.path(home, "envs", "micromamba", "bin", "micromamba")
  dir.create(dirname(real), recursive = TRUE)
  writeLines("real", real)
  bin_dir <- file.path(home, "bin")
  config_dir <- file.path(bin_dir, "trampoline_configuration")
  dir.create(config_dir, recursive = TRUE)
  write_config <- function(name, exe) {
    jsonlite::write_json(
      list(exe = exe, path_diff = dirname(real), env = list(CONDA_SHLVL = "1")),
      file.path(config_dir, paste0(name, ".json")),
      auto_unbox = TRUE
    )
  }
  trampoline <- file.path(bin_dir, "micromamba")
  writeLines("trampoline", trampoline)
  # No configuration: the path is kept.
  testthat::expect_identical(resolve_pixi_trampoline(trampoline), trampoline)
  write_config("micromamba", real)
  testthat::expect_identical(resolve_pixi_trampoline(trampoline), real)
  # Windows: `micromamba.exe` reads `micromamba.json`, with any case.
  trampoline_exe <- file.path(bin_dir, "micromamba.EXE")
  writeLines("trampoline", trampoline_exe)
  testthat::expect_identical(
    resolve_pixi_trampoline(trampoline_exe, on_windows = TRUE),
    real
  )
  # Through a symbolic link from another directory, as pixi resolves it.
  if (isFALSE(is_windows())) {
    link_dir <- file.path(home, "elsewhere")
    dir.create(link_dir)
    link <- file.path(link_dir, "micromamba")
    file.symlink(trampoline, link)
    testthat::expect_identical(resolve_pixi_trampoline(link), real)
  }
  # An `exe` that is missing, a directory, the trampoline itself, relative
  # (here an existing file of the working directory), or no string, and a
  # file that is no JSON object: the path is kept.
  withr::local_dir(dirname(real))
  for (exe in list(
    file.path(home, "missing"),
    home,
    trampoline,
    basename(real),
    1L
  )) {
    write_config("micromamba", exe)
    testthat::expect_identical(
      resolve_pixi_trampoline(trampoline),
      trampoline,
      info = format(exe)
    )
  }
  writeLines("not json", file.path(config_dir, "micromamba.json"))
  testthat::expect_identical(resolve_pixi_trampoline(trampoline), trampoline)
  writeLines("[1, 2]", file.path(config_dir, "micromamba.json"))
  testthat::expect_identical(resolve_pixi_trampoline(trampoline), trampoline)
  # Not a file: kept as given.
  for (path in list(NULL, NA_character_, "", file.path(home, "none"), home)) {
    testthat::expect_identical(resolve_pixi_trampoline(path), path)
  }
})

testthat::test_that("discovery returns the binary of a trampoline, not the trampoline", {
  home <- normalizePath(withr::local_tempdir(), winslash = "/")
  real <- file.path(home, "envs", "micromamba", "bin", "micromamba")
  dir.create(dirname(real), recursive = TRUE)
  writeLines("real", real)
  bin_dir <- file.path(home, "bin")
  dir.create(file.path(bin_dir, "trampoline_configuration"), recursive = TRUE)
  trampoline <- file.path(bin_dir, "micromamba")
  writeLines("trampoline", trampoline)
  jsonlite::write_json(
    list(exe = real, env = list(CONDA_SHLVL = "1")),
    file.path(bin_dir, "trampoline_configuration", "micromamba.json"),
    auto_unbox = TRUE
  )
  checked <- new.env()
  checked$paths <- character(0L)
  testthat::local_mocked_bindings(
    is_umamba_version_available = function(path) {
      checked$paths <- c(checked$paths, as.character(path))
      TRUE
    }
  )
  for (source in c("option", "envvar")) {
    checked$paths <- character(0L)
    local({
      if (identical(source, "option")) {
        withr::local_options(condathis.micromamba_path = trampoline)
      } else {
        withr::local_options(condathis.micromamba_path = NULL)
        withr::local_envvar(CONDATHIS_MICROMAMBA_PATH = trampoline)
      }
      result <- get_best_micromamba_path()
      testthat::expect_identical(as.character(result), real, info = source)
      testthat::expect_identical(checked$paths, real, info = source)
    })
  }
})
