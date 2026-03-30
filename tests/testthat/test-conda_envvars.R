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

testthat::test_that("get_clean_conda_envvars sets envs_dir when provided", {
  result <- get_clean_conda_envvars(
    tmp_dir = "/tmp/test",
    envs_dir = "/my/envs"
  )
  testthat::expect_equal(result$CONDA_ENVS_PATH, "/my/envs")
})

testthat::test_that("get_clean_conda_envvars defaults envs_dir to empty string", {
  result <- get_clean_conda_envvars(tmp_dir = "/tmp/test")
  testthat::expect_equal(result$CONDA_ENVS_PATH, "")
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
  testthat::expect_equal(names(result), expected_names)
})

testthat::test_that("CONDA_ENVS_DIRS is set to NULL (unset behavior)", {
  result <- get_clean_conda_envvars(tmp_dir = "/tmp/test")
  testthat::expect_null(result$CONDA_ENVS_DIRS)
})
