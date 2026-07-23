testthat::test_that("with_sandbox_dir isolates HOME and XDG directories from the ambient session", {
  outer_home <- Sys.getenv("HOME")
  outer_xdg_data <- Sys.getenv("XDG_DATA_HOME")
  outer_xdg_cache <- Sys.getenv("XDG_CACHE_HOME")

  wrapper_fn <- function() {
    with_sandbox_dir({
      testthat::expect_false(identical(Sys.getenv("HOME"), outer_home))
      testthat::expect_false(identical(
        Sys.getenv("XDG_DATA_HOME"),
        outer_xdg_data
      ))
      testthat::expect_false(identical(
        Sys.getenv("XDG_CACHE_HOME"),
        outer_xdg_cache
      ))
      testthat::expect_equal(Sys.getenv("USERPROFILE"), Sys.getenv("HOME"))
      testthat::expect_equal(
        Sys.getenv("LOCALAPPDATA"),
        Sys.getenv("XDG_DATA_HOME")
      )
      testthat::expect_equal(Sys.getenv("APPDATA"), Sys.getenv("XDG_DATA_HOME"))
      testthat::expect_equal(
        Sys.getenv("R_USER_DATA_DIR"),
        Sys.getenv("XDG_DATA_HOME")
      )
      testthat::expect_equal(
        Sys.getenv("R_USER_CACHE_DIR"),
        Sys.getenv("XDG_CACHE_HOME")
      )
    })
  }
  wrapper_fn()
})

testthat::test_that("with_sandbox_dir creates real, existing directories", {
  wrapper_fn <- function() {
    with_sandbox_dir({
      testthat::expect_true(fs::dir_exists(Sys.getenv("HOME")))
      testthat::expect_true(fs::dir_exists(Sys.getenv("XDG_DATA_HOME")))
      testthat::expect_true(fs::dir_exists(Sys.getenv("XDG_CACHE_HOME")))
    })
  }
  wrapper_fn()
})

testthat::test_that("with_sandbox_dir's override outlives the code block but not its calling frame", {
  outer_home <- Sys.getenv("HOME")

  wrapper_fn <- function() {
    sandboxed_home <- NULL
    with_sandbox_dir({
      sandboxed_home <- Sys.getenv("HOME")
    })
    # The override is scoped to `.local_envir` (this function's frame, by
    # default), not to the `{ ... }` block itself, so it is still active
    # here, after with_sandbox_dir() has already returned.
    testthat::expect_equal(Sys.getenv("HOME"), sandboxed_home)
    testthat::expect_false(identical(Sys.getenv("HOME"), outer_home))
  }
  wrapper_fn()

  # Restored once the calling frame (wrapper_fn) has exited.
  testthat::expect_equal(Sys.getenv("HOME"), outer_home)
})

testthat::test_that("with_sandbox_dir gives each call a fresh, unique sandbox", {
  wrapper_fn <- function() {
    home_1 <- NULL
    with_sandbox_dir({
      home_1 <- Sys.getenv("HOME")
    })
    home_2 <- NULL
    with_sandbox_dir({
      home_2 <- Sys.getenv("HOME")
    })
    testthat::expect_false(identical(home_1, home_2))
  }
  wrapper_fn()
})

testthat::test_that("with_sandbox_dir returns NULL invisibly", {
  wrapper_fn <- function() with_sandbox_dir(NULL)
  testthat::expect_invisible(wrapper_fn())
  testthat::expect_null(wrapper_fn())
})
