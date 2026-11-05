test_that("env_exists() defaults to env_name = 'condathis-env'", {
  # Regression test: env_exists() had no default and failed without
  # env_name, unlike every other function.
  testthat::expect_identical(formals(env_exists)$env_name, "condathis-env")
  stub <- local_stub_backend("stub-default", envs = "condathis-env")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-default"
  )
  testthat::expect_true(env_exists())
  probes <- stub_calls(stub, "backend_env_exists")
  testthat::expect_identical(probes[[1L]]$args$env_name, "condathis-env")
})

test_that("env_exists rejects invalid env_name instead of silently returning FALSE", {
  testthat::expect_error(
    env_exists(NULL),
    class = "condathis_env_exists_invalid_env_name"
  )
  testthat::expect_error(
    env_exists(NA),
    class = "condathis_env_exists_invalid_env_name"
  )
  testthat::expect_error(
    env_exists(NA_character_),
    class = "condathis_env_exists_invalid_env_name"
  )
  testthat::expect_error(
    env_exists(c("a", "b")),
    class = "condathis_env_exists_invalid_env_name"
  )
  testthat::expect_error(
    env_exists(42),
    class = "condathis_env_exists_invalid_env_name"
  )
  cnd <- testthat::expect_error(env_exists(42), class = "condathis_error")
  testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
})

test_that("env_exists() validates verbose and names the user's call", {
  # Regression test: an invalid verbose made the probe fail, and the
  # failure was read as FALSE.
  stub <- local_stub_backend("stub-verbose", envs = "x")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-verbose"
  )
  cnd <- testthat::expect_error(
    env_exists("x", verbose = "bogus"),
    class = "condathis_invalid_verbose"
  )
  testthat::expect_s3_class(cnd, "condathis_invalid_arg")
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "env_exists")
  # Rule R2: no backend was asked.
  testthat::expect_length(stub_calls(stub), 0L)
})

test_that("env_exists() passes a single verbose string to the backend", {
  stub <- local_stub_backend("stub-r4", envs = "x")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-r4"
  )
  for (verbose in list("silent", "output", "cmd", "full", TRUE, FALSE)) {
    testthat::expect_true(env_exists("x", verbose = verbose))
  }
  probes <- stub_calls(stub, "backend_env_exists")
  # The user's level, not the internal one: "cmd" must reach the backend,
  # or the command line is not shown, as ?env_exists promises.
  testthat::expect_identical(
    vapply(probes, function(x) x$args$verbose, character(1L)),
    c("silent", "output", "cmd", "full", "output", "silent")
  )
})

test_that("env_exists() aborts when the backend named by method fails", {
  # Regression test: every backend error was read as FALSE, also for an
  # explicit method.
  local_stub_backend(
    "stub-boom",
    backend_env_exists = function(backend, ...) {
      rlang::abort("listing failed", class = "stub_boom")
    }
  )
  cnd <- testthat::expect_error(
    env_exists("x", method = "stub-boom"),
    class = "condathis_env_exists_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "env_exists")
})

test_that("env_exists() rejects a backend answer that is not TRUE or FALSE", {
  local_stub_backend(
    "stub-yes",
    backend_env_exists = function(backend, ...) "yes"
  )
  cnd <- testthat::expect_error(
    env_exists("x", method = "stub-yes"),
    class = "condathis_env_exists_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
  testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
})

test_that("env_exists(method = 'auto') skips a failing backend with a warning", {
  local_stub_backend(
    "stub-bad",
    backend_env_exists = function(backend, ...) {
      rlang::abort("listing failed", class = "stub_boom")
    }
  )
  local_stub_backend("stub-good", envs = "ea")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-bad", "stub-good")
  )
  testthat::expect_warning(
    found <- env_exists("ea"),
    class = "condathis_backend_query_failed"
  )
  testthat::expect_true(found)
  testthat::expect_warning(
    missing_env <- env_exists("nope"),
    class = "condathis_backend_query_failed"
  )
  testthat::expect_false(missing_env)
})

test_that("env_exists(method = 'auto') aborts when every backend fails", {
  local_stub_backend(
    "stub-bad-1",
    backend_env_exists = function(backend, ...) rlang::abort("one")
  )
  local_stub_backend(
    "stub-bad-2",
    backend_env_exists = function(backend, ...) rlang::abort("two")
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-bad-1", "stub-bad-2")
  )
  cnd <- testthat::expect_error(
    env_exists("x"),
    class = "condathis_env_exists_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_error")
})

test_that("env_exists(method = 'auto') asks every backend in priority order, available or not", {
  order_log <- new.env()
  order_log$names <- character(0L)
  probe_as <- function(nm) {
    force(nm)
    return(function(backend, env_name, ...) {
      order_log$names <- c(order_log$names, nm)
      return(identical(nm, "stub-off") && identical(env_name, "ea"))
    })
  }
  local_stub_backend("stub-on", backend_env_exists = probe_as("stub-on"))
  local_stub_backend(
    "stub-off",
    available = FALSE,
    backend_env_exists = probe_as("stub-off")
  )
  # Not the alphabetical order: the old code asked the backends in
  # alphabetical order.
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-on", "stub-off")
  )
  # An environment of an unavailable backend still exists (rule R6).
  testthat::expect_true(env_exists("ea"))
  testthat::expect_identical(order_log$names, c("stub-on", "stub-off"))
})

test_that("env_exists() on a fresh data directory starts no process", {
  # Decision D3: a query works before any environment exists, without
  # creating one and without installing micromamba.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        stop("env_exists() must not start micromamba on a fresh root")
      },
      install_micromamba = function(...) {
        stop("env_exists() must not install micromamba")
      }
    )
    testthat::expect_false(env_exists("x", method = "micromamba"))
    testthat::expect_false(env_exists(method = "micromamba"))
    testthat::expect_false(env_exists("x"))
    # Nothing was created: no environment directory, no data directory.
    testthat::expect_false(fs::dir_exists(get_condathis_path()))
  })
})
