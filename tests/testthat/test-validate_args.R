rlang_tail <- c("rlang_error", "error", "condition")

catch_error <- function(expr) {
  return(rlang::catch_cnd(expr, classes = "error"))
}

testthat::test_that("validate_cmd_arg() rejects a missing or non-string cmd", {
  # Regression test: run() accepted 1, NA, "" and c("echo", "x") as cmd,
  # and run_bin() had no check at all.
  f <- function(cmd) {
    validate_cmd_arg(
      cmd,
      class = c("condathis_f_invalid_cmd", "condathis_f_null_cmd")
    )
  }
  expected <- c(
    "condathis_f_invalid_cmd",
    "condathis_f_null_cmd",
    "condathis_invalid_cmd",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  cnd <- catch_error(f())
  testthat::expect_identical(class(cnd), expected)
  testthat::expect_match(conditionMessage(cnd), "absent", fixed = TRUE)
  testthat::expect_identical(conditionCall(cnd), quote(f()))
  for (bad in list(NULL, 1, NA_character_, "", c("echo", "x"), TRUE)) {
    cnd <- catch_error(f(bad))
    testthat::expect_identical(class(cnd), expected, info = deparse(bad))
  }
  cnd <- catch_error(f(c("echo", "x")))
  testthat::expect_match(conditionMessage(cnd), "...", fixed = TRUE)
  testthat::expect_identical(f("echo"), "echo")
})

testthat::test_that("validate_bool_arg() accepts only TRUE and FALSE", {
  f <- function(supervise) {
    validate_bool_arg(supervise, class = arg_error_class("run", "supervise"))
  }
  testthat::expect_true(f(TRUE))
  testthat::expect_false(f(FALSE))
  for (bad in list(NA, "yes", 1, c(TRUE, FALSE), NULL)) {
    cnd <- catch_error(f(bad))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_run_invalid_supervise",
        "condathis_invalid_supervise",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
    testthat::expect_match(conditionMessage(cnd), "supervise", fixed = TRUE)
  }
})

testthat::test_that("validate_timeout_arg() checks and caps the timeout", {
  # Regression test: a non-numeric timeout silently meant no limit, and a
  # finite timeout above 2147483 s overflowed the integer milliseconds of a
  # process wait.
  cls <- arg_error_class("run", "timeout")
  testthat::expect_identical(validate_timeout_arg(Inf, class = cls), Inf)
  testthat::expect_identical(validate_timeout_arg(10L, class = cls), 10)
  testthat::expect_identical(validate_timeout_arg(0, class = cls), 0)
  testthat::expect_identical(validate_timeout_arg(1e12, class = cls), 2147483)
  for (bad in list("10", NA, NA_real_, -1, c(1, 2), NULL)) {
    cnd <- catch_error(validate_timeout_arg(bad, class = cls))
    testthat::expect_identical(
      class(cnd),
      c(cls, "condathis_error", rlang_tail),
      info = deparse(bad)
    )
  }
})

testthat::test_that("validate_target_arg() and validate_stdin_arg() check stream targets", {
  cls <- arg_error_class("run", "stdout")
  for (good in list(NULL, "|", "", "out.txt")) {
    testthat::expect_no_error(validate_target_arg(good, class = cls))
  }
  for (bad in list(1, NA_character_, c("a", "b"), TRUE)) {
    cnd <- catch_error(validate_target_arg(bad, class = cls))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_run_invalid_stdout",
        "condathis_invalid_stdout",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }

  stdin_file <- withr::local_tempfile()
  writeLines("x", stdin_file)
  stdin_cls <- arg_error_class("run", "stdin")
  for (good in list(NULL, "|", stdin_file)) {
    testthat::expect_no_error(validate_stdin_arg(good, class = stdin_cls))
  }
  for (bad in list(
    fs::path_temp("condathis-no-such-file"),
    tempdir(),
    1,
    NA_character_
  )) {
    cnd <- catch_error(validate_stdin_arg(bad, class = stdin_cls))
    testthat::expect_identical(
      class(cnd),
      c(stdin_cls, "condathis_error", rlang_tail),
      info = deparse(bad)
    )
  }
})

testthat::test_that("validate_run_args() checks every process argument of the run family", {
  ok <- list(
    timeout = Inf,
    supervise = FALSE,
    cleanup_tree = FALSE,
    linux_pdeathsig = FALSE,
    stdin = NULL,
    stdout = "|",
    stderr = "|",
    activate = TRUE
  )
  run_args <- function(fn, ...) {
    args <- utils::modifyList(ok, list(...), keep.null = TRUE)
    return(do.call(validate_run_args, c(list(fn = fn), args)))
  }
  testthat::expect_identical(run_args("run"), list(timeout = Inf))
  testthat::expect_identical(
    run_args("run_bin", timeout = 1e10),
    list(timeout = 2147483)
  )

  bad_values <- list(
    timeout = "10",
    supervise = NA,
    cleanup_tree = "yes",
    linux_pdeathsig = 1,
    activate = "yes",
    stdout = 1,
    stderr = c("a", "b"),
    stdin = "/nonexistent"
  )
  for (fn in c("run", "run_bin", "run_pipeline")) {
    for (arg in names(bad_values)) {
      args <- list(fn)
      args[[arg]] <- bad_values[[arg]]
      cnd <- catch_error(do.call(run_args, args))
      # Rule R1 order: the old stdin class of run() and run_bin() comes
      # right after the function class, and no other class is added.
      alias <- if (identical(arg, "stdin") && fn %in% c("run", "run_bin")) {
        "condathis_run_stdin_error"
      }
      testthat::expect_identical(
        class(cnd),
        c(
          paste0("condathis_", fn, "_invalid_", arg),
          alias,
          paste0("condathis_invalid_", arg),
          "condathis_invalid_arg",
          "condathis_error",
          rlang_tail
        ),
        info = paste(fn, arg)
      )
    }
  }
  # The old stdin class stays for run() and run_bin(), also when stdin is
  # not a string.
  for (fn in c("run", "run_bin")) {
    cnd <- catch_error(run_args(fn, stdin = 1))
    testthat::expect_identical(
      class(cnd),
      c(
        paste0("condathis_", fn, "_invalid_stdin"),
        "condathis_run_stdin_error",
        "condathis_invalid_stdin",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = fn
    )
  }
  cnd <- catch_error(run_args("run_pipeline", stdin = "/nonexistent"))
  testthat::expect_false(inherits(cnd, "condathis_run_stdin_error"))

  # The error names the caller of validate_run_args().
  f <- function() {
    validate_run_args(
      "run",
      timeout = -1,
      supervise = FALSE,
      cleanup_tree = FALSE,
      linux_pdeathsig = FALSE,
      stdin = NULL,
      stdout = "|",
      stderr = "|"
    )
  }
  testthat::expect_identical(conditionCall(catch_error(f())), quote(f()))
})

testthat::test_that("validate_packages_arg() checks a vector of package specs", {
  f <- function(packages, allow_null = FALSE) {
    validate_packages_arg(
      packages,
      allow_null = allow_null,
      missing_class = "condathis_f_missing_packages",
      invalid_class = "condathis_f_invalid_packages"
    )
  }
  testthat::expect_identical(
    f(c(a = "python", b = "r-base")),
    c("python", "r-base")
  )
  testthat::expect_identical(f(NULL, allow_null = TRUE), character(0L))
  testthat::expect_identical(f(character(0L), allow_null = TRUE), character(0L))
  missing_expected <- c(
    "condathis_f_missing_packages",
    "condathis_invalid_packages",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  testthat::expect_identical(class(catch_error(f())), missing_expected)
  testthat::expect_identical(class(catch_error(f(NULL))), missing_expected)
  testthat::expect_identical(
    class(catch_error(f(character(0L)))),
    missing_expected
  )
  for (bad in list(
    NA,
    NA_character_,
    c("a", NA),
    1,
    "",
    c("a", ""),
    list("a"),
    factor("a")
  )) {
    testthat::expect_identical(
      class(catch_error(f(bad, allow_null = TRUE))),
      c(
        "condathis_f_invalid_packages",
        "condathis_invalid_packages",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
})

testthat::test_that("validate_channels_arg() requires non-empty channel vectors", {
  # Regression test: channels = NULL silently meant "conda-forge" with
  # micromamba and no channel at all with other backends.
  f <- function(channels, additional_channels = NULL) {
    validate_channels_arg(
      channels,
      additional_channels,
      class = "condathis_f_invalid_channels"
    )
  }
  testthat::expect_no_error(f("conda-forge"))
  testthat::expect_no_error(f(c("conda-forge", "bioconda"), "file:///x"))
  for (bad in list(NULL, character(0L), NA_character_, "", c("a", NA), 1)) {
    testthat::expect_identical(
      class(catch_error(f(bad))),
      c(
        "condathis_f_invalid_channels",
        "condathis_invalid_channels",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
  for (bad in list(character(0L), NA_character_, "", 1)) {
    testthat::expect_identical(
      class(catch_error(f("conda-forge", bad))),
      c(
        "condathis_f_invalid_channels",
        "condathis_invalid_additional_channels",
        "condathis_invalid_channels",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
})

testthat::test_that("validate_channels_arg(allow_null = TRUE) accepts NULL and says so", {
  # Regression test: for validate_env(), which accepts channels = NULL, the
  # message said "a non-empty character vector" only.
  message_of <- function(channels, allow_null) {
    cnd <- catch_error(validate_channels_arg(
      channels,
      additional_channels = NULL,
      class = "condathis_f_invalid_channels",
      allow_null = allow_null
    ))
    return(cli::ansi_strip(conditionMessage(cnd)))
  }
  testthat::expect_no_error(validate_channels_arg(
    NULL,
    additional_channels = NULL,
    class = "condathis_f_invalid_channels",
    allow_null = TRUE
  ))
  testthat::expect_match(
    message_of(character(0L), allow_null = TRUE),
    "`channels` must be `NULL` or a non-empty character vector",
    fixed = TRUE
  )
  # Without allow_null, NULL is rejected and the message does not offer it.
  for (bad in list(NULL, character(0L))) {
    msg <- message_of(bad, allow_null = FALSE)
    testthat::expect_match(
      msg,
      "`channels` must be a non-empty character vector",
      fixed = TRUE
    )
    testthat::expect_no_match(msg, "must be `NULL`", fixed = TRUE)
  }
})

# A function with the D6 signature of create_env(), and one of
# install_packages(): package specs in `...`, every option named after it.
d6_create_env <- function(
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = "output",
  channels = "conda-forge",
  additional_channels = NULL,
  channel_priority = "strict",
  platform = NULL,
  env_file = NULL,
  overwrite = FALSE
) {
  return(collect_package_specs(rlang::list2(...), fn = "create_env"))
}
d6_install_packages <- function(
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = "output",
  channels = "conda-forge",
  additional_channels = NULL,
  channel_priority = "strict"
) {
  return(collect_package_specs(
    rlang::list2(...),
    fn = "install_packages",
    allow_empty = FALSE
  ))
}

invalid_packages_class <- function(fn) {
  return(c(
    paste0("condathis_", fn, "_invalid_packages"),
    "condathis_invalid_packages",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  ))
}

testthat::test_that("collect_package_specs() flattens unnamed specs in order", {
  testthat::expect_identical(d6_create_env(), character(0L))
  testthat::expect_identical(
    d6_create_env("a", c("b", "c"), character(0L), c(x = "d"), env_name = "e"),
    c("a", "b", "c", "d")
  )
  testthat::expect_identical(d6_create_env(!!!list("a", "b")), c("a", "b"))
  testthat::expect_identical(
    d6_install_packages("python>=3.12"),
    "python>=3.12"
  )
})

testthat::test_that("collect_package_specs() rejects values that are not specs", {
  for (bad in list(
    NULL,
    NA,
    NA_character_,
    "",
    1L,
    TRUE,
    list("a"),
    factor("a"),
    c("a", NA)
  )) {
    cnd <- catch_error(d6_create_env("python", bad))
    testthat::expect_identical(
      class(cnd),
      invalid_packages_class("create_env"),
      info = deparse(bad)
    )
    testthat::expect_identical(
      conditionCall(cnd),
      quote(d6_create_env("python", bad))
    )
    testthat::expect_match(conditionMessage(cnd), "Element 2", fixed = TRUE)
  }
  testthat::expect_identical(
    class(catch_error(d6_install_packages(1))),
    invalid_packages_class("install_packages")
  )
})

testthat::test_that("collect_package_specs() names the closest formal for a misspelled option", {
  cnd <- catch_error(d6_create_env("python", chanels = "bioconda"))
  testthat::expect_identical(class(cnd), invalid_packages_class("create_env"))
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(
    message,
    "`chanels` is not an argument of `create_env()`",
    fixed = TRUE
  )
  testthat::expect_match(message, "Did you mean `channels`?", fixed = TRUE)

  cnd <- catch_error(d6_install_packages("python", env = "x"))
  testthat::expect_match(conditionMessage(cnd), "env_name", fixed = TRUE)

  cnd <- catch_error(d6_create_env("python", overwrit = TRUE))
  testthat::expect_match(conditionMessage(cnd), "overwrite", fixed = TRUE)

  cnd <- catch_error(d6_create_env("python", zzzzzzzz = 1))
  testthat::expect_identical(class(cnd), invalid_packages_class("create_env"))
  testthat::expect_match(conditionMessage(cnd), "unnamed", fixed = TRUE)
})

testthat::test_that("collect_package_specs() rejects an environment file as a spec", {
  for (spec in c("environment.yml", "env.yaml", "ENV.YML")) {
    cnd <- catch_error(d6_create_env(spec))
    testthat::expect_identical(
      class(cnd),
      invalid_packages_class("create_env"),
      info = spec
    )
    testthat::expect_match(
      conditionMessage(cnd),
      "env_file = ",
      fixed = TRUE,
      info = spec
    )
  }
  cnd <- catch_error(d6_install_packages("python", "env.yml"))
  testthat::expect_identical(
    class(cnd),
    invalid_packages_class("install_packages")
  )
  testthat::expect_match(
    conditionMessage(cnd),
    "create_env(env_file = ",
    fixed = TRUE
  )
})

testthat::test_that("collect_package_specs() requires specs when allow_empty is FALSE", {
  for (call_result in list(
    catch_error(d6_install_packages()),
    catch_error(d6_install_packages(character(0L)))
  )) {
    testthat::expect_identical(
      class(call_result),
      c(
        "condathis_install_packages_missing_packages",
        "condathis_invalid_packages",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      )
    )
  }
  # An explicit `packages = NULL` or `character(0)` is the 0.1.4 empty
  # install: no specs, no error.
  for (empty in list(NULL, character(0L))) {
    testthat::expect_identical(
      suppressWarnings(
        d6_install_packages(packages = empty),
        classes = "condathis_deprecated_packages_arg"
      ),
      character(0L)
    )
  }
})

testthat::test_that("collect_package_specs() accepts `packages =` as a deprecated alias", {
  id <- "deprecated_packages_arg_create_env"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  res <- NULL
  cnd <- rlang::catch_cnd(
    res <- d6_create_env(packages = c("a", "b"), env_name = "e"),
    classes = "warning"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_deprecated_packages_arg",
      "condathis_warning",
      "rlang_warning",
      "warning",
      "condition"
    )
  )
  # catch_cnd() stops at the warning, so run the call again for its value.
  reset_warn_once(id)
  testthat::expect_warning(
    res <- d6_create_env(packages = c("a", "b"), env_name = "e"),
    class = "condathis_deprecated_packages_arg"
  )
  testthat::expect_identical(res, c("a", "b"))
  # Once per session.
  testthat::expect_no_warning(
    testthat::expect_identical(d6_create_env(packages = NULL), character(0L))
  )
  # The warning has the root class too.
  reset_warn_once(id)
  testthat::expect_warning(
    d6_create_env(packages = "a"),
    class = "condathis_warning"
  )
  # Each function warns on its own.
  other_id <- "deprecated_packages_arg_install_packages"
  reset_warn_once(other_id)
  withr::defer(reset_warn_once(other_id))
  testthat::expect_warning(
    d6_install_packages(packages = "a"),
    class = "condathis_deprecated_packages_arg"
  )

  # Invalid alias values are invalid packages.
  testthat::expect_identical(
    class(catch_error(d6_create_env(packages = NA))),
    invalid_packages_class("create_env")
  )
  # The alias with unnamed specs, or twice, aborts.
  testthat::expect_identical(
    class(catch_error(d6_create_env(packages = "a", "b"))),
    invalid_packages_class("create_env")
  )
  testthat::expect_identical(
    class(catch_error(d6_create_env(packages = "a", packages = "b"))),
    invalid_packages_class("create_env")
  )
})

testthat::test_that("collect_package_specs() warns about `packages =` only for direct use", {
  withr::local_options(lifecycle_verbosity = NULL)
  id <- "deprecated_packages_arg_create_env"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  collect <- function(user_env) {
    return(collect_package_specs(
      list(packages = "a"),
      fn = "create_env",
      formal_names = c("...", "env_name"),
      user_env = user_env
    ))
  }
  # Called from inside another package: no warning, and the id is not
  # used up.
  testthat::expect_no_warning(
    testthat::expect_identical(collect(asNamespace("tools")), "a")
  )
  testthat::expect_false(isTRUE(condathis_warn_once_state[[id]]))
  testthat::expect_warning(
    collect(globalenv()),
    class = "condathis_deprecated_packages_arg"
  )
  # The lifecycle_verbosity option and the tests of that package.
  reset_warn_once(id)
  withr::with_options(
    list(lifecycle_verbosity = "warning"),
    testthat::expect_warning(
      collect(asNamespace("tools")),
      class = "condathis_deprecated_packages_arg"
    )
  )
  reset_warn_once(id)
  withr::with_envvar(
    c(TESTTHAT_PKG = "tools"),
    testthat::expect_warning(
      collect(asNamespace("tools")),
      class = "condathis_deprecated_packages_arg"
    )
  )
  reset_warn_once(id)
  withr::with_options(
    list(lifecycle_verbosity = "quiet"),
    testthat::expect_no_warning(collect(globalenv()))
  )
})

testthat::test_that("collect_package_specs() points 0.1.4 positional values to their argument", {
  # install_packages(packages = x, "env"): 0.1.4's positional env_name.
  cnd <- catch_error(d6_install_packages(packages = "a", "my-env"))
  testthat::expect_identical(
    class(cnd),
    invalid_packages_class("install_packages")
  )
  testthat::expect_match(
    conditionMessage(cnd),
    "env_name = \"my-env\"",
    fixed = TRUE
  )
  # create_env(packages = x, "env.yml"): 0.1.4's positional env_file.
  cnd <- catch_error(d6_create_env(packages = "a", "env.yml"))
  testthat::expect_identical(class(cnd), invalid_packages_class("create_env"))
  testthat::expect_match(
    conditionMessage(cnd),
    "env_file = \"env.yml\"",
    fixed = TRUE
  )
  cnd <- catch_error(d6_create_env(packages = "a", "my-env"))
  testthat::expect_match(
    conditionMessage(cnd),
    "env_name = \"my-env\"",
    fixed = TRUE
  )
  # More than one value: only the general hint.
  cnd <- catch_error(d6_create_env(packages = "a", "b", "c"))
  testthat::expect_identical(class(cnd), invalid_packages_class("create_env"))
  testthat::expect_no_match(conditionMessage(cnd), "env_name", fixed = TRUE)

  # create_env("pkg", NULL, "env"): 0.1.4's positional env_file = NULL.
  cnd <- catch_error(d6_create_env("a", NULL, "my-env"))
  testthat::expect_identical(class(cnd), invalid_packages_class("create_env"))
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "must be named", fixed = TRUE)
  testthat::expect_match(message, "env_file = NULL", fixed = TRUE)
  cnd <- catch_error(d6_install_packages("a", NULL, "my-env"))
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "must be named", fixed = TRUE)
  testthat::expect_no_match(message, "env_file", fixed = TRUE)
  # A NULL at the end keeps the "no packages" hint.
  cnd <- catch_error(d6_create_env(NULL))
  testthat::expect_match(
    conditionMessage(cnd),
    "For no packages",
    fixed = TRUE
  )
})

testthat::test_that("collect_package_specs() names `packages` for its 0.1.4 abbreviations", {
  # Partial matching made these work in 0.1.4. They are not accepted.
  for (name in c("package", "pack", "pa")) {
    cnd <- catch_error(d6_create_env(!!!rlang::set_names(list("a"), name)))
    testthat::expect_identical(
      class(cnd),
      invalid_packages_class("create_env"),
      info = name
    )
    message <- cli::ansi_strip(conditionMessage(cnd))
    testthat::expect_match(message, "abbreviated `packages`", fixed = TRUE)
    testthat::expect_match(
      message,
      "create_env(\"pkg\", env_name = \"my-env\")",
      fixed = TRUE,
      info = name
    )
  }
  cnd <- catch_error(d6_install_packages(p = "a"))
  testthat::expect_identical(
    class(cnd),
    invalid_packages_class("install_packages")
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "abbreviated `packages`",
    fixed = TRUE
  )
  # `p` abbreviated `platform` of create_env() too: both are named.
  cnd <- catch_error(d6_create_env(p = "a"))
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "platform", fixed = TRUE)
  testthat::expect_match(message, "package specs unnamed", fixed = TRUE)
  testthat::expect_no_match(message, "0.1.4", fixed = TRUE)
  # validate_env() is new: no 0.1.4 sentence.
  cnd <- catch_error(collect_package_specs(
    list(pack = "a"),
    fn = "validate_env",
    formal_names = c("...", "env_name", "method")
  ))
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "package specs unnamed", fixed = TRUE)
  testthat::expect_no_match(message, "0.1.4", fixed = TRUE)
})

testthat::test_that("collect_package_specs() takes explicit formal names", {
  cnd <- catch_error(collect_package_specs(
    list("a", verbos = "silent"),
    fn = "validate_env",
    formal_names = c("...", "env_name", "verbose")
  ))
  testthat::expect_identical(class(cnd), invalid_packages_class("validate_env"))
  testthat::expect_match(conditionMessage(cnd), "verbose", fixed = TRUE)
})
