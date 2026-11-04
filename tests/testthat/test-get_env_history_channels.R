# get_env_history_channels() reads the history file of the directory it is
# given, so these tests need no backend and start no process.

local_history_dir <- function(lines, envir = parent.frame()) {
  env_dir <- withr::local_tempdir(.local_envir = envir)
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  writeLines(lines, con = fs::path(env_dir, "conda-meta", "history"))
  return(env_dir)
}

testthat::test_that("get_env_history_channels returns empty for missing history", {
  testthat::expect_identical(
    get_env_history_channels(env_dir = withr::local_tempdir()),
    character(0L)
  )
  testthat::expect_identical(
    get_env_history_channels(
      env_dir = fs::path(withr::local_tempdir(), "no-such-env")
    ),
    character(0L)
  )
})

testthat::test_that("get_env_history_channels parses channels from history file", {
  env_dir <- local_history_dir(c(
    "==> 2026-01-01 00:00:00 <==",
    "# cmd: micromamba create -n hist-env -c conda-forge python",
    "# conda version: 3.8.0",
    "+https://conda.anaconda.org/conda-forge/linux-64::python-3.11.0-0",
    "# update specs: [\"python\"]",
    "==> 2026-01-02 00:00:00 <==",
    "# cmd: micromamba install -n hist-env -c bioconda fastqc",
    "# conda version: 3.8.0",
    "+https://conda.anaconda.org/bioconda/linux-64::fastqc-0.11.5-1",
    "# update specs: [\"fastqc\"]"
  ))
  testthat::expect_setequal(
    get_env_history_channels(env_dir = env_dir),
    c("conda-forge", "bioconda")
  )
})

testthat::test_that("get_env_history_channels reads local file channels and other hosts", {
  # Regression test: only http(s) URLs were recognized, so packages from a
  # local `file://` channel left no channel behind. A channel on another
  # host was reduced to its path (`universe`), which did not compare equal
  # to the URL the user passes.
  env_dir <- local_history_dir(c(
    "+file:///tmp/channels/channel-a/noarch::polyglot-0.1.0-h4616a5c_0",
    "+file:///C:/Users/me/channel-b/noarch::polyglot-0.1.0-h4616a5c_0",
    "+https://repo.prefix.dev/universe/noarch::polyglot-0.1.0-h4616a5c_0",
    "+https://conda.anaconda.org/conda-forge/label/main/noarch::x-1-0"
  ))
  channels <- get_env_history_channels(env_dir = env_dir)
  testthat::expect_setequal(
    channels,
    c(
      "file:///tmp/channels/channel-a",
      "file:///C:/Users/me/channel-b",
      "https://repo.prefix.dev/universe",
      "conda-forge/label/main"
    )
  )
  # Each channel a user passes compares equal to one history channel.
  user_channels <- c(
    "/tmp/channels/channel-a",
    "C:/Users/me/channel-b",
    "https://repo.prefix.dev/universe",
    "https://conda.anaconda.org/conda-forge/label/main"
  )
  testthat::expect_setequal(
    normalize_channel_name(user_channels),
    normalize_channel_name(channels)
  )
})

testthat::test_that("install_packages reads the history of the resolved backend's directory", {
  # micromamba-cheap-probe: the history check takes the directory of the
  # backend that install_packages() already resolved, instead of calling
  # get_env_dir(), which resolved and probed every backend again.
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "micromamba",
    backend_probe_env = function(...) TRUE,
    find_owning_backends = function(...) "micromamba",
    get_env_dir = function(...) stop("get_env_dir() must not be called"),
    backend_install = function(...) list(status = 0L)
  )
  res <- install_packages("zlib", env_name = "hist-check-env", verbose = FALSE)
  testthat::expect_identical(res$status, 0L)
})
