# The credentials of channel URLs (`/t/<token>/`, `user:password@`) never
# appear in what condathis prints or returns: micromamba hides them in its
# own output (`hide_secrets()` of libmamba), rattlerthis in everything it
# writes and says. condathis printed them with `verbose = "cmd"` and
# `"full"`, and returned them in `cmd`.

# A channel URL with both kinds of credentials, and its hidden form.
secret_channel <- "http://rt-user:s3cr3t-pw@127.0.0.1:9/t/tk-SECRET1234/chan"
hidden_channel <- "http://rt-user:*****@127.0.0.1:9/t/*****/chan"

# Whether any text in `x` (a character vector or a list of them) has a
# secret of `secret_channel`.
has_secret <- function(x) {
  text <- unlist(x)
  return(any(
    grepl("s3cr3t-pw", text, fixed = TRUE) |
      grepl("tk-SECRET1234", text, fixed = TRUE)
  ))
}

# The lines of `format(x)` without the previews of the output, which is the
# command's own.
format_lines_but_output <- function(x) {
  lines <- strsplit(format(x), "\n", fixed = TRUE)[[1L]]
  return(lines[!grepl("^ *(stdout|stderr): ", lines)])
}

# The texts of an error and of all its parents: messages and the `stderr`,
# `stdout` and `cmd` fields.
condition_texts <- function(cnd) {
  texts <- character(0L)
  while (isFALSE(is.null(cnd))) {
    texts <- c(
      texts,
      conditionMessage(cnd),
      unlist(cnd[intersect(c("stderr", "stdout", "cmd"), names(cnd))])
    )
    cnd <- cnd$parent
  }
  return(texts)
}

testthat::test_that("hide_secrets() hides tokens and passwords as libmamba and rattlerthis do", {
  # The cases of `secrets::tests` in rattlerthis (`src/rust/src/secrets.rs`)
  # and of libmamba's `hide_secrets()`.
  cases <- c(
    "HTTP status 404 Not Found for http://h:1/t/SECRETTOK/chA/noarch/foo-1.0-0.tar.bz2" = "HTTP status 404 Not Found for http://h:1/t/*****/chA/noarch/foo-1.0-0.tar.bz2",
    "failed (http://rt-user:rt-pw@127.0.0.1:1/chA/x) and https://a:b@c" = "failed (http://rt-user:*****@127.0.0.1:1/chA/x) and https://a:*****@c",
    "http://u:p@h/t/ab/c http://h/t/x/y" = "http://u:*****@h/t/*****/c http://h/t/x/y",
    # A password with `@`, one in quotes and two URLs without white space
    # between them, as in JSON.
    "https://u:p@ss@h/c" = "https://u:*****@h/c",
    "'https://u:p@h/c'" = "'https://u:*****@h/c'",
    "{\"a\":\"https://u:p@h/c\",\"b\":\"https://v:q@h2/c\"}" = "{\"a\":\"https://u:*****@h/c\",\"b\":\"https://v:*****@h2/c\"}",
    # A `:` and `@` after the host are not a login.
    "https://u:p@h/x:y@z" = "https://u:*****@h/x:y@z",
    # anaconda.org user names: `_` only in the first two characters.
    "https://h/t/ab_cd/c" = "https://h/t/*****_cd/c",
    "https://h/t/a_/c" = "https://h/t/*****/c",
    # Hidden already (libmamba's `*****`, rattler's `********`).
    "http://u:*****@h/t/*****/c" = "http://u:*****@h/t/*****/c",
    "http://h/t/********/c" = "http://h/t/*****/c",
    # An IPv6 host and ANSI colors around a URL.
    "http://u:p@[::1]:8/c" = "http://u:*****@[::1]:8/c",
    "\033[34mhttps://u:p@h\033[39m" = "\033[34mhttps://u:*****@h\033[39m",
    # Nothing to hide.
    "no url here" = "no url here",
    "http://h/chA/noarch" = "http://h/chA/noarch",
    "user@host: denied" = "user@host: denied",
    "https://user@host/c" = "https://user@host/c",
    "a://b" = "a://b",
    "https://host/t/" = "https://host/t/",
    "https://host/t/x" = "https://host/t/x"
  )
  testthat::expect_identical(unname(hide_secrets(names(cases))), unname(cases))
  # Idempotent.
  testthat::expect_identical(unname(hide_secrets(cases)), unname(cases))

  # Names, `NA` and other values are kept; non-ASCII text too.
  x <- c(a = secret_channel, b = NA, c = "caf\u00e9 https://u:p\u00e9@h/c")
  testthat::expect_identical(
    hide_secrets(x),
    c(a = hidden_channel, b = NA, c = "caf\u00e9 https://u:*****@h/c")
  )
  testthat::expect_identical(hide_secrets(character(0L)), character(0L))
  testthat::expect_identical(hide_secrets(NULL), NULL)
  testthat::expect_identical(hide_secrets(1:3), 1:3)
  # Text that is not valid UTF-8 is read as bytes.
  invalid <- "https://u:p@h/\xff/t/abc"
  testthat::expect_identical(
    charToRaw(hide_secrets(invalid)),
    charToRaw("https://u:*****@h/\xff/t/*****")
  )
})

testthat::test_that("the Running line is the one of processx, with the credentials hidden", {
  # Regression test: `processx` printed the command line of micromamba
  # with the password and the token of each channel.
  args <- c("create", "-c", secret_channel, "pkg a", "", "x=1")
  for (width in c(40L, 80L, 200L)) {
    withr::local_options(width = width)
    plain <- utils::capture.output(
      processx:::do_echo_cmd("/opt/bin/micromamba", c(args[-3L], "y"))
    )
    testthat::expect_identical(
      utils::capture.output(
        echo_command_line("/opt/bin/micromamba", c(args[-3L], "y"))
      ),
      plain
    )
    out <- utils::capture.output(
      echo_command_line("/opt/bin/micromamba", args)
    )
    testthat::expect_false(has_secret(out))
    testthat::expect_true(any(grepl(hidden_channel, out, fixed = TRUE)))
  }
  testthat::expect_identical(
    format_cmd_line(c("/bin/micromamba", "-c", secret_channel)),
    paste(shQuote(c("/bin/micromamba", "-c", hidden_channel)), collapse = " ")
  )
})

testthat::test_that("execute_command() echoes the credentials hidden and passes them on", {
  testthat::skip_on_cran()
  script <- "cat(commandArgs(TRUE), sep = '\\n')"
  for (stdin in list(NULL, "|")) {
    out <- utils::capture.output(
      px_res <- execute_command(
        command = run_family_rscript(),
        args = c("--vanilla", "-e", script, secret_channel),
        echo_cmd = TRUE,
        stdin = stdin,
        input = if (identical(stdin, "|")) ""
      )
    )
    info <- if (is.null(stdin)) "processx::run()" else "writable stdin"
    testthat::expect_identical(px_res$status, 0L, label = info)
    testthat::expect_match(out[[1L]], "^Running ", label = info)
    testthat::expect_false(has_secret(out), label = info)
    testthat::expect_true(any(grepl(hidden_channel, out, fixed = TRUE)))
    # The process got the credentials.
    testthat::expect_identical(
      trimws(px_res$stdout),
      secret_channel,
      label = info
    )
  }
})

testthat::test_that("native_cmd() hides the credentials in cmd and passes them to micromamba", {
  fake_bin <- fs::path(withr::local_tempdir(), "micromamba")
  fs::file_create(fake_bin)
  spawned <- NULL
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function(...) fake_bin,
    execute_command = function(command, args, ...) {
      spawned <<- list(command = command, args = args)
      return(list(status = 0L, stdout = "", stderr = "", timeout = FALSE))
    }
  )
  px_res <- native_cmd(
    conda_cmd = "create",
    conda_args = c("-n", "secret-env", "-c", secret_channel),
    "pkg",
    verbose = "silent"
  )
  testthat::expect_true(secret_channel %in% spawned$args)
  testthat::expect_false(has_secret(px_res$cmd))
  testthat::expect_match(px_res$cmd, hidden_channel, fixed = TRUE)
})

testthat::test_that("condathis messages, warnings and errors hide the credentials", {
  f <- function(url) {
    condathis_abort(
      c(`x` = "Bad channel {.val {url}}.", `i` = "See {.url {url}}."),
      class = "condathis_f_failed",
      status = 2L
    )
  }
  cnd <- rlang::catch_cnd(f(secret_channel), classes = "error")
  testthat::expect_s3_class(cnd, "condathis_f_failed")
  testthat::expect_identical(cnd$status, 2L)
  testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "f")
  testthat::expect_false(has_secret(conditionMessage(cnd)))
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    paste0("Bad channel \"", hidden_channel, "\"."),
    fixed = TRUE
  )
  # A backend failure keeps its marker.
  cnd <- rlang::catch_cnd(
    condathis_abort(
      "Failed for {secret_channel}.",
      class = "condathis_backend_error"
    ),
    classes = "error"
  )
  testthat::expect_true(is_condathis_backend_error(cnd))
  testthat::expect_false(has_secret(conditionMessage(cnd)))

  cnd <- rlang::catch_cnd(
    condathis_warn(c(`!` = "Channel {.field {secret_channel}}."), class = "x"),
    classes = "warning"
  )
  testthat::expect_s3_class(cnd, "condathis_warning")
  testthat::expect_false(has_secret(conditionMessage(cnd)))
  testthat::expect_match(conditionMessage(cnd), hidden_channel, fixed = TRUE)

  cnd <- rlang::catch_cnd(
    condathis_inform(
      c(`v` = "Package {.field {secret_channel}::pkg} installed."),
      class = "condathis_x_message"
    ),
    classes = "message"
  )
  testthat::expect_s3_class(cnd, "condathis_x_message")
  testthat::expect_false(has_secret(conditionMessage(cnd)))
  testthat::expect_match(conditionMessage(cnd), hidden_channel, fixed = TRUE)
})

testthat::test_that("the cmd of a backend's result has the credentials hidden", {
  stub <- local_stub_backend(
    "stub-secret",
    backend_create_env = function(backend, env_name = "condathis-env", ...) {
      fs::dir_create(fs::path(
        backend_get_install_dir(backend),
        "envs",
        env_name
      ))
      return(list(status = 0L, cmd = paste("tool create -c", secret_channel)))
    },
    backend_clean_cache = function(backend, ...) {
      return(list(status = 0L, cmd = paste("tool clean -c", secret_channel)))
    }
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-secret"
  )
  res <- create_env(
    env_name = "secret-cmd-env",
    channels = secret_channel,
    method = "stub-secret",
    verbose = "silent"
  )
  testthat::expect_identical(res$cmd, paste("tool create -c", hidden_channel))
  res <- new_clean_cache_result(
    list(status = 0L, cmd = paste("tool clean -c", secret_channel)),
    backend_name = "stub-secret",
    call = rlang::current_env()
  )
  testthat::expect_identical(res$cmd, paste("tool clean -c", hidden_channel))
})

testthat::test_that("the run family hides the credentials in its echo, cmd and errors, not in the output", {
  testthat::skip_on_cran()
  local_run_family_stub()
  rscript <- run_family_rscript()
  script <- "cat(commandArgs(TRUE), sep = '\\n')"
  out <- utils::capture.output(
    res <- run(
      rscript,
      "--vanilla",
      "-e",
      script,
      secret_channel,
      env_name = "stub-env",
      verbose = "cmd"
    )
  )
  testthat::expect_match(out[[1L]], "^Running ")
  testthat::expect_false(has_secret(out))
  testthat::expect_true(any(grepl(hidden_channel, out, fixed = TRUE)))
  testthat::expect_false(has_secret(res$cmd))
  testthat::expect_match(res$cmd, hidden_channel, fixed = TRUE)
  testthat::expect_false(has_secret(format_lines_but_output(res)))
  # The command got the credentials, and its output is its own.
  testthat::expect_identical(trimws(res$stdout), secret_channel)

  # The error of a failed command shows its standard error with the
  # credentials hidden; the `stderr` field is the command's own.
  fail_script <- "message(commandArgs(TRUE)); quit(status = 3L)"
  cnd <- rlang::catch_cnd(
    run(
      rscript,
      "--vanilla",
      "-e",
      fail_script,
      secret_channel,
      env_name = "stub-env",
      verbose = "silent"
    ),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_run_status_error")
  testthat::expect_false(has_secret(conditionMessage(cnd)))
  testthat::expect_match(conditionMessage(cnd), hidden_channel, fixed = TRUE)
  testthat::expect_match(cnd$stderr, secret_channel, fixed = TRUE)

  out <- utils::capture.output(
    res <- run_bin(
      rscript,
      "--vanilla",
      "-e",
      script,
      secret_channel,
      env_name = "stub-env",
      verbose = "cmd"
    )
  )
  testthat::expect_false(has_secret(out))
  testthat::expect_true(any(grepl(hidden_channel, out, fixed = TRUE)))
  testthat::expect_false(has_secret(res$cmd))
  testthat::expect_identical(trimws(res$stdout), secret_channel)

  out <- utils::capture.output(
    res <- run_pipeline(
      run_step(rscript, "--vanilla", "-e", script, secret_channel),
      run_step(
        rscript,
        "--vanilla",
        "-e",
        "cat(readLines(file('stdin')), sep = '\\n')"
      ),
      env_name = "stub-env",
      verbose = "cmd"
    )
  )
  testthat::expect_false(has_secret(out))
  testthat::expect_true(any(grepl(hidden_channel, out, fixed = TRUE)))
  testthat::expect_false(has_secret(res$cmd))
  testthat::expect_false(has_secret(lapply(res$processes, `[[`, "cmd")))
  testthat::expect_false(has_secret(format_lines_but_output(res)))
  testthat::expect_identical(
    trimws(res$processes[[2L]]$stdout),
    secret_channel
  )
  testthat::expect_false(has_secret(format(run_step("tool", secret_channel))))
})

testthat::test_that("history channels and list_packages() have the credentials hidden", {
  # micromamba and rattler record channels with the credentials hidden;
  # the records of other tools may keep them.
  env_dir <- withr::local_tempdir()
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  writeLines(
    c(
      "==> 2026-01-01 00:00:00 <==",
      paste0("# cmd: micromamba create -c ", secret_channel),
      paste0("+", secret_channel, "/noarch::polyglot-0.1.0-h0_0"),
      "+https://conda.anaconda.org/t/tk-SECRET1234/conda-forge/noarch::x-1-0"
    ),
    con = fs::path(env_dir, "conda-meta", "history")
  )
  channels <- get_env_history_channels(env_dir)
  testthat::expect_identical(channels, c(hidden_channel, "conda-forge"))
  cnd <- rlang::catch_cnd(
    warn_on_missing_previous_channels(
      env_dir = env_dir,
      env_name = "hist-env",
      packages = "polyglot",
      channels = "bioconda"
    ),
    classes = "warning"
  )
  testthat::expect_s3_class(
    cnd,
    "condathis_install_packages_missing_previous_channels"
  )
  testthat::expect_false(has_secret(conditionMessage(cnd)))

  record <- paste0(
    '[{"base_url":"',
    secret_channel,
    '","build_number":0,"build_string":"h0_0","channel":"',
    secret_channel,
    '","dist_name":"polyglot-0.1.0-h0_0","name":"polyglot",',
    '"platform":"noarch","url":"',
    secret_channel,
    '/noarch/polyglot-0.1.0-h0_0.conda","version":"0.1.0"}]'
  )
  condathis::with_sandbox_dir({
    env_dir <- fs::path(
      install_dir_for_backend(micromamba_backend()),
      "envs",
      "secret-list-env"
    )
    fs::dir_create(fs::path(env_dir, "conda-meta"))
    fs::file_create(fs::path(env_dir, "conda-meta", "history"))
    testthat::local_mocked_bindings(
      backend_probe_env = function(...) TRUE,
      native_cmd = function(...) {
        list(status = 0L, stdout = record, stderr = "", timeout = FALSE)
      }
    )
    pkgs <- list_packages("secret-list-env", verbose = "silent")
    testthat::expect_identical(pkgs$name, "polyglot")
    testthat::expect_false(has_secret(as.list(pkgs)))
    testthat::expect_identical(pkgs$channel, hidden_channel)
    testthat::expect_identical(
      pkgs$url,
      paste0(hidden_channel, "/noarch/polyglot-0.1.0-h0_0.conda")
    )
  })
})

testthat::test_that("create_env() never prints the credentials of a channel with micromamba", {
  # End to end: a channel that refuses the connection, so micromamba fails
  # after condathis printed its command line, and the error names the
  # channel.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  local_sandbox_micromamba()
  condathis::with_sandbox_dir({
    out <- utils::capture.output(
      cnd <- rlang::catch_cnd(
        create_env(
          "polyglot",
          env_name = "secret-channel-env",
          channels = secret_channel,
          verbose = "cmd"
        ),
        classes = "error"
      )
    )
    testthat::expect_s3_class(cnd, "condathis_create_env_failed")
    testthat::expect_match(out[[1L]], "^Running ")
    testthat::expect_false(has_secret(out))
    testthat::expect_true(any(grepl(hidden_channel, out, fixed = TRUE)))
    testthat::expect_false(has_secret(condition_texts(cnd)))
    testthat::expect_false(env_exists("secret-channel-env"))
  })
})
