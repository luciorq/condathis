# Regression tests for the system tar rule.
#
# extract_tar_bz2() ran `TAR` as given whenever it was not empty, while
# has_system_tar() could return TRUE only because `tar` was on PATH. With
# `TAR=internal`, or a `TAR` that named no program, the fallback ran a
# program named "internal" (or the broken value), which failed, so the
# system tar never ran when R's internal tar failed. Both now use
# system_tar_program().
#
# `PATH` lookups are replaced with find_program(), because on Windows
# `Sys.which()` also searches the system directories, so `PATH` alone
# cannot control the result.

fake_path_tar <- "/fake/path/bin/tar"

local_fake_path_programs <- function(
  programs = c(tar = fake_path_tar, gtar = "/fake/path/bin/gtar"),
  .local_envir = parent.frame()
) {
  testthat::local_mocked_bindings(
    find_program = function(name) {
      if (isTRUE(name %in% names(programs))) {
        return(unname(programs[[name]]))
      }
      return("")
    },
    .env = .local_envir
  )
  return(invisible(NULL))
}

# R's own front end: an executable that exists on every platform.
rscript_path <- function() {
  exe <- if (isTRUE(is_windows())) "Rscript.exe" else "Rscript"
  return(as.character(fs::path(R.home("bin"), exe)))
}

testthat::test_that("is_executable() accepts an executable file", {
  # Regression test: file.access() names its result after the path, so
  # identical() with a bare 0L was always FALSE, and no TAR path was ever
  # accepted.
  testthat::expect_true(is_executable(rscript_path()))
  testthat::expect_false(is_executable(""))
  testthat::expect_false(
    is_executable(fs::path(withr::local_tempdir(), "missing"))
  )
})

testthat::test_that("system_tar_program() uses tar on PATH when TAR is unset or empty", {
  local_fake_path_programs()
  withr::local_envvar(TAR = NA)
  testthat::expect_identical(system_tar_program(), fake_path_tar)
  withr::local_envvar(TAR = "")
  testthat::expect_identical(system_tar_program(), fake_path_tar)
})

testthat::test_that("system_tar_program() skips TAR=internal", {
  local_fake_path_programs()
  withr::local_envvar(TAR = "internal")
  testthat::expect_identical(system_tar_program(), fake_path_tar)
})

testthat::test_that("system_tar_program() looks up a program name in TAR on PATH", {
  local_fake_path_programs()
  withr::local_envvar(TAR = "tar")
  testthat::expect_identical(system_tar_program(), fake_path_tar)
  withr::local_envvar(TAR = "gtar")
  testthat::expect_identical(system_tar_program(), "/fake/path/bin/gtar")
  # A name that is not on PATH falls back to tar.
  withr::local_envvar(TAR = "no-such-tar-program")
  testthat::expect_identical(system_tar_program(), fake_path_tar)
})

testthat::test_that("system_tar_program() uses an executable path in TAR", {
  local_fake_path_programs()
  exe <- rscript_path()
  withr::local_envvar(TAR = exe)
  testthat::expect_identical(
    system_tar_program(),
    as.character(fs::path_abs(exe))
  )

  # A relative path becomes absolute: extract_tar_bz2() runs tar in the
  # extraction directory.
  withr::local_dir(fs::path_dir(exe))
  rel_exe <- paste0("./", basename(exe))
  withr::local_envvar(TAR = rel_exe)
  tar_program <- system_tar_program()
  testthat::expect_true(fs::is_absolute_path(tar_program))
  testthat::expect_identical(tar_program, as.character(fs::path_abs(rel_exe)))
})

testthat::test_that("system_tar_program() uses the real tar given as an absolute path", {
  testthat::skip_on_cran()
  real_tar <- unname(Sys.which("tar"))
  # Linux, macOS and Windows 10 or later ship tar.
  testthat::expect_true(nzchar(real_tar))
  withr::local_envvar(TAR = real_tar)
  testthat::expect_identical(
    system_tar_program(),
    as.character(fs::path_abs(real_tar))
  )
  testthat::expect_true(has_system_tar())
})

testthat::test_that("system_tar_program() skips a TAR path that is missing or not executable", {
  local_fake_path_programs()
  missing_path <- fs::path(withr::local_tempdir(), "missing", "tar")
  withr::local_envvar(TAR = missing_path)
  testthat::expect_identical(system_tar_program(), fake_path_tar)

  # Neither Unix (no execute bit) nor Windows (no program extension) runs a
  # new text file.
  text_file <- withr::local_tempfile(fileext = ".txt")
  writeLines("not a program", text_file)
  withr::local_envvar(TAR = text_file)
  testthat::expect_identical(system_tar_program(), fake_path_tar)
})

testthat::test_that("system_tar_program() returns NULL when no tar is found", {
  local_fake_path_programs(programs = character(0L))
  for (tar_value in list(NA, "", "internal", "tar", "/missing/tar")) {
    withr::local_envvar(TAR = tar_value)
    testthat::expect_null(system_tar_program())
    testthat::expect_false(has_system_tar())
  }
})

testthat::test_that("has_system_tar() agrees with system_tar_program()", {
  missing_path <- fs::path(withr::local_tempdir(), "missing", "tar")
  tar_values <- list(NA, "", "internal", "tar", rscript_path(), missing_path)
  for (programs in list(c(tar = fake_path_tar), character(0L))) {
    local_fake_path_programs(programs = programs)
    for (tar_value in tar_values) {
      withr::local_envvar(TAR = tar_value)
      testthat::expect_identical(
        has_system_tar(),
        isFALSE(is.null(system_tar_program())),
        label = paste("TAR =", tar_value)
      )
    }
  }
  # And with the real PATH lookup.
  testthat::local_mocked_bindings(find_program = function(name) {
    return(unname(Sys.which(name)))
  })
  for (tar_value in tar_values) {
    withr::local_envvar(TAR = tar_value)
    testthat::expect_identical(
      has_system_tar(),
      isFALSE(is.null(system_tar_program()))
    )
  }
})

testthat::test_that("extract_tar_bz2() falls back to the tar that system_tar_program() finds", {
  local_fake_path_programs()
  archive <- withr::local_tempfile(fileext = ".tar.bz2")
  writeLines("not read: tar is mocked", archive)
  commands <- character(0L)
  testthat::local_mocked_bindings(
    untar = function(...) 1L,
    .package = "utils"
  )
  testthat::local_mocked_bindings(
    run = function(command, ...) {
      commands <<- c(commands, command)
      return(list(status = 0L))
    },
    .package = "processx"
  )

  missing_path <- fs::path(withr::local_tempdir(), "missing", "tar")
  for (tar_value in list(NA, "internal", "tar", missing_path)) {
    withr::local_envvar(TAR = tar_value)
    commands <- character(0L)
    testthat::expect_true(
      extract_tar_bz2(archive, withr::local_tempdir()),
      label = paste("TAR =", tar_value)
    )
    # The program that has_system_tar() reports, never "internal" or the
    # broken path.
    testthat::expect_identical(commands, fake_path_tar)
  }

  exe <- rscript_path()
  withr::local_envvar(TAR = exe)
  commands <- character(0L)
  testthat::expect_true(extract_tar_bz2(archive, withr::local_tempdir()))
  testthat::expect_identical(commands, as.character(fs::path_abs(exe)))
})

testthat::test_that("extract_tar_bz2() has no system tar fallback when no tar is found", {
  local_fake_path_programs(programs = character(0L))
  archive <- withr::local_tempfile(fileext = ".tar.bz2")
  writeLines("not an archive", archive)
  # extract_tar_bz2() turns errors into FALSE, so count the calls instead.
  run_calls <- 0L
  testthat::local_mocked_bindings(
    run = function(...) {
      run_calls <<- run_calls + 1L
      return(list(status = 0L))
    },
    .package = "processx"
  )
  withr::local_envvar(TAR = "internal")
  exdir <- fs::path(withr::local_tempdir(), "extract")
  testthat::expect_false(extract_tar_bz2(archive, exdir))
  testthat::expect_identical(run_calls, 0L)
  testthat::expect_false(fs::dir_exists(exdir))
})
