test_that("Native run conda command", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  px_res <- native_cmd("--help", verbose = FALSE)
  expect_equal(
    object = px_res$status,
    expected = 0L
  )

  px_res <- native_cmd("env", "list", verbose = FALSE)
  expect_equal(
    object = px_res$status,
    expected = 0L
  )

  px_res <- native_cmd("--version", verbose = FALSE)
  expect_equal(
    object = px_res$status,
    expected = 0L
  )
})

test_that("Native run accepts linux_pdeathsig", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # Ignored without a warning on platforms other than Linux.
  testthat::expect_no_warning(
    px_res <- native_cmd(
      "--version",
      verbose = FALSE,
      linux_pdeathsig = TRUE
    )
  )
  expect_equal(
    object = px_res$status,
    expected = 0L
  )
})

test_that("has_arg_sequence() finds consecutive arguments", {
  testthat::expect_true(has_arg_sequence(
    c("create", "--log-level", "error", "-n", "x"),
    c("--log-level", "error")
  ))
  testthat::expect_true(has_arg_sequence(
    list("--log-level", c("error", "pkg")),
    c("--log-level", "error")
  ))
  testthat::expect_false(has_arg_sequence(
    c("--log-level", "info", "error"),
    c("--log-level", "error")
  ))
  testthat::expect_false(has_arg_sequence(
    "--log-level",
    c("--log-level", "error")
  ))
  testthat::expect_false(has_arg_sequence(NULL, c("--log-level", "error")))
})

test_that("native_cmd_echo() looks only at the options condathis passes", {
  # Regression test: the quiet-mode check scanned every argument of
  # `micromamba run`, including the user's command line, so
  # `run("uvicorn", "app:app", "--log-level", "error")` never showed the
  # command's output live.
  testthat::expect_true(native_cmd_echo(
    output = TRUE,
    conda_args = c("-n", "my-env"),
    stderr = "|",
    encoding = "utf-8"
  ))
  testthat::expect_false(native_cmd_echo(
    output = TRUE,
    conda_args = c("-n", "my-env", micromamba_quiet_args),
    stderr = "|",
    encoding = "utf-8"
  ))
  testthat::expect_false(native_cmd_echo(
    output = FALSE,
    conda_args = NULL,
    stderr = "|",
    encoding = "utf-8"
  ))
  # stderr redirected away from the console, or binary output: no echo.
  testthat::expect_false(native_cmd_echo(TRUE, NULL, "stderr.log", "utf-8"))
  testthat::expect_false(native_cmd_echo(TRUE, NULL, "2>&1", "utf-8"))
  testthat::expect_false(native_cmd_echo(TRUE, NULL, "|", "binary"))
  # Inherited or discarded stderr keeps the echo, as before.
  testthat::expect_true(native_cmd_echo(TRUE, NULL, "", "utf-8"))
  testthat::expect_true(native_cmd_echo(TRUE, NULL, NULL, "utf-8"))
})

test_that("a user's --log-level error argument does not hide the output of run()", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  create_polyglot_env("native-cmd-echo-env")

  testthat::expect_output(
    res <- run(
      "polyglot",
      "--log-level",
      "error",
      env_name = "native-cmd-echo-env",
      verbose = "output"
    ),
    polyglot_expected_line(),
    fixed = TRUE
  )
  testthat::expect_identical(res$status, 0L)
})

test_that("native_cmd() reports the exact command line that ran", {
  # Regression test (cmd-field): create_env(), install_packages() and
  # remove_env() reported an invented summary such as
  # "micromamba create -n env pkg", without the flags that really ran.
  fake_bin <- fs::path(withr::local_tempdir(), "micromamba")
  fs::file_create(fake_bin)
  spawned <- NULL
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function(...) fake_bin,
    execute_command = function(command, args, ...) {
      spawned <<- list(command = command, args = args)
      return(list(status = 0L, stdout = "", stderr = "", timeout = FALSE))
    }
  )
  px_res <- native_cmd(
    conda_cmd = "create",
    conda_args = c("-n", "cmd-env", "--yes", micromamba_quiet_args),
    "pkg a",
    "pkg-b>=1",
    verbose = "silent"
  )
  expected <- paste(
    shQuote(as.character(c(spawned$command, spawned$args))),
    collapse = " "
  )
  testthat::expect_identical(px_res$cmd, expected)
  testthat::expect_identical(
    as.character(spawned$command),
    as.character(fs::path_real(fake_bin))
  )
  # Every argument is there, the package specs last and quoted.
  testthat::expect_match(px_res$cmd, "--rc-file", fixed = TRUE)
  testthat::expect_match(px_res$cmd, "--no-env", fixed = TRUE)
  testthat::expect_match(px_res$cmd, shQuote("pkg a"), fixed = TRUE)
  testthat::expect_true(endsWith(px_res$cmd, shQuote("pkg-b>=1")))
})

test_that("native_cmd() reports cmd for a real micromamba process", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  px_res <- native_cmd("--version", verbose = "silent")
  testthat::expect_identical(px_res$status, 0L)
  testthat::expect_type(px_res$cmd, "character")
  testthat::expect_length(px_res$cmd, 1L)
  testthat::expect_true(endsWith(px_res$cmd, shQuote("--version")))
  testthat::expect_true(startsWith(
    px_res$cmd,
    shQuote(as.character(fs::path_real(get_best_micromamba_path())))
  ))
})

test_that("native_cmd(install = FALSE) never installs micromamba", {
  # Regression test (decision D3): the listings of the micromamba backend
  # are queries, and native_cmd() installed micromamba for them when no
  # usable binary was found.
  installed <- 0L
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function(...) NULL,
    install_micromamba = function(...) {
      installed <<- installed + 1L
      stop("install requested")
    },
    execute_command = function(...) stop("No process may start here.")
  )
  cnd <- rlang::catch_cnd(
    native_cmd(
      conda_cmd = "env",
      conda_args = c("list", "--json"),
      verbose = "silent",
      install = FALSE
    ),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd)[1:2],
    c("condathis_micromamba_not_installed", "condathis_error")
  )
  testthat::expect_identical(installed, 0L)
  testthat::expect_null(native_cmd_if_installed(
    conda_cmd = "env",
    conda_args = c("list", "--json"),
    verbose = "silent"
  ))
  testthat::expect_identical(installed, 0L)

  # The default still installs micromamba for the commands that need it.
  testthat::expect_error(
    native_cmd(conda_cmd = "create", verbose = "silent"),
    "install requested",
    fixed = TRUE
  )
  testthat::expect_identical(installed, 1L)
})

test_that("native_cmd() gives micromamba its root and keeps its files in the root", {
  # Regression tests (footprint, TD5): micromamba wrote its sharded
  # repodata cache to `<user cache>/conda/pkgs/cache/shards` and the
  # `mamba/proc` directory of `run` to the user cache, `env list` and
  # `env remove` rewrote the user's `~/.conda/environments.txt`, and
  # `create` appended every new environment to it, all outside the
  # condathis root. micromamba also refused to start when its default root
  # prefix was not a Conda prefix: every command now gets
  # `MAMBA_ROOT_PREFIX`.
  fake_bin <- fs::path(withr::local_tempdir(), "micromamba")
  fs::file_create(fake_bin)
  seen <- new.env(parent = emptyenv())
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function(...) fake_bin,
    execute_command = function(command, args, env, ...) {
      seen$env <- env
      return(list(status = 0L, stdout = "", stderr = "", timeout = FALSE))
    }
  )
  home_var <- if (isTRUE(is_windows())) "USERPROFILE" else "HOME"
  other_home_var <- if (isTRUE(is_windows())) "HOME" else "USERPROFILE"
  user_home <- as.character(fs::path(withr::local_tempdir(), "user-home"))
  fs::dir_create(user_home)
  child_var <- function(name) {
    found <- match_env_name(names(seen$env), name)
    return(if (is.na(found)) NA_character_ else unname(seen$env[[found]]))
  }
  env_file <- withr::local_tempfile(fileext = ".yml")
  writeLines(c("dependencies:", "  - polyglot"), env_file)
  cmds <- list(
    create = list("create", c("-n", "x", "--yes"), list("pkg")),
    create_file = list("create", c("-n", "x", "--yes"), list("-f", env_file)),
    dry_run = list("create", c("-p", "x", "--dry-run"), list("pkg")),
    install = list("install", c("-n", "x", "--yes"), list("pkg")),
    remove = list("env", c("remove", "-n", "x", "--yes"), list()),
    list_pkgs = list("list", c("-n", "x", "--json"), list()),
    clean = list("clean", c("--yes", "--force-pkgs-dirs"), list()),
    info = list("info", "--json", list()),
    env_list = list("env", c("list", "-q", "--json"), list()),
    run = list("run", c("-n", "x"), list("Rscript"))
  )
  # The commands that run with the home `<root>/home`: the other commands
  # need the user's saved credentials and expand `~` with it, and a dry
  # run registers no environment.
  moved_home <- c("create", "create_file", "env_list", "remove")
  for (user_cache in list("/user/cache", NULL)) {
    withr::local_envvar(
      c(
        stats::setNames(user_home, home_var),
        stats::setNames(user_home, other_home_var),
        `XDG_CACHE_HOME` = user_cache %||% NA_character_,
        `MAMBA_ROOT_PREFIX` = "/caller/root"
      )
    )
    root <- as.character(install_dir_for_backend(micromamba_backend()))
    for (name in names(cmds)) {
      info <- paste(name, user_cache %||% "unset")
      rlang::exec(
        native_cmd,
        conda_cmd = cmds[[name]][[1L]],
        conda_args = cmds[[name]][[2L]],
        !!!cmds[[name]][[3L]],
        verbose = "silent"
      )
      testthat::expect_identical(
        child_var("MAMBA_ROOT_PREFIX"),
        root,
        info = info
      )
      testthat::expect_identical(
        child_var("XDG_CACHE_HOME"),
        as.character(fs::path(root, "cache")),
        info = info
      )
      expected_home <- if (isTRUE(name %in% moved_home)) {
        as.character(fs::path(root, "home"))
      } else {
        user_home
      }
      testthat::expect_identical(
        child_var(home_var),
        expected_home,
        info = info
      )
      testthat::expect_identical(
        child_var(other_home_var),
        user_home,
        info = info
      )
    }
  }
})

test_that("native_cmd() gives micromamba a TMP in its TMPDIR on Windows only", {
  # Regression test: on Windows, micromamba writes its temporary files to
  # `TMP` (else `TEMP`), not to `TMPDIR`, and a `micromamba run` stopped by
  # a timeout or an interrupt left its two batch files in the user's
  # `%TEMP%`. Every micromamba command that `native_cmd()` starts now gets
  # `TMP` = a directory of its own in its `TMPDIR` there. It is not the
  # `TMPDIR` itself, so an `activate.d` script that sets `TMP` to the
  # `TMPDIR` is still recorded. `TEMP` is never changed, and other OSs keep
  # the session's `TMP`.
  fake_bin <- fs::path(withr::local_tempdir(), "micromamba")
  fs::file_create(fake_bin)
  seen <- new.env(parent = emptyenv())
  child_var <- function(name) {
    found <- match_env_name(names(seen$env), name)
    return(if (is.na(found)) NA_character_ else unname(seen$env[[found]]))
  }
  leave_file <- FALSE
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function(...) fake_bin,
    execute_command = function(command, args, env, ...) {
      seen$env <- env
      seen$tmp_existed <- dir.exists(child_var("TMP"))
      if (isTRUE(leave_file)) {
        # A batch file of a `run` that was stopped.
        writeLines("", file.path(child_var("TMP"), "mamba_act1.bat"))
      }
      return(list(status = 0L, stdout = "", stderr = "", timeout = FALSE))
    }
  )
  withr::local_envvar(TMP = "session-tmp", TEMP = "session-temp")
  given_tmp_dir <- withr::local_tempdir()
  for (on_windows in c(TRUE, FALSE)) {
    testthat::with_mocked_bindings(
      is_windows = function() on_windows,
      code = {
        for (tmp_dir in list(NULL, given_tmp_dir)) {
          for (leave_file in unique(c(FALSE, on_windows))) {
            info <- paste(on_windows, is.null(tmp_dir), leave_file)
            native_cmd(
              conda_cmd = "run",
              conda_args = c("-n", "x"),
              "Rscript",
              verbose = "silent",
              tmp_dir = tmp_dir
            )
            child_tmp_dir <- child_var("TMPDIR")
            child_tmp <- child_var("TMP")
            testthat::expect_identical(
              child_tmp_dir,
              as.character(tmp_dir %||% child_tmp_dir),
              info = info
            )
            testthat::expect_identical(
              child_var("TEMP"),
              "session-temp",
              info = info
            )
            if (isFALSE(on_windows)) {
              testthat::expect_identical(child_tmp, "session-tmp", info = info)
              next
            }
            testthat::expect_identical(
              as.character(fs::path_dir(child_tmp)),
              as.character(fs::path(child_tmp_dir)),
              info = info
            )
            testthat::expect_identical(
              as.character(fs::path_file(child_tmp)),
              "mamba-tmp",
              info = info
            )
            testthat::expect_true(seen$tmp_existed, info = info)
            # It goes with the `TMPDIR`. A given `TMPDIR` keeps it, also
            # when it is empty: the activation capture shares the `TMPDIR`
            # with the command, which can get a value that names it.
            testthat::expect_identical(
              dir.exists(child_tmp),
              isFALSE(is.null(tmp_dir)),
              info = info
            )
            testthat::expect_identical(
              dir.exists(child_tmp_dir),
              isFALSE(is.null(tmp_dir)),
              info = info
            )
            unlink(child_tmp, recursive = TRUE)
          }
        }
        overlay <- micromamba_cmd_overlay("info", "--json", "/root")
        testthat::expect_false("TMP" %in% names(overlay))
        # The directory is spelled with the separator of the `TMPDIR`.
        expected_tmp <- c(
          "/call/tmp" = "/call/tmp/mamba-tmp",
          "C:\\call\\tmp" = "C:\\call\\tmp\\mamba-tmp"
        )
        for (call_tmp in names(expected_tmp)) {
          overlay <- micromamba_cmd_overlay(
            "info",
            "--json",
            "/root",
            tmp_dir = call_tmp
          )
          testthat::expect_identical(
            overlay[["TMP"]],
            if (isTRUE(on_windows)) expected_tmp[[call_tmp]] else NULL,
            info = call_tmp
          )
        }
      }
    )
  }
})

test_that("micromamba create keeps the user's home when it needs it", {
  # Regression test (footprint, R-12): `micromamba create` appended every
  # environment to `~/.conda/environments.txt`, which no setting stops. It
  # now runs with the home `<root>/home`, unless micromamba needs the
  # user's home: saved credentials, or an environment file that names the
  # home or runs pip.
  home <- withr::local_tempdir()
  testthat::expect_false(micromamba_create_keeps_home(list("pkg"), home = home))
  credential_files <- list(
    c(".mamba", "auth", "authentication.json"),
    ".netrc",
    "_netrc",
    c(
      ".continuum",
      "anaconda-client",
      "tokens",
      "https%3A%2F%2Fapi.anaconda.org.token"
    )
  )
  for (parts in credential_files) {
    path <- do.call(fs::path, c(list(home), as.list(parts)))
    fs::dir_create(fs::path_dir(path))
    writeLines("secret", path)
    testthat::expect_true(
      micromamba_create_keeps_home(list("pkg"), home = home),
      info = as.character(path)
    )
    fs::file_delete(path)
  }
  # A token directory without tokens is no credential.
  testthat::expect_false(micromamba_create_keeps_home(list("pkg"), home = home))

  env_file_needs_home <- function(lines) {
    path <- withr::local_tempfile(fileext = ".yml")
    writeLines(lines, path)
    return(micromamba_create_keeps_home(list("-f", path), home = home))
  }
  plain <- c(
    "channels:",
    "  - conda-forge",
    "dependencies:",
    "  - python>=3.10"
  )
  testthat::expect_false(env_file_needs_home(plain))
  testthat::expect_false(env_file_needs_home(c(plain, "  - pip")))
  testthat::expect_false(env_file_needs_home(c(plain, "  - numpy~=1.26")))
  testthat::expect_false(env_file_needs_home(c(plain, "  - homebrew-tools")))
  testthat::expect_true(env_file_needs_home(c(plain, "  - pip:", "    - six")))
  testthat::expect_true(env_file_needs_home(c(
    "package:",
    "  - name: six",
    "    manager: pip"
  )))
  # A mambajs lock file (JSON), whose pip packages micromamba installs with
  # pip too.
  mambajs <- withr::local_tempfile(fileext = ".json")
  writeLines(
    c(
      "{",
      "  \"lockVersion\": \"1.0.0\",",
      "  \"platform\": \"linux-64\",",
      "  \"channels\": [\"conda-forge\"],",
      "  \"packages\": {},",
      "  \"pipPackages\": {\"six-1.16.0-py2.py3-none-any.whl\": {}}",
      "}"
    ),
    mambajs
  )
  testthat::expect_true(micromamba_create_keeps_home(
    list("-f", mambajs),
    home = home
  ))
  testthat::expect_true(env_file_needs_home(c("channels:", "  - ~/my-channel")))
  testthat::expect_true(env_file_needs_home(c("channels:", "  - ${HOME}/ch")))
  testthat::expect_true(env_file_needs_home(c(
    "channels:",
    "  - %USERPROFILE%\\ch"
  )))
  testthat::expect_true(micromamba_create_keeps_home(
    list("-f", fs::path(home, "missing.yml")),
    home = home
  ))
})

test_that("micromamba_expand_home() expands ~ as micromamba does", {
  home <- if (isTRUE(is_windows())) "C:\\Users\\u" else "/home/u"
  testthat::expect_identical(
    micromamba_expand_home(
      c("~", "~/ch", "~user/ch", "a~/b", "conda-forge", NA),
      home = home
    ),
    c(home, paste0(home, "/ch"), "~user/ch", "a~/b", "conda-forge", NA)
  )
  windows_form <- micromamba_expand_home("~\\ch", home = home)
  if (isTRUE(is_windows())) {
    testthat::expect_identical(windows_form, paste0(home, "\\ch"))
  } else {
    testthat::expect_identical(windows_form, "~\\ch")
  }
  testthat::expect_identical(
    micromamba_expand_home(character(0L)),
    character(0L)
  )
  testthat::expect_identical(
    format_channels_args("~/ch", "conda-forge"),
    c("-c", paste0(micromamba_user_home(), "/ch"), "-c", "conda-forge")
  )
})

test_that("micromamba run gets a basename when the session's PATH has none", {
  # Regression test (R-4 g): micromamba's shell hook runs `basename`.
  # Without it on PATH, `micromamba run` activated nothing, and the command
  # ran without activation.
  testthat::expect_null(micromamba_run_path("/a:/b", on_windows = TRUE))
  tool_dir <- withr::local_tempdir()
  fs::file_create(fs::path(tool_dir, "basename"))
  fs::file_chmod(fs::path(tool_dir, "basename"), "u+x")
  testthat::expect_null(micromamba_run_path(
    paste("/nowhere", tool_dir, sep = ":"),
    on_windows = FALSE
  ))
  sh_only <- withr::local_tempdir()
  testthat::expect_identical(
    micromamba_run_path(
      sh_only,
      on_windows = FALSE,
      system_dirs = c("/nowhere", tool_dir)
    ),
    paste(sh_only, tool_dir, sep = ":")
  )
  testthat::expect_null(micromamba_run_path(
    sh_only,
    on_windows = FALSE,
    system_dirs = "/nowhere"
  ))
})

test_that("micromamba starts when its default root prefix is not a Conda prefix", {
  testthat::skip_on_cran()
  # Regression test (TD5): micromamba 2.8.1 to 2.10.0 abort (status 134,
  # even for `--version`) when the default root prefix, `<user data>/mamba`
  # (on Windows too, through `XDG_DATA_HOME`), exists but is not a Conda
  # prefix, whatever `-r` says. Then no micromamba binary was usable, and
  # installing one failed. Every micromamba process of condathis now gets
  # `MAMBA_ROOT_PREFIX`; the commands of environments keep it empty.
  # The managed binary of the test process: a micromamba installed in a
  # Conda environment (such as `micromamba-env`, or one from pixi) takes
  # that environment's root as its default, and never fails this way.
  umamba_path <- micromamba_bin_path()
  if (isFALSE(fs::file_exists(umamba_path))) {
    # The managed binary is downloaded, whatever other micromamba there is.
    testthat::skip_if_offline()
    suppressMessages(install_micromamba(verbose = "silent"))
  }
  withr::local_options(condathis.micromamba_path = as.character(umamba_path))
  condathis::with_sandbox_dir({
    fixture_dirs <- c(
      fs::path(Sys.getenv("XDG_DATA_HOME"), "mamba"),
      fs::path_home("micromamba")
    )
    raw_env <- Sys.getenv()
    raw_env <- raw_env[!names(raw_env) %in% "MAMBA_ROOT_PREFIX"]
    # Without the variable, and before these directories exist, micromamba
    # starts and names its default root prefix: one of them.
    info <- processx::run(
      as.character(umamba_path),
      c("--no-rc", "--no-env", "info", "--json"),
      env = raw_env,
      error_on_status = FALSE
    )
    testthat::expect_identical(info$status, 0L)
    real_path <- function(path) {
      path <- fs::path_tidy(path)
      return(as.character(
        fs::path(fs::path_real(fs::path_dir(path)), fs::path_file(path))
      ))
    }
    testthat::expect_true(
      real_path(jsonlite::fromJSON(info$stdout)[["base environment"]]) %in%
        vapply(fixture_dirs, real_path, character(1L), USE.NAMES = FALSE)
    )
    for (dir in fixture_dirs) {
      fs::dir_create(dir)
      writeLines("not a conda prefix", fs::path(dir, "notes.txt"))
    }
    # micromamba itself then refuses to start without the variable. It
    # aborts, and on macOS every abort writes a crash report to
    # `~/Library/Logs/DiagnosticReports`, so this probe runs on the other
    # systems only: the check above shows that the directories are the
    # default root prefix on macOS too.
    if (isFALSE(is_macos())) {
      raw <- processx::run(
        as.character(umamba_path),
        c("--no-rc", "--no-env", "--version"),
        env = raw_env,
        error_on_status = FALSE
      )
      testthat::expect_false(identical(raw$status, 0L))
      testthat::expect_match(
        raw$stderr,
        "not a conda prefix|Bad expected access",
        ignore.case = TRUE
      )
    }

    testthat::expect_match(get_micromamba_version(umamba_path), "^2\\.")
    testthat::expect_identical(
      as.character(get_best_micromamba_path()),
      as.character(umamba_path)
    )
    env_name <- "native-cmd-root-env"
    channel <- polyglot_channel()
    res <- create_env(
      "polyglot",
      env_name = env_name,
      channels = channel,
      verbose = "silent"
    )
    testthat::expect_identical(res$status, 0L)
    res <- install_packages(
      "polyglot",
      env_name = env_name,
      channels = channel,
      verbose = "silent"
    )
    testthat::expect_identical(res$status, 0L)
    testthat::expect_identical(
      list_envs(method = "micromamba")$env_name,
      env_name
    )
    testthat::expect_true("polyglot" %in% list_packages(env_name)$name)
    testthat::expect_true(rlang::is_string(micromamba_native_platform()))
    testthat::expect_identical(
      parse_output(run("polyglot", env_name = env_name, verbose = "silent"))[[
        1L
      ]],
      polyglot_expected_line()
    )
    rscript <- get_condathis_rscript_path()
    print_root <- c(
      "--vanilla",
      "-e",
      "cat(Sys.getenv('MAMBA_ROOT_PREFIX', 'unset'))"
    )
    testthat::expect_identical(
      run(rscript, print_root, env_name = env_name, verbose = "silent")$stdout,
      ""
    )
    testthat::expect_identical(
      run_bin(
        rscript,
        print_root,
        env_name = env_name,
        verbose = "silent"
      )$stdout,
      ""
    )
    pipeline_res <- run_pipeline(
      run_step(rscript, print_root),
      run_step(rscript, "--vanilla", "-e", "cat(readLines(file('stdin')))"),
      env_name = env_name,
      verbose = "silent"
    )
    testthat::expect_identical(parse_output(pipeline_res), character(0L))
    testthat::expect_identical(
      remove_env(env_name, verbose = "silent")$status,
      0L
    )
    testthat::expect_identical(clean_cache(verbose = "silent")$status, 0L)
  })
})

test_that("native_cmd() turns off the Start Menu shortcuts of micromamba", {
  # Regression test (footprint): on Windows, micromamba added a Start Menu
  # shortcut for each `Menu/*.json` of a linked package, in the Programs
  # known folder of the user, which no environment variable moves. The
  # condathis configuration file now sets `shortcuts: false`.
  testthat::skip_on_cran()
  local_sandbox_micromamba()
  condathis::with_sandbox_dir({
    root <- as.character(install_dir_for_backend(micromamba_backend()))
    rc_path <- ensure_condathis_rc_file(root)
    testthat::expect_true("shortcuts: false" %in% readLines(rc_path))
    res <- native_cmd(
      "config",
      c("list", "shortcuts", "--sources"),
      verbose = "silent"
    )
    out <- parse_output(res)
    line <- out[grepl("^shortcuts:", out)]
    testthat::expect_length(line, 1L)
    testthat::expect_match(line, "^shortcuts: false")
    testthat::expect_match(line, "condathis-micromamba.yaml", fixed = TRUE)
  })
})
