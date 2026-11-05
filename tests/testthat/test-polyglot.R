# Offline tests: every environment here comes from the local polyglot
# channel (inst/extdata/polyglot-channel), so only the micromamba binary has to
# be downloaded, once. polyglot is a single `noarch` script that runs on
# Linux, macOS and Windows alike.

testthat::test_that("create_env() installs from a local file channel", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  res <- create_polyglot_env("polyglot-env")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_true(env_exists("polyglot-env"))

  pkgs <- list_packages("polyglot-env", verbose = "silent")
  testthat::expect_identical(pkgs$name, "polyglot")
  testthat::expect_identical(pkgs$version, "0.1.0")

  # Already satisfied: a second call does not reinstall.
  testthat::expect_identical(create_polyglot_env("polyglot-env")$status, 0L)
})

testthat::test_that("run(), run_bin() and run_pipeline() find the polyglot script", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  create_polyglot_env("polyglot-env")

  # On Windows this resolves `Scripts\polyglot.cmd` through PATHEXT, and
  # on Linux and macOS the extension-less `bin/polyglot`.
  for (fn in list(run, run_bin)) {
    res <- fn("polyglot", env_name = "polyglot-env", verbose = "silent")
    testthat::expect_identical(res$status, 0L)
    testthat::expect_identical(
      parse_output(res)[[1L]],
      polyglot_expected_line()
    )
  }

  # A pipeline whose stages come from one environment and read each other:
  # the second polyglot ignores its stdin.
  res <- run_pipeline(
    run_step("polyglot"),
    run_step("polyglot"),
    env_name = "polyglot-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$statuses, c(0L, 0L))
  testthat::expect_identical(parse_output(res)[[1L]], polyglot_expected_line())
})

testthat::test_that("install_packages() warns when a previous local channel is dropped", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  channel_a <- polyglot_channel("channel-a")
  channel_b <- polyglot_channel("channel-b")
  create_polyglot_env("polyglot-channels-env", channel = channel_a)

  testthat::expect_warning(
    res <- install_packages(
      "polyglot",
      env_name = "polyglot-channels-env",
      channels = channel_b,
      verbose = "silent"
    ),
    class = "condathis_install_missing_previous_channels"
  )
  testthat::expect_identical(res$status, 0L)

  testthat::expect_no_warning(
    install_packages(
      "polyglot",
      env_name = "polyglot-channels-env",
      channels = c(channel_a, channel_b),
      verbose = "silent"
    ),
    class = "condathis_install_missing_previous_channels"
  )
})

testthat::test_that("remove_env() removes a polyglot environment", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  create_polyglot_env("polyglot-remove-env")

  remove_env("polyglot-remove-env", verbose = "silent")
  testthat::expect_false(env_exists("polyglot-remove-env"))
})

testthat::test_that("create_env() and install_packages() errors say why micromamba failed", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  # Regression test: micromamba ran with `--quiet`, which also hid its error
  # messages, so these errors had no text at any verbose level below "full".
  for (verbose in c("silent", "output")) {
    cnd <- rlang::catch_cnd(
      create_env(
        "no-such-package-in-channel",
        env_name = "polyglot-missing-env",
        channels = polyglot_channel(),
        verbose = verbose
      ),
      classes = "condathis_cmd_status_error"
    )
    testthat::expect_s3_class(cnd, "condathis_cmd_status_error")
    # The backend's class is kept under the classes of rule R1, and the
    # backend's error stays the parent.
    testthat::expect_s3_class(cnd, "condathis_create_env_failed")
    testthat::expect_s3_class(cnd, "condathis_backend_error")
    testthat::expect_s3_class(cnd$parent, "condathis_cmd_status_error")
    testthat::expect_match(
      conditionMessage(cnd),
      "no-such-package-in-channel",
      fixed = TRUE,
      info = verbose
    )
  }

  create_polyglot_env("polyglot-missing-install-env")
  cnd <- rlang::catch_cnd(
    install_packages(
      "no-such-package-in-channel",
      env_name = "polyglot-missing-install-env",
      channels = polyglot_channel(),
      verbose = "silent"
    ),
    classes = "condathis_cmd_status_error"
  )
  testthat::expect_s3_class(cnd, "condathis_cmd_status_error")
  testthat::expect_s3_class(cnd, "condathis_install_packages_failed")
  testthat::expect_match(
    conditionMessage(cnd),
    "no-such-package-in-channel",
    fixed = TRUE
  )
})

testthat::test_that("install_packages() does not create a missing custom environment with micromamba", {
  # Decision D3: a typo in env_name must not create an environment.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "polyglot-never-created-env"
  testthat::expect_error(
    install_packages(
      "polyglot",
      env_name = env_name,
      channels = polyglot_channel(),
      verbose = "silent"
    ),
    class = "condathis_install_packages_env_not_found"
  )
  testthat::expect_false(env_exists(env_name))
  testthat::expect_false(fs::dir_exists(get_env_dir(env_name)))
})

testthat::test_that("create_env() does not echo micromamba's progress output", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  out <- testthat::capture_output(suppressMessages(create_env(
    "polyglot",
    env_name = "polyglot-quiet-env",
    channels = polyglot_channel(),
    verbose = "output"
  )))
  testthat::expect_identical(out, "")
})

testthat::test_that("a local channel given as a plain path counts as the same channel", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  # micromamba records a channel passed as a path as a `file://` URL.
  channel_dir <- system.file(
    "extdata",
    "polyglot-channel",
    package = "condathis",
    mustWork = TRUE
  )
  create_polyglot_env("polyglot-path-env", channel = channel_dir)
  testthat::expect_no_warning(
    install_packages(
      "polyglot",
      env_name = "polyglot-path-env",
      channels = channel_dir,
      verbose = "silent"
    ),
    class = "condathis_install_missing_previous_channels"
  )
})

testthat::test_that("a root and a local channel under a /t/<word>/ directory work", {
  # Regression test: micromamba 2.9.0 and later hide every `/t/<word>` of
  # their JSON output as a channel token, paths included (see
  # `hide_secrets()`). Under such a root, list_envs() listed no environment,
  # so every call that names one aborted with condathis_env_not_found. The
  # history channel of a local channel under such a directory is read with
  # that part hidden, and install_packages() warned that the same channel,
  # passed again, was left out.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  local_sandbox_micromamba()

  base_dir <- withr::local_tempdir()
  channel_dir <- fs::path(base_dir, "t", "chan1", "polyglot-channel")
  fs::dir_create(fs::path_dir(channel_dir))
  fs::dir_copy(
    system.file(
      "extdata",
      "polyglot-channel",
      package = "condathis",
      mustWork = TRUE
    ),
    channel_dir
  )
  channel <- local_file_url(
    normalizePath(channel_dir, winslash = "/", mustWork = TRUE)
  )
  withr::local_envvar(
    R_USER_DATA_DIR = fs::path(base_dir, "t", "proj1", "data")
  )
  root <- install_dir_for_backend(micromamba_backend())
  testthat::expect_match(root, "/t/proj1/", fixed = TRUE)
  env_name <- "polyglot-t-dir-env"

  res <- create_polyglot_env(env_name, channel = channel)
  testthat::expect_identical(res$status, 0L)
  envs <- list_envs(verbose = "silent")
  testthat::expect_identical(envs$env_name, env_name)
  testthat::expect_true(env_exists(env_name))
  testthat::expect_identical(
    as.character(get_env_dir(env_name)),
    as.character(fs::path(root, "envs", env_name))
  )
  pkgs <- list_packages(env_name, verbose = "silent")
  testthat::expect_identical(pkgs$name, "polyglot")
  testthat::expect_identical(
    normalize_channel_name(pkgs$channel),
    normalize_channel_name(channel)
  )

  testthat::expect_no_warning(
    res <- install_packages(
      "polyglot",
      env_name = env_name,
      channels = channel,
      verbose = "silent"
    ),
    class = "condathis_install_missing_previous_channels"
  )
  testthat::expect_identical(res$status, 0L)
  # Already satisfied: nothing runs.
  testthat::expect_message(
    res <- create_env(
      "polyglot",
      env_name = env_name,
      channels = channel,
      verbose = "output"
    ),
    regexp = "already has the requested packages"
  )
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_true(
    validate_env("polyglot", env_name = env_name, channels = channel)
  )
  res <- run("polyglot", env_name = env_name, verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(parse_output(res)[[1L]], polyglot_expected_line())

  remove_env(env_name, verbose = "silent")
  testthat::expect_false(env_exists(env_name))
  testthat::expect_false(fs::dir_exists(fs::path(root, "envs", env_name)))
})
