testthat::test_that("install_packages warns when previous channels are dropped", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

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
