rlang_tail <- c("rlang_error", "error", "condition")

testthat::test_that("condathis_abort() adds the root class and names the caller", {
  # Regression test: no condathis error had a root class, so a handler
  # could not catch every condathis error with one class.
  f <- function() {
    condathis_abort(
      c(`x` = "Bad {.arg x}."),
      class = c("condathis_f_invalid_x", "condathis_f_invalid_x"),
      status = 3L
    )
  }
  cnd <- rlang::catch_cnd(f(), classes = "error")
  testthat::expect_identical(
    class(cnd),
    c("condathis_f_invalid_x", "condathis_error", rlang_tail)
  )
  testthat::expect_identical(conditionCall(cnd), quote(f()))
  testthat::expect_identical(cnd$status, 3L)

  cnd <- rlang::catch_cnd(condathis_abort("No class."), classes = "error")
  testthat::expect_identical(class(cnd), c("condathis_error", rlang_tail))
})

testthat::test_that("condathis_abort() interpolates in the caller and passes call on", {
  helper <- function(value, call = rlang::caller_env()) {
    condathis_abort("Value {.val {value}}.", call = call)
  }
  outer <- function() helper("abc")
  cnd <- rlang::catch_cnd(outer(), classes = "error")
  testthat::expect_identical(conditionCall(cnd), quote(outer()))
  testthat::expect_match(conditionMessage(cnd), "abc", fixed = TRUE)
})

testthat::test_that("condathis_warn() adds the root warning class", {
  cnd <- rlang::catch_cnd(
    condathis_warn(c(`!` = "Careful."), class = "condathis_some_warning"),
    classes = "warning"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_some_warning",
      "condathis_warning",
      "rlang_warning",
      "warning",
      "condition"
    )
  )
  res <- withVisible(suppressWarnings(condathis_warn("Plain.")))
  testthat::expect_null(res$value)
  testthat::expect_false(res$visible)
})

testthat::test_that("condathis_warn_once() warns once per id until reset", {
  id <- "test_conditions_once"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  cnd <- rlang::catch_cnd(
    condathis_warn_once(id, "First.", class = "x_once"),
    classes = "warning"
  )
  testthat::expect_identical(
    class(cnd),
    c("x_once", "condathis_warning", "rlang_warning", "warning", "condition")
  )
  # catch_cnd() stopped at the warning; the id is marked all the same.
  testthat::expect_no_warning(
    testthat::expect_false(condathis_warn_once(id, "Again.", class = "x_once"))
  )
  reset_warn_once(id)
  testthat::expect_warning(
    testthat::expect_true(condathis_warn_once(id, "First.", class = "x_once")),
    class = "x_once"
  )
  testthat::expect_no_warning(
    testthat::expect_false(condathis_warn_once(id, "Second.", class = "x_once"))
  )
  # Another id is independent.
  other <- "test_conditions_once_other"
  withr::defer(reset_warn_once(other))
  testthat::expect_warning(
    condathis_warn_once(other, "Other."),
    class = "condathis_warning"
  )
  reset_warn_once(id)
  testthat::expect_warning(
    condathis_warn_once(id, "Again.", class = "x_once"),
    class = "x_once"
  )
})

testthat::test_that("arg_error_class() builds the rule R1 class vector", {
  testthat::expect_identical(
    arg_error_class(
      "create_env",
      "overwrite",
      "condathis_create_invalid_overwrite_arg"
    ),
    c(
      "condathis_create_env_invalid_overwrite",
      "condathis_create_invalid_overwrite_arg",
      "condathis_invalid_overwrite",
      "condathis_invalid_arg"
    )
  )
  testthat::expect_identical(
    arg_error_class(NULL, "verbose"),
    c("condathis_invalid_verbose", "condathis_invalid_arg")
  )
})

testthat::test_that("arg_match_classed() returns the choice and classes its errors", {
  # Regression test: choice arguments failed with a plain rlang error,
  # without any condathis class.
  values <- c("strict", "flexible", "disabled")
  testthat::expect_identical(
    arg_match_classed(values, values, class = "x"),
    "strict"
  )
  testthat::expect_identical(
    arg_match_classed(c("flexible", "strict", "disabled"), values, class = "x"),
    "flexible"
  )
  testthat::expect_identical(
    arg_match_classed("disabled", values, class = "x"),
    "disabled"
  )

  f <- function(channel_priority) {
    arg_match_classed(
      channel_priority,
      values,
      class = c(
        "condathis_f_invalid_channel_priority",
        "condathis_invalid_channel_priority"
      )
    )
  }
  for (bad in list(
    "bogus",
    NA_character_,
    1,
    c("strict", "flexible"),
    NULL,
    ""
  )) {
    cnd <- rlang::catch_cnd(f(bad), classes = "error")
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_f_invalid_channel_priority",
        "condathis_invalid_channel_priority",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
    testthat::expect_identical(conditionCall(cnd), quote(f(bad)))
  }
  cnd <- rlang::catch_cnd(f("strickt"), classes = "error")
  testthat::expect_match(
    conditionMessage(cnd),
    "channel_priority",
    fixed = TRUE
  )
  testthat::expect_match(conditionMessage(cnd), "Did you mean", fixed = TRUE)
})

testthat::test_that("abort_env_not_found() has the shared class and takes hints", {
  f <- function(env_dir) {
    abort_env_not_found(
      "my-env",
      class = c("condathis_f_env_not_found", "condathis_f_missing_env"),
      hint = c(`i` = "Looked in {.path {env_dir}}.")
    )
  }
  cnd <- rlang::catch_cnd(f("/some/dir"), classes = "error")
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_f_env_not_found",
      "condathis_f_missing_env",
      "condathis_env_not_found",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_identical(conditionCall(cnd), quote(f("/some/dir")))
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "my-env", fixed = TRUE)
  testthat::expect_match(message, "/some/dir", fixed = TRUE)

  cnd <- rlang::catch_cnd(
    abort_env_not_found("e", class = "c1"),
    classes = "error"
  )
  testthat::expect_match(conditionMessage(cnd), "create_env", fixed = TRUE)
})

testthat::test_that("with_backend_errors() re-raises backend errors with the shared classes", {
  # Regression test: a backend failure had the backend's own classes only,
  # so the same failure had different classes on each backend.
  f <- function() {
    with_backend_errors(
      rlang::abort(
        "boom",
        class = c("stub_boom", "condathis_cmd_status_error", "condathis_error")
      ),
      fn = "create_env",
      backend_name = "stub",
      action = "create environment 'x'"
    )
  }
  cnd <- rlang::catch_cnd(f(), classes = "error")
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_failed",
      "condathis_backend_error",
      "condathis_cmd_status_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_identical(conditionCall(cnd), quote(f()))
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_true(rlang::cnd_inherits(cnd, "stub_boom"))
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Backend stub failed to create environment 'x'.",
    fixed = TRUE
  )

  # A base R error gets only the shared classes.
  cnd <- rlang::catch_cnd(
    with_backend_errors(
      stop("plain"),
      fn = "remove_env",
      backend_name = "b",
      action = "remove"
    ),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_remove_env_failed",
      "condathis_backend_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_s3_class(cnd$parent, "simpleError")
})

testthat::test_that("with_backend_errors() passes values, warnings and backend errors unchanged", {
  testthat::expect_identical(
    with_backend_errors(42L, fn = "f", backend_name = "b", action = "a"),
    42L
  )
  testthat::expect_warning(
    with_backend_errors(
      warning("w"),
      fn = "f",
      backend_name = "b",
      action = "a"
    ),
    "w"
  )
  original <- rlang::catch_cnd(
    condathis_abort(
      "Already wrapped.",
      class = c("condathis_x_failed", "condathis_backend_error")
    ),
    classes = "error"
  )
  cnd <- rlang::catch_cnd(
    with_backend_errors(
      rlang::cnd_signal(original),
      fn = "f",
      backend_name = "b",
      action = "a"
    ),
    classes = "error"
  )
  testthat::expect_identical(class(cnd), class(original))
  testthat::expect_null(cnd$parent)
})

testthat::test_that("with_backend_errors() wraps a backend's own condathis_backend_error", {
  # Regression test: an error that a backend built with the class
  # condathis_backend_error passed on unchanged, so it reached the user
  # without condathis_<fn>_failed and without condathis_error.
  backend_cnd <- function() {
    rlang::abort(
      "solver failed",
      class = c("mybackend_solve_error", "condathis_backend_error")
    )
  }
  for (wrap in c("with_backend_errors", "abort_backend_failure")) {
    cnd <- if (identical(wrap, "with_backend_errors")) {
      rlang::catch_cnd(
        with_backend_errors(
          backend_cnd(),
          fn = "create_env",
          backend_name = "mybackend",
          action = "create environment 'x'"
        ),
        classes = "error"
      )
    } else {
      rlang::catch_cnd(
        abort_backend_failure(
          rlang::catch_cnd(backend_cnd(), classes = "error"),
          fn = "create_env",
          backend_name = "mybackend",
          action = "create environment 'x'",
          call = rlang::current_env()
        ),
        classes = "error"
      )
    }
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_failed",
        "condathis_backend_error",
        "condathis_error",
        rlang_tail
      ),
      info = wrap
    )
    testthat::expect_s3_class(cnd$parent, "mybackend_solve_error")
    testthat::expect_true(is_condathis_backend_error(cnd), info = wrap)
  }
  # Only the errors that condathis raises carry the mark.
  testthat::expect_false(is_condathis_backend_error(
    rlang::catch_cnd(backend_cnd(), classes = "error")
  ))
  testthat::expect_true(is_condathis_backend_error(rlang::catch_cnd(
    condathis_abort("x", class = "condathis_backend_error"),
    classes = "error"
  )))
  testthat::expect_null(
    rlang::catch_cnd(condathis_abort("x"), classes = "error")[[
      "condathis_backend_rethrown"
    ]]
  )
})

testthat::test_that("new_backend_result() reads backend results with exact names", {
  # Regression test: a stub backend returning TRUE made create_env() fail
  # with "$ operator is invalid for atomic vectors" after the environment
  # was created, and `$` partial-matched `stdout_file` for `stdout`.
  for (value in list(TRUE, NULL, list(), list(stdout_file = "/tmp/x"))) {
    res <- new_backend_result(
      value,
      fn = "create_env",
      backend_name = "stub",
      env_name = "e"
    )
    testthat::expect_s3_class(res, "condathis_result")
    testthat::expect_identical(res$status, 0L)
    testthat::expect_identical(res$stdout, NA_character_)
    testthat::expect_identical(res$stderr, NA_character_)
    testthat::expect_false(res$timeout)
    testthat::expect_identical(res$pid, NA_integer_)
    testthat::expect_identical(res$cmd, NA_character_)
    testthat::expect_identical(res$env_name, "e")
  }

  res <- new_backend_result(
    list(
      status = 0,
      stdout = "out",
      stderr = as.raw(1:2),
      timeout = TRUE,
      pid = 12,
      cmd = "mm create"
    ),
    fn = "create_env",
    backend_name = "stub",
    env_name = "e"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, "out")
  testthat::expect_identical(res$stderr, as.raw(1:2))
  testthat::expect_true(res$timeout)
  testthat::expect_identical(res$pid, 12L)
  testthat::expect_identical(res$cmd, "mm create")

  res <- new_backend_result(
    list(cmd = c("a", "b"), pid = "x", stdout = c("a", "b")),
    fn = "install_packages",
    backend_name = "stub",
    env_name = "e"
  )
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_identical(res$pid, NA_integer_)
  testthat::expect_identical(res$stdout, NA_character_)
})

testthat::test_that("new_backend_result() aborts on a non-zero or invalid status", {
  f <- function(value) {
    new_backend_result(
      value,
      fn = "install_packages",
      backend_name = "stub",
      env_name = "e"
    )
  }
  cnd <- rlang::catch_cnd(
    f(list(status = 1L, stderr = "bad")),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_install_packages_failed",
      "condathis_backend_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_identical(cnd$status, 1L)
  testthat::expect_identical(cnd$stderr, "bad")
  testthat::expect_identical(
    conditionCall(cnd),
    quote(f(list(status = 1L, stderr = "bad")))
  )

  for (bad in list("0", NA_integer_, 1.5, c(0L, 0L), TRUE)) {
    testthat::expect_identical(
      class(rlang::catch_cnd(f(list(status = bad)), classes = "error")),
      c(
        "condathis_backend_invalid_return",
        "condathis_backend_contract_violation",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
})

testthat::test_that("resolve_failure_stderr() gives one text for every resolve failure", {
  cnd <- simpleError("\033[31mno such binary\033[39m")
  testthat::expect_identical(
    resolve_failure_stderr("command", "my-env", cnd),
    "Failed to resolve command for environment 'my-env': no such binary\n"
  )
  testthat::expect_identical(
    resolve_failure_stderr("activation", "/p/env", simpleError("x")),
    "Failed to resolve activation for environment '/p/env': x\n"
  )
})
