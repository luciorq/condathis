#' Download a File with Robust Error Handling
#'
#' Downloads a file from a URL, preferring `curl::curl_download()` when the
#' `curl` package is available, falling back to `utils::download.file()`.
#' Wraps downloads in error handling so failures return `FALSE` instead of
#' throwing errors.
#'
#' @param url Character string. The URL to download from.
#' @param destfile Character string. The destination file path.
#' @param timeout_limit Numeric. Timeout in seconds for the download.
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

  withr::with_options(
    new = base::list(
      timeout = base::max(
        base::unlist(base::options("timeout")),
        timeout_limit
      )
    ),
    code = {
      dl_success <- tryCatch(
        {
          if (
            base::requireNamespace("curl", quietly = TRUE) &&
              utils::packageVersion("curl") >= "5.0.0"
          ) {
            curl::curl_download(
              url = url,
              destfile = destfile,
              quiet = quiet,
              mode = "wb"
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

#' Try Downloading from Multiple Mirror URLs
#'
#' Iterates through a list of URLs and attempts to download from each one
#' until one succeeds or all fail.
#'
#' @param urls Character vector. URLs to try in order.
#' @param destfile Character string. The destination file path.
#' @param timeout_limit Numeric. Timeout in seconds.
#' @param method Character string. Download method for `utils::download.file()`.
#' @param quiet Logical. Whether to suppress download progress.
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
  quiet = TRUE
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
      return(TRUE)
    }
    # Clean up failed download
    if (file.exists(destfile)) {
      try(file.remove(destfile), silent = TRUE)
    }
  }
  return(FALSE)
}
