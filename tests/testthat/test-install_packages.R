testthat::test_that("install_packages warns when previous channels are dropped", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  # `fastqc` is only published on `bioconda` for `linux-64`/`osx-64`/
  # `noarch` (confirmed against bioconda's own repodata: no `win-64` build
  # at all, and the `noarch` build's own dependencies, e.g. `openjdk`,
  # `font-ttf-dejavu-sans-mono`, are themselves unavailable for `win-64`/
  # `osx-arm64`) — bioconda has never supported Windows and does not ship
  # native Apple Silicon builds, so this environment cannot solve on
  # Windows or on modern (arm64) macOS runners regardless of anything
  # `condathis` does. See the cross-platform equivalent below, which
  # exercises the same warning logic with `conda-forge`-only channels.
  testthat::skip_if_not(
    tolower(Sys.info()[["sysname"]]) == "linux",
    "This test requires Linux"
  )

  condathis::with_sandbox_dir({
    px_res <- create_env(
      packages = "python=3.11",
      env_name = "condathis-channel-warn-env",
      channels = "conda-forge",
      verbose = "silent"
    )
    testthat::expect_equal(px_res$status, 0L)

    testthat::expect_warning(
      object = {
        install_res <- install_packages(
          packages = "fastqc",
          env_name = "condathis-channel-warn-env",
          channels = "bioconda",
          verbose = "silent"
        )
      },
      class = "condathis_install_missing_previous_channels"
    )
    testthat::expect_s3_class(install_res, "condathis_result")
    testthat::expect_equal(install_res$status, 0L)

    # No warning when the previously used channel is included again.
    testthat::expect_no_warning(
      object = {
        install_packages(
          packages = "fastqc",
          env_name = "condathis-channel-warn-env",
          channels = c("conda-forge", "bioconda"),
          verbose = "silent"
        )
      },
      class = "condathis_install_missing_previous_channels"
    )

    remove_env(env_name = "condathis-channel-warn-env", verbose = "silent")
  })
})

testthat::test_that("install_packages warns when previous channels are dropped (cross-platform)", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # Same channel-history-diff logic as the Linux-only test above, but using
  # only `conda-forge` (and one of its own labels), which resolves
  # identically on Linux, macOS (Intel and Apple Silicon), and Windows.
  condathis::with_sandbox_dir({
    px_res <- create_env(
      packages = "zlib",
      env_name = "condathis-channel-warn-env-cf",
      channels = "conda-forge",
      verbose = "silent"
    )
    testthat::expect_equal(px_res$status, 0L)

    # Record a second "previously used" channel directly in the
    # environment's history, rather than relying on a real install
    # actually resolving from it. `conda-forge/label/main` hosts the same
    # packages as plain `conda-forge`, so which one a real solve records
    # for a trivially-available package like `zlib` is solver
    # tie-breaking, not something this test controls — confirmed flaky
    # (~1 in 3 runs) when this relied on that instead. Writing the history
    # line directly makes the "previously used channel" set deterministic;
    # `get_env_history_channels()`'s own parsing of exactly this line
    # format is separately unit-tested in
    # test-get_env_history_channels.R.
    history_file <- fs::path(
      get_env_dir("condathis-channel-warn-env-cf"),
      "conda-meta",
      "history"
    )
    cat(
      "+https://conda.anaconda.org/conda-forge/label/main/noarch::condathis-flake-fix-fake-pkg-1.0-0\n",
      file = history_file,
      append = TRUE
    )

    testthat::expect_warning(
      object = {
        install_res <- install_packages(
          packages = "xz",
          env_name = "condathis-channel-warn-env-cf",
          channels = "conda-forge",
          verbose = "silent"
        )
      },
      class = "condathis_install_missing_previous_channels"
    )
    testthat::expect_s3_class(install_res, "condathis_result")
    testthat::expect_equal(install_res$status, 0L)

    # No warning when the previously used channel is included again.
    testthat::expect_no_warning(
      object = {
        install_packages(
          packages = "xz",
          env_name = "condathis-channel-warn-env-cf",
          channels = c("conda-forge", "conda-forge/label/main"),
          verbose = "silent"
        )
      },
      class = "condathis_install_missing_previous_channels"
    )

    remove_env(env_name = "condathis-channel-warn-env-cf", verbose = "silent")
  })
})
