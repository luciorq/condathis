# Checks that every stage of a pipeline ran to its end, as in a shell: the
# last stage exits with status 0, and every other stage with status 0 or
# by SIGPIPE (status -13, which `run_pipeline()` does not count as a
# failure).
#
# In `polyglot | polyglot`, the second `polyglot` never reads its stdin
# and can exit before the first one writes its second line (the first runs
# `uname` between its two lines). On Linux and macOS SIGPIPE then ends the
# first one, which happens now and then on a busy machine.
expect_pipeline_statuses_ok <- function(res, n = 2L) {
  statuses <- res$statuses
  testthat::expect_length(statuses, n)
  testthat::expect_identical(statuses[[n]], 0L)
  testthat::expect_true(
    all(statuses[-n] %in% c(0L, broken_pipe_status)),
    label = paste("statuses", paste(statuses, collapse = " "))
  )
  return(invisible(res))
}
