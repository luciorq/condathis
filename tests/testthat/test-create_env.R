test_that("conda env is created", {
  px_res <- create_env(
    packages = c("r-base=4.1.3", "r-devtools"),
    env_name = "condathis-test-env"
  )
  expect_equal(px_res$status, 0)

  run_res <- run("R", "-q" ,"--version", env_name = "condathis-test-env")

  expect_equal(run_res$status, 0)

  expect_equal(
    stringr::str_detect(run_res$stdout, "R version 4.1.3"),
    TRUE
  )
  px_res <- install_packages(
    packages = c("python=3.8.16"),
    env_name = "condathis-test-env"
  )
  expect_equal(px_res$status, 0)

  inst_res <- run("python", "--version", env_name = "condathis-test-env")

  expect_equal(inst_res$status, 0)

  expect_equal(
    stringr::str_detect(inst_res$stdout, "Python 3.8.16"),
    TRUE
  )
})

test_that("Create conda env from file", {
  px_res <- create_env(
    env_file = fs::path_package("condathis", "extdata", "stat-env.yml"),
    method = "native",
    env_name = "condathis-test-env"
  )

  expect_equal(px_res$status, 0)
})

# fs::dir_delete(fs::path(get_install_dir(), "envs", "condathis-test-env"))
