rlang_tail <- c("rlang_error", "error", "condition")

catch_error <- function(expr) {
  return(rlang::catch_cnd(expr, classes = "error"))
}

# A package listing with the six columns of the backend contract.
validate_pkgs_df <- function(name, version = "1.0", platform = "noarch") {
  n <- length(name)
  return(data.frame(
    name = as.character(name),
    version = rep_len(as.character(version), n),
    build_number = rep_len(0L, n),
    build_string = rep_len("h0_0", n),
    channel = rep_len("conda-forge", n),
    platform = rep_len(as.character(platform), n),
    stringsAsFactors = FALSE
  ))
}

# A stub backend (helper-stub-backend.R) that is the only backend condathis
# sees in this test, so no test here reaches micromamba.
local_validate_stub <- function(
  name,
  envs = character(0L),
  packages = validate_pkgs_df(character(0L)),
  ...,
  envir = parent.frame()
) {
  # An explicit `backend_list_packages` in `...` replaces the listing.
  overrides <- list(...)
  if (isFALSE("backend_list_packages" %in% names(overrides))) {
    overrides$backend_list_packages <- function(backend, ...) packages
  }
  stub <- do.call(
    local_stub_backend,
    c(list(name), overrides, list(envs = envs, envir = envir))
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() name,
    .env = envir
  )
  return(stub)
}

testthat::test_that("validate_env() validates its arguments before any backend call", {
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  invalid_packages <- c(
    "condathis_validate_env_invalid_packages",
    "condathis_invalid_packages",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  for (bad in list(NA, "", 1L, NULL)) {
    testthat::expect_identical(
      class(catch_error(validate_env("zlib", bad))),
      invalid_packages,
      info = deparse(bad)
    )
  }
  cnd <- catch_error(validate_env("zlib", plaform = "linux-64"))
  testthat::expect_identical(class(cnd), invalid_packages)
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Did you mean `platform`?",
    fixed = TRUE
  )
  cnd <- catch_error(validate_env(env_name = "../x"))
  testthat::expect_s3_class(cnd, "condathis_validate_env_invalid_env_name")
  testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
  testthat::expect_s3_class(
    catch_error(validate_env(method = "no-such-backend")),
    "condathis_invalid_method_arg"
  )
  testthat::expect_identical(
    class(catch_error(validate_env(verbose = "bogus"))),
    c(
      "condathis_invalid_verbose",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  for (platform in list(
    c("a", "b"),
    "linux64",
    "bogus",
    "osx_arm64",
    NA_character_
  )) {
    cnd <- catch_error(validate_env("zlib", platform = platform))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_validate_env_invalid_platform",
        "condathis_invalid_platform",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(platform)
    )
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "Known platforms are lower case, such as",
      fixed = TRUE,
      info = deparse(platform)
    )
  }
  cnd <- catch_error(validate_env(error = "ignore"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_invalid_error",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_identical(
    conditionCall(cnd),
    quote(validate_env(error = "ignore"))
  )
})

testthat::test_that("validate_env() rejects an env_path() value", {
  # It takes environment names only, as create_env() and install_packages().
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  cnd <- catch_error(validate_env(env_name = env_path(withr::local_tempdir())))
  testthat::expect_s3_class(cnd, "condathis_env_path_read_only")
  testthat::expect_s3_class(cnd, "condathis_validate_env_invalid_env_name")
  testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
  testthat::expect_s3_class(cnd, "condathis_error")
})

testthat::test_that("validate_env() returns TRUE invisibly for a satisfied request", {
  local_validate_stub(
    "stub-validate-ok",
    envs = "ok-env",
    packages = validate_pkgs_df(c("zlib", "python"), c("1.3.1", "3.13.0"))
  )
  res <- withVisible(validate_env(
    "zlib>=1.3",
    "python=3.13",
    env_name = "ok-env"
  ))
  testthat::expect_identical(res$value, TRUE)
  testthat::expect_false(res$visible)
  # A vector of specs works as in create_env().
  testthat::expect_true(validate_env(c("zlib", "python"), env_name = "ok-env"))
  testthat::expect_no_message(validate_env("zlib", env_name = "ok-env"))
  testthat::expect_message(
    validate_env("zlib", env_name = "ok-env", verbose = "output"),
    regexp = "has the requested packages"
  )
})

testthat::test_that("validate_env() with no specs only checks that the environment exists", {
  stub <- local_validate_stub("stub-validate-exists", envs = "here-env")
  testthat::expect_true(validate_env(env_name = "here-env"))
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 0L)
})

testthat::test_that("validate_env() reports unsatisfied specs", {
  local_validate_stub(
    "stub-validate-unsatisfied",
    envs = "unsat-env",
    packages = validate_pkgs_df("zlib", "1.3.1")
  )
  cnd <- catch_error(
    validate_env("zlib>=2", "python", "zlib", env_name = "unsat-env")
  )
  testthat::expect_identical(
    class(cnd),
    c("condathis_validate_env_unsatisfied", "condathis_error", rlang_tail)
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "zlib>=2", fixed = TRUE)
  testthat::expect_match(message, "python", fixed = TRUE)
  testthat::expect_match(message, "install_packages()", fixed = TRUE)
  testthat::expect_match(message, "create_env(overwrite = TRUE)", fixed = TRUE)

  res <- validate_env(
    "zlib>=2",
    "python",
    "zlib",
    env_name = "unsat-env",
    error = "continue"
  )
  testthat::expect_false(res)
  testthat::expect_identical(attr(res, "reason"), "unsatisfied")
  testthat::expect_identical(attr(res, "unsatisfied"), c("zlib>=2", "python"))
})

testthat::test_that("validate_env() says why a spec with uncompared brackets is not satisfied", {
  local_validate_stub(
    "stub-validate-brackets",
    envs = "brackets-env",
    packages = validate_pkgs_df("zlib", "1.3.1")
  )
  # Compared bracket keys work, with names in any case.
  testthat::expect_true(validate_env(
    "ZLIB[version='>=1.3', build_number=0]",
    env_name = "brackets-env"
  ))
  cnd <- catch_error(
    validate_env("zlib[md5=abc]", "python", env_name = "brackets-env")
  )
  testthat::expect_s3_class(cnd, "condathis_validate_env_unsatisfied")
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "Not satisfied:", fixed = TRUE)
  testthat::expect_match(
    message,
    "\"zlib[md5=abc]\" never counts as satisfied",
    fixed = TRUE
  )
  # Without such a spec, the message has no bracket bullet.
  message <- cli::ansi_strip(conditionMessage(
    catch_error(validate_env("python", env_name = "brackets-env"))
  ))
  testthat::expect_no_match(message, "never count", fixed = TRUE)
})

testthat::test_that("validate_env() reports a platform mismatch first", {
  local_validate_stub(
    "stub-validate-platform",
    envs = "platform-env",
    packages = validate_pkgs_df(
      c("zlib", "tzdata"),
      platform = c("osx-64", "noarch")
    )
  )
  testthat::expect_true(
    validate_env("zlib", env_name = "platform-env", platform = "osx-64")
  )
  res <- validate_env(
    "zlib",
    "python",
    env_name = "platform-env",
    platform = "linux-64",
    error = "continue"
  )
  testthat::expect_false(res)
  testthat::expect_identical(attr(res, "reason"), "platform_mismatch")
  testthat::expect_identical(attr(res, "unsatisfied"), "python")
  cnd <- catch_error(
    validate_env("zlib", env_name = "platform-env", platform = "linux-64")
  )
  testthat::expect_s3_class(cnd, "condathis_validate_env_unsatisfied")
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "osx-64", fixed = TRUE)
  testthat::expect_match(message, "linux-64", fixed = TRUE)
})

testthat::test_that("validate_env() reports a missing environment and creates nothing", {
  # It is a query: also a missing "condathis-env" is not created.
  stub <- local_validate_stub("stub-validate-missing")
  for (env_name in c("never-created", "condathis-env")) {
    cnd <- catch_error(validate_env("zlib", env_name = env_name))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_validate_env_env_not_found",
        "condathis_env_not_found",
        "condathis_error",
        rlang_tail
      ),
      info = env_name
    )
    res <- validate_env("zlib", env_name = env_name, error = "continue")
    testthat::expect_false(res)
    testthat::expect_identical(attr(res, "reason"), "env_not_found")
    testthat::expect_identical(attr(res, "unsatisfied"), "zlib")
  }
  testthat::expect_false(validate_env(error = "continue"))
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
  testthat::expect_length(
    fs::dir_ls(fs::path(stub$root, "envs"), type = "directory"),
    0L
  )
})

testthat::test_that("validate_env() reports a backend failure, also after a failed probe", {
  # Rule R5: a failed probe is not read as "absent". The listing then
  # reports the backend's real error.
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  local_validate_stub(
    "stub-validate-boom",
    backend_env_exists = stub_boom,
    backend_list_packages = stub_boom
  )
  cnd <- suppressWarnings(
    catch_error(validate_env(
      "zlib",
      env_name = "boom-env",
      error = "continue"
    )),
    classes = "condathis_backend_query_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_validate_env_failed")
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_true(rlang::cnd_inherits(cnd, "stub_boom"))
})

testthat::test_that("validate_env() validates channels before any backend call", {
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  invalid_channels <- c(
    "condathis_validate_env_invalid_channels",
    "condathis_invalid_channels",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  for (bad in list(character(0L), NA_character_, "", c("conda-forge", NA), 1)) {
    testthat::expect_identical(
      class(catch_error(validate_env("zlib", channels = bad))),
      invalid_channels,
      info = deparse(bad)
    )
  }
  cnd <- catch_error(validate_env(channels = ""))
  testthat::expect_identical(
    conditionCall(cnd),
    quote(validate_env(channels = ""))
  )
  # Regression test: the message said only "a non-empty character vector",
  # although validate_env() also accepts NULL.
  for (bad in list("", character(0L))) {
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(
        catch_error(validate_env("zlib", channels = bad))
      )),
      "`channels` must be `NULL` or a non-empty character vector",
      fixed = TRUE,
      info = deparse(bad)
    )
  }
})

testthat::test_that("validate_env() points additional_channels to channels", {
  # Regression test: a create_env() call moved to validate_env() aborted
  # with "Package specs in `...` must be unnamed." and no hint that
  # validate_env() takes every channel in `channels`.
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  cnd <- catch_error(validate_env(
    "zlib",
    env_name = "x",
    additional_channels = "bioconda"
  ))
  testthat::expect_s3_class(cnd, "condathis_validate_env_invalid_packages")
  msg <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(
    msg,
    "`additional_channels` is not an argument of `validate_env()`",
    fixed = TRUE
  )
  testthat::expect_match(
    msg,
    "channels = c(channels, additional_channels)",
    fixed = TRUE
  )
  # Another unknown name keeps the generic hint.
  msg <- cli::ansi_strip(conditionMessage(catch_error(
    validate_env("zlib", env_name = "x", other_arg = 1)
  )))
  testthat::expect_no_match(msg, "additional_channels", fixed = TRUE)
})

# A listing with packages from six channels, as micromamba reports them:
# a channel on conda.anaconda.org by name, a channel of `defaults` as
# `pkgs/<name>`, any other channel by URL, without credentials.
validate_channels_df <- function() {
  return(data.frame(
    name = c(
      "zlib",
      "python",
      "tzdata",
      "samtools",
      "polyglot",
      "tokpkg",
      "mainpkg"
    ),
    version = c("1.3.1", "3.13.0", "2025b", "1.20", "0.1.0", "1.0", "1.0"),
    build_number = 0L,
    build_string = "h0_0",
    channel = c(
      "conda-forge",
      "conda-forge",
      "conda-forge",
      "bioconda",
      "file:///srv/channels/polyglot-channel",
      "http://127.0.0.1:18765/private-channel",
      "pkgs/main"
    ),
    platform = c(
      "linux-64",
      "linux-64",
      "noarch",
      "linux-64",
      "noarch",
      "noarch",
      "linux-64"
    ),
    stringsAsFactors = FALSE
  ))
}

testthat::test_that("validate_env() checks the channel of a spec without one only with channels", {
  local_validate_stub(
    "stub-validate-channels",
    envs = "channel-env",
    packages = validate_channels_df()
  )
  validated <- function(..., channels = NULL) {
    return(validate_env(
      ...,
      env_name = "channel-env",
      channels = channels,
      error = "continue"
    ))
  }
  # NULL: any channel.
  testthat::expect_true(validated("samtools", "zlib", "polyglot"))
  # A channel vector rejects a package from another channel.
  res <- validated("samtools", "zlib", channels = "conda-forge")
  testthat::expect_false(res)
  testthat::expect_identical(attr(res, "reason"), "unsatisfied")
  testthat::expect_identical(attr(res, "unsatisfied"), "samtools")
  cnd <- catch_error(
    validate_env("samtools", env_name = "channel-env", channels = "conda-forge")
  )
  testthat::expect_s3_class(cnd, "condathis_validate_env_unsatisfied")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Not satisfied: \"samtools\"",
    fixed = TRUE
  )
  # ... and accepts one from the right channel.
  testthat::expect_true(validated("samtools", channels = "bioconda"))
  testthat::expect_true(validated(
    "samtools",
    "zlib",
    channels = c("conda-forge", "bioconda")
  ))
  testthat::expect_false(validated("zlib", channels = "bioconda"))
  # A spec with a channel ignores `channels`.
  testthat::expect_true(validated(
    "bioconda::samtools",
    channels = "conda-forge"
  ))
  testthat::expect_false(validated(
    "conda-forge::samtools",
    channels = "bioconda"
  ))
  testthat::expect_true(validated(
    "samtools[channel=bioconda]",
    channels = "conda-forge"
  ))
  # URLs and local paths are compared as in create_env().
  testthat::expect_true(validated(
    "samtools",
    channels = "https://conda.anaconda.org/bioconda/"
  ))
  testthat::expect_true(validated(
    "polyglot",
    channels = "file:///srv/channels/polyglot-channel"
  ))
  testthat::expect_true(validated(
    "polyglot",
    channels = "/srv/channels/polyglot-channel"
  ))
  testthat::expect_false(validated(
    "polyglot",
    channels = "https://repo.prefix.dev/polyglot-channel"
  ))
})

testthat::test_that("validate_env() and create_env(overwrite = FALSE) give the same answer", {
  # Decision D4: one internal check. With the same channels, the two cannot
  # disagree: validate_env(channels = c(channels, additional_channels)).
  stub <- local_validate_stub(
    "stub-validate-parity",
    envs = "parity-env",
    packages = validate_channels_df()
  )
  cf <- "conda-forge"
  local_channel <- "file:///srv/channels/polyglot-channel"
  token_url <- "http://127.0.0.1:18765/t/tk-0123456789abcdef/private-channel"
  auth_url <- "http://user:s3cr3t@127.0.0.1:18765/private-channel"
  # specs, channels, additional_channels, platform, expected answer.
  cases <- list(
    # Credentials, a platform filter and `defaults`, as micromamba records
    # them, and a local channel with the same directory name elsewhere.
    list("tokpkg", token_url, NULL, NULL, TRUE),
    list("tokpkg", cf, auth_url, NULL, TRUE),
    list("tokpkg", "http://127.0.0.1:18765/other-channel", NULL, NULL, FALSE),
    list("mainpkg", "defaults", NULL, NULL, TRUE),
    list("mainpkg", cf, "defaults", NULL, TRUE),
    list("defaults::mainpkg", cf, NULL, NULL, TRUE),
    list("mainpkg", cf, NULL, NULL, FALSE),
    list("zlib", "defaults", NULL, NULL, FALSE),
    list("polyglot", paste0(local_channel, "/noarch"), NULL, NULL, TRUE),
    list("zlib", "conda-forge/linux-64", NULL, NULL, TRUE),
    list("polyglot", "/srv/other/polyglot-channel", NULL, NULL, FALSE),
    list("zlib", cf, NULL, NULL, TRUE),
    list(c("zlib>=1.3", "python=3.13"), cf, NULL, NULL, TRUE),
    list("zlib<1", cf, NULL, NULL, FALSE),
    list("missing-pkg", cf, NULL, NULL, FALSE),
    list("conda-forge::zlib", "bioconda", NULL, NULL, TRUE),
    list("bioconda::zlib", cf, NULL, NULL, FALSE),
    list("zlib[build_number=0]", cf, NULL, NULL, TRUE),
    list("zlib[build_number=1]", cf, NULL, NULL, FALSE),
    list("zlib[md5=abc]", cf, NULL, NULL, FALSE),
    list(c("ZLIB", "Python>=3.13"), cf, NULL, NULL, TRUE),
    list("samtools", cf, NULL, NULL, FALSE),
    list("samtools", cf, "bioconda", NULL, TRUE),
    list("samtools", c(cf, "bioconda"), NULL, NULL, TRUE),
    list("samtools", "https://conda.anaconda.org/bioconda", NULL, NULL, TRUE),
    list("bioconda::samtools", cf, NULL, NULL, TRUE),
    list("conda-forge::samtools", c(cf, "bioconda"), NULL, NULL, FALSE),
    list("polyglot", cf, NULL, NULL, FALSE),
    list("polyglot", local_channel, NULL, NULL, TRUE),
    list("polyglot", cf, "/srv/channels/polyglot-channel", NULL, TRUE),
    list("zlib", cf, NULL, "linux-64", TRUE),
    list("zlib", cf, NULL, "osx-arm64", FALSE),
    list(character(0L), "bioconda", NULL, NULL, TRUE),
    list(character(0L), cf, NULL, "win-64", FALSE)
  )
  for (case in cases) {
    names(case) <- c("specs", "channels", "additional", "platform", "expected")
    info <- paste(
      c(case$specs, "|", case$channels, "|", case$additional, case$platform),
      collapse = " "
    )
    validated <- validate_env(
      case$specs,
      env_name = "parity-env",
      channels = c(case$channels, case$additional),
      platform = case$platform,
      error = "continue"
    )
    created <- tryCatch(
      {
        create_env(
          case$specs,
          env_name = "parity-env",
          channels = case$channels,
          additional_channels = case$additional,
          platform = case$platform,
          verbose = "silent"
        )
        TRUE
      },
      condathis_create_env_exists = function(e) FALSE,
      condathis_create_env_platform_mismatch = function(e) FALSE
    )
    testthat::expect_identical(isTRUE(validated), case$expected, info = info)
    testthat::expect_identical(created, case$expected, info = info)
  }
  # create_env() never replaced the environment.
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("validate_env() and create_env() differ only where validate_env() only reads", {
  # The two exceptions the documentation of validate_env() names. Both come
  # from resolve_backend(mutating = FALSE) for a query.
  cf_zlib <- function(backend, ...) {
    return(validate_pkgs_df("zlib", platform = "linux-64"))
  }
  local_stub_backend(
    "stub-owner-a",
    envs = "own-env",
    backend_list_packages = cf_zlib
  )
  stub_b <- local_stub_backend("stub-owner-b", backend_list_packages = cf_zlib)
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-owner-a", "stub-owner-b")
  )
  # 1. `method` names a backend that does not own the environment.
  testthat::expect_warning(
    validated <- validate_env(
      "zlib",
      env_name = "own-env",
      channels = "conda-forge",
      method = "stub-owner-b",
      error = "continue"
    ),
    class = "condathis_backend_mismatch_warning"
  )
  testthat::expect_true(validated)
  testthat::expect_error(
    create_env(
      "zlib",
      env_name = "own-env",
      method = "stub-owner-b",
      verbose = "silent"
    ),
    class = "condathis_backend_mismatch"
  )
  testthat::expect_length(stub_calls(stub_b, "backend_create_env"), 0L)
})

testthat::test_that("validate_env() lists the packages when the probe fails, and create_env() aborts", {
  local_validate_stub(
    "stub-validate-probe",
    packages = validate_pkgs_df("zlib", platform = "linux-64"),
    backend_env_exists = function(...) {
      rlang::abort("cannot tell", class = "stub_probe")
    }
  )
  validated <- suppressWarnings(
    validate_env("zlib", env_name = "probe-env", channels = "conda-forge"),
    classes = "condathis_backend_query_failed"
  )
  testthat::expect_true(validated)
  testthat::expect_error(
    create_env("zlib", env_name = "probe-env", verbose = "silent"),
    class = "condathis_backend_probe_failed"
  )
})

testthat::test_that("validate_env() catches an old positional env_name", {
  local_validate_stub("stub-validate-positional", envs = "my-env")
  cnd <- catch_error(validate_env("python", "my-env"))
  testthat::expect_s3_class(cnd, "condathis_validate_env_positional_env_name")
  testthat::expect_s3_class(cnd, "condathis_error")
})

testthat::test_that("validate_env() accepts packages = as a deprecated alias", {
  id <- "deprecated_packages_arg_validate_env"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  local_validate_stub(
    "stub-validate-alias",
    envs = "alias-env",
    packages = validate_pkgs_df("zlib")
  )
  testthat::expect_warning(
    res <- validate_env(packages = "zlib", env_name = "alias-env"),
    class = "condathis_deprecated_packages_arg"
  )
  testthat::expect_true(res)
})

testthat::test_that("validate_env() reports a missing micromamba environment without a process", {
  # Decision D3 and micromamba-cheap-probe: on a fresh root, the query
  # neither runs nor installs micromamba.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("native_cmd() must not be called"),
      install_micromamba = function(...) {
        stop("install_micromamba() must not be called")
      }
    )
    res <- validate_env(
      "polyglot",
      env_name = "fresh-env",
      method = "micromamba",
      error = "continue"
    )
    testthat::expect_false(res)
    testthat::expect_identical(attr(res, "reason"), "env_not_found")
    testthat::expect_error(
      validate_env(env_name = "fresh-env"),
      class = "condathis_validate_env_env_not_found"
    )
    envs_dir <- fs::path(get_condathis_path(), "envs")
    if (isTRUE(fs::dir_exists(envs_dir))) {
      testthat::expect_length(fs::dir_ls(envs_dir, type = "directory"), 0L)
    }
  })
})

testthat::test_that("validate_env() works on a fresh root without creating an environment", {
  # Decision D3: a query works before any environment exists, and creates
  # no environment. The root directory may be created.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  umamba <- get_best_micromamba_path()
  if (is.null(umamba)) {
    suppressMessages(install_micromamba(verbose = "silent"))
    umamba <- micromamba_bin_path()
  }

  condathis::with_sandbox_dir({
    withr::local_options(
      list(condathis.micromamba_path = as.character(umamba))
    )
    res <- validate_env("polyglot", env_name = "fresh-env", error = "continue")
    testthat::expect_false(res)
    testthat::expect_identical(attr(res, "reason"), "env_not_found")
    testthat::expect_error(
      validate_env(env_name = "fresh-env"),
      class = "condathis_validate_env_env_not_found"
    )
    testthat::expect_false(validate_env(error = "continue"))
    envs_dir <- fs::path(
      install_dir_for_backend(micromamba_backend()),
      "envs"
    )
    if (isTRUE(fs::dir_exists(envs_dir))) {
      testthat::expect_length(fs::dir_ls(envs_dir, type = "directory"), 0L)
    }
    testthat::expect_false(env_exists("condathis-env"))
  })
})

testthat::test_that("validate_env() checks a real micromamba environment", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "condathis-validate-env-test-env"
  create_env(
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel(),
    verbose = "silent"
  )
  withr::defer(remove_env(env_name, verbose = "silent"))
  testthat::expect_true(validate_env("polyglot=0.1.0", env_name = env_name))
  res <- validate_env("polyglot>=2", env_name = env_name, error = "continue")
  testthat::expect_false(res)
  testthat::expect_identical(attr(res, "unsatisfied"), "polyglot>=2")

  # micromamba records the local channel as a `file://` URL. The channel
  # given as that URL or as a plain path matches it, as in create_env().
  channel_path <- normalizePath(
    system.file("extdata", "polyglot-channel", package = "condathis"),
    winslash = "/"
  )
  # A copy of the channel with the same directory name, elsewhere: another
  # channel, which the environment was not built from.
  same_name_elsewhere <- polyglot_channel(name = "polyglot-channel")
  rejected <- list("conda-forge", same_name_elsewhere)
  for (channels in list(
    NULL,
    polyglot_channel(),
    channel_path,
    paste0(polyglot_channel(), "/noarch"),
    paste0(channel_path, "/"),
    "conda-forge",
    same_name_elsewhere
  )) {
    expected <- isFALSE(any(vapply(rejected, identical, logical(1L), channels)))
    validated <- validate_env(
      "polyglot",
      env_name = env_name,
      channels = channels,
      error = "continue"
    )
    testthat::expect_identical(
      isTRUE(validated),
      expected,
      info = deparse(channels)
    )
    if (isFALSE(is.null(channels))) {
      created <- tryCatch(
        {
          create_env(
            "polyglot",
            env_name = env_name,
            channels = channels,
            verbose = "silent"
          )
          TRUE
        },
        condathis_create_env_exists = function(e) FALSE
      )
      testthat::expect_identical(created, expected, info = deparse(channels))
    }
  }
})
