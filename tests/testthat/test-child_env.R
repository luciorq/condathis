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
  # No variable of R reaches the child (see `undo_r_startup_env()`).
  testthat::expect_false("R_HOME" %in% names(env))
  testthat::expect_identical(
    grep("^_?R_", names(env), value = TRUE),
    character(0L)
  )
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
    path_entry_key(
      c("C:\\", "C:/", "c:\\\\", "C:", "\\", "/"),
      on_windows = TRUE
    ),
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
  base_path <- paste(c("/a", "/b"), collapse = .Platform$path.sep)
  envvars <- get_activation_envvars(
    env_name = "fake-env",
    env_dir = "/fake/envs/fake-env",
    base_path = base_path
  )
  testthat::expect_equal(
    unname(envvars[["CONDA_PREFIX"]]),
    "/fake/envs/fake-env"
  )
  testthat::expect_identical(unname(envvars[["CONDA_DEFAULT_ENV"]]), "fake-env")
  testthat::expect_identical(unname(envvars[["CONDA_SHLVL"]]), "1")
  testthat::expect_identical(unname(envvars[["MAMBA_SHLVL"]]), "1")
  testthat::expect_identical(
    unname(envvars[c("CONDA_PROMPT_MODIFIER", "MAMBA_PROMPT_MODIFIER")]),
    rep("", 2L)
  )
  # The env's bin layout dirs come first, then the given PATH, never the
  # session's.
  testthat::expect_identical(
    unname(envvars[["PATH"]]),
    prepend_path_dirs(env_bin_search_dirs("/fake/envs/fake-env"), base_path)
  )
  path_parts <- strsplit(
    envvars[["PATH"]],
    .Platform$path.sep,
    fixed = TRUE
  )[[1L]]
  testthat::expect_equal(
    path_parts[seq_along(env_bin_search_dirs("/fake/envs/fake-env"))],
    as.character(env_bin_search_dirs("/fake/envs/fake-env"))
  )
  # `TMPDIR` and `CONDA_ENVS_PATH` come from the clean overlay (see
  # child_conda_dirs()), so both `activate` modes give a command the same
  # values.
  testthat::expect_false("CONDA_ENVS_PATH" %in% names(envvars))
  testthat::expect_false("TMPDIR" %in% names(envvars))
  # Without a base PATH, the default is the PATH a child starts from.
  testthat::expect_identical(
    unname(get_activation_envvars("e", "/fake/envs/e")[["PATH"]]),
    prepend_path_dirs(
      env_bin_search_dirs("/fake/envs/e"),
      isolated_session_path()
    )
  )
})

testthat::test_that("isolate_host_env() undoes a nested host activation", {
  dir <- withr::local_tempdir()
  prefixes <- make_fake_host_prefixes(dir, c("outer", "inner", "pixi", "r"))
  keep_dir <- as.character(fs::path(dir, "keep"))
  system_dir <- if (isTRUE(is_windows())) "C:/Windows/System32" else "/usr/bin"
  env <- fake_nested_host_vars(
    prefixes,
    keep_dir,
    paste(
      c(fake_host_bin(prefixes[["r"]]), system_dir),
      collapse = .Platform$path.sep
    )
  )
  # The backup of the libglib form may be empty: then the variable it
  # saved was unset before the activation.
  env[["CONDATHIS_HOST_SCHEMA_CONDA_BACKUP"]] <- ""
  env[["_CE_CONDA"]] <- ""
  env[["R_LIBS_USER"]] <- "/r/libs"
  env[["CONDATHIS_UNRELATED"]] <- "kept"

  isolated <- isolate_host_env(env, r_prefix = prefixes[["r"]])

  # The directories of R's own prefix leave PATH on every OS.
  expected_path <- c(keep_dir, system_dir)
  testthat::expect_identical(
    isolated[["PATH"]],
    paste(expected_path, collapse = .Platform$path.sep)
  )
  testthat::expect_identical(isolated[["CONDATHIS_HOST_SAVED"]], "before")
  testthat::expect_identical(isolated[["CONDATHIS_HOST_CC"]], "user-cc")
  testthat::expect_false("CONDATHIS_HOST_SCHEMA" %in% names(isolated))
  testthat::expect_false("CONDATHIS_HOST_ENVVAR" %in% names(isolated))
  testthat::expect_false("CONDATHIS_STATE" %in% names(isolated))
  # A value that differs from the one of `env_vars.d` is the user's own.
  testthat::expect_identical(isolated[["CONDATHIS_HOST_USER"]], "user")
  testthat::expect_identical(
    intersect(c(fake_host_marker_names(), "_CE_CONDA"), names(isolated)),
    character(0L)
  )
  testthat::expect_identical(isolated[["PIXI_HOME"]], env[["PIXI_HOME"]])
  # Every variable of R leaves, also one the user set.
  testthat::expect_false("R_LIBS_USER" %in% names(isolated))
  testthat::expect_identical(isolated[["CONDATHIS_UNRELATED"]], "kept")
  # The variables of the clean overlay are left to it.
  testthat::expect_identical(isolated[["CONDA_PREFIX"]], prefixes[["inner"]])
  testthat::expect_identical(isolated[["CONDA_SHLVL"]], "2")
  testthat::expect_identical(isolated[["CONDA_DEFAULT_ENV"]], "inner")

  # The prefixes come from every stack, and R's own prefix.
  # R's own prefix leaves PATH on every OS, Windows included.
  found <- host_env_prefixes(env, r_prefix = prefixes[["r"]])
  testthat::expect_setequal(found, unname(prefixes))
})

testthat::test_that("isolate_host_env() restores the oldest saved value of a stack", {
  env <- list(
    CONDA_ENV_SHLVL_2_CONDATHIS_X = "level-2",
    CONDA_ENV_SHLVL_1_CONDATHIS_X = "level-1",
    CONDATHIS_X = "now",
    CONDA_ENV_SHLVL_1_PATH = "/old/path",
    PATH = "/a:/b"
  )
  isolated <- isolate_host_env(env, r_prefix = NULL, on_windows = FALSE)
  testthat::expect_identical(isolated[["CONDATHIS_X"]], "level-1")
  # PATH is never restored from a backup.
  testthat::expect_identical(isolated[["PATH"]], "/a:/b")
  testthat::expect_named(isolated, c("CONDATHIS_X", "PATH"))
})

testthat::test_that("isolate_host_env() leaves a session without host activation alone", {
  env <- list(
    PATH = "/usr/local/bin::/usr/bin:/bin:",
    HOME = "/home/user",
    CONDATHIS_UNRELATED = "kept",
    PIXI_HOME = "/home/user/.pixi"
  )
  testthat::expect_identical(
    isolate_host_env(env, r_prefix = NULL, on_windows = FALSE),
    env
  )
  # A `CONDA_PREFIX` that is not a Conda prefix never removes a directory.
  env[["CONDA_PREFIX"]] <- "/usr"
  testthat::expect_identical(
    isolate_host_env(
      env,
      r_prefix = "/usr",
      on_windows = FALSE,
      is_prefix = function(dir) FALSE
    ),
    env
  )
  # A prefix whose directory is not on PATH leaves PATH byte-identical,
  # empty entries included.
  testthat::expect_identical(
    strip_host_path("/a::/b:", "/elsewhere", on_windows = FALSE),
    "/a::/b:"
  )
  # A removed entry keeps the empty entries around it.
  testthat::expect_identical(
    strip_host_path("/p/bin::/b:", "/p", on_windows = FALSE),
    ":/b:"
  )
  # Off Windows, entries compare as written.
  testthat::expect_identical(
    strip_host_path("/p/bin/:/p/bin", "/p", on_windows = FALSE),
    "/p/bin/"
  )
})

testthat::test_that("isolate_host_env() applies the Windows rule", {
  env <- list(
    Path = paste(
      c(
        "c:/envs/inner/Library/bin",
        "C:\\envs\\inner\\Scripts\\",
        "\"C:\\envs\\inner\"",
        "C:\\Windows\\System32",
        "C:\\R-conda\\Library\\bin",
        "C:\\envs\\outer\\Library\\bin"
      ),
      collapse = ";"
    ),
    conda_prefix = "C:\\envs\\inner",
    Conda_Prefix_1 = "C:\\envs\\outer",
    conda_exe = "C:\\envs\\outer\\Scripts\\conda.exe",
    pixi_in_shell = "1",
    Conda_Backup_CC = "user-cc",
    cc = "conda-cc"
  )
  isolated <- isolate_host_env(
    env,
    r_prefix = "C:\\R-conda",
    on_windows = TRUE,
    is_prefix = function(dir) TRUE
  )
  # R's own prefix leaves PATH on Windows too; the name keeps its spelling.
  testthat::expect_identical(isolated[["Path"]], "C:\\Windows\\System32")
  testthat::expect_identical(isolated[["cc"]], "user-cc")
  testthat::expect_setequal(names(isolated), c("Path", "conda_prefix", "cc"))
  # The same block off Windows: names compare as written, so none of these
  # names matches, and nothing changes.
  testthat::expect_identical(
    isolate_host_env(
      env,
      r_prefix = NULL,
      on_windows = FALSE,
      is_prefix = function(dir) TRUE
    ),
    env
  )
})

testthat::test_that("build_child_env() starts from the isolated session", {
  host <- local_fake_nested_host()
  env <- build_child_env(tmp_dir = "/tmp/fake-tmp-dir")
  testthat::expect_identical(
    intersect(fake_host_marker_names(), names(env)),
    character(0L)
  )
  testthat::expect_identical(unname(env[["CONDA_PREFIX"]]), "")
  testthat::expect_identical(unname(env[["CONDA_SHLVL"]]), "0")
  testthat::expect_identical(unname(env[["CONDATHIS_HOST_SAVED"]]), "before")
  testthat::expect_identical(unname(env[["CONDATHIS_HOST_CC"]]), "user-cc")
  testthat::expect_identical(
    unname(env[["CONDATHIS_HOST_SCHEMA"]]),
    "user-schema"
  )
  testthat::expect_false("CONDATHIS_HOST_ENVVAR" %in% names(env))
  testthat::expect_false("CONDATHIS_STATE" %in% names(env))
  path <- env_block_path(env)
  testthat::expect_identical(path, isolated_session_path())
  testthat::expect_false(
    path_names_any(path, vapply(host$prefixes, fake_host_bin, character(1L)))
  )
  testthat::expect_true(path_names_any(path, host$keep_dir))
  # The session itself is unchanged.
  testthat::expect_identical(
    Sys.getenv("CONDA_PREFIX_1"),
    host$prefixes[["outer"]]
  )
  testthat::expect_true(
    path_names_any(Sys.getenv("PATH"), fake_host_bin(host$prefixes[["inner"]]))
  )
})

testthat::test_that("condathis_r_prefix() finds the Conda prefix that R runs from", {
  dir <- withr::local_tempdir()
  prefix <- as.character(fs::path(dir, "r-env"))
  fs::dir_create(fs::path(prefix, "conda-meta"))
  fs::dir_create(fs::path(prefix, "lib", "R"))
  testthat::expect_identical(
    condathis_r_prefix(as.character(fs::path(prefix, "lib", "R"))),
    prefix
  )
  # CRAN R and the R of a Linux distribution have none.
  testthat::expect_null(condathis_r_prefix(as.character(fs::path(dir, "R"))))
  testthat::expect_null(condathis_r_prefix(""))
})

testthat::test_that("drop_activation_stack_vars() drops the stacking variables only", {
  testthat::expect_identical(
    drop_activation_stack_vars(
      c(
        "CONDA_PREFIX",
        "CONDA_PREFIX_1",
        "CONDA_PREFIX_12",
        "CONDA_ENV_SHLVL_1_CONDA_PREFIX",
        "CONDA_ENV_SHLVL_2_FOO",
        "CONDA_SHLVL",
        "CONDA_PREFIX_X",
        "conda_prefix_1"
      ),
      on_windows = FALSE
    ),
    c("CONDA_PREFIX", "CONDA_SHLVL", "CONDA_PREFIX_X", "conda_prefix_1")
  )
  testthat::expect_identical(
    drop_activation_stack_vars(c("conda_prefix_1", "Path"), on_windows = TRUE),
    "Path"
  )
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

testthat::test_that("compose_child_env() gives every command one activation level", {
  # The decision of 2026-11-16: CONDA_SHLVL and MAMBA_SHLVL are the same,
  # "1", and the prompt modifiers are empty, in both modes and whatever a
  # backend's activation sets.
  env_dir <- as.character(fs::path(withr::local_tempdir(), "envs", "e"))
  base_env <- build_child_env(tmp_dir = withr::local_tempdir())
  level <- child_activation_level_vars()
  testthat::expect_identical(
    level,
    c(
      CONDA_SHLVL = "1",
      MAMBA_SHLVL = "1",
      CONDA_PROMPT_MODIFIER = "",
      MAMBA_PROMPT_MODIFIER = ""
    )
  )
  backend_env <- c(
    CONDA_PREFIX = env_dir,
    CONDA_SHLVL = "3",
    MAMBA_SHLVL = "0",
    CONDA_PROMPT_MODIFIER = "(e) ",
    MAMBA_PROMPT_MODIFIER = NA_character_
  )
  for (activate in c(TRUE, FALSE)) {
    invocation <- list(
      command = "tool",
      args = character(0L),
      env = if (isTRUE(activate)) {
        backend_env
      } else {
        get_activation_envvars("e", env_dir, env_block_path(base_env))
      },
      dir = NULL
    )
    child_env <- compose_child_env(
      base_env,
      invocation,
      env_dir = env_dir,
      activate = activate
    )
    testthat::expect_identical(
      child_env[names(level)],
      level,
      info = paste("activate:", activate)
    )
    testthat::expect_identical(
      unname(child_env[["CONDA_PREFIX"]]),
      env_dir,
      info = paste("activate:", activate)
    )
  }
})

testthat::test_that("a program of R's own prefix gets its directories back on Windows", {
  r_prefix <- "C:/conda/envs/rconda"
  child_env <- c(
    PATH = "C:\\env\\bin;C:\\Windows\\System32",
    CONDA_SHLVL = "1"
  )
  r_dirs <- as.character(env_bin_search_dirs(r_prefix, on_windows = TRUE))

  for (command in c(
    "C:/conda/envs/rconda/Lib/R/bin/x64/Rscript.exe",
    "c:\\CONDA\\envs\\rconda\\Library\\bin\\curl.exe"
  )) {
    res <- r_prefix_command_env(
      command,
      child_env = child_env,
      on_windows = TRUE,
      r_prefix = r_prefix
    )
    testthat::expect_identical(
      strsplit(unname(res[["PATH"]]), ";", fixed = TRUE)[[1L]],
      c("C:\\env\\bin", "C:\\Windows\\System32", r_dirs),
      info = command
    )
    testthat::expect_identical(res[["CONDA_SHLVL"]], "1")
  }

  # A relative command is taken from the working directory.
  res <- r_prefix_command_env(
    "Lib/R/bin/x64/Rscript.exe",
    child_env = child_env,
    wd = r_prefix,
    on_windows = TRUE,
    r_prefix = r_prefix
  )
  testthat::expect_false(identical(res, child_env))

  # Every other command, a sibling directory with the same start included,
  # keeps its environment block.
  for (command in c(
    "C:/conda/envs/rconda2/Scripts/tool.exe",
    "C:/env/bin/tool.exe",
    "tool"
  )) {
    testthat::expect_identical(
      r_prefix_command_env(
        command,
        child_env = child_env,
        wd = "C:/work",
        on_windows = TRUE,
        r_prefix = r_prefix
      ),
      child_env,
      info = command
    )
  }
  testthat::expect_identical(
    r_prefix_command_env(
      NULL,
      child_env = child_env,
      on_windows = TRUE,
      r_prefix = r_prefix
    ),
    child_env
  )
  # Without R's prefix, and off Windows, nothing changes.
  rscript <- "C:/conda/envs/rconda/Lib/R/bin/x64/Rscript.exe"
  testthat::expect_identical(
    r_prefix_command_env(
      rscript,
      child_env = child_env,
      on_windows = TRUE,
      r_prefix = NULL
    ),
    child_env
  )
  testthat::expect_identical(
    r_prefix_command_env(
      rscript,
      child_env = child_env,
      on_windows = FALSE,
      r_prefix = r_prefix
    ),
    child_env
  )
  # Directories already on the `PATH` are not added twice.
  full <- c(
    PATH = paste(
      c("C:\\env\\bin", gsub("/", "\\", r_dirs, fixed = TRUE)),
      collapse = ";"
    )
  )
  testthat::expect_identical(
    r_prefix_command_env(
      rscript,
      child_env = full,
      on_windows = TRUE,
      r_prefix = r_prefix
    ),
    full
  )
})

testthat::test_that("undo_r_startup_env() removes what R's startup set", {
  r_startup <- c(
    MAKE = "make",
    EDITOR = "vi",
    TAR = "/usr/bin/tar",
    LD_LIBRARY_PATH = "/opt/R/lib:/usr/lib/jvm/lib/server",
    DYLD_FALLBACK_LIBRARY_PATH = "/R/lib"
  )
  env <- list(
    PATH = "/usr/bin:/bin",
    MAKE = "make",
    EDITOR = "nvim",
    LD_LIBRARY_PATH = "/opt/R/lib:/usr/lib/jvm/lib/server:/user/lib",
    DYLD_FALLBACK_LIBRARY_PATH = "/R/lib",
    R_HOME = "/opt/R",
    R_LIBS_USER = "/user/R-lib",
    `_R_CHECK_FAKE_` = "true",
    RSTUDIO = "1",
    CONDATHIS_R_LIKE = "kept",
    r_lower = "kept off Windows"
  )
  out <- undo_r_startup_env(env, r_startup = r_startup, on_windows = FALSE)
  testthat::expect_identical(
    out,
    list(
      PATH = "/usr/bin:/bin",
      EDITOR = "nvim",
      LD_LIBRARY_PATH = "/user/lib",
      RSTUDIO = "1",
      CONDATHIS_R_LIKE = "kept",
      r_lower = "kept off Windows"
    )
  )
  # A library path that does not start with R's part is the user's.
  out <- undo_r_startup_env(
    list(LD_LIBRARY_PATH = "/user/lib:/opt/R/lib:/usr/lib/jvm/lib/server"),
    r_startup = r_startup,
    on_windows = FALSE
  )
  testthat::expect_identical(
    out[["LD_LIBRARY_PATH"]],
    "/user/lib:/opt/R/lib:/usr/lib/jvm/lib/server"
  )
  # Without a measurement, only the `R_*` variables leave.
  out <- undo_r_startup_env(env, r_startup = NULL, on_windows = FALSE)
  testthat::expect_identical(out[["MAKE"]], "make")
  testthat::expect_identical(
    grep("^_?R_", names(out), value = TRUE),
    character(0L)
  )
})

testthat::test_that("undo_r_startup_env() applies the Windows rules", {
  env <- list(
    Path = paste(
      c(
        "c:/rtools45/x86_64-w64-mingw32.static.posix/bin",
        "C:\\rtools45\\usr\\bin\\",
        "C:\\Windows\\System32",
        "c:/rtools45/usr/bin"
      ),
      collapse = ";"
    ),
    R_RTOOLS45_PATH = "c:/rtools45/x86_64-w64-mingw32.static.posix/bin;c:/rtools45/usr/bin",
    r_arch = "/x64",
    R_Compiled_By = "gcc 14.3.0",
    curl_ca_bundle = "C:/R/etc/curl-ca-bundle.crt",
    MSYS2_ENV_CONV_EXCL = "R_ARCH",
    USERPROFILE = "C:\\Users\\me"
  )
  out <- undo_r_startup_env(
    env,
    r_startup = c(
      CURL_CA_BUNDLE = "C:/R/etc/curl-ca-bundle.crt",
      MSYS2_ENV_CONV_EXCL = "R_ARCH"
    ),
    on_windows = TRUE
  )
  # Only the entries in front go: the user put the later copy there.
  testthat::expect_identical(
    out,
    list(
      Path = "C:\\Windows\\System32;c:/rtools45/usr/bin",
      USERPROFILE = "C:\\Users\\me"
    )
  )
  # Rtools entries that are not in front stay.
  env[["Path"]] <- "C:\\Windows\\System32;c:/rtools45/usr/bin"
  out <- undo_r_startup_env(env, r_startup = NULL, on_windows = TRUE)
  testthat::expect_identical(out[["Path"]], env[["Path"]])
})

testthat::test_that("strip_leading_path_entries() needs all entries, in order", {
  testthat::expect_identical(
    strip_leading_path_entries("/a:/b:/c", c("/a", "/b"), on_windows = FALSE),
    "/c"
  )
  testthat::expect_identical(
    strip_leading_path_entries("/b:/a:/c", c("/a", "/b"), on_windows = FALSE),
    "/b:/a:/c"
  )
  testthat::expect_identical(
    strip_leading_path_entries("/a", c("/a", "/b"), on_windows = FALSE),
    "/a"
  )
  testthat::expect_identical(
    strip_leading_path_entries("/a:/b", character(0L), on_windows = FALSE),
    "/a:/b"
  )
  testthat::expect_identical(
    strip_leading_path_entries("/a:/b", c("/a", "/b"), on_windows = FALSE),
    ""
  )
})

testthat::test_that("r_startup_env_vars() measures R's startup once per session", {
  testthat::local_mocked_bindings(
    get_condathis_rscript_path = function() {
      stop("the cache must answer", call. = FALSE)
    }
  )
  local_r_startup_cache(c(MAKE = "cached-make"))
  testthat::expect_identical(r_startup_env_vars(), c(MAKE = "cached-make"))
  local_r_startup_cache(NA)
  testthat::expect_null(r_startup_env_vars())
})

testthat::test_that("r_startup_env_vars() reads the values of R's own Rscript", {
  values <- r_startup_env_vars(use_cache = FALSE)
  testthat::expect_type(values, "character")
  testthat::expect_true(all(
    env_name_key(names(values)) %in% env_name_key(r_startup_var_names())
  ))
  # `etc/Renviron` sets these off Windows.
  # R's base profile sets `CURL_CA_BUNDLE` only when R ships the file: CRAN
  # R does, the R of conda-forge does not.
  if (isTRUE(is_windows())) {
    testthat::expect_identical(
      "CURL_CA_BUNDLE" %in% names(values),
      file.exists(file.path(R.home("etc"), "curl-ca-bundle.crt"))
    )
  } else {
    testthat::expect_true(all(c("MAKE", "TAR", "LN_S") %in% names(values)))
  }
  # A session value of the user is not what R measures.
  withr::local_envvar(c(MAKE = "condathis-user-make"))
  testthat::expect_false(identical(
    unname(r_startup_env_vars(use_cache = FALSE)["MAKE"]),
    "condathis-user-make"
  ))
  # A failed start is no measurement.
  testthat::expect_null(r_startup_env_vars(
    use_cache = FALSE,
    rscript_path = file.path(tempdir(), "no-such-rscript")
  ))
})
