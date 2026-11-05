test_that("Format Channels args", {
  expect_equal(format_channels_args(), c("-c", "conda-forge"))
  expect_equal(
    format_channels_args(NULL),
    c("-c", "conda-forge")
  )
  expect_equal(format_channels_args(NA), c("-c", NA_character_))
  expect_equal(format_channels_args(1), c("-c", "1"))
  expect_equal(format_channels_args("A", "BCD"), c("-c", "A", "-c", "BCD"))
})

testthat::test_that("a local channel with white space in its path gets a path without", {
  # Regression test (R-36): micromamba failed every create and install from
  # a local channel in a directory with a space, as a path and as a
  # `file://` URL ("Failed to parse URL"). condathis now passes another
  # path to the same directory: a link in `<root>/channels` (Linux,
  # macOS), or the short path (Windows).
  root <- as.character(install_dir_for_backend(micromamba_backend()))
  base <- fs::path(withr::local_tempdir(), "with space")
  channel_dir <- as.character(fs::path(base, "my channel"))
  fs::dir_create(fs::path(channel_dir, "noarch"))
  plain <- c("conda-forge", "/no/space", "file:///no/space", NA)
  testthat::expect_identical(micromamba_channel_arg(plain), plain)
  # A directory that does not exist is passed as it is.
  missing_dir <- as.character(fs::path(base, "missing dir"))
  testthat::expect_identical(micromamba_channel_arg(missing_dir), missing_dir)

  for (form in c("path", "url")) {
    channel <- if (identical(form, "path")) {
      channel_dir
    } else {
      local_file_url(channel_dir, encode = TRUE)
    }
    arg <- micromamba_channel_arg(channel)
    testthat::expect_match(arg, "^file://", info = form)
    testthat::expect_false(grepl("[[:space:]]", arg), info = form)
    new_path <- file_url_path(arg)
    if (isTRUE(is_windows())) {
      testthat::expect_identical(
        normalizePath(new_path, winslash = "/"),
        normalizePath(channel_dir, winslash = "/"),
        info = form
      )
    } else {
      testthat::expect_identical(
        as.character(fs::path_dir(new_path)),
        as.character(fs::path(root, "channels"))
      )
      testthat::expect_true(fs::is_link(new_path), info = form)
      testthat::expect_identical(
        as.character(fs::link_path(new_path)),
        as.character(fs::path_abs(channel_dir)),
        info = form
      )
    }
    # Shown as the URL of the directory, as rattler records it: on Windows
    # the long path of the short one, elsewhere the target of the link.
    shown_dir <- if (isTRUE(is_windows())) {
      normalizePath(channel_dir, winslash = "/")
    } else {
      as.character(fs::path_abs(channel_dir))
    }
    testthat::expect_identical(
      micromamba_channel_display(arg),
      local_file_url(shown_dir, encode = TRUE),
      info = form
    )
  }
  # The same directory always gets the same path, and a platform filter is
  # kept.
  arg <- micromamba_channel_arg(channel_dir)
  testthat::expect_identical(micromamba_channel_arg(channel_dir), arg)
  testthat::expect_identical(
    micromamba_channel_arg(fs::path(channel_dir, "linux-64")),
    paste0(arg, "/linux-64")
  )
  testthat::expect_identical(
    micromamba_channel_arg(paste0(channel_dir, "[linux-64]")),
    paste0(arg, "[linux-64]")
  )
  testthat::expect_identical(
    format_channels_args(channel_dir, "conda-forge"),
    c("-c", arg, "-c", "conda-forge")
  )
  testthat::expect_identical(
    micromamba_channel_display(c("conda-forge", "file:///no/space", NA)),
    c("conda-forge", "file:///no/space", NA)
  )
})

testthat::test_that("a local channel with white space stays as it is where no other path can be made", {
  # micromamba then fails as before (R-36): on a Windows volume without
  # short (8.3) names, and on Linux and macOS when the root of condathis has
  # white space, where no link is made either.
  base <- fs::path(withr::local_tempdir(), "with space")
  channel_dir <- as.character(fs::path(base, "my channel"))
  fs::dir_create(fs::path(channel_dir, "noarch"))
  channel_url <- local_file_url(channel_dir, encode = TRUE)
  spaced_root <- as.character(fs::path(base, "a root"))
  for (channel in c(channel_dir, channel_url)) {
    testthat::expect_identical(
      micromamba_channel_arg(
        channel,
        root_dir = spaced_root,
        on_windows = FALSE
      ),
      channel
    )
  }
  testthat::expect_false(fs::dir_exists(fs::path(spaced_root, "channels")))
  # Windows: `utils::shortPathName()` gives the long path back on a volume
  # without short names (elsewhere it does not exist).
  if (isTRUE(is_windows())) {
    testthat::local_mocked_bindings(
      shortPathName = function(path) path,
      .package = "utils"
    )
  }
  for (channel in c(channel_dir, channel_url)) {
    testthat::expect_identical(
      micromamba_channel_arg(channel, on_windows = TRUE),
      channel
    )
  }
})

testthat::test_that("micromamba installs from a local channel in a directory with a space", {
  testthat::skip_on_cran()
  # Regression test (R-36), end to end: create_env() and install_packages()
  # work, and the channel is reported as the URL of its directory, so
  # install_packages() does not warn that the environment's channel was
  # left out.
  base <- fs::path(withr::local_tempdir(), "with space")
  fs::dir_create(base)
  fs::dir_copy(
    file_url_path(polyglot_channel()),
    fs::path(base, "polyglot channel")
  )
  channel_dir <- normalizePath(
    fs::path(base, "polyglot channel"),
    winslash = "/"
  )
  env_name <- "format-channels-space-env"
  create_env(
    "polyglot",
    env_name = env_name,
    channels = channel_dir,
    verbose = "silent"
  )
  expected_url <- local_file_url(channel_dir, encode = TRUE)
  pkgs <- list_packages(env_name)
  testthat::expect_identical(pkgs$channel, expected_url)
  testthat::expect_identical(pkgs$base_url, expected_url)
  # The package URL too, not the link that micromamba got.
  testthat::expect_identical(
    pkgs$url,
    paste0(expected_url, "/noarch/polyglot-0.1.0-h4616a5c_0.conda")
  )
  testthat::expect_identical(
    get_env_history_channels(get_env_dir(env_name)),
    expected_url
  )
  testthat::expect_no_warning(
    res <- install_packages(
      "polyglot",
      env_name = env_name,
      channels = channel_dir,
      verbose = "silent"
    )
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    parse_output(run("polyglot", env_name = env_name, verbose = "silent"))[[
      1L
    ]],
    polyglot_expected_line()
  )
  # create_env() with the same request keeps the environment: its package
  # comes from the requested channel.
  res <- create_env(
    "polyglot",
    env_name = env_name,
    channels = local_file_url(channel_dir),
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  remove_env(env_name, verbose = "silent")
})
