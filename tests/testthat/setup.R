withr::local_options(
  .new = list(
    warnPartialMatchArgs = TRUE,
    warnPartialMatchAttr = TRUE,
    warnPartialMatchDollar = TRUE
  ),
  .local_envir = testthat::teardown_env()
)

# On Windows, R's `isatty()` can read past the end of a buffer when the
# stream is a pipe, and the process then crashes with an access violation
# (exit code -1073741819). Parallel workers write to pipes, and cli calls
# `isatty()` for its color, hyperlink, dynamic, ANSI and theme checks
# unless these options answer them. They are cli's answers for a stream
# that is not a terminal.
if (isTRUE(is_windows())) {
  withr::local_options(
    .new = list(
      cli.num_colors = 1L,
      cli.hyperlink = FALSE,
      cli.dynamic = FALSE,
      cli.ansi = FALSE,
      cli.theme_dark = FALSE
    ),
    .local_envir = testthat::teardown_env()
  )
}

# Every test process gets its own sandbox: home, data and cache
# directories under one root, so micromamba, the package cache and the
# environments never touch the user's own. The root sits next to R's
# `tempdir()`, not inside it, so a worker's exit never has to delete it.
# On CRAN, where no test downloads anything and the sandbox stays small,
# it sits inside `tempdir()`, the only directory a check may write to.
#
# `R CMD check --as-cran` points `TMPDIR` at a "working_dir" inside its own
# `tempdir()`, and when it ends reports what is left there ("checking for
# detritus in the temp directory"). The background deletion below can
# still be running then. So under that check, the root sits in the
# temporary directory of the check itself, which the check does not report
# and deletes when it exits.
on_cran <- !identical(Sys.getenv("NOT_CRAN"), "true")
sandbox_parent <- if (isTRUE(on_cran)) tempdir() else dirname(tempdir())
if (
  isFALSE(on_cran) &&
    nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_")) &&
    identical(basename(sandbox_parent), "working_dir")
) {
  sandbox_parent <- dirname(sandbox_parent)
}
sandbox_root <- tempfile(pattern = "condathis-test-", tmpdir = sandbox_parent)
tmp_home_path <- fs::path(sandbox_root, "home")
tmp_data_path <- fs::path(sandbox_root, "data")
tmp_cache_path <- fs::path(sandbox_root, "cache")

# Deletes `paths` from a detached process, which outlives this one.
#
# testthat gives each parallel worker one second to run its teardown, then
# kills it. Deleting a sandbox takes longer (its package cache alone holds
# gigabytes), so with `withr::local_tempdir()` every run left it behind,
# together with the worker's `tempdir()`.
#
# Some hosts kill the detached process too (see below). It then leaves
# nothing outside `paths`, which a later run deletes:
# - The R code comes from standard input. With `-e`, Rscript on Windows
#   writes the code to a file in the temporary directory, and deletes that
#   file only when it exits. R keeps a script file open while it runs, and
#   Windows cannot delete an open file or the directories that hold it.
# - `TMPDIR` is the first path, so the process makes its `tempdir()` there.
#   If that path is gone, R uses `TMP`, `TEMP` or its default, as usual.
#   `TMP` and `TEMP` keep their values: on Windows, if none of the three is
#   a writable directory, R uses the home directory of the user.
#
# Tests give other R `code`. Returns the process, or `NULL` if no process
# started.
delete_in_background <- function(
  paths,
  code = "unlink(commandArgs(TRUE), recursive = TRUE, force = TRUE)"
) {
  if (identical(length(paths), 0L)) {
    return(invisible(NULL))
  }
  cleanup_env <- Sys.getenv()
  # processx `kill_tree()` finds a process's children through inherited
  # `PROCESSX_*` variables. Without them, killing the worker does not kill
  # this process too.
  cleanup_env <- cleanup_env[!startsWith(names(cleanup_env), "PROCESSX_")]
  cleanup_env <- c(
    cleanup_env[toupper(names(cleanup_env)) != "TMPDIR"],
    TMPDIR = paths[[1L]]
  )
  proc <- try(
    processx::process$new(
      command = file.path(R.home("bin"), "Rscript"),
      # `-` reads the code from standard input. With `--vanilla`, the
      # process does not read the R profile or environment files of the
      # user.
      args = c("--vanilla", "-", paths),
      # Outside the sandbox and outside `tempdir()`: Windows cannot delete
      # a process's working directory.
      wd = dirname(tempdir()),
      env = cleanup_env,
      stdin = "|",
      stdout = NULL,
      stderr = NULL,
      cleanup = FALSE
    ),
    silent = TRUE
  )
  if (inherits(proc, "try-error")) {
    return(invisible(NULL))
  }
  try(
    {
      proc$write_input(paste0(code, "\n"))
      close(proc$get_input_connection())
    },
    silent = TRUE
  )
  return(invisible(proc))
}

# The owner record tells later runs that this sandbox is in use, however
# long its tests take (see helper-sandbox.R).
fs::dir_create(sandbox_root)
write_sandbox_owner(sandbox_root)

# Some hosts still kill the detached process, for example an OpenSSH
# session on Windows ending, or a CI runner. Sandboxes left behind that way,
# with the `tempdir()` of the killed process inside, are deleted by a later
# run, once their owner no longer runs. Deleting one that a detached process
# is still deleting does no harm. On CRAN, each sandbox is inside the
# `tempdir()` of its own process.
if (isFALSE(on_cran)) {
  delete_in_background(find_stale_sandboxes(sandbox_parent))
}

# Registered first, so it runs after the working directory is restored.
# Not on CRAN: there the sandbox is inside `tempdir()`, which R deletes
# when it exits. A detached process would outlive the tests, delete the
# same files at the same time as R, and make its own `tempdir()` outside
# the one of the check.
if (isFALSE(on_cran)) {
  withr::defer(
    delete_in_background(sandbox_root),
    envir = testthat::teardown_env()
  )
}

tmp_wd_path <- fs::path(tmp_home_path, "wd")

if (isFALSE(fs::dir_exists(tmp_home_path))) {
  fs::dir_create(tmp_home_path)
}
if (isFALSE(fs::dir_exists(tmp_data_path))) {
  fs::dir_create(tmp_data_path)
}
if (isFALSE(fs::dir_exists(tmp_cache_path))) {
  fs::dir_create(tmp_cache_path)
}
if (isFALSE(fs::dir_exists(tmp_wd_path))) {
  fs::dir_create(tmp_wd_path)
}

withr::local_dir(
  new = tmp_wd_path,
  .local_envir = testthat::teardown_env()
)

withr::local_envvar(
  .new = list(
    `HOME` = tmp_home_path,
    `USERPROFILE` = tmp_home_path,
    `LOCALAPPDATA` = tmp_data_path,
    `APPDATA` = tmp_data_path,
    `R_USER_DATA_DIR` = tmp_data_path,
    `XDG_DATA_HOME` = tmp_data_path,
    `R_USER_CACHE_DIR` = tmp_cache_path,
    `XDG_CACHE_HOME` = tmp_cache_path
  ),
  .local_envir = testthat::teardown_env()
)

base::rm(tmp_home_path)
base::rm(tmp_data_path)
base::rm(tmp_cache_path)
base::rm(tmp_wd_path)

# condathis loads a backend package that it knows by name (rattlerthis) on
# demand. The test machines install it in the same library, so the suite
# would load it into its workers. For the whole suite, every package reads
# as not installed: only test-backend-packages.R mocks these again, with a
# stub that registers. The stub backend named "rattler" of test-backend.R
# is safe this way.
testthat::local_mocked_bindings(
  load_backend_namespace = function(pkg) FALSE,
  backend_package_installed = function(pkg) FALSE,
  .package = "condathis",
  .env = testthat::teardown_env()
)
