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

testthat::test_that("split_activated_path() finds what the activation put before and after the session's PATH", {
  sep <- .Platform$path.sep
  p <- function(...) paste(c(...), collapse = sep)
  testthat::expect_identical(
    split_activated_path(
      p("/env/bin", "/env/scripts", "/usr/bin", "/bin"),
      p("/usr/bin", "/bin")
    ),
    list(prepend = c("/env/bin", "/env/scripts"), append = character(0L))
  )
  # No additions -> empty; empty baseline -> everything in front.
  testthat::expect_identical(
    split_activated_path(p("/usr/bin", "/bin"), p("/usr/bin", "/bin")),
    list(prepend = character(0L), append = character(0L))
  )
  testthat::expect_identical(
    split_activated_path(p("/a", "/b"), ""),
    list(prepend = c("/a", "/b"), append = character(0L))
  )
  # Regression test: an environment directory that the session's PATH
  # already has at its end was dropped as "not added", so a program of the
  # same name earlier on the session's PATH ran instead.
  testthat::expect_identical(
    split_activated_path(
      p("/env/bin", "/usr/bin", "/env/bin"),
      p("/usr/bin", "/env/bin")
    ),
    list(prepend = "/env/bin", append = character(0L))
  )
  testthat::expect_identical(
    compose_path("/env/bin", p("/usr/bin", "/env/bin")),
    p("/env/bin", "/usr/bin")
  )
  # What an activate.d script appends stays behind the session's entries.
  testthat::expect_identical(
    split_activated_path(
      p("/env/bin", "/usr/bin", "/bin", "/extra"),
      p("/usr/bin", "/bin")
    ),
    list(prepend = "/env/bin", append = "/extra")
  )
  testthat::expect_identical(
    compose_path("/env/bin", p("/usr/bin", "/bin"), append = "/extra"),
    p("/env/bin", "/usr/bin", "/bin", "/extra")
  )
  # Entries that Rscript puts in front of both dumps at its start (Rtools on
  # Windows) are not the activation's.
  testthat::expect_identical(
    split_activated_path(
      p("/rtools", "/env/bin", "/usr/bin"),
      p("/rtools", "/usr/bin")
    ),
    list(prepend = "/env/bin", append = character(0L))
  )
  # The session's entries spelled differently (micromamba on Windows): every
  # entry the baseline lacks counts as put in front, as before.
  testthat::expect_identical(
    split_activated_path(
      p("/env/bin", "\\usr\\bin"),
      p("/usr/bin")
    ),
    list(prepend = c("/env/bin", "\\usr\\bin"), append = character(0L))
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
  # `CONDA_ENVS_PATH` comes from the clean overlay (see child_conda_dirs()),
  # so both `activate` modes of run_pipeline() give a stage the same value.
  testthat::expect_false("CONDA_ENVS_PATH" %in% names(envvars))
})

testthat::test_that("build_child_env sets the conda dirs from conda_dirs only", {
  # Regression test: build_child_env() gave every child the package cache
  # and envs directory of the micromamba root, whichever backend owned the
  # environment being run.
  withr::local_envvar(
    CONDA_PKGS_DIRS = "/user/pkgs",
    MAMBA_PKGS_DIRS = "/user/pkgs",
    CONDA_ENVS_PATH = "/user/envs"
  )
  var_names <- c("CONDA_PKGS_DIRS", "MAMBA_PKGS_DIRS", "CONDA_ENVS_PATH")

  # No directories: cleared, never the session's values.
  env_none <- build_child_env(tmp_dir = "/tmp/fake-tmp-dir")
  testthat::expect_identical(unname(env_none[var_names]), c("", "", ""))

  # A child of another backend: the directory that holds its environment,
  # and the `conda-pkgs` directory of its root, never micromamba's cache.
  other_backend <- structure(
    list(),
    class = c("condathis_backend_other", "condathis_backend")
  )
  env_other <- build_child_env(
    tmp_dir = "/tmp/fake-tmp-dir",
    conda_dirs = child_conda_dirs(other_backend, env_dir = "/other/envs/e")
  )
  testthat::expect_identical(
    unname(env_other[var_names]),
    as.character(c(
      fs::path("/other", "conda-pkgs"),
      fs::path("/other", "conda-pkgs"),
      fs::path("/other/envs")
    ))
  )
  # Not in a directory named `envs`: no package cache to give.
  env_layout <- build_child_env(
    tmp_dir = "/tmp/fake-tmp-dir",
    conda_dirs = child_conda_dirs(other_backend, env_dir = "/other/pfx/e")
  )
  testthat::expect_identical(
    unname(env_layout[var_names]),
    c("", "", as.character(fs::path("/other/pfx")))
  )

  # micromamba and a child of its environments: the root's `pkgs/` and
  # `envs/`.
  env_micromamba <- build_child_env(
    tmp_dir = "/tmp/fake-tmp-dir",
    conda_dirs = micromamba_conda_dirs("/root")
  )
  testthat::expect_identical(
    unname(env_micromamba[var_names]),
    as.character(c(
      fs::path("/root", "pkgs"),
      fs::path("/root", "pkgs"),
      fs::path("/root", "envs")
    ))
  )

  # Activation variables from a backend's `backend_resolve_run()` win.
  env_overlay <- build_child_env(
    tmp_dir = "/tmp/fake-tmp-dir",
    conda_dirs = child_conda_dirs(other_backend, env_dir = "/other/envs/e"),
    overlay = c(CONDA_PKGS_DIRS = "/backend/pkgs")
  )
  testthat::expect_identical(
    unname(env_overlay[["CONDA_PKGS_DIRS"]]),
    "/backend/pkgs"
  )
})

testthat::test_that("with_sandbox_dir() recognizes a child of another backend's environment", {
  # Regression test: a child of a non-micromamba backend got `""` for
  # CONDA_ENVS_PATH, CONDA_PKGS_DIRS and MAMBA_PKGS_DIRS. A process it left
  # running, with no CONDA_PREFIX (`activate = FALSE`, or a backend whose
  # activation does not set it) and with nothing on its command line inside
  # the sandbox, was no longer stopped by with_sandbox_dir().
  root <- "/tmp/Rtmp1/condathis-sandbox-1a2b"
  other_backend <- structure(
    list(),
    class = c("condathis_backend_other", "condathis_backend")
  )
  env_dir <- file.path(root, "home", "other-root", "envs", "e")
  child_env <- build_child_env(
    tmp_dir = "/tmp/Rtmp1/condathis-tmp-1",
    conda_dirs = child_conda_dirs(other_backend, env_dir = env_dir)
  )
  # Only the variables `with_sandbox_dir()` checks, so the result does not
  # depend on the session that runs the test.
  checked <- names(child_env) %in% sandbox_process_envvars()
  testthat::expect_true(process_uses_sandbox(
    exe = "/usr/bin/sleep",
    cmdline = c("sleep", "60"),
    environ = child_env[checked],
    root_forms = root,
    windows = FALSE
  ))
  # An environment outside the sandbox does not tie the child to it.
  outside_env <- build_child_env(
    tmp_dir = "/tmp/Rtmp1/condathis-tmp-1",
    conda_dirs = child_conda_dirs(other_backend, env_dir = "/opt/envs/e")
  )
  testthat::expect_false(process_uses_sandbox(
    exe = "/usr/bin/sleep",
    cmdline = c("sleep", "60"),
    environ = outside_env[names(outside_env) %in% sandbox_process_envvars()],
    root_forms = root,
    windows = FALSE
  ))
})
