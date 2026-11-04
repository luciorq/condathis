testthat::test_that("%||% is imported from rlang", {
  # Regression test: `%||%` is used in many places but was neither defined
  # nor imported. Base R has it only from 4.4.0, and DESCRIPTION declares
  # R (>= 4.3), so those code paths failed on R 4.3 with
  # 'could not find function "%||%"'.
  imports <- getNamespaceImports("condathis")
  rlang_imports <- unlist(imports[names(imports) == "rlang"], use.names = FALSE)
  testthat::expect_true(
    isTRUE(rlang_imports) || "%||%" %in% rlang_imports
  )
  imports_env <- parent.env(asNamespace("condathis"))
  testthat::expect_true(exists("%||%", envir = imports_env, inherits = FALSE))
  testthat::expect_identical(
    get("%||%", envir = imports_env, inherits = FALSE),
    rlang::`%||%`
  )
})
