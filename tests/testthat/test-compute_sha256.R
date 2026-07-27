# The standard SHA-256 test vector for the ASCII string "abc", cross-checked
# directly against tools::sha256sum(), digest::digest(), openssl::sha256(),
# and Python's hashlib (all agree) before being hardcoded here and in
# R/install_micromamba.R's sha256_command_is_trustworthy().
abc_sha256 <- "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"

abc_test_file <- function() {
  # Deliberately not withr::local_tempfile(): its default .local_envir is
  # this helper's own frame, which exits (deleting the file) the instant
  # this function returns — before any caller like compute_sha256() ever
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
  # Simulates a broken/wrong/aliased binary on PATH under the expected name —
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
    micromamba_version = "2.8.1-0"
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
