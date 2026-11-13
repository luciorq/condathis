# Every test here uses stub backends only (helper-stub-backend.R), and mocks
# the priority order so no test reaches micromamba.

local_only_backends <- function(names, envir = parent.frame()) {
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() names,
    .env = envir
  )
}

stub_boom <- function(...) {
  rlang::abort("boom", class = "stub_boom")
}

testthat::test_that("backend_probe_env() separates absent from could-not-tell", {
  # Regression test: backend_has_env() turned every probe error into FALSE,
  # so a failed listing read as "the environment does not exist" (R5).
  ok <- local_stub_backend("stub-probe-ok", envs = "here")
  testthat::expect_true(backend_probe_env(ok$backend, "here"))
  testthat::expect_false(backend_probe_env(ok$backend, "absent"))

  failing <- local_stub_backend(
    "stub-probe-fail",
    backend_env_exists = stub_boom
  )
  probe <- backend_probe_env(failing$backend, "here")
  testthat::expect_true(is.na(probe))
  testthat::expect_s3_class(attr(probe, "condition"), "stub_boom")
  testthat::expect_false(backend_has_env(failing$backend, "here"))

  # A value other than TRUE or FALSE is a contract violation, so the
  # probe cannot tell either.
  for (value in list(NA, "yes", c(TRUE, TRUE), NULL, 1L)) {
    bad <- local_stub_backend(
      "stub-probe-bad",
      backend_env_exists = function(...) value
    )
    probe <- backend_probe_env(bad$backend, "here")
    testthat::expect_true(is.na(probe), info = deparse(value))
    testthat::expect_s3_class(
      attr(probe, "condition"),
      "condathis_backend_invalid_return"
    )
    unregister_backend("stub-probe-bad")
  }
})

testthat::test_that("backend probes get verbose = 'silent' by default", {
  stub <- local_stub_backend("stub-probe-verbose", envs = "e")
  backend_probe_env(stub$backend, "e")
  backend_has_env(stub$backend, "e")
  calls <- stub_calls(stub, "backend_env_exists")
  testthat::expect_length(calls, 2L)
  for (call in calls) {
    testthat::expect_identical(call$args$verbose, "silent")
    testthat::expect_identical(call$args$env_name, "e")
  }
})

testthat::test_that("backend_env_exists_checked() names the backend in its error", {
  stub <- local_stub_backend(
    "stub-checked",
    backend_env_exists = function(...) NA
  )
  cnd <- rlang::catch_cnd(
    backend_env_exists_checked(stub$backend, "x"),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_backend_invalid_return",
      "condathis_backend_contract_violation",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "stub-checked", fixed = TRUE)
  testthat::expect_match(message, "backend_env_exists", fixed = TRUE)
})

testthat::test_that("find_owning_backends() probes in priority order", {
  local_stub_backend("stub-own-a", envs = "shared")
  local_stub_backend("stub-own-b", envs = c("shared", "only-b"))
  local_only_backends(c("stub-own-b", "stub-own-a"))
  testthat::expect_identical(
    find_owning_backends("shared"),
    c("stub-own-b", "stub-own-a")
  )
  testthat::expect_identical(find_owning_backends("only-b"), "stub-own-b")
  testthat::expect_identical(find_owning_backends("nowhere"), character(0L))
})

testthat::test_that("find_owning_backends() aborts a mutating caller on a failed probe", {
  # Regression test: a failed probe counted as "not the owner", so an
  # existing environment looked new and could be rebuilt by another backend.
  local_stub_backend("stub-fail-owner", backend_env_exists = stub_boom)
  local_stub_backend("stub-ok-owner", envs = "e")
  local_only_backends(c("stub-fail-owner", "stub-ok-owner"))

  f <- function() find_owning_backends("e", mutating = TRUE)
  cnd <- rlang::catch_cnd(f(), classes = "error")
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_backend_probe_failed",
      "condathis_backend_error",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_identical(conditionCall(cnd), quote(f()))
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "stub-fail-owner", fixed = TRUE)

  # The condathis classes of the backend's error are kept (rule R1), so a
  # handler for a micromamba failure still catches it.
  unregister_backend("stub-fail-owner")
  local_stub_backend(
    "stub-fail-owner",
    backend_env_exists = function(...) {
      condathis_abort("Listing failed.", class = "condathis_cmd_status_error")
    }
  )
  cnd <- rlang::catch_cnd(f(), classes = "error")
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_backend_probe_failed",
      "condathis_backend_error",
      "condathis_cmd_status_error",
      "condathis_error"
    )
  )
})

testthat::test_that("find_owning_backends() warns a read-only caller and skips the backend", {
  local_stub_backend("stub-fail-ro", backend_env_exists = stub_boom)
  local_stub_backend("stub-ok-ro", envs = "e")
  local_only_backends(c("stub-fail-ro", "stub-ok-ro"))
  testthat::expect_warning(
    owners <- find_owning_backends("e", mutating = FALSE),
    class = "condathis_backend_query_failed"
  )
  testthat::expect_identical(owners, "stub-ok-ro")
  cnd <- rlang::catch_cnd(find_owning_backends("e"), classes = "warning")
  testthat::expect_s3_class(cnd, "condathis_warning")
  testthat::expect_s3_class(cnd$parent, "stub_boom")
})

testthat::test_that("validate_backend_return() checks backend_list_envs()", {
  # Regression test: list_envs() used the listing unchecked, and a named
  # vector added row names.
  f <- function(value) {
    validate_backend_return(value, "backend_list_envs", backend_name = "stub")
  }
  testthat::expect_identical(f(c(x = "a", y = "b")), c("a", "b"))
  testthat::expect_identical(f(character(0L)), character(0L))
  testthat::expect_identical(f(fs::path("a")), "a")
  for (bad in list(c("a", NA), c("a", "a"), 1, NULL, list("a"))) {
    cnd <- rlang::catch_cnd(f(bad), classes = "error")
    testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
    testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
    testthat::expect_identical(conditionCall(cnd), quote(f(bad)))
  }
})

testthat::test_that("validate_backend_return() checks the directories", {
  existing <- withr::local_tempdir()
  res <- validate_backend_return(existing, "backend_get_install_dir", "stub")
  testthat::expect_s3_class(res, "fs_path")
  testthat::expect_identical(
    as.character(res),
    as.character(fs::path(existing))
  )
  missing_dir <- fs::path(existing, "missing")
  for (bad in list(
    missing_dir,
    "relative/dir",
    NA_character_,
    c(existing, existing),
    1
  )) {
    testthat::expect_error(
      validate_backend_return(bad, "backend_get_install_dir", "stub"),
      class = "condathis_backend_invalid_return",
      info = deparse(bad)
    )
  }

  res <- validate_backend_return(missing_dir, "backend_get_env_dir", "stub")
  testthat::expect_s3_class(res, "fs_path")
  for (bad in list("relative/dir", NA_character_, character(0L), 1)) {
    testthat::expect_error(
      validate_backend_return(bad, "backend_get_env_dir", "stub"),
      class = "condathis_backend_invalid_return",
      info = deparse(bad)
    )
  }
})

testthat::test_that("install_dir_for_backend() and env_dir_for_backend() return checked fs paths", {
  # Regression test: get_env_dir() returned whatever the backend returned,
  # although its docs promised a path.
  good <- local_stub_backend("stub-dirs-good")
  testthat::expect_s3_class(install_dir_for_backend(good$backend), "fs_path")
  env_dir <- env_dir_for_backend(good$backend, "e")
  testthat::expect_s3_class(env_dir, "fs_path")
  testthat::expect_identical(
    as.character(env_dir),
    as.character(fs::path(good$root, "envs", "e"))
  )

  relative <- local_stub_backend(
    "stub-dirs-relative",
    backend_get_env_dir = function(backend, env_name) {
      file.path("envs", env_name)
    }
  )
  cnd <- rlang::catch_cnd(
    env_dir_for_backend(relative$backend, "e"),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
  testthat::expect_match(
    conditionMessage(cnd),
    "stub-dirs-relative",
    fixed = TRUE
  )

  missing_root <- local_stub_backend(
    "stub-dirs-missing",
    backend_get_install_dir = function(backend) {
      fs::path(tempdir(), "condathis-stub-root-that-does-not-exist")
    }
  )
  testthat::expect_error(
    install_dir_for_backend(missing_root$backend),
    class = "condathis_backend_invalid_return"
  )
})

testthat::test_that("validate_backend_return() checks the six package columns", {
  # Regression test: create_env() reads build_string and platform, which
  # the contract did not guarantee, so the platform check never fired.
  full <- data.frame(
    name = "python",
    version = "3.13.0",
    build_number = 1,
    build_string = "h1_0",
    channel = "conda-forge",
    platform = "linux-64",
    url = "https://x",
    stringsAsFactors = FALSE
  )
  res <- validate_backend_return(full, "backend_list_packages", "stub")
  testthat::expect_identical(res$build_number, 1L)
  testthat::expect_identical(res$url, "https://x")
  testthat::expect_s3_class(res, "data.frame")

  tbl <- full
  class(tbl) <- c("tbl_df", "tbl", "data.frame")
  testthat::expect_s3_class(
    validate_backend_return(tbl, "backend_list_packages", "stub"),
    "tbl_df"
  )

  no_platform <- full[, setdiff(names(full), c("platform", "build_string"))]
  cnd <- rlang::catch_cnd(
    validate_backend_return(no_platform, "backend_list_packages", "stub-pkgs"),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "stub-pkgs", fixed = TRUE)
  testthat::expect_match(message, "build_string", fixed = TRUE)
  testthat::expect_match(message, "platform", fixed = TRUE)

  fractional <- full
  fractional$build_number <- 1.5
  testthat::expect_error(
    validate_backend_return(fractional, "backend_list_packages", "stub"),
    class = "condathis_backend_invalid_return"
  )
  as_factor <- full
  as_factor$name <- factor(as_factor$name)
  testthat::expect_error(
    validate_backend_return(as_factor, "backend_list_packages", "stub"),
    class = "condathis_backend_invalid_return"
  )
  testthat::expect_error(
    validate_backend_return(list(name = "x"), "backend_list_packages", "stub"),
    class = "condathis_backend_invalid_return"
  )

  # The checked wrapper uses the same rule.
  stub <- local_stub_backend(
    "stub-pkgs-checked",
    backend_list_packages = function(...) data.frame(name = "x")
  )
  testthat::expect_error(
    backend_list_packages_checked(stub$backend, "e"),
    class = "condathis_backend_invalid_return"
  )
  ok <- local_stub_backend("stub-pkgs-ok")
  testthat::expect_identical(
    names(backend_list_packages_checked(ok$backend, "e")),
    names(backend_list_packages_columns)
  )
})

testthat::test_that("backend_list_envs_checked() returns an unnamed character vector", {
  stub <- local_stub_backend(
    "stub-list-named",
    backend_list_envs = function(...) c(first = "a", second = "b")
  )
  testthat::expect_identical(
    backend_list_envs_checked(stub$backend),
    c("a", "b")
  )
  dup <- local_stub_backend(
    "stub-list-dup",
    backend_list_envs = function(...) c("a", "a")
  )
  testthat::expect_error(
    backend_list_envs_checked(dup$backend),
    class = "condathis_backend_invalid_return"
  )
})

testthat::test_that("query_registered_backends() aborts for an explicit backend", {
  stub <- local_stub_backend(
    "stub-query-explicit",
    backend_list_envs = function(...) {
      rlang::abort(
        "listing failed",
        class = c("stub_boom", "condathis_cmd_status_error")
      )
    }
  )
  f <- function() {
    query_registered_backends(
      "stub-query-explicit",
      query = function(backend) backend_list_envs_checked(backend),
      auto = FALSE,
      fn = "list_envs",
      action = "list its environments"
    )
  }
  cnd <- rlang::catch_cnd(f(), classes = "error")
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_list_envs_failed",
      "condathis_backend_error",
      "condathis_cmd_status_error",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_identical(conditionCall(cnd), quote(f()))
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Backend stub-query-explicit failed to list its environments.",
    fixed = TRUE
  )
})

testthat::test_that("query_registered_backends() skips a failing backend under auto", {
  # Regression test: list_envs() aborted as a whole when one backend's
  # listing failed, also under method = "auto".
  local_stub_backend("stub-query-ok", envs = c("e1", "e2"))
  local_stub_backend("stub-query-fail", backend_list_envs = stub_boom)
  query <- function(backend) backend_list_envs_checked(backend)
  testthat::expect_warning(
    res <- query_registered_backends(
      c("stub-query-fail", "stub-query-ok"),
      query = query,
      auto = TRUE,
      fn = "list_envs",
      action = "list its environments"
    ),
    class = "condathis_backend_query_failed"
  )
  testthat::expect_identical(res, list(`stub-query-ok` = c("e1", "e2")))

  cnd <- rlang::catch_cnd(
    query_registered_backends(
      c("stub-query-fail", "stub-query-ok"),
      query = query,
      auto = TRUE,
      fn = "list_envs",
      action = "list its environments"
    ),
    classes = "warning"
  )
  testthat::expect_s3_class(cnd, "condathis_warning")
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_match(conditionMessage(cnd), "stub-query-fail", fixed = TRUE)
})

testthat::test_that("query_registered_backends() aborts when every backend fails under auto", {
  local_stub_backend("stub-query-fail-1", backend_env_exists = stub_boom)
  local_stub_backend("stub-query-fail-2", backend_env_exists = stub_boom)
  testthat::expect_no_warning(
    cnd <- rlang::catch_cnd(
      query_registered_backends(
        c("stub-query-fail-1", "stub-query-fail-2"),
        query = function(backend) backend_env_exists_checked(backend, "x"),
        auto = TRUE,
        fn = "env_exists",
        action = "check whether environment 'x' exists"
      ),
      classes = "error"
    )
  )
  testthat::expect_s3_class(cnd, "condathis_env_exists_failed")
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_identical(
    query_registered_backends(
      character(0L),
      query = stub_boom,
      auto = TRUE,
      fn = "env_exists",
      action = "x"
    ),
    list()
  )
})

testthat::test_that("query_registered_backends() keeps every result, also FALSE and empty ones", {
  local_stub_backend("stub-query-a")
  local_stub_backend("stub-query-b", envs = "x")
  res <- query_registered_backends(
    c("stub-query-a", "stub-query-b"),
    query = function(backend) backend_env_exists_checked(backend, "x"),
    auto = TRUE,
    fn = "env_exists",
    action = "check"
  )
  testthat::expect_identical(
    res,
    list(`stub-query-a` = FALSE, `stub-query-b` = TRUE)
  )
  res <- query_registered_backends(
    "stub-query-a",
    query = function(backend) backend_list_envs_checked(backend),
    auto = FALSE,
    fn = "list_envs",
    action = "list"
  )
  testthat::expect_identical(res, list(`stub-query-a` = character(0L)))
})

testthat::test_that("positional_env_name_possible() needs two or more unnamed arguments", {
  # Only 0.1.4's positional shape `fn("pkg", "env")` can hold an env_name.
  testthat::expect_true(positional_env_name_possible(list("a", "b")))
  testthat::expect_true(positional_env_name_possible(list(c("a", "b"), "c")))
  testthat::expect_true(positional_env_name_possible(list("a", c(x = "b"))))
  # One vector, `packages =` (by name, do.call(), !!!), or a last value
  # that is not one string.
  testthat::expect_false(positional_env_name_possible(list()))
  testthat::expect_false(positional_env_name_possible(list("a")))
  testthat::expect_false(positional_env_name_possible(list(c("a", "b"))))
  testthat::expect_false(
    positional_env_name_possible(list(packages = c("a", "b")))
  )
  testthat::expect_false(
    positional_env_name_possible(list(packages = "a", "b"))
  )
  testthat::expect_false(positional_env_name_possible(list("a", c("b", "c"))))
  testthat::expect_false(positional_env_name_possible(list("a", character(0L))))
  testthat::expect_false(positional_env_name_possible(list("a", NULL)))
})

testthat::test_that("abort_on_positional_env_name() catches an old positional env_name", {
  local_stub_backend("stub-positional", envs = "my-env")
  local_stub_backend("stub-positional-fail", backend_env_exists = stub_boom)
  local_only_backends(c("stub-positional-fail", "stub-positional"))
  f <- function(...) {
    abort_on_positional_env_name(c(...), fn = "install_packages")
  }
  cnd <- rlang::catch_cnd(f("python", "my-env"), classes = "error")
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_install_packages_positional_env_name",
      "condathis_invalid_packages",
      "condathis_invalid_arg",
      "condathis_error",
      "rlang_error",
      "error",
      "condition"
    )
  )
  testthat::expect_match(
    conditionMessage(cnd),
    "env_name = \"my-env\"",
    fixed = TRUE
  )
  testthat::expect_identical(conditionCall(cnd), quote(f("python", "my-env")))
  # One spec, a spec that is no environment, or a spec that is not a valid
  # name: no error.
  testthat::expect_null(f("my-env"))
  testthat::expect_null(f("python", "other-env"))
  testthat::expect_null(f("python", "python>=3.12"))
  testthat::expect_null(f())
})

testthat::test_that("warn_on_backend_marker_mismatch() warns with the root class", {
  stub <- local_stub_backend("stub-marker", envs = "e")
  write_backend_marker(fs::path(stub$root, "envs", "e"), "another-backend")
  testthat::expect_warning(
    warn_on_backend_marker_mismatch("stub-marker", "e"),
    class = "condathis_backend_marker_mismatch"
  )
  cnd <- rlang::catch_cnd(
    warn_on_backend_marker_mismatch("stub-marker", "e"),
    classes = "warning"
  )
  testthat::expect_s3_class(cnd, "condathis_warning")
})

testthat::test_that("validate_backend_return() checks the new optional functions", {
  check <- function(value, generic) {
    return(validate_backend_return(
      value,
      generic = generic,
      backend_name = "stub-x"
    ))
  }
  # backend_native_platform(): one platform, or NA.
  testthat::expect_identical(
    check("osx-arm64", "backend_native_platform"),
    "osx-arm64"
  )
  testthat::expect_identical(
    check(NA, "backend_native_platform"),
    NA_character_
  )
  testthat::expect_identical(
    check(NA_character_, "backend_native_platform"),
    NA_character_
  )
  for (value in list("", c("a", "b"), 1L, NULL, list("linux-64"))) {
    testthat::expect_error(
      check(value, "backend_native_platform"),
      class = "condathis_backend_invalid_return",
      info = deparse(value)
    )
  }
  # backend_can_solve(): TRUE, FALSE or NA.
  testthat::expect_true(check(TRUE, "backend_can_solve"))
  testthat::expect_false(check(FALSE, "backend_can_solve"))
  testthat::expect_identical(check(NA, "backend_can_solve"), NA)
  testthat::expect_identical(
    check(structure(TRUE, note = "x"), "backend_can_solve"),
    TRUE
  )
  for (value in list("TRUE", c(TRUE, FALSE), 1L, NULL, logical(0L))) {
    testthat::expect_error(
      check(value, "backend_can_solve"),
      class = "condathis_backend_invalid_return",
      info = deparse(value)
    )
  }
  # backend_quiesce(): TRUE or FALSE.
  testthat::expect_true(check(TRUE, "backend_quiesce"))
  testthat::expect_false(check(FALSE, "backend_quiesce"))
  for (value in list(NA, NULL, "yes")) {
    testthat::expect_error(
      check(value, "backend_quiesce"),
      class = "condathis_backend_contract_violation",
      info = deparse(value)
    )
  }
})

testthat::test_that("an error from a platform probe counts as 'cannot tell'", {
  stub <- local_stub_backend(
    "stub-probe-errors",
    backend_native_platform = function(...) stop("no platform"),
    backend_can_solve = function(...) stop("no network")
  )
  testthat::expect_identical(
    backend_native_platform_checked(stub$backend),
    NA_character_
  )
  testthat::expect_identical(
    backend_can_solve_checked(
      stub$backend,
      packages = "pkg-a",
      channels = "conda-forge",
      channel_priority = "strict",
      additional_channels = NULL,
      platform = "osx-64"
    ),
    NA
  )
  call <- stub_calls(stub, "backend_can_solve")[[1L]]
  testthat::expect_identical(call$args$platform, "osx-64")
  testthat::expect_identical(call$args$packages, "pkg-a")

  # A value that breaks the contract still aborts, naming the backend.
  bad <- local_stub_backend(
    "stub-probe-invalid",
    backend_native_platform = function(...) 64L,
    backend_can_solve = function(...) "yes"
  )
  cnd <- rlang::catch_cnd(
    backend_native_platform_checked(bad$backend),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
  testthat::expect_match(conditionMessage(cnd), "stub-probe-invalid")
  testthat::expect_error(
    backend_can_solve_checked(bad$backend, platform = "osx-64"),
    class = "condathis_backend_invalid_return"
  )
})

testthat::test_that("quiesce_registered_backends() asks every backend and never stops", {
  calls <- character(0L)
  local_stub_backend(
    "stub-quiesce-a",
    backend_quiesce = function(backend, timeout = 30) {
      calls <<- c(calls, paste0("a:", timeout))
      stop("cannot tell")
    }
  )
  local_stub_backend(
    "stub-quiesce-b",
    backend_quiesce = function(backend, timeout = 30) {
      calls <<- c(calls, paste0("b:", timeout))
      return(invisible(FALSE))
    }
  )
  local_stub_backend(
    "stub-quiesce-c",
    backend_quiesce = function(backend, timeout = 30) {
      calls <<- c(calls, "c")
      return("idle")
    }
  )
  warnings <- list()
  idle <- withCallingHandlers(
    quiesce_registered_backends(timeout = 2),
    warning = function(w) {
      warnings[[length(warnings) + 1L]] <<- w
      invokeRestart("muffleWarning")
    }
  )
  testthat::expect_false(idle)
  testthat::expect_setequal(calls, c("a:2", "b:2", "c"))
  testthat::expect_length(warnings, 2L)
  for (w in warnings) {
    testthat::expect_identical(
      class(w)[1:2],
      c("condathis_backend_quiesce_failed", "condathis_warning")
    )
  }
  testthat::expect_match(
    conditionMessage(warnings[[1L]]),
    "stub-quiesce-a",
    fixed = TRUE
  )
  # Every default answers TRUE.
  testthat::expect_true(backend_quiesce(micromamba_backend()))
})
