# The standard SHA-256 test vector for the ASCII string "abc", cross-checked
# directly against tools::sha256sum(), digest::digest(), openssl::sha256(),
# and Python's hashlib (all agree) before being hardcoded here and in
# R/install_micromamba.R's sha256_command_is_trustworthy().
abc_sha256 <- "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

abc_test_file <- function() {
  # Deliberately not withr::local_tempfile(): its default .local_envir is
  # this helper's own frame, which exits (deleting the file) the instant
  # this function returns - before any caller like compute_sha256() ever
  # gets to read it. A plain tempfile() is cleaned up when the R session
  # ends, which is fine for a few tiny scratch files.
  tmp <- base::tempfile()
  writeBin(charToRaw("abc"), tmp)
  return(tmp)
}

testthat::test_that("has_tools_sha256sum reflects both R version and namespace presence", {
  testthat::local_mocked_bindings(
    getRversion = function() base::as.numeric_version("4.4.0"),
    .package = "base"
  )
  testthat::expect_false(has_tools_sha256sum())
})

testthat::test_that("sha256_command_is_trustworthy accepts a real, correct tool", {
  testthat::skip_if_not(
    nzchar(Sys.which("sha256sum")) || nzchar(Sys.which("shasum"))
  )
  sha_cmd <- if (nzchar(Sys.which("sha256sum"))) "sha256sum" else "shasum"
  testthat::expect_true(sha256_command_is_trustworthy(sha_cmd))
})

testthat::test_that("sha256_command_is_trustworthy rejects a nonexistent command", {
  testthat::expect_false(
    sha256_command_is_trustworthy("definitely-not-a-real-sha-tool-xyz")
  )
})

testthat::test_that("sha256_command_is_trustworthy rejects a tool that reports the wrong hash", {
  # Simulates a broken/wrong/aliased binary on PATH under the expected name -
  # confirmed as a live risk during development, not a hypothetical.
  testthat::local_mocked_bindings(
    run = function(...) {
      list(
        status = 0L,
        stdout = paste0(strrep("0", 64), "  file\n")
      )
    },
    .package = "processx"
  )
  testthat::expect_false(sha256_command_is_trustworthy("sha256sum"))
})

testthat::test_that("run_sha256_command strips the GNU coreutils backslash-escape prefix", {
  # GNU coreutils' sha256sum prepends a literal "\" directly before the
  # hash (no space) whenever the filename contains a backslash or newline
  # - its documented escaping convention. Essentially guaranteed on
  # Windows, where every absolute path contains backslashes; confirmed on
  # real Windows CI as the root cause of a perfectly valid hash being
  # rejected by the 64-hex-char check below.
  abc_sha256 <- "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  testthat::local_mocked_bindings(
    run = function(...) {
      list(
        status = 0L,
        stdout = paste0(
          "\\",
          abc_sha256,
          " *C:\\Users\\runner\\AppData\\Local\\Temp\\file123\n"
        )
      )
    },
    .package = "processx"
  )
  testthat::expect_equal(
    run_sha256_command("sha256sum", "irrelevant"),
    abc_sha256
  )
})

testthat::test_that("run_sha256_command rejects output that isn't a real 64-char hex digest", {
  testthat::local_mocked_bindings(
    run = function(...) list(status = 0L, stdout = "not-a-hash  file\n"),
    .package = "processx"
  )
  testthat::expect_true(is.na(run_sha256_command("sha256sum", "irrelevant")))
})

testthat::test_that("run_sha256_command returns NA when the command fails", {
  testthat::local_mocked_bindings(
    run = function(...) list(status = 1L, stdout = ""),
    .package = "processx"
  )
  testthat::expect_true(is.na(run_sha256_command("sha256sum", "irrelevant")))
})

testthat::test_that("compute_sha256 matches the known-answer vector end to end", {
  testthat::expect_equal(compute_sha256(abc_test_file()), abc_sha256)
})

testthat::test_that("compute_sha256 falls through to digest when tools::sha256sum is unavailable", {
  testthat::skip_if_not_installed("digest")
  testthat::local_mocked_bindings(has_tools_sha256sum = function() FALSE)
  testthat::expect_equal(compute_sha256(abc_test_file()), abc_sha256)
})

testthat::test_that("compute_sha256 falls through to a trustworthy system command as a last resort", {
  testthat::skip_if_not(
    nzchar(Sys.which("sha256sum")) || nzchar(Sys.which("shasum"))
  )
  testthat::local_mocked_bindings(has_tools_sha256sum = function() FALSE)
  testthat::local_mocked_bindings(
    requireNamespace = function(...) FALSE,
    .package = "base"
  )
  testthat::expect_equal(compute_sha256(abc_test_file()), abc_sha256)
})

testthat::test_that("compute_sha256 returns NA_character_ when nothing is available, never errors", {
  testthat::local_mocked_bindings(has_tools_sha256sum = function() FALSE)
  testthat::local_mocked_bindings(
    requireNamespace = function(...) FALSE,
    .package = "base"
  )
  testthat::local_mocked_bindings(sha256_command_is_trustworthy = function(
    ...
  ) {
    FALSE
  })
  result <- testthat::expect_no_error(compute_sha256(abc_test_file()))
  testthat::expect_true(is.na(result))
})

testthat::test_that("verify_micromamba_checksum warns, but never aborts, on a real mismatch", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  urls <- get_micromamba_urls(
    sys_arch_str = is_micromamba_available_for_arch(),
    micromamba_version = "2.9.0-0"
  )
  # Any file that isn't the real micromamba binary triggers a genuine
  # mismatch against the real, network-fetched .sha256 for this version.
  not_the_binary <- abc_test_file()

  result <- NULL
  testthat::expect_warning(
    object = {
      result <- verify_micromamba_checksum(
        bin_path = not_the_binary,
        sha256_urls = urls$sha256,
        verbose = list(strategy = "full")
      )
    },
    regexp = "checksum mismatch"
  )
  testthat::expect_false(result)
})

testthat::test_that("parse_sha256_file reads bare and sha256sum-format checksum files", {
  write_sha_file <- function(content) {
    tmp <- base::tempfile(fileext = ".sha256")
    writeBin(charToRaw(content), tmp)
    return(tmp)
  }
  # micromamba release files hold the bare hash with no trailing newline.
  testthat::expect_identical(
    parse_sha256_file(write_sha_file(abc_sha256)),
    abc_sha256
  )
  testthat::expect_identical(
    parse_sha256_file(write_sha_file(paste0(toupper(abc_sha256), "\n"))),
    abc_sha256
  )
  testthat::expect_identical(
    parse_sha256_file(write_sha_file(paste0(abc_sha256, "  micromamba\n"))),
    abc_sha256
  )
  testthat::expect_identical(
    parse_sha256_file(write_sha_file("<!DOCTYPE html><html></html>")),
    NA_character_
  )
  testthat::expect_identical(
    parse_sha256_file(write_sha_file("")),
    NA_character_
  )
})

testthat::test_that("verify_micromamba_checksum accepts the sha256sum file format", {
  # Regression test: the whole first line was compared, so a
  # `<hash>  <file name>` line never matched a correct binary.
  sha_content <- paste0(abc_sha256, "  micromamba-linux-64\n")
  testthat::local_mocked_bindings(
    try_download_from_mirrors = function(urls, destfile, ...) {
      writeBin(charToRaw(sha_content), destfile)
      TRUE
    }
  )
  testthat::expect_true(
    verify_micromamba_checksum(abc_test_file(), sha256_urls = "mocked")
  )

  # A checksum file that is not one cannot verify anything: NA, not a
  # mismatch.
  sha_content <- "<html>rate limited</html>"
  testthat::expect_identical(
    verify_micromamba_checksum(abc_test_file(), sha256_urls = "mocked"),
    NA
  )
})

testthat::test_that("the default micromamba version publishes a valid checksum", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  default_version <- formals(install_micromamba)$micromamba_version
  urls <- get_micromamba_urls(
    sys_arch_str = is_micromamba_available_for_arch(),
    micromamba_version = default_version
  )
  sha_file <- withr::local_tempfile(fileext = ".sha256")
  testthat::expect_true(
    try_download_from_mirrors(urls = urls$sha256, destfile = sha_file)
  )
  testthat::expect_match(parse_sha256_file(sha_file), "^[0-9a-f]{64}$")
})

testthat::test_that("parse_certutil_sha256 reads the hash from certutil output", {
  # Windows 10 and 11.
  modern <- paste0(
    "SHA256 hash of C:\\Users\\me\\AppData\\Local\\Temp\\Rtmp\\file1a2b:\r\n",
    abc_sha256,
    "\r\nCertUtil: -hashfile command completed successfully.\r\n"
  )
  testthat::expect_identical(parse_certutil_sha256(modern), abc_sha256)
  # Older Windows: the bytes separated by spaces, the hash in upper case.
  spaced <- paste0(
    "SHA256 hash of file C:\\tmp\\file:\n",
    paste(
      substring(toupper(abc_sha256), seq(1, 63, 2), seq(2, 64, 2)),
      collapse = " "
    ),
    "\nCertUtil: -hashfile command completed successfully.\n"
  )
  testthat::expect_identical(parse_certutil_sha256(spaced), abc_sha256)
  # A localized header and footer, in a code page that is not UTF-8, and a
  # path with a hex-looking file name.
  localized <- paste0(
    "SHA256-Hash von C:\\Temp\\",
    strrep("a", 64),
    ":\r\n",
    abc_sha256,
    "\r\nCertUtil: -hashfile-Befehl wurde erfolgreich ausgef\xfchrt.\r\n"
  )
  testthat::expect_identical(parse_certutil_sha256(localized), abc_sha256)
  # No hash, two different hashes, or no output at all.
  testthat::expect_identical(
    parse_certutil_sha256(
      "CertUtil: -hashfile command FAILED: 0x80070002 (WIN32: 2)\r\n"
    ),
    NA_character_
  )
  testthat::expect_identical(
    parse_certutil_sha256(paste(abc_sha256, strrep("0", 64), sep = "\n")),
    NA_character_
  )
  testthat::expect_identical(parse_certutil_sha256(""), NA_character_)
  testthat::expect_identical(
    parse_certutil_sha256(NA_character_),
    NA_character_
  )
  testthat::expect_identical(parse_certutil_sha256(NULL), NA_character_)
})

testthat::test_that("run_sha256_command runs certutil -hashfile and parses its output", {
  seen <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    sha256_command_path = function(sha_cmd) "C:/Windows/System32/certutil.exe"
  )
  testthat::local_mocked_bindings(
    run = function(command, args, ...) {
      seen$command <- command
      seen$args <- args
      list(
        status = 0L,
        stdout = paste0(
          "SHA256 hash of C:\\file:\r\n",
          abc_sha256,
          "\r\nCertUtil: -hashfile command completed successfully.\r\n"
        )
      )
    },
    .package = "processx"
  )
  testthat::expect_identical(
    run_sha256_command("certutil", "C:/file"),
    abc_sha256
  )
  testthat::expect_identical(seen$command, "C:/Windows/System32/certutil.exe")
  testthat::expect_identical(seen$args, c("-hashfile", "C:/file", "SHA256"))
})

testthat::test_that("compute_sha256 falls back to certutil on Windows only", {
  # R 4.3 or 4.4 on Windows, without digest and without Rtools on PATH.
  testthat::local_mocked_bindings(has_tools_sha256sum = function() FALSE)
  testthat::local_mocked_bindings(
    requireNamespace = function(...) FALSE,
    .package = "base"
  )
  tried <- character(0L)
  testthat::local_mocked_bindings(
    sha256_command_is_trustworthy = function(sha_cmd) {
      tried <<- c(tried, sha_cmd)
      identical(sha_cmd, "certutil")
    },
    run_sha256_command = function(sha_cmd, file_path) {
      if (identical(sha_cmd, "certutil")) abc_sha256 else NA_character_
    }
  )
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  testthat::expect_identical(compute_sha256(abc_test_file()), abc_sha256)
  testthat::expect_identical(tried, c("sha256sum", "shasum", "certutil"))

  tried <- character(0L)
  testthat::local_mocked_bindings(is_windows = function() FALSE)
  testthat::expect_identical(compute_sha256(abc_test_file()), NA_character_)
  testthat::expect_identical(tried, c("sha256sum", "shasum"))
})

testthat::test_that("certutil is trusted exactly where it is the Windows tool", {
  # On Windows it is always there and passes the known-answer test. Where
  # a `certutil` exists elsewhere, it is the NSS tool, which fails it.
  testthat::expect_identical(
    sha256_command_is_trustworthy("certutil"),
    is_windows()
  )
  if (isTRUE(is_windows())) {
    testthat::expect_identical(
      run_sha256_command("certutil", abc_test_file()),
      abc_sha256
    )
  }
})
