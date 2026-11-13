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

testthat::test_that("path_entry_key() compares as Windows does on Windows only", {
  x <- c("C:/Env/Scripts", "c:\\env\\scripts", "/usr/bin")
  testthat::expect_identical(path_entry_key(x, on_windows = FALSE), x)
  testthat::expect_identical(
    path_entry_key(x, on_windows = TRUE),
    c("c:\\env\\scripts", "c:\\env\\scripts", "\\usr\\bin")
  )
  testthat::expect_identical(
    path_entry_key(character(0L), on_windows = TRUE),
    character(0L)
  )
  # The default follows `is_windows()`.
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  testthat::expect_identical(path_entry_key("/A/b"), "\\a\\b")
})

testthat::test_that("path_entry_key() ignores a trailing separator on Windows only", {
  # A directory with and without a trailing separator is the same one.
  testthat::expect_identical(
    path_entry_key(
      c("C:\\x\\", "C:\\x", "c:/X/", "C:\\x\\\\", "\\\\srv\\share\\"),
      on_windows = TRUE
    ),
    c("c:\\x", "c:\\x", "c:\\x", "c:\\x", "\\\\srv\\share")
  )
  # A drive root keeps its separator: `C:\` is not `C:`, the current
  # directory of drive C:. Nor does the root of the current drive become
  # an empty entry.
  testthat::expect_identical(
    path_entry_key(c("C:\\", "C:/", "c:\\\\", "C:", "\\", "/"), on_windows = TRUE),
    c("c:\\", "c:\\", "c:\\", "c:", "\\", "\\")
  )
  testthat::expect_identical(path_entry_key("", on_windows = TRUE), "")
  # Off Windows, entries still compare as written.
  testthat::expect_identical(
    path_entry_key(c("/usr/bin/", "/usr/bin", "/"), on_windows = FALSE),
    c("/usr/bin/", "/usr/bin", "/")
  )
  # prepend_path_dirs() keeps one copy of a directory that the base PATH
  # spells with a trailing separator. Paths without a drive letter, as
  # `.Platform$path.sep` is `:` off Windows.
  p <- function(...) paste(c(...), collapse = .Platform$path.sep)
  testthat::expect_identical(
    prepend_path_dirs(
      c("\\Env", "\\Env\\Scripts"),
      p("\\env\\", "/ENV/scripts/", "\\other\\"),
      on_windows = TRUE
    ),
    p("\\Env", "\\Env\\Scripts", "\\other\\")
  )
})

testthat::test_that("prepend_path_dirs() keeps one copy of each prepended directory", {
  sep <- .Platform$path.sep
  p <- function(...) paste(c(...), collapse = sep)
  # Paths without a drive letter, as `.Platform$path.sep` is `:` off
  # Windows.
  dirs <- c("/root/envs/e", "/root/envs/e/Library/bin", "/root/envs/e/Scripts")
  activated <- p(
    "\\root\\envs\\e",
    "\\Root\\Envs\\E\\Library\\bin",
    "\\root\\envs\\e\\Scripts",
    "\\root\\condabin",
    "/usr/bin",
    "\\Windows",
    "\\windows"
  )
  # Regression test: on Windows, `run_bin()` put the environment's
  # directories on the command's PATH twice, spelled with `/` in front of
  # the activation's copies spelled with `\`. The first copy and its
  # spelling are kept; the other entries of the PATH stay as they are,
  # also the two spellings of `\Windows`, as with `run()`.
  testthat::expect_identical(
    prepend_path_dirs(dirs, activated, on_windows = TRUE),
    p(dirs, "\\root\\condabin", "/usr/bin", "\\Windows", "\\windows")
  )
  # Off Windows, entries compare as written: the result is that of
  # `compose_path()`.
  testthat::expect_identical(
    prepend_path_dirs(dirs, activated, on_windows = FALSE),
    compose_path(dirs, activated)
  )
  testthat::expect_identical(
    prepend_path_dirs(dirs, activated, on_windows = FALSE),
    p(dirs, strsplit(activated, sep, fixed = TRUE)[[1L]])
  )
  same <- p(dirs, "/usr/bin", "/root/envs/e", "/bin")
  for (on_windows in c(TRUE, FALSE)) {
    testthat::expect_identical(
      prepend_path_dirs(dirs, same, on_windows = on_windows),
      p(dirs, "/usr/bin", "/bin"),
      info = on_windows
    )
    testthat::expect_identical(
      prepend_path_dirs(dirs, same, on_windows = on_windows),
      compose_path(dirs, same),
      info = on_windows
    )
  }
  # Repeated prepended directories, empty entries and an empty PATH.
  testthat::expect_identical(
    prepend_path_dirs(c("/a", "", "\\A"), p("", "/b"), on_windows = TRUE),
    p("/a", "/b")
  )
  testthat::expect_identical(
    prepend_path_dirs("/a", "", on_windows = TRUE),
    "/a"
  )
  testthat::expect_identical(prepend_path_dirs("/a", NULL), "/a")
})

testthat::test_that("apply_child_overlay() and build_child_env() prepend each directory once", {
  sep <- .Platform$path.sep
  p <- function(...) paste(c(...), collapse = sep)
  dirs <- c("/root/envs/e", "/root/envs/e/Scripts")
  overlay_path <- p("\\root\\envs\\e", "\\root\\envs\\e\\Scripts", "/usr/bin")
  base_env <- c(KEEP = "1", Path = "/usr/bin")
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  child_env <- apply_child_overlay(
    base_env,
    overlay = c(PATH = overlay_path),
    path_prepend = dirs
  )
  testthat::expect_identical(
    child_env[sort(names(child_env))],
    c(KEEP = "1", PATH = p(dirs, "/usr/bin"))
  )
  built <- build_child_env(
    tmp_dir = "/tmp/fake-tmp-dir",
    overlay = c(PATH = overlay_path),
    path_prepend = dirs
  )
  path_name <- match_env_name(names(built), "PATH")
  testthat::expect_identical(unname(built[[path_name]]), p(dirs, "/usr/bin"))
  # Off Windows, the activation's `\` spelling is another directory.
  testthat::local_mocked_bindings(is_windows = function() FALSE)
  child_env <- apply_child_overlay(
    c(KEEP = "1", PATH = "/usr/bin"),
    overlay = c(PATH = overlay_path),
    path_prepend = dirs
  )
  testthat::expect_identical(
    unname(child_env[["PATH"]]),
    compose_path(dirs, overlay_path)
  )
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
  # Off Windows, entries compare as written: every entry the baseline lacks
  # counts as put in front.
  testthat::local_mocked_bindings(is_windows = function() FALSE)
  testthat::expect_identical(
    split_activated_path(
      p("/env/bin", "\\usr\\bin"),
      p("/usr/bin")
    ),
    list(prepend = c("/env/bin", "\\usr\\bin"), append = character(0L))
  )
})

testthat::test_that("split_activated_path() compares Windows entries as Windows does", {
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  sep <- .Platform$path.sep
  p <- function(...) paste(c(...), collapse = sep)
  # Regression test: micromamba spells the session's entries with
  # backslashes, so with a first session entry spelled with `/` every such
  # entry went in front of the session's PATH again (found on r-universe's
  # Windows runners, where R CMD check puts `C:/R/bin/x64` first). Paths
  # without a drive letter, as `.Platform$path.sep` is `:` off Windows.
  testthat::expect_identical(
    split_activated_path(
      p("\\env", "\\env\\Scripts", "\\R\\bin\\x64", "\\Windows", "\\Apps"),
      p("/R/bin/x64", "\\Windows", "/apps")
    ),
    list(prepend = c("\\env", "\\env\\Scripts"), append = character(0L))
  )
  # What an activate.d script appends, spelled either way, is still found.
  testthat::expect_identical(
    split_activated_path(
      p("\\env", "\\Windows", "\\Extra", "/extra"),
      p("\\Windows")
    ),
    list(prepend = "\\env", append = "\\Extra")
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
