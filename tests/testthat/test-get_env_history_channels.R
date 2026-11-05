testthat::test_that("get_env_history_channels returns empty for missing history", {
  condathis::with_sandbox_dir({
    testthat::expect_equal(
      get_env_history_channels(env_name = "no-such-env"),
      character(0L)
    )
  })
})

testthat::test_that("get_env_history_channels parses channels from history file", {
  condathis::with_sandbox_dir({
    history_dir <- fs::path(get_env_dir("hist-env"), "conda-meta")
    fs::dir_create(history_dir, recurse = TRUE)
    writeLines(
      c(
        "==> 2026-01-01 00:00:00 <==",
        "# cmd: micromamba create -n hist-env -c conda-forge python",
        "# conda version: 3.8.0",
        "+https://conda.anaconda.org/conda-forge/linux-64::python-3.11.0-0",
        "# update specs: [\"python\"]",
        "==> 2026-01-02 00:00:00 <==",
        "# cmd: micromamba install -n hist-env -c bioconda fastqc",
        "# conda version: 3.8.0",
        "+https://conda.anaconda.org/bioconda/linux-64::fastqc-0.11.5-1",
        "# update specs: [\"fastqc\"]"
      ),
      con = fs::path(history_dir, "history")
    )

    channels <- get_env_history_channels(env_name = "hist-env")
    testthat::expect_setequal(channels, c("conda-forge", "bioconda"))
  })
})
