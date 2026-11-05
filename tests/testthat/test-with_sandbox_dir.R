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
      testthat::expect_equal(
        Sys.getenv("R_USER_CONFIG_DIR"),
        Sys.getenv("XDG_CONFIG_HOME")
      )
    })
  }
  wrapper_fn()
})

testthat::test_that("with_sandbox_dir isolates the configuration and state directories", {
  # Regression test (footprint): `XDG_CONFIG_HOME` and `XDG_STATE_HOME`
  # kept the session's values, and micromamba's package extraction read
  # the Conda configuration files of the real `XDG_CONFIG_HOME`.
  withr::local_envvar(
    XDG_CONFIG_HOME = "/outer/config",
    XDG_STATE_HOME = "/outer/state",
    R_USER_CONFIG_DIR = "/outer/r-config"
  )
  with_sandbox_dir({
    sandbox <- fs::path_dir(Sys.getenv("HOME"))
    for (name in c("XDG_CONFIG_HOME", "XDG_STATE_HOME", "R_USER_CONFIG_DIR")) {
      value <- Sys.getenv(name)
      testthat::expect_true(fs::dir_exists(value), info = name)
      testthat::expect_identical(
        as.character(fs::path_dir(value)),
        as.character(sandbox),
        info = name
      )
    }
  })
  testthat::expect_identical(Sys.getenv("XDG_CONFIG_HOME"), "/outer/config")
  testthat::expect_identical(Sys.getenv("XDG_STATE_HOME"), "/outer/state")
  testthat::expect_identical(Sys.getenv("R_USER_CONFIG_DIR"), "/outer/r-config")
})

testthat::test_that("with_sandbox_dir creates real, existing directories", {
  wrapper_fn <- function() {
    with_sandbox_dir({
      testthat::expect_true(fs::dir_exists(Sys.getenv("HOME")))
      testthat::expect_true(fs::dir_exists(Sys.getenv("XDG_DATA_HOME")))
      testthat::expect_true(fs::dir_exists(Sys.getenv("XDG_CACHE_HOME")))
      testthat::expect_true(fs::dir_exists(Sys.getenv("XDG_CONFIG_HOME")))
      testthat::expect_true(fs::dir_exists(Sys.getenv("XDG_STATE_HOME")))
    })
  }
  wrapper_fn()
})

testthat::test_that("with_sandbox_dir restores everything before it returns", {
  # Regression test: the overrides and directories were scoped to the
  # caller's frame. At top level, as in examples, HOME stayed sandboxed and
  # the directories stayed on disk for the rest of the session.
  old_envvars <- Sys.getenv()
  old_wd <- getwd()
  sandbox_home <- NULL

  with_sandbox_dir({
    sandbox_home <- Sys.getenv("HOME")
    Sys.setenv(CONDATHIS_SANDBOX_TEST_ADDED = "added")
    Sys.setenv(LANG = "condathis-sandbox-test")
    Sys.unsetenv("PATH")
    setwd(sandbox_home)
  })

  testthat::expect_identical(Sys.getenv(), old_envvars)
  testthat::expect_identical(getwd(), old_wd)
  testthat::expect_false(fs::dir_exists(sandbox_home))
})

testthat::test_that("with_sandbox_dir cleans up after an error", {
  old_envvars <- Sys.getenv()
  sandbox_home <- NULL

  testthat::expect_error(
    with_sandbox_dir({
      sandbox_home <- Sys.getenv("HOME")
      stop("error inside the sandbox")
    }),
    "error inside the sandbox"
  )

  testthat::expect_identical(Sys.getenv(), old_envvars)
  testthat::expect_false(fs::dir_exists(sandbox_home))
})

# Starts `Rscript` with `args` and waits until it has written its process
# ID to `pid_file`: on macOS, the environment of a process that has not
# finished starting cannot be read. Returns a list: `proc`, the `processx`
# process, and `r_pid`, the ID that R itself reports (on Windows,
# `Rscript.exe` runs R as a child process).
start_r_sleeper <- function(args, pid_file, env = NULL) {
  proc <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    args,
    env = env
  )
  r_pid <- wait_for_pid_file(pid_file)
  testthat::expect_false(is.na(r_pid))
  return(list(proc = proc, r_pid = r_pid))
}

# The process ID written to `pid_file`, or `NA` after 10 seconds.
wait_for_pid_file <- function(pid_file) {
  for (i in seq_len(100L)) {
    if (isTRUE(file.exists(pid_file))) {
      pid <- suppressWarnings(as.integer(readLines(pid_file, warn = FALSE)))
      if (isTRUE(length(pid) == 1L && !is.na(pid))) {
        return(pid)
      }
    }
    Sys.sleep(0.1)
  }
  return(NA_integer_)
}

# A killed process can take a moment to go away: Windows ends it
# asynchronously, and on Linux it is a zombie until it is reaped
# (`run_family_pid_running()` does not count a zombie).
wait_until_gone <- function(pid) {
  for (i in seq_len(50L)) {
    if (isFALSE(run_family_pid_running(pid))) {
      break
    }
    Sys.sleep(0.1)
  }
  return(!run_family_pid_running(pid))
}

# R code that writes the process ID to the file named by the first
# argument, then sleeps.
sleeper_code <- paste(
  "writeLines(as.character(Sys.getpid()), commandArgs(TRUE)[[1L]]);",
  "Sys.sleep(60)"
)

# A file with `code`, for `Rscript <file>`. The tests kill these children,
# and on Windows a killed `Rscript -e` leaves its code behind in a file
# `Rscript<hex>` in `TMPDIR`. Create the file before the process, so that
# the process is killed before the file is deleted.
local_r_script <- function(code, .local_envir = parent.frame()) {
  path <- withr::local_tempfile(fileext = ".R", .local_envir = .local_envir)
  writeLines(code, path)
  return(path)
}

testthat::test_that("with_sandbox_dir stops the processes that use the sandbox", {
  # The R children that this test kills cannot delete their temporary
  # directories.
  local_child_tempdir()
  rscript <- file.path(R.home("bin"), "Rscript")
  sleeper_script <- local_r_script(sleeper_code)
  started_before <- processx::process$new(
    rscript,
    local_r_script("Sys.sleep(60)")
  )
  withr::defer(started_before$kill())
  outside_dir <- withr::local_tempdir()
  script_child <- NULL
  env_child <- NULL
  grandchild_pid <- NULL
  with_sandbox_dir({
    # Scripts inside the sandbox: a path on the command line ties a process
    # to the sandbox, as `-r <root>` does for micromamba.
    scripts_dir <- file.path(Sys.getenv("HOME"), "scripts")
    dir.create(scripts_dir)
    sleeper <- file.path(scripts_dir, "sleeper.R")
    spawner <- file.path(scripts_dir, "spawner.R")
    writeLines(
      c(
        "writeLines(as.character(Sys.getpid()), commandArgs(TRUE)[[1L]])",
        "Sys.sleep(60)"
      ),
      sleeper
    )
    writeLines(
      c(
        "args <- commandArgs(TRUE)",
        # `system2(wait = FALSE)` does not outlive this script on Windows.
        "processx::process$new(args[[1L]], args[-1L], cleanup = FALSE)"
      ),
      spawner
    )
    script_child <- start_r_sleeper(
      c(sleeper, file.path(outside_dir, "script-child.pid")),
      file.path(outside_dir, "script-child.pid")
    )
    # Nothing on the command line names the sandbox, but the process runs
    # in an environment inside it, as `micromamba run` children do.
    env_child <- start_r_sleeper(
      c(sleeper_script, file.path(outside_dir, "env-child.pid")),
      file.path(outside_dir, "env-child.pid"),
      env = c(
        "current",
        CONDA_PREFIX = file.path(
          Sys.getenv("XDG_DATA_HOME"),
          "condathis",
          "envs",
          "sandbox-test-env"
        )
      )
    )
    # A grandchild whose parent has exited: only the marker finds it.
    grandchild_pid_file <- file.path(outside_dir, "grandchild.pid")
    # No pipes: the grandchild would hold them open, and `run()` waits for
    # every holder to close them.
    processx::run(
      rscript,
      c(spawner, rscript, sleeper, grandchild_pid_file),
      env = c(
        "current",
        R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)
      ),
      stdout = NULL,
      stderr = NULL
    )
    grandchild_pid <- wait_for_pid_file(grandchild_pid_file)
    # Without a PID, `ps::ps_handle(NA)` would fail for another reason.
    testthat::expect_false(is.na(grandchild_pid))
    testthat::expect_true(script_child$proc$is_alive())
    testthat::expect_true(env_child$proc$is_alive())
    testthat::expect_true(run_family_pid_running(grandchild_pid))
  })
  script_child$proc$wait(timeout = 5000)
  env_child$proc$wait(timeout = 5000)
  testthat::expect_false(script_child$proc$is_alive())
  testthat::expect_false(env_child$proc$is_alive())
  testthat::expect_true(wait_until_gone(script_child$r_pid))
  testthat::expect_true(wait_until_gone(env_child$r_pid))
  testthat::expect_true(wait_until_gone(grandchild_pid))
  # Processes started before the sandbox are left alone.
  testthat::expect_true(started_before$is_alive())
})

testthat::test_that("with_sandbox_dir leaves session helpers started inside it running", {
  # Regression test: the cleanup stopped every process started inside the
  # sandbox. A session helper first started there, such as a `callr`
  # session or a `mirai` daemon, was dead after the block. This one only
  # inherits the sandbox's `HOME` and its marker variable.
  outside_dir <- withr::local_tempdir()
  # The R children that this test kills cannot delete their temporary
  # directories.
  local_child_tempdir()
  sleeper_script <- local_r_script(sleeper_code)
  helper <- NULL
  with_sandbox_dir({
    helper <- start_r_sleeper(
      c(sleeper_script, file.path(outside_dir, "helper.pid")),
      file.path(outside_dir, "helper.pid")
    )
  })
  withr::defer(helper$proc$kill_tree())
  testthat::expect_true(helper$proc$is_alive())
  testthat::expect_true(run_family_pid_running(helper$r_pid))
})

testthat::test_that("with_sandbox_dir leaves the processx supervisor running", {
  # Regression test: the cleanup stopped the `processx` supervisor when the
  # first `supervise = TRUE` process of the session ran inside the sandbox.
  # `processx` only checks that it knows a supervisor ID, so every later
  # supervised process had no crash cleanup.
  rscript <- file.path(R.home("bin"), "Rscript")
  # The R children that this test kills cannot delete their temporary
  # directories.
  local_child_tempdir()
  # The supervisor must start inside the sandbox, so stop the one an
  # earlier test may have started.
  processx:::supervisor_reset()
  with_sandbox_dir({
    inside <- processx::process$new(
      rscript,
      c("-e", "invisible()"),
      supervise = TRUE
    )
    inside$wait(timeout = 10000)
  })
  supervisor_pid <- processx:::supervisor_info$pid
  testthat::expect_length(supervisor_pid, 1L)

  later <- processx::process$new(
    rscript,
    local_r_script("Sys.sleep(60)"),
    supervise = TRUE
  )
  withr::defer(later$kill())
  # The later process is watched by the same supervisor, which still runs.
  testthat::expect_identical(processx:::supervisor_info$pid, supervisor_pid)
  testthat::expect_true(run_family_pid_running(supervisor_pid))

  # Both ways of recognizing the supervisor work on this platform.
  handle <- ps::ps_handle(supervisor_pid)
  testthat::expect_identical(processx_supervisor_pid(), supervisor_pid)
  testthat::expect_true(is_processx_supervisor(
    handle,
    supervisor_pid = supervisor_pid,
    supervisor_exe = NA_character_
  ))
  testthat::expect_true(is_processx_supervisor(
    handle,
    supervisor_pid = NULL,
    supervisor_exe = processx_supervisor_exe()
  ))
  testthat::expect_false(is_processx_supervisor(
    ps::ps_handle(),
    supervisor_pid = supervisor_pid,
    supervisor_exe = processx_supervisor_exe()
  ))
})

testthat::test_that("process_uses_sandbox() needs a sandbox path, not an inherited HOME", {
  root <- "/tmp/Rtmp1/condathis-sandbox-1a2b"
  inherited <- c(
    HOME = file.path(root, "home"),
    XDG_DATA_HOME = file.path(root, "data"),
    R_USER_CACHE_DIR = file.path(root, "cache"),
    CONDA_ENVS_PATH = "/home/user/.conda/envs"
  )
  uses <- function(exe, cmdline, environ = inherited) {
    return(process_uses_sandbox(
      exe = exe,
      cmdline = cmdline,
      environ = environ,
      root_forms = root,
      windows = FALSE
    ))
  }

  # micromamba from outside the sandbox, run with `-r <root>`.
  testthat::expect_true(uses(
    "/opt/bin/micromamba",
    c("/opt/bin/micromamba", "-r", file.path(root, "data", "condathis"), "run")
  ))
  testthat::expect_true(uses(
    "/opt/bin/micromamba",
    c("micromamba", paste0("--rc-file=", root, "/data/condathis/.mambarc"))
  ))
  # A binary of an environment in the sandbox.
  testthat::expect_true(uses(
    file.path(root, "data", "condathis", "envs", "e", "bin", "samtools"),
    "samtools"
  ))
  # A system binary started by an environment's command.
  testthat::expect_true(uses(
    "/usr/bin/sleep",
    c("sleep", "60"),
    c(inherited, CONDA_PREFIX = file.path(root, "data/condathis/envs/e"))
  ))
  testthat::expect_true(uses(
    "/usr/bin/sleep",
    c("sleep", "60"),
    c(
      inherited,
      CONDA_PKGS_DIRS = paste0("/elsewhere:", root, "/data/condathis/pkgs")
    )
  ))
  # The root itself, at the end of a string.
  testthat::expect_true(uses("/bin/ls", c("ls", root)))

  # The processx supervisor, a callr session or a mirai daemon: only the
  # variables `with_sandbox_dir()` sets point inside the sandbox.
  testthat::expect_false(uses(
    "/usr/lib/R/library/processx/bin/supervisor",
    c("supervisor", "-p", "123", "-i", "/tmp/Rtmp1/supervisor_stdin_1")
  ))
  testthat::expect_false(uses(
    "/usr/lib/R/bin/exec/R",
    c("R", "-e", "mirai::daemon('abstract://x')")
  ))
  testthat::expect_false(uses(NA_character_, character(), character()))
  # Another sandbox whose name starts with this one's name.
  testthat::expect_false(uses(
    "/usr/bin/Rscript",
    c("Rscript", paste0(root, "9/home/script.R"))
  ))
  testthat::expect_false(uses("/usr/bin/sleep", c("sleep", "60"), inherited))
})

testthat::test_that("process_uses_sandbox() compares Windows paths without case or separator differences", {
  root_forms <- canonical_path_string(
    "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\Rtmp1\\condathis-sandbox-1a2b",
    windows = TRUE
  )
  testthat::expect_identical(
    root_forms,
    "c:/users/runner~1/appdata/local/temp/rtmp1/condathis-sandbox-1a2b"
  )
  testthat::expect_true(process_uses_sandbox(
    exe = paste0(
      "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\Rtmp1\\",
      "condathis-sandbox-1a2b\\data\\envs\\e\\Library\\bin\\tool.exe"
    ),
    cmdline = "tool.exe",
    environ = character(),
    root_forms = root_forms,
    windows = TRUE
  ))
  # Environment variable names do not depend on case on Windows.
  testthat::expect_true(process_uses_sandbox(
    exe = "C:\\Windows\\System32\\cmd.exe",
    cmdline = "cmd.exe",
    environ = c(
      Conda_Prefix = paste0(
        "c:/users/runner~1/appdata/local/temp/rtmp1/",
        "condathis-sandbox-1a2b/data/envs/e"
      )
    ),
    root_forms = root_forms,
    windows = TRUE
  ))
  testthat::expect_false(process_uses_sandbox(
    exe = "C:\\Windows\\System32\\cmd.exe",
    cmdline = "cmd.exe",
    environ = c(
      USERPROFILE = paste0(
        "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\Rtmp1\\",
        "condathis-sandbox-1a2b\\home"
      )
    ),
    root_forms = root_forms,
    windows = TRUE
  ))
  # Elsewhere, case matters.
  testthat::expect_false(process_uses_sandbox(
    exe = "/TMP/RTMP1/CONDATHIS-SANDBOX-1A2B/bin/tool",
    cmdline = "tool",
    environ = character(),
    root_forms = "/tmp/Rtmp1/condathis-sandbox-1a2b",
    windows = FALSE
  ))
})

testthat::test_that("sandbox_root_forms() includes the real path of the root", {
  root <- withr::local_tempdir()
  forms <- sandbox_root_forms(root)
  testthat::expect_true(canonical_path_string(root) %in% forms)
  testthat::expect_true(
    canonical_path_string(as.character(fs::path_real(root))) %in% forms
  )
  # `with_sandbox_dir()` builds `HOME` and the `XDG_*` paths with
  # `fs::path()`.
  testthat::expect_true(
    canonical_path_string(as.character(fs::path(root))) %in% forms
  )
  testthat::expect_false(any(endsWith(forms, "/")))

  # An existing root spelled with two separators, as `tempfile()` spells it
  # on macOS.
  doubled <- paste0(root, "//", "condathis-sandbox-1")
  dir.create(doubled)
  doubled_forms <- sandbox_root_forms(doubled)
  testthat::expect_true(all(mentions_sandbox(
    c(
      as.character(fs::path(doubled, "home", "script.R")),
      file.path(doubled, "data"),
      file.path(as.character(fs::path_real(doubled)), "cache")
    ),
    root_forms = doubled_forms
  )))
})

testthat::test_that("a sandbox path matches the root whatever its number of separators", {
  # Regression test: on macOS, `TMPDIR` ends with `/` and `/var` is a
  # symbolic link to `/private/var`. `tempfile()` gave the root
  # `/var/folders/x/T//Rtmp1/condathis-sandbox-1`, its real path started
  # with `/private/var`, but the sandbox's `HOME`, built with `fs::path()`,
  # was `/var/folders/x/T/Rtmp1/condathis-sandbox-1/home`. No root form
  # matched that spelling, so processes that named the sandbox through
  # `HOME` or `XDG_DATA_HOME` kept running. The root does not exist here,
  # so only its spelling is compared, as for the symbolic link on macOS.
  root <- "/var/folders/x/T//Rtmp1/condathis-sandbox-1"
  forms <- sandbox_root_forms(root, windows = FALSE)
  testthat::expect_true(mentions_sandbox(
    as.character(fs::path(root, "home", "scripts", "sleeper.R")),
    root_forms = forms,
    windows = FALSE
  ))
  testthat::expect_true(process_uses_sandbox(
    exe = "/usr/bin/sleep",
    cmdline = c("sleep", "60"),
    environ = c(
      CONDA_PREFIX = "/var/folders/x/T/Rtmp1/condathis-sandbox-1/data/envs/e"
    ),
    root_forms = forms,
    windows = FALSE
  ))
  # The root itself, and separators doubled anywhere in a process's string.
  testthat::expect_true(all(mentions_sandbox(
    c(
      "/var/folders/x/T/Rtmp1/condathis-sandbox-1",
      "/var//folders/x/T///Rtmp1//condathis-sandbox-1//home"
    ),
    root_forms = forms,
    windows = FALSE
  )))
  testthat::expect_false(mentions_sandbox(
    "/var/folders/x/T/Rtmp1/condathis-sandbox-12/home",
    root_forms = forms,
    windows = FALSE
  ))

  # On Windows, `\` and `/` runs are one separator too.
  win_root <- paste0(
    "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\\\Rtmp1\\",
    "condathis-sandbox-1"
  )
  win_forms <- sandbox_root_forms(win_root, windows = TRUE)
  testthat::expect_true(all(mentions_sandbox(
    c(
      as.character(fs::path(win_root, "home")),
      "c:/users/runner~1/appdata/local/temp/rtmp1/condathis-sandbox-1/data",
      "C:\\Users\\RUNNER~1\\AppData\\Local\\Temp\\Rtmp1\\condathis-sandbox-1"
    ),
    root_forms = win_forms,
    windows = TRUE
  )))
})

testthat::test_that("canonical_path_string() writes one separator for each run", {
  testthat::expect_identical(
    canonical_path_string(
      c("/var/folders/x/T//Rtmp1///a/", "/tmp/a", NA_character_),
      windows = FALSE
    ),
    c("/var/folders/x/T/Rtmp1/a/", "/tmp/a", NA_character_)
  )
  testthat::expect_identical(
    canonical_path_string("C:\\Temp\\\\Rtmp1/\\A", windows = TRUE),
    "c:/temp/rtmp1/a"
  )
  # A command line that is not valid UTF-8 does not fail the comparison.
  invalid <- "/tmp//\xff\xfe//a"
  testthat::expect_no_error(canonical_path_string(invalid, windows = FALSE))
  testthat::expect_false(mentions_sandbox(
    invalid,
    root_forms = "/tmp/Rtmp1/condathis-sandbox-1",
    windows = FALSE
  ))
})

testthat::test_that("the sandbox cleanup stops a process that names the root with one separator", {
  # Regression test: the cleanup missed a process whose argument named the
  # sandbox with fewer separators than the `tempfile()` spelling of the
  # root (see the test above). Here the whole cleanup path runs: reading
  # the command line with `ps`, comparing it, and stopping the process.
  outside_dir <- withr::local_tempdir()
  # The R children that this test kills cannot delete their temporary
  # directories.
  local_child_tempdir()
  # Never created, so its real path cannot give the one-separator spelling.
  root <- paste0(outside_dir, "//", "condathis-sandbox-1")
  pid_file <- file.path(outside_dir, "one-separator.pid")
  old_descendants <- process_keys(sandbox_descendants())
  marker <- ps::ps_mark_tree()
  withr::defer(Sys.unsetenv(marker))
  child <- start_r_sleeper(
    c(
      local_r_script(sleeper_code),
      pid_file,
      as.character(fs::path(root, "home", "script.R"))
    ),
    pid_file
  )
  withr::defer(child$proc$kill_tree())

  stop_sandbox_processes(
    sandbox_root = root,
    process_marker = marker,
    old_descendants = old_descendants
  )
  child$proc$wait(timeout = 5000)
  testthat::expect_false(child$proc$is_alive())
  testthat::expect_true(wait_until_gone(child$r_pid))
})

testthat::test_that("nested with_sandbox_dir calls restore the outer sandbox", {
  old_envvars <- Sys.getenv()
  outer_home <- NULL
  inner_home <- NULL

  with_sandbox_dir({
    outer_home <- Sys.getenv("HOME")
    with_sandbox_dir({
      inner_home <- Sys.getenv("HOME")
    })
    testthat::expect_identical(Sys.getenv("HOME"), outer_home)
    testthat::expect_true(fs::dir_exists(outer_home))
    testthat::expect_false(fs::dir_exists(inner_home))
  })

  testthat::expect_identical(Sys.getenv(), old_envvars)
  testthat::expect_false(fs::dir_exists(outer_home))
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

testthat::test_that("with_sandbox_dir returns the value of the code", {
  testthat::expect_identical(with_sandbox_dir(Sys.getenv("HOME") != ""), TRUE)
  testthat::expect_visible(with_sandbox_dir(1L))
  testthat::expect_invisible(with_sandbox_dir(invisible(1L)))
})

testthat::test_that("a sandbox that cannot be deleted warns with the new and the old class", {
  # Regression test: the warning had only the old class, without the root
  # class `condathis_warning`. Deleting is mocked, so the test is the same
  # on every platform.
  sandbox_root <- withr::local_tempdir(pattern = "condathis-sandbox-")
  testthat::local_mocked_bindings(
    stop_sandbox_processes = function(...) invisible(list()),
    delete_sandbox_root = function(sandbox_root) FALSE
  )
  cnd <- testthat::expect_warning(
    cleanup_sandbox(
      sandbox_root = sandbox_root,
      process_marker = "unused",
      old_descendants = character(0L),
      old_envvars = Sys.getenv(),
      old_wd = getwd()
    ),
    class = "condathis_with_sandbox_dir_cleanup_failed"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_with_sandbox_dir_cleanup_failed",
      "condathis_sandbox_cleanup_failed",
      "condathis_warning",
      "rlang_warning",
      "warning",
      "condition"
    )
  )
  testthat::expect_match(conditionMessage(cnd), "sandbox directory")
})

testthat::test_that("with_sandbox_dir() restores the session when a value has invalid bytes", {
  # Regression test: `Sys.getenv()` fails on a value that is not valid in
  # the session's encoding ("invalid multibyte string"), which stopped the
  # cleanup: HOME stayed in the sandbox, and the sandbox stayed on disk.
  withr::defer(Sys.unsetenv("CONDATHIS_TEST_BAD_BYTES"))
  old_home <- Sys.getenv("HOME")
  sandbox_home <- NULL
  with_sandbox_dir({
    sandbox_home <- Sys.getenv("HOME")
    # Windows may refuse such a value; the cleanup is checked either way.
    tryCatch(
      Sys.setenv(CONDATHIS_TEST_BAD_BYTES = "caf\xe9"),
      error = function(e) NULL
    )
  })
  testthat::expect_identical(Sys.getenv("HOME"), old_home)
  testthat::expect_identical(
    Sys.getenv("CONDATHIS_TEST_BAD_BYTES", unset = NA),
    NA_character_
  )
  testthat::expect_false(fs::dir_exists(fs::path_dir(sandbox_home)))
})

testthat::test_that("an interrupt while the cleanup waits leaves the session restored", {
  # Regression test: the environment variables and the working directory
  # were restored only after the wait for the backends, so an interrupt
  # there left the session in the sandbox.
  sandbox_root <- withr::local_tempdir(pattern = "condathis-sandbox-")
  old_envvars <- Sys.getenv()
  old_wd <- getwd()
  withr::local_envvar(CONDATHIS_TEST_SANDBOX_VAR = "inside")
  withr::local_dir(withr::local_tempdir())
  events <- character(0L)
  testthat::local_mocked_bindings(
    stop_sandbox_processes = function(...) {
      events <<- c(events, "stop")
      return(invisible(list()))
    },
    quiesce_registered_backends = function(timeout = 30, call = NULL) {
      events <<- c(events, "quiesce")
      rlang::interrupt()
    },
    delete_sandbox_root = function(sandbox_root) {
      events <<- c(events, "delete")
      return(TRUE)
    }
  )
  cnd <- tryCatch(
    cleanup_sandbox(
      sandbox_root = sandbox_root,
      process_marker = "unused",
      old_descendants = character(0L),
      old_envvars = old_envvars,
      old_wd = old_wd
    ),
    interrupt = function(cnd) cnd
  )
  testthat::expect_s3_class(cnd, "interrupt")
  testthat::expect_identical(events, c("stop", "quiesce"))
  testthat::expect_identical(
    Sys.getenv("CONDATHIS_TEST_SANDBOX_VAR", unset = NA),
    NA_character_
  )
  testthat::expect_identical(getwd(), old_wd)
})

testthat::test_that("delete_sandbox_root() reports whether the directory is gone", {
  sandbox_root <- withr::local_tempdir(pattern = "condathis-sandbox-")
  fs::dir_create(fs::path(sandbox_root, "home", "nested"))
  testthat::expect_true(delete_sandbox_root(sandbox_root))
  testthat::expect_false(fs::dir_exists(sandbox_root))
  # Nothing to delete: also gone.
  testthat::expect_true(delete_sandbox_root(sandbox_root))
})

# --- Backends other than micromamba ------------------------------------------

testthat::test_that("with_sandbox_dir() moves the root of a backend with the default root", {
  # A backend without its own `backend_get_install_dir()` keeps its
  # environments in `backend_root_dir(name)`, inside the condathis data
  # directory, so the sandbox moves it, as it moves the micromamba root.
  outside_root <- backend_root_dir("stub-sandboxed")
  outside_existed <- fs::dir_exists(outside_root)
  sandbox_root <- NULL
  inside_root <- NULL
  with_sandbox_dir({
    sandbox_root <- fs::path_real(fs::path_dir(Sys.getenv("HOME")))
    stub <- local_stub_backend(
      "stub-sandboxed",
      envs = "sandboxed-env",
      default_root = TRUE
    )
    inside_root <- backend_root_dir("stub-sandboxed")
    testthat::expect_true(fs::path_has_parent(inside_root, sandbox_root))
    testthat::expect_false(identical(inside_root, outside_root))
    testthat::expect_true(fs::path_has_parent(
      get_install_dir(method = "stub-sandboxed")$path,
      sandbox_root
    ))
    testthat::expect_identical(
      as.character(get_env_dir("sandboxed-env", method = "stub-sandboxed")),
      as.character(fs::path(inside_root, "envs", "sandboxed-env"))
    )
    testthat::expect_identical(
      list_envs(method = "stub-sandboxed")$env_name,
      "sandboxed-env"
    )
    # The package cache of its children is in the sandbox too.
    testthat::expect_true(fs::path_has_parent(
      child_conda_dirs(
        stub$backend,
        env_dir = get_env_dir("sandboxed-env", method = "stub-sandboxed")
      )$pkgs_dir,
      sandbox_root
    ))
  })
  testthat::expect_false(fs::dir_exists(sandbox_root))
  testthat::expect_false(fs::dir_exists(inside_root))
  # Nothing appeared in the root outside the sandbox.
  testthat::expect_identical(fs::dir_exists(outside_root), outside_existed)
})

testthat::test_that("with_sandbox_dir() stops a process that only an activated CONDA_PREFIX ties to it", {
  # The stub's activation sets CONDA_PREFIX to its environment inside the
  # sandbox, and clears the conda directories, so nothing else about the
  # process left running names the sandbox.
  testthat::skip_on_cran()
  daemon <- local_run_family_daemon()
  pid_file <- file.path(daemon$dir, "prefix-child.pid")
  leftover_pid <- NA_integer_
  with_sandbox_dir({
    stub <- local_stub_backend(
      "stub-prefix-child",
      envs = "prefix-env",
      default_root = TRUE,
      backend_resolve_run = function(backend, cmd, args = character(0L), ...) {
        env_dir <- fs::path(
          backend_root_dir("stub-prefix-child"),
          "envs",
          "prefix-env"
        )
        return(list(
          command = cmd,
          args = args,
          env = c(
            CONDA_PREFIX = as.character(env_dir),
            CONDA_ENVS_PATH = "",
            CONDA_PKGS_DIRS = "",
            MAMBA_PKGS_DIRS = ""
          ),
          dir = NULL
        ))
      }
    )
    testthat::local_mocked_bindings(
      backend_names_by_priority = function() "stub-prefix-child"
    )
    # No pipes: the leftover process would hold them open.
    res <- run(
      run_family_rscript(),
      daemon$args(pid_file),
      env_name = "prefix-env",
      stdout = file.path(daemon$dir, "prefix-child.out"),
      stderr = file.path(daemon$dir, "prefix-child.err"),
      verbose = "silent"
    )
    testthat::expect_identical(res$status, 0L)
    leftover_pid <- run_family_read_pid(pid_file)
    testthat::expect_false(is.na(leftover_pid))
    testthat::expect_true(run_family_pid_running(leftover_pid))
  })
  testthat::expect_true(wait_until_gone(leftover_pid))
})

testthat::test_that("with_sandbox_dir() waits for every backend before it deletes the sandbox", {
  # A backend that works in the R process itself (rattler) can still write
  # into the sandbox after an interrupt: the cleanup asks every registered
  # backend to finish first.
  seen <- new.env(parent = emptyenv())
  seen$calls <- list()
  stub <- local_stub_backend(
    "stub-quiesce",
    backend_quiesce = function(backend, timeout = 30) {
      seen$calls[[length(seen$calls) + 1L]] <- list(
        timeout = timeout,
        sandbox_exists = isTRUE(dir.exists(seen$sandbox_root %||% ""))
      )
      return(invisible(TRUE))
    }
  )
  with_sandbox_dir({
    seen$sandbox_root <- dirname(Sys.getenv("HOME"))
  })
  testthat::expect_length(seen$calls, 1L)
  testthat::expect_identical(seen$calls[[1L]]$timeout, 30)
  testthat::expect_true(seen$calls[[1L]]$sandbox_exists)
  testthat::expect_false(dir.exists(seen$sandbox_root))

  # A backend that cannot tell gives a warning, and the sandbox is still
  # deleted.
  failing <- local_stub_backend(
    "stub-quiesce-fails",
    backend_quiesce = function(backend, ...) stop("still busy")
  )
  sandbox_root <- NULL
  cnd <- testthat::expect_warning(
    with_sandbox_dir({
      sandbox_root <- dirname(Sys.getenv("HOME"))
    }),
    class = "condathis_backend_quiesce_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_warning")
  testthat::expect_false(dir.exists(sandbox_root))
  unregister_backend("stub-quiesce-fails")

  # A value that breaks the contract: the error names the user's call.
  # Regression test: it named `quiesce_registered_backends()`.
  invalid <- local_stub_backend(
    "stub-quiesce-invalid",
    backend_quiesce = function(backend, ...) "yes"
  )
  cnd <- testthat::expect_warning(
    with_sandbox_dir(NULL),
    class = "condathis_backend_quiesce_failed"
  )
  testthat::expect_s3_class(cnd$parent, "condathis_backend_invalid_return")
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd$parent)),
    "with_sandbox_dir"
  )
})

testthat::test_that("cleanup_sandbox() quiesces the backends after it stops the processes and before it deletes", {
  sandbox_root <- withr::local_tempdir(pattern = "condathis-sandbox-")
  events <- character(0L)
  testthat::local_mocked_bindings(
    stop_sandbox_processes = function(...) {
      events <<- c(events, "stop")
      return(invisible(list()))
    },
    quiesce_registered_backends = function(timeout = 30, call = NULL) {
      events <<- c(events, "quiesce")
      return(invisible(TRUE))
    },
    delete_sandbox_root = function(sandbox_root) {
      events <<- c(events, "delete")
      return(TRUE)
    }
  )
  cleanup_sandbox(
    sandbox_root = sandbox_root,
    process_marker = "unused",
    old_descendants = character(0L),
    old_envvars = Sys.getenv(),
    old_wd = getwd()
  )
  testthat::expect_identical(events, c("stop", "quiesce", "delete"))

  # An error from the quiesce step does not stop the cleanup.
  events <- character(0L)
  testthat::local_mocked_bindings(
    quiesce_registered_backends = function(timeout = 30, call = NULL) {
      events <<- c(events, "quiesce")
      stop("unexpected")
    }
  )
  testthat::expect_no_error(cleanup_sandbox(
    sandbox_root = sandbox_root,
    process_marker = "unused",
    old_descendants = character(0L),
    old_envvars = Sys.getenv(),
    old_wd = getwd()
  ))
  testthat::expect_identical(events, c("stop", "quiesce", "delete"))
})
