testthat::test_that("satisfies_dependencies returns null for null input", {
  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = character(0),
    env_name = "numpy-test-env"
  )
  testthat::expect_equal(is_satisfied_vector, logical(0))
})

testthat::test_that("satisfies_dependencies returns correct results", {
  if (env_exists("numpy-test-env")) {
    remove_env("numpy-test-env", verbose = "silent")
  }

  pkg_str_vector_test <- c("python", "conda-forge::numpy>=1.8,<2|1.9")

  create_env(
    packages = pkg_str_vector_test,
    env_name = "numpy-test-env",
    verbose = "silent",
    overwrite = FALSE
  )

  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = pkg_str_vector_test,
    env_name = "numpy-test-env"
  )

  testthat::expect_length(is_satisfied_vector, length(pkg_str_vector_test))

  testthat::expect_type(is_satisfied_vector, "logical")
  # is not an S3 class object
  testthat::expect_s3_class(is_satisfied_vector, NA)

  testthat::expect_true(all(is_satisfied_vector))

  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = c(
      pkg_str_vector_test,
      "conda-forge::pandas==1.8.1"
    ),
    env_name = "numpy-test-env"
  )

  testthat::expect_length(is_satisfied_vector, length(pkg_str_vector_test) + 1L)

  testthat::expect_false(is_satisfied_vector[length(is_satisfied_vector)])

  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = "PYTHON",
    env_name = "numpy-test-env"
  )

  testthat::expect_length(is_satisfied_vector, 1L)
  testthat::expect_false(is_satisfied_vector)
})
