# The lock of an environment (R/env_lock.R): create_env(), install_packages()
# and remove_env() change an environment only while they hold its lock, so
# a second R session waits instead of racing the first. The races run in
# other R sessions (callr, see helper-env-lock.R): the first call is held
# inside its backend function, with the lock, until the test lets it go on,
# and the second must wait without reaching its own backend function.
# Environment names start with "lk-".
#
# On CRAN, of the tests that use a sandbox (with_sandbox_dir()) or other R
# sessions, only the one of the lock file's place runs: each takes about a
# second on Windows, where listing the processes is slow.

testthat::test_that("the lock of an environment is a file in the data directory, outside every environment", {
  with_sandbox_dir({
    path <- env_lock_path("Lk-Env")
    testthat::expect_identical(
      as.character(fs::path_dir(path)),
      as.character(fs::path(get_condathis_path(), "locks"))
    )
    # Lower case, so the spellings that open one directory on macOS and
    # Windows share one lock.
    testthat::expect_identical(as.character(fs::path_file(path)), "lk-env.lock")
    testthat::expect_identical(env_lock_path("lk-env"), path)
    take_lock <- function() {
      local_env_lock("Lk-Env", verbose = "silent")
      return(fs::file_exists(path))
    }
    testthat::expect_true(take_lock())
    # The file stays: deleting it could let two sessions in at once.
    testthat::expect_true(fs::file_exists(path))
    testthat::expect_false(
      fs::dir_exists(fs::path(get_condathis_path(), "envs", "locks"))
    )
  })
})

testthat::test_that("a session that holds the lock gets it again, and releases it when the call ends", {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("callr")
  with_sandbox_dir({
    inner <- function() {
      local_env_lock("lk-nested", verbose = "silent")
      return(env_lock_is_free("lk-nested"))
    }
    outer <- function() {
      local_env_lock("lk-nested", verbose = "silent")
      held_inside <- inner()
      # The inner call released only its own hold.
      return(c(
        inside = held_inside,
        after_inner = env_lock_is_free("lk-nested")
      ))
    }
    testthat::expect_identical(
      outer(),
      c(inside = FALSE, after_inner = FALSE)
    )
    testthat::expect_true(env_lock_is_free("lk-nested"))

    fails <- function() {
      local_env_lock("lk-nested", verbose = "silent")
      stop("lk-boom")
    }
    testthat::expect_error(fails(), "lk-boom")
    testthat::expect_true(env_lock_is_free("lk-nested"))

    interrupted <- function() {
      local_env_lock("lk-nested", verbose = "silent")
      rlang::interrupt()
    }
    cnd <- rlang::catch_cnd(interrupted(), classes = "interrupt")
    testthat::expect_s3_class(cnd, "interrupt")
    testthat::expect_true(env_lock_is_free("lk-nested"))
  })
})

testthat::test_that("clean_cache() keeps the locks, also one that is held", {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("callr")
  with_sandbox_dir({
    path <- env_lock_path("lk-clean")
    hold_and_clean <- function() {
      local_env_lock("lk-clean", verbose = "silent")
      clean_cache(verbose = "silent")
      return(c(
        exists = isTRUE(unname(fs::file_exists(path))),
        held = isFALSE(env_lock_is_free("lk-clean"))
      ))
    }
    testthat::expect_identical(hold_and_clean(), c(exists = TRUE, held = TRUE))
    clean_cache(verbose = "silent")
    testthat::expect_true(fs::file_exists(path))
    testthat::expect_true(env_lock_is_free("lk-clean"))
  })
})

testthat::test_that("a call goes on without the lock where files cannot be locked", {
  testthat::skip_on_cran()
  with_sandbox_dir({
    # A lock directory below a file cannot be created.
    blocker <- fs::path(get_condathis_path(), "not-a-directory")
    fs::dir_create(fs::path_dir(blocker))
    writeLines("x", blocker)
    testthat::local_mocked_bindings(
      env_lock_dir = function() fs::path(blocker, "locks")
    )
    reset_warn_once("env_lock_unavailable")
    withr::defer(reset_warn_once("env_lock_unavailable"))
    local_stub_backend("stub-lk", default_root = TRUE)

    warnings <- list()
    withCallingHandlers(
      create_env(
        env_name = "lk-nolock",
        method = "stub-lk",
        verbose = "silent"
      ),
      warning = function(cnd) {
        warnings[[length(warnings) + 1L]] <<- cnd
        invokeRestart("muffleWarning")
      }
    )
    testthat::expect_length(warnings, 1L)
    testthat::expect_s3_class(warnings[[1L]], "condathis_env_lock_unavailable")
    testthat::expect_s3_class(warnings[[1L]], "condathis_warning")
    testthat::expect_true(env_exists("lk-nolock", method = "stub-lk"))
    # Once per session.
    testthat::expect_no_warning(
      remove_env("lk-nolock", method = "stub-lk", verbose = "silent")
    )
    testthat::expect_false(env_exists("lk-nolock", method = "stub-lk"))
  })
})

testthat::test_that("an interrupt of the wait on Windows is an interrupt, as on Linux and macOS", {
  # filelock turns an interrupt during a wait on Windows into the error
  # "Locking interrupted"; condathis signals it as an interrupt again.
  testthat::local_mocked_bindings(
    lock = function(...) stop("Locking interrupted"),
    .package = "filelock"
  )
  path <- fs::path(withr::local_tempdir(), "locks", "lk-int.lock")
  cnd <- rlang::catch_cnd(
    try_env_lock(path, timeout = 0L),
    classes = "interrupt"
  )
  testthat::expect_s3_class(cnd, "interrupt")

  # Any other error means that the file cannot be locked.
  testthat::local_mocked_bindings(
    lock = function(...) stop("No locks available"),
    .package = "filelock"
  )
  value <- try_env_lock(path, timeout = 0L)
  testthat::expect_s3_class(value, "error")
})

# Starts the call `first` in session `a` and holds it inside its backend
# function, starts `second` in session `b`, checks that `b` waits for the
# lock without reaching its backend function, and lets `a` go on. Each
# call is a list with `fn`, `args` and `hook` (the backend function where
# the call is held, or where it is seen). Returns the outcomes and how long
# `b` took to say that it waits.
race_env_lock <- function(a, b, sync_dir, label, first, second) {
  label_a <- paste0(label, "-a")
  label_b <- paste0(label, "-b")
  start_lock_call(
    a,
    first$fn,
    first$args,
    hook = first$hook,
    sync_dir = sync_dir,
    label = label_a,
    hold = TRUE
  )
  lock_wait_until(
    function() file.exists(lock_marker(sync_dir, label_a, "in")),
    what = paste("the first call of", label)
  )
  b_started <- Sys.time()
  start_lock_call(
    b,
    second$fn,
    second$args,
    hook = second$hook,
    sync_dir = sync_dir,
    label = label_b
  )
  lock_wait_until(
    function() file.exists(lock_marker(sync_dir, label_b, "waiting")),
    what = paste("the second call of", label, "to wait")
  )
  waited <- as.numeric(difftime(Sys.time(), b_started, units = "secs"))
  # The second call has not reached its backend function, and still runs.
  testthat::expect_false(
    file.exists(lock_marker(sync_dir, label_b, "in")),
    label = label
  )
  testthat::expect_identical(b$poll_process(0L), "timeout", label = label)
  file.create(lock_marker(sync_dir, label_a, "go"))
  return(list(
    a = lock_call_outcome(a),
    b = lock_call_outcome(b),
    waited = waited,
    b_reached_backend = file.exists(lock_marker(sync_dir, label_b, "in"))
  ))
}

# The pairs of calls that must not run at once, for `backend` with the
# packages `pkgs` (three names) from `channels`. Each pair names what the
# environment holds before (`before`, `NULL` for no environment), the two
# calls, and the expected outcome: the values of both calls, the class of
# the second call's error, and the packages after (`NULL` for no
# environment).
env_lock_race_cases <- function(env_name, backend, pkgs, channels) {
  common <- list(env_name = env_name, method = backend, verbose = "output")
  with_channels <- c(common, list(channels = channels))
  install <- function(pkg) {
    return(list(
      fn = "install_packages",
      args = c(list(pkg), with_channels),
      hook = "backend_install"
    ))
  }
  overwrite <- function(pkg) {
    return(list(
      fn = "create_env",
      args = c(list(pkg), with_channels, list(overwrite = TRUE)),
      hook = "backend_create_env"
    ))
  }
  remove <- list(fn = "remove_env", args = common, hook = "backend_remove_env")
  return(list(
    `install-remove` = list(
      before = pkgs[[1L]],
      first = install(pkgs[[2L]]),
      second = remove,
      values = c("done", "done"),
      after = NULL
    ),
    `remove-install` = list(
      before = pkgs[[1L]],
      first = remove,
      second = install(pkgs[[2L]]),
      values = c("done", "error"),
      error_class = "condathis_install_packages_env_not_found",
      after = NULL
    ),
    `overwrite-install` = list(
      before = pkgs[[1L]],
      first = overwrite(pkgs[[3L]]),
      second = install(pkgs[[2L]]),
      values = c("done", "done"),
      after = sort(pkgs[2:3])
    ),
    `install-overwrite` = list(
      before = pkgs[[1L]],
      first = install(pkgs[[2L]]),
      second = overwrite(pkgs[[3L]]),
      values = c("done", "done"),
      after = pkgs[[3L]]
    )
  ))
}

# Runs every case of `env_lock_race_cases()`.
run_env_lock_races <- function(a, b, env_name, backend, pkgs, channels) {
  sync_dir <- withr::local_tempdir(pattern = "lk-sync-")
  env_pkgs <- function() {
    if (isFALSE(env_exists(env_name, method = backend))) {
      return(NULL)
    }
    return(sort(
      list_packages(env_name, method = backend, verbose = "silent")$name
    ))
  }
  cases <- env_lock_race_cases(env_name, backend, pkgs, channels)
  for (case_name in names(cases)) {
    case <- cases[[case_name]]
    if (isTRUE(env_exists(env_name, method = backend))) {
      remove_env(env_name, method = backend, verbose = "silent")
    }
    create_env(
      case$before,
      env_name = env_name,
      channels = channels,
      method = backend,
      verbose = "silent"
    )
    raced <- race_env_lock(
      a,
      b,
      sync_dir = sync_dir,
      label = paste0(backend, "-", case_name),
      first = case$first,
      second = case$second
    )
    info <- paste(
      backend,
      case_name,
      raced$a$error_message,
      raced$b$error_message
    )
    testthat::expect_identical(
      c(raced$a$value, raced$b$value),
      case$values,
      info = info
    )
    testthat::expect_true(raced$b$waited, info = info)
    testthat::expect_false(raced$a$waited, info = info)
    # The message comes after a short wait.
    testthat::expect_gte(raced$waited, env_lock_notice_ms() / 1000 - 0.1)
    if (isFALSE(is.null(case$error_class))) {
      testthat::expect_true(
        case$error_class %in% raced$b$error_class,
        info = info
      )
    }
    testthat::expect_identical(env_pkgs(), case$after, info = info)
  }
  return(invisible(NULL))
}

testthat::test_that("two sessions never change one environment at once (stub backend)", {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("callr")
  register_lock_stub(env = environment())
  withr::defer({
    root <- backend_root_dir("lockstub")
    if (isTRUE(fs::dir_exists(root))) {
      fs::dir_delete(root)
    }
  })
  a <- local_lock_session()
  b <- local_lock_session()
  a$run(register_lock_stub)
  b$run(register_lock_stub)

  run_env_lock_races(
    a,
    b,
    env_name = "lk-stub-env",
    backend = "lockstub",
    pkgs = c("lk-one", "lk-two", "lk-three"),
    channels = "conda-forge"
  )

  # Two creates of one new environment: the second finds the first's
  # environment, which has its packages, and keeps it.
  sync_dir <- withr::local_tempdir(pattern = "lk-sync-")
  remove_env("lk-stub-env", method = "lockstub", verbose = "silent")
  create_call <- list(
    fn = "create_env",
    args = list(
      "lk-one",
      env_name = "lk-stub-env",
      method = "lockstub",
      verbose = "output"
    ),
    hook = "backend_create_env"
  )
  raced <- race_env_lock(
    a,
    b,
    sync_dir = sync_dir,
    label = "create-create",
    first = create_call,
    second = create_call
  )
  testthat::expect_identical(c(raced$a$value, raced$b$value), c("done", "done"))
  testthat::expect_false(raced$b_reached_backend)
  testthat::expect_identical(
    list_packages("lk-stub-env", method = "lockstub", verbose = "silent")$name,
    "lk-one"
  )

  # With `verbose = "silent"`, the second call waits without a message.
  label_a <- "silent-a"
  label_b <- "silent-b"
  start_lock_call(
    a,
    "install_packages",
    list(
      "lk-two",
      env_name = "lk-stub-env",
      method = "lockstub",
      verbose = "silent"
    ),
    hook = "backend_install",
    sync_dir = sync_dir,
    label = label_a,
    hold = TRUE
  )
  lock_wait_until(function() file.exists(lock_marker(sync_dir, label_a, "in")))
  start_lock_call(
    b,
    "remove_env",
    list(env_name = "lk-stub-env", method = "lockstub", verbose = "silent"),
    hook = "backend_remove_env",
    sync_dir = sync_dir,
    label = label_b
  )
  Sys.sleep(env_lock_notice_ms() / 1000 + 1)
  testthat::expect_identical(b$poll_process(0L), "timeout")
  testthat::expect_false(file.exists(lock_marker(sync_dir, label_b, "in")))
  file.create(lock_marker(sync_dir, label_a, "go"))
  out_a <- lock_call_outcome(a)
  out_b <- lock_call_outcome(b)
  testthat::expect_identical(c(out_a$value, out_b$value), c("done", "done"))
  testthat::expect_identical(out_b$messages, character(0L))
  testthat::expect_false(env_exists("lk-stub-env", method = "lockstub"))
})

testthat::test_that("an interrupt stops the wait for a lock, and of the session that holds it releases it", {
  # The interrupts are signals to other R sessions (see
  # `interrupt_lock_session()`), so whether they arrive depends on how the
  # check was started (see `lock_session_ignores_interrupt()`).
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("callr")
  if (isTRUE(lock_session_ignores_interrupt())) {
    testthat::skip(
      "The R sessions of this process ignore interrupts (SIGINT is ignored)."
    )
  }
  register_lock_stub(env = environment())
  withr::defer({
    root <- backend_root_dir("lockstub")
    if (isTRUE(fs::dir_exists(root))) {
      fs::dir_delete(root)
    }
  })
  a <- local_lock_session()
  b <- local_lock_session()
  a$run(register_lock_stub)
  b$run(register_lock_stub)
  sync_dir <- withr::local_tempdir(pattern = "lk-sync-")
  env_name <- "lk-int-env"
  create_env(
    "lk-one",
    env_name = env_name,
    method = "lockstub",
    verbose = "silent"
  )
  call_args <- function(...) {
    return(list(
      ...,
      env_name = env_name,
      method = "lockstub",
      verbose = "output"
    ))
  }

  # The waiting session is interrupted: it never reaches its backend
  # function, the other one keeps the lock, and the session goes on.
  start_lock_call(
    a,
    "install_packages",
    call_args("lk-two"),
    hook = "backend_install",
    sync_dir = sync_dir,
    label = "wait-a",
    hold = TRUE
  )
  lock_wait_until(function() file.exists(lock_marker(sync_dir, "wait-a", "in")))
  start_lock_call(
    b,
    "remove_env",
    call_args(),
    hook = "backend_remove_env",
    sync_dir = sync_dir,
    label = "wait-b"
  )
  lock_wait_until(function() {
    file.exists(lock_marker(sync_dir, "wait-b", "waiting"))
  })
  interrupted_at <- Sys.time()
  interrupt_lock_session(b)
  out_b <- lock_call_outcome(b, timeout = 60)
  testthat::expect_identical(
    out_b$value,
    "interrupted",
    info = out_b$error_message
  )
  testthat::expect_lt(
    as.numeric(difftime(Sys.time(), interrupted_at, units = "secs")),
    10
  )
  testthat::expect_false(file.exists(lock_marker(sync_dir, "wait-b", "in")))
  testthat::expect_false(env_lock_is_free(env_name))
  testthat::expect_true(env_exists(env_name, method = "lockstub"))
  file.create(lock_marker(sync_dir, "wait-a", "go"))
  testthat::expect_identical(lock_call_outcome(a)$value, "done")
  testthat::expect_true(env_lock_is_free(env_name))
  start_lock_call(
    b,
    "install_packages",
    call_args("lk-three"),
    hook = "backend_install",
    sync_dir = sync_dir,
    label = "after-b"
  )
  out_after <- lock_call_outcome(b)
  testthat::expect_identical(
    out_after$value,
    "done",
    info = out_after$error_message
  )
  testthat::expect_false(out_after$waited)
  testthat::expect_identical(
    list_packages(env_name, method = "lockstub", verbose = "silent")$name,
    c("lk-one", "lk-three", "lk-two")
  )

  # The session that holds the lock is interrupted while it replaces the
  # environment: the old environment is back, and the lock is free.
  start_lock_call(
    a,
    "create_env",
    c(call_args("lk-four"), list(overwrite = TRUE)),
    hook = "backend_create_env",
    sync_dir = sync_dir,
    label = "hold-a",
    hold = TRUE
  )
  lock_wait_until(function() file.exists(lock_marker(sync_dir, "hold-a", "in")))
  testthat::expect_false(env_lock_is_free(env_name))
  interrupt_lock_session(a)
  out_a <- lock_call_outcome(a, timeout = 60)
  testthat::expect_identical(
    out_a$value,
    "interrupted",
    info = out_a$error_message
  )
  testthat::expect_true(env_lock_is_free(env_name))
  testthat::expect_identical(
    list_packages(env_name, method = "lockstub", verbose = "silent")$name,
    c("lk-one", "lk-three", "lk-two")
  )
})

testthat::test_that("the lock of a session that is killed is free at once", {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("callr")
  # The R children that this test kills cannot delete their temporary
  # directories.
  local_child_tempdir()
  register_lock_stub(env = environment())
  withr::defer({
    root <- backend_root_dir("lockstub")
    if (isTRUE(fs::dir_exists(root))) {
      fs::dir_delete(root)
    }
  })
  a <- local_lock_session()
  b <- local_lock_session()
  a$run(register_lock_stub)
  b$run(register_lock_stub)
  sync_dir <- withr::local_tempdir(pattern = "lk-sync-")
  env_name <- "lk-kill-env"
  create_env(
    "lk-one",
    env_name = env_name,
    method = "lockstub",
    verbose = "silent"
  )
  start_lock_call(
    a,
    "install_packages",
    list(
      "lk-two",
      env_name = env_name,
      method = "lockstub",
      verbose = "output"
    ),
    hook = "backend_install",
    sync_dir = sync_dir,
    label = "kill-a",
    hold = TRUE
  )
  lock_wait_until(function() file.exists(lock_marker(sync_dir, "kill-a", "in")))
  start_lock_call(
    b,
    "remove_env",
    list(env_name = env_name, method = "lockstub", verbose = "output"),
    hook = "backend_remove_env",
    sync_dir = sync_dir,
    label = "kill-b"
  )
  lock_wait_until(function() {
    file.exists(lock_marker(sync_dir, "kill-b", "waiting"))
  })
  killed_at <- Sys.time()
  a$kill()
  out_b <- lock_call_outcome(b, timeout = 60)
  testthat::expect_identical(out_b$value, "done", info = out_b$error_message)
  testthat::expect_lt(
    as.numeric(difftime(Sys.time(), killed_at, units = "secs")),
    10
  )
  testthat::expect_true(file.exists(lock_marker(sync_dir, "kill-b", "in")))
  testthat::expect_false(env_exists(env_name, method = "lockstub"))
  testthat::expect_true(env_lock_is_free(env_name))
})

testthat::test_that("two sessions never change one environment at once (micromamba backend)", {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("callr")
  skip_if_no_micromamba_offline()
  umamba_path <- get_best_micromamba_path()
  if (is.null(umamba_path)) {
    suppressMessages(install_micromamba(verbose = "silent"))
    umamba_path <- get_best_micromamba_path()
  }
  channel <- lock_test_channel()
  a <- local_lock_session(micromamba_path = as.character(umamba_path))
  b <- local_lock_session(micromamba_path = as.character(umamba_path))
  env_name <- "lk-mm-env"
  withr::defer({
    if (isTRUE(env_exists(env_name, method = "micromamba"))) {
      remove_env(env_name, method = "micromamba", verbose = "silent")
    }
  })

  run_env_lock_races(
    a,
    b,
    env_name = env_name,
    backend = "micromamba",
    pkgs = c("lkpkg-a", "lkpkg-b", "lkpkg-a"),
    channels = channel
  )
  # Nothing of the lock is an environment. The names only: a path to the
  # environments can contain "lock" anywhere.
  env_names <- list_envs(method = "micromamba")$env_name
  testthat::expect_false("locks" %in% env_names)
  testthat::expect_false(any(grepl("lock", env_names)))
})

testthat::test_that("a call that changes nothing does not warn that it could not lock", {
  testthat::skip_on_cran()
  # Regression test: the warning came when the lock was taken, so a
  # create_env() of an environment that already has what it asks for, which
  # changes nothing, warned on a data directory that cannot be written.
  with_sandbox_dir({
    local_stub_backend("stub-lk-noop", default_root = TRUE)
    create_env(
      env_name = "lk-noop",
      method = "stub-lk-noop",
      verbose = "silent"
    )
    blocker <- fs::path(get_condathis_path(), "not-a-directory")
    writeLines("x", blocker)
    testthat::local_mocked_bindings(
      env_lock_dir = function() fs::path(blocker, "locks")
    )
    reset_warn_once("env_lock_unavailable")
    withr::defer(reset_warn_once("env_lock_unavailable"))
    testthat::expect_no_warning(
      create_env(
        env_name = "lk-noop",
        method = "stub-lk-noop",
        verbose = "silent"
      )
    )
    # A call that changes the environment still warns.
    testthat::expect_warning(
      remove_env("lk-noop", method = "stub-lk-noop", verbose = "silent"),
      class = "condathis_env_lock_unavailable"
    )
    testthat::expect_false(env_exists("lk-noop", method = "stub-lk-noop"))
  })
})

testthat::test_that("a session waits for a lock without a timed attempt, and says so", {
  testthat::skip_on_cran()
  # Regression test: the wait tried once, then for 2 s, then without a
  # limit. A try that fails keeps its file open in filelock 1.0.3, which on
  # Windows kept the lock file from being deleted, and a timed try that ran
  # out just as the lock was released kept the lock with a handle that
  # nothing released, so the session then waited for itself forever. Now
  # filelock waits only without a limit, and whether another session holds
  # the lock comes from its owner entry.
  testthat::skip_if_not_installed("callr")
  # The R children that this test kills cannot delete their temporary
  # directories.
  local_child_tempdir()
  with_sandbox_dir({
    other <- callr::r_bg(function() Sys.sleep(120), supervise = TRUE)
    withr::defer(other$kill())
    path <- as.character(env_lock_path("lk-owner"))
    owners_dir <- lock_owners_dir(path)
    fs::dir_create(owners_dir)
    other_entry <- fs::path(
      owners_dir,
      sprintf(
        "x-%d-%.3f",
        other$get_pid(),
        lock_process_start_time(other$get_pid())
      )
    )
    fs::file_create(other_entry)
    timeouts <- numeric(0L)
    real_lock <- filelock::lock
    testthat::local_mocked_bindings(
      lock = function(path, exclusive = TRUE, timeout = Inf) {
        timeouts <<- c(timeouts, timeout)
        return(real_lock(path, exclusive = exclusive, timeout = timeout))
      },
      .package = "filelock"
    )
    owner_entries <- function() {
      if (isFALSE(fs::dir_exists(owners_dir))) {
        return(character(0L))
      }
      return(as.character(fs::path_file(fs::dir_ls(owners_dir))))
    }
    take_lock <- function(verbose) {
      holder <- local_env_lock("lk-owner", verbose = verbose)
      return(owner_entries())
    }
    started <- Sys.time()
    testthat::expect_message(
      held <- take_lock("output"),
      class = "condathis_env_lock_waiting"
    )
    testthat::expect_gte(
      as.numeric(difftime(Sys.time(), started, units = "secs")),
      env_lock_notice_ms() / 1000 - 0.1
    )
    testthat::expect_identical(timeouts, Inf)
    # While it held the lock, its own entry was there too; afterwards only
    # the other process's.
    testthat::expect_true(any(startsWith(
      held,
      paste0("x-", Sys.getpid(), "-")
    )))
    testthat::expect_identical(
      owner_entries(),
      as.character(fs::path_file(other_entry))
    )
    # Silent: the same wait without the message.
    testthat::expect_no_message(take_lock("silent"))
    # The entry of a process that has ended is dropped, without a wait.
    other$kill()
    started <- Sys.time()
    testthat::expect_no_message(take_lock("output"))
    testthat::expect_lt(
      as.numeric(difftime(Sys.time(), started, units = "secs")),
      env_lock_notice_ms() / 1000
    )
    # The directory of the entries goes with the last one.
    testthat::expect_false(fs::dir_exists(owners_dir))
    testthat::expect_true(all(timeouts == Inf))
    # A shared lock waits only for an exclusive owner.
    fs::dir_create(owners_dir)
    fs::file_create(fs::path(
      owners_dir,
      sprintf("s-%d-%.3f", Sys.getpid() + 1L, 0)
    ))
    testthat::expect_false(lock_held_by_others(owners_dir, exclusive = FALSE))
  })
})

testthat::test_that("a session that waited for a lock leaves no lock file open", {
  testthat::skip_on_cran()
  # Regression test (Windows): every wait kept handles of the lock file open
  # for the rest of the session, so with_sandbox_dir() could not delete its
  # directory.
  testthat::skip_if_not_installed("callr")
  warnings <- list()
  sandbox_root <- NULL
  withCallingHandlers(
    with_sandbox_dir({
      sandbox_root <- dirname(Sys.getenv("XDG_DATA_HOME"))
      register_lock_stub(env = environment())
      sync_dir <- withr::local_tempdir(pattern = "lk-sync-")
      a <- callr::r_session$new(
        options = callr::r_session_options(libpath = .libPaths()),
        wait = TRUE
      )
      a$run(
        function(source_dir) {
          if (is.null(source_dir)) {
            loadNamespace("condathis")
          } else {
            pkgload::load_all(
              source_dir,
              quiet = TRUE,
              helpers = FALSE,
              attach_testthat = FALSE,
              export_all = FALSE
            )
          }
          return(invisible(NULL))
        },
        args = list(source_dir = condathis_source_dir())
      )
      a$run(register_lock_stub)
      create_env(
        "lk-one",
        env_name = "lk-sbx-env",
        method = "lockstub",
        verbose = "silent"
      )
      start_lock_call(
        a,
        "install_packages",
        list(
          "lk-two",
          env_name = "lk-sbx-env",
          method = "lockstub",
          verbose = "silent"
        ),
        hook = "backend_install",
        sync_dir = sync_dir,
        label = "sbx-a",
        hold = TRUE
      )
      lock_wait_until(function() {
        file.exists(lock_marker(sync_dir, "sbx-a", "in"))
      })
      # Lets the other session go on after 3 s, while this one waits.
      go <- callr::r_bg(
        function(go_file) {
          Sys.sleep(3)
          file.create(go_file)
        },
        args = list(go_file = lock_marker(sync_dir, "sbx-a", "go"))
      )
      install_packages(
        "lk-three",
        env_name = "lk-sbx-env",
        method = "lockstub",
        verbose = "silent"
      )
      testthat::expect_identical(lock_call_outcome(a)$value, "done")
      go$wait()
      a$close()
      testthat::expect_identical(
        list_packages(
          "lk-sbx-env",
          method = "lockstub",
          verbose = "silent"
        )$name,
        c("lk-one", "lk-three", "lk-two")
      )
    }),
    warning = function(cnd) {
      warnings[[length(warnings) + 1L]] <<- cnd
      invokeRestart("muffleWarning")
    }
  )
  testthat::expect_length(warnings, 0L)
  testthat::expect_false(dir.exists(sandbox_root))
})

testthat::test_that("clean_cache() and the creates and installs of other sessions wait for each other", {
  testthat::skip_on_cran()
  # Regression test: clean_cache() took no lock, and deleted micromamba's
  # package cache, its lock files included, while another session
  # downloaded into it: that create failed.
  testthat::skip_if_not_installed("callr")
  with_sandbox_dir({
    register_lock_stub(env = environment())
    # Closed before the sandbox ends: it stops the processes started in it.
    a <- local_lock_session(env = rlang::current_env())
    b <- local_lock_session(env = rlang::current_env())
    a$run(register_lock_stub)
    b$run(register_lock_stub)
    sync_dir <- withr::local_tempdir(pattern = "lk-sync-")
    create_env(
      "lk-one",
      env_name = "lk-cache-env",
      method = "lockstub",
      verbose = "silent"
    )
    # A create holds the caches: clean_cache() waits, and says so.
    raced <- race_env_lock(
      a,
      b,
      sync_dir = sync_dir,
      label = "create-clean",
      first = list(
        fn = "create_env",
        args = list(
          "lk-two",
          env_name = "lk-cache-env-2",
          method = "lockstub",
          verbose = "output"
        ),
        hook = "backend_create_env"
      ),
      second = list(
        fn = "clean_cache",
        args = list(verbose = "output"),
        hook = "clean_backend_cache"
      )
    )
    testthat::expect_identical(
      c(raced$a$value, raced$b$value),
      c("done", "done")
    )
    testthat::expect_true("condathis_cache_lock_waiting" %in% raced$b$messages)
    testthat::expect_gte(raced$waited, env_lock_notice_ms() / 1000 - 0.1)
    # clean_cache() holds the caches: an install waits.
    raced <- race_env_lock(
      a,
      b,
      sync_dir = sync_dir,
      label = "clean-install",
      first = list(
        fn = "clean_cache",
        args = list(verbose = "output"),
        hook = "clean_backend_cache"
      ),
      second = list(
        fn = "install_packages",
        args = list(
          "lk-three",
          env_name = "lk-cache-env",
          method = "lockstub",
          verbose = "output"
        ),
        hook = "backend_install"
      )
    )
    testthat::expect_identical(
      c(raced$a$value, raced$b$value),
      c("done", "done")
    )
    testthat::expect_true("condathis_cache_lock_waiting" %in% raced$b$messages)
    testthat::expect_identical(
      list_packages(
        "lk-cache-env",
        method = "lockstub",
        verbose = "silent"
      )$name,
      c("lk-one", "lk-three")
    )
    # Creates do not wait for each other's hold of the caches.
    start_lock_call(
      a,
      "create_env",
      list(
        "lk-four",
        env_name = "lk-cache-a",
        method = "lockstub",
        verbose = "output"
      ),
      hook = "backend_create_env",
      sync_dir = sync_dir,
      label = "shared-a",
      hold = TRUE
    )
    lock_wait_until(function() {
      file.exists(lock_marker(sync_dir, "shared-a", "in"))
    })
    start_lock_call(
      b,
      "create_env",
      list(
        "lk-four",
        env_name = "lk-cache-b",
        method = "lockstub",
        verbose = "output"
      ),
      hook = "backend_create_env",
      sync_dir = sync_dir,
      label = "shared-b"
    )
    out_b <- lock_call_outcome(b, timeout = 60)
    testthat::expect_identical(out_b$value, "done", info = out_b$error_message)
    testthat::expect_false(out_b$waited)
    file.create(lock_marker(sync_dir, "shared-a", "go"))
    testthat::expect_identical(lock_call_outcome(a)$value, "done")
    a$close()
    b$close()
  })
})

testthat::test_that("the owner entry of a process that has ended but was not reaped does not hold a lock", {
  testthat::skip_on_cran()
  # Regression test: an owner that had ended but that its parent had not
  # reaped (a zombie) counted as running, so every session that took the
  # lock waited two seconds and said that it waited. In a container whose
  # first process never reaps (`docker run` without `--init`), a session
  # killed after its parent ended stays a zombie.
  with_sandbox_dir({
    if (isTRUE(is_windows())) {
      # Windows has no zombies: an ended process is gone.
      proc <- processx::process$new(
        file.path(R.home("bin"), "Rscript"),
        c("-e", "invisible()")
      )
      owner <- proc$as_ps_handle()
      proc$wait(timeout = 10000)
    } else {
      # `sh` starts `sleep 0`, then becomes `sleep 60`, which never reaps
      # it.
      parent <- processx::process$new("sh", c("-c", "sleep 0 & exec sleep 60"))
      withr::defer(parent$kill())
      owner <- NULL
      lock_wait_until(
        function() {
          # The parent's handle comes from ps, not processx: ps_children()
          # keeps only children that started no earlier than the parent,
          # and processx's handle has a start time a little later than ps
          # reads, so a child started in the same clock tick was missed.
          children <- ps::ps_children(ps::ps_handle(parent$get_pid()))
          if (
            identical(length(children), 1L) &&
              identical(ps::ps_status(children[[1L]]), "zombie")
          ) {
            owner <<- children[[1L]]
            return(TRUE)
          }
          return(FALSE)
        },
        timeout = 10,
        what = "the zombie of `sleep 0`"
      )
    }
    testthat::expect_false(process_running(owner))
    owners_dir <- lock_owners_dir(as.character(env_lock_path("lk-zombie")))
    fs::dir_create(owners_dir)
    entry <- fs::path(
      owners_dir,
      sprintf(
        "x-%d-%.3f",
        ps::ps_pid(owner),
        as.numeric(ps::ps_create_time(owner))
      )
    )
    fs::file_create(entry)
    testthat::expect_false(lock_held_by_others(owners_dir, exclusive = TRUE))
    # The entry of an ended process is deleted.
    testthat::expect_false(fs::file_exists(entry))
  })
})
