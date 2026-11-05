# `env_path()` refers to an environment by its directory. The environments
# here are built with `create_prefix_env()` (helper-env-path.R) in a
# temporary directory outside the condathis root, as another conda client
# would, from the local polyglot channel: no network access is needed once
# micromamba is installed.

# A backend that only reports that it is unavailable, as in
# man/examples/backend-stub.R, registered for the calling test only.
register_env_path_stub_backend <- function(name, envir = parent.frame()) {
  not_implemented <- function(...) {
    stop("Not implemented by this stub backend.")
  }
  stub_root <- function() {
    root <- file.path(tempdir(), name)
    dir.create(root, recursive = TRUE, showWarnings = FALSE)
    return(normalizePath(root, winslash = "/"))
  }
  stub <- structure(
    list(
      backend_create_env = not_implemented,
      backend_install = not_implemented,
      backend_remove_env = not_implemented,
      backend_list_envs = function(backend, verbose) character(),
      backend_env_exists = function(backend, env_name, verbose) FALSE,
      backend_list_packages = not_implemented,
      backend_get_env_dir = function(backend, env_name) {
        file.path(stub_root(), "envs", env_name)
      },
      # The contract requires the absolute path of an existing directory.
      backend_get_install_dir = function(backend) {
        stub_root()
      },
      backend_resolve_run = not_implemented,
      backend_available = function(backend) FALSE
    ),
    class = c(paste0("condathis_backend_", name), "condathis_backend")
  )
  register_backend(name, stub)
  withr::defer(unregister_backend(name), envir = envir)
  return(invisible(stub))
}

# --- Construction (no micromamba) -------------------------------------------

testthat::test_that("env_path() rejects anything but a single non-empty string", {
  invalid_paths <- list(
    NULL,
    NA,
    NA_character_,
    "",
    c("a", "b"),
    1,
    TRUE,
    list("a")
  )
  for (path in invalid_paths) {
    cnd <- testthat::expect_error(
      env_path(path),
      class = "condathis_env_path_invalid"
    )
    # The classes of rule R1, with the old class kept.
    testthat::expect_identical(
      class(cnd)[1:5],
      c(
        "condathis_env_path_invalid_path",
        "condathis_env_path_invalid",
        "condathis_invalid_path",
        "condathis_invalid_arg",
        "condathis_error"
      )
    )
  }
  cnd <- testthat::expect_error(env_path(), class = "condathis_invalid_path")
  testthat::expect_match(conditionMessage(cnd), "absent", fixed = TRUE)
})

testthat::test_that("env_path() makes a relative path absolute at call time", {
  wd <- withr::local_tempdir()
  withr::local_dir(wd)
  expected <- as.character(fs::path_norm(fs::path(getwd(), "not-yet", "env")))

  ep <- env_path("not-yet/env")
  testthat::expect_true(fs::is_absolute_path(ep$path))
  testthat::expect_identical(ep$path, expected)
  # `..` and `.` are normalized away.
  testthat::expect_identical(
    env_path("not-yet/../not-yet/./env")$path,
    expected
  )

  # The object holds the absolute path: a later setwd() changes nothing.
  withr::local_dir(withr::local_tempdir())
  testthat::expect_identical(ep$path, expected)
  testthat::expect_false(identical(env_path("not-yet/env")$path, expected))
})

testthat::test_that("env_path() expands a leading tilde", {
  ep <- env_path("~/condathis-env-path-no-such-dir")
  testthat::expect_false(startsWith(ep$path, "~"))
  testthat::expect_true(fs::is_absolute_path(ep$path))
  testthat::expect_identical(
    ep$path,
    as.character(
      fs::path_norm(fs::path_expand("~/condathis-env-path-no-such-dir"))
    )
  )
})

testthat::test_that("env_path() resolves an existing directory to its real path", {
  dir <- withr::local_tempdir()
  ep <- env_path(dir)
  testthat::expect_identical(ep$path, as.character(fs::path_real(dir)))
  # Two spellings of one directory give one path, so they share one
  # activation cache entry.
  testthat::expect_identical(env_path(fs::path(dir, "."))$path, ep$path)
  testthat::expect_identical(
    env_path(paste0(dir, "/sub/.."))$path,
    ep$path
  )
})

testthat::test_that("env_path() does not check that the directory exists", {
  missing_dir <- fs::path(withr::local_tempdir(), "env-path-not-created")
  ep <- testthat::expect_no_error(env_path(missing_dir))
  testthat::expect_s3_class(ep, "condathis_env_path")
  testthat::expect_false(fs::dir_exists(missing_dir))
})

testthat::test_that("env_path() returns a classed list, not a character vector", {
  ep <- env_path(withr::local_tempdir())
  testthat::expect_s3_class(ep, "condathis_env_path", exact = TRUE)
  testthat::expect_true(is.list(ep))
  testthat::expect_false(is.character(ep))
  testthat::expect_identical(names(ep), "path")
  testthat::expect_true(rlang::is_string(ep$path))
})

testthat::test_that("env_path() has format and print methods", {
  ep <- env_path(withr::local_tempdir())
  testthat::expect_identical(format(ep), paste0("<env_path> ", ep$path))

  out <- utils::capture.output(visible <- withVisible(print(ep)))
  testthat::expect_identical(out, paste0("<env_path> ", ep$path))
  testthat::expect_false(visible$visible)
  testthat::expect_identical(visible$value, ep)
})

testthat::test_that("a forged condathis_env_path object is rejected where it is used", {
  forged <- list(
    structure(list(path = "relative/x"), class = "condathis_env_path"),
    structure(list(path = NA_character_), class = "condathis_env_path"),
    structure(list(path = c("/a", "/b")), class = "condathis_env_path"),
    structure(list(), class = "condathis_env_path"),
    structure("/abs/path", class = "condathis_env_path")
  )
  for (ep in forged) {
    cnd <- testthat::expect_error(
      run("polyglot", env_name = ep, verbose = "silent"),
      class = "condathis_env_path_invalid"
    )
    # Every invalid `env_name` shares `condathis_invalid_env_name`, and the
    # function's own class names it.
    testthat::expect_identical(
      class(cnd)[1:5],
      c(
        "condathis_env_path_invalid",
        "condathis_run_invalid_env_name",
        "condathis_invalid_env_name",
        "condathis_invalid_arg",
        "condathis_error"
      )
    )
    testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run")
    # Not a missing environment: `error = "continue"` does not apply.
    testthat::expect_error(
      run("polyglot", env_name = ep, error = "continue", verbose = "silent"),
      class = "condathis_env_path_invalid"
    )
    cnd <- testthat::expect_error(
      run_bin("polyglot", env_name = ep, verbose = "silent"),
      class = "condathis_env_path_invalid"
    )
    testthat::expect_s3_class(cnd, "condathis_run_bin_invalid_env_name")
    testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
    testthat::expect_identical(rlang::call_name(conditionCall(cnd)), "run_bin")
    cnd <- testthat::expect_error(
      run_pipeline(
        run_step("polyglot"),
        run_step("polyglot"),
        env_name = ep,
        verbose = "silent"
      ),
      class = "condathis_env_path_invalid"
    )
    testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
    cnd <- testthat::expect_error(
      run_step("polyglot", env_name = ep),
      class = "condathis_env_path_invalid"
    )
    testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
  }
})

# --- Read-only safety -------------------------------------------------------

testthat::test_that("only the run() family accepts an environment given by path", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  prefix <- fs::path(withr::local_tempdir(), "env-path-read-only")
  create_prefix_env(prefix)
  ep <- env_path(prefix)
  missing_ep <- env_path(fs::path(withr::local_tempdir(), "env-path-absent"))
  channel <- polyglot_channel()

  # Every exported function with an `env_name` argument must be listed in
  # exactly one of these two lists, so a new one fails this test until it
  # is classified.
  accepts <- list(
    run = list(
      class = "condathis_result",
      call = function(env) run("polyglot", env_name = env, verbose = "silent")
    ),
    run_bin = list(
      class = "condathis_result",
      call = function(env) {
        run_bin("polyglot", env_name = env, verbose = "silent")
      }
    ),
    run_pipeline = list(
      class = "condathis_pipeline",
      call = function(env) {
        run_pipeline(
          run_step("polyglot"),
          run_step("polyglot"),
          env_name = env,
          verbose = "silent"
        )
      }
    ),
    run_step = list(
      class = "condathis_run_step",
      call = function(env) run_step("polyglot", env_name = env)
    )
  )
  rejects <- list(
    create_env = list(
      class = "condathis_create_invalid_env_name",
      call = function(env) {
        create_env(
          "polyglot",
          env_name = env,
          channels = channel,
          verbose = "silent"
        )
      }
    ),
    install_packages = list(
      class = "condathis_install_packages_invalid_env_name",
      call = function(env) {
        install_packages(
          "polyglot",
          env_name = env,
          channels = channel,
          verbose = "silent"
        )
      }
    ),
    remove_env = list(
      class = "condathis_remove_env_invalid_env_name",
      call = function(env) remove_env(env_name = env, verbose = "silent")
    ),
    env_exists = list(
      class = "condathis_env_exists_invalid_env_name",
      call = function(env) env_exists(env_name = env)
    ),
    list_packages = list(
      class = "condathis_list_packages_invalid_env_name",
      call = function(env) list_packages(env_name = env, verbose = "silent")
    ),
    get_env_dir = list(
      class = "condathis_get_env_dir_invalid_env_name",
      call = function(env) get_env_dir(env_name = env)
    ),
    validate_env = list(
      class = "condathis_validate_env_invalid_env_name",
      call = function(env) validate_env(env_name = env)
    )
  )

  exported <- mget(
    getNamespaceExports("condathis"),
    envir = asNamespace("condathis")
  )
  with_env_name <- names(Filter(
    function(f) is.function(f) && "env_name" %in% names(formals(f)),
    exported
  ))
  testthat::expect_setequal(with_env_name, c(names(accepts), names(rejects)))
  testthat::expect_length(intersect(names(accepts), names(rejects)), 0L)

  for (fn_name in with_env_name) {
    if (fn_name %in% names(accepts)) {
      testthat::expect_s3_class(
        accepts[[fn_name]]$call(ep),
        accepts[[fn_name]]$class
      )
      next
    }
    if (isFALSE(fn_name %in% names(rejects))) {
      testthat::fail(sprintf(
        "Exported `%s()` takes `env_name`: classify how it treats `env_path()`.",
        fn_name
      ))
      next
    }
    # Rejected before anything else, whether the directory exists or not.
    for (env in list(ep, missing_ep)) {
      cnd <- testthat::expect_error(
        rejects[[fn_name]]$call(env),
        class = "condathis_env_path_read_only",
        info = fn_name
      )
      # The function's own invalid-`env_name` class, for existing handlers,
      # and the shared classes of every invalid `env_name`.
      testthat::expect_s3_class(cnd, rejects[[fn_name]]$class)
      testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
      testthat::expect_s3_class(cnd, "condathis_invalid_arg")
      testthat::expect_s3_class(cnd, "condathis_error")
    }
  }

  # Nothing touched the environment: it still runs, and condathis still
  # does not know it by name.
  testthat::expect_true(fs::dir_exists(fs::path(prefix, "conda-meta")))
  testthat::expect_identical(
    run("polyglot", env_name = ep, verbose = "silent")$status,
    0L
  )
  testthat::expect_false(fs::dir_exists(missing_ep$path))
  testthat::expect_false(fs::path_file(prefix) %in% list_envs())
  testthat::expect_false(env_exists(fs::path_file(prefix)))
})

# --- Running commands -------------------------------------------------------

testthat::test_that("run(), run_bin() and run_pipeline() run in an environment given by path", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  prefix <- fs::path(withr::local_tempdir(), "env-path-run")
  create_prefix_env(prefix)
  ep <- env_path(prefix)

  for (fn in list(run, run_bin)) {
    res <- fn("polyglot", env_name = ep, verbose = "silent")
    testthat::expect_s3_class(res, "condathis_result")
    testthat::expect_identical(res$status, 0L)
    testthat::expect_identical(res$env_name, ep$path)
    testthat::expect_identical(
      parse_output(res)[[1L]],
      polyglot_expected_line()
    )
  }

  # As the pipeline default.
  res <- run_pipeline(
    run_step("polyglot"),
    run_step("polyglot"),
    env_name = ep,
    verbose = "silent"
  )
  expect_pipeline_statuses_ok(res)
  testthat::expect_identical(
    vapply(res$processes, `[[`, character(1L), "env_name"),
    rep(ep$path, 2L)
  )
  testthat::expect_identical(parse_output(res)[[1L]], polyglot_expected_line())

  # Per step. No step uses the default "condathis-env", so it is not
  # created either.
  res <- run_pipeline(
    run_step("polyglot", env_name = ep),
    run_step("polyglot", env_name = ep),
    verbose = "silent"
  )
  expect_pipeline_statuses_ok(res)
  testthat::expect_identical(
    vapply(res$processes, `[[`, character(1L), "env_name"),
    rep(ep$path, 2L)
  )
})

testthat::test_that("a pipeline mixes a step given by path with a named step", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  prefix <- fs::path(withr::local_tempdir(), "env-path-mixed")
  create_prefix_env(prefix)
  ep <- env_path(prefix)
  create_polyglot_env("env-path-named-env")

  res <- run_pipeline(
    run_step("polyglot", env_name = ep),
    run_step("polyglot"),
    env_name = "env-path-named-env",
    verbose = "silent"
  )
  expect_pipeline_statuses_ok(res)
  testthat::expect_identical(
    vapply(res$processes, `[[`, character(1L), "env_name"),
    c(ep$path, "env-path-named-env")
  )
  testthat::expect_identical(parse_output(res)[[1L]], polyglot_expected_line())

  # The other way around: the path is the default, a step names its own.
  res <- run_pipeline(
    run_step("polyglot", env_name = "env-path-named-env"),
    run_step("polyglot"),
    env_name = ep,
    verbose = "silent"
  )
  expect_pipeline_statuses_ok(res)
  testthat::expect_identical(
    vapply(res$processes, `[[`, character(1L), "env_name"),
    c("env-path-named-env", ep$path)
  )
})

testthat::test_that("a relative env_path() still finds its environment after setwd()", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  parent <- withr::local_tempdir()
  create_prefix_env(fs::path(parent, "env-path-relative"))

  withr::local_dir(parent)
  ep <- env_path("env-path-relative")
  testthat::expect_identical(
    ep$path,
    as.character(fs::path_real(fs::path(parent, "env-path-relative")))
  )

  withr::local_dir(withr::local_tempdir())
  testthat::expect_false(fs::dir_exists("env-path-relative"))
  for (fn in list(run, run_bin)) {
    res <- fn("polyglot", env_name = ep, verbose = "silent")
    testthat::expect_identical(res$status, 0L)
    testthat::expect_identical(res$env_name, ep$path)
  }
})

testthat::test_that("a missing environment directory honors error and is never created", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  missing_dir <- fs::path(withr::local_tempdir(), "env-path-missing")
  ep <- env_path(missing_dir)

  # run(): "cancel" aborts, with run()'s own "not found" class too, and the
  # class every missing environment shares.
  cnd <- testthat::expect_error(
    run("polyglot", env_name = ep, verbose = "silent"),
    class = "condathis_env_path_not_found"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_env_path_not_found",
      "condathis_run_env_not_found",
      "condathis_env_not_found",
      "condathis_error"
    )
  )
  res <- run("polyglot", env_name = ep, error = "continue", verbose = "silent")
  testthat::expect_identical(res$status, 127L)
  testthat::expect_match(res$stderr, "does not exist", fixed = TRUE)
  testthat::expect_identical(res$env_name, ep$path)

  # run_bin(), with its own "not found" class.
  cnd <- testthat::expect_error(
    run_bin("polyglot", env_name = ep, verbose = "silent"),
    class = "condathis_env_path_not_found"
  )
  testthat::expect_s3_class(cnd, "condathis_run_bin_env_not_found")
  testthat::expect_s3_class(cnd, "condathis_env_not_found")
  res <- run_bin(
    "polyglot",
    env_name = ep,
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
  testthat::expect_match(res$stderr, "does not exist", fixed = TRUE)
  testthat::expect_identical(res$env_name, ep$path)

  # run_pipeline(), with its own "not found" class too.
  cnd <- testthat::expect_error(
    run_pipeline(
      run_step("polyglot"),
      run_step("polyglot"),
      env_name = ep,
      verbose = "silent"
    ),
    class = "condathis_env_path_not_found"
  )
  testthat::expect_s3_class(cnd, "condathis_pipeline_env_not_found")
  testthat::expect_s3_class(cnd, "condathis_env_not_found")
  res <- run_pipeline(
    run_step("polyglot"),
    run_step("polyglot"),
    env_name = ep,
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$statuses, c(127L, 127L))
  testthat::expect_match(
    res$processes[[1L]]$stderr,
    "does not exist",
    fixed = TRUE
  )
  testthat::expect_identical(res$processes[[1L]]$env_name, ep$path)

  # No call created the directory.
  testthat::expect_false(fs::dir_exists(missing_dir))
})

testthat::test_that("a directory without conda-meta honors error and is left alone", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  plain_dir <- withr::local_tempdir()
  ep <- env_path(plain_dir)

  cnd <- testthat::expect_error(
    run("polyglot", env_name = ep, verbose = "silent"),
    class = "condathis_env_path_not_conda_env"
  )
  testthat::expect_s3_class(cnd, "condathis_run_env_not_found")
  res <- run("polyglot", env_name = ep, error = "continue", verbose = "silent")
  testthat::expect_identical(res$status, 127L)
  testthat::expect_match(res$stderr, "conda-meta", fixed = TRUE)

  cnd <- testthat::expect_error(
    run_bin("polyglot", env_name = ep, verbose = "silent"),
    class = "condathis_env_path_not_conda_env"
  )
  testthat::expect_s3_class(cnd, "condathis_run_bin_env_not_found")
  testthat::expect_s3_class(cnd, "condathis_env_not_found")
  res <- run_bin(
    "polyglot",
    env_name = ep,
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
  testthat::expect_match(res$stderr, "conda-meta", fixed = TRUE)

  cnd <- testthat::expect_error(
    run_pipeline(
      run_step("polyglot"),
      run_step("polyglot"),
      env_name = ep,
      verbose = "silent"
    ),
    class = "condathis_env_path_not_conda_env"
  )
  testthat::expect_s3_class(cnd, "condathis_pipeline_env_not_found")
  res <- run_pipeline(
    run_step("polyglot"),
    run_step("polyglot"),
    env_name = ep,
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$statuses, c(127L, 127L))
  testthat::expect_match(res$processes[[2L]]$stderr, "conda-meta", fixed = TRUE)

  testthat::expect_false(fs::dir_exists(fs::path(plain_dir, "conda-meta")))
  testthat::expect_length(fs::dir_ls(plain_dir, all = TRUE), 0L)
})

testthat::test_that("a backend without backend_resolve_run_in_dir() cannot run an environment given by path", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  stub_name <- "envpathstub"
  register_env_path_stub_backend(stub_name)
  testthat::expect_true(stub_name %in% list_registered_backend_names())

  prefix <- fs::path(withr::local_tempdir(), "env-path-method")
  create_prefix_env(prefix)
  ep <- env_path(prefix)

  # Not gated by `error`: the call itself is wrong.
  for (error_mode in c("cancel", "continue")) {
    cnd <- testthat::expect_error(
      run(
        "polyglot",
        env_name = ep,
        method = stub_name,
        error = error_mode,
        verbose = "silent"
      ),
      class = "condathis_env_path_unsupported_method"
    )
    testthat::expect_identical(
      class(cnd)[1:5],
      c(
        "condathis_env_path_unsupported_method",
        "condathis_backend_unsupported",
        "condathis_invalid_method",
        "condathis_invalid_arg",
        "condathis_error"
      )
    )
    testthat::expect_error(
      run_bin(
        "polyglot",
        env_name = ep,
        method = stub_name,
        error = error_mode,
        verbose = "silent"
      ),
      class = "condathis_env_path_unsupported_method"
    )
    testthat::expect_error(
      run_pipeline(
        run_step("polyglot"),
        run_step("polyglot"),
        env_name = ep,
        method = stub_name,
        error = error_mode,
        verbose = "silent"
      ),
      class = "condathis_env_path_unsupported_method"
    )
    # Also when only one step asks for the other backend.
    testthat::expect_error(
      run_pipeline(
        run_step("polyglot", env_name = ep, method = stub_name),
        run_step("polyglot", env_name = ep),
        error = error_mode,
        verbose = "silent"
      ),
      class = "condathis_env_path_unsupported_method"
    )
  }

  # "auto" (the default) and "micromamba" are supported.
  for (method in c("auto", "micromamba")) {
    res <- run("polyglot", env_name = ep, method = method, verbose = "silent")
    testthat::expect_identical(res$status, 0L)
    res <- run_pipeline(
      run_step("polyglot", method = method),
      run_step("polyglot"),
      env_name = ep,
      verbose = "silent"
    )
    expect_pipeline_statuses_ok(res)
  }
})

testthat::test_that("a backend with backend_resolve_run_in_dir() runs an environment given by path", {
  # A stub backend (helper-stub-backend.R) whose hook names the directory
  # it was given in the command's environment. No micromamba is needed.
  prefix <- fs::path(withr::local_tempdir(), "env-path-stub")
  fs::dir_create(fs::path(prefix, "conda-meta"))
  ep <- env_path(prefix)
  rscript <- file.path(R.home("bin"), "Rscript")
  code <- "cat(Sys.getenv('STUB_ENV_DIR'), Sys.getenv('STUB_UNSET', 'unset'))"
  stub <- local_stub_backend(
    "stub-indir",
    backend_resolve_run_in_dir = function(
      backend,
      cmd,
      args = character(0L),
      env_dir,
      verbose = "silent",
      base_env = NULL
    ) {
      return(list(
        command = cmd,
        args = args,
        env = c(STUB_ENV_DIR = env_dir, STUB_UNSET = NA),
        dir = NULL
      ))
    }
  )
  withr::local_envvar(STUB_UNSET = "session")
  expected <- paste(ep$path, "unset")

  res <- run(
    rscript,
    "-e",
    code,
    env_name = ep,
    method = "stub-indir",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, expected)
  testthat::expect_identical(res$env_name, ep$path)
  res <- run_bin(
    rscript,
    "-e",
    code,
    env_name = ep,
    method = "stub-indir",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, expected)
  # Both steps print; the result is the last one's output. The last step
  # reads its input first, so the first step never writes to a closed pipe.
  pipe_code <- paste0("invisible(readLines(file('stdin'))); ", code)
  res <- run_pipeline(
    run_step(rscript, "-e", code),
    run_step(rscript, "-e", pipe_code),
    env_name = ep,
    method = "stub-indir",
    verbose = "silent"
  )
  expect_pipeline_statuses_ok(res)
  testthat::expect_identical(parse_output(res), expected)

  calls <- stub_calls(stub, "backend_resolve_run_in_dir")
  testthat::expect_length(calls, 4L)
  testthat::expect_identical(
    lapply(calls, function(call) call$args$args),
    list(c("-e", code), c("-e", code), c("-e", code), c("-e", pipe_code))
  )
  for (call in calls) {
    testthat::expect_identical(call$args$env_dir, ep$path)
    testthat::expect_identical(call$args$cmd, rscript)
    testthat::expect_true(rlang::is_string(call$args$verbose))
    testthat::expect_true(is.character(call$args$base_env))
    testthat::expect_true(isFALSE(is.null(names(call$args$base_env))))
  }
  # The environment is never looked up by name, created or changed.
  testthat::expect_length(stub_calls(stub, "backend_resolve_run"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_env_exists"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)

  # Without activation, no backend function runs.
  res <- run_bin(
    rscript,
    "-e",
    "cat('plain')",
    env_name = ep,
    method = "stub-indir",
    activate = FALSE,
    verbose = "silent"
  )
  testthat::expect_identical(res$stdout, "plain")
  testthat::expect_length(stub_calls(stub, "backend_resolve_run_in_dir"), 4L)

  # "auto" takes the first backend of `condathis.backend_priority` that has
  # the function.
  testthat::expect_identical(
    resolve_env_path_target(ep, method = "auto")$name,
    "micromamba"
  )
  withr::local_options(
    condathis.backend_priority = c("stub-indir", "micromamba")
  )
  res <- run(rscript, "-e", code, env_name = ep, verbose = "silent")
  testthat::expect_identical(res$stdout, expected)
  testthat::expect_length(stub_calls(stub, "backend_resolve_run_in_dir"), 5L)
  withr::local_options(
    condathis.backend_priority = c("stub-plain", "micromamba")
  )
  local_stub_backend("stub-plain")
  testthat::expect_identical(
    resolve_env_path_target(ep, method = "auto")$name,
    "micromamba"
  )
})

testthat::test_that("the value and the errors of backend_resolve_run_in_dir() are checked as for backend_resolve_run()", {
  prefix <- fs::path(withr::local_tempdir(), "env-path-stub-bad")
  fs::dir_create(fs::path(prefix, "conda-meta"))
  ep <- env_path(prefix)
  rscript <- file.path(R.home("bin"), "Rscript")
  local_stub_backend(
    "stub-badindir",
    backend_resolve_run_in_dir = function(backend, ...) list(command = 1L)
  )
  for (fn in list(run, run_bin)) {
    testthat::expect_error(
      fn(rscript, env_name = ep, method = "stub-badindir", verbose = "silent"),
      class = "condathis_backend_resolve_run_invalid"
    )
  }
  testthat::expect_error(
    run_pipeline(
      run_step(rscript),
      run_step(rscript),
      env_name = ep,
      method = "stub-badindir",
      verbose = "silent"
    ),
    class = "condathis_backend_resolve_run_invalid"
  )

  local_stub_backend(
    "stub-failindir",
    backend_resolve_run_in_dir = function(backend, ...) stop("no activation")
  )
  cnd <- testthat::expect_error(
    run(rscript, env_name = ep, method = "stub-failindir", verbose = "silent"),
    class = "condathis_run_resolve_failed"
  )
  testthat::expect_match(conditionMessage(cnd$parent), "no activation")
  testthat::expect_error(
    run_bin(
      rscript,
      env_name = ep,
      method = "stub-failindir",
      verbose = "silent"
    ),
    class = "condathis_run_bin_resolve_failed"
  )
  res <- run(
    rscript,
    env_name = ep,
    method = "stub-failindir",
    error = "continue",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 127L)
})

testthat::test_that("the default of backend_resolve_run_in_dir() refuses, and registration checks its arguments", {
  backend <- structure(
    list(),
    class = c("condathis_backend_indir_default_test", "condathis_backend")
  )
  testthat::expect_error(
    backend_resolve_run_in_dir(backend, cmd = "x", env_dir = tempdir()),
    class = "condathis_backend_unsupported"
  )
  testthat::expect_false(backend_runs_in_dir(backend))
  testthat::expect_true(backend_runs_in_dir(micromamba_backend()))

  minimal <- structure(
    list(
      backend_create_env = function(backend, ...) NULL,
      backend_install = function(backend, ...) NULL,
      backend_resolve_run = function(backend, ...) NULL,
      backend_resolve_run_in_dir = function(backend, cmd, args) NULL
    ),
    class = c("condathis_backend_indir_args_test", "condathis_backend")
  )
  cnd <- testthat::expect_error(
    register_backend("indir-args-test", minimal),
    class = "condathis_backend_contract_violation"
  )
  testthat::expect_match(
    conditionMessage(cnd),
    "backend_resolve_run_in_dir",
    fixed = TRUE
  )
  testthat::expect_false("indir-args-test" %in% list_registered_backend_names())
})

testthat::test_that("run_bin() caches the activation of a path environment by directory", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  prefix <- fs::path(withr::local_tempdir(), "env-path-cache")
  create_prefix_env(prefix)
  ep <- env_path(prefix)
  cache_key <- paste0("path:", ep$path)
  reset_micromamba_activation_cache(cache_key)
  withr::defer(reset_micromamba_activation_cache(cache_key))
  testthat::expect_false(
    exists(cache_key, envir = condathis_activation_cache, inherits = FALSE)
  )

  res <- run_bin("polyglot", env_name = ep, verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_true(
    exists(cache_key, envir = condathis_activation_cache, inherits = FALSE)
  )
  # Keyed by the directory, never by the directory's base name.
  testthat::expect_false(
    exists(
      fs::path_file(prefix),
      envir = condathis_activation_cache,
      inherits = FALSE
    )
  )

  # Another spelling of the same directory reuses the entry.
  keys_before <- ls(condathis_activation_cache, all.names = TRUE)
  res <- run_bin(
    "polyglot",
    env_name = env_path(fs::path(prefix, ".")),
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    ls(condathis_activation_cache, all.names = TRUE),
    keys_before
  )
})

testthat::test_that("activate = FALSE keeps CONDA_ENVS_PATH at the condathis root for a path environment", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  prefix <- fs::path(withr::local_tempdir(), "env-path-envs-path")
  create_prefix_env(prefix)
  rscript <- file.path(R.home("bin"), "Rscript")
  root_envs <- as.character(
    fs::path(install_dir_for_backend(micromamba_backend()), "envs")
  )

  for (activate in c(TRUE, FALSE)) {
    res <- run_pipeline(
      run_step("polyglot"),
      run_step(
        rscript,
        "--vanilla",
        "-e",
        "invisible(readLines(file('stdin'))); cat(Sys.getenv('CONDA_ENVS_PATH'))"
      ),
      env_name = env_path(prefix),
      activate = activate,
      verbose = "silent"
    )
    testthat::expect_identical(res$statuses[[2L]], 0L)
    # The parent of the foreign environment is not a condathis directory.
    testthat::expect_identical(
      fs::path_norm(res$processes[[2L]]$stdout),
      fs::path_norm(root_envs)
    )
  }
})

testthat::test_that("a path environment of another backend gets that backend's own envs and package directories", {
  # The parent of a foreign environment is not a directory condathis
  # manages: its `envs` directory must not make the `conda-pkgs` next to it
  # (in the root of another installation) the package cache of a command.
  # The commands get the directories of the backend's own environments, as
  # micromamba's get those of its root.
  prefix <- fs::path(withr::local_tempdir(), "other-root", "envs", "ep-dirs")
  fs::dir_create(fs::path(prefix, "conda-meta"))
  ep <- env_path(prefix)
  local_stub_backend(
    "stub-ep-dirs",
    backend_resolve_run_in_dir = function(
      backend,
      cmd,
      args = character(0L),
      env_dir,
      verbose = "silent",
      base_env = NULL
    ) {
      return(list(command = cmd, args = args, env = NULL, dir = NULL))
    },
    default_root = TRUE
  )
  root <- backend_root_dir("stub-ep-dirs")
  rscript <- file.path(R.home("bin"), "Rscript")
  code <- paste0(
    "cat(Sys.getenv(c('CONDA_ENVS_PATH', 'CONDA_PKGS_DIRS', ",
    "'MAMBA_PKGS_DIRS')), sep = '|')"
  )
  expected <- paste(
    c(
      fs::path(root, "envs"),
      fs::path(root, "conda-pkgs"),
      fs::path(root, "conda-pkgs")
    ),
    collapse = "|"
  )
  call_args <- list(
    rscript,
    "-e",
    code,
    env_name = ep,
    method = "stub-ep-dirs",
    verbose = "silent"
  )
  outputs <- list(
    run = do.call(run, call_args)$stdout,
    run_bin = do.call(run_bin, call_args)$stdout,
    run_bin_noact = do.call(run_bin, c(call_args, activate = FALSE))$stdout
  )
  for (activate in c(TRUE, FALSE)) {
    res <- run_pipeline(
      run_step(rscript, "-e", "cat('x')"),
      run_step(
        rscript,
        "-e",
        paste0("invisible(readLines(file('stdin'))); ", code)
      ),
      env_name = ep,
      method = "stub-ep-dirs",
      activate = activate,
      verbose = "silent"
    )
    outputs[[paste0("run_pipeline_", activate)]] <- parse_output(res)
  }
  for (fn in names(outputs)) {
    testthat::expect_identical(outputs[[fn]], expected, info = fn)
  }
  # Nothing was created for the backend, or next to the environment.
  testthat::expect_false(fs::dir_exists(root))
  testthat::expect_identical(
    as.character(fs::path_file(fs::dir_ls(fs::path_dir(fs::path_dir(prefix))))),
    "envs"
  )
})

testthat::test_that("check_env_path_usable() aborts or reports, per error", {
  # One helper for run(), run_bin() and run_pipeline(), which each had a
  # copy of this check.
  conda_env <- withr::local_tempdir()
  fs::dir_create(fs::path(conda_env, "conda-meta"))
  plain_dir <- withr::local_tempdir()
  missing_dir <- fs::path(withr::local_tempdir(), "missing")

  for (error_var in c(TRUE, FALSE)) {
    testthat::expect_null(check_env_path_usable(conda_env, error_var))
  }
  testthat::expect_identical(
    check_env_path_usable(missing_dir, error_var = FALSE),
    sprintf("Environment directory '%s' does not exist.\n", missing_dir)
  )
  testthat::expect_match(
    check_env_path_usable(plain_dir, error_var = FALSE),
    "conda-meta",
    fixed = TRUE
  )
  cnd <- testthat::expect_error(
    check_env_path_usable(missing_dir, TRUE, class = "caller_class"),
    class = "condathis_env_path_not_found"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_env_path_not_found",
      "caller_class",
      "condathis_env_not_found",
      "condathis_error"
    )
  )
  testthat::expect_error(
    check_env_path_usable(plain_dir, error_var = TRUE),
    class = "condathis_env_path_not_conda_env"
  )
  # The error names the calling function.
  caller <- function() check_env_path_usable(missing_dir, error_var = TRUE)
  cnd <- testthat::expect_error(caller())
  testthat::expect_identical(rlang::call_name(cnd$call), "caller")
})

testthat::test_that("abort_env_path_read_only() has the classes of an invalid env_name", {
  cnd <- testthat::expect_error(
    abort_env_path_read_only(class = "condathis_caller_invalid_env_name"),
    class = "condathis_env_path_read_only"
  )
  testthat::expect_identical(
    class(cnd)[1:5],
    c(
      "condathis_env_path_read_only",
      "condathis_caller_invalid_env_name",
      "condathis_invalid_env_name",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  testthat::expect_match(conditionMessage(cnd), "must be an environment name")
})
