# `run_step()` only describes one command of a pipeline: everything here but
# the splicing test runs without micromamba.

testthat::test_that("run_step() records a command without running it", {
  step <- run_step("polyglot", "a", "b c", env_name = "run-step-env")
  testthat::expect_s3_class(step, "condathis_run_step", exact = TRUE)
  testthat::expect_true(is.list(step))
  testthat::expect_identical(
    names(step),
    c("cmd", "args", "env_name", "method", "stderr", "stderr_set")
  )
  testthat::expect_identical(step$cmd, "polyglot")
  testthat::expect_identical(step$args, c("a", "b c"))
  testthat::expect_identical(step$env_name, "run-step-env")
  testthat::expect_null(step$method)
  testthat::expect_null(step$stderr)
  testthat::expect_false(step$stderr_set)

  # Nothing is looked up: neither the command nor the environment exists.
  testthat::expect_no_error(
    run_step("condathis-no-such-command", env_name = "condathis-no-such-env")
  )
  # Nor is an environment given by path checked or created.
  missing_dir <- fs::path(withr::local_tempdir(), "run-step-missing")
  step <- run_step("polyglot", env_name = env_path(missing_dir))
  testthat::expect_s3_class(step$env_name, "condathis_env_path")
  testthat::expect_false(fs::dir_exists(missing_dir))
})

testthat::test_that("run_step() defaults to the pipeline's env_name and method", {
  step <- run_step("polyglot")
  testthat::expect_null(step$env_name)
  testthat::expect_null(step$method)
  testthat::expect_identical(step$args, character(0L))
  testthat::expect_identical(run_step("polyglot", NULL)$args, character(0L))
})

testthat::test_that("run_step() converts numeric arguments to character", {
  testthat::expect_identical(run_step("seq", 1, 3)$args, c("1", "3"))
  testthat::expect_identical(run_step("seq", 1L, 2.5)$args, c("1", "2.5"))
  testthat::expect_identical(
    run_step("seq", "-s", ",", 10L)$args,
    c("-s", ",", "10")
  )
  testthat::expect_identical(
    run_step("x", c("a", "b"), 3)$args,
    c("a", "b", "3")
  )
  testthat::expect_type(run_step("seq", 1, 3)$args, "character")
})

testthat::test_that("run_step() writes numbers in full, never in scientific notation", {
  # Regression test: `as.character()` wrote `100000` as "1e+05", so
  # `run_step("head", "-n", 100000)` made `head` fail with "invalid number
  # of lines", and `run_step("seq", 1, 1e6)` passed "1e+06".
  testthat::expect_identical(
    run_step("head", "-n", 100000)$args,
    c("-n", "100000")
  )
  testthat::expect_identical(run_step("seq", 1, 1e6)$args, c("1", "1000000"))
  testthat::expect_identical(run_step("x", 2^31)$args, "2147483648")
  testthat::expect_identical(
    run_step("x", 1e15, 1e22)$args,
    c(
      "1000000000000000",
      "10000000000000000000000"
    )
  )
  # Other doubles keep every digit needed to read back the same number.
  testthat::expect_identical(run_step("x", 0.1)$args, "0.1")
  testthat::expect_identical(run_step("x", 1 / 3)$args, "0.3333333333333333")
  testthat::expect_identical(
    run_step("x", 0.1 + 0.2)$args,
    "0.30000000000000004"
  )
  testthat::expect_identical(run_step("x", 2.5e-7)$args, "0.00000025")
  for (value in c(1 / 3, 0.1 + 0.2, 2 / 7, 1e-20, 123456.789, pi * 1e10)) {
    testthat::expect_identical(as.numeric(run_step("x", value)$args), value)
  }
  # Regression test: `format(scientific = FALSE)` only adds a penalty of
  # 100 characters to the scientific form, so doubles below about 1e-310
  # still came out as "4.94065645841247e-324".
  for (value in c(
    5e-324,
    -5e-324,
    1e-320,
    .Machine$double.xmin,
    .Machine$double.xmax
  )) {
    text <- run_step("x", value)$args
    testthat::expect_false(grepl("e", text, fixed = TRUE), label = text)
    # R reads these extreme values back exactly only with an extended
    # precision long double. Without one (arm64 macOS), subnormals read back
    # as 0 and the largest double as Inf, so the formatter falls back to 17
    # significant digits, which always identify a double; the command reads
    # the text with its own parser.
    if (isTRUE(.Machine$sizeof.longdouble > 8L)) {
      testthat::expect_identical(as.numeric(text), value)
    } else {
      testthat::expect_identical(
        text,
        format(value, digits = 17L, scientific = 1000L, trim = TRUE)
      )
    }
  }
  testthat::expect_identical(
    substr(run_step("x", 5e-324)$args, 1L, 6L),
    "0.0000"
  )
  testthat::expect_identical(run_step("x", -5)$args, "-5")
  testthat::expect_identical(run_step("x", -0)$args, "0")
  testthat::expect_identical(run_step("x", -2.5)$args, "-2.5")
  testthat::expect_identical(run_step("x", Inf, -Inf)$args, c("Inf", "-Inf"))
  # Integers and logical values.
  testthat::expect_identical(
    run_step("x", 100000L, -7L, .Machine$integer.max)$args,
    c("100000", "-7", "2147483647")
  )
  testthat::expect_identical(
    run_step("x", TRUE, FALSE)$args,
    c("TRUE", "FALSE")
  )
  # Mixed character and numeric values, also in one vector.
  testthat::expect_identical(
    run_step("x", "-n", 1e5, c(1e6, 0.5), "--flag", 3L, c("a", "b"))$args,
    c("-n", "100000", "1000000", "0.5", "--flag", "3", "a", "b")
  )
  # The decimal mark is always ".".
  withr::local_options(OutDec = ",", scipen = -9)
  testthat::expect_identical(run_step("x", 0.5, 1e5)$args, c("0.5", "100000"))
  # Values with a class use their own `as.character()` method.
  testthat::expect_identical(
    run_step("x", factor("level-b", levels = c("level-a", "level-b")))$args,
    "level-b"
  )
  testthat::expect_identical(
    run_step("x", as.Date("2026-01-02"))$args,
    "2026-01-02"
  )
  # Names are dropped.
  testthat::expect_identical(
    run_step("x", c(a = "1", b = "2"))$args,
    c("1", "2")
  )
})

testthat::test_that("run(), run_bin() and run_step() convert arguments the same way", {
  # One helper converts the `...` of the whole run() family.
  values <- list("-n", 100000, c(1e6, 0.1), 2^31, 1 / 3, -5, 7L, TRUE, NULL)
  expected <- c(
    "-n",
    "100000",
    "1000000",
    "0.1",
    "2147483648",
    "0.3333333333333333",
    "-5",
    "7",
    "TRUE"
  )
  testthat::expect_identical(
    cmd_args_as_character(values, class = "test_class"),
    expected
  )
  testthat::expect_identical(
    do.call(run_step, c(list("x"), values))$args,
    expected
  )
  testthat::expect_identical(
    cmd_args_as_character(list(), class = "test_class"),
    character(0L)
  )
  # The same invalid values fail, with each function's own class and the
  # shared one.
  for (bad in list(NA, NA_real_, c("a", NA), list("a"), function() "a", NaN)) {
    testthat::expect_error(
      cmd_args_as_character(list("ok", bad), class = "test_class"),
      class = "test_class"
    )
    testthat::expect_error(
      run_step("x", bad),
      class = "condathis_invalid_cmd_args"
    )
    testthat::expect_error(
      run("x", bad, env_name = "condathis-no-such-env"),
      class = "condathis_run_invalid_args"
    )
    testthat::expect_error(
      run_bin("x", bad, env_name = "condathis-no-such-env"),
      class = "condathis_run_bin_invalid_args"
    )
  }
})

testthat::test_that("run_step() rejects an invalid cmd", {
  invalid_cmds <- list(
    NULL,
    NA,
    NA_character_,
    "",
    c("seq", "1"),
    1,
    TRUE,
    list("seq")
  )
  for (cmd in invalid_cmds) {
    testthat::expect_error(
      run_step(cmd),
      class = "condathis_run_step_invalid_cmd"
    )
  }
  testthat::expect_error(run_step())
})

testthat::test_that("run_step() rejects invalid command arguments", {
  invalid_args <- list(
    list("a"),
    NA,
    NA_character_,
    NA_integer_,
    c("a", NA),
    function() "a"
  )
  for (arg in invalid_args) {
    testthat::expect_error(
      run_step("cmd", arg),
      class = "condathis_run_step_invalid_args"
    )
  }
  testthat::expect_error(
    run_step("cmd", "a", NA),
    class = "condathis_run_step_invalid_args"
  )
  # Arguments are unnamed: a misspelled option is an error, never an
  # argument (`env` does not partially match `env_name` after `...`). The
  # error has the condathis classes, as in run() and run_bin(), and names
  # the closest option. Before, it was rlang's `rlib_error_dots_named`,
  # without `condathis_error`.
  cnd <- testthat::expect_error(
    run_step("cmd", env = "run-step-env"),
    class = "condathis_run_step_invalid_args"
  )
  testthat::expect_identical(
    setdiff(class(cnd), c("rlang_error", "error", "condition")),
    c(
      "condathis_run_step_invalid_args",
      "condathis_invalid_cmd_args",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run_step")
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "`env` is named", fixed = TRUE)
  testthat::expect_match(message, "Did you mean `env_name`?", fixed = TRUE)
  # A named NULL is not dropped either.
  testthat::expect_error(
    run_step("cmd", verbose = NULL),
    class = "condathis_run_step_invalid_args"
  )
})

testthat::test_that("run_step() rejects an invalid env_name", {
  invalid_env_names <- list(
    NA,
    NA_character_,
    "",
    c("env-a", "env-b"),
    1,
    list("env-a"),
    "a/b",
    "..",
    "-n"
  )
  for (env_name in invalid_env_names) {
    testthat::expect_error(
      run_step("cmd", env_name = env_name),
      class = "condathis_run_step_invalid_env_name"
    )
  }
  # Names that would leave the envs directory also carry the shared class.
  testthat::expect_error(
    run_step("cmd", env_name = "../outside"),
    class = "condathis_invalid_env_name"
  )
  # A malformed environment given by path.
  testthat::expect_error(
    run_step(
      "cmd",
      env_name = structure(
        list(path = "relative"),
        class = "condathis_env_path"
      )
    ),
    class = "condathis_env_path_invalid"
  )
  # A valid environment given by path is kept as is.
  ep <- env_path(withr::local_tempdir())
  testthat::expect_identical(run_step("cmd", env_name = ep)$env_name, ep)
})

testthat::test_that("run_step() rejects an invalid method", {
  invalid_methods <- list(
    NA,
    NA_character_,
    c("auto", "micromamba"),
    1,
    TRUE,
    list("micromamba")
  )
  for (method in invalid_methods) {
    testthat::expect_error(
      run_step("cmd", method = method),
      class = "condathis_run_step_invalid_method"
    )
  }
  testthat::expect_identical(
    run_step("cmd", method = "micromamba")$method,
    "micromamba"
  )
})

testthat::test_that("run_step() checks its arguments in a fixed order", {
  # `run_step()` builds the step and checks it with the same function as
  # `run_pipeline()`. When several arguments are invalid, the first one in
  # the order of the signature is reported.
  testthat::expect_error(
    run_step(NA, list(1), env_name = 1, method = 1, stderr = 1),
    class = "condathis_run_step_invalid_cmd"
  )
  testthat::expect_error(
    run_step("cmd", list(1), env_name = 1, method = 1, stderr = 1),
    class = "condathis_run_step_invalid_args"
  )
  testthat::expect_error(
    run_step("cmd", env_name = 1, method = 1, stderr = 1),
    class = "condathis_run_step_invalid_env_name"
  )
  testthat::expect_error(
    run_step("cmd", method = 1, stderr = 1),
    class = "condathis_run_step_invalid_method"
  )
  # The error names the argument, and `run_step()` as the caller.
  cnd <- testthat::expect_error(
    run_step("cmd", stderr = 1),
    class = "condathis_run_step_invalid_stderr"
  )
  testthat::expect_match(conditionMessage(cnd), "stderr", fixed = TRUE)
  testthat::expect_identical(rlang::call_name(cnd$call), "run_step")
  # A step from `run_step()` always passes the pipeline check.
  step <- run_step("cmd", 1e5, env_name = "env-a", stderr = NULL)
  testthat::expect_identical(
    validate_run_step_object(step, index = 1L),
    step
  )
})

testthat::test_that("run_step() rejects an invalid stderr", {
  invalid_stderrs <- list(
    NA,
    NA_character_,
    c("|", "file.log"),
    1,
    TRUE,
    list("|")
  )
  for (stderr in invalid_stderrs) {
    testthat::expect_error(
      run_step("cmd", stderr = stderr),
      class = "condathis_run_step_invalid_stderr"
    )
  }
})

testthat::test_that("run_step() tells a missing stderr from stderr = NULL", {
  # Missing: the step uses the pipeline's stderr.
  step <- run_step("cmd")
  testthat::expect_false(step$stderr_set)
  testthat::expect_null(step$stderr)

  # NULL is a target of its own: discard.
  step <- run_step("cmd", stderr = NULL)
  testthat::expect_true(step$stderr_set)
  testthat::expect_null(step$stderr)
  testthat::expect_true("stderr" %in% names(step))

  for (target in c("|", "", "stage.log")) {
    step <- run_step("cmd", stderr = target)
    testthat::expect_true(step$stderr_set)
    testthat::expect_identical(step$stderr, target)
  }
})

testthat::test_that("run_step() has format and print methods", {
  testthat::expect_identical(
    format(run_step("cmd", "arg", "a b")),
    paste0("<run_step> cmd arg ", shQuote("a b"), " [env: pipeline default]")
  )
  # Words are quoted only when a shell would need it.
  testthat::expect_identical(
    format(run_step("cmd", "--flag", "a=b", "dir/file.txt", "", "$HOME")),
    paste(
      "<run_step> cmd --flag a=b dir/file.txt",
      shQuote(""),
      shQuote("$HOME"),
      "[env: pipeline default]"
    )
  )
  testthat::expect_identical(
    format(run_step("cmd", env_name = "run-step-env", method = "micromamba")),
    "<run_step> cmd [env: run-step-env, method: micromamba]"
  )
  ep <- env_path(withr::local_tempdir())
  testthat::expect_identical(
    format(run_step("cmd", 1, env_name = ep)),
    paste0("<run_step> cmd 1 [env: ", ep$path, "]")
  )

  step <- run_step("cmd", "arg", env_name = "run-step-env")
  out <- utils::capture.output(visible <- withVisible(print(step)))
  testthat::expect_identical(out, "<run_step> cmd arg [env: run-step-env]")
  testthat::expect_false(visible$visible)
  testthat::expect_identical(visible$value, step)
})

testthat::test_that("run_pipeline() names a misspelled option caught by ...", {
  steps <- list(run_step("cmd-a"), run_step("cmd-b"))
  cnd <- testthat::expect_error(
    run_pipeline(!!!steps, eror = "continue"),
    class = "condathis_pipeline_invalid_step"
  )
  testthat::expect_match(conditionMessage(cnd), "eror", fixed = TRUE)
  # Options after `...` never match partially.
  cnd <- testthat::expect_error(
    run_pipeline(!!!steps, env = "run-step-env"),
    class = "condathis_pipeline_invalid_step"
  )
  testthat::expect_match(conditionMessage(cnd), "`env`", fixed = TRUE)
  # A NULL value is not dropped either.
  cnd <- testthat::expect_error(
    run_pipeline(!!!steps, std_out = NULL),
    class = "condathis_pipeline_invalid_step"
  )
  testthat::expect_match(conditionMessage(cnd), "std_out", fixed = TRUE)

  # An unnamed value is named by its position.
  cnd <- testthat::expect_error(
    run_pipeline(run_step("cmd-a"), NULL, run_step("cmd-b")),
    class = "condathis_pipeline_invalid_step"
  )
  testthat::expect_match(conditionMessage(cnd), "Argument 2", fixed = TRUE)

  # A list of steps must be spliced, not passed as one value.
  testthat::expect_error(
    run_pipeline(steps),
    class = "condathis_pipeline_invalid_step"
  )
})

testthat::test_that("run_pipeline() accepts steps spliced in with !!!", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  create_polyglot_env("run-step-splice-env")

  steps <- list(run_step("polyglot"), run_step("polyglot"))
  res <- run_pipeline(
    !!!steps,
    env_name = "run-step-splice-env",
    verbose = "silent"
  )
  testthat::expect_s3_class(res, "condathis_pipeline")
  expect_pipeline_statuses_ok(res)
  testthat::expect_identical(parse_output(res)[[1L]], polyglot_expected_line())

  # Spliced and literal steps mix, in order; steps built in a loop.
  looped <- lapply(1:2, function(i) run_step("polyglot", i))
  res <- run_pipeline(
    run_step("polyglot", "first"),
    !!!looped,
    env_name = "run-step-splice-env",
    verbose = "silent"
  )
  expect_pipeline_statuses_ok(res, n = 3L)
  testthat::expect_identical(
    vapply(res$processes, `[[`, character(1L), "env_name"),
    rep("run-step-splice-env", 3L)
  )
  testthat::expect_match(res$processes[[1L]]$cmd, "first", fixed = TRUE)
  testthat::expect_match(res$processes[[3L]]$cmd, "2", fixed = TRUE)
})
