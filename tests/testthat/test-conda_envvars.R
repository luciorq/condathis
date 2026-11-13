testthat::test_that("get_clean_conda_envvars returns expected structure", {
  result <- get_clean_conda_envvars(tmp_dir = "/tmp/test")
  testthat::expect_type(result, "list")
  testthat::expect_equal(result$TMPDIR, "/tmp/test")
  testthat::expect_equal(result$R_HOME, "")
  testthat::expect_equal(result$CONDA_PREFIX, "")
  testthat::expect_equal(result$CONDA_SHLVL, "0")
  testthat::expect_equal(result$MAMBA_SHLVL, "0")
  testthat::expect_equal(result$CONDARC, "")
  testthat::expect_equal(result$MAMBARC, "")
})

testthat::test_that("get_clean_conda_envvars points the conda dirs at the micromamba root", {
  # Regression test: an empty `CONDA_PKGS_DIRS`/`MAMBA_PKGS_DIRS` made
  # micromamba fall back to a list that includes the user's global
  # `~/.mamba/pkgs`, which `clean_cache()` then deleted. A child of the
  # micromamba backend gets the `envs/` and `pkgs/` of its root.
  result <- get_clean_conda_envvars(
    tmp_dir = "/tmp/test",
    conda_dirs = micromamba_conda_dirs("/my")
  )
  testthat::expect_identical(
    result$CONDA_ENVS_PATH,
    as.character(fs::path("/my", "envs"))
  )
  testthat::expect_identical(
    result$CONDA_PKGS_DIRS,
    as.character(fs::path("/my", "pkgs"))
  )
  testthat::expect_identical(result$MAMBA_PKGS_DIRS, result$CONDA_PKGS_DIRS)
})

testthat::test_that("get_clean_conda_envvars clears the conda dirs it is not given", {
  # Regression test: without conda directories, the variables were taken
  # from the micromamba root for every child, so a command of a rattler or
  # other third-party backend got the micromamba package cache and envs
  # directory.
  result <- get_clean_conda_envvars(tmp_dir = "/tmp/test")
  testthat::expect_identical(result$CONDA_ENVS_PATH, "")
  testthat::expect_identical(result$CONDA_PKGS_DIRS, "")
  testthat::expect_identical(result$MAMBA_PKGS_DIRS, "")

  # Only an envs directory, as a child of another backend gets.
  result <- get_clean_conda_envvars(
    tmp_dir = "/tmp/test",
    conda_dirs = list(envs_dir = "/other/envs", pkgs_dir = NULL)
  )
  testthat::expect_identical(result$CONDA_ENVS_PATH, "/other/envs")
  testthat::expect_identical(result$CONDA_PKGS_DIRS, "")
  testthat::expect_identical(result$MAMBA_PKGS_DIRS, "")
})

testthat::test_that("building a child environment does no file system access", {
  # Regression test: get_clean_conda_envvars() created and real-path
  # resolved the micromamba data directory on every call, also for
  # `native_cmd()`, which had already resolved it, and for children of
  # other backends.
  fail_on_access <- function(...) {
    cli::cli_abort("The micromamba data directory must not be accessed.")
  }
  testthat::local_mocked_bindings(
    install_dir_for_backend = fail_on_access,
    get_condathis_path = fail_on_access
  )
  other_backend <- structure(
    list(),
    class = c("condathis_backend_other", "condathis_backend")
  )
  testthat::expect_no_error(get_clean_conda_envvars(tmp_dir = "/tmp/test"))
  testthat::expect_no_error(
    get_clean_conda_envvars(
      tmp_dir = "/tmp/test",
      conda_dirs = micromamba_conda_dirs("/my")
    )
  )
  testthat::expect_no_error(build_child_env(tmp_dir = "/tmp/test"))
  testthat::expect_no_error(
    build_child_env(
      tmp_dir = "/tmp/test",
      conda_dirs = micromamba_conda_dirs("/my")
    )
  )
  testthat::expect_no_error(
    build_child_env(
      tmp_dir = "/tmp/test",
      conda_dirs = child_conda_dirs(other_backend, env_dir = "/other/envs/e")
    )
  )
})

testthat::test_that("child_conda_dirs() takes the conda dirs from the owning backend", {
  # Regression tests:
  # - every child got the micromamba package cache and envs directory,
  #   whichever backend owned its environment;
  # - a child of another backend then got `""` for all three variables, so
  #   `with_sandbox_dir()` no longer recognized a process it left running,
  #   and `run_pipeline(activate = FALSE)` was the only entry point that
  #   set `CONDA_ENVS_PATH` for it.
  root_dir <- install_dir_for_backend(micromamba_backend())
  testthat::expect_identical(
    child_conda_dirs(micromamba_backend(), env_dir = "/foreign/env"),
    micromamba_conda_dirs(root_dir)
  )
  # The micromamba backend never needs the environment's directory, so a
  # caller can pass an expensive lookup that runs only for other backends.
  testthat::expect_no_error(
    child_conda_dirs(
      micromamba_backend(),
      env_dir = cli::cli_abort("env_dir must not be evaluated.")
    )
  )

  # Any other backend: the directory that holds the environment, the
  # `conda-pkgs` directory of its root, and no access to the micromamba
  # data directory.
  other_backend <- structure(
    list(),
    class = c("condathis_backend_other", "condathis_backend")
  )
  testthat::local_mocked_bindings(
    install_dir_for_backend = function(...) {
      cli::cli_abort("The micromamba data directory must not be accessed.")
    }
  )
  testthat::expect_identical(
    child_conda_dirs(other_backend, env_dir = "/other/root/envs/e"),
    list(
      envs_dir = as.character(fs::path("/other/root/envs")),
      pkgs_dir = as.character(fs::path("/other/root/conda-pkgs"))
    )
  )
  testthat::expect_identical(
    child_conda_dirs(other_backend, env_dir = NULL),
    list(envs_dir = NULL, pkgs_dir = NULL)
  )
})

testthat::test_that("a child of another backend gets the conda-pkgs of its root, never micromamba's cache", {
  # Regression tests:
  # - a child of a non-micromamba backend got `""` for both package-cache
  #   variables, so a Conda tool run in a rattler environment kept its
  #   packages in the user's `~/.conda/pkgs`, outside condathis's data
  #   directory;
  # - every child got the micromamba package cache, whichever backend owned
  #   its environment.
  other_backend <- structure(
    list(),
    class = c("condathis_backend_other", "condathis_backend")
  )
  fail_on_access <- function(...) {
    cli::cli_abort("No file system access is allowed here.")
  }
  testthat::local_mocked_bindings(
    install_dir_for_backend = fail_on_access,
    get_condathis_path = fail_on_access
  )
  root <- fs::path(withr::local_tempdir(), "condathis", "other")
  dirs <- child_conda_dirs(other_backend, env_dir = fs::path(root, "envs", "e"))
  testthat::expect_identical(
    dirs$pkgs_dir,
    as.character(fs::path(root, "conda-pkgs"))
  )
  # Only computed: nothing is created.
  testthat::expect_false(fs::dir_exists(fs::path(root)))
  # The micromamba package cache is `<condathis root>/pkgs`, and the
  # backend's own caches stay its own.
  testthat::expect_false(identical(
    dirs$pkgs_dir,
    as.character(fs::path(fs::path_dir(root), "pkgs"))
  ))
  testthat::expect_false(identical(
    dirs$pkgs_dir,
    as.character(fs::path(root, "pkgs"))
  ))

  # An environment that is not in a directory named `envs` (a backend with
  # a layout of its own): no package cache to give, so both variables are
  # `""`.
  dirs <- child_conda_dirs(
    other_backend,
    env_dir = fs::path(root, "prefixes", "e")
  )
  testthat::expect_identical(
    dirs$envs_dir,
    as.character(fs::path(root, "prefixes"))
  )
  testthat::expect_null(dirs$pkgs_dir)
  child_env <- build_child_env(tmp_dir = "/tmp/test", conda_dirs = dirs)
  testthat::expect_identical(
    unname(child_env[c("CONDA_PKGS_DIRS", "MAMBA_PKGS_DIRS")]),
    c("", "")
  )

  # A name that only ends in `envs` is not `envs`.
  testthat::expect_null(
    child_conda_dirs(other_backend, env_dir = "/x/my-envs/e")$pkgs_dir
  )
  # On Windows, the name is compared without case.
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  testthat::expect_identical(
    child_conda_dirs(other_backend, env_dir = "/x/root/Envs/e")$pkgs_dir,
    as.character(fs::path("/x/root", "conda-pkgs"))
  )
})

testthat::test_that("an environment directory of a backend's own gets conda-pkgs only in its root", {
  # Regression test: any parent directory named `envs` gave its sibling
  # `conda-pkgs`, so the children of a backend that keeps its environments
  # in `/data/envs` got `/data/conda-pkgs`, a directory of another tool,
  # which clean_cache() then deleted.
  elsewhere <- fs::path_real(withr::local_tempdir())
  env_dir_in <- function(dir) {
    force(dir)
    return(function(backend, env_name = "condathis-env") {
      return(fs::path(dir, "envs", env_name))
    })
  }
  # A root of its own (the stub's `backend_get_install_dir()`).
  stub_out <- local_stub_backend(
    "stub-pkgs-outside",
    backend_get_env_dir = env_dir_in(elsewhere)
  )
  testthat::expect_null(
    child_conda_dirs(
      stub_out$backend,
      env_dir = fs::path(elsewhere, "envs", "e")
    )$pkgs_dir
  )
  stub_in <- local_stub_backend("stub-pkgs-inside")
  testthat::expect_identical(
    child_conda_dirs(
      stub_in$backend,
      env_dir = fs::path(stub_in$root, "envs", "e")
    )$pkgs_dir,
    as.character(fs::path(stub_in$root, "conda-pkgs"))
  )
  # The root that condathis assigns, with an own backend_get_env_dir().
  listing <- list(
    backend_list_envs = function(backend, ...) character(0L),
    backend_env_exists = function(backend, ...) FALSE
  )
  default_root <- backend_root_dir("stub-pkgs-assigned")
  stub_assigned <- do.call(
    local_stub_backend,
    c(
      list(
        "stub-pkgs-assigned",
        default_root = TRUE,
        backend_get_env_dir = env_dir_in(default_root)
      ),
      listing
    )
  )
  testthat::expect_identical(
    child_conda_dirs(
      stub_assigned$backend,
      env_dir = fs::path(default_root, "envs", "e")
    )$pkgs_dir,
    as.character(fs::path(default_root, "conda-pkgs"))
  )
  testthat::expect_null(
    child_conda_dirs(
      stub_assigned$backend,
      env_dir = fs::path(elsewhere, "envs", "e")
    )$pkgs_dir
  )
  # Only computed: the assigned root is not created.
  testthat::expect_false(fs::dir_exists(default_root))
})

testthat::test_that("children of a stub backend get its conda-pkgs, with and without activation", {
  testthat::skip_on_cran()
  # The rule of `child_conda_dirs()`, end to end through run(), run_bin()
  # and run_pipeline() (both `activate` values), for a backend with the
  # root condathis assigns.
  stub <- local_stub_backend(
    "stub-pkgs",
    envs = "pkgs-env",
    default_root = TRUE
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-pkgs"
  )
  root <- backend_root_dir("stub-pkgs")
  rscript <- get_condathis_rscript_path()
  dump_dir <- withr::local_tempdir()
  withr::local_envvar(
    CONDA_PKGS_DIRS = "/user/pkgs",
    MAMBA_PKGS_DIRS = "/user/pkgs"
  )
  entry_points <- list(
    run = function(script) {
      run(
        rscript,
        "--vanilla",
        script,
        env_name = "pkgs-env",
        verbose = "silent"
      )
    },
    run_bin = function(script) {
      run_bin(
        rscript,
        "--vanilla",
        script,
        env_name = "pkgs-env",
        verbose = "silent"
      )
    },
    run_bin_no_activate = function(script) {
      run_bin(
        rscript,
        "--vanilla",
        script,
        env_name = "pkgs-env",
        activate = FALSE,
        verbose = "silent"
      )
    },
    run_pipeline = function(script) {
      run_pipeline(
        run_step(rscript, "--vanilla", script),
        run_step(
          rscript,
          "--vanilla",
          "-e",
          "invisible(readLines(file('stdin')))"
        ),
        env_name = "pkgs-env",
        verbose = "silent"
      )
    },
    run_pipeline_no_activate = function(script) {
      run_pipeline(
        run_step(rscript, "--vanilla", script),
        run_step(
          rscript,
          "--vanilla",
          "-e",
          "invisible(readLines(file('stdin')))"
        ),
        env_name = "pkgs-env",
        activate = FALSE,
        verbose = "silent"
      )
    }
  )
  expected <- as.character(fs::path_norm(fs::path(root, "conda-pkgs")))
  for (entry_point in names(entry_points)) {
    dump_path <- fs::path(dump_dir, paste0(entry_point, ".rds"))
    script_path <- fs::path(dump_dir, paste0(entry_point, ".R"))
    writeLines(
      paste0(
        "saveRDS(Sys.getenv(c('CONDA_PKGS_DIRS', 'MAMBA_PKGS_DIRS')), ",
        "file = ",
        deparse(as.character(dump_path)),
        ")"
      ),
      script_path
    )
    entry_points[[entry_point]](as.character(script_path))
    child_vars <- unname(readRDS(dump_path))
    testthat::expect_identical(
      as.character(fs::path_norm(child_vars)),
      c(expected, expected),
      info = entry_point
    )
  }
  # Nothing creates the directory: a Conda tool does when it needs it.
  testthat::expect_false(fs::dir_exists(fs::path(root, "conda-pkgs")))
})

testthat::test_that("micromamba uses only the condathis package cache", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  res <- native_cmd(
    "config",
    c("list", "pkgs_dirs", "--sources"),
    verbose = "silent"
  )
  root_pkgs <- as.character(fs::path(
    install_dir_for_backend(micromamba_backend()),
    "pkgs"
  ))
  out <- parse_output(res)
  listed <- trimws(sub(
    "#.*$",
    "",
    sub("^\\s*-\\s*", "", out[grepl("^\\s*-", out)])
  ))
  testthat::expect_identical(fs::path_norm(listed), fs::path_norm(root_pkgs))
})

testthat::test_that("get_clean_conda_envvars includes all 20 env vars", {
  result <- get_clean_conda_envvars(tmp_dir = "/tmp/test")
  expected_names <- c(
    "TMPDIR",
    "CONDA_SHLVL",
    "MAMBA_SHLVL",
    "CONDA_ENVS_PATH",
    "CONDA_ENVS_DIRS",
    "CONDA_ROOT_PREFIX",
    "CONDA_PREFIX",
    "MAMBA_ENVS_PATH",
    "MAMBA_ENVS_DIRS",
    "MAMBA_ROOT_PREFIX",
    "MAMBA_PREFIX",
    "CONDARC",
    "MAMBARC",
    "CONDA_PROMPT_MODIFIER",
    "MAMBA_PROMPT_MODIFIER",
    "CONDA_DEFAULT_ENV",
    "MAMBA_DEFAULT_ENV",
    "CONDA_PKGS_DIRS",
    "MAMBA_PKGS_DIRS",
    "R_HOME"
  )
  testthat::expect_named(result, expected_names)
})

testthat::test_that("CONDA_ENVS_DIRS is set to NULL (unset behavior)", {
  result <- get_clean_conda_envvars(tmp_dir = "/tmp/test")
  testthat::expect_null(result$CONDA_ENVS_DIRS)
})
