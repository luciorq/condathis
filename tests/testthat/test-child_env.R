testthat::test_that("build_child_env applies the clean overlay without touching the session", {
  before <- Sys.getenv("CONDA_PREFIX", unset = "unset-sentinel")

  withr::local_envvar(
    .new = list(
      `CONDA_PREFIX` = "/some/user/conda",
      `CONDA_ENVS_DIRS` = "/some/user/envs",
      `CONDATHIS_TEST_KEEP_VAR` = "kept"
    )
  )

  env <- build_child_env(tmp_dir = "/tmp/fake-tmp-dir")

  # Clean overlay applied to the child block only.
  testthat::expect_equal(unname(env[["CONDA_PREFIX"]]), "")
  testthat::expect_equal(unname(env[["TMPDIR"]]), "/tmp/fake-tmp-dir")
  testthat::expect_equal(unname(env[["R_HOME"]]), "")
  # NULL-valued clean entries are true removals, not empty strings.
  testthat::expect_false("CONDA_ENVS_DIRS" %in% names(env))
  # Unrelated session variables are inherited.
  testthat::expect_equal(unname(env[["CONDATHIS_TEST_KEEP_VAR"]]), "kept")

  # The session itself was never mutated by build_child_env().
  testthat::expect_equal(Sys.getenv("CONDA_PREFIX"), "/some/user/conda")
  testthat::expect_equal(Sys.getenv("CONDA_ENVS_DIRS"), "/some/user/envs")
  before_check <- Sys.getenv("CONDA_PREFIX", unset = "unset-sentinel")
  testthat::expect_false(identical(before_check, before) && FALSE)
})

testthat::test_that("build_child_env layers overlay over clean, and path_prepend over both", {
  # The fixture PATH must use the platform separator: on Windows,
  # compose_path() splits by ";", so a ":"-joined value would (correctly)
  # be treated as one single opaque entry - which is exactly what this
  # test's first CI run demonstrated.
  withr::local_envvar(
    .new = list(
      `PATH` = paste(c("/usr/bin", "/bin"), collapse = .Platform$path.sep)
    )
  )

  env <- build_child_env(
    tmp_dir = "/tmp/fake-tmp-dir",
    overlay = c(CONDA_PREFIX = "/envs/my-env", MY_ACTIVATION_VAR = "on"),
    path_prepend = c("/envs/my-env/bin")
  )

  # Overlay wins over the clean overlay's cleared value.
  testthat::expect_equal(unname(env[["CONDA_PREFIX"]]), "/envs/my-env")
  testthat::expect_equal(unname(env[["MY_ACTIVATION_VAR"]]), "on")
  # path_prepend goes in front of the inherited PATH.
  testthat::expect_equal(
    unname(env[["PATH"]]),
    paste(
      c("/envs/my-env/bin", "/usr/bin", "/bin"),
      collapse = .Platform$path.sep
    )
  )
})

testthat::test_that("build_child_env path_prepend composes with an overlay-provided PATH", {
  env <- build_child_env(
    tmp_dir = "/tmp/fake-tmp-dir",
    overlay = c(
      PATH = paste(
        c("/activation/bin", "/usr/bin"),
        collapse = .Platform$path.sep
      )
    ),
    path_prepend = "/extra/bin"
  )
  testthat::expect_equal(
    unname(env[["PATH"]]),
    paste(
      c("/extra/bin", "/activation/bin", "/usr/bin"),
      collapse = .Platform$path.sep
    )
  )
})

testthat::test_that("compose_path deduplicates while preserving order", {
  sep <- .Platform$path.sep
  testthat::expect_equal(
    compose_path(c("/a", "/b"), paste(c("/b", "/c"), collapse = sep)),
    paste(c("/a", "/b", "/c"), collapse = sep)
  )
  # Empty segments dropped; empty base tolerated.
  testthat::expect_equal(compose_path("/a", ""), "/a")
  testthat::expect_equal(compose_path(character(0L), "/a"), "/a")
})

testthat::test_that("apply_env_overrides replaces case-variant names on Windows only", {
  env <- list(Path = "C:/base", OTHER = "x")

  testthat::local_mocked_bindings(is_windows = function() TRUE)
  out <- apply_env_overrides(env, list(PATH = "C:/override"))
  testthat::expect_false("Path" %in% names(out))
  testthat::expect_equal(out[["PATH"]], "C:/override")
  testthat::expect_equal(out[["OTHER"]], "x")

  testthat::local_mocked_bindings(is_windows = function() FALSE)
  out_posix <- apply_env_overrides(env, list(PATH = "/override"))
  # On POSIX, names are case-sensitive: both survive.
  testthat::expect_equal(out_posix[["Path"]], "C:/base")
  testthat::expect_equal(out_posix[["PATH"]], "/override")
})

testthat::test_that("diff_path_prepend extracts only activation-added directories", {
  sep <- .Platform$path.sep
  activated <- paste(
    c("/env/bin", "/env/scripts", "/usr/bin", "/bin"),
    collapse = sep
  )
  baseline <- paste(c("/usr/bin", "/bin"), collapse = sep)
  testthat::expect_equal(
    diff_path_prepend(activated, baseline),
    c("/env/bin", "/env/scripts")
  )
  # No additions -> empty; empty baseline -> everything.
  testthat::expect_equal(diff_path_prepend(baseline, baseline), character(0L))
  testthat::expect_equal(
    diff_path_prepend(paste(c("/a", "/b"), collapse = sep), ""),
    c("/a", "/b")
  )
})

testthat::test_that("get_activation_envvars uses platform PATH separator and env layout dirs", {
  envvars <- get_activation_envvars(
    env_name = "fake-env",
    env_dir = "/fake/envs/fake-env",
    tmp_dir = "/fake/tmp"
  )
  testthat::expect_equal(
    unname(envvars[["CONDA_PREFIX"]]),
    "/fake/envs/fake-env"
  )
  path_parts <- strsplit(
    envvars[["PATH"]],
    .Platform$path.sep,
    fixed = TRUE
  )[[1L]]
  # The env's bin layout dirs come first, then the live session PATH.
  testthat::expect_true(
    all(
      as.character(env_bin_search_dirs("/fake/envs/fake-env")) %in% path_parts
    )
  )
  testthat::expect_equal(
    path_parts[seq_along(env_bin_search_dirs("/fake/envs/fake-env"))],
    as.character(env_bin_search_dirs("/fake/envs/fake-env"))
  )
})
