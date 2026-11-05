test_that("get_env_dir() works", {
  env_name <- "condathis-get-test-env"
  testthat::expect_equal(
    fs::path(get_install_dir(method = "micromamba")$path, "envs", env_name),
    get_env_dir(env_name)
  )
})

test_that("get_env_dir() validates env_name", {
  testthat::expect_error(
    object = get_env_dir(env_name = c("a", "b")),
    class = "condathis_get_env_dir_invalid_env_name"
  )
  testthat::expect_error(
    object = get_env_dir(env_name = NA),
    class = "condathis_get_env_dir_invalid_env_name"
  )
  testthat::expect_error(
    object = get_env_dir(env_name = 123),
    class = "condathis_get_env_dir_invalid_env_name"
  )
})

test_that("get_env_dir() returns an fs_path from the owning backend", {
  # Regression test: get_env_dir() returned whatever the backend returned,
  # although its docs promised a path.
  stub <- local_stub_backend(
    "stub-chr",
    envs = "ea",
    backend_get_env_dir = function(backend, env_name = "condathis-env") {
      # A plain string, not an fs_path.
      return(as.character(fs::path(stub_root, "envs", env_name)))
    }
  )
  stub_root <- stub$root
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-chr"
  )
  env_dir <- get_env_dir("ea")
  testthat::expect_s3_class(env_dir, "fs_path")
  testthat::expect_identical(
    as.character(env_dir),
    as.character(fs::path(stub$root, "envs", "ea"))
  )
})

test_that("get_env_dir() rejects a path that is not absolute", {
  local_stub_backend(
    "stub-relative",
    envs = "ea",
    backend_get_env_dir = function(backend, env_name = "condathis-env") {
      return(fs::path("envs", env_name))
    }
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-relative"
  )
  cnd <- testthat::expect_error(
    get_env_dir("ea"),
    class = "condathis_backend_invalid_return"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
  testthat::expect_s3_class(cnd, "condathis_error")
  # Regression test: for an existing environment, the owner lookup reads
  # its directory first, and the error named the internal
  # env_dir_for_backend().
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "get_env_dir"
  )
})

test_that("get_env_dir() names the user's call for an invalid path", {
  # Regression test: the error named the internal env_dir_for_backend().
  # "new-env" does not exist, so the owner lookup does not read its
  # directory and the check in get_env_dir() is the one that fails.
  local_stub_backend(
    "stub-relative",
    backend_get_env_dir = function(backend, env_name = "condathis-env") {
      return(fs::path("envs", env_name))
    }
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-relative"
  )
  cnd <- testthat::expect_error(
    get_env_dir("new-env"),
    class = "condathis_backend_invalid_return"
  )
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "get_env_dir"
  )
  testthat::expect_match(conditionMessage(cnd), "stub-relative")
})

test_that("get_env_dir() on a fresh data directory starts no process", {
  # Decision D3: a query works before any environment exists, without
  # creating one and without installing micromamba. Only the backend's data
  # directory is created.
  condathis::with_sandbox_dir({
    # Count the calls: the owner lookup catches a failed probe and only
    # warns (rule R5), so an error alone would not fail this test.
    started <- new.env(parent = emptyenv())
    started$native_cmd <- 0L
    started$install <- 0L
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        started$native_cmd <- started$native_cmd + 1L
        stop("get_env_dir() must not start micromamba on a fresh root")
      },
      install_micromamba = function(...) {
        started$install <- started$install + 1L
        stop("get_env_dir() must not install micromamba")
      }
    )
    root <- fs::path_real(get_install_dir(method = "micromamba")$path)
    testthat::expect_no_warning(env_dir <- get_env_dir("x"))
    testthat::expect_identical(
      as.character(env_dir),
      as.character(fs::path(root, "envs", "x"))
    )
    testthat::expect_no_warning(env_dir <- get_env_dir())
    testthat::expect_identical(
      as.character(env_dir),
      as.character(fs::path(root, "envs", "condathis-env"))
    )
    testthat::expect_identical(started$native_cmd, 0L)
    testthat::expect_identical(started$install, 0L)
    testthat::expect_false(fs::dir_exists(fs::path(root, "envs")))
  })
})
