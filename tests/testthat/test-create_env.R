test_that("conda env is created", {
  px_res <- create_env(
    packages = c("r-base=4.1.3", "r-devtools"),
    env_name = "condathis-test-env"
  )
  expect_equal(px_res, 0)
})

test_that("CLI run inside environment", {
  run_res <- run("R", "--version", env_name = "condathis-test-env")

  expect_equal(run_res$status, 0)

  expect_equal(
    stringr::str_detect(run_res$stdout, "R version 4.1.3"),
    TRUE
  )
})
