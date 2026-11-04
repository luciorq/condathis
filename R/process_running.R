#' Whether a process still runs
#'
#' As `ps::ps_is_running()`, but a zombie, a process that has ended and
#' that its parent has not reaped, counts as ended. A process whose parent
#' ends first is reaped by the first process of the system or container.
#' In a container started without an init process (`docker run` without
#' `--init`), that first process often never reaps, such as the
#' `tail -f /dev/null` of a CI job container, so the process stays a zombie
#' until the container stops.
#'
#' @param handle A `ps_handle` object.
#'
#' @returns `TRUE` or `FALSE`. An error of `ps::ps_is_running()` is
#'   signaled. A process whose status cannot be read counts as running.
#'
#' @keywords internal
#' @noRd
process_running <- function(handle) {
  if (isFALSE(ps::ps_is_running(handle))) {
    return(FALSE)
  }
  zombie <- tryCatch(
    identical(ps::ps_status(handle), "zombie"),
    error = function(e) FALSE
  )
  return(isFALSE(zombie))
}
