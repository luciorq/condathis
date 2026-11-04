# packages_solve_native() and micromamba_native_platform(): what the
# emulation fallbacks of define_platform() ask, on Apple Silicon and with
# the win-arm64 micromamba.

# A fake `native_cmd()` that records its call and returns `stdout`.
local_fake_solve <- function(stdout, status = 0L, envir = parent.frame()) {
  record <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    native_cmd = function(
      conda_cmd,
      conda_args = NULL,
      ...,
      verbose = NULL,
      error = "cancel"
    ) {
      record$conda_cmd <- conda_cmd
      record$conda_args <- conda_args
      record$dots <- c(...)
      record$error <- error
      if (isTRUE("-p" %in% conda_args)) {
        record$prefix <- conda_args[[which(conda_args == "-p") + 1L]]
        record$prefix_existed <- fs::file_exists(record$prefix)
      }
      return(list(status = status, stdout = stdout, stderr = ""))
    },
    .env = envir
  )
  return(record)
}

testthat::test_that("packages_solve_native() solves the whole request in a dry run", {
  record <- local_fake_solve(stdout = "{\"success\": true}")
  testthat::expect_true(packages_solve_native(
    c("r-base", "zlib"),
    channels = "conda-forge",
    channel_priority = "strict",
    additional_channels = "bioconda",
    platform = "win-arm64"
  ))
  testthat::expect_identical(record$conda_cmd, "create")
  testthat::expect_identical(record$dots, c("r-base", "zlib"))
  testthat::expect_true(all(
    c("--dry-run", "--json", "--yes", "--override-channels") %in%
      record$conda_args
  ))
  i <- which(record$conda_args == "--platform")
  testthat::expect_length(i, 1L)
  testthat::expect_identical(record$conda_args[[i + 1L]], "win-arm64")
  channels <- record$conda_args[which(record$conda_args == "-c") + 1L]
  testthat::expect_identical(channels, c("conda-forge", "bioconda"))
  # A non-zero status is an answer, not an error.
  testthat::expect_identical(record$error, "continue")
  # Into a new prefix, never an environment: `micromamba create` deletes an
  # existing prefix first. Its temporary directory is gone afterwards.
  testthat::expect_false(record$prefix_existed)
  testthat::expect_false(fs::dir_exists(fs::path_dir(record$prefix)))

  record <- local_fake_solve(stdout = "{}")
  testthat::expect_true(packages_solve_native(
    c("-f", "env.yml"),
    platform = "win-64"
  ))
  testthat::expect_identical(record$dots, c("-f", "env.yml"))
})

testthat::test_that("packages_solve_native() tells a request that does not solve from other failures", {
  # The JSON of micromamba 2.10.0 and 2.8.1 for a request that does not
  # solve.
  local_fake_solve(
    stdout = "{\"solver_problems\": [\"unsupported request\"], \"success\": false}",
    status = 1L
  )
  testthat::expect_false(packages_solve_native("pkg", platform = "win-arm64"))

  # A missing channel or no network: only `log_history` (2.10.0), or no
  # JSON at all (2.8.1).
  for (stdout in c(
    "{\"log_history\": [{\"level\": \"critical\"}]}",
    "",
    "not json",
    "[1]"
  )) {
    local_fake_solve(stdout = stdout, status = 1L)
    testthat::expect_identical(
      packages_solve_native("pkg", platform = "win-arm64"),
      NA,
      info = stdout
    )
  }
})

testthat::test_that("packages_solve_native() reads the answers of the real micromamba", {
  # The local `noarch` channel needs no network. It has no win-arm64
  # directory, which micromamba accepts as an empty one.
  skip_if_no_micromamba_offline()
  condathis::with_sandbox_dir({
    channel <- polyglot_channel()
    testthat::expect_true(packages_solve_native(
      "polyglot",
      channels = channel,
      platform = "win-arm64"
    ))
    for (spec in c("polyglot>=99", "no-such-package")) {
      testthat::expect_false(
        packages_solve_native(spec, channels = channel, platform = "win-arm64"),
        info = spec
      )
    }
    testthat::expect_identical(
      packages_solve_native(
        "polyglot",
        channels = paste0(channel, "-missing"),
        platform = "win-arm64"
      ),
      NA
    )

    env_file <- fs::path(withr::local_tempdir(), "polyglot-env.yml")
    writeLines(c("dependencies:", "  - polyglot"), env_file)
    testthat::expect_true(packages_solve_native(
      c("-f", env_file),
      channels = channel,
      platform = "win-arm64"
    ))
  })
})

testthat::test_that("packages_solve_native() fails a noarch spec whose dependency has no build", {
  # The reason for a solve instead of a search per spec: `r-ggplot2` is
  # `noarch`, so a search finds it for win-arm64, but `r-base` has no
  # win-arm64 build.
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    testthat::expect_false(packages_solve_native(
      "r-ggplot2",
      platform = "win-arm64"
    ))
    testthat::expect_true(packages_solve_native(
      "r-ggplot2",
      platform = "win-64"
    ))
  })
})

# A file with the start of a PE header: a 64-byte DOS header with `"MZ"`
# and the offset of the PE signature at 0x3C, then the signature and the
# `Machine` field at that offset. `size` cuts the file short.
write_fake_pe <- function(
  path,
  machine,
  pe_offset = 128L,
  dos_magic = charToRaw("MZ"),
  signature = as.raw(c(0x50, 0x45, 0x00, 0x00)),
  size = NULL
) {
  bytes <- raw(pe_offset + 24L)
  bytes[1:2] <- dos_magic
  bytes[61:64] <- writeBin(
    as.integer(pe_offset),
    raw(),
    size = 4L,
    endian = "little"
  )
  bytes[pe_offset + 1:4] <- signature
  bytes[pe_offset + 5:6] <- writeBin(
    as.integer(machine),
    raw(),
    size = 2L,
    endian = "little"
  )
  if (isFALSE(is.null(size))) {
    bytes <- bytes[seq_len(size)]
  }
  writeBin(bytes, path)
  return(path)
}

testthat::test_that("micromamba_native_platform() reads the Machine field of the PE header", {
  # Regression test: it ran `micromamba info --json`, a process on every
  # create_env() with specs or an env_file on every Windows machine.
  testthat::local_mocked_bindings(
    native_cmd = function(...) stop("native_cmd() must not be called")
  )
  dir <- withr::local_tempdir()
  fake <- function(name, ...) {
    return(write_fake_pe(fs::path(dir, name), ...))
  }
  testthat::expect_identical(
    micromamba_native_platform(fake("arm64.exe", machine = 0xAA64)),
    "win-arm64"
  )
  testthat::expect_identical(
    micromamba_native_platform(fake("x64.exe", machine = 0x8664)),
    "win-64"
  )
  # The PE signature right after the DOS header, and far after it.
  testthat::expect_identical(
    micromamba_native_platform(
      fake("near.exe", machine = 0xAA64, pe_offset = 64L)
    ),
    "win-arm64"
  )
  testthat::expect_identical(
    micromamba_native_platform(
      fake("far.exe", machine = 0x8664, pe_offset = 70000L)
    ),
    "win-64"
  )
  # By default, the managed binary, which native_cmd() runs when no
  # override names another.
  withr::local_options(condathis.micromamba_path = NULL)
  withr::local_envvar(CONDATHIS_MICROMAMBA_PATH = NA)
  testthat::local_mocked_bindings(
    micromamba_bin_path = function() fs::path(dir, "arm64.exe")
  )
  testthat::expect_identical(micromamba_native_platform(), "win-arm64")

  not_win <- list(
    i386 = fake("i386.exe", machine = 0x014C),
    arm32 = fake("arm32.exe", machine = 0x01C4),
    bad_signature = fake(
      "bad-signature.exe",
      machine = 0xAA64,
      signature = as.raw(c(0x4E, 0x45, 0x00, 0x00))
    ),
    bad_dos_magic = fake(
      "bad-magic.exe",
      machine = 0xAA64,
      dos_magic = charToRaw("ZM")
    ),
    # The signature is there, the Machine field is cut off.
    truncated = fake("truncated.exe", machine = 0xAA64, size = 128L + 5L),
    # Shorter than the DOS header.
    short = fake("short.exe", machine = 0xAA64, size = 40L),
    # An offset past the end of the file, and a negative one.
    past_end = fake(
      "past-end.exe",
      machine = 0xAA64,
      pe_offset = 128L,
      size = 100L
    ),
    negative = fake("negative.exe", machine = 0xAA64, pe_offset = 128L),
    empty = fs::file_create(fs::path(dir, "empty.exe")),
    missing = fs::path(dir, "missing.exe"),
    directory = dir
  )
  # 0xFFFFFFF0 as a signed little-endian integer.
  negative_bytes <- readBin(not_win$negative, "raw", n = 200L)
  negative_bytes[61:64] <- as.raw(c(0xF0, 0xFF, 0xFF, 0xFF))
  writeBin(negative_bytes, not_win$negative)
  writeLines("#!/bin/sh", fs::path(dir, "script"))
  not_win$script <- fs::path(dir, "script")
  for (case in names(not_win)) {
    testthat::expect_identical(
      micromamba_native_platform(not_win[[case]]),
      NA_character_,
      info = case
    )
  }
})

testthat::test_that("micromamba_native_platform() asks micromamba info when native_cmd() does not run the managed binary", {
  # Regression test: only the managed binary was read, so the first
  # create_env() on a new Windows ARM64 machine, before micromamba is
  # installed, and every binary of an override or the PATH got `NA`, and no
  # win-64 fallback.
  dir <- withr::local_tempdir()
  managed <- write_fake_pe(fs::path(dir, "managed.exe"), machine = 0xAA64)
  testthat::local_mocked_bindings(micromamba_bin_path = function() managed)
  withr::local_options(condathis.micromamba_path = NULL)
  withr::local_envvar(CONDATHIS_MICROMAMBA_PATH = NA)
  record <- local_fake_solve(stdout = '{"platform": "win-64"}')
  testthat::expect_identical(micromamba_native_platform(), "win-arm64")
  testthat::expect_null(record$conda_cmd)

  # No managed binary yet: native_cmd() installs it for `micromamba info`.
  fs::file_delete(managed)
  testthat::expect_identical(micromamba_native_platform(), "win-64")
  testthat::expect_identical(record$conda_cmd, "info")
  testthat::expect_identical(record$conda_args, "--json")
  testthat::expect_identical(record$error, "continue")

  # A managed binary that is not a PE file, such as on Linux and macOS.
  writeLines("#!/bin/sh", managed)
  record$conda_cmd <- NULL
  testthat::expect_identical(micromamba_native_platform(), "win-64")
  testthat::expect_identical(record$conda_cmd, "info")

  # An override comes before the managed binary, also when that is there.
  write_fake_pe(managed, machine = 0xAA64)
  withr::local_options(condathis.micromamba_path = fs::path(dir, "other.exe"))
  record$conda_cmd <- NULL
  testthat::expect_identical(micromamba_native_platform(), "win-64")
  testthat::expect_identical(record$conda_cmd, "info")
  withr::local_options(condathis.micromamba_path = NULL)
  withr::local_envvar(CONDATHIS_MICROMAMBA_PATH = fs::path(dir, "other.exe"))
  record$conda_cmd <- NULL
  testthat::expect_identical(micromamba_native_platform(), "win-64")
  testthat::expect_identical(record$conda_cmd, "info")
  # A given path is read as is, with no process.
  record$conda_cmd <- NULL
  testthat::expect_identical(micromamba_native_platform(managed), "win-arm64")
  testthat::expect_null(record$conda_cmd)
})

testthat::test_that("micromamba_native_platform() gives NA when micromamba info gives no platform", {
  withr::local_options(condathis.micromamba_path = NULL)
  withr::local_envvar(CONDATHIS_MICROMAMBA_PATH = NA)
  testthat::local_mocked_bindings(
    micromamba_bin_path = function() fs::path(tempdir(), "no-such-binary")
  )
  for (stdout in c("", "not json", "[1, 2]", "{}", '{"platform": null}')) {
    local_fake_solve(stdout = stdout, status = 1L)
    testthat::expect_identical(
      micromamba_native_platform(),
      NA_character_,
      info = stdout
    )
  }
})

testthat::test_that("micromamba_native_platform() reads the real micromamba as micromamba info does", {
  # The ELF and Mach-O binaries of Linux and macOS have no PE header, so
  # the default asks `micromamba info` there; define_platform() asks only on
  # Windows.
  skip_if_no_micromamba_offline()
  condathis::with_sandbox_dir({
    # Installs micromamba when no binary is found.
    info_res <- native_cmd(
      conda_cmd = "info",
      conda_args = "--json",
      verbose = "silent"
    )
    info_platform <- jsonlite::fromJSON(info_res$stdout)[["platform"]]
    umamba_path <- get_best_micromamba_path()
    testthat::expect_false(is.null(umamba_path))
    # The default, as define_platform() calls it.
    testthat::expect_identical(micromamba_native_platform(), info_platform)
    if (isTRUE(is_windows())) {
      testthat::expect_true(info_platform %in% c("win-64", "win-arm64"))
      testthat::expect_identical(
        micromamba_native_platform(umamba_path),
        info_platform
      )
    } else {
      testthat::expect_identical(
        micromamba_native_platform(umamba_path),
        NA_character_
      )
    }
  })
})
