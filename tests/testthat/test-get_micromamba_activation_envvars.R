test_that("get_micromamba_activation_envvars() resolves real activation vars", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()

  create_env(verbose = "silent")
  reset_micromamba_activation_cache("condathis-env")

  envvars <- get_micromamba_activation_envvars("condathis-env")

  testthat::expect_true(is.character(envvars))
  testthat::expect_true(!is.null(names(envvars)))
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
  testthat::expect_error(
    object = get_micromamba_activation_envvars("no-such-env-xyz"),
    class = "condathis_activation_env_not_found"
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
  # on macOS/Windows). wait()-then-read blocks forever in that case — `env`
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
