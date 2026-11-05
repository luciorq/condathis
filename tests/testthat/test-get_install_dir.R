# Mocking get_sys_arch to return specific values
mock_get_sys_arch <- function(value) {
  function() value
}

# get_condathis_path()
testthat::test_that("get_sys_arch returns correct path for each os", {
  testthat::with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Linux-x86_64"),
    expect_equal(
      get_condathis_path(),
      fs::path(tools::R_user_dir("condathis", which = "data"))
    )
  )

  testthat::with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Darwin-x86_64"),
    testthat::expect_equal(
      get_condathis_path(),
      withr::with_envvar(
        new = list(
          `XDG_DATA_HOME` = fs::path_home(".local", "share")
        ),
        code = {
          fs::path(tools::R_user_dir("condathis", which = "data"))
        }
      )
    )
  )

  testthat::with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Darwin-arm64"),
    testthat::expect_equal(
      get_condathis_path(),
      withr::with_envvar(
        new = list(
          `XDG_DATA_HOME` = fs::path_home(".local", "share")
        ),
        code = {
          fs::path(tools::R_user_dir("condathis", which = "data"))
        }
      )
    )
  )

  testthat::with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Unknown-arch"),
    testthat::expect_equal(
      get_condathis_path(),
      fs::path(tools::R_user_dir("condathis", which = "data"))
    )
  )
})

testthat::test_that("get_install_dir() returns a tibble with compact integer row names", {
  # Regression test: vapply() kept the backend names, so the result had
  # character row names.
  stub <- local_stub_backend("stub-dir")
  dirs <- get_install_dir(method = "stub-dir")
  testthat::expect_s3_class(
    dirs,
    c("tbl_df", "tbl", "data.frame"),
    exact = TRUE
  )
  testthat::expect_identical(attr(dirs, "row.names"), 1L)
  testthat::expect_identical(dirs$backend, "stub-dir")
  testthat::expect_identical(dirs$path, as.character(stub$root))
  testthat::expect_null(names(dirs$path))
})

testthat::test_that("get_install_dir(method = 'auto') reports an unavailable backend, in priority order", {
  # Rule R6: availability only decides where a new environment goes.
  on_stub <- local_stub_backend("stub-on")
  off_stub <- local_stub_backend("stub-off", available = FALSE)
  # Not the alphabetical order, so that the test fails for code that sorts
  # the backends.
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-on", "stub-off")
  )
  dirs <- get_install_dir()
  testthat::expect_identical(dirs$backend, c("stub-on", "stub-off"))
  testthat::expect_identical(
    dirs$path,
    as.character(c(on_stub$root, off_stub$root))
  )
  testthat::expect_identical(attr(dirs, "row.names"), 1:2)
})

testthat::test_that("get_install_dir() handles a failing backend", {
  local_stub_backend(
    "stub-bad",
    backend_get_install_dir = function(backend) {
      rlang::abort("no data directory", class = "stub_boom")
    }
  )
  good <- local_stub_backend("stub-good")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-bad", "stub-good")
  )
  testthat::expect_warning(
    dirs <- get_install_dir(),
    class = "condathis_backend_query_failed"
  )
  testthat::expect_identical(dirs$backend, "stub-good")
  testthat::expect_identical(dirs$path, as.character(good$root))

  cnd <- testthat::expect_error(
    get_install_dir(method = "stub-bad"),
    class = "condathis_get_install_dir_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_s3_class(cnd$parent, "stub_boom")
})

testthat::test_that("get_install_dir() rejects a data directory that does not exist", {
  local_stub_backend(
    "stub-gone",
    backend_get_install_dir = function(backend) {
      return(fs::path(tempdir(), "condathis-no-such-dir", "root"))
    }
  )
  local_stub_backend(
    "stub-relative",
    backend_get_install_dir = function(backend) "relative/root"
  )
  for (name in c("stub-gone", "stub-relative")) {
    cnd <- testthat::expect_error(
      get_install_dir(method = name),
      class = "condathis_backend_invalid_return"
    )
    testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
  }
})

testthat::test_that("get_install_dir() on a fresh data directory creates only the root", {
  # Decision D3: no environment, no micromamba install, no process.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        stop("get_install_dir() must not start micromamba")
      },
      install_micromamba = function(...) {
        stop("get_install_dir() must not install micromamba")
      }
    )
    root <- get_condathis_path()
    testthat::expect_false(fs::dir_exists(root))
    dirs <- get_install_dir(method = "micromamba")
    testthat::expect_identical(dirs$backend, "micromamba")
    testthat::expect_identical(
      dirs$path,
      as.character(fs::path_real(root))
    )
    testthat::expect_true(fs::dir_exists(root))
    # The root is empty: no `envs/`, no environment, no micromamba.
    testthat::expect_length(fs::dir_ls(root, all = TRUE), 0L)
  })
})
