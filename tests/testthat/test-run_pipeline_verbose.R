# The `verbose` levels of `run_pipeline()`. No network access is needed
# once micromamba is installed: the environment comes from the local
# polyglot channel. In `polyglot | polyglot` the second `polyglot` ignores
# its stdin, so the last command's stdout is exactly one `polyglot` report.

# Two steps that write to standard error, R scripts run by R's own
# `Rscript` by absolute path, the same way on every platform. The first
# writes a line to stderr and one to stdout. The second reads its stdin to
# the end (so the first always exits on its own, also on Windows, where a
# stage whose reader exits early is killed), writes a line to stderr, and
# copies its stdin to stdout.
pipeline_verbose_r_steps <- function(
  first_stderr,
  .local_envir = parent.frame()
) {
  scripts_dir <- withr::local_tempdir(.local_envir = .local_envir)
  first_script <- file.path(scripts_dir, "first.R")
  last_script <- file.path(scripts_dir, "last.R")
  writeLines(
    c(
      "message(\"pipeline-verbose-stderr-1\")",
      "writeLines(\"pipeline-verbose-stdout\")"
    ),
    first_script
  )
  writeLines(
    c(
      "input <- readLines(file(\"stdin\"))",
      "message(\"pipeline-verbose-stderr-2\")",
      "writeLines(input)"
    ),
    last_script
  )
  rscript <- file.path(R.home("bin"), "Rscript")
  first_step <- if (missing(first_stderr)) {
    run_step(rscript, "--vanilla", first_script)
  } else {
    run_step(rscript, "--vanilla", first_script, stderr = first_stderr)
  }
  return(list(first_step, run_step(rscript, "--vanilla", last_script)))
}

# Whether any captured console line contains `text`.
has_line <- function(out, text) {
  return(any(grepl(text, out, fixed = TRUE)))
}

testthat::test_that("verbose = 'silent' and FALSE print nothing", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "pipeline-verbose-env"
  create_polyglot_env(env_name)

  for (verbose in list("silent", FALSE)) {
    testthat::expect_silent(
      res <- run_pipeline(
        run_step("polyglot"),
        run_step("polyglot"),
        env_name = env_name,
        verbose = verbose
      )
    )
    # Still captured.
    expect_pipeline_statuses_ok(res)
    testthat::expect_identical(
      parse_output(res)[[1L]],
      polyglot_expected_line()
    )
  }

  # Not even standard error.
  testthat::expect_silent(
    res <- run_pipeline(
      !!!pipeline_verbose_r_steps(),
      env_name = env_name,
      verbose = "silent"
    )
  )
  testthat::expect_identical(res$statuses, c(0L, 0L))
  testthat::expect_match(
    res$processes[[1L]]$stderr,
    "pipeline-verbose-stderr-1",
    fixed = TRUE
  )
})

testthat::test_that("verbose = 'spinner' prints nothing in a non-interactive session", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "pipeline-verbose-env"
  create_polyglot_env(env_name)

  withr::local_options(rlang_interactive = FALSE)
  testthat::expect_silent(
    res <- run_pipeline(
      run_step("polyglot"),
      run_step("polyglot"),
      env_name = env_name,
      verbose = "spinner"
    )
  )
  expect_pipeline_statuses_ok(res)
})

testthat::test_that("the default verbose echoes the last command's stdout", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "pipeline-verbose-env"
  create_polyglot_env(env_name)

  # The default, "output", and TRUE behave alike.
  testthat::expect_output(
    run_pipeline(
      run_step("polyglot"),
      run_step("polyglot"),
      env_name = env_name
    ),
    polyglot_expected_line(),
    fixed = TRUE
  )
  for (verbose in list("output", TRUE)) {
    out <- utils::capture.output(
      res <- run_pipeline(
        run_step("polyglot"),
        run_step("polyglot"),
        env_name = env_name,
        verbose = verbose
      )
    )
    # Exactly what was captured, once: only the last command reaches R.
    testthat::expect_identical(
      paste0(paste(out, collapse = "\n"), "\n"),
      res$processes[[2L]]$stdout
    )
    testthat::expect_identical(
      sum(grepl(polyglot_expected_line(), out, fixed = TRUE)),
      1L
    )
    testthat::expect_false(any(startsWith(out, "Running")))
  }
})

testthat::test_that("verbose = 'output' echoes every command's stderr, in red", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "pipeline-verbose-env"
  create_polyglot_env(env_name)
  steps <- pipeline_verbose_r_steps()

  out <- utils::capture.output(
    res <- run_pipeline(!!!steps, env_name = env_name)
  )
  testthat::expect_identical(res$statuses, c(0L, 0L))
  testthat::expect_true(has_line(out, "pipeline-verbose-stderr-1"))
  testthat::expect_true(has_line(out, "pipeline-verbose-stderr-2"))
  testthat::expect_true(has_line(out, "pipeline-verbose-stdout"))
  # The first command's stdout is piped on, so it reaches R once.
  testthat::expect_identical(
    sum(grepl("pipeline-verbose-stdout", out, fixed = TRUE)),
    1L
  )

  withr::local_options(cli.num_colors = 256L)
  out <- utils::capture.output(run_pipeline(!!!steps, env_name = env_name))
  # The ANSI code that opens red text, right before each stderr line.
  red <- cli::col_red("pipeline-verbose-stderr")
  red_open <- substr(red, 1L, regexpr("pipeline", red, fixed = TRUE) - 1L)
  testthat::expect_true(nzchar(red_open))
  all_out <- paste(out, collapse = "\n")
  for (i in 1:2) {
    testthat::expect_match(
      all_out,
      paste0(red_open, "pipeline-verbose-stderr-", i),
      fixed = TRUE
    )
  }
  # Standard output is not red.
  testthat::expect_false(
    grepl(paste0(red_open, "pipeline-verbose-stdout"), all_out, fixed = TRUE)
  )
})

testthat::test_that("stderr that is not captured is not echoed", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "pipeline-verbose-env"
  create_polyglot_env(env_name)

  # Discarded by the first step only.
  out <- utils::capture.output(
    res <- run_pipeline(
      !!!pipeline_verbose_r_steps(first_stderr = NULL),
      env_name = env_name
    )
  )
  testthat::expect_identical(res$statuses, c(0L, 0L))
  testthat::expect_false(has_line(out, "pipeline-verbose-stderr-1"))
  testthat::expect_true(has_line(out, "pipeline-verbose-stderr-2"))
  testthat::expect_true(has_line(out, "pipeline-verbose-stdout"))

  # Sent to a file by the pipeline: only stdout is echoed.
  stderr_file <- withr::local_tempfile(fileext = ".log")
  out <- utils::capture.output(
    res <- run_pipeline(
      !!!pipeline_verbose_r_steps(),
      env_name = env_name,
      stderr = stderr_file
    )
  )
  testthat::expect_identical(res$statuses, c(0L, 0L))
  testthat::expect_false(has_line(out, "pipeline-verbose-stderr"))
  testthat::expect_true(has_line(out, "pipeline-verbose-stdout"))
  stderr_lines <- readLines(stderr_file)
  testthat::expect_true(has_line(stderr_lines, "pipeline-verbose-stderr-1"))
  testthat::expect_true(has_line(stderr_lines, "pipeline-verbose-stderr-2"))
})

testthat::test_that("verbose = 'cmd' prints the pipeline first, and no output", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "pipeline-verbose-env"
  create_polyglot_env(env_name)

  out <- utils::capture.output(
    res <- run_pipeline(
      run_step("polyglot"),
      run_step("polyglot", "a b"),
      env_name = env_name,
      verbose = "cmd"
    )
  )
  testthat::expect_length(out, 1L)
  testthat::expect_match(out, "^Running ")
  testthat::expect_match(out, " | ", fixed = TRUE)
  # Words are quoted only when needed.
  testthat::expect_identical(
    out,
    paste("Running polyglot | polyglot", shQuote("a b"))
  )
  expect_pipeline_statuses_ok(res)
  testthat::expect_identical(parse_output(res)[[1L]], polyglot_expected_line())

  # Not even standard error.
  out <- utils::capture.output(
    run_pipeline(
      !!!pipeline_verbose_r_steps(),
      env_name = env_name,
      verbose = "cmd"
    )
  )
  testthat::expect_length(out, 1L)
  testthat::expect_match(out, "^Running ")
})

testthat::test_that("verbose = 'full' prints the pipeline, then its output", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "pipeline-verbose-env"
  create_polyglot_env(env_name)

  out <- utils::capture.output(
    res <- run_pipeline(
      run_step("polyglot"),
      run_step("polyglot"),
      env_name = env_name,
      verbose = "full"
    )
  )
  testthat::expect_identical(out[[1L]], "Running polyglot | polyglot")
  testthat::expect_identical(
    paste0(paste(out[-1L], collapse = "\n"), "\n"),
    res$processes[[2L]]$stdout
  )
  testthat::expect_true(has_line(out, polyglot_expected_line()))

  out <- utils::capture.output(
    run_pipeline(
      !!!pipeline_verbose_r_steps(),
      env_name = env_name,
      verbose = "full"
    )
  )
  testthat::expect_match(out[[1L]], "^Running ")
  testthat::expect_match(out[[1L]], " | ", fixed = TRUE)
  echoed <- out[-1L]
  testthat::expect_true(has_line(echoed, "pipeline-verbose-stderr-1"))
  testthat::expect_true(has_line(echoed, "pipeline-verbose-stderr-2"))
  testthat::expect_true(has_line(echoed, "pipeline-verbose-stdout"))
})

testthat::test_that("binary = TRUE never echoes", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "pipeline-verbose-env"
  create_polyglot_env(env_name)
  steps <- pipeline_verbose_r_steps()

  for (verbose in c("output", "full")) {
    out <- utils::capture.output(
      res <- run_pipeline(
        !!!steps,
        env_name = env_name,
        binary = TRUE,
        verbose = verbose
      )
    )
    testthat::expect_identical(res$statuses, c(0L, 0L))
    testthat::expect_true(is.raw(res$processes[[2L]]$stdout))
    testthat::expect_true(is.raw(res$processes[[1L]]$stderr))
    testthat::expect_match(
      rawToChar(res$processes[[1L]]$stderr),
      "pipeline-verbose-stderr-1",
      fixed = TRUE
    )
    testthat::expect_match(
      rawToChar(res$processes[[2L]]$stdout),
      "pipeline-verbose-stdout",
      fixed = TRUE
    )
    # Only "full" prints a line: the "Running" line, with the commands, not
    # their output.
    if (identical(verbose, "full")) {
      testthat::expect_length(out, 1L)
      testthat::expect_match(out, "^Running ")
    } else {
      testthat::expect_length(out, 0L)
    }
  }
})

testthat::test_that("stdout that is not captured is not echoed", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "pipeline-verbose-env"
  create_polyglot_env(env_name)

  stdout_file <- withr::local_tempfile(fileext = ".txt")
  testthat::expect_silent(
    res <- run_pipeline(
      run_step("polyglot"),
      run_step("polyglot"),
      env_name = env_name,
      stdout = stdout_file
    )
  )
  expect_pipeline_statuses_ok(res)
  testthat::expect_identical(
    readLines(stdout_file)[[1L]],
    polyglot_expected_line()
  )

  testthat::expect_silent(
    run_pipeline(
      run_step("polyglot"),
      run_step("polyglot"),
      env_name = env_name,
      stdout = NULL
    )
  )

  # Standard error is still echoed.
  out <- utils::capture.output(
    run_pipeline(
      !!!pipeline_verbose_r_steps(),
      env_name = env_name,
      stdout = withr::local_tempfile(fileext = ".txt")
    )
  )
  testthat::expect_false(has_line(out, "pipeline-verbose-stdout"))
  testthat::expect_true(has_line(out, "pipeline-verbose-stderr-2"))
})

testthat::test_that("run_pipeline() rejects an unknown verbose level", {
  # The shared verbose classes, and the error names the user's call.
  cnd <- testthat::expect_error(
    run_pipeline(
      run_step("polyglot"),
      run_step("polyglot"),
      verbose = "loud"
    ),
    regexp = "verbose",
    class = "condathis_invalid_verbose"
  )
  testthat::expect_s3_class(cnd, "condathis_invalid_arg")
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "run_pipeline"
  )
})

testthat::test_that("the spinner never splits an echoed line", {
  testthat::skip_on_cran()
  rscript <- file.path(R.home("bin"), "Rscript")
  proc <- processx::process$new(
    rscript,
    c(
      "--vanilla",
      "-e",
      "cat('partial'); flush(stdout()); Sys.sleep(0.8); cat(' done\\n')"
    ),
    stdout = "|",
    stderr = "|"
  )
  withr::defer(if (isTRUE(proc$is_alive())) proc$kill())
  # `utils::capture.output()`, not `testthat::capture_output()`, which
  # turns carriage returns into line breaks.
  out <- paste(
    utils::capture.output(
      res <- pump_pipeline_io(list(proc), echo = TRUE, spinner = TRUE)
    ),
    collapse = "\n"
  )
  proc$wait()
  # Windows writes text-mode line endings as "\r\n".
  testthat::expect_identical(
    gsub("\r\n", "\n", res$stdout[[1L]], fixed = TRUE),
    "partial done\n"
  )
  # Frames are drawn as "\r<frame>\r" only at the start of a line, so the
  # partial line is printed whole.
  testthat::expect_match(out, "partial done", fixed = TRUE)
  testthat::expect_match(out, "\r-\r", fixed = TRUE)
})
