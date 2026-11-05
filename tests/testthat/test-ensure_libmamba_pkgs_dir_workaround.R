testthat::test_that("needs_libmamba_pkgs_dir_workaround gates on the 2.0.4 fix", {
  testthat::expect_true(needs_libmamba_pkgs_dir_workaround("2.0.0"))
  testthat::expect_true(needs_libmamba_pkgs_dir_workaround("2.0.2"))
  testthat::expect_false(needs_libmamba_pkgs_dir_workaround("2.0.4"))
  testthat::expect_false(needs_libmamba_pkgs_dir_workaround("2.3.1"))
  testthat::expect_false(needs_libmamba_pkgs_dir_workaround("2.8.1"))
  testthat::expect_false(needs_libmamba_pkgs_dir_workaround("2.9.0"))
  # A two-digit minor version compares as a number, not as text.
  testthat::expect_false(needs_libmamba_pkgs_dir_workaround("2.10.0"))
})

testthat::test_that("needs_libmamba_pkgs_dir_workaround does no I/O when the minimum version has the fix", {
  # Regression test: the gate looked up the micromamba binary and ran an
  # extra `micromamba --version` on every create_env() call, although
  # discovery accepts only micromamba >= micromamba_minimum_version, which
  # already has the fix. Comparing the two constants must decide it.
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function() {
      cli::cli_abort("the binary lookup must not run")
    },
    get_micromamba_version = function(...) {
      cli::cli_abort("micromamba --version must not run")
    }
  )
  testthat::expect_false(needs_libmamba_pkgs_dir_workaround())
  testthat::expect_false(
    needs_libmamba_pkgs_dir_workaround(minimum_version = "2.0.4")
  )
  # The default floor is the package minimum, which has the fix.
  testthat::expect_true(
    utils::compareVersion(
      micromamba_minimum_version,
      libmamba_pkgs_dir_workaround_fixed_version
    ) >=
      0L
  )
})

testthat::test_that("needs_libmamba_pkgs_dir_workaround resolves the version from the discovered binary", {
  # Only reachable when the minimum version is below the fix.
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function() fs::path("/mock/micromamba"),
    get_micromamba_version = function(...) "2.0.2"
  )
  testthat::expect_true(
    needs_libmamba_pkgs_dir_workaround(minimum_version = "2.0.0")
  )

  testthat::local_mocked_bindings(
    get_micromamba_version = function(...) "2.8.1"
  )
  testthat::expect_false(
    needs_libmamba_pkgs_dir_workaround(minimum_version = "2.0.0")
  )
})

testthat::test_that("needs_libmamba_pkgs_dir_workaround is FALSE with no binary or unreadable version", {
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function() NULL
  )
  testthat::expect_false(
    needs_libmamba_pkgs_dir_workaround(minimum_version = "2.0.0")
  )

  testthat::local_mocked_bindings(
    get_best_micromamba_path = function() fs::path("/mock/micromamba"),
    get_micromamba_version = function(...) {
      cli::cli_abort("boom", class = "condathis_umamba_version_not_detected")
    }
  )
  testthat::expect_false(
    needs_libmamba_pkgs_dir_workaround(minimum_version = "2.0.0")
  )
})

testthat::test_that("workaround touches nothing for micromamba >= 2.0.4", {
  condathis::with_sandbox_dir({
    pkgs_dir <- libmamba_default_pkgs_dir()
    mamba_dir <- fs::path_dir(pkgs_dir)
    for (version in c("2.0.4", "2.3.1", "2.8.1", "2.9.0", "2.10.0")) {
      local({
        ensure_libmamba_pkgs_dir_workaround(umamba_version = version)
        testthat::expect_false(fs::dir_exists(pkgs_dir), info = version)
      })
    }
    testthat::expect_false(fs::dir_exists(mamba_dir))
  })
})

testthat::test_that("workaround creates and then removes both dirs when neither existed", {
  condathis::with_sandbox_dir({
    pkgs_dir <- libmamba_default_pkgs_dir()
    mamba_dir <- fs::path_dir(pkgs_dir)
    testthat::expect_false(fs::dir_exists(mamba_dir))
    local({
      ensure_libmamba_pkgs_dir_workaround(umamba_version = "2.0.2")
      testthat::expect_true(fs::dir_exists(pkgs_dir))
    })
    testthat::expect_false(fs::dir_exists(pkgs_dir))
    testthat::expect_false(fs::dir_exists(mamba_dir))
  })
})

testthat::test_that("workaround preserves a pre-existing .mamba dir and only removes pkgs", {
  condathis::with_sandbox_dir({
    pkgs_dir <- libmamba_default_pkgs_dir()
    mamba_dir <- fs::path_dir(pkgs_dir)
    keep_file <- fs::path(mamba_dir, "keep.txt")
    fs::dir_create(mamba_dir)
    fs::file_create(keep_file)
    local({
      ensure_libmamba_pkgs_dir_workaround(umamba_version = "2.0.2")
      testthat::expect_true(fs::dir_exists(pkgs_dir))
      # Something libmamba might write into the cache dir we created.
      fs::file_create(fs::path(pkgs_dir, "urls.txt"))
    })
    testthat::expect_false(fs::dir_exists(pkgs_dir))
    testthat::expect_true(fs::dir_exists(mamba_dir))
    testthat::expect_true(fs::file_exists(keep_file))
  })
})

testthat::test_that("workaround leaves a pre-existing pkgs dir untouched", {
  condathis::with_sandbox_dir({
    pkgs_dir <- libmamba_default_pkgs_dir()
    marker <- fs::path(pkgs_dir, "cached-package.tar.bz2")
    fs::dir_create(pkgs_dir)
    fs::file_create(marker)
    local({
      ensure_libmamba_pkgs_dir_workaround(umamba_version = "2.0.2")
    })
    testthat::expect_true(fs::dir_exists(pkgs_dir))
    testthat::expect_true(fs::file_exists(marker))
  })
})

testthat::test_that("workaround cleanup fires when the envir frame exits, not when the helper returns", {
  condathis::with_sandbox_dir({
    pkgs_dir <- libmamba_default_pkgs_dir()
    caller <- function() {
      ensure_libmamba_pkgs_dir_workaround(
        envir = environment(),
        umamba_version = "2.0.2"
      )
      # Still present after the helper has returned: the cleanup is tied to
      # this frame (the `envir` argument), not to the helper's own frame.
      isTRUE(fs::dir_exists(pkgs_dir))
    }
    testthat::expect_true(caller())
    testthat::expect_false(fs::dir_exists(pkgs_dir))
  })
})
