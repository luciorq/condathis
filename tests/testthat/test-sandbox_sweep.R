# The stale-sandbox sweep and the background deletion of setup.R, with the
# helpers in helper-sandbox.R.

# A sandbox root named like the ones setup.R creates, inside `parent`.
local_fake_sandbox <- function(parent, name) {
  root <- file.path(parent, paste0("condathis-test-", name))
  dir.create(file.path(root, "home"), recursive = TRUE)
  return(root)
}

# Three hours from now, every fake sandbox root is older than two hours.
three_hours_later <- function() {
  return(Sys.time() + 3 * 60 * 60)
}

testthat::test_that("the sandbox sweep keeps a sandbox whose owner runs, however old", {
  # Regression test: the sweep deleted every sandbox whose root was more
  # than two hours old. A root's modification time does not change while
  # its tests run, so a second test run deleted the live sandbox of a run
  # that took longer than two hours.
  parent <- withr::local_tempdir()
  live <- local_fake_sandbox(parent, "live")
  write_sandbox_owner(live)

  testthat::expect_identical(
    find_stale_sandboxes(parent, now = three_hours_later()),
    character(0L)
  )
})

testthat::test_that("the sandbox sweep deletes a sandbox whose owner has exited", {
  parent <- withr::local_tempdir()
  dead <- local_fake_sandbox(parent, "dead")
  proc <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    c("-e", "invisible()")
  )
  # The handle keeps the creation time `processx` recorded at the start, so
  # it can be written after the process has exited.
  write_sandbox_owner(dead, proc$as_ps_handle())
  proc$wait(timeout = 10000)
  testthat::expect_false(proc$is_alive())
  # Windows keeps the ID of an exited process while a handle to it is
  # open.
  rm(proc)
  gc()

  # Even a fresh sandbox is deleted once its owner is gone.
  testthat::expect_identical(find_stale_sandboxes(parent), dead)
})

testthat::test_that("the sandbox sweep deletes a sandbox whose owner ID was reused", {
  parent <- withr::local_tempdir()
  reused <- local_fake_sandbox(parent, "reused")
  # This process has the recorded ID, but started a day after the owner.
  me <- ps::ps_handle()
  write.dcf(
    data.frame(
      pid = ps::ps_pid(me),
      create_time = sprintf(
        "%.6f",
        as.numeric(ps::ps_create_time(me)) - 24 * 60 * 60
      )
    ),
    sandbox_owner_path(reused)
  )

  testthat::expect_identical(find_stale_sandboxes(parent), reused)
})

testthat::test_that("the sandbox sweep uses the age only for sandboxes without an owner record", {
  parent <- withr::local_tempdir()
  unowned <- local_fake_sandbox(parent, "unowned")
  unreadable <- local_fake_sandbox(parent, "unreadable")
  writeLines("not an owner record", sandbox_owner_path(unreadable))
  # Not a test sandbox, however old.
  dir.create(file.path(parent, "other-dir"))

  testthat::expect_null(read_sandbox_owner(unowned))
  testthat::expect_null(read_sandbox_owner(unreadable))
  testthat::expect_identical(find_stale_sandboxes(parent), character(0L))
  testthat::expect_setequal(
    find_stale_sandboxes(parent, now = three_hours_later()),
    c(unowned, unreadable)
  )
})

testthat::test_that("sandbox owner records round-trip", {
  root <- local_fake_sandbox(withr::local_tempdir(), "record")
  me <- ps::ps_handle()
  write_sandbox_owner(root, me)

  owner <- read_sandbox_owner(root)
  testthat::expect_identical(owner$pid, Sys.getpid())
  testthat::expect_equal(
    owner$create_time,
    as.numeric(ps::ps_create_time(me)),
    tolerance = 1e-6
  )
  testthat::expect_true(sandbox_owner_running(owner))
  # The temporary file of the write is renamed, not left behind.
  testthat::expect_setequal(list.files(root), c("home", "owner.dcf"))
})

testthat::test_that("the test sandbox of this session names this process as its owner", {
  # setup.R puts HOME in the sandbox root.
  sandbox_root <- dirname(Sys.getenv("HOME"))
  owner <- read_sandbox_owner(sandbox_root)
  testthat::expect_identical(owner$pid, Sys.getpid())
  testthat::expect_true(sandbox_owner_running(owner))
})

testthat::test_that("the background deletion deletes its paths and leaves nothing else", {
  # On Windows, `TMP` and `TEMP` of the process are `tmp` too.
  tmp <- local_child_tempdir()
  first <- local_fake_sandbox(tmp, "first")
  second <- local_fake_sandbox(tmp, "second")
  writeLines("x", file.path(first, "home", "file"))

  proc <- delete_in_background(c(first, second))
  testthat::expect_s3_class(proc, "process")
  proc$wait(timeout = 30000)

  # The `tempdir()` of the process was inside `first`. R exits normally
  # although it is gone.
  testthat::expect_identical(proc$get_exit_status(), 0L)
  testthat::expect_identical(
    list.files(tmp, all.files = TRUE, no.. = TRUE),
    character(0L)
  )
})

testthat::test_that("a killed background deletion leaves nothing outside its first path", {
  # Regression test: a host that killed the deletion left its `tempdir()`
  # in the temporary directory of the user. On Windows, it also left the
  # file that Rscript writes `-e` code to.
  tmp <- local_child_tempdir()
  root <- local_fake_sandbox(tmp, "killed")
  started <- file.path(root, "started")

  proc <- delete_in_background(
    root,
    code = "file.create(file.path(commandArgs(TRUE), 'started')); Sys.sleep(60)"
  )
  testthat::expect_s3_class(proc, "process")
  withr::defer(proc$kill())
  # The code runs after R starts, so R made its `tempdir()` already.
  deadline <- Sys.time() + 30
  while (
    isFALSE(file.exists(started)) &&
      isTRUE(proc$is_alive()) &&
      Sys.time() < deadline
  ) {
    Sys.sleep(0.05)
  }
  testthat::expect_true(file.exists(started))
  proc$kill()
  proc$wait(timeout = 10000)
  testthat::expect_false(proc$is_alive())

  testthat::expect_identical(
    list.files(tmp, all.files = TRUE, no.. = TRUE),
    basename(root)
  )
  testthat::expect_length(list.files(root, pattern = "^Rtmp"), 1L)
})
