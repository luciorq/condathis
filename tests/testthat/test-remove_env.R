rlang_tail <- c("rlang_error", "error", "condition")

catch_error <- function(expr) {
  return(rlang::catch_cnd(expr, classes = "error"))
}

# A stub backend (helper-stub-backend.R) that is the only backend condathis
# sees in this test, so no test here reaches micromamba.
local_remove_stub <- function(
  name,
  envs = character(0L),
  ...,
  envir = parent.frame()
) {
  stub <- local_stub_backend(name, ..., envs = envs, envir = envir)
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() name,
    .env = envir
  )
  return(stub)
}

testthat::test_that("remove_env validates its arguments before any backend call", {
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  cnd <- catch_error(remove_env("e", verbose = "bogus"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_invalid_verbose",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_identical(
    conditionCall(cnd),
    quote(remove_env("e", verbose = "bogus"))
  )
  testthat::expect_s3_class(
    catch_error(remove_env("e", method = "no-such-backend")),
    "condathis_invalid_method_arg"
  )
  cnd <- catch_error(remove_env("../e"))
  testthat::expect_s3_class(cnd, "condathis_remove_env_invalid_env_name")
  testthat::expect_s3_class(cnd, "condathis_error")
})

testthat::test_that("remove_env aborts for a missing environment before the backend is called", {
  # Regression test: remove_env() dispatched without an existence check, so
  # each backend raised its own class (a stub raised `stub_missing`).
  stub <- local_remove_stub(
    "stub-remove-missing",
    backend_remove_env = function(...) {
      rlang::abort("no such env", class = "stub_missing")
    }
  )
  cnd <- catch_error(
    remove_env("never-created", method = "stub-remove-missing")
  )
  # The new class and the old one.
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_remove_env_env_not_found",
      "condathis_error_env_remove",
      "condathis_env_not_found",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_false(inherits(cnd, "stub_missing"))
  testthat::expect_length(stub_calls(stub, "backend_remove_env"), 0L)
})

testthat::test_that("remove_env passes a failed probe on to the backend", {
  # Rule R5: a failed probe (`NA`) is not read as "absent". resolve_backend()
  # is mocked to return the stub, so find_owning_backends() does not abort
  # first; the backend gets the call and reports the real error.
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  stub <- local_stub_backend(
    "stub-remove-pass",
    backend_env_exists = stub_boom,
    backend_remove_env = function(...) {
      rlang::abort("remove failed", class = "stub_remove_failed")
    }
  )
  testthat::local_mocked_bindings(
    resolve_backend = function(...) {
      return(list(backend = stub$backend, name = "stub-remove-pass"))
    }
  )
  cnd <- catch_error(remove_env("probe-env", verbose = "silent"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_remove_env_failed",
      "condathis_backend_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_s3_class(cnd$parent, "stub_remove_failed")
  testthat::expect_false(rlang::cnd_inherits(cnd, "condathis_env_not_found"))
  testthat::expect_length(stub_calls(stub, "backend_remove_env"), 1L)
})

testthat::test_that("remove_env aborts for a missing micromamba environment without a process", {
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("native_cmd() must not be called"),
      install_micromamba = function(...) {
        stop("install_micromamba() must not be called")
      }
    )
    testthat::expect_error(
      remove_env("never-created", method = "micromamba"),
      class = "condathis_remove_env_env_not_found"
    )
  })
})

testthat::test_that("remove_env passes one verbose string to the backend, and reports success by default", {
  # Decision D5: remove_env() changes state, so it defaults to "output".
  stub <- local_remove_stub("stub-remove-verbose", envs = c("a", "b", "c"))
  testthat::expect_message(
    res <- remove_env("a"),
    regexp = "Environment .*a.* successfully removed"
  )
  testthat::expect_s3_class(res, "condathis_result")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$env_name, "a")
  # cmd-field: the stub reports no command line.
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_no_message(remove_env("b", verbose = FALSE))
  testthat::expect_no_message(remove_env("c", verbose = "silent"))
  testthat::expect_identical(
    lapply(stub_calls(stub, "backend_remove_env"), function(x) x$args$verbose),
    list("output", "silent", "silent")
  )
})

testthat::test_that("remove_env re-raises a backend error with its own classes", {
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  local_remove_stub(
    "stub-remove-boom",
    envs = "boom-env",
    backend_remove_env = stub_boom
  )
  cnd <- catch_error(remove_env("boom-env", verbose = "silent"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_remove_env_failed",
      "condathis_backend_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_s3_class(cnd$parent, "stub_boom")
})

testthat::test_that("remove_env reads the backend result by exact name", {
  # Regression test: a backend returning TRUE (rattlerthis does) made
  # remove_env() fail after the environment was removed.
  local_remove_stub(
    "stub-remove-result",
    envs = c("true-env", "bad-env"),
    backend_remove_env = function(backend, env_name = "condathis-env", ...) {
      if (identical(env_name, "bad-env")) {
        return(list(status = 2L))
      }
      return(TRUE)
    }
  )
  res <- remove_env("true-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, NA_character_)
  testthat::expect_error(
    remove_env("bad-env", verbose = "silent"),
    class = "condathis_remove_env_failed"
  )
})

testthat::test_that("remove_env errors when the environment does not exist", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  cnd <- catch_error(
    remove_env(env_name = "definitely-does-not-exist-condathis-test-env")
  )
  testthat::expect_s3_class(cnd, "condathis_error_env_remove")
  testthat::expect_s3_class(cnd, "condathis_remove_env_env_not_found")
  testthat::expect_s3_class(cnd, "condathis_env_not_found")
})

testthat::test_that("remove_env leaves a directory alone that is not an environment", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  # A directory can exist under the envs root without micromamba tracking
  # it as an environment (for example left over from an interrupted
  # create). remove_env() checks existence before the backend runs, so it
  # aborts and does not delete the directory; create_env() deletes it
  # before it creates the environment.
  stray_dir <- get_env_dir("stray-dir-remove-test-env")
  fs::dir_create(stray_dir)
  withr::defer(fs::dir_delete(stray_dir))
  testthat::expect_true(fs::dir_exists(stray_dir))

  testthat::expect_error(
    remove_env("stray-dir-remove-test-env", verbose = "silent"),
    class = "condathis_remove_env_env_not_found"
  )
  testthat::expect_true(fs::dir_exists(stray_dir))
})

testthat::test_that("remove_env removes a real environment", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  create_env(env_name = "condathis-remove-test-env", verbose = "silent")
  testthat::expect_true(env_exists("condathis-remove-test-env"))

  px_res <- remove_env(
    env_name = "condathis-remove-test-env",
    verbose = "silent"
  )
  testthat::expect_s3_class(px_res, "condathis_result")
  testthat::expect_equal(px_res$status, 0L)
  testthat::expect_equal(px_res$env_name, "condathis-remove-test-env")
  testthat::expect_false(env_exists("condathis-remove-test-env"))
  testthat::expect_false(fs::dir_exists(get_env_dir(
    "condathis-remove-test-env"
  )))
})

testthat::test_that("remove_env reports success via message at verbose = 'output'", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  create_env(
    env_name = "condathis-remove-verbose-test-env",
    verbose = "silent"
  )

  testthat::expect_message(
    remove_env(
      env_name = "condathis-remove-verbose-test-env",
      verbose = "output"
    ),
    regexp = "successfully removed"
  )
  testthat::expect_false(env_exists("condathis-remove-verbose-test-env"))
})

testthat::test_that("remove_env emits no message at verbose = 'silent'", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  create_env(
    env_name = "condathis-remove-silent-test-env",
    verbose = "silent"
  )

  testthat::expect_no_message(
    remove_env(
      env_name = "condathis-remove-silent-test-env",
      verbose = "silent"
    )
  )
})

testthat::test_that("remove_env() warns about the pre-unlink scripts it did not run", {
  # The default remove of condathis does not run pre-unlink scripts, and
  # reports the packages that have one.
  stub <- local_stub_backend(
    "stub-remove-scripts",
    default_root = TRUE,
    backend_remove_env = NULL,
    envs = "scripts-env"
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-remove-scripts"
  )
  env_dir <- fs::path(
    backend_root_dir("stub-remove-scripts"),
    "envs",
    "scripts-env"
  )
  script_dir <- if (isTRUE(is_windows())) "Scripts" else "bin"
  script_ext <- if (isTRUE(is_windows())) "bat" else "sh"
  script <- paste0(".plink-pre-unlink.", script_ext)
  fs::dir_create(fs::path(env_dir, script_dir))
  fs::file_create(fs::path(env_dir, script_dir, script))
  jsonlite::write_json(
    list(
      name = "plink",
      version = "1.0",
      build = "0",
      subdir = "noarch",
      files = list(paste0(script_dir, "/", script))
    ),
    fs::path(env_dir, "conda-meta", "plink-1.0-0.json"),
    auto_unbox = TRUE
  )
  msgs <- character(0L)
  cnd <- NULL
  res <- withCallingHandlers(
    remove_env("scripts-env", verbose = "output"),
    message = function(m) {
      msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
      invokeRestart("muffleMessage")
    },
    warning = function(w) {
      cnd <<- w
      invokeRestart("muffleWarning")
    }
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_false(fs::dir_exists(env_dir))
  testthat::expect_match(
    paste(msgs, collapse = "\n"),
    "successfully removed",
    fixed = TRUE
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_remove_env_link_scripts_skipped",
      "condathis_link_scripts_skipped",
      "condathis_warning"
    )
  )
  testthat::expect_identical(cnd$backend, "stub-remove-scripts")
  testthat::expect_identical(cnd$packages, "plink")
  testthat::expect_identical(cnd$scripts$script, "pre-unlink")
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(
    message,
    "Backend stub-remove-scripts did not run the pre-unlink scripts of plink before it removed them.",
    fixed = TRUE
  )
  # Removing again with method = "micromamba" is no help: the hint is only
  # for create_env() and install_packages().
  testthat::expect_no_match(message, "method = \"micromamba\"", fixed = TRUE)

  # Without such scripts, no warning.
  local_stub_backend(
    "stub-remove-scripts",
    default_root = TRUE,
    backend_remove_env = NULL,
    envs = "plain-env"
  )
  testthat::expect_no_warning(remove_env("plain-env", verbose = "silent"))
})
