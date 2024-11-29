test_that("env_exists missing env_name", {
  expect_error(env_exists())
  expect_equal(env_exists(NULL), FALSE)
  expect_equal(env_exists(NA), FALSE)
})
