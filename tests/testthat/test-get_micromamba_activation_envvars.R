test_that("get_micromamba_activation_envvars() resolves real activation vars", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  reset_micromamba_activation_cache("condathis-env")

  envvars <- get_micromamba_activation_envvars("condathis-env")

  testthat::expect_type(envvars, "character")
  testthat::expect_false(is.null(names(envvars)))
  testthat::expect_true("CONDA_PREFIX" %in% names(envvars))
  testthat::expect_true("PATH" %in% names(envvars))
  testthat::expect_match(
    envvars[["CONDA_PREFIX"]],
    "condathis-env",
    fixed = TRUE
  )
  testthat::expect_match(envvars[["PATH"]], "condathis-env", fixed = TRUE)
})

test_that("get_micromamba_activation_envvars() works inside a caller's own clean-envvar scope", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  # Regression test: get_clean_conda_envvars() sets R_HOME = "" via
  # withr::local_envvar(), which corrupts R.home() for the remainder of
  # that scope. run_bin()/run_pipeline() apply that scope themselves
  # *before* calling get_micromamba_activation_envvars(), so resolving
  # Rscript's path via a live R.home() call inside this function (rather
  # than the package-load-time cache in condathis-package.R) fails here
  # with "/bin/Rscript: No such file or directory" even though it works
  # fine when get_micromamba_activation_envvars() is called directly.
  create_env(verbose = "silent")
  reset_micromamba_activation_cache("condathis-env")

  tmp_dir_path <- withr::local_tempdir()
  withr::local_envvar(.new = get_clean_conda_envvars(tmp_dir = tmp_dir_path))

  envvars <- get_micromamba_activation_envvars(
    "condathis-env",
    use_cache = FALSE
  )
  testthat::expect_true("CONDA_PREFIX" %in% names(envvars))
})

test_that("get_micromamba_activation_envvars() drops known noise variables", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  reset_micromamba_activation_cache("condathis-env")

  envvars <- get_micromamba_activation_envvars("condathis-env")

  testthat::expect_false("TMPDIR" %in% names(envvars))
  testthat::expect_false("PWD" %in% names(envvars))
  testthat::expect_false("SHLVL" %in% names(envvars))
  testthat::expect_false(any(grepl("^PROCESSX_PS", names(envvars))))
})

test_that("get_micromamba_activation_envvars() errors on a missing environment", {
  cnd <- testthat::expect_error(
    object = get_micromamba_activation_envvars("no-such-env-xyz"),
    class = "condathis_activation_env_not_found"
  )
  # Every missing environment shares `condathis_env_not_found` (rule R1).
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_activation_env_not_found",
      "condathis_env_not_found",
      "condathis_error"
    )
  )
  msg <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(msg, "no-such-env-xyz", fixed = TRUE)
  # The path is still shown.
  testthat::expect_match(msg, "Path:", fixed = TRUE)

  # An environment given by path is named by its directory.
  missing_dir <- fs::path(withr::local_tempdir(), "no-such-prefix")
  cnd <- testthat::expect_error(
    get_micromamba_activation_envvars(NULL, env_dir = missing_dir),
    class = "condathis_env_not_found"
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "no-such-prefix",
    fixed = TRUE
  )
})

test_that("get_micromamba_activation_envvars() result works as a process env overlay", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  reset_micromamba_activation_cache("condathis-env")

  envvars <- get_micromamba_activation_envvars("condathis-env")
  px <- processx::process$new(
    "env",
    stdout = "|",
    env = c("current", envvars)
  )
  # Drain stdout before wait()ing: `env`'s full dump of the process
  # environment can exceed the OS pipe buffer (64KB on Linux, much smaller
  # on macOS/Windows). wait()-then-read blocks forever in that case - `env`
  # blocks on write() because nobody is reading yet, and wait() blocks
  # because the child never exits. read_all_output() polls the pipe as data
  # arrives instead of waiting for exit first.
  out <- px$read_all_output()
  px$wait()
  testthat::expect_match(out, "CONDA_PREFIX=", fixed = TRUE)
})

test_that("get_micromamba_activation_envvars() caches per env_name", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  reset_micromamba_activation_cache("condathis-env")

  envvars_first <- get_micromamba_activation_envvars("condathis-env")
  testthat::expect_true(
    exists("condathis-env", envir = condathis_activation_cache)
  )

  envvars_cached <- get_micromamba_activation_envvars("condathis-env")
  testthat::expect_identical(envvars_first, envvars_cached)

  envvars_forced <- get_micromamba_activation_envvars(
    "condathis-env",
    use_cache = FALSE
  )
  testthat::expect_identical(envvars_first, envvars_forced)
})

test_that("reset_micromamba_activation_cache() clears cache entries", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  get_micromamba_activation_envvars("condathis-env")
  testthat::expect_true(
    exists("condathis-env", envir = condathis_activation_cache)
  )

  reset_micromamba_activation_cache("condathis-env")
  testthat::expect_false(
    exists("condathis-env", envir = condathis_activation_cache)
  )
})

test_that("activation_cache_stamp() changes when conda-meta contents change", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  env_dir <- get_env_dir(env_name = "condathis-env")
  conda_meta_dir <- fs::path(env_dir, "conda-meta")
  fs::dir_create(conda_meta_dir)

  stamp_before <- activation_cache_stamp(env_dir)

  fake_pkg_file <- fs::path(conda_meta_dir, "fake-package-1.0-0.json")
  writeLines("{}", fake_pkg_file)
  Sys.setFileTime(fake_pkg_file, Sys.time() + 5)

  stamp_after <- activation_cache_stamp(env_dir)
  testthat::expect_false(identical(stamp_before, stamp_after))

  fs::file_delete(fake_pkg_file)
})

testthat::test_that("activation_cache_stamp() changes when the activation's own files change", {
  env_dir <- fs::path(withr::local_tempdir(), "stamp-env")
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  writeLines("{}", fs::path(env_dir, "conda-meta", "pkg-1.0-0.json"))
  stamps <- list(activation_cache_stamp(env_dir))
  # The time is a number: formatting it would set TZDIR on macOS.
  testthat::expect_false(grepl(":", stamps[[1L]][[1L]], fixed = TRUE))

  activate_dir <- fs::path(env_dir, "etc", "conda", "activate.d")
  fs::dir_create(activate_dir)
  script <- fs::path(activate_dir, "stamp.sh")
  writeLines("export STAMP_A=1", script)
  stamps[[2L]] <- activation_cache_stamp(env_dir)
  # The same size and modification time, other contents.
  mtime <- fs::file_info(script)$modification_time
  writeLines("export STAMP_A=2", script)
  Sys.setFileTime(script, mtime)
  stamps[[3L]] <- activation_cache_stamp(env_dir)
  vars_dir <- fs::path(env_dir, "etc", "conda", "env_vars.d")
  fs::dir_create(vars_dir)
  writeLines('{"STAMP_B": "1"}', fs::path(vars_dir, "stamp.json"))
  stamps[[4L]] <- activation_cache_stamp(env_dir)
  testthat::expect_identical(anyDuplicated(stamps), 0L)
  testthat::expect_identical(activation_cache_stamp(env_dir), stamps[[4L]])
})

testthat::test_that("the cached activation is resolved again when its files or the session change", {
  # The activation scripts can read the session's variables, and their own
  # files can change without a package change, as rattlerthis's cache of
  # its activation also notices.
  env_dir <- fs::path(withr::local_tempdir(), "cache-env")
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  resolutions <- 0L
  testthat::local_mocked_bindings(
    resolve_micromamba_activation_envvars = function(...) {
      resolutions <<- resolutions + 1L
      return(list(envvars = c(CACHE_TEST = "1"), path_prepend = character(0L)))
    }
  )
  withr::defer(reset_micromamba_activation_cache())
  get_env <- function() {
    return(get_micromamba_activation_envvars(
      env_name = NULL,
      env_dir = env_dir
    ))
  }
  testthat::expect_identical(get_env()[["CACHE_TEST"]], "1")
  get_env()
  testthat::expect_identical(resolutions, 1L)
  withr::with_envvar(c(CONDATHIS_CACHE_TEST_VAR = "x"), get_env())
  testthat::expect_identical(resolutions, 2L)
  get_env()
  testthat::expect_identical(resolutions, 3L)
  get_env()
  testthat::expect_identical(resolutions, 3L)
  activate_dir <- fs::path(env_dir, "etc", "conda", "activate.d")
  fs::dir_create(activate_dir)
  writeLines("export CACHE_TEST=2", fs::path(activate_dir, "cache.sh"))
  get_env()
  testthat::expect_identical(resolutions, 4L)
  get_env()
  testthat::expect_identical(resolutions, 4L)
})

testthat::test_that("the priming micromamba run on Windows uses an empty throwaway environment", {
  # Priming `condabin/` in the environment being activated ran its
  # activate.d scripts once more on the first activation on Windows.
  with_sandbox_dir({
    calls <- list()
    testthat::local_mocked_bindings(
      is_windows = function() TRUE,
      native_cmd = function(conda_cmd, conda_args, ...) {
        prefix <- conda_args[[match("-p", conda_args) + 1L]]
        calls[[length(calls) + 1L]] <<- list(
          conda_cmd = conda_cmd,
          conda_args = conda_args,
          cmd = c(...)[[1L]],
          entries = list.files(prefix, recursive = TRUE, all.files = TRUE)
        )
        return(invisible(NULL))
      }
    )
    ensure_windows_micromamba_bat()
    testthat::expect_length(calls, 1L)
    call <- calls[[1L]]
    testthat::expect_identical(call$conda_cmd, "run")
    testthat::expect_identical(call$conda_args[[1L]], "-p")
    testthat::expect_false("-n" %in% call$conda_args)
    testthat::expect_identical(call$cmd, "dir")
    # An empty environment, outside every root, and gone afterwards.
    testthat::expect_identical(call$entries, "conda-meta/history")
    testthat::expect_false(fs::dir_exists(call$conda_args[[2L]]))
    root <- install_dir_for_backend(micromamba_backend())
    testthat::expect_false(startsWith(
      as.character(call$conda_args[[2L]]),
      as.character(root)
    ))
  })
})

testthat::test_that("read_activation_dump reads the dump file and rejects broken ones", {
  # The dump subprocess writes its environment to an RDS file with base R
  # only, so it works without any package in the child's library paths and
  # banners printed by activate.d hooks cannot corrupt the result.
  tmp_dir <- withr::local_tempdir()
  good <- fs::path(tmp_dir, "good.rds")
  saveRDS(list(CONDA_PREFIX = "/envs/x", MY_VAR = "1"), good)
  parsed <- read_activation_dump(good, env_name = "x")
  testthat::expect_equal(parsed$CONDA_PREFIX, "/envs/x")
  testthat::expect_equal(parsed$MY_VAR, "1")

  # Missing file, unreadable file, or wrong shape: classed error.
  missing <- rlang::catch_cnd(
    read_activation_dump(fs::path(tmp_dir, "missing.rds"), env_name = "x")
  )
  testthat::expect_s3_class(missing, "condathis_activation_dump_error")
  testthat::expect_s3_class(missing, "condathis_error")

  garbage <- fs::path(tmp_dir, "garbage.rds")
  writeLines("not an rds file", garbage)
  cnd_garbage <- rlang::catch_cnd(read_activation_dump(garbage, env_name = "x"))
  testthat::expect_s3_class(cnd_garbage, "condathis_activation_dump_error")

  wrong_shape <- fs::path(tmp_dir, "wrong.rds")
  saveRDS(list(1, 2), wrong_shape)
  cnd_shape <- rlang::catch_cnd(read_activation_dump(
    wrong_shape,
    env_name = "x"
  ))
  testthat::expect_s3_class(cnd_shape, "condathis_activation_dump_error")
})

testthat::test_that("the activation dump script loads no package", {
  # Regression test: the dump ran `cat(jsonlite::toJSON(...))` under
  # `Rscript --vanilla`, which skips `.Rprofile`. When jsonlite was only
  # reachable through library paths set there (for example by renv), the
  # dump failed with "there is no package called 'jsonlite'".
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  scripts <- character(0L)
  testthat::local_mocked_bindings(
    native_cmd = function(conda_cmd, conda_args = NULL, ...) {
      dots <- Filter(rlang::is_string, list(...))
      script <- Filter(function(x) grepl("dump_env\\.R$", x), dots)
      if (isTRUE(length(script) == 1L)) {
        scripts <<- c(scripts, readLines(script[[1L]]))
        saveRDS(
          as.list(Sys.getenv()),
          sub("dump_env\\.R$", "activated_env.rds", script[[1L]])
        )
      }
      invisible(list(status = 0L, stdout = "", stderr = ""))
    }
  )
  resolve_micromamba_activation_envvars(
    env_name = "run-bin-cli-tools-env",
    env_dir = get_env_dir("run-bin-cli-tools-env")
  )
  testthat::expect_length(scripts, 1L)
  testthat::expect_false(grepl("::", scripts, fixed = TRUE))
  testthat::expect_false(grepl("library\\(|require\\(", scripts))
})

testthat::test_that("activation resolution never routes through the public get_env_dir()", {
  # Regression test: get_env_dir()'s backend resolution runs a
  # `micromamba env list` subprocess on every call (even activation cache
  # hits) and can abort on multi-backend ambiguity; the micromamba-specific
  # activation helper must compute the env dir from the micromamba layout
  # directly.
  testthat::local_mocked_bindings(
    get_env_dir = function(...) {
      cli::cli_abort(
        "get_env_dir() must not be called by activation resolution."
      )
    }
  )
  testthat::expect_error(
    get_micromamba_activation_envvars("definitely-nonexistent-env-xyz"),
    class = "condathis_activation_env_not_found"
  )
})

testthat::test_that("the activation overlay carries no variable set by R's own startup", {
  # Regression test: the activated dump was diffed against the
  # `build_child_env()` block, not against an unactivated `Rscript` dump.
  # Variables R sets at startup (`R_HOME`, `R_PAPERSIZE_USER`, ...) then
  # looked like activation variables, and `R_HOME` overrode the clean
  # overlay's `R_HOME = ""` in every activated child.
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  create_env(
    test_os_pkg("coreutils"),
    env_name = "run-bin-cli-tools-env",
    verbose = "silent"
  )
  overlay <- get_micromamba_activation_envvars(
    "run-bin-cli-tools-env",
    use_cache = FALSE
  )
  testthat::expect_false(any(grepl("^R_", names(overlay))))
  testthat::expect_identical(
    fs::path_norm(overlay[["CONDA_PREFIX"]]),
    fs::path_norm(get_env_dir("run-bin-cli-tools-env"))
  )
})

testthat::test_that("the activation baseline starts once for two environments", {
  # Regression test: every activation cache miss started its own baseline
  # `Rscript` process, although the baseline depends only on the session's
  # environment, not on the target environment. Two new environments cost
  # three processes each instead of two.
  envs_parent <- withr::local_tempdir()
  env_dirs <- as.character(fs::path(
    envs_parent,
    c("baseline-env-a", "baseline-env-b", "baseline-env-c")
  ))
  fs::dir_create(fs::path(env_dirs, "conda-meta"))
  reset_micromamba_activation_cache()
  withr::defer(reset_micromamba_activation_cache())

  real_dump_activation_baseline <- dump_activation_baseline
  n_baseline <- 0L
  testthat::local_mocked_bindings(
    dump_activation_baseline = function(...) {
      n_baseline <<- n_baseline + 1L
      return(real_dump_activation_baseline(...))
    },
    # Writes the activated dump in this process, so no micromamba is
    # needed. `conda_args` is `c("-p", <env_dir>)`.
    native_cmd = function(conda_cmd, conda_args = NULL, ...) {
      dots <- Filter(rlang::is_string, list(...))
      script <- Filter(function(x) grepl("dump_env\\.R$", x), dots)
      if (isTRUE(length(script) == 1L)) {
        withr::with_envvar(
          new = c(CONDA_PREFIX = conda_args[[2L]]),
          code = source(script[[1L]], local = new.env())
        )
      }
      return(invisible(list(status = 0L, stdout = "", stderr = "")))
    }
  )

  overlay_a <- get_micromamba_activation_envvars(
    env_name = NULL,
    env_dir = env_dirs[[1L]]
  )
  overlay_b <- get_micromamba_activation_envvars(
    env_name = NULL,
    env_dir = env_dirs[[2L]]
  )
  testthat::expect_identical(n_baseline, 1L)
  testthat::expect_identical(overlay_a[["CONDA_PREFIX"]], env_dirs[[1L]])
  testthat::expect_identical(overlay_b[["CONDA_PREFIX"]], env_dirs[[2L]])

  # A change to the session's environment invalidates the baseline.
  withr::local_envvar(CONDATHIS_TEST_BASELINE_KEY = "changed")
  get_micromamba_activation_envvars(env_name = NULL, env_dir = env_dirs[[3L]])
  testthat::expect_identical(n_baseline, 2L)

  # `use_cache = FALSE` dumps the baseline again.
  get_micromamba_activation_envvars(
    env_name = NULL,
    env_dir = env_dirs[[1L]],
    use_cache = FALSE
  )
  testthat::expect_identical(n_baseline, 3L)

  # Clearing the whole cache clears the baseline too.
  reset_micromamba_activation_cache()
  testthat::expect_null(condathis_activation_baseline_cache$entry)
})

testthat::test_that("a failed activation command raises a condathis error", {
  # Regression test: the `micromamba run` of the activation dump was not
  # wrapped, so its failure escaped as a bare process error without the
  # condathis classes.
  env_dir <- withr::local_tempdir()
  testthat::local_mocked_bindings(
    native_cmd = function(conda_cmd, ...) {
      rlang::abort(
        "failed",
        class = "system_command_status_error",
        status = 2L,
        stderr = "an activate.d script failed"
      )
    }
  )
  cnd <- testthat::expect_error(
    resolve_micromamba_activation_envvars(
      env_name = NULL,
      env_dir = env_dir,
      use_cache = FALSE
    ),
    class = "condathis_micromamba_status_error"
  )
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_identical(cnd$status, 2L)
  testthat::expect_match(
    conditionMessage(cnd),
    "an activate.d script failed",
    fixed = TRUE
  )
})

testthat::test_that("the activation leaves out the variables of micromamba's own process", {
  # Regression test (TD5, footprint): `micromamba run` gets
  # `MAMBA_ROOT_PREFIX` and `XDG_CACHE_HOME` from condathis, so the
  # activation dump inherited them, and the commands of run(), run_bin()
  # and run_pipeline() got them as activation variables. On Windows,
  # micromamba's activation also exports its root. Commands keep
  # `MAMBA_ROOT_PREFIX = ""` and the session's user cache.
  root <- "/condathis/root"
  overlay <- micromamba_cmd_overlay("run", character(0L), root)
  activated <- list(
    MAMBA_ROOT_PREFIX = root,
    XDG_CACHE_HOME = overlay[["XDG_CACHE_HOME"]],
    CONDA_PREFIX = "/condathis/root/envs/x",
    OTHER = "kept"
  )
  testthat::expect_identical(
    drop_micromamba_process_vars(
      names(activated),
      activated_vars = activated,
      root_dir = root
    ),
    c("CONDA_PREFIX", "OTHER")
  )
  # A value that an activate.d script set is the activation's; the root
  # prefix never is.
  activated$XDG_CACHE_HOME <- "/set/by/activate.d"
  activated$MAMBA_ROOT_PREFIX <- "/set/by/activate.d"
  testthat::expect_identical(
    drop_micromamba_process_vars(
      names(activated),
      activated_vars = activated,
      root_dir = root
    ),
    c("XDG_CACHE_HOME", "CONDA_PREFIX", "OTHER")
  )

  # The rest needs a micromamba binary, which may be downloaded.
  testthat::skip_on_cran()
  create_env(verbose = "silent")
  reset_micromamba_activation_cache("condathis-env")
  envvars <- get_micromamba_activation_envvars("condathis-env")
  testthat::expect_false(any(
    toupper(names(envvars)) %in% c("MAMBA_ROOT_PREFIX", "XDG_CACHE_HOME")
  ))
  testthat::expect_false(anyNA(envvars))
})

testthat::test_that("the activation leaves out micromamba's own TMP on Windows, not a TMP that a script sets", {
  # Regression test: on Windows, every micromamba command that
  # `native_cmd()` starts gets `TMP` = a directory in its `TMPDIR` (see
  # `micromamba_cmd_overlay()`), which `micromamba run -e` cannot change,
  # so the activated dump has it and the baseline has the session's `TMP`.
  # Recorded, it gave every later command of the environment a deleted
  # directory as `TMP`. When it was the `TMPDIR` itself, a script that set
  # `TMP` to the `TMPDIR` was lost.
  root <- "/condathis/root"
  call_tmp <- "/session/tmp/condathis-tmp1"
  for (on_windows in c(TRUE, FALSE)) {
    testthat::with_mocked_bindings(
      is_windows = function() on_windows,
      code = {
        activated <- list(TMP = paste0(call_tmp, "/mamba-tmp"), OTHER = "kept")
        testthat::expect_identical(
          drop_micromamba_process_vars(
            names(activated),
            activated_vars = activated,
            root_dir = root,
            tmp_dir = call_tmp
          ),
          if (isTRUE(on_windows)) "OTHER" else c("TMP", "OTHER"),
          info = paste("on_windows:", on_windows)
        )
        for (script_tmp in c("/set/by/activate.d", call_tmp)) {
          activated$TMP <- script_tmp
          testthat::expect_identical(
            drop_micromamba_process_vars(
              names(activated),
              activated_vars = activated,
              root_dir = root,
              tmp_dir = call_tmp
            ),
            c("TMP", "OTHER"),
            info = paste("on_windows:", on_windows, script_tmp)
          )
        }
      }
    )
  }

  # The whole resolution, with and without the command's environment: the
  # activated dump is written in this process, with the variables of
  # micromamba's process, then the `TMP` of an `activate.d` script
  # (`"%TMPDIR%"`: the `TMPDIR` of the capture).
  env_dir <- fs::path(withr::local_tempdir(), "tmp-env")
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  withr::local_envvar(TMP = withr::local_tempdir())
  reset_micromamba_activation_cache()
  withr::defer(reset_micromamba_activation_cache())
  script_tmp <- NULL
  seen <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    ensure_windows_micromamba_bat = function(...) invisible(NULL),
    native_cmd = function(conda_cmd, conda_args = NULL, ..., tmp_dir = NULL) {
      tmp_dir <- tmp_dir %||% withr::local_tempdir()
      seen$tmp_dir <- tmp_dir
      dots <- Filter(rlang::is_string, list(...))
      script <- Filter(function(x) grepl("dump_env\\.R$", x), dots)
      dump_vars <- c(TMPDIR = tmp_dir)
      if (isTRUE(is_windows())) {
        dump_vars[["TMP"]] <- micromamba_cmd_overlay(
          conda_cmd,
          conda_args,
          "/root",
          tmp_dir = tmp_dir
        )[["TMP"]]
      }
      if (isFALSE(is.null(script_tmp))) {
        dump_vars[["TMP"]] <- if (identical(script_tmp, "%TMPDIR%")) {
          tmp_dir
        } else {
          script_tmp
        }
      }
      withr::with_envvar(
        new = dump_vars,
        code = source(script[[1L]], local = new.env())
      )
      return(invisible(list(status = 0L, stdout = "", stderr = "")))
    }
  )
  cmd_tmp <- withr::local_tempdir()
  for (on_windows in c(TRUE, FALSE)) {
    testthat::with_mocked_bindings(
      is_windows = function() on_windows,
      code = {
        for (base_env in list(NULL, build_child_env(tmp_dir = cmd_tmp))) {
          for (script_tmp in list(NULL, "/set/by/activate.d", "%TMPDIR%")) {
            info <- paste(on_windows, is.null(base_env), script_tmp)
            resolved <- resolve_micromamba_activation_envvars(
              env_name = NULL,
              env_dir = env_dir,
              base_env = base_env
            )
            testthat::expect_identical(
              resolved$tmp_dir,
              seen$tmp_dir,
              info = info
            )
            if (isFALSE(is.null(base_env))) {
              testthat::expect_identical(seen$tmp_dir, cmd_tmp, info = info)
            }
            tmp_name <- names(resolved$envvars)[
              toupper(names(resolved$envvars)) == "TMP"
            ]
            if (is.null(script_tmp)) {
              testthat::expect_length(tmp_name, 0L)
            } else {
              testthat::expect_identical(tmp_name, "TMP", info = info)
              testthat::expect_identical(
                unname(resolved$envvars[["TMP"]]),
                if (identical(script_tmp, "%TMPDIR%")) {
                  seen$tmp_dir
                } else {
                  script_tmp
                },
                info = info
              )
            }
          }
        }
      }
    )
  }
})

testthat::test_that("a value built from micromamba's TMP names the command's TMP", {
  # Regression test: on Windows, a value that an `activate.d` script built
  # from `%TMP%` (`set FOO=%TMP%\foo`) named micromamba's own `TMP`, a
  # directory in the call's `TMPDIR` that `native_cmd()` removed when it was
  # empty. Before micromamba had a `TMP` of its own, the value named the
  # session's `TMP`.
  mamba_tmp <- "C:\\call\\tmp\\mamba-tmp"
  activated <- list(
    FOO = "C:\\call\\tmp\\mamba-tmp\\foo",
    BAR = "C:/call/tmp/mamba-tmp/bar",
    TEMP = mamba_tmp,
    TMP = mamba_tmp,
    OTHER = "C:\\call\\tmp\\other"
  )
  rewritten <- rewrite_micromamba_tmp_dir(
    activated,
    mamba_tmp_dir = mamba_tmp,
    base_env = c(TMP = "C:\\Users\\me\\Temp", TMPDIR = "C:\\call\\tmp")
  )
  testthat::expect_identical(
    rewritten,
    list(
      FOO = "C:\\Users\\me\\Temp\\foo",
      BAR = "C:\\Users\\me\\Temp/bar",
      TEMP = "C:\\Users\\me\\Temp",
      # Still micromamba's: `drop_micromamba_process_vars()` drops it.
      TMP = mamba_tmp,
      OTHER = "C:\\call\\tmp\\other"
    )
  )
  # A `TMP` that a script extended, and a command with no `TMP`: a batch
  # file expands an unset variable to nothing.
  activated$TMP <- paste0(mamba_tmp, "\\x")
  rewritten <- rewrite_micromamba_tmp_dir(
    activated,
    mamba_tmp_dir = mamba_tmp,
    base_env = c(TMPDIR = "C:\\call\\tmp")
  )
  testthat::expect_identical(rewritten$TMP, "\\x")
  testthat::expect_identical(rewritten$FOO, "\\foo")
  withr::local_envvar(TMP = "C:\\session\\tmp")
  testthat::expect_identical(
    rewrite_micromamba_tmp_dir(activated, mamba_tmp, base_env = NULL)$TMP,
    "C:\\session\\tmp\\x"
  )
  # A script wrote something there: the directory and the values stay.
  written_tmp <- fs::path(withr::local_tempdir(), "mamba-tmp")
  fs::dir_create(fs::path(written_tmp, "bar"))
  written <- list(BAR = as.character(fs::path(written_tmp, "bar")))
  testthat::expect_identical(
    rewrite_micromamba_tmp_dir(written, as.character(written_tmp), NULL),
    written
  )
  testthat::expect_true(fs::dir_exists(fs::path(written_tmp, "bar")))
  testthat::expect_identical(
    rewrite_micromamba_tmp_dir(activated, NULL, base_env = NULL),
    activated
  )
  testthat::with_mocked_bindings(
    is_windows = function() FALSE,
    code = testthat::expect_null(micromamba_tmp_dir("C:\\call\\tmp"))
  )
})

testthat::test_that("an activation built from micromamba's TMP is cached on Windows, unless a script wrote there", {
  # Regression test: on Windows, a value built from micromamba's own `TMP`
  # named the call's `TMPDIR`, so the activation was recorded again for
  # every command, and the command got a path in a deleted directory. When
  # a script writes there, the directory stays with the command's
  # `TMPDIR`, and the activation is not cached, as with `$TMPDIR` on Linux
  # and macOS. The activated dump is written in this process, with the
  # `TMPDIR` and `TMP` of micromamba's process, and a `FOO` built from
  # that `TMP`.
  env_dir <- fs::path(withr::local_tempdir(), "tmp-foo-env")
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  session_tmp <- as.character(withr::local_tempdir())
  withr::local_envvar(TMP = session_tmp)
  cache_key <- activation_cache_key(env_name = NULL, env_dir = env_dir)
  reset_micromamba_activation_cache()
  withr::defer(reset_micromamba_activation_cache())
  script <- list(writes = FALSE, extends_tmp = FALSE)
  mamba_tmp_of <- function(tmp_dir) {
    return(micromamba_cmd_overlay(
      "run",
      character(0L),
      "/root",
      tmp_dir = tmp_dir
    )[["TMP"]])
  }
  testthat::local_mocked_bindings(
    is_windows = function() TRUE,
    ensure_windows_micromamba_bat = function(...) invisible(NULL),
    native_cmd = function(conda_cmd, conda_args = NULL, ..., tmp_dir = NULL) {
      # As `native_cmd()`, which creates micromamba's `TMP`.
      mamba_tmp_dir <- mamba_tmp_of(tmp_dir)
      fs::dir_create(mamba_tmp_dir)
      dots <- Filter(rlang::is_string, list(...))
      dump_script <- Filter(function(x) grepl("dump_env\\.R$", x), dots)
      dump_vars <- c(
        TMPDIR = tmp_dir,
        TMP = mamba_tmp_dir,
        FOO = file.path(mamba_tmp_dir, "foo")
      )
      if (isTRUE(script$extends_tmp)) {
        dump_vars[["TMP"]] <- file.path(mamba_tmp_dir, "x")
      }
      if (isTRUE(script$writes)) {
        fs::dir_create(file.path(mamba_tmp_dir, "foo"))
      }
      withr::with_envvar(
        new = dump_vars,
        code = source(dump_script[[1L]], local = new.env())
      )
      return(invisible(list(status = 0L, stdout = "", stderr = "")))
    }
  )
  cmd_tmp <- as.character(withr::local_tempdir())
  base_env <- build_child_env(tmp_dir = cmd_tmp)
  cmd_mamba_tmp <- mamba_tmp_of(cmd_tmp)
  resolve <- function() {
    reset_micromamba_activation_cache(cache_key)
    unlink(cmd_mamba_tmp, recursive = TRUE)
    return(get_micromamba_activation_envvars(
      env_name = NULL,
      env_dir = env_dir,
      base_env = base_env
    ))
  }
  envvars <- resolve()
  testthat::expect_identical(
    unname(envvars[["FOO"]]),
    file.path(session_tmp, "foo")
  )
  testthat::expect_false("TMP" %in% names(envvars))
  testthat::expect_false(dir.exists(cmd_mamba_tmp))
  testthat::expect_true(exists(cache_key, envir = condathis_activation_cache))

  script$extends_tmp <- TRUE
  envvars <- resolve()
  testthat::expect_identical(
    unname(envvars[["TMP"]]),
    file.path(session_tmp, "x")
  )
  testthat::expect_true(exists(cache_key, envir = condathis_activation_cache))

  # What a script wrote there stays for the command, which shares the
  # `TMPDIR`, and the values name it.
  script$writes <- TRUE
  envvars <- resolve()
  testthat::expect_identical(
    unname(envvars[["FOO"]]),
    file.path(cmd_mamba_tmp, "foo")
  )
  testthat::expect_true(dir.exists(envvars[["FOO"]]))
  testthat::expect_identical(
    unname(envvars[["TMP"]]),
    file.path(cmd_mamba_tmp, "x")
  )
  testthat::expect_false(exists(cache_key, envir = condathis_activation_cache))
})

testthat::test_that("an activation overlay removes the variables an activate.d script unsets", {
  # Regression test (R-4 c): the activation diff recorded only the
  # variables an activation added or changed, so a variable that an
  # `activate.d` script unsets kept the session's value. It is now `NA` in
  # the overlay, which removes it.
  base_env <- c(KEEP = "1", GONE = "2", PATH = "/bin")
  child_env <- apply_child_overlay(
    base_env,
    overlay = c(GONE = NA_character_, NEW = "3")
  )
  testthat::expect_identical(
    child_env[sort(names(child_env))],
    c(KEEP = "1", NEW = "3", PATH = "/bin")
  )
  withr::local_envvar(CONDATHIS_TEST_GONE = "session")
  built <- build_child_env(
    tmp_dir = withr::local_tempdir(),
    overlay = c(CONDATHIS_TEST_GONE = NA_character_)
  )
  testthat::expect_false("CONDATHIS_TEST_GONE" %in% names(built))
})

testthat::test_that("activation_cache_rule() keeps an activation for the call or the working directory that it names", {
  home <- "/home/u"
  env_dir <- "/home/u/.local/share/R/condathis/envs/e"
  root <- "/home/u/.local/share/R/condathis"
  tmp <- "/tmp/Rtmp1/condathis-tmp2"
  plain <- c(env_dir, paste0(env_dir, "/bin"), paste0(root, "/condabin"))
  # The environment's own paths are below a home directory as the working
  # directory: still one entry for every working directory.
  testthat::expect_identical(
    activation_cache_rule(
      plain,
      tmp_dir = tmp,
      wd = home,
      fixed_dirs = c(env_dir, root)
    ),
    list(cache = TRUE, wd = NULL)
  )
  # A value below the call's TMPDIR: not cached.
  testthat::expect_false(
    activation_cache_rule(c(plain, paste0(tmp, "/x")), tmp_dir = tmp)$cache
  )
  # A value that names the working directory: cached for it.
  testthat::expect_identical(
    activation_cache_rule(
      c(plain, "/work/project"),
      tmp_dir = tmp,
      wd = "/work/project",
      fixed_dirs = c(env_dir, root)
    ),
    list(cache = TRUE, wd = "/work/project")
  )
  testthat::expect_identical(
    activation_cache_rule(
      c(plain, paste0(home, "/notes")),
      tmp_dir = tmp,
      wd = home,
      fixed_dirs = c(env_dir, root)
    ),
    list(cache = TRUE, wd = home)
  )
})
