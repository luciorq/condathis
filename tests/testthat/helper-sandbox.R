# The per-process test sandbox (see setup.R): who owns a sandbox, and which
# sandboxes left behind by earlier runs can be deleted. Also a temporary
# directory for the R processes that a test kills.
#
# A sandbox root's modification time is set when the root is created and
# does not change while its tests run. Deleting every sandbox older than
# two hours therefore also deleted the live sandbox of a test run that took
# longer, for example a slow CI job or an `R CMD check` in another
# terminal. Each root now names the process that uses it.

# The file in a sandbox root that names its owner.
sandbox_owner_path <- function(sandbox_root) {
  return(file.path(sandbox_root, "owner.dcf"))
}

# Records `handle` as the owner of `sandbox_root`: its process ID and its
# creation time, so a later process with the same ID is not taken for it.
# Written to a temporary file and renamed, so a concurrent reader never
# sees part of a record.
write_sandbox_owner <- function(sandbox_root, handle = ps::ps_handle()) {
  record <- data.frame(
    pid = ps::ps_pid(handle),
    create_time = sprintf("%.6f", as.numeric(ps::ps_create_time(handle)))
  )
  tmp_path <- tempfile(pattern = "owner-", tmpdir = sandbox_root)
  write.dcf(record, tmp_path)
  file.rename(tmp_path, sandbox_owner_path(sandbox_root))
  return(invisible(sandbox_owner_path(sandbox_root)))
}

# The owner record of `sandbox_root`: a list with `pid` (integer) and
# `create_time` (seconds since the epoch), or `NULL` if there is no
# readable record.
read_sandbox_owner <- function(sandbox_root) {
  record <- tryCatch(
    read.dcf(
      sandbox_owner_path(sandbox_root),
      fields = c("pid", "create_time")
    ),
    error = function(e) NULL,
    warning = function(w) NULL
  )
  if (isFALSE(is.matrix(record)) || isFALSE(identical(nrow(record), 1L))) {
    return(NULL)
  }
  pid <- suppressWarnings(as.integer(record[[1L, "pid"]]))
  create_time <- suppressWarnings(as.numeric(record[[1L, "create_time"]]))
  if (isTRUE(is.na(pid)) || isTRUE(is.na(create_time))) {
    return(NULL)
  }
  return(list(pid = pid, create_time = create_time))
}

# Whether the process in `owner` (from `read_sandbox_owner()`) still runs.
#
# The creation times are compared with a `tolerance` in seconds. On Linux,
# `ps` computes a creation time from the boot time, which moves when the
# system clock is stepped. Taking a live owner for a dead one deletes its
# sandbox; taking a new process with the same ID for the owner only delays
# the deletion until that process ends.
sandbox_owner_running <- function(owner, tolerance = 60) {
  handle <- tryCatch(ps::ps_handle(owner$pid), error = function(e) e)
  if (inherits(handle, "error")) {
    # A process that cannot be inspected may still be the owner.
    return(inherits(handle, "access_denied"))
  }
  create_time <- tryCatch(
    as.numeric(ps::ps_create_time(handle)),
    error = function(e) NA_real_
  )
  if (isTRUE(is.na(create_time))) {
    return(FALSE)
  }
  if (isTRUE(abs(create_time - owner$create_time) > tolerance)) {
    return(FALSE)
  }
  # A zombie owner has ended (see `process_running()`).
  running <- tryCatch(process_running(handle), error = function(e) FALSE)
  return(isTRUE(running))
}

# The test sandboxes in `sandbox_parent` that can be deleted: those whose
# owner no longer runs. A sandbox without an owner record, for example one
# from before owner records existed or one whose record is not written yet,
# can be deleted once it is `max_age` seconds old.
find_stale_sandboxes <- function(
  sandbox_parent,
  max_age = 2 * 60 * 60,
  now = Sys.time()
) {
  roots <- list.files(
    sandbox_parent,
    pattern = "^condathis-test-",
    full.names = TRUE
  )
  stale <- vapply(
    roots,
    function(root) {
      owner <- read_sandbox_owner(root)
      if (is.null(owner)) {
        mtime <- file.info(root)$mtime
        return(isTRUE(mtime < now - max_age))
      }
      return(isFALSE(sandbox_owner_running(owner)))
    },
    logical(1L),
    USE.NAMES = FALSE
  )
  return(roots[stale])
}

# Points `TMPDIR` (on Windows also `TMP` and `TEMP`) at a new directory
# inside this process's `tempdir()` until `.local_envir` ends, and deletes
# it then. R processes started meanwhile make their own temporary
# directories there. A killed R process cannot delete its own, so a test
# that kills R children calls this before it starts them: the directory
# goes after they are killed, and at the latest with this process's
# `tempdir()`. A test that runs a program that leaves files in the
# temporary directory of the system calls it too.
local_child_tempdir <- function(.local_envir = parent.frame()) {
  dir <- withr::local_tempdir(
    pattern = "child-tmp-",
    .local_envir = .local_envir
  )
  vars <- c(TMPDIR = dir)
  if (isTRUE(is_windows())) {
    vars <- c(vars, TMP = dir, TEMP = dir)
  }
  withr::local_envvar(vars, .local_envir = .local_envir)
  return(invisible(dir))
}
