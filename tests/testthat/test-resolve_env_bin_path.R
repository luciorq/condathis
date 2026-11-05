test_that("resolve_env_bin_path() does not join an absolute path to the environment", {
  # On Windows, joining a long absolute command to a long environment
  # directory exceeded PATH_MAX and made `fs::path()` abort.
  env_dir <- withr::local_tempdir(pattern = strrep("e", 100L))
  tool_dir <- withr::local_tempdir(pattern = strrep("t", 100L))
  tool_name <- if (isTRUE(is_windows())) "tool.exe" else "tool"
  tool <- fs::path(tool_dir, tool_name)
  fs::file_create(tool)

  testthat::expect_identical(
    as.character(resolve_env_bin_path(env_dir, as.character(tool))),
    as.character(tool)
  )
  testthat::expect_null(
    resolve_env_bin_path(env_dir, as.character(fs::path(tool_dir, "missing")))
  )
})

test_that("resolve_env_bin_path() tries PATHEXT extensions for a path without one on Windows", {
  testthat::skip_if_not(isTRUE(is_windows()))
  tool_dir <- withr::local_tempdir()
  tool <- fs::path(tool_dir, "tool.exe")
  fs::file_create(tool)
  resolved <- resolve_env_bin_path(
    withr::local_tempdir(),
    as.character(fs::path(tool_dir, "tool"))
  )
  testthat::expect_identical(
    tolower(as.character(resolved)),
    tolower(as.character(tool))
  )
})
