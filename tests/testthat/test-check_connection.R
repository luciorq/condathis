test_that("GitHub is reachable", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  testthat::skip_on_ci()

  github_url <- "https://github.com"
  con_res <- check_connection(url_to_check = github_url)

  testthat::expect_true(con_res)
})

# test_that("conda-forge is reachable", {
#   testthat::skip_if_offline()
#   testthat::skip_on_ci()
#   testthat::skip_on_cran()
#
#
#   # TODO: @luciorq Add mirrors to conda-forge
#   # + check GitHub OCI mirror: <https://github.com/orgs/channel-mirrors/packages>
#   # + Prefix Dev mirror: <https://prefix.dev/blog/towards_a_vendor_lock_in_free_conda_experience>
#
#   # conda_forge_url <- "https://conda.anaconda.org/conda-forge"
#   # con_res <- check_connection(url_to_check = conda_forge_url)
#
#   # testthat::expect_true(con_res)
# })
