test_that("resolve_env_bin_path() does not join an absolute path to the environment", {
  # On Windows, joining a long absolute command to a long environment
  # directory exceeded PATH_MAX and made `fs::path()` abort.
  env_dir <- withr::local_tempdir(pattern = strrep("e", 100L))
  tool_dir <- withr::local_tempdir(pattern = strrep("t", 100L))
  tool_name <- if (isTRUE(is_windows())) "tool.exe" else "tool"
  tool <- fs::path(tool_dir, tool_name)
  fs::file_create(tool)

  testthat::expect_identical(
    as.character(resolve_env_bin_path(env_dir, as.character(tool))),
    as.character(native_command_path(tool))
  )
  testthat::expect_null(
    resolve_env_bin_path(env_dir, as.character(fs::path(tool_dir, "missing")))
  )

  # On Windows, `cmd.exe` given with backslashes resolves to the same
  # path, and that path starts it.
  if (isTRUE(is_windows())) {
    cmd_exe <- gsub(
      "/",
      "\\",
      file.path(Sys.getenv("SystemRoot"), "System32", "cmd.exe"),
      fixed = TRUE
    )
    resolved <- resolve_env_bin_path(env_dir, cmd_exe)
    testthat::expect_identical(resolved, cmd_exe)
    res <- processx::run(
      resolved,
      c("/d", "/c", "echo", "condathis-ok"),
      error_on_status = FALSE
    )
    testthat::expect_identical(res$status, 0L)
    testthat::expect_match(res$stdout, "condathis-ok", fixed = TRUE)
  }
})

test_that("resolve_env_bin_path() returns an absolute path with backslashes on Windows", {
  # Regression test: on Windows, an absolute command came back with `/`
  # (`C:/Windows/System32/cmd.exe`), and `cmd.exe` started with that path
  # fails with "The syntax of the command is incorrect.".
  testthat::expect_identical(
    native_command_path("C:/Windows/System32/cmd.exe", on_windows = TRUE),
    "C:\\Windows\\System32\\cmd.exe"
  )
  testthat::expect_identical(
    native_command_path("C:\\Windows/System32\\cmd.exe", on_windows = TRUE),
    "C:\\Windows\\System32\\cmd.exe"
  )
  testthat::expect_identical(
    native_command_path("C:\\Windows\\System32\\cmd.exe", on_windows = TRUE),
    "C:\\Windows\\System32\\cmd.exe"
  )
  # Off Windows, the path is the one `fs::path()` gives, as before.
  testthat::expect_identical(
    native_command_path("/usr/bin/env", on_windows = FALSE),
    fs::path("/usr/bin/env")
  )
  # The default follows `is_windows()`.
  testthat::with_mocked_bindings(
    is_windows = function() TRUE,
    code = testthat::expect_identical(native_command_path("/a/b"), "\\a\\b")
  )

  # resolve_env_bin_path() with the Windows rule, also on Linux and macOS:
  # the file is found through `PATHEXT` and returned with backslashes.
  tool_dir <- withr::local_tempdir()
  tool <- fs::path(tool_dir, "tool.exe")
  fs::file_create(tool)
  testthat::with_mocked_bindings(
    is_windows = function() TRUE,
    code = withr::with_envvar(
      c(PATHEXT = ".EXE"),
      testthat::expect_identical(
        resolve_env_bin_path(
          withr::local_tempdir(),
          as.character(fs::path(tool_dir, "tool"))
        ),
        gsub("/", "\\", as.character(tool), fixed = TRUE)
      )
    )
  )
  # Without the Windows rule, the path stays an `fs_path` with `/`.
  testthat::with_mocked_bindings(
    is_windows = function() FALSE,
    code = testthat::expect_identical(
      resolve_env_bin_path(withr::local_tempdir(), as.character(tool)),
      fs::path(tool)
    )
  )
})

test_that("resolve_env_bin_path() tries PATHEXT extensions for a path without one on Windows", {
  tool_dir <- withr::local_tempdir()
  tool <- fs::path(tool_dir, "tool.exe")
  fs::file_create(tool)
  bare <- as.character(fs::path(tool_dir, "tool"))

  # The Windows rule runs on every OS: the names that are tried have the
  # extensions of `PATHEXT`, in lower case first, and never the path itself.
  candidates <- command_candidate_names(
    bare,
    on_windows = TRUE,
    pathext = ".COM;.EXE"
  )
  testthat::expect_identical(
    candidates,
    paste0(bare, c(".com", ".exe", ".COM", ".EXE"))
  )
  testthat::expect_identical(
    candidates[file.exists(candidates)][[1L]],
    as.character(tool)
  )
  testthat::expect_identical(
    command_candidate_names(bare, on_windows = FALSE, pathext = ".COM;.EXE"),
    bare
  )

  # resolve_env_bin_path() with that rule, also on Linux and macOS.
  testthat::with_mocked_bindings(
    is_windows = function() TRUE,
    code = withr::with_envvar(
      c(PATHEXT = ".COM;.EXE"),
      testthat::expect_identical(
        resolve_env_bin_path(withr::local_tempdir(), bare),
        native_command_path(tool, on_windows = TRUE)
      )
    )
  )

  # The extensions come from `PATHEXT`, not from a built-in list.
  other <- fs::path(tool_dir, "other.xyz")
  fs::file_create(other)
  testthat::with_mocked_bindings(
    is_windows = function() TRUE,
    code = withr::with_envvar(
      c(PATHEXT = ".XYZ"),
      testthat::expect_identical(
        resolve_env_bin_path(
          withr::local_tempdir(),
          as.character(fs::path(tool_dir, "other"))
        ),
        native_command_path(other, on_windows = TRUE)
      )
    )
  )

  # On Windows, with the `PATHEXT` of the session.
  if (isTRUE(is_windows())) {
    resolved <- resolve_env_bin_path(withr::local_tempdir(), bare)
    testthat::expect_identical(
      tolower(resolved),
      tolower(native_command_path(tool))
    )
  }
})
