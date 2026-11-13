rlang_tail <- c("rlang_error", "error", "condition")

catch_error <- function(expr) {
  return(rlang::catch_cnd(expr, classes = "error"))
}

# A package listing with the six columns of the backend contract.
pkgs_df <- function(
  name,
  version = "1.0",
  channel = "conda-forge",
  platform = "noarch",
  build_string = "h0_0"
) {
  n <- length(name)
  return(data.frame(
    name = as.character(name),
    version = rep_len(as.character(version), n),
    build_number = rep_len(0L, n),
    build_string = rep_len(as.character(build_string), n),
    channel = rep_len(as.character(channel), n),
    platform = rep_len(as.character(platform), n),
    stringsAsFactors = FALSE
  ))
}

# A stub backend (helper-stub-backend.R) that is the only backend condathis
# sees in this test, so no test here reaches micromamba. `packages` is what
# its `backend_list_packages()` returns.
local_env_stub <- function(
  name,
  envs = character(0L),
  packages = pkgs_df(character(0L)),
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

# Fails the test when argument validation lets a call reach a backend.
local_no_backend <- function(envir = parent.frame()) {
  testthat::local_mocked_bindings(
    resolve_backend = function(...) {
      stop("resolve_backend() must not be called")
    },
    .env = envir
  )
}

testthat::test_that("create_env() validates method before any backend call", {
  local_no_backend()
  for (method in list(NA, "na", "NonExisting", c("auto", "auto"))) {
    cnd <- catch_error(create_env(method = method))
    testthat::expect_s3_class(cnd, "condathis_invalid_method_arg")
    testthat::expect_false(
      grepl("must not be called", conditionMessage(cnd), fixed = TRUE),
      info = deparse(method)
    )
  }
})

testthat::test_that("create_env() validates verbose before any backend call", {
  # Regression test: verbose was parsed after resolve_backend(), so an
  # invalid value could install micromamba and start a process first.
  local_no_backend()
  cnd <- catch_error(create_env(verbose = "bogus"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_invalid_verbose",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_identical(
    conditionCall(cnd),
    quote(create_env(verbose = "bogus"))
  )
})

testthat::test_that("create_env() rejects package specs that are not character strings", {
  # Regression test: NA reached micromamba as the package "NA".
  local_no_backend()
  for (bad in list(NA, NA_character_, "", 1L, NULL, list("a"))) {
    cnd <- catch_error(create_env("python", bad))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_invalid_packages",
        "condathis_invalid_packages",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
  testthat::expect_s3_class(
    catch_error(create_env(NA)),
    "condathis_invalid_packages"
  )
})

testthat::test_that("create_env() names the closest argument for a misspelled option", {
  local_no_backend()
  cnd <- catch_error(create_env("python", chanels = "bioconda"))
  testthat::expect_s3_class(cnd, "condathis_create_env_invalid_packages")
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "Did you mean `channels`?", fixed = TRUE)
})

testthat::test_that("create_env() points an environment file in ... to env_file", {
  # The old positional `create_env(NULL, "environment.yml")` and
  # `create_env("environment.yml")` both end here.
  local_no_backend()
  for (call in list(
    quote(create_env("environment.yml")),
    quote(create_env(NULL, "environment.yml"))
  )) {
    cnd <- catch_error(eval(call))
    testthat::expect_s3_class(cnd, "condathis_create_env_invalid_packages")
  }
  cnd <- catch_error(create_env("environment.yml"))
  testthat::expect_match(
    conditionMessage(cnd),
    "env_file = \"environment.yml\"",
    fixed = TRUE
  )
})

testthat::test_that("create_env() rejects a non-logical overwrite, with the old and new class", {
  local_no_backend()
  for (bad in list("yes", NA, c(TRUE, FALSE), 1L)) {
    cnd <- catch_error(create_env(overwrite = bad))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_invalid_overwrite",
        "condathis_create_invalid_overwrite_arg",
        "condathis_invalid_overwrite",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
})

testthat::test_that("create_env() rejects a platform that is not a single string, with the old and new class", {
  local_no_backend()
  for (platform in list(c("linux-64", "osx-64"), NA_character_, "", 64L)) {
    cnd <- catch_error(create_env(env_name = "e", platform = platform))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_invalid_platform",
        "condathis_create_invalid_platform_arg",
        "condathis_invalid_platform",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(platform)
    )
  }
})

testthat::test_that("create_env() rejects a malformed platform, before any backend call", {
  # Regression test: any string reached micromamba, which accepts it and
  # then looks for packages in a subdirectory of that name. A misspelled
  # platform failed with "does not exist (perhaps a typo or a missing
  # channel)", after micromamba was installed and the channels were read.
  local_no_backend()
  cases <- list(
    linux64 = "linux-64",
    `LINUX-64` = "linux-64",
    osx_arm64 = "osx-arm64",
    `win-64 ` = "win-64",
    `emscripten_wasm32` = "emscripten-wasm32",
    `linux-x86_64` = "linux-64",
    `x86_64-linux` = NULL,
    bogus = NULL
  )
  for (platform in names(cases)) {
    cnd <- catch_error(create_env(env_name = "e", platform = platform))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_invalid_platform",
        "condathis_create_invalid_platform_arg",
        "condathis_invalid_platform",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = platform
    )
    message <- cli::ansi_strip(conditionMessage(cnd))
    testthat::expect_match(message, platform, fixed = TRUE, info = platform)
    # The message says what a platform looks like.
    testthat::expect_match(
      message,
      "Known platforms are lower case, such as",
      fixed = TRUE,
      info = platform
    )
    suggestion <- cases[[platform]]
    if (is.null(suggestion)) {
      testthat::expect_no_match(message, "Did you mean", info = platform)
    } else {
      testthat::expect_match(
        message,
        paste0(
          "Did you mean ",
          paste0("\"", suggestion, "\"", collapse = " or "),
          "?"
        ),
        fixed = TRUE,
        info = platform
      )
    }
  }
})

testthat::test_that("create_env() passes known platforms beyond micromamba's list to the backend", {
  # Regression test: only the platforms of micromamba's own list were
  # accepted, so `"emscripten-wasm32"` (emscripten-forge) aborted, although
  # micromamba solves for it and rattler knows it.
  local_no_backend()
  for (platform in c(
    "emscripten-wasm32",
    "wasi-wasm32",
    "linux-loongarch64",
    "freebsd-64",
    "noarch"
  )) {
    cnd <- catch_error(create_env(env_name = "e", platform = platform))
    testthat::expect_match(
      conditionMessage(cnd),
      "resolve_backend() must not be called",
      fixed = TRUE,
      info = platform
    )
  }
})

testthat::test_that("create_env() rejects other spellings of a platform and names the conda one", {
  # Regression test: `"linux-arm64"` has the form of a platform, so it
  # reached micromamba, which accepts any subdir and failed late with
  # "does not exist". Edit distance alone suggests `"linux-armv6l"`.
  local_no_backend()
  cases <- c(
    `linux-arm64` = "linux-aarch64",
    `osx-aarch64` = "osx-arm64",
    `win-aarch64` = "win-arm64",
    `linux-amd64` = "linux-64",
    `osx-x86_64` = "osx-64",
    `windows-x64` = "win-64",
    `darwin-arm64` = "osx-arm64"
  )
  for (platform in names(cases)) {
    cnd <- catch_error(create_env(env_name = "e", platform = platform))
    testthat::expect_s3_class(
      cnd,
      "condathis_create_env_invalid_platform"
    )
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      paste0("Did you mean \"", cases[[platform]], "\"?"),
      fixed = TRUE,
      info = platform
    )
  }
})

testthat::test_that("validate_platform_arg() accepts NULL and every known platform", {
  # The KnownPlatform list of micromamba 2.10.0 (libmamba specs/platform.hpp)
  # is part of known_platforms.
  micromamba_platforms <- c(
    "noarch",
    "linux-32",
    "linux-64",
    "linux-armv6l",
    "linux-armv7l",
    "linux-aarch64",
    "linux-ppc64le",
    "linux-ppc64",
    "linux-s390x",
    "linux-riscv32",
    "linux-riscv64",
    "osx-64",
    "osx-arm64",
    "win-32",
    "win-64",
    "win-arm64",
    "zos-z"
  )
  testthat::expect_true(all(micromamba_platforms %in% known_platforms))
  testthat::expect_false(anyDuplicated(known_platforms) > 0L)
  class <- arg_error_class("create_env", "platform")
  testthat::expect_null(validate_platform_arg(NULL, class = class))
  for (platform in known_platforms) {
    testthat::expect_identical(
      validate_platform_arg(platform, class = class),
      platform
    )
  }
  # Every platform that condathis picks itself is one of them.
  for (sys_arch in c(
    "Linux-x86_64",
    "Linux-aarch64",
    "Linux-ppc64le",
    "Darwin-x86_64",
    "Darwin-arm64",
    "Windows-x86_64",
    "Windows-arm64"
  )) {
    platform <- is_micromamba_available_for_arch(sys_arch)
    testthat::expect_true(platform %in% known_platforms, info = sys_arch)
  }
})

testthat::test_that("create_env() rejects an invalid env_name, with the old and new class", {
  local_no_backend()
  cnd <- catch_error(create_env(env_name = "../outside"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_invalid_env_name",
      "condathis_create_invalid_env_name",
      "condathis_invalid_env_name",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
})

testthat::test_that("create_env() rejects a missing env_file, with the old and new class", {
  local_no_backend()
  cnd <- catch_error(create_env(env_file = "definitely-does-not-exist.yml"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_missing_env_file",
      "condathis_create_missing_env_file",
      "condathis_invalid_env_file",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  # Regression test: the message printed the literal text "env_file".
  testthat::expect_match(
    conditionMessage(cnd),
    "definitely-does-not-exist.yml",
    fixed = TRUE
  )
})

testthat::test_that("create_env() rejects an env_file that is not a single string", {
  # Regression test: only `file_exists()` was checked, so a vector of two
  # existing files passed.
  local_no_backend()
  f1 <- withr::local_tempfile(fileext = ".yml", lines = "dependencies: []")
  f2 <- withr::local_tempfile(fileext = ".yml", lines = "dependencies: []")
  for (bad in list(c(f1, f2), NA_character_, "", 1L)) {
    cnd <- catch_error(create_env(env_file = bad))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_invalid_env_file",
        "condathis_invalid_env_file",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
})

testthat::test_that("create_env() aborts when both package specs and env_file are given", {
  # Regression test: the specs were silently dropped.
  local_no_backend()
  env_file <- withr::local_tempfile(
    fileext = ".yml",
    lines = "dependencies: []"
  )
  cnd <- catch_error(create_env("zlib", env_file = env_file))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_conflicting_args",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
})

testthat::test_that("create_env() validates channels and additional_channels", {
  # Regression test: NULL silently meant "conda-forge" with micromamba and
  # no channel at all with other backends; NA became `-c NA`.
  local_no_backend()
  for (bad in list(NULL, character(0L), NA_character_, "", c("a", NA), 1L)) {
    cnd <- catch_error(create_env(env_name = "e", channels = bad))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_invalid_channels",
        "condathis_invalid_channels",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
  for (bad in list(character(0L), NA_character_, "", 1L)) {
    cnd <- catch_error(create_env(env_name = "e", additional_channels = bad))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_invalid_channels",
        "condathis_invalid_additional_channels",
        "condathis_invalid_channels",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(bad)
    )
  }
})

testthat::test_that("create_env() validates channel_priority regardless of environment state", {
  # Regression test: this check used to run only inside
  # backend_create_env(), which the already-satisfied shortcut skips.
  local_no_backend()
  cnd <- catch_error(
    create_env("zlib", env_name = "e", channel_priority = "bananas")
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_invalid_channel_priority",
      "condathis_invalid_channel_priority",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
})

testthat::test_that("create_env() passes one channel_priority and one verbose string to the backend", {
  # Rule R4: a backend generic always gets one of the five verbose strings.
  stub <- local_env_stub("stub-create-args")
  # The default verbose reports the creation.
  testthat::expect_message(
    create_env(env_name = "args-a"),
    regexp = "successfully created"
  )
  testthat::expect_message(
    create_env(
      env_name = "args-b",
      verbose = TRUE,
      channel_priority = "flexible"
    ),
    regexp = "successfully created"
  )
  testthat::expect_no_message(create_env(env_name = "args-c", verbose = FALSE))
  calls <- stub_calls(stub, "backend_create_env")
  testthat::expect_length(calls, 3L)
  testthat::expect_identical(
    lapply(calls, function(x) x$args$verbose),
    list("output", "output", "silent")
  )
  testthat::expect_identical(
    lapply(calls, function(x) x$args$channel_priority),
    list("strict", "flexible", "strict")
  )
  # No specs reach the backend as NULL.
  testthat::expect_null(calls[[1L]]$args$packages)
})

testthat::test_that("create_env() reads the backend result by exact name", {
  # Regression test: a backend returning TRUE made create_env() fail after
  # the environment was created.
  stub <- local_env_stub(
    "stub-create-true",
    backend_create_env = function(backend, env_name = "condathis-env", ...) {
      fs::dir_create(fs::path(stub_root, "envs", env_name))
      return(TRUE)
    }
  )
  stub_root <- stub$root
  res <- create_env(env_name = "true-env", verbose = "silent")
  testthat::expect_s3_class(res, "condathis_result")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$stdout, NA_character_)
  # cmd-field: the stub reports no command line, so cmd is NA.
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_identical(res$env_name, "true-env")
})

testthat::test_that("create_env() reports the backend's command line and fails on a non-zero status", {
  stub <- local_env_stub(
    "stub-create-status",
    backend_create_env = function(backend, env_name = "condathis-env", ...) {
      if (identical(env_name, "bad-env")) {
        return(list(status = 1L, stderr = "solver failed"))
      }
      return(list(status = 0L, cmd = "stub create -n ok-env"))
    }
  )
  res <- create_env(env_name = "ok-env", verbose = "silent")
  testthat::expect_identical(res$cmd, "stub create -n ok-env")
  cnd <- catch_error(create_env(env_name = "bad-env", verbose = "silent"))
  testthat::expect_s3_class(cnd, "condathis_create_env_failed")
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_s3_class(cnd, "condathis_error")
  # A failed environment gets no backend marker.
  testthat::expect_false(
    fs::file_exists(fs::path(stub$root, "envs", "bad-env", ".condathis"))
  )
})

testthat::test_that("create_env() re-raises a backend error with its own classes", {
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  local_env_stub("stub-create-boom", backend_create_env = stub_boom)
  cnd <- catch_error(create_env(env_name = "boom-env", verbose = "silent"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_failed",
      "condathis_backend_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_true(rlang::cnd_inherits(cnd, "stub_boom"))
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Backend stub-create-boom failed to create environment 'boom-env'.",
    fixed = TRUE
  )
  testthat::expect_identical(
    conditionCall(cnd),
    quote(create_env(env_name = "boom-env", verbose = "silent"))
  )
})

testthat::test_that("create_env() catches an old positional env_name", {
  # Decision D6: `create_env("pkg", "env")` now means two specs. When the
  # last one names an existing environment, the user meant env_name.
  stub <- local_env_stub("stub-create-positional", envs = "my-env")
  cnd <- catch_error(create_env("python", "my-env"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_positional_env_name",
      "condathis_invalid_packages",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_match(
    conditionMessage(cnd),
    "env_name = \"my-env\"",
    fixed = TRUE
  )
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  # With env_name named, the specs are only specs.
  res <- create_env("python", "my-env", env_name = "other-env", verbose = FALSE)
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[1L]]$args$packages,
    c("python", "my-env")
  )
})

testthat::test_that("create_env() checks for a positional env_name only with two or more unnamed specs", {
  # Regression test: `packages = c("x", "<env>")` and one vector aborted
  # when "<env>" named an existing environment. 0.1.4 read both as specs.
  id <- "deprecated_packages_arg_create_env"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  stub <- local_env_stub("stub-create-positional-alias", envs = "my-env")
  testthat::expect_warning(
    res <- create_env(packages = c("python", "my-env"), verbose = FALSE),
    class = "condathis_deprecated_packages_arg"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[1L]]$args$packages,
    c("python", "my-env")
  )
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[1L]]$args$env_name,
    "condathis-env"
  )
  # The same through do.call() with a named list, and as one vector.
  remove_env("condathis-env", verbose = "silent")
  res <- do.call(
    create_env,
    list(packages = c("python", "my-env"), verbose = FALSE)
  )
  testthat::expect_identical(res$status, 0L)
  remove_env("condathis-env", verbose = "silent")
  res <- create_env(c("python", "my-env"), verbose = FALSE)
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 3L)
  # Two unnamed arguments still abort.
  testthat::expect_error(
    create_env("python", "my-env"),
    class = "condathis_create_env_positional_env_name"
  )
  testthat::expect_error(
    create_env(c("python"), "my-env"),
    class = "condathis_create_env_positional_env_name"
  )
})

testthat::test_that("create_env() reads the 0.1.4 default method vector", {
  id <- "deprecated_method_native"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  testthat::local_mocked_bindings(
    resolve_backend = function(env_name = NULL, method = "auto", ...) {
      rlang::abort(method, class = "stub_resolved")
    }
  )
  # c("native", "auto") is "native": micromamba, with the deprecation.
  testthat::expect_warning(
    cnd <- rlang::catch_cnd(
      create_env(env_name = "e", method = c("native", "auto")),
      classes = "stub_resolved"
    ),
    class = "condathis_deprecated_method_native"
  )
  testthat::expect_identical(conditionMessage(cnd), "micromamba")
  cnd <- rlang::catch_cnd(
    create_env(env_name = "e", method = c("auto", "native")),
    classes = "stub_resolved"
  )
  testthat::expect_identical(conditionMessage(cnd), "auto")
})

testthat::test_that("create_env() warns about packages = only for direct use", {
  withr::local_options(lifecycle_verbosity = NULL)
  id <- "deprecated_packages_arg_create_env"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  stub <- local_env_stub("stub-create-soft")
  # A function of another package's namespace, such as a wrapper in a
  # package that depends on condathis.
  pkg_env <- new.env(parent = asNamespace("tools"))
  pkg_env$create_env <- create_env
  pkg_fn <- function(env_name) {
    return(create_env(packages = "zlib", env_name = env_name, verbose = FALSE))
  }
  environment(pkg_fn) <- pkg_env
  testthat::expect_no_warning(res <- pkg_fn("soft-env"))
  testthat::expect_identical(res$status, 0L)
  testthat::expect_false(isTRUE(condathis_warn_once_state[[id]]))
  # From the tests of this package, once.
  testthat::expect_warning(
    create_env(packages = "zlib", env_name = "soft-env-2", verbose = FALSE),
    class = "condathis_deprecated_packages_arg"
  )
  testthat::expect_no_warning(
    create_env(packages = "zlib", env_name = "soft-env-3", verbose = FALSE)
  )
})

testthat::test_that("create_env() accepts packages = as a deprecated alias", {
  id <- "deprecated_packages_arg_create_env"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  stub <- local_env_stub("stub-create-alias")
  testthat::expect_warning(
    res <- create_env(
      packages = "zlib",
      env_name = "alias-env",
      verbose = FALSE
    ),
    class = "condathis_deprecated_packages_arg"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[1L]]$args$packages,
    "zlib"
  )
})

testthat::test_that("create_env(overwrite = FALSE) keeps an existing environment that has the packages", {
  stub <- local_env_stub(
    "stub-keep",
    envs = "keep-env",
    packages = pkgs_df("zlib", version = "1.3.1")
  )
  testthat::expect_message(
    res <- create_env("zlib>=1.3", env_name = "keep-env", verbose = "output"),
    regexp = "already has the requested packages"
  )
  testthat::expect_s3_class(res, "condathis_result")
  testthat::expect_identical(res$status, 0L)
  # Nothing ran.
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_no_message(
    create_env("zlib", env_name = "keep-env", verbose = "silent")
  )
})

testthat::test_that("create_env() with no specs on an existing environment changes nothing", {
  # Regression test: create_env(env_name = <existing>) rebuilt it empty,
  # which deleted every package added with install_packages().
  stub <- local_env_stub(
    "stub-noop",
    envs = "noop-env",
    packages = pkgs_df("python")
  )
  res <- create_env(env_name = "noop-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  # Nothing to compare, so the packages are not even listed.
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 0L)
})

testthat::test_that("create_env(overwrite = FALSE) aborts instead of replacing an environment", {
  # Decision D4: an unsatisfied request on an existing environment, or
  # any env_file request, aborts and keeps the environment.
  stub <- local_env_stub(
    "stub-exists",
    envs = "exists-env",
    packages = pkgs_df("zlib", version = "1.3.1")
  )
  cnd <- catch_error(
    create_env("zlib", "python", env_name = "exists-env", verbose = "silent")
  )
  testthat::expect_identical(
    class(cnd),
    c("condathis_create_env_exists", "condathis_error", rlang_tail)
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "python", fixed = TRUE)
  testthat::expect_match(message, "install_packages()", fixed = TRUE)
  testthat::expect_match(message, "overwrite = TRUE", fixed = TRUE)

  env_file <- withr::local_tempfile(
    fileext = ".yml",
    lines = "dependencies: []"
  )
  testthat::expect_error(
    create_env(
      env_file = env_file,
      env_name = "exists-env",
      verbose = "silent"
    ),
    class = "condathis_create_env_exists"
  )
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_true(fs::dir_exists(fs::path(
    stub$root,
    "envs",
    "exists-env"
  )))
})

testthat::test_that("create_env(overwrite = TRUE) creates an existing environment again", {
  stub <- local_env_stub(
    "stub-overwrite",
    envs = "overwrite-env",
    packages = pkgs_df("zlib")
  )
  res <- create_env(
    "python",
    env_name = "overwrite-env",
    overwrite = TRUE,
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  calls <- stub_calls(stub, "backend_create_env")
  testthat::expect_length(calls, 1L)
  testthat::expect_true(calls[[1L]]$args$overwrite)
  # The old environment is not read.
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 0L)
})

testthat::test_that("create_env() aborts instead of acting on a failed existence check", {
  # Rule R5: a probe that fails is not read as "absent", because creating
  # the environment again would replace it.
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  stub <- local_env_stub("stub-probe-fail", backend_env_exists = stub_boom)
  cnd <- suppressWarnings(
    catch_error(
      create_env(env_name = "probe-env", method = "stub-probe-fail")
    ),
    classes = "condathis_backend_query_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_probe_failed")
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_true(rlang::cnd_inherits(cnd, "stub_boom"))
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("env_exists_for_change() aborts on a failed probe", {
  # Rule R5, tested directly: through create_env(), resolve_backend()
  # usually aborts first, in find_owning_backends(mutating = TRUE).
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  stub <- local_stub_backend(
    "stub-probe-direct",
    backend_env_exists = stub_boom
  )
  cnd <- catch_error(
    env_exists_for_change(stub$backend, "stub-probe-direct", "probe-env")
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_backend_probe_failed",
      "condathis_backend_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "stub-probe-direct", fixed = TRUE)
  testthat::expect_match(message, "probe-env", fixed = TRUE)

  # The condathis classes of the probe's error are kept.
  stub_status <- local_stub_backend(
    "stub-probe-status",
    backend_env_exists = function(...) {
      condathis_abort("exit 1", class = "condathis_cmd_status_error")
    }
  )
  cnd <- catch_error(
    env_exists_for_change(stub_status$backend, "stub-probe-status", "probe-env")
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_backend_probe_failed",
      "condathis_backend_error",
      "condathis_cmd_status_error",
      "condathis_error",
      rlang_tail
    )
  )

  # A probe that works gives TRUE or FALSE.
  stub_ok <- local_stub_backend("stub-probe-ok", envs = "here-env")
  testthat::expect_true(
    env_exists_for_change(stub_ok$backend, "stub-probe-ok", "here-env")
  )
  testthat::expect_false(
    env_exists_for_change(stub_ok$backend, "stub-probe-ok", "other-env")
  )
})

testthat::test_that("create_env() aborts on a failed probe that resolve_backend() did not catch", {
  # The branch of create_env() itself: resolve_backend() is mocked to return
  # the stub, so find_owning_backends() does not probe first.
  stub_boom <- function(...) rlang::abort("boom", class = "stub_boom")
  stub <- local_stub_backend(
    "stub-probe-create",
    backend_env_exists = stub_boom
  )
  testthat::local_mocked_bindings(
    resolve_backend = function(...) {
      return(list(backend = stub$backend, name = "stub-probe-create"))
    }
  )
  cnd <- catch_error(
    create_env("zlib", env_name = "probe-env", verbose = "silent")
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_backend_probe_failed",
      "condathis_backend_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 0L)
  # With overwrite = TRUE too: an existing environment is moved aside
  # before the backend creates it again (see with_env_dir_replacement()),
  # so the probe decides what happens to the directory. Its error has the
  # classes of a failed create, as when micromamba's own replacement code
  # made that check. Regression test: it had the classes of a failed
  # probe.
  cnd <- catch_error(
    create_env(
      "zlib",
      env_name = "probe-env",
      overwrite = TRUE,
      verbose = "silent"
    )
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_failed",
      "condathis_backend_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_s3_class(cnd$parent, "stub_boom")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Backend stub-probe-create failed to create environment 'probe-env'.",
    fixed = TRUE
  )
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("create_env(overwrite = FALSE) keeps an environment for specs in another case", {
  # Regression test: names compared with case, so a second, identical
  # create_env("ZLIB", env_name = "x") aborted with
  # condathis_create_env_exists, although micromamba had installed `zlib`.
  stub <- local_env_stub(
    "stub-case",
    envs = "case-env",
    packages = pkgs_df(c("zlib", "pyyaml"), version = c("1.3.2", "6.0.3"))
  )
  testthat::expect_message(
    res <- create_env(
      "ZLIB",
      "PyYAML>=6",
      env_name = "case-env",
      verbose = "output"
    ),
    regexp = "already has the requested packages"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_true(is.na(res$cmd))
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("create_env(overwrite = FALSE) compares bracket constraints it can read", {
  # Regression test: every spec with brackets counted as not satisfied, so
  # a second, identical create_env("zlib[build_number=0]", ...) aborted.
  stub <- local_env_stub(
    "stub-brackets",
    envs = "brackets-env",
    packages = pkgs_df("zlib", version = "1.3.2", build_string = "h25fd6f3_0")
  )
  res <- create_env(
    "zlib[version='>=1.3', build_number=0]",
    "zlib[build=h25fd*]",
    env_name = "brackets-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)

  cnd <- catch_error(create_env(
    "zlib[build_number='>0']",
    env_name = "brackets-env",
    verbose = "silent"
  ))
  testthat::expect_s3_class(cnd, "condathis_create_env_exists")
  testthat::expect_no_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "never count",
    fixed = TRUE
  )

  # A key that the package listing cannot answer aborts, and the message
  # says why the spec never counts as satisfied.
  cnd <- catch_error(create_env(
    "zlib[md5=0123abcd]",
    "zlib[sha256=abc]",
    env_name = "brackets-env",
    verbose = "silent"
  ))
  testthat::expect_identical(
    class(cnd),
    c("condathis_create_env_exists", "condathis_error", rlang_tail)
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(
    message,
    "\"zlib[md5=0123abcd]\" and \"zlib[sha256=abc]\" never count as satisfied",
    fixed = TRUE
  )
  testthat::expect_match(message, "overwrite = TRUE", fixed = TRUE)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("create_env aborts instead of silently deleting a directory when the existence check itself fails", {
  # The stale-directory cleanup of `with_env_dir_replacement()` must not
  # read a failed existence check as "absent, safe to delete". create_env()
  # now aborts before it calls the backend (rule R5).
  install_dir <- install_dir_for_backend(micromamba_backend())
  fake_env_dir <- fs::path(
    install_dir,
    "envs",
    "condathis-swallow-guard-test-env"
  )
  fs::dir_create(fake_env_dir)
  withr::defer(fs::dir_delete(fake_env_dir))
  marker_file <- fs::path(fake_env_dir, "marker.txt")
  fs::file_create(marker_file)

  testthat::local_mocked_bindings(
    backend_env_exists = function(backend, env_name, verbose = "silent") {
      cli::cli_abort(
        message = "Simulated transient existence-check failure.",
        class = "condathis_cmd_status_error"
      )
    }
  )

  cnd <- suppressWarnings(
    catch_error(
      create_env(
        "python",
        env_name = "condathis-swallow-guard-test-env",
        method = "micromamba",
        verbose = "silent"
      )
    ),
    classes = "condathis_backend_query_failed"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_probe_failed")
  testthat::expect_s3_class(cnd, "condathis_cmd_status_error")
  testthat::expect_true(fs::file_exists(marker_file))
})

testthat::test_that("create_env() checks the package listing of an existing environment", {
  # Regression test: without a `platform` column, the platform check never
  # fired, and `$build_string` warned on a tibble. A listing that breaks
  # the backend contract now aborts at the boundary.
  local_env_stub(
    "stub-create-columns",
    envs = "columns-env",
    packages = data.frame(
      name = "pkg1",
      version = "1.0",
      channel = "conda-forge"
    )
  )
  cnd <- catch_error(
    create_env(
      "pkg1",
      env_name = "columns-env",
      platform = "linux-64",
      verbose = "silent"
    )
  )
  testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
  testthat::expect_s3_class(cnd, "condathis_error")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "platform",
    fixed = TRUE
  )
})

testthat::test_that("create_env with platform keeps an existing environment that satisfies the request", {
  # Regression test: any non-NULL `platform` skipped the already-satisfied
  # check, so every call ran `micromamba create --yes` on the existing
  # environment. That rebuilt it from scratch and dropped packages added
  # since with install_packages().
  stub <- local_env_stub(
    "stub-platform-keep",
    envs = "platform-env",
    packages = pkgs_df(c("pkg1", "pkg2"), platform = c("linux-64", "noarch"))
  )
  res <- create_env(
    "pkg1",
    env_name = "platform-env",
    platform = "linux-64",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("create_env with platform keeps an environment of only noarch packages", {
  # `noarch` packages install on any platform, so they never count as a
  # mismatch.
  stub <- local_env_stub(
    "stub-platform-noarch",
    envs = "noarch-env",
    packages = pkgs_df("pkg1", platform = "noarch")
  )
  res <- create_env(
    "pkg1",
    env_name = "noarch-env",
    platform = "osx-arm64",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("create_env aborts instead of rebuilding an environment of another platform", {
  stub <- local_env_stub(
    "stub-platform-mismatch",
    envs = "mismatch-env",
    packages = pkgs_df(c("pkg1", "pkg2"), platform = c("osx-64", "noarch"))
  )
  cnd <- catch_error(
    create_env(
      "pkg1",
      env_name = "mismatch-env",
      platform = "osx-arm64",
      verbose = "silent"
    )
  )
  # The new class and the old one.
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_platform_mismatch",
      "condathis_create_platform_mismatch",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_match(
    conditionMessage(cnd),
    "overwrite = TRUE",
    fixed = TRUE
  )

  # The platform check comes first: also for a spec that is not installed,
  # and for env_file.
  testthat::expect_error(
    create_env(
      "other-pkg",
      env_name = "mismatch-env",
      platform = "osx-arm64",
      verbose = "silent"
    ),
    class = "condathis_create_env_platform_mismatch"
  )
  env_file <- withr::local_tempfile(
    fileext = ".yml",
    lines = "dependencies: []"
  )
  testthat::expect_error(
    create_env(
      env_file = env_file,
      env_name = "mismatch-env",
      platform = "osx-arm64",
      verbose = "silent"
    ),
    class = "condathis_create_env_platform_mismatch"
  )
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("create_env with overwrite = TRUE rebuilds an environment of another platform", {
  stub <- local_env_stub(
    "stub-platform-overwrite",
    envs = "platform-overwrite-env",
    packages = pkgs_df("pkg1", platform = "osx-64")
  )
  res <- create_env(
    "pkg1",
    env_name = "platform-overwrite-env",
    platform = "osx-arm64",
    overwrite = TRUE,
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 1L)
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 0L)
})

testthat::test_that("create_env without platform does not compare the platform of an environment", {
  # The Rosetta 2 fallback creates osx-64 environments on Apple Silicon
  # without a `platform` argument, so `platform = NULL` must not compare.
  stub <- local_env_stub(
    "stub-platform-null",
    envs = "platform-null-env",
    packages = pkgs_df("pkg1", platform = "osx-64")
  )
  res <- create_env("pkg1", env_name = "platform-null-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  # The one listing is for the satisfaction check.
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 1L)
})

testthat::test_that("create_env with platform reads an existing environment only once", {
  # Regression test: the platform check and the satisfaction check each
  # listed the packages, so a `platform` request started one extra
  # `micromamba list --json`.
  without_platform <- local_env_stub(
    "stub-one-read-a",
    envs = "one-read-env",
    packages = pkgs_df("pkg1", platform = "linux-64")
  )
  create_env("pkg1", env_name = "one-read-env", verbose = "silent")
  with_platform <- local_env_stub(
    "stub-one-read-b",
    envs = "one-read-env",
    packages = pkgs_df("pkg1", platform = "linux-64")
  )
  res <- create_env(
    "pkg1",
    env_name = "one-read-env",
    platform = "linux-64",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(
    stub_calls(with_platform, "backend_list_packages"),
    1L
  )
  # Same number of existence checks as a call without `platform`.
  testthat::expect_identical(
    length(stub_calls(with_platform, "backend_env_exists")),
    length(stub_calls(without_platform, "backend_env_exists"))
  )
})

testthat::test_that("create_env with platform does not list packages of a new environment", {
  stub <- local_env_stub("stub-platform-new")
  res <- create_env(
    "pkg1",
    env_name = "platform-new-env",
    platform = "linux-64",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 1L)
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 0L)
})

testthat::test_that("create_env() records the platform it passed to the backend", {
  # The platform goes into the marker, so later installs solve for it, with
  # every backend (see env_platform()).
  stub <- local_env_stub("stub-platform-marker")
  create_env(
    "pkg",
    env_name = "given-env",
    platform = "osx-64",
    verbose = "silent"
  )
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[1L]]$args$platform,
    "osx-64"
  )
  marker <- read_backend_marker(fs::path(stub$root, "envs", "given-env"))
  testthat::expect_identical(marker$backend, "stub-platform-marker")
  testthat::expect_identical(marker$platform, "osx-64")

  # The native platform: no platform, and none recorded.
  create_env("pkg", env_name = "native-env", verbose = "silent")
  testthat::expect_null(
    stub_calls(stub, "backend_create_env")[[2L]]$args$platform
  )
  marker <- read_backend_marker(fs::path(stub$root, "envs", "native-env"))
  testthat::expect_identical(marker$backend, "stub-platform-marker")
  testthat::expect_false("platform" %in% names(marker))
})

testthat::test_that("create_env() chooses an emulated platform for every backend", {
  # The emulation fallback runs in the front end: a backend that can tell
  # whether the request solves gets the emulated platform, and the marker
  # records it. The OS is given through mocks.
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    is_rosetta_running = function() TRUE
  )
  stub <- local_env_stub(
    "stub-platform-emulated",
    backend_can_solve = function(backend, ..., platform) {
      return(identical(platform, "osx-64"))
    }
  )
  msgs <- character(0L)
  withCallingHandlers(
    create_env("r-base", env_name = "emulated-env", verbose = "output"),
    message = function(m) {
      msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  testthat::expect_match(
    paste(msgs, collapse = "\n"),
    "Using Rosetta 2 emulation.",
    fixed = TRUE
  )
  solves <- stub_calls(stub, "backend_can_solve")
  testthat::expect_identical(
    vapply(solves, function(x) x$args$platform, character(1L)),
    c("osx-arm64", "osx-64")
  )
  testthat::expect_identical(solves[[1L]]$args$packages, "r-base")
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[1L]]$args$platform,
    "osx-64"
  )
  testthat::expect_identical(
    read_backend_marker(fs::path(stub$root, "envs", "emulated-env"))$platform,
    "osx-64"
  )

  # An empty environment is not solved.
  create_env(env_name = "empty-env", verbose = "silent")
  testthat::expect_length(stub_calls(stub, "backend_can_solve"), 2L)
  testthat::expect_null(
    stub_calls(stub, "backend_create_env")[[2L]]$args$platform
  )
})

testthat::test_that("create_env() warns when the backend did not run link scripts", {
  skipped <- data.frame(
    package = c("zeta", "alpha", "alpha", "beta"),
    script = c("post-link", "post-link", "pre-link", "pre-unlink"),
    stringsAsFactors = FALSE
  )
  stub <- local_env_stub(
    "stub-link-scripts",
    backend_create_env = function(backend, env_name = "condathis-env", ...) {
      fs::dir_create(fs::path(
        backend_get_install_dir(backend),
        "envs",
        env_name
      ))
      return(list(status = 0L, link_scripts_skipped = skipped))
    }
  )
  msgs <- character(0L)
  cnd <- NULL
  res <- withCallingHandlers(
    create_env("pkg", env_name = "scripts-env", verbose = "output"),
    message = function(m) {
      msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
      invokeRestart("muffleMessage")
    },
    warning = function(w) {
      cnd <<- w
      invokeRestart("muffleWarning")
    }
  )
  # The environment is created, and the result has the same fields as for
  # any backend.
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    names(unclass(res)),
    c("status", "stdout", "stderr", "timeout", "pid", "cmd", "env_name")
  )
  testthat::expect_null(attr(res, "link_scripts_skipped"))
  testthat::expect_match(
    paste(msgs, collapse = "\n"),
    "successfully created",
    fixed = TRUE
  )
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_link_scripts_skipped",
      "condathis_link_scripts_skipped",
      "condathis_warning",
      "rlang_warning",
      "warning",
      "condition"
    )
  )
  testthat::expect_identical(cnd$backend, "stub-link-scripts")
  testthat::expect_identical(cnd$env_name, "scripts-env")
  testthat::expect_identical(cnd$packages, c("alpha", "beta", "zeta"))
  testthat::expect_identical(cnd$scripts, skipped)
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(
    message,
    "Backend stub-link-scripts did not run the pre-link scripts of alpha.",
    fixed = TRUE
  )
  testthat::expect_match(
    message,
    "did not run the post-link scripts of alpha and zeta.",
    fixed = TRUE
  )
  testthat::expect_match(
    message,
    "did not run the pre-unlink scripts of beta before it removed them.",
    fixed = TRUE
  )
  testthat::expect_match(message, "may not work", fixed = TRUE)
  testthat::expect_match(message, "method = \"micromamba\"", fixed = TRUE)

  # At every verbose level: a warning is not output.
  testthat::expect_warning(
    create_env(
      "pkg",
      env_name = "scripts-env",
      overwrite = TRUE,
      verbose = "silent"
    ),
    class = "condathis_link_scripts_skipped"
  )
})

testthat::test_that("create_env() does not warn for a backend that ran every link script", {
  for (value in list(
    NULL,
    data.frame(package = character(0L), script = character(0L))
  )) {
    stub <- local_env_stub(
      "stub-link-scripts-none",
      backend_create_env = function(backend, env_name = "condathis-env", ...) {
        fs::dir_create(fs::path(
          backend_get_install_dir(backend),
          "envs",
          env_name
        ))
        return(list(status = 0L, link_scripts_skipped = value))
      }
    )
    testthat::expect_no_warning(
      create_env(
        "pkg",
        env_name = "no-scripts-env",
        overwrite = TRUE,
        verbose = "silent"
      )
    )
  }
})

testthat::test_that("create_env() aborts for an invalid link_scripts_skipped and keeps the old environment", {
  testthat::skip_on_cran()
  bad_values <- list(
    "plink",
    data.frame(package = "plink", stringsAsFactors = FALSE),
    data.frame(
      package = "plink",
      script = "post-install",
      stringsAsFactors = FALSE
    ),
    data.frame(
      package = NA_character_,
      script = "post-link",
      stringsAsFactors = FALSE
    ),
    data.frame(package = factor("plink"), script = "post-link")
  )
  for (value in bad_values) {
    stub <- local_env_stub(
      "stub-link-scripts-bad",
      envs = "bad-scripts-env",
      backend_create_env = function(backend, env_name = "condathis-env", ...) {
        env_dir <- fs::path(backend_get_install_dir(backend), "envs", env_name)
        fs::dir_create(env_dir)
        fs::file_create(fs::path(env_dir, "new-file"))
        return(list(status = 0L, link_scripts_skipped = value))
      }
    )
    old_file <- fs::path(stub$root, "envs", "bad-scripts-env", "old-file")
    fs::file_create(old_file)
    cnd <- catch_error(create_env(
      "pkg",
      env_name = "bad-scripts-env",
      overwrite = TRUE,
      verbose = "silent"
    ))
    testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
    testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "backend_create_env()",
      fixed = TRUE
    )
    testthat::expect_true(fs::file_exists(old_file))
  }
})

testthat::test_that("every create_env() error has the class condathis_error", {
  local_no_backend()
  testthat::expect_error(create_env(env_name = 1), class = "condathis_error")
  testthat::expect_error(create_env(1), class = "condathis_error")
  testthat::expect_error(create_env(overwrite = 1), class = "condathis_error")
})

testthat::test_that("packages_satisfied_by matches satisfies_dependencies on the same listing", {
  # `create_env()` checks specs against a listing it already has. The
  # result must be the same as the check that lists the packages itself.
  installed <- pkgs_df(
    c("zlib", "python"),
    version = c("1.3.1", "3.12.4"),
    build_string = c("h4ab18f5_1", "h2ad013b_0_cpython"),
    channel = c("conda-forge", "https://conda.anaconda.org/bioconda/"),
    platform = c("linux-64", "linux-64")
  )
  specs <- c(
    "zlib",
    "zlib>=1.3",
    "zlib<1",
    "python=3.12",
    "conda-forge::python",
    "bioconda::python",
    "python[build_number=0]",
    "missing-pkg"
  )
  testthat::local_mocked_bindings(
    backend_list_packages = function(...) installed
  )
  for (channels in list(NULL, "conda-forge", c("conda-forge", "bioconda"))) {
    testthat::expect_identical(
      packages_satisfied_by(
        packages = specs,
        installed_pkgs_df = installed,
        channels = channels
      ),
      satisfies_dependencies(
        pkg_str_vector = specs,
        env_name = "condathis-satisfied-parity-env",
        backend = micromamba_backend(),
        channels = channels
      ),
      info = deparse(channels)
    )
  }
})

testthat::test_that("check_env_request() reports the platform mismatch first", {
  installed <- pkgs_df(c("a", "b"), platform = c("osx-64", "noarch"))
  res <- check_env_request(installed, c("a", "c"), platform = "linux-64")
  testthat::expect_false(res$satisfied)
  testthat::expect_identical(res$reason, "platform_mismatch")
  testthat::expect_identical(res$unsatisfied, "c")
  testthat::expect_identical(res$env_platforms, "osx-64")

  res <- check_env_request(installed, c("a", "c"))
  testthat::expect_identical(res$reason, "unsatisfied")
  testthat::expect_identical(res$unsatisfied, "c")

  res <- check_env_request(NULL, character(0L))
  testthat::expect_true(res$satisfied)
  testthat::expect_identical(res$reason, NA_character_)
})

testthat::test_that("env_package_platforms drops noarch and missing platforms", {
  testthat::expect_identical(
    env_package_platforms(data.frame(
      platform = c("linux-64", "noarch", "linux-64", NA, "")
    )),
    "linux-64"
  )
  testthat::expect_identical(
    env_package_platforms(data.frame(platform = "noarch")),
    character(0L)
  )
  # A backend that reports no platform column gives no evidence.
  testthat::expect_identical(
    env_package_platforms(data.frame(name = "x")),
    character(0L)
  )
})

testthat::test_that("create_env with platform does not rebuild an existing environment", {
  # Regression test with a real environment: `micromamba create --yes` on
  # an existing environment deletes its directory, so a file placed in it
  # shows whether the second call rebuilt it.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "condathis-platform-no-rebuild-env"
  native_platform <- is_micromamba_available_for_arch()
  create_args <- list(
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel(),
    platform = native_platform,
    verbose = "silent"
  )
  res <- do.call(create_env, create_args)
  testthat::expect_identical(res$status, 0L)
  withr::defer(remove_env(env_name, verbose = "silent"))

  marker <- fs::path(get_env_dir(env_name), "condathis-test-marker.txt")
  fs::file_create(marker)

  res <- do.call(create_env, create_args)
  testthat::expect_identical(res$status, 0L)
  testthat::expect_true(fs::file_exists(marker))
})

testthat::test_that("create_env() creates an environment for a platform that micromamba does not list", {
  # Regression test with a real environment: `"emscripten-wasm32"` aborted
  # before micromamba ran, although micromamba solves for it. The local
  # channel has only `noarch` packages, which match every platform.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "condathis-dynamic-platform-env"
  res <- create_env(
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel(),
    platform = "emscripten-wasm32",
    verbose = "silent"
  )
  withr::defer(remove_env(env_name, verbose = "silent"))
  testthat::expect_identical(res$status, 0L)
  testthat::expect_match(res$cmd, "emscripten-wasm32", fixed = TRUE)
  testthat::expect_identical(
    env_platform(get_env_dir(env_name)),
    "emscripten-wasm32"
  )
  testthat::expect_identical(
    read_backend_marker(get_env_dir(env_name))$platform,
    "emscripten-wasm32"
  )
  testthat::expect_true(validate_env(
    "polyglot",
    env_name = env_name,
    platform = "emscripten-wasm32"
  ))
})

testthat::test_that("create_env(overwrite = FALSE) never deletes packages added later", {
  # Regression test for decision D4 with a real environment:
  # `create_env(env_name = x)` rebuilt `x` empty, which deleted the
  # packages installed into it with install_packages().
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "condathis-overwrite-semantics-env"
  create_env(env_name = env_name, verbose = "silent")
  withr::defer(remove_env(env_name, verbose = "silent"))
  install_packages(
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel(),
    verbose = "silent"
  )
  has_polyglot <- function() {
    return("polyglot" %in% list_packages(env_name, verbose = "silent")$name)
  }
  testthat::expect_true(has_polyglot())

  res <- create_env(env_name = env_name, verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_true(has_polyglot())

  testthat::expect_error(
    create_env(
      "polyglot>=99",
      env_name = env_name,
      channels = polyglot_channel(),
      verbose = "silent"
    ),
    class = "condathis_create_env_exists"
  )
  testthat::expect_true(has_polyglot())

  res <- create_env(env_name = env_name, overwrite = TRUE, verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_false(has_polyglot())
})

testthat::test_that("create_env() through micromamba reports the command line that ran", {
  # Regression test: cmd was an invented summary that left out the flags
  # micromamba really got, such as `--override-channels` and `-c`.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  env_name <- "condathis-cmd-field-env"
  res <- create_env(
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel(),
    verbose = "silent"
  )
  withr::defer(remove_env(env_name, verbose = "silent"))
  testthat::expect_identical(res$status, 0L)
  testthat::expect_match(res$cmd, "--override-channels", fixed = TRUE)
  testthat::expect_match(res$cmd, "polyglot", fixed = TRUE)
})

testthat::test_that("create_env returns a condathis_result when dependencies are already satisfied", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  create_env(
    "zlib",
    env_name = "condathis-already-satisfied-test-env",
    channels = "conda-forge",
    verbose = "silent"
  )

  # Second call with the same package: the satisfaction check returns
  # before any process starts.
  px_res <- create_env(
    "zlib",
    env_name = "condathis-already-satisfied-test-env",
    channels = "conda-forge",
    verbose = "silent"
  )
  testthat::expect_s3_class(px_res, "condathis_result")
  testthat::expect_equal(px_res$status, 0L)
  testthat::expect_identical(px_res$cmd, NA_character_)
  testthat::expect_equal(
    px_res$env_name,
    "condathis-already-satisfied-test-env"
  )

  # A missing `env_file` aborts before the satisfaction check.
  testthat::expect_error(
    object = {
      create_env(
        env_file = "definitely-does-not-exist.yml",
        env_name = "condathis-already-satisfied-test-env",
        channels = "conda-forge",
        verbose = "silent"
      )
    },
    class = "condathis_create_missing_env_file"
  )

  remove_env(
    env_name = "condathis-already-satisfied-test-env",
    verbose = "silent"
  )
})

testthat::test_that("create_env rethrows a failing micromamba command", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  cnd <- catch_error(
    create_env(
      "this-package-definitely-does-not-exist-xyz-condathis-test",
      env_name = "condathis-cmd-status-error-test-env",
      channels = "conda-forge",
      verbose = "silent"
    )
  )
  # The backend's class is kept, under the classes of rule R1.
  testthat::expect_s3_class(cnd, "condathis_cmd_status_error")
  testthat::expect_s3_class(cnd, "condathis_create_env_failed")
  testthat::expect_s3_class(cnd, "condathis_backend_error")

  if (fs::dir_exists(get_env_dir("condathis-cmd-status-error-test-env"))) {
    fs::dir_delete(get_env_dir("condathis-cmd-status-error-test-env"))
  }
})

testthat::test_that("conda env is created", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # `test_r_base_pkgs()` (helper-cli-tools.R) pins the broken conda-forge
  # MinGW runtime on Windows - see the helper for the full root-cause
  # analysis. r-base itself is unpinned.
  px_res <- create_env(
    test_r_base_pkgs(),
    env_name = "condathis-create-test-env",
    verbose = "silent"
  )
  testthat::expect_s3_class(px_res, "condathis_result")
  testthat::expect_equal(px_res$status, 0L)
  testthat::expect_equal(px_res$env_name, "condathis-create-test-env")

  # Ensure micromamba is installed at the internal path for further tests.
  # With the discovery chain, native_cmd() may use an external micromamba
  # and skip installing to the internal path. Install explicitly here.
  if (isFALSE(fs::file_exists(micromamba_bin_path()))) {
    suppressMessages(install_micromamba(verbose = "silent"))
  }

  withr::with_path(
    new = dirname(micromamba_bin_path()),
    code = {
      umamba_path <- micromamba_user_installed()
    },
    action = "replace"
  )

  testthat::expect_true(fs::file_exists(umamba_path))

  run_res <- run(
    "Rmissing",
    env_name = "condathis-create-test-env",
    error = "continue",
    verbose = "silent"
  )

  testthat::expect_false(identical(run_res$status, 0L))

  testthat::expect_error(
    object = {
      run(
        "Rmissing",
        env_name = "condathis-create-test-env",
        error = "cancel",
        verbose = "silent"
      )
    },
    class = "condathis_run_status_error"
  )

  run_res <- run(
    "R",
    "-s",
    "-q",
    "--version",
    env_name = "condathis-create-test-env",
    verbose = "silent",
    error = "continue"
  )

  run_bin_res <- run_bin(
    "R",
    "-s",
    "-q",
    "--version",
    env_name = "condathis-create-test-env",
    verbose = "silent",
    error = "continue"
  )

  testthat::expect_equal(run_res$status, run_bin_res$status)

  testthat::expect_equal(run_res$status, 0L)

  r_version_output <- run_res$stdout
  # Check both stdout and stderr for R version output
  # + On Windows that can vary
  if (isFALSE(nzchar(r_version_output))) {
    r_version_output <- run_res$stderr
  }
  testthat::expect_true(
    stringr::str_detect(
      r_version_output,
      stringr::regex("R version 4\\.\\d+\\.\\d+")
    )
  )

  pkgs_list_res <- list_packages(
    env_name = "condathis-create-test-env",
    verbose = "silent"
  )

  testthat::expect_true(ncol(pkgs_list_res) > 0L)

  testthat::expect_true("r-base" %in% pkgs_list_res$name)

  withr::with_envvar(
    new = list(`MY_VAR_1` = "HELLO FROM OUTSIDE"),
    code = {
      px_res <- run(
        "R",
        "-q",
        "-s",
        "-e",
        "print(Sys.getenv('MY_VAR_1'))",
        env_name = "condathis-create-test-env",
        verbose = "silent"
      )
    }
  )

  testthat::expect_equal(px_res$status, 0L)
  envvar_output <- px_res$stdout
  if (isFALSE(nzchar(envvar_output))) {
    envvar_output <- px_res$stderr
  }
  testthat::expect_true(
    stringr::str_detect(envvar_output, "HELLO FROM OUTSIDE")
  )

  install_res <- install_packages(
    "python>=3.11,<4.0",
    env_name = "condathis-create-test-env",
    verbose = FALSE
  )
  testthat::expect_equal(install_res$status, 0L)

  inst_res <- run(
    "python",
    "--version",
    env_name = "condathis-create-test-env",
    verbose = FALSE
  )

  testthat::expect_equal(inst_res$status, 0L)

  testthat::expect_true(
    stringr::str_detect(
      inst_res$stdout,
      stringr::regex("Python 3\\.\\d+\\.\\d+")
    )
  )

  testthat::expect_true(env_exists(env_name = "condathis-create-test-env"))

  px_res <- remove_env(env_name = "condathis-create-test-env", verbose = FALSE)

  testthat::expect_equal(px_res$status, 0L)
  testthat::expect_false(env_exists(env_name = "condathis-create-test-env"))
  testthat::expect_false("condathis-create-test-env" %in% list_envs()$env_name)
})

testthat::test_that("Create conda env from file", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # conda-forge has no win-arm64 build of pandas: with the win-arm64
  # micromamba, the file falls back to win-64, through x64 emulation.
  px_res <- create_env(
    env_file = fs::path_package("condathis", "extdata", "stat-env.yml"),
    method = "micromamba",
    env_name = "condathis-create-file-test-env",
    verbose = "silent"
  )
  testthat::expect_equal(px_res$status, 0L)

  current_envs <- list_envs()

  testthat::expect_true(
    "condathis-create-file-test-env" %in% current_envs$env_name
  )

  testthat::expect_true(env_exists(env_name = "condathis-create-file-test-env"))

  px_res <- remove_env(
    env_name = "condathis-create-file-test-env",
    verbose = "silent"
  )

  testthat::expect_equal(px_res$status, 0L)

  current_envs <- list_envs()

  testthat::expect_false(
    "condathis-create-file-test-env" %in% current_envs$env_name
  )

  testthat::expect_false(env_exists(
    env_name = "condathis-create-file-test-env"
  ))
})

# A backend error with the text micromamba 2 gives for requested specs that
# are on none of the channels. The tree characters are escaped, so the file
# stays ASCII.
micromamba_not_found_error <- function(...) {
  stderr <- paste0(
    "error    libmamba Could not solve for environment specs\n",
    "    The following packages are incompatible\n",
    "    \u251c\u2500 samtools =1.17 * does not exist ",
    "(perhaps a typo or a missing channel);\n",
    "    \u2514\u2500 x =* * does not exist ",
    "(perhaps a typo or a missing channel).\n",
    "critical libmamba Could not solve for environment specs\n"
  )
  rlang::abort(
    "`micromamba` failed with status code 1.",
    class = c(
      "condathis_micromamba_status_error",
      "condathis_cmd_status_error",
      "condathis_error"
    ),
    status = 1L,
    stderr = stderr
  )
}

# The message of a condition on one line, so a match does not depend on
# where cli wraps it.
flat_message <- function(cnd) {
  return(gsub("\\s+", " ", cli::ansi_strip(conditionMessage(cnd))))
}

default_channels_hint_text <- "Since condathis 0.2.0, the default `channels` is only"

testthat::test_that("create_env() says that bioconda is no longer a default channel", {
  stub <- local_env_stub(
    "stub-default-channels",
    backend_create_env = micromamba_not_found_error
  )
  cnd <- catch_error(create_env(
    "samtools=1.17",
    "conda-forge::x",
    "python",
    env_name = "bioc-env",
    verbose = "silent"
  ))
  # The error keeps its classes, fields and parent.
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_failed",
      "condathis_backend_error",
      "condathis_micromamba_status_error",
      "condathis_cmd_status_error",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_identical(cnd$status, 1L)
  testthat::expect_match(cnd$stderr, "does not exist", fixed = TRUE)
  testthat::expect_s3_class(cnd$parent, "condathis_micromamba_status_error")
  message <- flat_message(cnd)
  testthat::expect_match(message, default_channels_hint_text, fixed = TRUE)
  # Only the requested specs without a channel that were not found.
  testthat::expect_match(message, "\"bioconda::samtools=1.17\"", fixed = TRUE)
  testthat::expect_no_match(message, "bioconda::conda-forge::x", fixed = TRUE)
  testthat::expect_no_match(message, "bioconda::python", fixed = TRUE)
  testthat::expect_match(
    message,
    "channels = c(\"conda-forge\", \"bioconda\")",
    fixed = TRUE
  )
  # The hint comes before the backend's own error.
  testthat::expect_true(
    regexpr("Since condathis", message, fixed = TRUE) <
      regexpr("Caused by error", message, fixed = TRUE)
  )
})

testthat::test_that("create_env() adds the default-channels hint only when it applies", {
  stub <- local_env_stub(
    "stub-default-channels-no",
    backend_create_env = micromamba_not_found_error
  )
  no_hint <- function(expr) {
    cnd <- catch_error(expr)
    testthat::expect_s3_class(cnd, "condathis_create_env_failed")
    testthat::expect_no_match(
      flat_message(cnd),
      "Since condathis 0.2.0",
      fixed = TRUE
    )
  }
  # `channels` given, also with its default value.
  no_hint(create_env(
    "samtools=1.17",
    env_name = "e1",
    channels = "conda-forge",
    verbose = "silent"
  ))
  # bioconda among the channels, by name or by URL.
  no_hint(create_env(
    "samtools=1.17",
    env_name = "e2",
    additional_channels = "bioconda",
    verbose = "silent"
  ))
  no_hint(create_env(
    "samtools=1.17",
    env_name = "e3",
    additional_channels = "https://conda.anaconda.org/bioconda/",
    verbose = "silent"
  ))
  # A spec that names its channel.
  no_hint(create_env("conda-forge::x", env_name = "e4", verbose = "silent"))
  # A spec that the error does not name.
  no_hint(create_env("python", env_name = "e5", verbose = "silent"))
  # An environment file names its own channels.
  env_file <- withr::local_tempfile(
    fileext = ".yml",
    lines = c("dependencies:", "  - samtools=1.17")
  )
  no_hint(create_env(env_file = env_file, env_name = "e6", verbose = "silent"))
})

testthat::test_that("create_env() reads the not-found text of micromamba and rattler only", {
  n_stubs <- 0L
  hint_for <- function(message, stderr = NULL) {
    stub_error <- function(...) {
      rlang::abort(message, class = "stub_solve_error", stderr = stderr)
    }
    n_stubs <<- n_stubs + 1L
    local_env_stub(
      paste0("stub-not-found-text-", n_stubs),
      backend_create_env = stub_error
    )
    cnd <- catch_error(
      create_env("samtools", "zlib", env_name = "t-env", verbose = "silent")
    )
    testthat::expect_s3_class(cnd, "condathis_create_env_failed")
    testthat::expect_s3_class(cnd$parent, "stub_solve_error")
    return(grepl("Since condathis 0.2.0", flat_message(cnd), fixed = TRUE))
  }
  # rattler (resolvo), in the message.
  testthat::expect_true(hint_for(paste0(
    "failed to solve environment: Cannot solve the request because of: ",
    "No candidates were found for samtools *."
  )))
  # micromamba, in the `stderr` field.
  testthat::expect_true(hint_for(
    "solve failed",
    stderr = "samtools =* * does not exist (perhaps a typo or a missing channel)."
  ))
  # A missing dependency is not a missing requested spec.
  testthat::expect_false(hint_for(
    "solve failed",
    stderr = paste0(
      "samtools =* * is not installable because it requires\n",
      "  htslib =* *, which does not exist (perhaps a missing channel)."
    )
  ))
  # Any other error.
  testthat::expect_false(hint_for("boom"))
  testthat::expect_false(hint_for("samtools: download failed"))
})

testthat::test_that("missing_spec_names() reads every not-found spec of a backend error", {
  stderr <- paste0(
    "    \u251c\u2500 Fastp =* * does not exist ",
    "(perhaps a typo or a missing channel);\n",
    "    \u2514\u2500 samtools >=1.2 * does not exist ",
    "(perhaps a typo or a missing channel).\n"
  )
  parent <- rlang::error_cnd(message = "failed", stderr = stderr)
  cnd <- rlang::error_cnd(message = "outer", parent = parent)
  testthat::expect_identical(missing_spec_names(cnd), c("fastp", "samtools"))
  testthat::expect_identical(
    missing_spec_names(rlang::error_cnd(
      message = "No candidates were found for r-base ==9.9."
    )),
    "r-base"
  )
  testthat::expect_identical(
    missing_spec_names(simpleError("boom")),
    character(0L)
  )
})

testthat::test_that("create_env() does not compare virtual package specs", {
  # Regression test: a spec such as "__cuda=12" is never in the package
  # listing, so the identical second call aborted with
  # condathis_create_env_exists.
  stub <- local_env_stub(
    "stub-virtual",
    envs = "cuda-env",
    packages = pkgs_df(
      c("pytorch-gpu", "cuda-version"),
      version = c("2.5.1", "12.6")
    )
  )
  res <- create_env(
    "__cuda=12",
    "pytorch-gpu",
    "cuda-version>=12.4",
    "__glibc>=2.17",
    env_name = "cuda-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)

  # The other specs are still compared.
  cnd <- catch_error(create_env(
    "__cuda=12",
    "zlib",
    env_name = "cuda-env",
    verbose = "silent"
  ))
  testthat::expect_s3_class(cnd, "condathis_create_env_exists")
  message <- flat_message(cnd)
  testthat::expect_match(message, "Not satisfied: \"zlib\".", fixed = TRUE)
  testthat::expect_no_match(message, "__cuda", fixed = TRUE)

  # A new environment: the backend gets the virtual specs.
  create_env("__unix", "zlib", env_name = "new-env", verbose = "silent")
  calls <- stub_calls(stub, "backend_create_env")
  testthat::expect_length(calls, 1L)
  testthat::expect_identical(calls[[1L]]$args$packages, c("__unix", "zlib"))
})

testthat::test_that("check_env_request() leaves out virtual package specs", {
  installed <- pkgs_df("zlib", version = "1.3.1")
  check <- check_env_request(
    installed,
    c("__unix", "__glibc>=2.17", "conda-forge::__cuda=12", "zlib"),
    channels = "conda-forge"
  )
  testthat::expect_true(check$satisfied)
  testthat::expect_identical(check$unsatisfied, character(0L))
  check <- check_env_request(installed, c("__unix", "python"))
  testthat::expect_identical(check$unsatisfied, "python")
  testthat::expect_identical(
    is_virtual_package_spec(c("__cuda=12", "_libgcc_mutex", "zlib", "__UNIX")),
    c(TRUE, FALSE, FALSE, TRUE)
  )
})

testthat::test_that("create_env() names the channel of an installed package outside channels", {
  # An environment that condathis 0.1.4 built with its default channels,
  # c("conda-forge", "bioconda").
  stub <- local_env_stub(
    "stub-other-channel",
    envs = "old-env",
    packages = pkgs_df(
      c("samtools", "htslib"),
      version = "1.17",
      channel = "https://conda.anaconda.org/bioconda"
    )
  )
  cnd <- catch_error(
    create_env("samtools=1.17", env_name = "old-env", verbose = "silent")
  )
  testthat::expect_identical(
    class(cnd),
    c("condathis_create_env_exists", "condathis_error", rlang_tail)
  )
  message <- flat_message(cnd)
  testthat::expect_match(
    message,
    "\"samtools\" is installed from \"bioconda\", which is not in `channels`.",
    fixed = TRUE
  )
  testthat::expect_match(message, "\"bioconda::samtools\"", fixed = TRUE)
  # `overwrite = TRUE` with the same channels would fail, so it is not
  # suggested.
  testthat::expect_no_match(message, "overwrite = TRUE", fixed = TRUE)

  # Another spec that is not satisfied keeps the usual hint.
  message <- flat_message(catch_error(
    create_env("samtools", "zlib", env_name = "old-env", verbose = "silent")
  ))
  testthat::expect_match(
    message,
    "is installed from \"bioconda\"",
    fixed = TRUE
  )
  testthat::expect_match(message, "overwrite = TRUE", fixed = TRUE)

  # A version that the package does not have is not about the channel.
  message <- flat_message(catch_error(
    create_env("samtools=1.18", env_name = "old-env", verbose = "silent")
  ))
  testthat::expect_no_match(message, "is installed from", fixed = TRUE)
  testthat::expect_match(message, "overwrite = TRUE", fixed = TRUE)

  # The channel is still part of the request: with it, the environment is
  # kept.
  res <- create_env(
    "samtools=1.17",
    env_name = "old-env",
    channels = c("conda-forge", "bioconda"),
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("specs_from_other_channels() suggests a spec only for a channel name", {
  installed <- rbind(
    pkgs_df("samtools", version = "1.17", channel = "bioconda"),
    pkgs_df("polyglot", channel = "file:///srv/channels/bioconda"),
    pkgs_df("zlib", channel = "conda-forge")
  )
  check <- check_env_request(
    installed,
    c("samtools>=1", "polyglot", "zlib", "pkgs/main::zlib", "python"),
    channels = "defaults"
  )
  other <- check$other_channels
  testthat::expect_identical(other$spec, c("samtools>=1", "polyglot", "zlib"))
  testthat::expect_identical(other$name, c("samtools", "polyglot", "zlib"))
  testthat::expect_identical(
    other$channel,
    c("bioconda", "/srv/channels/bioconda", "conda-forge")
  )
  testthat::expect_identical(
    other$spec_hint,
    c("bioconda::samtools", NA, "conda-forge::zlib")
  )
  testthat::expect_false(unsatisfied_only_by_channel(check))
  # Without `channels`, a spec without a channel matches any channel.
  testthat::expect_identical(
    nrow(check_env_request(installed, "polyglot")$other_channels),
    0L
  )
})

testthat::test_that("specs_from_other_channels() leaves out packages that pip installed", {
  installed <- rbind(
    pkgs_df("requests", version = "2.32.3", channel = "pypi"),
    pkgs_df("samtools", version = "1.17", channel = "bioconda")
  )
  check <- check_env_request(
    installed,
    c("requests", "samtools"),
    channels = "conda-forge"
  )
  testthat::expect_identical(check$unsatisfied, c("requests", "samtools"))
  testthat::expect_identical(check$other_channels$spec, "samtools")
  testthat::expect_false(unsatisfied_only_by_channel(check))
})

testthat::test_that("create_env() keeps an environment created with a virtual package spec", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  # A virtual package that micromamba defines on this OS.
  virtual <- if (isTRUE(is_windows())) "__win" else "__unix"
  env_name <- "condathis-virtual-spec-env"
  res <- create_env(
    virtual,
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel(),
    verbose = "silent"
  )
  withr::defer(remove_env(env_name, verbose = "silent"))
  testthat::expect_identical(res$status, 0L)
  # The solver got the virtual spec.
  testthat::expect_match(res$cmd, virtual, fixed = TRUE)

  res <- create_env(
    virtual,
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel(),
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$cmd, NA_character_)
  testthat::expect_true(validate_env(
    virtual,
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel()
  ))

  res <- install_packages(
    virtual,
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel(),
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_match(res$cmd, virtual, fixed = TRUE)
})

testthat::test_that("create_env() names the channel an existing environment was built from", {
  # An environment built from a channel that is not requested again, as
  # one that condathis 0.1.4 built from bioconda. A copy of the polyglot
  # channel stands in for bioconda.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  other <- polyglot_channel("bioconda")
  env_name <- "condathis-other-channel-env"
  create_polyglot_env(env_name, channel = other)
  withr::defer(remove_env(env_name, verbose = "silent"))

  # With the default channels: only the listing runs, no solver.
  for (channels in list(NULL, polyglot_channel())) {
    args <- list("polyglot", env_name = env_name, verbose = "silent")
    if (isFALSE(is.null(channels))) {
      args$channels <- channels
    }
    cnd <- catch_error(do.call(create_env, args))
    testthat::expect_s3_class(cnd, "condathis_create_env_exists")
    message <- flat_message(cnd)
    testthat::expect_match(
      message,
      "\"polyglot\" is installed from",
      fixed = TRUE
    )
    testthat::expect_match(message, "bioconda\", which is not in", fixed = TRUE)
    testthat::expect_match(message, "to `channels`.", fixed = TRUE)
    testthat::expect_no_match(message, "overwrite = TRUE", fixed = TRUE)
  }
  testthat::expect_false(validate_env(
    "polyglot",
    env_name = env_name,
    channels = polyglot_channel(),
    error = "continue"
  ))

  res <- create_env(
    "polyglot",
    env_name = env_name,
    channels = c(polyglot_channel(), other),
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$cmd, NA_character_)
})
