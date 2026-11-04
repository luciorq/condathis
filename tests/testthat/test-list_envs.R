testthat::test_that("list_envs returns a tibble with backend/env_name/path", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_base_env(verbose = "silent")
  envs <- list_envs(verbose = "silent")
  testthat::expect_s3_class(envs, "data.frame")
  testthat::expect_named(envs, c("backend", "env_name", "path"))
  testthat::expect_type(envs$env_name, "character")
  testthat::expect_true(all(envs$backend == "micromamba"))
})

testthat::test_that("condathis_env_names matches the install root as an anchored literal prefix", {
  # Two regressions covered: the root was once used as a regex pattern
  # (the `.` in a real install path matched any character), and later as
  # an unanchored literal substring (any path merely *containing* the
  # root somewhere inside it - e.g. a backup copy - was claimed as
  # condathis-owned). It must be an anchored literal prefix.
  root <- "/root/a.b/condathis"
  envs <- c(
    "/root/a.b/condathis", # the root itself -> not a child -> dropped
    "/root/a.b/condathis/envs/foo", # a real child -> kept
    "/root/aXb/condathis/envs/decoy", # NOT under root; `.` regex would match
    "/backup/root/a.b/condathis/envs/copy", # contains root as infix only
    "/root/a.b/condathis-other/envs/sibling" # shares the prefix, no separator
  )
  result <- condathis_env_names(envs, root)
  testthat::expect_equal(result, "foo")
  testthat::expect_false("decoy" %in% result)
  testthat::expect_false("copy" %in% result)
  testthat::expect_false("sibling" %in% result)
  testthat::expect_false("condathis" %in% result)
})

testthat::test_that("list_envs excludes the condathis root pseudo-environment", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_base_env(verbose = "silent")
  envs <- list_envs(verbose = "silent")
  testthat::expect_false("condathis" %in% envs$env_name)
  testthat::expect_true("condathis-env" %in% envs$env_name)
})

testthat::test_that("list_envs reflects environment creation and removal", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  condathis::with_sandbox_dir({
    testthat::expect_false(
      "list-envs-test-env" %in% list_envs(verbose = "silent")$env_name
    )

    create_env(env_name = "list-envs-test-env", verbose = "silent")
    testthat::expect_true(
      "list-envs-test-env" %in% list_envs(verbose = "silent")$env_name
    )

    remove_env("list-envs-test-env", verbose = "silent")
    testthat::expect_false(
      "list-envs-test-env" %in% list_envs(verbose = "silent")$env_name
    )
  })
})

testthat::test_that("list_envs raises condathis_cmd_status_error on failure instead of returning a number", {
  # `rethrow_error_cmd()` normally already aborts before list_envs() ever
  # sees a non-zero status (native_cmd()'s default error = "cancel" makes
  # the underlying processx::run() throw, not return, on failure) - mock
  # native_cmd() directly so it *returns* a non-zero status instead, to
  # exercise list_envs()'s own defensive handling of that case.
  condathis::with_sandbox_dir({
    # The micromamba backend lists nothing, without starting micromamba,
    # while `<root>/envs` has no directory. One directory makes it run the
    # mocked command.
    fs::dir_create(fs::path(get_condathis_path(), "envs", "x"))
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        list(status = 1L, stdout = "", stderr = "boom", timeout = FALSE)
      }
    )
    cnd <- testthat::expect_error(
      list_envs(method = "micromamba", verbose = "silent"),
      class = "condathis_cmd_status_error"
    )
    # The backend failure is wrapped with the shared classes.
    testthat::expect_s3_class(cnd, "condathis_list_envs_failed")
    testthat::expect_s3_class(cnd, "condathis_backend_error")
    testthat::expect_s3_class(cnd, "condathis_error")
  })
})

testthat::test_that("list_envs echoes the underlying command at verbose = 'full'", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_base_env(verbose = "silent")
  captured <- testthat::capture_output(list_envs(verbose = "full"))
  testthat::expect_true(stringr::str_detect(
    captured,
    stringr::fixed("Running")
  ))
})

testthat::test_that("realize_env_paths tolerates stale and vanished environment paths", {
  # Regression test: a vectorized fs::path_real() errors ENOENT on the
  # first stale registry entry (e.g. ~/.conda/environments.txt), which
  # aborted list_envs() for every environment at once and made
  # env_exists() report existing environments as absent through
  # backend_has_env()'s never-errors coercion.
  real_dir <- withr::local_tempdir()
  stale_path <- fs::path(real_dir, "definitely-gone-subdir", "old-env")
  out <- realize_env_paths(c(as.character(real_dir), as.character(stale_path)))
  testthat::expect_equal(out, as.character(fs::path_real(real_dir)))
  # All-stale input: empty result, no error.
  testthat::expect_equal(
    realize_env_paths(as.character(stale_path)),
    character(0L)
  )
})

testthat::test_that("condathis_env_names keeps a real environment named 'condathis'", {
  # Regression test: the root prefix was dropped by basename, which also
  # dropped `<root>/envs/condathis`. That environment then looked absent and
  # the stale-directory cleanup of create_env()/remove_env() deleted it.
  root <- "/data/R/condathis"
  envs <- c(
    "/data/R/condathis",
    "/data/R/condathis/envs/condathis",
    "/data/R/condathis/envs/other",
    "/data/R/condathis/pkgs/condathis"
  )
  testthat::expect_equal(
    condathis_env_names(envs, root),
    c("condathis", "other")
  )
  # Backslash paths (Windows fallback when a path cannot be realized).
  testthat::expect_equal(
    condathis_env_names(
      "C:\\data\\R\\condathis\\envs\\win-env",
      "C:/data/R/condathis"
    ),
    "win-env"
  )
})

testthat::test_that("an environment named 'condathis' survives create and remove", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    create_env(env_name = "condathis", verbose = "silent")
    testthat::expect_true(env_exists("condathis"))
    testthat::expect_true(
      "condathis" %in% list_envs(verbose = "silent")$env_name
    )
    remove_env("condathis", verbose = "silent")
    testthat::expect_false(env_exists("condathis"))
  })
})

testthat::test_that("list_envs() validates verbose and names the user's call", {
  stub <- local_stub_backend("stub-verbose", envs = "ea")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-verbose"
  )
  cnd <- testthat::expect_error(
    list_envs(verbose = "bogus"),
    class = "condathis_invalid_verbose"
  )
  testthat::expect_s3_class(cnd, "condathis_invalid_arg")
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "list_envs")
  testthat::expect_length(stub_calls(stub), 0L)
})

testthat::test_that("list_envs() passes a single verbose string to the backend", {
  stub <- local_stub_backend("stub-r4", envs = "ea")
  for (verbose in list("silent", "output", "cmd", "full", TRUE, FALSE)) {
    list_envs(method = "stub-r4", verbose = verbose)
  }
  listings <- stub_calls(stub, "backend_list_envs")
  # The user's level, not the internal one: "cmd" must reach the backend,
  # or the command line is not shown, as ?list_envs promises.
  testthat::expect_identical(
    vapply(listings, function(x) x$args$verbose, character(1L)),
    c("silent", "output", "cmd", "full", "output", "silent")
  )
})

testthat::test_that("list_envs(verbose = 'cmd') shows the command, 'output' hides the JSON", {
  # Regression test: list_envs() passed the internal level, which turns
  # "cmd" into "spinner", so the command line was never shown.
  condathis::with_sandbox_dir({
    env_dir <- fs::path(get_condathis_path(), "envs", "x")
    fs::dir_create(fs::path(env_dir, "conda-meta"))
    listing_json <- as.character(jsonlite::toJSON(
      list(envs = as.character(env_dir)),
      auto_unbox = FALSE
    ))
    record <- new.env(parent = emptyenv())
    record$calls <- list()
    testthat::local_mocked_bindings(
      native_cmd = function(conda_cmd, conda_args = NULL, ..., verbose = NULL) {
        record$calls[[length(record$calls) + 1L]] <- list(
          conda_args = conda_args,
          verbose = parse_strategy_verbose(verbose)
        )
        return(list(
          status = 0L,
          stdout = listing_json,
          stderr = "",
          timeout = FALSE
        ))
      }
    )
    for (level in c("cmd", "full", "output")) {
      envs <- list_envs(method = "micromamba", verbose = level)
      testthat::expect_identical(envs$env_name, "x")
    }
    testthat::expect_length(record$calls, 3L)
    cmd_call <- record$calls[[1L]]
    full_call <- record$calls[[2L]]
    output_call <- record$calls[[3L]]
    # "cmd" and "full" echo the command line.
    testthat::expect_true(cmd_call$verbose$cmd)
    testthat::expect_true(full_call$verbose$cmd)
    # "output" keeps the JSON listing off the console.
    testthat::expect_false(output_call$verbose$cmd)
    testthat::expect_false(native_cmd_echo(
      output = output_call$verbose$output,
      conda_args = output_call$conda_args,
      stderr = "|",
      encoding = "utf-8"
    ))
  })
})

testthat::test_that("list_envs() returns a tibble with compact integer row names", {
  # Regression test: vapply() kept the environment names, so the result
  # had character row names.
  local_stub_backend("stub-rows", envs = c("ea", "eb", "ec"))
  envs <- list_envs(method = "stub-rows")
  testthat::expect_s3_class(
    envs,
    c("tbl_df", "tbl", "data.frame"),
    exact = TRUE
  )
  testthat::expect_identical(attr(envs, "row.names"), 1:3)
  testthat::expect_identical(.row_names_info(envs), -3L)
  testthat::expect_identical(envs$env_name, c("ea", "eb", "ec"))
  testthat::expect_null(names(envs$path))
  testthat::expect_identical(envs$backend, rep("stub-rows", 3L))

  local_stub_backend("stub-none")
  empty <- list_envs(method = "stub-none")
  testthat::expect_identical(nrow(empty), 0L)
  testthat::expect_named(empty, c("backend", "env_name", "path"))
  testthat::expect_identical(attr(empty, "row.names"), integer(0L))
})

testthat::test_that("list_envs(method = 'auto') lists an unavailable backend, in priority order", {
  # Rule R6: availability only decides where a new environment goes. An
  # environment of an unavailable backend was found by env_exists() and
  # run(), but not listed.
  local_stub_backend("stub-on", envs = "eb")
  local_stub_backend("stub-off", available = FALSE, envs = "ea")
  # Not the alphabetical order, so that the test fails for code that sorts
  # the backends.
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-on", "stub-off")
  )
  envs <- list_envs()
  testthat::expect_identical(envs$backend, c("stub-on", "stub-off"))
  testthat::expect_identical(envs$env_name, c("eb", "ea"))
  testthat::expect_identical(attr(envs, "row.names"), 1:2)
})

testthat::test_that("list_envs(method = 'auto') skips a failing backend with a warning", {
  local_stub_backend(
    "stub-bad",
    backend_list_envs = function(backend, ...) {
      rlang::abort("listing failed", class = "stub_boom")
    }
  )
  local_stub_backend("stub-good", envs = "ea")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-bad", "stub-good")
  )
  cnd <- testthat::expect_warning(
    envs <- list_envs(),
    class = "condathis_backend_query_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_warning")
  testthat::expect_identical(envs$backend, "stub-good")
  testthat::expect_identical(envs$env_name, "ea")

  # The backend named by `method` aborts instead.
  cnd <- testthat::expect_error(
    list_envs(method = "stub-bad"),
    class = "condathis_list_envs_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_s3_class(cnd$parent, "stub_boom")
})

testthat::test_that("list_envs() checks what backend_list_envs() returns", {
  local_stub_backend(
    "stub-na",
    backend_list_envs = function(backend, ...) c("ea", NA_character_)
  )
  cnd <- testthat::expect_error(
    list_envs(method = "stub-na"),
    class = "condathis_list_envs_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
  testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")

  local_stub_backend(
    "stub-dup",
    backend_list_envs = function(backend, ...) c("ea", "ea")
  )
  testthat::expect_error(
    list_envs(method = "stub-dup"),
    class = "condathis_backend_invalid_return"
  )

  # A named vector is valid: the names are dropped.
  local_stub_backend(
    "stub-named",
    backend_list_envs = function(backend, ...) c(first = "ea")
  )
  envs <- list_envs(method = "stub-named")
  testthat::expect_identical(envs$env_name, "ea")
  testthat::expect_identical(attr(envs, "row.names"), 1L)
})

testthat::test_that("list_envs() on a fresh data directory starts no process", {
  # Decision D3: a query works before any environment exists, without
  # creating one and without installing micromamba.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        stop("list_envs() must not start micromamba on a fresh root")
      },
      install_micromamba = function(...) {
        stop("list_envs() must not install micromamba")
      }
    )
    for (envs in list(list_envs(method = "micromamba"), list_envs())) {
      testthat::expect_s3_class(envs, "tbl_df")
      testthat::expect_identical(nrow(envs), 0L)
      testthat::expect_named(envs, c("backend", "env_name", "path"))
    }
    testthat::expect_false(fs::dir_exists(get_condathis_path()))

    # An empty `<root>/envs` is still a fresh root.
    fs::dir_create(fs::path(get_condathis_path(), "envs"))
    testthat::expect_identical(nrow(list_envs(method = "micromamba")), 0L)
    testthat::expect_length(
      fs::dir_ls(fs::path(get_condathis_path(), "envs")),
      0L
    )
  })
})
