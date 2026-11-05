#' Download a file with robust error handling
#'
#' Downloads a file from an endpoint, preferring `curl::curl_download()` when
#' the `curl` package is available, falling back to `utils::download.file()`.
#' Wraps downloads in error handling so failures return `FALSE` instead of
#' throwing errors.
#'
#' @param url Character string with the download endpoint.
#' @param destfile Character string. The destination file path.
#' @param timeout_limit Numeric. Timeout in seconds for the download. `Inf`
#'   means no limit. The download uses the larger of this value and
#'   `getOption("timeout")` (see `download_timeout_secs()`). A finite limit
#'   above `max_download_timeout_secs()` (about 24.8 days) is lowered to it.
#'   Defaults to `3600`.
#' @param method Character string. Download method passed to
#'   `utils::download.file()` when `curl` is not available.
#'   Defaults to `"auto"`.
#' @param quiet Logical. Whether to suppress download progress output.
#'   Defaults to `TRUE`.
#'
#' @returns Logical. `TRUE` if the download succeeded, `FALSE` otherwise.
#'
#' @keywords internal
#' @noRd
download_micromamba_file <- function(
  url,
  destfile,
  timeout_limit = 3600,
  method = "auto",
  quiet = TRUE
) {
  dl_success <- FALSE

  if (isFALSE(rlang::is_interactive())) {
    quiet <- TRUE
  }

  timeout_secs <- download_timeout_secs(timeout_limit = timeout_limit)

  withr::with_options(
    new = base::list(timeout = r_download_timeout(timeout_secs)),
    code = {
      dl_success <- tryCatch(
        {
          if (isTRUE(use_curl_download())) {
            # curl ignores `options(timeout)`, so pass the same limit on
            # the handle. Without it a stalled mirror hung the install
            # indefinitely and the mirror fallback never ran.
            curl::curl_download(
              url = url,
              destfile = destfile,
              quiet = quiet,
              mode = "wb",
              handle = base::do.call(
                curl::new_handle,
                curl_timeout_options(timeout_secs)
              )
            )
          } else {
            dl_res <- utils::download.file(
              url = url,
              destfile = destfile,
              method = method,
              mode = "wb",
              quiet = quiet
            )
            if (!identical(dl_res, 0L)) {
              return(FALSE)
            }
          }
          TRUE
        },
        error = function(e) {
          FALSE
        },
        warning = function(w) {
          # Suppress download warnings (e.g., HTTP errors) and return FALSE
          FALSE
        }
      )
    }
  )

  return(dl_success)
}

#' Should downloads use `curl::curl_download()`?
#'
#' A separate function so tests can select the `utils::download.file()`
#' path.
#'
#' @returns Logical scalar. `TRUE` when `curl` 5.0.0 or later is installed.
#'
#' @keywords internal
#' @noRd
use_curl_download <- function() {
  return(
    isTRUE(base::requireNamespace("curl", quietly = TRUE)) &&
      isTRUE(utils::packageVersion("curl") >= "5.0.0")
  )
}

#' Resolve the timeout of one download
#'
#' Uses the larger of `timeout_limit` and the session `timeout` option, so
#' a user who raised `options(timeout)` for a slow network is not cut off
#' by the default `timeout_limit`. A session value that is not a single
#' non-negative number is ignored. Base R accepts any value in `options()`,
#' and `max()` of a character string and a number is a character string.
#'
#' @param timeout_limit Numeric scalar. Timeout in seconds. `Inf` means no
#'   limit.
#' @param session_timeout Value of `getOption("timeout")`.
#'
#' @returns Numeric scalar. Timeout in seconds, possibly `Inf`.
#'
#' @keywords internal
#' @noRd
download_timeout_secs <- function(
  timeout_limit,
  session_timeout = getOption("timeout")
) {
  if (isTRUE(is_timeout_value(session_timeout))) {
    return(base::max(timeout_limit, session_timeout))
  }
  return(timeout_limit)
}

#' Is a value a valid timeout?
#'
#' @param x Value to check.
#'
#' @returns Logical scalar. `TRUE` for a single non-negative number that is
#'   not `NA`. `Inf` is valid.
#'
#' @keywords internal
#' @noRd
is_timeout_value <- function(x) {
  return(
    isTRUE(is.numeric(x)) &&
      isTRUE(identical(length(x), 1L)) &&
      isFALSE(is.na(x)) &&
      isTRUE(x >= 0)
  )
}

#' Largest timeout that every supported libcurl accepts
#'
#' libcurl before 8.15.0 rejects `CURLOPT_TIMEOUT` and
#' `CURLOPT_CONNECTTIMEOUT` above `INT_MAX / 1000` seconds (2147483 s, about
#' 24.8 days) with "Invalid or unsupported value", because it stores the
#' value in milliseconds in an `int`. Builds of the `curl` package for
#' Windows and macOS can bundle such a libcurl (8.14 in curl 8.1.0). R's
#' `download.file()` also multiplies
#' `options(timeout)` by 1000 in a C `long`, which is 32 bits on Windows.
#' A value up to this limit is safe in both cases.
#'
#' @returns Integer scalar. Timeout in seconds.
#'
#' @keywords internal
#' @noRd
max_download_timeout_secs <- function() {
  return(.Machine$integer.max %/% 1000L)
}

#' Timeout options for a `curl` handle
#'
#' `curl::new_handle()` rejects `timeout = Inf` with "Invalid or
#' unsupported value", which made every download fail. curl takes the
#' timeouts as whole seconds, and `0` means no limit. So a limit that is not
#' finite becomes `0`. A finite limit above `max_download_timeout_secs()`
#' would also be rejected, so it becomes that limit.
#'
#' The connect timeout stays at 60 seconds or less, also without a total
#' limit, so an unreachable mirror does not stop the fallback to the next
#' one.
#'
#' @param timeout_secs Numeric scalar. Timeout in seconds, possibly `Inf`.
#'   `0` means no limit.
#'
#' @returns A named list with integer `timeout` and `connecttimeout`, the
#'   arguments for `curl::new_handle()`.
#'
#' @keywords internal
#' @noRd
curl_timeout_options <- function(timeout_secs) {
  total <- 0L
  if (isTRUE(is.finite(timeout_secs)) && isTRUE(timeout_secs > 0)) {
    # Round up, so a limit below one second is not taken as `0`, no limit.
    total <- as.integer(
      base::min(base::ceiling(timeout_secs), max_download_timeout_secs())
    )
  }
  connect <- 60L
  if (isTRUE(total > 0L)) {
    connect <- base::min(total, 60L)
  }
  return(list(timeout = total, connecttimeout = connect))
}

#' Value of `options(timeout)` for `utils::download.file()`
#'
#' R reads the `timeout` option as an integer. `Inf`, or a value that does
#' not fit in an integer, gives the warning "NAs introduced by coercion to
#' integer range", and `download_micromamba_file()` treats every warning as
#' a failed download. R then multiplies the value by 1000 in a C `long`,
#' which overflows on Windows above `max_download_timeout_secs()`. So a
#' limit that is not finite, is `0` (no limit, as for curl), or is above
#' that limit becomes that limit.
#'
#' @param timeout_secs Numeric scalar. Timeout in seconds, possibly `Inf`.
#'
#' @returns Integer scalar. A positive timeout in seconds.
#'
#' @keywords internal
#' @noRd
r_download_timeout <- function(timeout_secs) {
  max_secs <- max_download_timeout_secs()
  if (isTRUE(is.finite(timeout_secs)) && isTRUE(timeout_secs > 0)) {
    return(as.integer(base::min(base::ceiling(timeout_secs), max_secs)))
  }
  return(max_secs)
}

#' Try downloading from multiple mirror endpoints
#'
#' Iterates through endpoint strings and attempts to download from each one
#' until one succeeds or all fail. A download succeeds when the file is not
#' empty and `accept` returns `TRUE` for it.
#'
#' @param urls Character vector of endpoints to try in order.
#' @param destfile Character string. The destination file path.
#' @param timeout_limit Numeric. Timeout in seconds.
#' @param method Character string. Download method for `utils::download.file()`.
#' @param quiet Logical. Whether to suppress download progress.
#' @param accept Function called as `accept(destfile, url)` after each
#'   download that is not empty. It returns `TRUE` to keep the download and
#'   stop. Any other value removes `destfile` and moves to the next mirror,
#'   so a mirror that serves an error page with status 200, a truncated
#'   file, or a file that fails a check does not end the search. `NULL`
#'   (the default) accepts every file that is not empty.
#'
#' @returns Logical. `TRUE` if any download succeeded, `FALSE` if all failed.
#'
#' @keywords internal
#' @noRd
try_download_from_mirrors <- function(
  urls,
  destfile,
  timeout_limit = 3600,
  method = "auto",
  quiet = TRUE,
  accept = NULL
) {
  for (url in urls) {
    success <- download_micromamba_file(
      url = url,
      destfile = destfile,
      timeout_limit = timeout_limit,
      method = method,
      quiet = quiet
    )
    if (isTRUE(success) && file.exists(destfile) && file.size(destfile) > 0L) {
      if (is.null(accept) || isTRUE(accept(destfile, url))) {
        return(TRUE)
      }
    }
    # Clean up failed download
    if (file.exists(destfile)) {
      base::try(file.remove(destfile), silent = TRUE)
    }
  }
  return(FALSE)
}
