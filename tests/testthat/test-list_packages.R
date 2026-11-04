test_that("list packages on absent environment", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  cnd <- testthat::expect_error(
    object = {
      list_packages(
        env_name = "non-existing-env",
        verbose = "silent"
      )
    },
    class = "condathis_list_packages_missing_env"
  )
  testthat::expect_s3_class(cnd, "condathis_list_packages_env_not_found")
  testthat::expect_s3_class(cnd, "condathis_env_not_found")

  create_base_env(verbose = "silent")
  testthat::expect_message(
    object = {
      pkgs_df <- list_packages(verbose = "output")
    },
    regexp = "Retrieved [0-9]+ packages? from environment"
  )
  testthat::expect_s3_class(pkgs_df, "tbl_df")
})

# A micromamba environment directory in the current sandbox, as the
# backend checks for it before it lists the packages: `conda-meta/history`
# and no package record. The tests that mock `native_cmd()` use it, so they
# do not depend on an earlier test (skipped on CRAN and offline) creating
# a real "condathis-env".
create_fake_micromamba_env <- function(env_name) {
  env_dir <- fs::path(
    install_dir_for_backend(micromamba_backend()),
    "envs",
    env_name
  )
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  fs::file_create(fs::path(env_dir, "conda-meta", "history"))
  return(invisible(env_dir))
}

test_that("list_packages raises condathis_cmd_status_error on failure instead of a raw error", {
  # As with list_envs(): rethrow_error_cmd() normally already aborts before
  # list_packages() ever sees a non-zero status. Mock native_cmd() (and
  # backend_probe_env() so the missing-env check does not fire first: the
  # mocked native_cmd() failure would make the probe fail) to exercise the
  # micromamba backend's own handling of that case directly.
  condathis::with_sandbox_dir({
    create_fake_micromamba_env("condathis-env")
    testthat::local_mocked_bindings(
      backend_probe_env = function(...) TRUE,
      native_cmd = function(...) {
        list(status = 1L, stdout = "", stderr = "boom", timeout = FALSE)
      }
    )
    cnd <- testthat::expect_error(
      list_packages(env_name = "condathis-env", verbose = "silent"),
      class = "condathis_cmd_status_error"
    )
    # The backend failure is wrapped with the shared classes.
    testthat::expect_s3_class(cnd, "condathis_list_packages_failed")
    testthat::expect_s3_class(cnd, "condathis_backend_error")
  })
})

testthat::test_that("list_packages parses both micromamba list --json output shapes", {
  # micromamba 2.9.0 changed `list --json` from a bare package array to
  # `{"log_history": [...], "packages": [...]}`. Which binary answers
  # depends on the discovery chain (a system-installed 2.9+ can win over
  # the pinned internal version), so both shapes must parse.
  old_shape <- '[{"base_url":"u","build_number":1,"build_string":"b","channel":"c","dist_name":"d","name":"zlib","platform":"linux-64","version":"1.3"}]'
  new_shape <- paste0('{"log_history":[],"packages":', old_shape, "}")

  condathis::with_sandbox_dir({
    create_fake_micromamba_env("condathis-env")
    for (shape in c(old_shape, new_shape)) {
      testthat::local_mocked_bindings(
        backend_probe_env = function(...) TRUE,
        native_cmd = function(...) {
          list(status = 0L, stdout = shape, stderr = "", timeout = FALSE)
        }
      )
      pkgs <- list_packages(env_name = "condathis-env", verbose = "silent")
      testthat::expect_equal(pkgs$name, "zlib")
      testthat::expect_equal(pkgs$version, "1.3")
      testthat::expect_identical(pkgs$build_number, 1L)
    }
  })
})

# A data frame with the six columns that `backend_list_packages()` must
# return.
stub_packages <- function(n = 2L, build_number = seq_len(n) - 1L) {
  return(data.frame(
    name = paste0("pkg", seq_len(n)),
    version = rep("1.0", n),
    build_number = build_number,
    build_string = rep("h0_0", n),
    channel = rep("conda-forge", n),
    platform = rep("noarch", n),
    extra = rep("x", n),
    stringsAsFactors = FALSE
  ))
}

testthat::test_that("list_packages() never creates an environment", {
  # Regression test: list_packages() created "condathis-env" when it was
  # missing. Decision D3: only the run family and install_packages() create
  # it.
  stub <- local_stub_backend("stub-empty")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-empty"
  )
  for (env_name in c("condathis-env", "other-env")) {
    cnd <- testthat::expect_error(
      list_packages(env_name),
      class = "condathis_list_packages_env_not_found"
    )
    testthat::expect_s3_class(cnd, "condathis_list_packages_missing_env")
    testthat::expect_s3_class(cnd, "condathis_env_not_found")
    testthat::expect_s3_class(cnd, "condathis_error")
    testthat::expect_identical(
      rlang::call_name(conditionCall(cnd)),
      "list_packages"
    )
  }
  testthat::expect_error(
    list_packages(),
    class = "condathis_list_packages_env_not_found"
  )
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 0L)
  testthat::expect_length(fs::dir_ls(fs::path(stub$root, "envs")), 0L)
})

testthat::test_that("list_packages() on a fresh data directory starts no process", {
  # Decision D3: a query works before any environment exists, without
  # creating one and without installing micromamba.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        stop("list_packages() must not start micromamba on a fresh root")
      },
      install_micromamba = function(...) {
        stop("list_packages() must not install micromamba")
      }
    )
    testthat::expect_error(
      list_packages("x", method = "micromamba"),
      class = "condathis_list_packages_env_not_found"
    )
    testthat::expect_error(
      list_packages(),
      class = "condathis_env_not_found"
    )
    testthat::expect_false(
      fs::dir_exists(fs::path(get_condathis_path(), "envs"))
    )
  })
})

testthat::test_that("list_packages() defaults to verbose = 'silent' and always returns visibly", {
  # Regression test: the default was "output", with a "Retrieved N
  # packages" message on every call, and "silent" returned invisibly.
  testthat::expect_identical(formals(list_packages)$verbose, "silent")
  local_stub_backend(
    "stub-pkgs",
    envs = "ea",
    backend_list_packages = function(backend, ...) stub_packages(2L)
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-pkgs"
  )
  testthat::expect_no_message(pkgs <- list_packages("ea"))
  testthat::expect_true(withVisible(list_packages("ea"))$visible)
  testthat::expect_true(
    withVisible(list_packages("ea", verbose = "silent"))$visible
  )
  testthat::expect_message(
    list_packages("ea", verbose = "output"),
    regexp = "Retrieved 2 packages from environment"
  )
})

testthat::test_that("list_packages() pluralizes its message", {
  local_stub_backend(
    "stub-one",
    envs = "ea",
    backend_list_packages = function(backend, ...) stub_packages(1L)
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-one"
  )
  testthat::expect_message(
    list_packages("ea", verbose = "output"),
    regexp = "Retrieved 1 package from environment"
  )
})

testthat::test_that("list_packages() returns a plain tibble with the six columns", {
  local_stub_backend(
    "stub-cols",
    envs = "ea",
    backend_list_packages = function(backend, ...) {
      pkgs <- stub_packages(2L, build_number = c(0, 3))
      rownames(pkgs) <- c("a", "b")
      return(pkgs)
    }
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-cols"
  )
  pkgs <- list_packages("ea")
  testthat::expect_s3_class(
    pkgs,
    c("tbl_df", "tbl", "data.frame"),
    exact = TRUE
  )
  testthat::expect_identical(attr(pkgs, "row.names"), 1:2)
  # A whole-number double build_number is made integer.
  testthat::expect_identical(pkgs$build_number, c(0L, 3L))
  for (column in c("name", "version", "build_string", "channel", "platform")) {
    testthat::expect_type(pkgs[[column]], "character")
  }
  # Columns beyond the six are kept.
  testthat::expect_identical(pkgs$extra, c("x", "x"))
})

testthat::test_that("list_packages() rejects a listing without the six columns", {
  local_stub_backend(
    "stub-no-platform",
    envs = "ea",
    backend_list_packages = function(backend, ...) {
      pkgs <- stub_packages(1L)
      pkgs$platform <- NULL
      return(pkgs)
    }
  )
  local_stub_backend(
    "stub-bad-type",
    envs = "eb",
    backend_list_packages = function(backend, ...) {
      pkgs <- stub_packages(1L)
      pkgs$build_number <- "0"
      return(pkgs)
    }
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() {
      c("stub-no-platform", "stub-bad-type")
    }
  )
  cnd <- testthat::expect_error(
    list_packages("ea"),
    class = "condathis_backend_invalid_return"
  )
  # The same classes as a failed listing, as in list_envs() and
  # validate_env(): one handler for condathis_backend_error catches both.
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_list_packages_failed",
      "condathis_backend_error",
      "condathis_backend_invalid_return",
      "condathis_backend_contract_violation",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_s3_class(cnd$parent, "condathis_backend_invalid_return")
  testthat::expect_match(conditionMessage(cnd$parent), "platform")
  testthat::expect_match(conditionMessage(cnd$parent), "stub-no-platform")
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "list_packages"
  )

  cnd <- testthat::expect_error(
    list_packages("eb"),
    class = "condathis_backend_invalid_return"
  )
  testthat::expect_s3_class(cnd, "condathis_list_packages_failed")
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_match(conditionMessage(cnd$parent), "build_number")
})

testthat::test_that("list_packages() wraps a backend failure with the shared classes", {
  local_stub_backend(
    "stub-boom",
    envs = "ea",
    backend_list_packages = function(backend, ...) {
      rlang::abort("listing failed", class = "stub_boom")
    }
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-boom"
  )
  cnd <- testthat::expect_error(
    list_packages("ea"),
    class = "condathis_list_packages_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "list_packages"
  )
})

testthat::test_that("list_packages() lists when the existence probe fails", {
  # Rule R5: a failed probe is not "absent". The listing runs, and its own
  # error (or result) is what the user sees.
  stub <- local_stub_backend(
    "stub-noprobe",
    backend_env_exists = function(backend, ...) {
      rlang::abort("probe failed", class = "stub_probe_boom")
    },
    backend_list_packages = function(backend, ...) stub_packages(1L)
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-noprobe"
  )
  testthat::expect_warning(
    pkgs <- list_packages("ea", method = "stub-noprobe"),
    class = "condathis_backend_query_failed"
  )
  testthat::expect_identical(pkgs$name, "pkg1")
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 1L)
})

testthat::test_that("list_packages() passes a single verbose string to the backend", {
  stub <- local_stub_backend(
    "stub-r4",
    envs = "ea",
    backend_list_packages = function(backend, ...) stub_packages(1L)
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-r4"
  )
  suppressMessages({
    list_packages("ea", verbose = TRUE)
    list_packages("ea", verbose = FALSE)
    list_packages("ea", verbose = "full")
  })
  listings <- stub_calls(stub, "backend_list_packages")
  testthat::expect_identical(
    vapply(listings, function(x) x$args$verbose, character(1L)),
    c("output", "silent", "full")
  )
  cnd <- testthat::expect_error(
    list_packages("ea", verbose = "bogus"),
    class = "condathis_invalid_verbose"
  )
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "list_packages"
  )
})
