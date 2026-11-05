# The local conda channel shipped in inst/extdata/polyglot-channel, which
# the examples use too, as a `file://` URL.
# See inst/extdata/polyglot-channel/README.md.
#
# `name` gives the channel a different directory name, copied into a
# temporary directory: two channels with different names, for tests that
# compare the channels an environment was built from.
polyglot_channel <- function(name = NULL, .local_envir = parent.frame()) {
  channel_dir <- system.file(
    "extdata",
    "polyglot-channel",
    package = "condathis",
    mustWork = TRUE
  )
  if (isFALSE(is.null(name))) {
    copy_dir <- fs::path(
      withr::local_tempdir(.local_envir = .local_envir),
      name
    )
    fs::dir_copy(channel_dir, copy_dir)
    channel_dir <- copy_dir
  }
  channel_dir <- normalizePath(channel_dir, winslash = "/", mustWork = TRUE)
  # `file:///C:/...` on Windows, `file:///home/...` elsewhere.
  return(paste0("file://", if (isTRUE(is_windows())) "/", channel_dir))
}

# The first line `polyglot` prints on this platform.
polyglot_expected_line <- function() {
  if (isTRUE(is_windows())) {
    return("System detected: Windows")
  }
  return("System detected: Linux/Unix")
}

# Tests that create environments from the local channel need no network,
# only a micromamba binary, which is downloaded once when missing.
skip_if_no_micromamba_offline <- function() {
  if (is.null(get_best_micromamba_path())) {
    testthat::skip_if_offline()
  }
}

# A `polyglot` environment built from the local channel.
create_polyglot_env <- function(env_name, channel = polyglot_channel()) {
  create_env(
    "polyglot",
    env_name = env_name,
    channels = channel,
    verbose = "silent"
  )
}

# The micromamba binary of the test process, for code inside
# `with_sandbox_dir()`: the fresh root of a sandbox has none, and
# `native_cmd()` would download one. With the option, it uses this one,
# so such tests run offline once the test process has a binary. Call it
# before `with_sandbox_dir()`.
local_sandbox_micromamba <- function(envir = parent.frame()) {
  umamba_path <- get_best_micromamba_path()
  if (is.null(umamba_path)) {
    testthat::skip_if_offline()
    suppressMessages(install_micromamba(verbose = "silent"))
    umamba_path <- get_best_micromamba_path()
  }
  withr::local_options(
    condathis.micromamba_path = as.character(umamba_path),
    .local_envir = envir
  )
  return(invisible(umamba_path))
}
