# Arguments must reach the command exactly as given, on every platform.
#
# Regression tests: on Windows, `micromamba run` wrapped the command in a
# temporary `.bat` script, so `cmd.exe` re-parsed every argument of `run()`.
# `>`, `<`, `|` and `&` turned into redirections and command separators,
# `^` and `%` were consumed, and newlines could not be passed at all.
# The probes in helper-argv-probe.R report every argument as hex, which
# makes any change visible.

argv_probe_cases <- function() {
  c(
    plain = "plain",
    gt = "a>b",
    lt = "a<b",
    pipe = "a|b",
    amp = "a&b",
    caret = "a^b",
    percent = "100%",
    percent_var = "%PATH%",
    dollar = "$HOME",
    backtick = "`id`",
    space = "a b",
    empty = "",
    double_quote = "a\"b",
    single_quote = "a'b",
    backslash = "a\\b",
    trailing_backslash = "dir\\",
    tab = "a\tb",
    newline = "a\nb",
    unicode = "\u00fcn\u00ef\u00e7\u00f8d\u00e9",
    bang = "!x!",
    parens = "(x)",
    semicolon = "a;b",
    star = "*",
    tilde = "~",
    quoted_space = "\"a b\"",
    spaced_meta = "a > b & c | d",
    equals = "k=v"
  )
}

expect_argv_roundtrip <- function(res) {
  cases <- argv_probe_cases()
  got <- argv_probe_decode(parse_output(res))
  testthat::expect_length(got, length(cases))
  for (i in seq_along(cases)) {
    testthat::expect_identical(
      got[[i]],
      unname(cases[[i]]),
      info = paste0("Argument '", names(cases)[[i]], "'")
    )
  }
}

testthat::test_that("run() passes arguments verbatim", {
  testthat::skip_on_cran()
  create_argv_probe_env()

  probe <- argv_probe_commands()$probe
  res <- run(
    probe[[1L]],
    probe[-1L],
    unname(argv_probe_cases()),
    env_name = "argv-probe-env",
    verbose = "silent"
  )
  expect_argv_roundtrip(res)
})

testthat::test_that("run_bin() passes arguments verbatim", {
  testthat::skip_on_cran()
  create_argv_probe_env()

  probe <- argv_probe_commands()$probe
  res <- run_bin(
    probe[[1L]],
    probe[-1L],
    unname(argv_probe_cases()),
    env_name = "argv-probe-env",
    verbose = "silent"
  )
  expect_argv_roundtrip(res)
})

testthat::test_that("run_pipeline() passes arguments verbatim", {
  testthat::skip_on_cran()
  create_argv_probe_env()

  probes <- argv_probe_commands()
  res <- run_pipeline(
    run_step(probes$probe[[1L]], probes$probe[-1L], unname(argv_probe_cases())),
    run_step(probes$cat[[1L]], probes$cat[-1L]),
    env_name = "argv-probe-env",
    verbose = "silent"
  )
  expect_argv_roundtrip(res)
})

# Numbers in `...` reach the command written in full: `as.character()`
# wrote `100000` as "1e+05".
argv_probe_number_args <- list(
  100000,
  1e6,
  2^31,
  0.1,
  1 / 3,
  -5,
  7L,
  TRUE,
  "text"
)
argv_probe_number_expected <- c(
  "100000",
  "1000000",
  "2147483648",
  "0.1",
  "0.3333333333333333",
  "-5",
  "7",
  "TRUE",
  "text"
)

testthat::test_that("run(), run_bin() and run_pipeline() write numbers in full", {
  testthat::skip_on_cran()
  create_argv_probe_env()

  probes <- argv_probe_commands()
  probe <- probes$probe
  res <- do.call(
    run,
    c(
      list(probe[[1L]], probe[-1L]),
      argv_probe_number_args,
      list(env_name = "argv-probe-env", verbose = "silent")
    )
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    argv_probe_decode(parse_output(res)),
    argv_probe_number_expected
  )
  # `cmd` is the whole command line through one `shQuote()` call, so the
  # quote character is not fixed: `shQuote()` uses `"` on Windows, and on
  # Linux and macOS also for every word when any word has a `'`, as the
  # `-c` code of the Python probes does.
  testthat::expect_identical(
    res$cmd,
    paste(shQuote(c(probe, argv_probe_number_expected)), collapse = " ")
  )

  res <- do.call(
    run_bin,
    c(
      list(probe[[1L]], probe[-1L]),
      argv_probe_number_args,
      list(env_name = "argv-probe-env", verbose = "silent")
    )
  )
  testthat::expect_identical(
    argv_probe_decode(parse_output(res)),
    argv_probe_number_expected
  )

  res <- run_pipeline(
    do.call(
      run_step,
      c(list(probe[[1L]], probe[-1L]), argv_probe_number_args)
    ),
    run_step(probes$cat[[1L]], probes$cat[-1L]),
    env_name = "argv-probe-env",
    verbose = "silent"
  )
  testthat::expect_identical(
    argv_probe_decode(parse_output(res)),
    argv_probe_number_expected
  )
})

testthat::test_that("run() on the backend path does not leak the caller's conda state", {
  testthat::skip_on_cran()
  create_argv_probe_env()

  # Regression test: `run_internal_backend()` built the child environment
  # as `c("current", <activation>)`, so the caller's own `MAMBA_*`/`CONDA_*`
  # settings, rc files and `R_HOME` reached the child. It now applies the
  # same clean-conda overlay as `run_bin()` and `run_pipeline()`.
  withr::local_envvar(
    MAMBA_ROOT_PREFIX = "/caller/mamba/root",
    CONDARC = "/caller/condarc.yml",
    CONDATHIS_PROBE_KEEP = "kept"
  )
  env_probe <- argv_probe_commands()$env
  res <- run_internal_backend(
    micromamba_backend(),
    env_probe[[1L]],
    env_probe[-1L],
    "MAMBA_ROOT_PREFIX",
    "CONDARC",
    "R_HOME",
    "CONDATHIS_PROBE_KEEP",
    "CONDA_PREFIX",
    env_name = "argv-probe-env",
    verbose = "silent"
  )
  out <- argv_probe_decode(parse_output(res))
  # Empty, never the caller's value, and never the root prefix that
  # micromamba's activation exports on Windows.
  testthat::expect_identical(out[[1L]], "")
  testthat::expect_identical(out[[2L]], "")
  testthat::expect_identical(out[[3L]], "")
  testthat::expect_identical(out[[4L]], "kept")
  testthat::expect_identical(
    fs::path_norm(out[[5L]]),
    fs::path_norm(get_env_dir("argv-probe-env"))
  )
})
