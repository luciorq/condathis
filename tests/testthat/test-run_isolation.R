# The commands of run(), run_bin() and run_pipeline() never get the
# activation of the R session: R running in an activated Conda or pixi
# environment, or in several nested ones (see isolate_host_env()).

# Runs `Rscript` in `env_name` the way `fn` does, with `activate`, and
# returns the environment it saw. On Windows, `Rscript` puts the Rtools
# directories in front of the PATH it was given: read the PATH with
# `rscript_dumped_path_entries()`. `fn` is "run", "run_bin" or
# "run_pipeline" (the first of two stages dumps).
run_isolation_dump <- function(fn, activate, env_name = "stub-env") {
  dump_file <- tempfile(fileext = ".rds")
  withr::defer(unlink(dump_file))
  dump_args <- c(
    "--vanilla",
    "-e",
    paste0(
      "saveRDS(as.list(Sys.getenv()), ",
      deparse(gsub("\\\\", "/", dump_file)),
      ")"
    )
  )
  rscript <- run_family_rscript()
  res <- switch(
    fn,
    run = run(
      rscript,
      dump_args,
      env_name = env_name,
      activate = activate,
      verbose = "silent"
    ),
    run_bin = run_bin(
      rscript,
      dump_args,
      env_name = env_name,
      activate = activate,
      verbose = "silent"
    ),
    run_pipeline = run_pipeline(
      run_step(rscript, dump_args),
      run_step(
        rscript,
        "--vanilla",
        "-e",
        "invisible(readLines(file('stdin')))"
      ),
      env_name = env_name,
      activate = activate,
      verbose = "silent"
    )
  )
  testthat::expect_identical(res$status, 0L)
  return(readRDS(dump_file))
}

# The calls to check: each function, with and without activation.
run_isolation_cases <- function() {
  return(list(
    list(fn = "run", activate = TRUE),
    list(fn = "run", activate = FALSE),
    list(fn = "run_bin", activate = TRUE),
    list(fn = "run_bin", activate = FALSE),
    list(fn = "run_pipeline", activate = TRUE),
    list(fn = "run_pipeline", activate = FALSE)
  ))
}

# The checks that hold in both modes. A marker variable may be set by the
# activation of the environment itself (micromamba's sets `MAMBA_EXE`),
# never with the value of the host.
expect_no_host_activation <- function(seen, host, info) {
  for (name in fake_host_marker_names()) {
    testthat::expect_false(
      identical(seen[[name]], host$vars[[name]]),
      info = paste(info, name)
    )
  }
  path <- seen[[match_env_name(names(seen), "PATH")]]
  testthat::expect_false(
    path_names_any(path, vapply(host$prefixes, fake_host_bin, character(1L))),
    info = info
  )
  testthat::expect_true(path_names_any(path, host$keep_dir), info = info)
  testthat::expect_identical(
    seen[["CONDATHIS_HOST_SAVED"]],
    "before",
    info = info
  )
  testthat::expect_identical(
    seen[["CONDATHIS_HOST_CC"]],
    "user-cc",
    info = info
  )
  testthat::expect_identical(
    seen[["CONDATHIS_HOST_SCHEMA"]],
    "user-schema",
    info = info
  )
  testthat::expect_null(seen[["CONDATHIS_HOST_ENVVAR"]], info = info)
  testthat::expect_null(seen[["CONDATHIS_STATE"]], info = info)
  testthat::expect_identical(seen[["CONDATHIS_HOST_USER"]], "user", info = info)
  return(invisible(NULL))
}

test_that("run(), run_bin() and run_pipeline() never see the host activation, with and without activation", {
  host <- local_fake_nested_host()
  # The activation of the stub sets no PATH: condathis puts the
  # environment's directories in front of the PATH of `base_env`.
  stub <- local_run_family_stub(
    backend_resolve_run = function(
      backend,
      cmd,
      args = character(0L),
      ...
    ) {
      return(list(
        command = cmd,
        args = args,
        env = c(CONDATHIS_STUB_ACTIVATED = "yes"),
        dir = NULL
      ))
    }
  )
  env_dir <- as.character(fs::path(stub$root, "envs", "stub-env"))
  for (case in run_isolation_cases()) {
    info <- paste(case$fn, "activate:", case$activate)
    calls_before <- length(stub_calls(stub, "backend_resolve_run"))
    seen <- run_isolation_dump(case$fn, case$activate)
    calls_after <- length(stub_calls(stub, "backend_resolve_run"))
    expect_no_host_activation(seen, host, info)
    entries <- rscript_dumped_path_entries(
      seen[[match_env_name(names(seen), "PATH")]]
    )
    bin_dirs <- as.character(env_bin_search_dirs(env_dir))
    testthat::expect_identical(
      path_entry_key(entries[seq_along(bin_dirs)]),
      path_entry_key(bin_dirs),
      info = info
    )
    # The host's prompt never reaches the command, in either mode.
    for (prompt_var in c("CONDA_PROMPT_MODIFIER", "MAMBA_PROMPT_MODIFIER")) {
      testthat::expect_identical(seen[[prompt_var]] %||% "", "", info = info)
    }
    if (isTRUE(case$activate)) {
      testthat::expect_identical(
        seen[["CONDATHIS_STUB_ACTIVATED"]],
        "yes",
        info = info
      )
      testthat::expect_identical(seen[["CONDA_PREFIX"]], "", info = info)
      testthat::expect_identical(seen[["CONDA_SHLVL"]], "1", info = info)
      testthat::expect_identical(seen[["MAMBA_SHLVL"]], "1", info = info)
      testthat::expect_true(calls_after > calls_before, info = info)
    } else {
      testthat::expect_null(seen[["CONDATHIS_STUB_ACTIVATED"]], info = info)
      testthat::expect_identical(calls_after, calls_before, info = info)
      testthat::expect_identical(
        as.character(fs::path_norm(seen[["CONDA_PREFIX"]])),
        as.character(fs::path_norm(env_dir)),
        info = info
      )
      testthat::expect_identical(seen[["CONDA_SHLVL"]], "1", info = info)
      testthat::expect_identical(seen[["MAMBA_SHLVL"]], "1", info = info)
      testthat::expect_identical(
        seen[["CONDA_DEFAULT_ENV"]],
        "stub-env",
        info = info
      )
    }
  }
})

test_that("a host program never runs in place of a missing one", {
  # On Windows, run() leaves a bare name that the environment lacks to
  # processx, which searches the PATH of the R session for `.exe` and
  # `.com` files only: the `.cmd` tool of the fake host is not found
  # either. A host `.exe` would be (a known limit).
  local_fake_nested_host()
  local_run_family_stub()
  results <- list()
  for (activate in c(TRUE, FALSE)) {
    results[[paste0("run_", activate)]] <- run(
      "condathis-host-tool",
      env_name = "stub-env",
      activate = activate,
      error = "continue",
      verbose = "silent"
    )
    results[[paste0("run_bin_", activate)]] <- run_bin(
      "condathis-host-tool",
      env_name = "stub-env",
      activate = activate,
      error = "continue",
      verbose = "silent"
    )
    results[[paste0("run_pipeline_", activate)]] <- run_pipeline(
      run_step("condathis-host-tool"),
      run_step(
        run_family_rscript(),
        "--vanilla",
        "-e",
        "invisible(readLines(file('stdin')))"
      ),
      env_name = "stub-env",
      activate = activate,
      error = "continue",
      verbose = "silent"
    )
  }
  for (name in names(results)) {
    res <- results[[name]]
    status <- if (startsWith(name, "run_pipeline")) {
      res$statuses[[1L]]
    } else {
      res$status
    }
    testthat::expect_identical(status, 127L, info = name)
  }
})

test_that("activate = FALSE never runs a PATH program for a missing environment", {
  # The probe fails (NA, rule R5), so the call goes on, and no backend code
  # runs with activate = FALSE. The environment directory is missing.
  # The failed probe also warns when the backend is resolved.
  local_run_family_stub(
    backend_env_exists = function(...) stop("listing failed", call. = FALSE)
  )
  path_dir <- withr::local_tempdir(pattern = "path-tool")
  run_family_write_tool(path_dir, "condathis-path-tool", "from-path")
  withr::local_path(path_dir, action = "prefix")
  reader <- run_step(
    run_family_rscript(),
    "--vanilla",
    "-e",
    "invisible(readLines(file('stdin')))"
  )

  res_run <- suppressWarnings(run(
    "condathis-path-tool",
    env_name = "stub-gone",
    activate = FALSE,
    error = "continue",
    verbose = "silent"
  ))
  res_run_bin <- suppressWarnings(run_bin(
    "condathis-path-tool",
    env_name = "stub-gone",
    activate = FALSE,
    error = "continue",
    verbose = "silent"
  ))
  res_pipeline <- suppressWarnings(run_pipeline(
    run_step("condathis-path-tool"),
    reader,
    env_name = "stub-gone",
    activate = FALSE,
    error = "continue",
    verbose = "silent"
  ))
  for (res in list(res_run, res_run_bin)) {
    testthat::expect_identical(res$status, 127L)
    testthat::expect_no_match(res$stdout, "from-path", fixed = TRUE)
    testthat::expect_match(res$stderr, "does not exist", fixed = TRUE)
  }
  testthat::expect_identical(res_pipeline$statuses[[1L]], 127L)

  testthat::expect_error(
    suppressWarnings(run(
      "condathis-path-tool",
      env_name = "stub-gone",
      activate = FALSE,
      verbose = "silent"
    )),
    class = "condathis_run_env_not_found"
  )
  testthat::expect_error(
    suppressWarnings(run_bin(
      "condathis-path-tool",
      env_name = "stub-gone",
      activate = FALSE,
      verbose = "silent"
    )),
    class = "condathis_run_bin_env_not_found"
  )
  testthat::expect_error(
    suppressWarnings(run_pipeline(
      run_step("condathis-path-tool"),
      reader,
      env_name = "stub-gone",
      activate = FALSE,
      verbose = "silent"
    )),
    class = "condathis_run_pipeline_env_not_found"
  )
})

test_that("a backend whose activation sets no PATH still finds the environment's programs", {
  # The default stub returns `env = character(0)`. condathis puts the
  # environment's directories in front of the PATH, so the program of the
  # environment runs with both activate values, for every function.
  stub <- local_run_family_stub()
  env_bin <- fs::path(
    stub$root,
    "envs",
    "stub-env",
    if (isTRUE(is_windows())) "Scripts" else "bin"
  )
  fs::dir_create(env_bin)
  run_family_write_tool(env_bin, "condathis-stub-tool", "from-stub-env")
  for (activate in c(TRUE, FALSE)) {
    info <- paste("activate:", activate)
    for (fn in list(run, run_bin)) {
      res <- fn(
        "condathis-stub-tool",
        env_name = "stub-env",
        activate = activate,
        verbose = "silent"
      )
      testthat::expect_identical(res$status, 0L, info = info)
      testthat::expect_identical(
        parse_output(res),
        "from-stub-env",
        info = info
      )
    }
    res <- run_pipeline(
      run_step("condathis-stub-tool"),
      run_step(
        run_family_rscript(),
        "--vanilla",
        "-e",
        "cat(readLines(file('stdin')))"
      ),
      env_name = "stub-env",
      activate = activate,
      verbose = "silent"
    )
    testthat::expect_identical(res$statuses, c(0L, 0L), info = info)
    testthat::expect_identical(parse_output(res), "from-stub-env", info = info)
  }
})

test_that("condathis keeps the order of an activation PATH that names the environment", {
  stub_path <- NULL
  stub <- local_run_family_stub(
    backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
      return(list(
        command = cmd,
        args = args,
        env = c(PATH = stub_path),
        dir = NULL
      ))
    }
  )
  env_bin <- as.character(fs::path(
    stub$root,
    "envs",
    "stub-env",
    if (isTRUE(is_windows())) "Scripts" else "bin"
  ))
  fs::dir_create(env_bin)
  run_family_write_tool(env_bin, "condathis-order-tool", "from-env")
  # A directory that an `activate.d` script puts in front of the
  # environment's own.
  decoy_dir <- withr::local_tempdir()
  run_family_write_tool(decoy_dir, "condathis-order-tool", "from-decoy")
  stub_path <- paste(
    c(decoy_dir, env_bin, isolated_session_path()),
    collapse = .Platform$path.sep
  )
  res <- run("condathis-order-tool", env_name = "stub-env", verbose = "silent")
  # The activation PATH is used as it is, on every OS: no reordering, and
  # the environment's directory is not put in front a second time.
  testthat::expect_identical(parse_output(res), "from-decoy")
  seen <- run_isolation_dump("run", activate = TRUE)
  entries <- rscript_dumped_path_entries(
    seen[[match_env_name(names(seen), "PATH")]]
  )
  testthat::expect_identical(
    sum(path_entry_key(entries) == path_entry_key(env_bin)),
    1L
  )
  testthat::expect_identical(
    path_entry_key(entries[[1L]]),
    path_entry_key(as.character(decoy_dir))
  )
})

test_that("run(activate = FALSE) calls no backend function to resolve the command", {
  stub <- local_run_family_stub(
    backend_resolve_run = function(...) {
      stop("backend_resolve_run() must not be called.", call. = FALSE)
    }
  )
  res <- run(
    run_family_rscript(),
    "--vanilla",
    "-e",
    "cat('no activation')",
    env_name = "stub-env",
    activate = FALSE,
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, "no activation")
  testthat::expect_length(stub_calls(stub, "backend_resolve_run"), 0L)

  # With activation, the backend's failure is the error of run(), with the
  # hint about `activate = FALSE`.
  cnd <- testthat::expect_error(
    run(run_family_rscript(), env_name = "stub-env", verbose = "silent"),
    class = "condathis_run_resolve_failed"
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "activate = FALSE",
    fixed = TRUE
  )
})

test_that("run() has the fixed activation with activate = FALSE", {
  stub <- local_run_family_stub()
  env_dir <- as.character(fs::path(stub$root, "envs", "stub-env"))
  fixed_names <- c(
    "CONDA_PREFIX",
    "CONDA_DEFAULT_ENV",
    "CONDA_SHLVL",
    "MAMBA_SHLVL",
    "CONDA_PROMPT_MODIFIER",
    "MAMBA_PROMPT_MODIFIER"
  )
  res <- run(
    run_family_rscript(),
    "--vanilla",
    "-e",
    # An empty value is written `[]`, so that no line is empty.
    paste0(
      "x <- Sys.getenv(c(",
      paste(deparse(fixed_names), collapse = ""),
      ")); x[!nzchar(x)] <- '[]'; cat(x, sep = '\\n')"
    ),
    env_name = "stub-env",
    activate = FALSE,
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  values <- strsplit(res$stdout, "\r?\n")[[1L]]
  testthat::expect_identical(
    as.character(fs::path_norm(values[[1L]])),
    as.character(fs::path_norm(env_dir))
  )
  testthat::expect_identical(
    values[-1L],
    c("stub-env", "1", "1", "[]", "[]")
  )
})

test_that("activate.d runs only with activation, and the host never leaks", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "run-isolation-env"
  create_polyglot_env(env_name)
  env_dir <- as.character(get_env_dir(env_name))
  activate_dir <- fs::path(env_dir, "etc", "conda", "activate.d")
  fs::dir_create(activate_dir)
  withr::defer(fs::dir_delete(activate_dir))
  writeLines(
    c("export CDT_ISO_ACT=yes", "unset CDT_ISO_UNSET"),
    fs::path(activate_dir, "cdt-iso.sh")
  )
  writeLines(
    c("@set CDT_ISO_ACT=yes", "@set CDT_ISO_UNSET="),
    fs::path(activate_dir, "cdt-iso.bat")
  )
  reset_micromamba_activation_cache()
  withr::defer(reset_micromamba_activation_cache())
  host <- local_fake_nested_host()
  withr::local_envvar(CDT_ISO_UNSET = "session")

  for (case in run_isolation_cases()) {
    info <- paste(case$fn, "activate:", case$activate)
    seen <- run_isolation_dump(case$fn, case$activate, env_name = env_name)
    expect_no_host_activation(seen, host, info)
    testthat::expect_identical(seen[["CONDA_SHLVL"]], "1", info = info)
    testthat::expect_null(seen[["CONDA_PREFIX_1"]], info = info)
    testthat::expect_false(
      any(grepl("^CONDA_ENV_SHLVL_", names(seen), ignore.case = TRUE)),
      info = info
    )
    testthat::expect_identical(
      as.character(fs::path_norm(seen[["CONDA_PREFIX"]])),
      as.character(fs::path_norm(env_dir)),
      info = info
    )
    first <- rscript_dumped_path_entries(
      seen[[match_env_name(names(seen), "PATH")]]
    )[[1L]]
    testthat::expect_true(
      path_entry_key(first) %in%
        path_entry_key(as.character(env_bin_search_dirs(env_dir))),
      info = info
    )
    if (isTRUE(case$activate)) {
      testthat::expect_identical(seen[["CDT_ISO_ACT"]], "yes", info = info)
      testthat::expect_null(seen[["CDT_ISO_UNSET"]], info = info)
    } else {
      testthat::expect_null(seen[["CDT_ISO_ACT"]], info = info)
      testthat::expect_identical(
        seen[["CDT_ISO_UNSET"]],
        "session",
        info = info
      )
    }
  }
})

test_that("a micromamba started through an activating wrapper records a clean activation", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "run-isolation-env"
  create_polyglot_env(env_name)
  if (isFALSE(is_windows())) {
    # A wrapper that activates an environment of its own before it starts
    # micromamba, as a pixi global binary does. micromamba refuses to run
    # under another name, so the wrapper is called `micromamba`.
    # A pixi global binary is such a wrapper itself: discovery gives the
    # binary that it starts (see the pixi trampoline test below).
    real_micromamba <- as.character(get_best_micromamba_path())
    wrapper_dir <- withr::local_tempdir()
    wrapper_prefix <- fs::path(wrapper_dir, "wrapper-env")
    fs::dir_create(fs::path(wrapper_prefix, c("conda-meta", "bin")))
    wrapper <- fs::path(wrapper_dir, "micromamba")
    writeLines(
      c(
        "#!/bin/sh",
        paste0(
          "CONDA_PREFIX=",
          shQuote(wrapper_prefix),
          " CONDA_SHLVL=1 ",
          "PATH=",
          shQuote(fs::path(wrapper_prefix, "bin")),
          ":\"$PATH\" ",
          "exec ",
          shQuote(real_micromamba),
          " \"$@\""
        )
      ),
      wrapper
    )
    fs::file_chmod(wrapper, "u+x")
    withr::local_options(condathis.micromamba_path = as.character(wrapper))
  }
  reset_micromamba_activation_cache()
  withr::defer(reset_micromamba_activation_cache())
  res <- run(
    run_family_rscript(),
    "--vanilla",
    "-e",
    paste(
      "cat(Sys.getenv('CONDA_SHLVL'), Sys.getenv('CONDA_PREFIX_1', 'unset'),",
      "grepl('wrapper-env', Sys.getenv('PATH'), fixed = TRUE))"
    ),
    env_name = env_name,
    verbose = "silent"
  )
  testthat::expect_identical(res$stdout, "1 unset FALSE")
})

# A fake pixi global trampoline for `real`: a program in `dir` named as
# micromamba, and `trampoline_configuration/micromamba.json` next to it,
# whose `exe` is `real` and whose `env` is an activation of a pixi
# environment. Off Windows the program is a script that sets that
# activation, as the trampoline does; on Windows a copy of `real` (a
# script cannot be the micromamba of condathis there).
make_fake_trampoline <- function(dir, real) {
  pixi_env <- file.path(dir, "envs", "micromamba")
  dir.create(file.path(pixi_env, "conda-meta"), recursive = TRUE)
  bin_dir <- file.path(dir, "bin")
  dir.create(file.path(bin_dir, "trampoline_configuration"), recursive = TRUE)
  if (isTRUE(is_windows())) {
    trampoline <- file.path(bin_dir, "micromamba.exe")
    file.copy(real, trampoline)
  } else {
    trampoline <- file.path(bin_dir, "micromamba")
    writeLines(
      c(
        "#!/bin/sh",
        paste0(
          "CONDA_SHLVL=1 CONDA_PREFIX=",
          shQuote(pixi_env),
          " exec ",
          shQuote(real),
          " \"$@\""
        )
      ),
      trampoline
    )
    Sys.chmod(trampoline, "0755")
  }
  jsonlite::write_json(
    list(
      exe = real,
      path_diff = file.path(pixi_env, "bin"),
      env = list(CONDA_SHLVL = "1", CONDA_PREFIX = pixi_env)
    ),
    file.path(bin_dir, "trampoline_configuration", "micromamba.json"),
    auto_unbox = TRUE
  )
  return(list(trampoline = trampoline, pixi_env = pixi_env))
}

test_that("a pixi trampoline as the micromamba path runs the binary it starts", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "run-isolation-env"
  create_polyglot_env(env_name)
  real <- as.character(get_best_micromamba_path())
  fake <- make_fake_trampoline(
    normalizePath(withr::local_tempdir(pattern = "pixi-home-"), winslash = "/"),
    real
  )
  withr::local_options(condathis.micromamba_path = fake$trampoline)
  testthat::expect_identical(
    path_entry_key(as.character(get_best_micromamba_path())),
    path_entry_key(real)
  )
  # The option keeps the value of the user.
  testthat::expect_identical(
    getOption("condathis.micromamba_path"),
    fake$trampoline
  )
  reset_micromamba_activation_cache()
  withr::defer(reset_micromamba_activation_cache())
  condabin <- file.path(
    install_dir_for_backend(micromamba_backend()),
    "condabin"
  )
  for (case in run_isolation_cases()[c(TRUE, FALSE)]) {
    info <- paste(case$fn, "activate:", case$activate)
    seen <- run_isolation_dump(case$fn, case$activate, env_name = env_name)
    path <- seen[[match_env_name(names(seen), "PATH")]]
    testthat::expect_true(path_names_any(path, condabin), info = info)
    testthat::expect_no_match(path, fake$pixi_env, fixed = TRUE, info = info)
    testthat::expect_identical(
      path_entry_key(normalizePath(seen[["MAMBA_EXE"]], winslash = "/")),
      path_entry_key(normalizePath(real, winslash = "/")),
      info = info
    )
    testthat::expect_identical(seen[["CONDA_SHLVL"]], "1", info = info)
    testthat::expect_null(seen[["CONDA_PREFIX_1"]], info = info)
  }
})

test_that("the commands never see the variables of R's own startup", {
  sep <- .Platform$path.sep
  local_r_startup_cache(c(
    MAKE = "r-make",
    EDITOR = "vi",
    LD_LIBRARY_PATH = paste("/r/lib", "/r/jvm", sep = sep)
  ))
  withr::local_envvar(c(
    MAKE = "r-make",
    EDITOR = "condathis-user-editor",
    LD_LIBRARY_PATH = paste("/r/lib", "/r/jvm", "/user/lib", sep = sep),
    R_LIBS_USER = "/user/R-lib",
    R_CONDATHIS_FAKE = "x",
    `_R_CONDATHIS_FAKE_` = "y"
  ))
  local_run_family_stub()
  dump <- if (isTRUE(is_windows())) c("cmd", "/c", "set") else "env"
  for (activate in c(TRUE, FALSE)) {
    for (fn in c("run", "run_bin")) {
      info <- paste(fn, "activate:", activate)
      call_fn <- if (identical(fn, "run")) run else run_bin
      res <- rlang::exec(
        call_fn,
        !!!as.list(dump),
        env_name = "stub-env",
        activate = activate,
        verbose = "silent"
      )
      testthat::expect_identical(res$status, 0L, info = info)
      lines <- strsplit(res$stdout, "\r?\n")[[1L]]
      seen <- sub("=.*$", "", lines[grepl("=", lines, fixed = TRUE)])
      testthat::expect_identical(
        grep("^_?R_", seen, value = TRUE, ignore.case = is_windows()),
        character(0L),
        info = info
      )
      value_of <- function(name) {
        hit <- grep(
          paste0("^", name, "="),
          lines,
          value = TRUE,
          ignore.case = is_windows()
        )
        if (identical(length(hit), 0L)) {
          return(NULL)
        }
        return(sub("^[^=]*=", "", hit[[1L]]))
      }
      testthat::expect_null(value_of("MAKE"), info = info)
      testthat::expect_identical(
        value_of("EDITOR"),
        "condathis-user-editor",
        info = info
      )
      testthat::expect_identical(
        value_of("LD_LIBRARY_PATH"),
        "/user/lib",
        info = info
      )
    }
  }
})

test_that("the commands never see the Python state of the R session", {
  # Decision D18: a python of the environment never finds the modules of
  # PYTHONPATH or of the user's site directory, a PYTHONHOME never breaks
  # it, and uv never installs into a virtual environment of the session.
  # The variables are set with Sys.setenv(), as reticulate sets
  # VIRTUAL_ENV, not only in the shell that started R.
  local_run_family_stub()
  venv <- withr::local_tempdir(pattern = "host-venv")
  file.create(file.path(venv, "pyvenv.cfg"))
  venv_bin <- file.path(venv, if (isTRUE(is_windows())) "Scripts" else "bin")
  dir.create(venv_bin)
  withr::local_path(venv_bin, action = "prefix")
  removed <- c(
    VIRTUAL_ENV = venv,
    VIRTUAL_ENV_PROMPT = "(host-venv) ",
    PYTHONHOME = file.path(venv, "home"),
    PYTHONPATH = file.path(venv, "pythonpath"),
    PYTHONUSERBASE = file.path(venv, "userbase"),
    PYTHONSTARTUP = file.path(venv, "startup.py"),
    UV_PYTHON = file.path(venv_bin, "python"),
    UV_SYSTEM_PYTHON = "1",
    UV_PROJECT_ENVIRONMENT = venv
  )
  withr::local_envvar(c(removed, PYTHONNOUSERSITE = ""))
  for (case in run_isolation_cases()) {
    info <- paste(case$fn, "activate:", case$activate)
    seen <- run_isolation_dump(case$fn, case$activate)
    for (name in names(removed)) {
      testthat::expect_null(seen[[name]], info = paste(info, name))
    }
    testthat::expect_identical(seen[["PYTHONNOUSERSITE"]], "1", info = info)
    testthat::expect_false(
      path_names_any(seen[[match_env_name(names(seen), "PATH")]], venv_bin),
      info = info
    )
  }
})
