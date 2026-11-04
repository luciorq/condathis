testthat::test_that("Micromamba installation", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  withr::local_path(new = list(base::tempdir()), action = "replace")
  umamba_bin_path <- install_micromamba(force = FALSE, verbose = FALSE)
  testthat::expect_true(fs::file_exists(umamba_bin_path))
})

testthat::test_that("Micromamba is already installed", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  testthat::expect_message(
    object = {
      umamba_bin_path <- install_micromamba(force = FALSE, verbose = "output")
    },
    regexp = "installed"
  )
  testthat::expect_true(fs::file_exists(umamba_bin_path))
})

testthat::test_that("Install micromamba from scratch", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  if (
    isTRUE(fs::dir_exists(fs::path(
      get_install_dir(method = "micromamba")$path,
      "micromamba"
    )))
  ) {
    fs::dir_delete(fs::path(
      get_install_dir(method = "micromamba")$path,
      "micromamba"
    ))
  }

  captured_output <- testthat::capture_output(code = {
    testthat::expect_message(
      object = {
        install_micromamba(verbose = "output")
      },
      # regexp = ".*successfully.*",
      class = "rlang_message"
    )
  })
  testthat::expect_true(fs::file_exists(micromamba_bin_path()))

  # The installed binary is the default version, so an explicit request
  # for that version keeps it.
  default_version <- formals(install_micromamba)$micromamba_version
  captured_output <- suppressMessages(
    testthat::expect_message(
      object = {
        install_micromamba(
          micromamba_version = default_version,
          verbose = "full"
        )
      },
      regexp = ".*already.*",
      class = "rlang_message"
    )
  ) |>
    testthat::capture_output()
  captured_output <- testthat::expect_message(
    object = {
      install_micromamba(
        micromamba_version = default_version,
        verbose = "output"
      )
    },
    regexp = ".*already.*",
    class = "rlang_message"
  ) |>
    testthat::capture_output()

  install_micromamba(micromamba_version = default_version, verbose = "silent")

  # An unsupported version is refused also when a binary is installed.
  testthat::expect_error(
    install_micromamba(micromamba_version = "1.5.9-0", verbose = "silent"),
    class = "condathis_install_micromamba_unsupported_version"
  )

  suppressMessages(
    testthat::expect_error(
      object = {
        suppressWarnings(
          install_micromamba(
            micromamba_version = "0.0.0-0",
            force = TRUE
          )
        )
      }
    )
  )
})

testthat::test_that("Fallback to uncompressed when archive extraction fails", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  testthat::local_mocked_bindings(extract_tar_bz2 = function(...) FALSE)

  if (
    isTRUE(fs::dir_exists(fs::path(
      get_install_dir(method = "micromamba")$path,
      "micromamba"
    )))
  ) {
    fs::dir_delete(fs::path(
      get_install_dir(method = "micromamba")$path,
      "micromamba"
    ))
  }

  captured_output <- suppressMessages(
    suppressWarnings(
      install_micromamba(force = TRUE, verbose = "silent")
    )
  ) |>
    testthat::capture_output()

  testthat::expect_true(fs::file_exists(micromamba_bin_path()))
})

# testthat::test_that("Mirror failover works when primary source fails", {
#   testthat::skip_if_offline()
#   testthat::skip_on_cran()

#   call_count <- 0L
#   original_download <- download_micromamba_file

#   # Mock download_micromamba_file to fail on the first URL (GitHub)
#   # and succeed on subsequent URLs (conda-forge mirror)
#   testthat::local_mocked_bindings(
#     download_micromamba_file = function(url, destfile, ...) {
#       call_count <<- call_count + 1L
#       if (base::identical(call_count, 1L)) {
#         return(FALSE)
#       }
#       return(original_download(url = url, destfile = destfile, ...))
#     }
#   )

#   if (isTRUE(fs::dir_exists(fs::path(get_install_dir(), "micromamba")))) {
#     fs::dir_delete(fs::path(get_install_dir(), "micromamba"))
#   }

#   captured_output <- suppressMessages(
#     suppressWarnings(
#       install_micromamba(force = TRUE, verbose = "silent")
#     )
#   ) |>
#     testthat::capture_output()

#   testthat::expect_true(fs::file_exists(micromamba_bin_path()))
#   # Verify that multiple download attempts were made (failover happened)
#   testthat::expect_gt(call_count, 1L)
# })

testthat::test_that("get_micromamba_urls returns correct structure", {
  urls <- get_micromamba_urls(
    sys_arch_str = "linux-64",
    micromamba_version = "2.9.0-0"
  )

  testthat::expect_type(urls, "list")
  testthat::expect_named(
    urls,
    c("compressed", "uncompressed", "sha256", "archive_sha256")
  )

  # Compressed URLs should include GitHub, Anaconda, and prefix.dev.
  # micro.mamba.pm is deliberately not included: confirmed (2026-07-24) that
  # its API no longer serves pinned versions at all (only "latest"), and
  # condathis always requests a pinned version, so it would fail on every
  # single install - not a transient outage, permanently dead for this
  # package's use case.
  testthat::expect_length(urls$compressed, 3L)
  testthat::expect_match(urls$compressed[1L], "github.com")
  testthat::expect_match(urls$compressed[2L], "anaconda.org")
  testthat::expect_match(urls$compressed[3L], "prefix.dev")
  testthat::expect_false(any(grepl("micro.mamba.pm", urls$compressed)))

  # Uncompressed URL should be from GitHub only
  testthat::expect_length(urls$uncompressed, 1L)
  testthat::expect_match(urls$uncompressed[1L], "github.com")

  # SHA256 URL should be from GitHub
  testthat::expect_match(urls$sha256[1L], "\\.sha256$")
})

testthat::test_that("get_micromamba_urls() builds the win-arm64 endpoints", {
  # Every endpoint answered 200 on 2026-10-27 for 2.10.0-0, 2.9.0-0 and
  # 2.8.1-1. 2.8.1-0 has all of them except the `.sha256` file.
  urls <- get_micromamba_urls(
    sys_arch_str = "win-arm64",
    micromamba_version = "2.10.0-0"
  )
  github <- paste0(
    "https://github.com/mamba-org/micromamba-releases/releases/download/",
    "2.10.0-0/micromamba-win-arm64"
  )
  testthat::expect_identical(
    urls$compressed,
    c(
      paste0(github, ".tar.bz2"),
      paste0(
        "https://api.anaconda.org/download/conda-forge/micromamba/2.10.0/",
        "win-arm64/micromamba-2.10.0-0.tar.bz2"
      ),
      "https://repo.prefix.dev/conda-forge/win-arm64/micromamba-2.10.0-0.tar.bz2"
    )
  )
  testthat::expect_identical(urls$uncompressed, github)
  testthat::expect_identical(urls$sha256, paste0(github, ".sha256"))
  testthat::expect_identical(
    urls$archive_sha256,
    paste0(github, ".tar.bz2.sha256")
  )
})

testthat::test_that("has_system_tar returns logical", {
  testthat::expect_type(has_system_tar(), "logical")
})

testthat::test_that("No warnings when archive extraction fails", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  testthat::local_mocked_bindings(extract_tar_bz2 = function(...) FALSE)

  if (
    isTRUE(fs::dir_exists(fs::path(
      get_install_dir(method = "micromamba")$path,
      "micromamba"
    )))
  ) {
    fs::dir_delete(fs::path(
      get_install_dir(method = "micromamba")$path,
      "micromamba"
    ))
  }

  # This should NOT produce any warnings about tar or bzip2
  captured_output <- testthat::capture_output({
    result <- testthat::expect_no_warning(
      suppressMessages(
        install_micromamba(force = TRUE, verbose = "silent")
      )
    )
  })

  testthat::expect_true(fs::file_exists(micromamba_bin_path()))
})

testthat::test_that("download_uncompressed_binary preserves an existing binary when all mirrors fail", {
  # Regression test: the live binary path used to be passed directly as
  # the download destination, and try_download_from_mirrors() deletes its
  # destfile after every failed mirror - so `force = TRUE` on a machine
  # with unreachable mirrors deleted a working installation and then
  # aborted, leaving nothing. The download must go to a temporary path,
  # and the existing binary must only be replaced once a complete new one
  # exists.
  bin_dir <- withr::local_tempdir()
  bin_path <- fs::path(bin_dir, "micromamba")
  writeLines("existing working binary", bin_path)

  seen_destfiles <- character(0L)
  testthat::local_mocked_bindings(
    download_micromamba_file = function(url, destfile, ...) {
      seen_destfiles <<- c(seen_destfiles, as.character(destfile))
      # A partial download, which the mirror loop must delete.
      writeLines("partial", destfile)
      FALSE
    }
  )

  result <- download_uncompressed_binary(
    uncompressed_urls = c(
      "https://mirror-a.invalid",
      "https://mirror-b.invalid"
    ),
    umamba_bin_path = bin_path,
    timeout_limit = 1,
    download_method = "auto",
    dl_quiet_flag = TRUE
  )

  testthat::expect_false(result)
  # The live binary was never handed out as a download destination...
  testthat::expect_false(as.character(bin_path) %in% seen_destfiles)
  # ...and survived the total failure, intact.
  testthat::expect_true(fs::file_exists(bin_path))
  testthat::expect_equal(readLines(bin_path), "existing working binary")
})

testthat::test_that("download_uncompressed_binary replaces the binary only after a successful download", {
  bin_dir <- withr::local_tempdir()
  bin_path <- fs::path(bin_dir, "micromamba")
  writeLines("old binary", bin_path)

  testthat::local_mocked_bindings(
    download_micromamba_file = function(url, destfile, ...) {
      writeLines("new binary", destfile)
      TRUE
    },
    candidate_micromamba_runs = function(path) TRUE,
    verify_micromamba_checksum = function(...) NA
  )

  result <- download_uncompressed_binary(
    uncompressed_urls = "https://mirror-a.invalid",
    umamba_bin_path = bin_path,
    timeout_limit = 1,
    download_method = "auto",
    dl_quiet_flag = TRUE
  )

  testthat::expect_true(result)
  testthat::expect_equal(readLines(bin_path), "new binary")
  # No temporary download debris left behind.
  leftovers <- fs::dir_ls(bin_dir, glob = "*micromamba-dl-*")
  testthat::expect_length(leftovers, 0L)
})

testthat::test_that("a candidate that does not run is never installed", {
  # Regression test: an extraction that failed (an HTML error page served
  # with status 200, or a truncated archive) was counted as success whenever
  # a file already existed at the live path, and a truncated archive could
  # overwrite a working binary in place.
  bin_dir <- withr::local_tempdir()
  bin_path <- fs::path(bin_dir, "micromamba")
  writeLines("old working binary", bin_path)

  testthat::local_mocked_bindings(
    download_micromamba_file = function(url, destfile, ...) {
      writeLines("<html>not a binary</html>", destfile)
      TRUE
    }
  )
  result <- download_uncompressed_binary(
    uncompressed_urls = "https://mirror-a.invalid",
    umamba_bin_path = bin_path,
    timeout_limit = 1,
    download_method = "auto",
    dl_quiet_flag = TRUE
  )
  testthat::expect_false(result)
  testthat::expect_equal(readLines(bin_path), "old working binary")
  testthat::expect_length(fs::dir_ls(bin_dir, glob = "*micromamba-dl-*"), 0L)
})

testthat::test_that("a candidate with a mismatching checksum is never installed", {
  bin_dir <- withr::local_tempdir()
  bin_path <- fs::path(bin_dir, "micromamba")
  writeLines("old working binary", bin_path)
  candidate <- fs::path(bin_dir, "candidate")
  writeLines("tampered binary", candidate)

  testthat::local_mocked_bindings(
    candidate_micromamba_runs = function(path) TRUE,
    verify_micromamba_checksum = function(...) FALSE
  )
  testthat::expect_false(install_candidate_micromamba(
    candidate = candidate,
    umamba_bin_path = bin_path,
    sha256_urls = "https://mirror-a.invalid",
    timeout_limit = 1,
    download_method = "auto",
    verbose = list(strategy = "silent")
  ))
  testthat::expect_equal(readLines(bin_path), "old working binary")

  # An unverifiable checksum (NA) does not block the install.
  testthat::local_mocked_bindings(verify_micromamba_checksum = function(...) NA)
  testthat::expect_true(install_candidate_micromamba(
    candidate = candidate,
    umamba_bin_path = bin_path,
    sha256_urls = character(0L),
    timeout_limit = 1,
    download_method = "auto",
    verbose = list(strategy = "silent")
  ))
  testthat::expect_equal(readLines(bin_path), "tampered binary")
})

testthat::test_that("a broken archive leaves the live binary untouched", {
  root <- withr::local_tempdir()
  untar_dir <- fs::path(root, "micromamba")
  bin_path <- fs::path(untar_dir, "bin", "micromamba")
  fs::dir_create(fs::path_dir(bin_path))
  writeLines("old working binary", bin_path)

  testthat::local_mocked_bindings(
    download_micromamba_file = function(url, destfile, ...) {
      writeLines("<html>404 page served with status 200</html>", destfile)
      TRUE
    }
  )
  result <- download_compressed_and_extract(
    compressed_urls = "https://mirror-a.invalid",
    output_dir = root,
    untar_dir = untar_dir,
    umamba_bin_path = bin_path,
    timeout_limit = 1,
    download_method = "auto",
    dl_quiet_flag = TRUE
  )
  testthat::expect_false(result)
  testthat::expect_equal(readLines(bin_path), "old working binary")
  testthat::expect_length(fs::dir_ls(root, glob = "*micromamba-extract-*"), 0L)
  testthat::expect_length(fs::dir_ls(root, glob = "*micromamba-dl-*"), 0L)
})

testthat::test_that("install_micromamba() refuses versions older than the minimum", {
  # Regression test: an older version was installed, then skipped by
  # discovery and silently replaced by the pinned version.
  condathis::with_sandbox_dir({
    testthat::expect_error(
      install_micromamba(micromamba_version = "2.0.2-2", force = TRUE),
      class = "condathis_micromamba_version_unsupported"
    )
    # The renamed class and the old one (decision D2).
    cnd <- testthat::expect_error(
      install_micromamba(micromamba_version = "2.0.2-2", force = TRUE),
      class = "condathis_install_micromamba_unsupported_version"
    )
    testthat::expect_identical(
      class(cnd)[1:3],
      c(
        "condathis_install_micromamba_unsupported_version",
        "condathis_micromamba_version_unsupported",
        "condathis_error"
      )
    )
  })
})

# A `.tar.bz2` archive laid out like the micromamba package, written with
# R's internal tar so the test needs no system tools.
local_fake_micromamba_archive <- function(.local_envir = parent.frame()) {
  src <- withr::local_tempdir(.local_envir = .local_envir)
  fs::dir_create(fs::path(src, "bin"))
  writeLines("fake micromamba", fs::path(src, "bin", "micromamba"))
  archive <- withr::local_tempfile(
    fileext = ".tar.bz2",
    .local_envir = .local_envir
  )
  withr::with_dir(src, {
    utils::tar(archive, files = "bin", compression = "bzip2", tar = "internal")
  })
  return(archive)
}

testthat::test_that("extract_tar_bz2() needs no system tar or bzip2", {
  # Regression test: the archive was only used when `tar` and `bzip2` were
  # both on PATH. Windows rarely has `bzip2`, so Windows installs never
  # used the Anaconda and prefix.dev mirrors.
  archive <- local_fake_micromamba_archive()
  testthat::local_mocked_bindings(system_tar_program = function(...) NULL)
  withr::local_envvar(PATH = "", TAR = "")
  exdir <- withr::local_tempdir()

  testthat::expect_true(extract_tar_bz2(archive, exdir))
  testthat::expect_identical(
    readLines(fs::path(exdir, "bin", "micromamba")),
    "fake micromamba"
  )
})

testthat::test_that("extract_tar_bz2() falls back to the system tar", {
  archive <- local_fake_micromamba_archive()
  calls <- list()
  testthat::local_mocked_bindings(
    system_tar_program = function(...) "/opt/fake/tar"
  )
  testthat::local_mocked_bindings(
    untar = function(...) 1L,
    .package = "utils"
  )
  testthat::local_mocked_bindings(
    run = function(command, args, stdin, wd, ...) {
      calls[[length(calls) + 1L]] <<- list(
        command = command,
        args = args,
        stdin = stdin,
        wd = wd
      )
      list(status = 0L)
    },
    .package = "processx"
  )
  exdir <- withr::local_tempdir()

  testthat::expect_true(extract_tar_bz2(archive, exdir))
  testthat::expect_length(calls, 1L)
  testthat::expect_identical(calls[[1L]]$command, "/opt/fake/tar")
  # The archive goes in on stdin: no path argument for tar to misread.
  testthat::expect_identical(calls[[1L]]$args, c("-xjf", "-"))
  testthat::expect_identical(calls[[1L]]$stdin, as.character(archive))
})

testthat::test_that("extract_tar_bz2() works with the real system tar", {
  testthat::skip_if_not(has_system_tar())
  archive <- local_fake_micromamba_archive()
  testthat::local_mocked_bindings(
    untar = function(...) 1L,
    .package = "utils"
  )
  exdir <- withr::local_tempdir()
  # GNU tar needs bzip2 for -j; bsdtar (the Windows and macOS tar) does not.
  testthat::skip_if_not(
    extract_tar_bz2(archive, exdir),
    "tar cannot read bzip2"
  )
  testthat::expect_identical(
    readLines(fs::path(exdir, "bin", "micromamba")),
    "fake micromamba"
  )
})

testthat::test_that("extract_tar_bz2() ignores warnings from R's internal tar", {
  # Regression test: conda-forge archives use pax headers, and R warns
  # "using pax extended headers" while extracting them correctly. Any
  # warning counted as a failed extraction.
  archive <- local_fake_micromamba_archive()
  real_untar <- utils::untar
  testthat::local_mocked_bindings(system_tar_program = function(...) NULL)
  testthat::local_mocked_bindings(
    untar = function(tarfile, exdir, ...) {
      warning("using pax extended headers")
      real_untar(tarfile, exdir = exdir, tar = "internal")
    },
    .package = "utils"
  )
  testthat::expect_true(extract_tar_bz2(archive, withr::local_tempdir()))
})

testthat::test_that("extract_tar_bz2() reports failure and cleans up", {
  not_an_archive <- withr::local_tempfile(fileext = ".tar.bz2")
  writeLines("<html>404 page served with status 200</html>", not_an_archive)
  testthat::local_mocked_bindings(system_tar_program = function(...) NULL)
  exdir <- fs::path(withr::local_tempdir(), "extract")

  testthat::expect_false(extract_tar_bz2(not_an_archive, exdir))
  testthat::expect_false(fs::dir_exists(exdir))
})

testthat::test_that("install_micromamba() installs from the archive without system tar", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # Only the archive strategy is available, and no system tar: the install
  # must succeed with R's internal tar alone, on every platform.
  testthat::local_mocked_bindings(
    system_tar_program = function(...) NULL,
    download_uncompressed_binary = function(...) FALSE
  )
  testthat::expect_no_error(
    install_micromamba(force = TRUE, verbose = "silent")
  )
  testthat::expect_true(check_micromamba_version(micromamba_bin_path()))
})

# No download may start: every test below fails before one, or mocks it.
local_no_download <- function(.local_envir = parent.frame()) {
  testthat::local_mocked_bindings(
    download_micromamba_file = function(...) {
      stop("no download may start")
    },
    .env = .local_envir
  )
  return(invisible(NULL))
}

testthat::test_that("install_micromamba() validates force", {
  # Regression test: force was only tested with isFALSE(), so "yes" or NA
  # reinstalled micromamba.
  local_no_download()
  condathis::with_sandbox_dir({
    for (bad in list("yes", NA, c(TRUE, FALSE), 1, NULL)) {
      cnd <- testthat::expect_error(
        install_micromamba(force = bad),
        class = "condathis_install_micromamba_invalid_force"
      )
      testthat::expect_identical(
        class(cnd)[1:4],
        c(
          "condathis_install_micromamba_invalid_force",
          "condathis_invalid_force",
          "condathis_invalid_arg",
          "condathis_error"
        )
      )
    }
    testthat::expect_false(fs::dir_exists(get_condathis_path()))
  })
})

testthat::test_that("install_micromamba() validates the micromamba_version format", {
  # Regression test: "latest" passed unchecked, and "2.9.0" built download
  # URLs that end in "-NA".
  local_no_download()
  condathis::with_sandbox_dir({
    for (bad in list(
      "latest",
      "2.9.0",
      "v2.9.0-0",
      "2.9-0",
      NA_character_,
      2.9,
      c("2.9.0-0", "2.8.1-0")
    )) {
      cnd <- testthat::expect_error(
        install_micromamba(micromamba_version = bad, force = TRUE),
        class = "condathis_install_micromamba_invalid_micromamba_version"
      )
      testthat::expect_s3_class(cnd, "condathis_invalid_arg")
      testthat::expect_s3_class(cnd, "condathis_error")
    }
    testthat::expect_identical(
      validate_micromamba_version_arg("2.9.0-0"),
      "2.9.0"
    )
    testthat::expect_identical(
      validate_micromamba_version_arg("10.12.3-11"),
      "10.12.3"
    )
    # A two-digit minor version is newer than the minimum, 2.8.1.
    testthat::expect_identical(
      validate_micromamba_version_arg("2.10.0-0"),
      "2.10.0"
    )
    testthat::expect_false(fs::dir_exists(get_condathis_path()))
  })
})

testthat::test_that("install_micromamba() validates download_method", {
  local_no_download()
  condathis::with_sandbox_dir({
    for (bad in list("bogus", NA_character_, 1, c("curl", "wget"))) {
      cnd <- testthat::expect_error(
        install_micromamba(download_method = bad, force = TRUE),
        class = "condathis_install_micromamba_invalid_download_method"
      )
      testthat::expect_s3_class(cnd, "condathis_invalid_download_method")
      testthat::expect_s3_class(cnd, "condathis_invalid_arg")
      testthat::expect_s3_class(cnd, "condathis_error")
    }
  })
})

testthat::test_that("install_micromamba() validates verbose", {
  local_no_download()
  condathis::with_sandbox_dir({
    cnd <- testthat::expect_error(
      install_micromamba(verbose = "bogus"),
      class = "condathis_invalid_verbose"
    )
    testthat::expect_s3_class(cnd, "condathis_error")
    testthat::expect_identical(
      rlang::call_name(conditionCall(cnd)),
      "install_micromamba"
    )
  })
})

testthat::test_that("install_micromamba() installs a requested version that differs from the installed one", {
  # Regression test: with any binary present and force = FALSE, an explicit
  # micromamba_version was ignored.
  condathis::with_sandbox_dir({
    bin_path <- micromamba_bin_path()
    fs::dir_create(fs::path_dir(bin_path))
    writeLines("installed micromamba", bin_path)
    downloads <- new.env()
    downloads$n <- 0L
    installed <- new.env()
    installed$version <- "2.9.0"
    testthat::local_mocked_bindings(
      get_micromamba_version = function(...) installed$version,
      download_compressed_and_extract = function(...) {
        downloads$n <- downloads$n + 1L
        return(TRUE)
      },
      download_uncompressed_binary = function(...) {
        stop("the first strategy succeeded")
      }
    )

    # The installed version is the requested one: kept.
    testthat::expect_identical(
      install_micromamba(micromamba_version = "2.9.0-0", verbose = "silent"),
      bin_path
    )
    testthat::expect_identical(downloads$n, 0L)

    # Another version: installed.
    messages <- testthat::capture_messages(
      install_micromamba(micromamba_version = "2.8.1-0", verbose = "output")
    )
    testthat::expect_true(
      any(grepl("Installing the requested version", messages, fixed = TRUE))
    )
    testthat::expect_identical(downloads$n, 1L)

    # No explicit version: an installed binary is kept, whatever its
    # version.
    installed$version <- "2.8.1"
    install_micromamba(verbose = "silent")
    testthat::expect_identical(downloads$n, 1L)

    # A version that cannot be read does not satisfy an explicit request.
    testthat::local_mocked_bindings(
      get_micromamba_version = function(...) stop("no version")
    )
    install_micromamba(micromamba_version = "2.9.0-0", verbose = "silent")
    testthat::expect_identical(downloads$n, 2L)
  })
})

testthat::test_that("install_micromamba() renames timeout_limit to timeout", {
  # Decision: the run family names it `timeout`. `timeout_limit` is a
  # deprecated alias.
  testthat::expect_identical(
    names(formals(install_micromamba)),
    c(
      "micromamba_version",
      "timeout",
      "download_method",
      "force",
      "verbose",
      "timeout_limit"
    )
  )
  condathis::with_sandbox_dir({
    seen <- new.env()
    testthat::local_mocked_bindings(
      download_compressed_and_extract = function(..., timeout_limit) {
        seen$timeout <- timeout_limit
        return(TRUE)
      },
      file_exists_retry = function(...) TRUE
    )
    install_micromamba(timeout = 60, force = TRUE, verbose = "silent")
    testthat::expect_identical(seen$timeout, 60)

    # Positional calls keep working: `timeout` took the old position.
    install_micromamba("2.9.0-0", 61, force = TRUE, verbose = "silent")
    testthat::expect_identical(seen$timeout, 61)

    cnd <- testthat::expect_warning(
      install_micromamba(timeout_limit = 30, force = TRUE, verbose = "silent"),
      class = "condathis_deprecated_arg"
    )
    testthat::expect_s3_class(cnd, "condathis_warning")
    testthat::expect_identical(seen$timeout, 30)

    # Values above the largest process timeout are lowered to it.
    install_micromamba(timeout = 1e9, force = TRUE, verbose = "silent")
    testthat::expect_identical(seen$timeout, 2147483)
  })
})

testthat::test_that("install_micromamba() refuses timeout together with timeout_limit", {
  local_no_download()
  condathis::with_sandbox_dir({
    cnd <- testthat::expect_error(
      install_micromamba(timeout = 10, timeout_limit = 20, force = TRUE),
      class = "condathis_install_micromamba_conflicting_args"
    )
    testthat::expect_s3_class(cnd, "condathis_invalid_arg")
    testthat::expect_s3_class(cnd, "condathis_error")
  })
})

testthat::test_that("verify_micromamba_checksum() reads the archive checksum when the binary has none", {
  # Regression test: micromamba 2.8.1-0 publishes no checksum of the
  # win-arm64 binary, so it installed unverified. The `.tar.bz2.sha256`
  # file holds the hash of the binary for most releases, and the hash of
  # the archive for that one: either now verifies the binary.
  bin_path <- withr::local_tempfile()
  writeLines("binary", bin_path)
  binary_hash <- compute_sha256(bin_path)
  archive_hash <- strrep("c", 64L)
  served <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    try_download_from_mirrors = function(urls, destfile, ...) {
      served$urls <- c(served$urls, urls)
      content <- served$files[[urls[[1L]]]]
      if (is.null(content)) {
        return(FALSE)
      }
      writeLines(content, destfile)
      return(TRUE)
    }
  )
  check <- function(archive_sha, archive_hash_value, strategy = "output") {
    served$urls <- character(0L)
    served$files <- list(archive = archive_sha)
    return(verify_micromamba_checksum(
      bin_path,
      sha256_urls = "binary",
      verbose = list(strategy = strategy),
      archive = list(hash = archive_hash_value, sha256_urls = "archive")
    ))
  }

  # The hash of the archive the binary was extracted from.
  testthat::expect_true(check(archive_hash, archive_hash))
  testthat::expect_identical(served$urls, c("binary", "archive"))
  # The hash of the binary, as most releases publish it, also without an
  # archive.
  testthat::expect_true(check(binary_hash, archive_hash))
  testthat::expect_true(check(binary_hash, NA_character_))
  # A hash that is neither: a mismatch for an extracted binary, also when
  # silent.
  testthat::expect_warning(
    res <- check(strrep("d", 64L), archive_hash, strategy = "silent"),
    class = "condathis_install_micromamba_checksum_mismatch"
  )
  testthat::expect_false(res)
  # For a binary downloaded on its own, it can be the hash of an archive:
  # not verified.
  testthat::expect_warning(
    res <- check(archive_hash, NA_character_),
    class = "condathis_install_micromamba_checksum_unavailable"
  )
  testthat::expect_true(is.na(res))
  # No archive checksum either: not verified, as before.
  testthat::expect_warning(
    res <- check(NULL, archive_hash),
    class = "condathis_install_micromamba_checksum_unavailable"
  )
  testthat::expect_true(is.na(res))
  # A published checksum of the binary is used first, and alone.
  served$urls <- character(0L)
  served$files <- list(binary = binary_hash, archive = strrep("d", 64L))
  testthat::expect_true(verify_micromamba_checksum(
    bin_path,
    sha256_urls = "binary",
    archive = list(hash = archive_hash, sha256_urls = "archive")
  ))
  testthat::expect_identical(served$urls, "binary")
})

testthat::test_that("verify_micromamba_checksum() warnings have classes", {
  bin_path <- withr::local_tempfile()
  writeLines("binary", bin_path)
  verbose <- list(strategy = "output")

  # No checksum could be downloaded.
  testthat::local_mocked_bindings(try_download_from_mirrors = function(...) {
    FALSE
  })
  cnd <- testthat::expect_warning(
    res <- verify_micromamba_checksum(bin_path, "u", verbose = verbose),
    class = "condathis_install_micromamba_checksum_unavailable"
  )
  testthat::expect_s3_class(cnd, "condathis_warning")
  testthat::expect_true(is.na(res))

  # The checksum file is not valid.
  testthat::local_mocked_bindings(
    try_download_from_mirrors = function(urls, destfile, ...) {
      writeLines("<html>not a checksum</html>", destfile)
      return(TRUE)
    }
  )
  testthat::expect_warning(
    verify_micromamba_checksum(bin_path, "u", verbose = verbose),
    class = "condathis_install_micromamba_checksum_unavailable"
  )

  # The hash cannot be computed.
  testthat::local_mocked_bindings(
    try_download_from_mirrors = function(urls, destfile, ...) {
      writeLines(strrep("a", 64L), destfile)
      return(TRUE)
    },
    compute_sha256 = function(...) NA_character_
  )
  testthat::expect_warning(
    verify_micromamba_checksum(bin_path, "u", verbose = verbose),
    class = "condathis_install_micromamba_checksum_unavailable"
  )

  # A mismatch warns also when silent.
  testthat::local_mocked_bindings(compute_sha256 = function(...) {
    strrep("b", 64L)
  })
  cnd <- testthat::expect_warning(
    res <- verify_micromamba_checksum(
      bin_path,
      "u",
      verbose = list(strategy = "silent")
    ),
    class = "condathis_install_micromamba_checksum_mismatch"
  )
  testthat::expect_s3_class(cnd, "condathis_warning")
  testthat::expect_false(res)
})
