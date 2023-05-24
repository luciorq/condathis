test_that("conda env is created in docker", {

  if ("condathis-micromamba-base" %in% dockerthis::docker_list_containers()) {
    dockerthis::docker_remove_container("condathis-micromamba-base")
  }
  px_res <- create_env(
    packages = c(
      "samtools"
    ),
    env_name = "condathis-docker-test-env",
    method = "docker"
  )
  expect_equal(px_res$status, 0)

  # run_res <- run("R", "-q" ,"--version", env_name = "condathis-test-env")

  # expect_equal(run_res$status, 0)
#
#   expect_equal(
#     stringr::str_detect(run_res$stdout, "R version 4.1.3"),
#     TRUE
#   )
#   px_res <- install_packages(
#     packages = c("python=3.8.16"),
#     env_name = "condathis-test-env"
#   )
#   expect_equal(px_res$status, 0)
#
#   inst_res <- run("python", "--version", env_name = "condathis-test-env")
#
#   expect_equal(inst_res$status, 0)
#
#   expect_equal(
#     stringr::str_detect(inst_res$stdout, "Python 3.8.16"),
#     TRUE
#   )
})
