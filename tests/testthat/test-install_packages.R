rlang_tail <- c("rlang_error", "error", "condition")

catch_error <- function(expr) {
  return(rlang::catch_cnd(expr, classes = "error"))
}

# A stub backend (helper-stub-backend.R) that is the only backend condathis
# sees in this test, so no test here reaches micromamba.
local_install_stub <- function(
  name,
  envs = character(0L),
  ...,
  envir = parent.frame()
) {
  stub <- local_stub_backend(name, ..., envs = envs, envir = envir)
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() name,
    .env = envir
  )
  return(stub)
}

# Fails the test when argument validation lets a call reach a backend.
local_no_backend <- function(envir = parent.frame()) {
  testthat::local_mocked_bindings(
    resolve_backend = function(...) {
      stop("resolve_backend() must not be called")
    },
    .env = envir
  )
}

testthat::test_that("install_packages requires package specs", {
  local_no_backend()
  missing_class <- c(
    "condathis_install_packages_missing_packages",
    "condathis_invalid_packages",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  testthat::expect_identical(
    class(catch_error(install_packages(env_name = "some-env"))),
    missing_class
  )
  testthat::expect_identical(
    class(catch_error(install_packages(character(0L), env_name = "some-env"))),
    missing_class
  )
})

testthat::test_that("install_packages(packages = NULL) installs nothing, as in 0.1.4", {
  # Regression test: an explicit `packages = NULL` or `character(0)` aborted
  # with condathis_install_packages_missing_packages. 0.1.4 ran an empty
  # install with status 0.
  id <- "deprecated_packages_arg_install_packages"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  stub <- local_install_stub("stub-install-empty", envs = "empty-env")
  testthat::expect_warning(
    res <- install_packages(
      packages = NULL,
      env_name = "empty-env",
      verbose = "silent"
    ),
    class = "condathis_deprecated_packages_arg"
  )
  testthat::expect_s3_class(res, "condathis_result")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_identical(res$env_name, "empty-env")
  res <- install_packages(
    packages = character(0L),
    env_name = "empty-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  res <- do.call(
    install_packages,
    list(packages = NULL, env_name = "empty-env", verbose = "silent")
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
  testthat::expect_message(
    install_packages(packages = NULL, env_name = "empty-env"),
    regexp = "nothing to install"
  )
  # A missing environment other than the default one still aborts.
  testthat::expect_error(
    install_packages(packages = NULL, env_name = "missing-env"),
    class = "condathis_install_packages_env_not_found"
  )
  # No specs at all still abort.
  testthat::expect_error(
    install_packages(env_name = "empty-env"),
    class = "condathis_install_packages_missing_packages"
  )
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
})

testthat::test_that("install_packages rejects package specs that are not character strings", {
  # Regression test: install_packages(NA) and install_packages(1) printed
  # "Package NA/1 succesfully installed".
  local_no_backend()
  for (bad in list(NA, NA_character_, "", 1, c("a", NA))) {
    testthat::expect_identical(
      class(catch_error(install_packages(bad, env_name = "some-env"))),
      c(
        "condathis_install_packages_invalid_packages",
        "condathis_invalid_packages",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
  cnd <- catch_error(install_packages("python", chanels = "bioconda"))
  testthat::expect_s3_class(cnd, "condathis_install_packages_invalid_packages")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Did you mean `channels`?",
    fixed = TRUE
  )
})

testthat::test_that("install_packages validates env_name", {
  local_no_backend()
  for (bad in list(c("a", "b"), NA, 1, "../x")) {
    cnd <- catch_error(install_packages("python", env_name = bad))
    testthat::expect_s3_class(
      cnd,
      "condathis_install_packages_invalid_env_name"
    )
    testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
    testthat::expect_s3_class(cnd, "condathis_error")
  }
})

testthat::test_that("install_packages validates verbose, method and channel_priority before any backend call", {
  # Regression test: an invalid channel_priority went straight to the
  # backend.
  local_no_backend()
  cnd <- catch_error(install_packages("python", verbose = "bogus"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_invalid_verbose",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_s3_class(
    catch_error(install_packages("python", method = "no-such-backend")),
    "condathis_invalid_method_arg"
  )
  cnd <- catch_error(
    install_packages("python", env_name = "e", channel_priority = "bogus")
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_install_packages_invalid_channel_priority",
      "condathis_invalid_channel_priority",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
})

testthat::test_that("install_packages validates channels and additional_channels", {
  local_no_backend()
  for (bad in list(NULL, character(0L), NA_character_, "", 1L)) {
    cnd <- catch_error(install_packages(
      "python",
      env_name = "e",
      channels = bad
    ))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_install_packages_invalid_channels",
        "condathis_invalid_channels",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
  cnd <- catch_error(
    install_packages("python", env_name = "e", additional_channels = NA)
  )
  testthat::expect_s3_class(cnd, "condathis_invalid_additional_channels")
  testthat::expect_s3_class(cnd, "condathis_install_packages_invalid_channels")
})

testthat::test_that("install_packages passes one channel_priority and one verbose string to the backend", {
  # Regression test: the default channel_priority reached the backend as
  # the whole vector of choices (rule R4 for verbose).
  stub <- local_install_stub("stub-install-args", envs = "e")
  suppressMessages(install_packages("zlib", env_name = "e"))
  install_packages(
    "zlib",
    env_name = "e",
    channel_priority = "disabled",
    verbose = FALSE
  )
  calls <- stub_calls(stub, "backend_install")
  testthat::expect_length(calls, 2L)
  testthat::expect_identical(
    lapply(calls, function(x) x$args$channel_priority),
    list("strict", "disabled")
  )
  testthat::expect_identical(
    lapply(calls, function(x) x$args$verbose),
    list("output", "silent")
  )
  testthat::expect_identical(calls[[1L]]$args$packages, "zlib")
  # The existence probes get "silent", whatever the user passed.
  probes <- stub_calls(stub, "backend_env_exists")
  testthat::expect_true(all(vapply(
    probes,
    function(x) identical(x$args$verbose, "silent"),
    logical(1L)
  )))
})

testthat::test_that("install_packages does not create a missing custom environment", {
  # Decision D3: only "condathis-env" is created. A typo in env_name must
  # not create an environment.
  stub <- local_install_stub("stub-install-missing")
  cnd <- catch_error(
    install_packages("zlib", env_name = "never-created", verbose = "silent")
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_install_packages_env_not_found",
      "condathis_env_not_found",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_match(conditionMessage(cnd), "create_env()", fixed = TRUE)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
  testthat::expect_false(
    fs::dir_exists(fs::path(stub$root, "envs", "never-created"))
  )
})

testthat::test_that("install_packages aborts for a missing micromamba environment without a process", {
  # About a second or more on Windows: not on CRAN.
  testthat::skip_on_cran()
  # Decision D3 on a fresh root: nothing is created, and micromamba is
  # neither run nor installed.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("native_cmd() must not be called"),
      install_micromamba = function(...) {
        stop("install_micromamba() must not be called")
      }
    )
    testthat::expect_error(
      install_packages(
        "zlib",
        env_name = "never-created",
        method = "micromamba",
        verbose = "silent"
      ),
      class = "condathis_install_packages_env_not_found"
    )
    testthat::expect_false(
      fs::dir_exists(fs::path(get_condathis_path(), "envs", "never-created"))
    )
  })
})

testthat::test_that("install_packages creates the default environment when it is missing", {
  stub <- local_install_stub("stub-install-default")
  res <- install_packages("zlib", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$env_name, "condathis-env")
  creates <- stub_calls(stub, "backend_create_env")
  testthat::expect_length(creates, 1L)
  testthat::expect_identical(creates[[1L]]$args$env_name, "condathis-env")
  # Created empty: the specs go to backend_install().
  testthat::expect_null(creates[[1L]]$args$packages)
  testthat::expect_length(stub_calls(stub, "backend_install"), 1L)
})

testthat::test_that("install_packages aborts on a failed existence check and creates nothing", {
  # Rule R5: a probe that fails is not read as "absent". resolve_backend()
  # probes every backend for a mutating call, and aborts first.
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  stub <- local_install_stub(
    "stub-install-probe",
    backend_env_exists = stub_boom
  )
  for (env_name in c("probe-env", "condathis-env")) {
    cnd <- catch_error(
      install_packages(
        "zlib",
        env_name = env_name,
        method = "stub-install-probe",
        verbose = "silent"
      )
    )
    testthat::expect_s3_class(cnd, "condathis_backend_probe_failed")
    testthat::expect_s3_class(cnd, "condathis_backend_error")
    testthat::expect_true(rlang::cnd_inherits(cnd, "stub_boom"))
  }
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
})

testthat::test_that("install_packages passes a failed probe that resolve_backend() did not catch on to the backend", {
  # The branch of install_packages() itself: resolve_backend() is mocked to
  # return the stub, so find_owning_backends() does not probe first. A failed
  # probe (`NA`) neither creates the environment nor reports it missing: the
  # backend gets the call and reports the real error.
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  stub <- local_stub_backend(
    "stub-install-pass",
    backend_env_exists = stub_boom,
    backend_install = function(...) {
      rlang::abort("install failed", class = "stub_install_failed")
    }
  )
  testthat::local_mocked_bindings(
    resolve_backend = function(...) {
      return(list(backend = stub$backend, name = "stub-install-pass"))
    }
  )
  for (env_name in c("probe-env", "condathis-env")) {
    cnd <- catch_error(
      install_packages("zlib", env_name = env_name, verbose = "silent")
    )
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_install_packages_failed",
        "condathis_backend_error",
        "condathis_error",
        rlang_tail
      ),
      info = env_name
    )
    testthat::expect_s3_class(cnd$parent, "stub_install_failed")
  }
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_install"), 2L)
})

testthat::test_that("install_packages re-raises a backend error with its own classes", {
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  local_install_stub(
    "stub-install-boom",
    envs = "boom-env",
    backend_install = stub_boom
  )
  cnd <- catch_error(
    install_packages("zlib", env_name = "boom-env", verbose = "silent")
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_install_packages_failed",
      "condathis_backend_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Backend stub-install-boom failed to install packages in environment 'boom-env'.",
    fixed = TRUE
  )
})

testthat::test_that("install_packages reads the backend result by exact name", {
  local_install_stub(
    "stub-install-result",
    envs = c("true-env", "bad-env", "cmd-env"),
    backend_install = function(backend, env_name = "condathis-env", ...) {
      return(switch(
        env_name,
        `true-env` = TRUE,
        `bad-env` = list(status = 1L),
        list(status = 0L, cmd = "stub install -n cmd-env zlib")
      ))
    }
  )
  res <- install_packages("zlib", env_name = "true-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, NA_character_)
  # cmd-field: no invented command line.
  testthat::expect_identical(res$cmd, NA_character_)
  res <- install_packages("zlib", env_name = "cmd-env", verbose = "silent")
  testthat::expect_identical(res$cmd, "stub install -n cmd-env zlib")
  testthat::expect_error(
    install_packages("zlib", env_name = "bad-env", verbose = "silent"),
    class = "condathis_install_packages_failed"
  )
})

testthat::test_that("install_packages catches an old positional env_name", {
  stub <- local_install_stub("stub-install-positional", envs = "my-env")
  cnd <- catch_error(install_packages("python", "my-env"))
  testthat::expect_s3_class(
    cnd,
    "condathis_install_packages_positional_env_name"
  )
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_match(
    conditionMessage(cnd),
    "env_name = \"my-env\"",
    fixed = TRUE
  )
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
})

testthat::test_that("install_packages checks for a positional env_name only with two or more unnamed specs", {
  # Regression test: `packages = c("x", "<env>")` aborted when "<env>" named
  # an existing environment. 0.1.4 read it as two specs.
  id <- "deprecated_packages_arg_install_packages"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  stub <- local_install_stub(
    "stub-install-positional-alias",
    envs = c("condathis-env", "my-env")
  )
  testthat::expect_warning(
    res <- install_packages(
      packages = c("python", "my-env"),
      verbose = "silent"
    ),
    class = "condathis_deprecated_packages_arg"
  )
  testthat::expect_identical(res$status, 0L)
  res <- install_packages(c("python", "my-env"), verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  res <- do.call(
    install_packages,
    list(packages = c("python", "my-env"), verbose = "silent")
  )
  testthat::expect_identical(res$status, 0L)
  installs <- stub_calls(stub, "backend_install")
  testthat::expect_length(installs, 3L)
  for (call in installs) {
    testthat::expect_identical(call$args$packages, c("python", "my-env"))
    testthat::expect_identical(call$args$env_name, "condathis-env")
  }
  # Two unnamed arguments still abort.
  testthat::expect_error(
    install_packages("python", "my-env"),
    class = "condathis_install_packages_positional_env_name"
  )
  testthat::expect_length(stub_calls(stub, "backend_install"), 3L)
})

testthat::test_that("install_packages accepts packages = as a deprecated alias", {
  id <- "deprecated_packages_arg_install_packages"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  stub <- local_install_stub("stub-install-alias", envs = "alias-env")
  testthat::expect_warning(
    install_packages(
      packages = "zlib",
      env_name = "alias-env",
      verbose = FALSE
    ),
    class = "condathis_deprecated_packages_arg"
  )
  testthat::expect_identical(
    stub_calls(stub, "backend_install")[[1L]]$args$packages,
    "zlib"
  )
})

testthat::test_that("install_packages reports success with the v bullet", {
  local_install_stub("stub-install-message", envs = "msg-env")
  testthat::expect_message(
    install_packages("zlib", env_name = "msg-env", verbose = "output"),
    regexp = "successfully installed"
  )
  testthat::expect_no_message(
    install_packages("zlib", env_name = "msg-env", verbose = "silent")
  )
})

testthat::test_that("the previous-channel warning has the old and new class", {
  env_dir <- withr::local_tempdir()
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  writeLines(
    "+https://conda.anaconda.org/bioconda/noarch::x-1-0",
    fs::path(env_dir, "conda-meta", "history")
  )
  cnd <- rlang::catch_cnd(
    warn_on_missing_previous_channels(
      env_dir = env_dir,
      env_name = "e",
      packages = "zlib",
      channels = "conda-forge"
    ),
    classes = "warning"
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_install_packages_missing_previous_channels",
      "condathis_install_missing_previous_channels",
      "condathis_warning",
      "rlang_warning",
      "warning",
      "condition"
    )
  )
  # A channel named in a spec counts as included.
  testthat::expect_no_warning(
    warn_on_missing_previous_channels(
      env_dir = env_dir,
      env_name = "e",
      packages = "bioconda::samtools",
      channels = "conda-forge"
    )
  )
})

testthat::test_that("install_packages() warns about left-out channels with every backend", {
  # Regression test: the warning was given only for the micromamba backend.
  # A backend that writes `conda-meta/history` gets it too; one that writes
  # none gets no warning.
  stub <- local_install_stub("stub-install-history", envs = "hist-env")
  env_dir <- fs::path(stub$root, "envs", "hist-env")
  testthat::expect_no_warning(
    install_packages("zlib", env_name = "hist-env", verbose = "silent")
  )
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  writeLines(
    "+https://conda.anaconda.org/bioconda/noarch::x-1-0",
    fs::path(env_dir, "conda-meta", "history")
  )
  testthat::expect_warning(
    install_packages("zlib", env_name = "hist-env", verbose = "silent"),
    class = "condathis_install_packages_missing_previous_channels"
  )
  testthat::expect_no_warning(
    install_packages(
      "zlib",
      env_name = "hist-env",
      channels = c("conda-forge", "bioconda"),
      verbose = "silent"
    )
  )
  testthat::expect_length(stub_calls(stub, "backend_install"), 3L)
})

testthat::test_that("install_packages() passes the platform of the environment to every backend", {
  stub <- local_install_stub("stub-install-platform", envs = "plat-env")
  env_dir <- fs::path(stub$root, "envs", "plat-env")
  last_platform <- function() {
    calls <- stub_calls(stub, "backend_install")
    return(calls[[length(calls)]]$args$platform)
  }
  install <- function() {
    return(install_packages("zlib", env_name = "plat-env", verbose = "silent"))
  }
  # Nothing recorded: the native platform of the backend.
  testthat::local_mocked_bindings(has_platform_fallback = function() FALSE)
  install()
  testthat::expect_true(
    "platform" %in% names(stub_calls(stub, "backend_install")[[1L]]$args)
  )
  testthat::expect_null(last_platform())

  # The `.mambarc` of a micromamba environment of an older condathis.
  cat("platform: win-64", file = fs::path(env_dir, ".mambarc"))
  install()
  testthat::expect_identical(last_platform(), "win-64")

  # The marker that create_env() writes comes first.
  write_backend_marker(env_dir, "stub-install-platform", platform = "osx-64")
  install()
  testthat::expect_identical(last_platform(), "osx-64")

  # Without either, where a fallback exists: the package records.
  fs::file_delete(fs::path(env_dir, ".mambarc"))
  write_backend_marker(env_dir, "stub-install-platform")
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  fs::file_create(fs::path(env_dir, "conda-meta", "history"))
  jsonlite::write_json(
    list(name = "zlib", version = "1.3.1", build = "0", subdir = "osx-64"),
    fs::path(env_dir, "conda-meta", "zlib-1.3.1-0.json"),
    auto_unbox = TRUE
  )
  install()
  testthat::expect_null(last_platform())
  testthat::local_mocked_bindings(has_platform_fallback = function() TRUE)
  install()
  testthat::expect_identical(last_platform(), "osx-64")
})

testthat::test_that("install_packages() gives an empty environment of any backend the emulation fallback", {
  # The OS is given through mocks. The stub tells whether the request
  # solves: only for osx-64.
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    is_rosetta_running = function() TRUE
  )
  stub <- local_install_stub(
    "stub-install-fallback",
    envs = "empty-env",
    backend_can_solve = function(backend, ..., platform) {
      return(identical(platform, "osx-64"))
    }
  )
  # Every message is caught, so the success message of verbose = "output"
  # does not reach the test output.
  msgs <- character(0L)
  withCallingHandlers(
    install_packages(
      "r-base",
      env_name = "empty-env",
      channels = "conda-forge",
      channel_priority = "flexible",
      additional_channels = "bioconda",
      verbose = "output"
    ),
    message = function(m) {
      msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  testthat::expect_match(
    msgs,
    "Using Rosetta 2 emulation.",
    fixed = TRUE,
    all = FALSE
  )
  testthat::expect_match(
    msgs,
    "Package r-base successfully installed in environment empty-env.",
    fixed = TRUE,
    all = FALSE
  )
  testthat::expect_identical(
    stub_calls(stub, "backend_install")[[1L]]$args$platform,
    "osx-64"
  )
  solve <- stub_calls(stub, "backend_can_solve")[[1L]]$args
  testthat::expect_identical(solve$packages, "r-base")
  testthat::expect_identical(solve$channels, "conda-forge")
  testthat::expect_identical(solve$channel_priority, "flexible")
  testthat::expect_identical(solve$additional_channels, "bioconda")
  testthat::expect_identical(solve$platform, "osx-arm64")
})

testthat::test_that("install_packages() warns when the backend did not run link scripts", {
  stub <- local_install_stub(
    "stub-install-scripts",
    envs = "scripts-env",
    backend_install = function(backend, ...) {
      return(list(
        status = 0L,
        link_scripts_skipped = data.frame(
          package = c("plink", "plink"),
          script = c("post-link", "pre-unlink"),
          stringsAsFactors = FALSE
        )
      ))
    }
  )
  cnd <- rlang::catch_cnd(
    install_packages("plink", env_name = "scripts-env", verbose = "silent"),
    classes = "warning"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_install_packages_link_scripts_skipped",
      "condathis_link_scripts_skipped",
      "condathis_warning"
    )
  )
  testthat::expect_identical(cnd$packages, "plink")
  testthat::expect_identical(cnd$env_name, "scripts-env")
  testthat::expect_identical(nrow(cnd$scripts), 2L)
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "post-link scripts of plink.", fixed = TRUE)
  testthat::expect_match(
    message,
    "pre-unlink scripts of plink before it removed them.",
    fixed = TRUE
  )

  # The result has the same fields as for any backend.
  res <- suppressWarnings(
    install_packages("plink", env_name = "scripts-env", verbose = "silent")
  )
  testthat::expect_identical(
    names(unclass(res)),
    c("status", "stdout", "stderr", "timeout", "pid", "cmd", "env_name")
  )
})

testthat::test_that("every install_packages() error has the class condathis_error", {
  local_no_backend()
  testthat::expect_error(install_packages(), class = "condathis_error")
  testthat::expect_error(install_packages(1), class = "condathis_error")
})

testthat::test_that("install_packages warns when previous channels are dropped", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # Real remote channels on every platform: `polyglot` is a dependency-free
  # `noarch` package published only on the prefix.dev `universe` channel,
  # so the environment's history holds exactly `conda-forge` (from
  # `create_env()`) and `universe`. The offline variant with two local
  # channels is in test-polyglot.R.
  universe <- "https://repo.prefix.dev/universe"
  condathis::with_sandbox_dir({
    px_res <- create_env(
      "zlib",
      env_name = "condathis-channel-warn-env",
      channels = "conda-forge",
      verbose = "silent"
    )
    testthat::expect_equal(px_res$status, 0L)

    testthat::expect_warning(
      object = {
        install_res <- install_packages(
          "polyglot",
          env_name = "condathis-channel-warn-env",
          channels = universe,
          verbose = "silent"
        )
      },
      class = "condathis_install_packages_missing_previous_channels"
    )
    testthat::expect_s3_class(install_res, "condathis_result")
    testthat::expect_equal(install_res$status, 0L)
    testthat::expect_true(
      "polyglot" %in%
        list_packages("condathis-channel-warn-env", verbose = "silent")$name
    )

    # No warning when the previously used channels are included again. The
    # history records `universe` by its URL, which matches the URL passed.
    testthat::expect_no_warning(
      object = {
        install_packages(
          "polyglot",
          env_name = "condathis-channel-warn-env",
          channels = c("conda-forge", universe),
          verbose = "silent"
        )
      },
      class = "condathis_install_missing_previous_channels"
    )

    remove_env(env_name = "condathis-channel-warn-env", verbose = "silent")
  })
})

testthat::test_that("defaults and channel URLs with credentials count as included channels", {
  # The history names the channels by package URL: `defaults` packages
  # under repo.anaconda.com/pkgs/main, a token channel with the token
  # hidden. The warning compares them as create_env() does.
  env_dir <- withr::local_tempdir()
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  writeLines(
    c(
      "+https://repo.anaconda.com/pkgs/main/linux-64::zlib-1.3.2-h0_0",
      "+http://127.0.0.1:18765/t/*****/private/noarch::polyglot-0.1.0-h0_0"
    ),
    con = fs::path(env_dir, "conda-meta", "history")
  )
  warn <- function(channels) {
    return(warn_on_missing_previous_channels(
      env_dir = env_dir,
      env_name = "hist-env",
      packages = "zlib",
      channels = channels
    ))
  }
  testthat::expect_no_warning(
    warn(c("defaults", "http://127.0.0.1:18765/t/tk-0123456789/private")),
    class = "condathis_install_missing_previous_channels"
  )
  testthat::expect_warning(
    warn(c("conda-forge", "http://127.0.0.1:18765/t/tk-0123456789/private")),
    class = "condathis_install_missing_previous_channels"
  )
  testthat::expect_warning(
    warn("defaults"),
    class = "condathis_install_missing_previous_channels"
  )
})

testthat::test_that("channels with a /t/<word> part count as included channels", {
  # Regression test: the history channels have every `/t/<word>` hidden
  # (see `hide_secrets()`), in local paths and inside URL paths too, and the
  # warning compared them with the plain channels of the call. So a local
  # channel under `<dir>/t/chan1/` was always left out, and so was a URL
  # with such a part deeper in its path (`/org/t/<token>/`).
  channel_dir <- fs::path(
    withr::local_tempdir(),
    "t",
    "chan1",
    "polyglot-channel"
  )
  channel_url <- local_file_url(channel_dir)
  token_url <- "https://repo.example.org/org/t/tk-0123456789/private"
  env_dir <- withr::local_tempdir()
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  writeLines(
    c(
      paste0("+", channel_url, "/noarch::polyglot-0.1.0-h4616a5c_0"),
      paste0("+", token_url, "/noarch::zlib-1.3.2-h0_0")
    ),
    con = fs::path(env_dir, "conda-meta", "history")
  )
  warn <- function(channels) {
    return(warn_on_missing_previous_channels(
      env_dir = env_dir,
      env_name = "hist-env",
      packages = "polyglot",
      channels = channels
    ))
  }
  # The local channel as a URL and as a path, with `\` on Windows.
  local_forms <- c(channel_url, as.character(channel_dir))
  if (isTRUE(is_windows())) {
    local_forms <- c(local_forms, gsub("/", "\\\\", channel_dir))
  }
  for (local_channel in local_forms) {
    testthat::expect_no_warning(
      warn(c(local_channel, token_url)),
      class = "condathis_install_missing_previous_channels"
    )
  }
  # Another directory or another host is still another channel.
  other_dir <- fs::path(fs::path_dir(channel_dir), "other-channel")
  testthat::expect_warning(
    warn(c(local_file_url(other_dir), token_url)),
    class = "condathis_install_missing_previous_channels"
  )
  testthat::expect_warning(
    warn(c(
      channel_url,
      sub("example.org", "example.com", token_url, fixed = TRUE)
    )),
    class = "condathis_install_missing_previous_channels"
  )
})

testthat::test_that("channel URLs and spec channels count as included channels", {
  # Regression test: a channel URL or a channel prefix inside `packages`
  # was not recognised, so install_packages() warned about a "missing"
  # previous channel that the call did include.
  testthat::expect_identical(
    normalize_channel_name(c(
      "conda-forge",
      "https://conda.anaconda.org/conda-forge",
      "https://conda.anaconda.org/bioconda/"
    )),
    c("conda-forge", "conda-forge", "bioconda")
  )
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    create_env("conda-forge::zlib", env_name = "chan-env", verbose = "silent")
    testthat::expect_no_warning(
      install_packages(
        "conda-forge::zlib",
        env_name = "chan-env",
        channels = "https://conda.anaconda.org/conda-forge",
        verbose = "silent"
      ),
      class = "condathis_install_missing_previous_channels"
    )
  })
})

# The platform that the micromamba in use solves for, from
# `micromamba info`. Installs micromamba when no binary is found.
real_micromamba_platform <- function() {
  info_res <- native_cmd(
    conda_cmd = "info",
    conda_args = "--json",
    verbose = "silent"
  )
  return(jsonlite::fromJSON(info_res$stdout)[["platform"]])
}

testthat::test_that("install_packages() installs for the platform the environment was created for", {
  # Regression test: micromamba records `create --platform` in the
  # `.mambarc` of the environment, which `--rc-file` keeps it from reading,
  # so the install solved for the platform of the micromamba binary and one
  # environment held packages of two platforms. The win-64 fallback on
  # Windows on ARM64 creates such environments. Windows packages hold no
  # symbolic links and these run no link scripts, so every OS can create
  # them.
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    other_platform <- "win-64"
    if (identical(real_micromamba_platform(), "win-64")) {
      other_platform <- "win-arm64"
    }
    create_env(
      "zlib",
      env_name = "other-platform-env",
      platform = other_platform,
      verbose = "silent"
    )
    install_res <- install_packages(
      "zstd",
      env_name = "other-platform-env",
      verbose = "silent"
    )
    testthat::expect_equal(install_res$status, 0L)
    pkgs <- list_packages("other-platform-env", verbose = "silent")
    testthat::expect_true("zstd" %in% pkgs$name)
    testthat::expect_identical(env_package_platforms(pkgs), other_platform)
    remove_env(env_name = "other-platform-env", verbose = "silent")
  })
})

# The OS, the solves and micromamba are mocked: `native_cmd()` records its
# create and install calls, a create makes the environment directory, as
# micromamba does, and `env list` lists the environment directories.
local_fake_emulation <- function(sys_arch, emulated, envir = parent.frame()) {
  log <- new.env(parent = emptyenv())
  log$calls <- list()
  log$solves <- character(0L)
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "micromamba",
    get_sys_arch = function() sys_arch,
    is_rosetta_running = function() TRUE,
    micromamba_native_platform = function() "win-arm64",
    packages_solve_native = function(..., platform) {
      log$solves <- c(log$solves, platform)
      return(identical(platform, emulated))
    },
    native_cmd = function(
      conda_cmd,
      conda_args = NULL,
      ...,
      verbose = "silent",
      error = "cancel",
      cleanup_tree = FALSE
    ) {
      stdout <- ""
      if (identical(conda_cmd, "env")) {
        # `micromamba env list --json`, for the existence check of an
        # environment that exists.
        stdout <- as.character(jsonlite::toJSON(list(
          envs = as.character(fs::dir_ls(
            fs::path(get_condathis_path(), "envs"),
            type = "directory"
          ))
        )))
      } else {
        log$calls[[length(log$calls) + 1L]] <- list(
          conda_cmd = conda_cmd,
          conda_args = conda_args,
          specs = c(...),
          cleanup_tree = cleanup_tree
        )
      }
      if (identical(conda_cmd, "create")) {
        i <- which(conda_args == "-n")
        meta_dir <- fs::path(
          get_condathis_path(),
          "envs",
          conda_args[[i + 1L]],
          "conda-meta"
        )
        fs::dir_create(meta_dir)
        fs::file_create(fs::path(meta_dir, "history"))
      }
      return(list(
        status = 0L,
        stdout = stdout,
        stderr = "",
        cmd = paste("micromamba", conda_cmd)
      ))
    },
    .env = envir
  )
  return(log)
}

# The `--platform` value of a recorded `native_cmd()` call, or `NULL`.
call_platform <- function(call) {
  i <- which(call$conda_args == "--platform")
  if (identical(length(i), 0L)) {
    return(NULL)
  }
  return(call$conda_args[[i + 1L]])
}

testthat::test_that("install_packages() gives the new default environment the emulation fallback of create_env()", {
  # About a second or more on Windows: not on CRAN.
  testthat::skip_on_cran()
  # Regression test: install_packages() creates a missing "condathis-env"
  # empty, so no platform was recorded for it, and the first install solved
  # for the platform of the micromamba binary: `r-base` got no fallback to
  # osx-64 on Apple Silicon, or to win-64 with the win-arm64 micromamba.
  # After the first install, the package records give the platform.
  check_default_env <- function(sys_arch, native, emulated, message) {
    condathis::with_sandbox_dir({
      log <- local_fake_emulation(sys_arch = sys_arch, emulated = emulated)
      msgs <- character(0L)
      withCallingHandlers(
        res <- install_packages("r-base", verbose = "output"),
        message = function(m) {
          msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
          invokeRestart("muffleMessage")
        }
      )
      testthat::expect_identical(res$env_name, "condathis-env", info = sys_arch)
      cmds <- vapply(log$calls, function(x) x$conda_cmd, character(1L))
      testthat::expect_identical(cmds, c("create", "install"), info = sys_arch)
      # micromamba's own processes (a pip step, link scripts) are killed
      # with it: on Windows an interrupt otherwise left them running.
      testthat::expect_identical(
        vapply(log$calls, function(x) isTRUE(x$cleanup_tree), logical(1L)),
        c(TRUE, TRUE),
        info = sys_arch
      )
      # Created empty, with no platform: there was nothing to solve.
      testthat::expect_null(log$calls[[1L]]$specs, info = sys_arch)
      testthat::expect_null(call_platform(log$calls[[1L]]), info = sys_arch)
      testthat::expect_identical(
        log$calls[[2L]]$specs,
        "r-base",
        info = sys_arch
      )
      testthat::expect_identical(
        call_platform(log$calls[[2L]]),
        emulated,
        info = sys_arch
      )
      testthat::expect_identical(
        log$solves,
        c(native, emulated),
        info = sys_arch
      )
      testthat::expect_match(
        paste(msgs, collapse = "\n"),
        message,
        fixed = TRUE,
        info = sys_arch
      )

      # What micromamba writes for the installed package.
      jsonlite::write_json(
        list(name = "r-base", version = "4.5.1", subdir = emulated),
        fs::path(
          get_condathis_path(),
          "envs",
          "condathis-env",
          "conda-meta",
          "r-base-4.5.1-0.json"
        ),
        auto_unbox = TRUE
      )
      install_packages("r-ggplot2", verbose = "silent")
      testthat::expect_length(log$calls, 3L)
      testthat::expect_identical(
        call_platform(log$calls[[3L]]),
        emulated,
        info = sys_arch
      )
      # Nothing was solved again.
      testthat::expect_length(log$solves, 2L)
    })
  }
  check_default_env(
    sys_arch = "Darwin-arm64",
    native = "osx-arm64",
    emulated = "osx-64",
    message = "Using Rosetta 2 emulation."
  )
  check_default_env(
    sys_arch = "Windows-aarch64",
    native = "win-arm64",
    emulated = "win-64",
    message = "Using x64 emulation for \"win-64\" packages."
  )
})

testthat::test_that("install_packages() keeps the platform that the first install into an empty environment got", {
  # With a real micromamba: the first install into an empty environment
  # gets the platform of the emulation fallback, mocked here so every OS
  # can run the test, and records nothing for the environment. The package
  # records then give the platform of the next install. Windows packages
  # hold no symbolic links and these run no link scripts, so every OS can
  # install them.
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    other_platform <- "win-64"
    if (identical(real_micromamba_platform(), "win-64")) {
      other_platform <- "win-arm64"
    }
    fallback_calls <- 0L
    testthat::local_mocked_bindings(
      # As on Apple Silicon and Windows, the systems with a fallback.
      has_platform_fallback = function() TRUE,
      define_platform = function(backend, packages, ...) {
        fallback_calls <<- fallback_calls + 1L
        return(other_platform)
      }
    )
    install_res <- install_packages("zlib", verbose = "silent")
    testthat::expect_equal(install_res$status, 0L)
    testthat::expect_identical(fallback_calls, 1L)
    env_dir <- get_env_dir("condathis-env")
    testthat::expect_false(fs::file_exists(fs::path(env_dir, ".mambarc")))

    install_res <- install_packages("zstd", verbose = "silent")
    testthat::expect_equal(install_res$status, 0L)
    testthat::expect_identical(fallback_calls, 1L)
    # `shQuote()` quotes with `'` on Unix and with `"` on Windows.
    testthat::expect_match(
      install_res$cmd,
      paste0("--platform[\"'] [\"']", other_platform, "[\"']")
    )
    pkgs <- list_packages("condathis-env", verbose = "silent")
    testthat::expect_true(all(c("zlib", "zstd") %in% pkgs$name))
    testthat::expect_identical(env_package_platforms(pkgs), other_platform)
  })
})

testthat::test_that("install_packages() says that bioconda is no longer a default channel", {
  # The text micromamba 2 gives for a requested spec that is on none of the
  # channels.
  not_found <- function(...) {
    rlang::abort(
      "`micromamba` failed with status code 1.",
      class = c("condathis_micromamba_status_error", "condathis_error"),
      status = 1L,
      stderr = paste0(
        "    \u2514\u2500 samtools =* * does not exist ",
        "(perhaps a typo or a missing channel).\n"
      )
    )
  }
  stub <- local_install_stub(
    "stub-install-default-channels",
    envs = "bioc-env",
    backend_install = not_found
  )
  flat <- function(cnd) {
    return(gsub("\\s+", " ", cli::ansi_strip(conditionMessage(cnd))))
  }
  cnd <- catch_error(
    install_packages("samtools", env_name = "bioc-env", verbose = "silent")
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_install_packages_failed",
      "condathis_backend_error",
      "condathis_micromamba_status_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_identical(cnd$status, 1L)
  message <- flat(cnd)
  testthat::expect_match(
    message,
    "Since condathis 0.2.0, the default `channels` is only \"conda-forge\"",
    fixed = TRUE
  )
  testthat::expect_match(message, "\"bioconda::samtools\"", fixed = TRUE)

  # Not when `channels` is given or has bioconda.
  for (cnd in list(
    catch_error(install_packages(
      "samtools",
      env_name = "bioc-env",
      channels = "conda-forge",
      verbose = "silent"
    )),
    catch_error(install_packages(
      "samtools",
      env_name = "bioc-env",
      additional_channels = "bioconda",
      verbose = "silent"
    ))
  )) {
    testthat::expect_s3_class(cnd, "condathis_install_packages_failed")
    testthat::expect_no_match(flat(cnd), "Since condathis 0.2.0", fixed = TRUE)
  }
})

testthat::test_that("install_packages() passes virtual package specs to the backend", {
  stub <- local_install_stub("stub-install-virtual", envs = "cuda-env")
  install_packages(
    "__cuda=12",
    "pytorch-gpu",
    env_name = "cuda-env",
    verbose = "silent"
  )
  calls <- stub_calls(stub, "backend_install")
  testthat::expect_length(calls, 1L)
  testthat::expect_identical(
    calls[[1L]]$args$packages,
    c("__cuda=12", "pytorch-gpu")
  )
})
