# define_platform() decides on Apple Silicon and, on Windows, for a
# backend that solves for win-arm64 only. It asks the backend through
# backend_can_solve() and backend_native_platform(). Most tests below use
# the micromamba backend, whose two functions wrap packages_solve_native()
# and micromamba_native_platform(); the tests at the end use a stub
# backend. The architecture, the solves, the platform of the micromamba
# binary and the Rosetta 2 check are mocked, so these tests run the same
# on every OS and start no process.

# Apple Silicon. Both fallbacks solve the whole request with
# packages_solve_native(), so a `noarch` spec whose dependency has no
# osx-arm64 build falls back too, and so does an env_file.
local_apple_silicon <- function(
  native,
  rosetta_running,
  rosetta,
  envir = parent.frame()
) {
  log <- new.env(parent = emptyenv())
  log$solves <- list()
  log$rosetta_checks <- 0L
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    micromamba_native_platform = function() stop("must not ask on macOS"),
    is_rosetta_running = function() {
      log$rosetta_checks <- log$rosetta_checks + 1L
      return(rosetta_running)
    },
    packages_solve_native = function(
      packages_arg,
      channels,
      channel_priority,
      additional_channels,
      platform,
      verbose
    ) {
      log$solves[[length(log$solves) + 1L]] <- list(
        packages_arg = packages_arg,
        channels = channels,
        channel_priority = channel_priority,
        additional_channels = additional_channels,
        platform = platform,
        verbose = verbose
      )
      answer <- switch(
        platform,
        `osx-arm64` = native,
        `osx-64` = rosetta,
        stop("unexpected platform ", platform)
      )
      # A function is called, so it can fail the test.
      if (is.function(answer)) {
        answer <- answer()
      }
      return(answer)
    },
    .env = envir
  )
  return(log)
}

solve_platforms <- function(log) {
  return(vapply(log$solves, function(s) s$platform, character(1L)))
}

must_not_solve <- function() {
  stop("must not solve for the emulated platform")
}

testthat::test_that("define_platform() uses Rosetta 2 when the request solves only for osx-64", {
  log <- local_apple_silicon(
    native = FALSE,
    rosetta_running = TRUE,
    rosetta = TRUE
  )
  testthat::expect_message(
    res <- define_platform(
      micromamba_backend(),
      c("r-base", "zlib"),
      channels = "conda-forge",
      channel_priority = "flexible",
      additional_channels = "bioconda",
      verbose = "output"
    ),
    regexp = "Rosetta 2"
  )
  testthat::expect_identical(res, "osx-64")
  testthat::expect_identical(solve_platforms(log), c("osx-arm64", "osx-64"))
  # Both solves get the request of the caller.
  for (solve in log$solves) {
    testthat::expect_identical(solve$packages_arg, c("r-base", "zlib"))
    testthat::expect_identical(solve$channels, "conda-forge")
    testthat::expect_identical(solve$channel_priority, "flexible")
    testthat::expect_identical(solve$additional_channels, "bioconda")
  }
  testthat::expect_identical(log$rosetta_checks, 1L)
})

testthat::test_that("define_platform() keeps osx-arm64 when the request solves for it", {
  log <- local_apple_silicon(
    native = TRUE,
    rosetta_running = TRUE,
    rosetta = must_not_solve
  )
  testthat::expect_no_message(
    res <- define_platform(micromamba_backend(), "zlib", verbose = "output")
  )
  testthat::expect_null(res)
  testthat::expect_identical(solve_platforms(log), "osx-arm64")
  testthat::expect_identical(log$rosetta_checks, 0L)
})

testthat::test_that("define_platform() on Apple Silicon solves an env_file as micromamba create gets it", {
  # Regression test: the Rosetta 2 fallback searched the package specs one
  # by one, so an env_file was never checked.
  log <- local_apple_silicon(
    native = FALSE,
    rosetta_running = TRUE,
    rosetta = TRUE
  )
  testthat::expect_identical(
    suppressMessages(define_platform(
      micromamba_backend(),
      NULL,
      env_file = "stat-env.yml"
    )),
    "osx-64"
  )
  for (solve in log$solves) {
    testthat::expect_identical(solve$packages_arg, c("-f", "stat-env.yml"))
  }
  testthat::expect_identical(solve_platforms(log), c("osx-arm64", "osx-64"))
})

testthat::test_that("define_platform() on Apple Silicon does not fall back after a failure that is not about the packages", {
  # `NA` from a solve, such as for a missing channel: the create reports
  # micromamba's own error, and Rosetta 2 is not even checked.
  log <- local_apple_silicon(
    native = NA,
    rosetta_running = TRUE,
    rosetta = must_not_solve
  )
  testthat::expect_no_message(
    res <- define_platform(micromamba_backend(), "zlib", verbose = "output")
  )
  testthat::expect_null(res)
  testthat::expect_identical(solve_platforms(log), "osx-arm64")
  testthat::expect_identical(log$rosetta_checks, 0L)

  log <- local_apple_silicon(
    native = FALSE,
    rosetta_running = TRUE,
    rosetta = NA
  )
  testthat::expect_no_message(
    res <- define_platform(micromamba_backend(), "zlib", verbose = "output")
  )
  testthat::expect_null(res)
  testthat::expect_identical(solve_platforms(log), c("osx-arm64", "osx-64"))

  # As without a fallback: the solver then reports the missing package.
  log <- local_apple_silicon(
    native = FALSE,
    rosetta_running = TRUE,
    rosetta = FALSE
  )
  testthat::expect_no_message(
    res <- define_platform(
      micromamba_backend(),
      "no-such-package",
      verbose = "output"
    )
  )
  testthat::expect_null(res)
  testthat::expect_identical(solve_platforms(log), c("osx-arm64", "osx-64"))
})

testthat::test_that("define_platform() is silent with verbose = 'silent'", {
  # Regression test: the Rosetta 2 messages were printed at every verbose
  # level, also "silent".
  local_apple_silicon(native = FALSE, rosetta_running = TRUE, rosetta = TRUE)
  testthat::expect_no_message(
    res <- define_platform(micromamba_backend(), "pkg", verbose = "silent")
  )
  testthat::expect_identical(res, "osx-64")

  local_apple_silicon(
    native = FALSE,
    rosetta_running = FALSE,
    rosetta = must_not_solve
  )
  testthat::expect_no_message(
    res <- define_platform(micromamba_backend(), "pkg", verbose = "silent")
  )
  testthat::expect_null(res)
})

testthat::test_that("define_platform() says why it cannot use Rosetta 2", {
  log <- local_apple_silicon(
    native = FALSE,
    rosetta_running = FALSE,
    rosetta = must_not_solve
  )
  msgs <- character(0L)
  withCallingHandlers(
    res <- define_platform(micromamba_backend(), "pkg", verbose = "output"),
    message = function(m) {
      msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  testthat::expect_null(res)
  testthat::expect_identical(solve_platforms(log), "osx-arm64")
  text <- paste(msgs, collapse = "\n")
  # Specs that conflict do not solve for any platform either, so the
  # message does not say that a package is missing.
  testthat::expect_match(
    text,
    "The requested packages cannot be installed for \"osx-arm64\".",
    fixed = TRUE
  )
  testthat::expect_match(text, "Rosetta 2", fixed = TRUE)
  # create_env() and install_packages() take the specs in `...`, so the
  # message must not name a `packages` argument.
  testthat::expect_no_match(text, "`packages`", fixed = TRUE)
})

testthat::test_that("define_platform() always solves silently and uses verbose only for its messages", {
  # Regression test: `verbose` went on to the package checks, so a caller
  # that passed its own verbose level to get the Rosetta 2 messages also
  # printed the JSON output of micromamba.
  for (level in c("output", "full", "cmd", "spinner", "silent")) {
    log <- local_apple_silicon(
      native = FALSE,
      rosetta_running = TRUE,
      rosetta = TRUE
    )
    msgs <- character(0L)
    withCallingHandlers(
      res <- define_platform(micromamba_backend(), "pkg", verbose = level),
      message = function(m) {
        msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
        invokeRestart("muffleMessage")
      }
    )
    testthat::expect_identical(res, "osx-64", info = level)
    testthat::expect_identical(
      vapply(log$solves, function(s) s$verbose, character(1L)),
      c("silent", "silent"),
      info = level
    )
    if (identical(level, "silent")) {
      testthat::expect_length(msgs, 0L)
    } else {
      testthat::expect_match(
        paste(msgs, collapse = "\n"),
        "Using Rosetta 2 emulation.",
        fixed = TRUE,
        info = level
      )
    }
  }
})

testthat::test_that("define_platform() keeps a given platform and skips the solve", {
  log <- local_apple_silicon(
    native = function() stop("must not solve"),
    rosetta_running = TRUE,
    rosetta = must_not_solve
  )
  testthat::expect_identical(
    define_platform(micromamba_backend(), "pkg", platform = "osx-arm64"),
    "osx-arm64"
  )
  testthat::expect_identical(
    define_platform(
      micromamba_backend(),
      NULL,
      platform = "osx-64",
      env_file = "env.yml"
    ),
    "osx-64"
  )
  testthat::expect_length(log$solves, 0L)
  testthat::expect_identical(log$rosetta_checks, 0L)
  testthat::local_mocked_bindings(get_sys_arch = function() "Linux-x86_64")
  testthat::expect_null(define_platform(micromamba_backend(), "pkg"))
})

testthat::test_that("define_platform() solves nothing for an empty request", {
  log <- local_apple_silicon(
    native = function() stop("must not solve"),
    rosetta_running = TRUE,
    rosetta = must_not_solve
  )
  testthat::expect_null(define_platform(
    micromamba_backend(),
    NULL,
    verbose = "output"
  ))
  testthat::expect_null(define_platform(
    micromamba_backend(),
    character(0L),
    verbose = "output"
  ))
  testthat::expect_length(log$solves, 0L)
})

testthat::test_that("define_platform() asks for the micromamba platform only on Windows", {
  testthat::local_mocked_bindings(
    micromamba_native_platform = function() stop("must not ask"),
    packages_solve_native = function(...) stop("must not solve"),
    is_rosetta_running = function() stop("must not probe Rosetta 2")
  )
  for (sys_arch in c("Linux-x86_64", "Linux-aarch64", "Darwin-x86_64")) {
    testthat::local_mocked_bindings(get_sys_arch = function() sys_arch)
    testthat::expect_null(
      define_platform(micromamba_backend(), "pkg"),
      info = sys_arch
    )
  }
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    packages_solve_native = function(...) FALSE,
    is_rosetta_running = function() FALSE
  )
  testthat::expect_null(define_platform(micromamba_backend(), "pkg"))
})

# Windows on ARM64. As above, the architecture, the platform of the
# micromamba binary and the solves are mocked. Windows 11 on ARM always has
# x64 emulation, so nothing like is_rosetta_running() is asked.
local_windows_arm64 <- function(
  native,
  emulated,
  binary = "win-arm64",
  sys_arch = "Windows-aarch64",
  envir = parent.frame()
) {
  log <- new.env(parent = emptyenv())
  log$solves <- list()
  log$platform_queries <- 0L
  testthat::local_mocked_bindings(
    get_sys_arch = function() sys_arch,
    is_rosetta_running = function() stop("must not probe Rosetta 2"),
    micromamba_native_platform = function() {
      log$platform_queries <- log$platform_queries + 1L
      return(binary)
    },
    packages_solve_native = function(
      packages_arg,
      channels,
      channel_priority,
      additional_channels,
      platform,
      verbose
    ) {
      log$solves[[length(log$solves) + 1L]] <- list(
        packages_arg = packages_arg,
        channels = channels,
        channel_priority = channel_priority,
        additional_channels = additional_channels,
        platform = platform,
        verbose = verbose
      )
      answer <- switch(
        platform,
        `win-arm64` = native,
        `win-64` = emulated,
        stop("unexpected platform ", platform)
      )
      # A function is called, so it can fail the test.
      if (is.function(answer)) {
        answer <- answer()
      }
      return(answer)
    },
    .env = envir
  )
  return(log)
}

testthat::test_that("define_platform() uses win-64 when the request solves only for win-64", {
  log <- local_windows_arm64(native = FALSE, emulated = TRUE)
  msgs <- character(0L)
  withCallingHandlers(
    res <- define_platform(
      micromamba_backend(),
      c("r-base", "zlib"),
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
  testthat::expect_identical(res, "win-64")
  testthat::expect_identical(solve_platforms(log), c("win-arm64", "win-64"))
  # Both solves get the request of the caller.
  for (solve in log$solves) {
    testthat::expect_identical(solve$packages_arg, c("r-base", "zlib"))
    testthat::expect_identical(solve$channels, "conda-forge")
    testthat::expect_identical(solve$channel_priority, "flexible")
    testthat::expect_identical(solve$additional_channels, "bioconda")
  }
  testthat::expect_length(msgs, 1L)
  testthat::expect_match(
    msgs,
    "Using x64 emulation for \"win-64\" packages.",
    fixed = TRUE
  )
})

testthat::test_that("define_platform() keeps win-arm64 when the request solves for it", {
  log <- local_windows_arm64(native = TRUE, emulated = must_not_solve)
  testthat::expect_no_message(
    res <- define_platform(micromamba_backend(), "zlib", verbose = "output")
  )
  testthat::expect_null(res)
  testthat::expect_identical(solve_platforms(log), "win-arm64")
})

testthat::test_that("define_platform() leaves the platform alone when win-64 does not solve either", {
  # As on Apple Silicon with Rosetta 2: the solver then reports the
  # missing package for the native platform.
  log <- local_windows_arm64(native = FALSE, emulated = FALSE)
  testthat::expect_no_message(
    res <- define_platform(
      micromamba_backend(),
      "no-such-package",
      verbose = "output"
    )
  )
  testthat::expect_null(res)
  testthat::expect_identical(solve_platforms(log), c("win-arm64", "win-64"))
})

testthat::test_that("define_platform() does not fall back after a failure that is not about the packages", {
  # Regression test: a failed `micromamba search` (a mistyped channel, no
  # network) aborted create_env() with a bare "Command failed with status
  # 1". An `NA` solve now leaves the platform alone, so the create reports
  # micromamba's own error.
  log <- local_windows_arm64(native = NA, emulated = must_not_solve)
  testthat::expect_no_message(
    res <- define_platform(micromamba_backend(), "zlib", verbose = "output")
  )
  testthat::expect_null(res)
  testthat::expect_identical(solve_platforms(log), "win-arm64")

  log <- local_windows_arm64(native = FALSE, emulated = NA)
  testthat::expect_no_message(
    res <- define_platform(micromamba_backend(), "zlib", verbose = "output")
  )
  testthat::expect_null(res)
  testthat::expect_identical(solve_platforms(log), c("win-arm64", "win-64"))
})

testthat::test_that("define_platform() on Windows solves silently and uses verbose only for its message", {
  for (level in c("output", "full", "cmd", "spinner", "silent")) {
    log <- local_windows_arm64(native = FALSE, emulated = TRUE)
    msgs <- character(0L)
    withCallingHandlers(
      res <- define_platform(micromamba_backend(), "pkg", verbose = level),
      message = function(m) {
        msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
        invokeRestart("muffleMessage")
      }
    )
    testthat::expect_identical(res, "win-64", info = level)
    testthat::expect_identical(
      vapply(log$solves, function(s) s$verbose, character(1L)),
      c("silent", "silent"),
      info = level
    )
    if (identical(level, "silent")) {
      testthat::expect_length(msgs, 0L)
    } else {
      testthat::expect_match(
        paste(msgs, collapse = "\n"),
        "Using x64 emulation",
        fixed = TRUE,
        info = level
      )
    }
  }
})

testthat::test_that("define_platform() keeps a given platform on Windows and asks nothing", {
  log <- local_windows_arm64(
    native = function() stop("must not solve"),
    emulated = must_not_solve
  )
  for (platform in c("win-arm64", "win-64", "noarch")) {
    testthat::expect_identical(
      define_platform(micromamba_backend(), "pkg", platform = platform),
      platform
    )
  }
  testthat::expect_identical(log$platform_queries, 0L)
  testthat::expect_length(log$solves, 0L)
})

testthat::test_that("define_platform() follows the platform of the micromamba binary, not of R", {
  # Every R of a user shares the managed binary. An x64 R on an ARM64 PC
  # can run the win-arm64 binary that a native ARM64 R installed: it solves
  # for win-arm64 and needs the fallback too.
  log <- local_windows_arm64(
    native = FALSE,
    emulated = TRUE,
    sys_arch = "Windows-x86-64"
  )
  testthat::expect_identical(
    suppressMessages(define_platform(micromamba_backend(), "r-base")),
    "win-64"
  )
  testthat::expect_identical(solve_platforms(log), c("win-arm64", "win-64"))

  # A native ARM64 R with the win-64 binary of an x64 R: that binary
  # already solves for win-64. And a platform that cannot be read.
  for (binary in c("win-64", NA_character_)) {
    log <- local_windows_arm64(
      native = function() stop("must not solve"),
      emulated = must_not_solve,
      binary = binary
    )
    testthat::expect_null(
      define_platform(micromamba_backend(), "r-base"),
      info = binary
    )
    testthat::expect_identical(log$platform_queries, 1L, info = binary)
  }
})

testthat::test_that("define_platform() falls back to win-64 on a new Windows ARM64 machine", {
  # Regression test: only the managed binary was read for the platform of
  # micromamba, and the first create_env() asks before any command installs
  # it, so `r-base` got no win-64 fallback. `micromamba info` asks the
  # binary that native_cmd() runs, which it installs first.
  withr::local_options(condathis.micromamba_path = NULL)
  withr::local_envvar(CONDATHIS_MICROMAMBA_PATH = NA)
  missing_binary <- fs::path(withr::local_tempdir(), "micromamba.exe")
  log <- new.env(parent = emptyenv())
  log$cmds <- character(0L)
  log$solves <- character(0L)
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Windows-aarch64",
    is_rosetta_running = function() stop("must not probe Rosetta 2"),
    micromamba_bin_path = function() missing_binary,
    native_cmd = function(
      conda_cmd,
      conda_args = NULL,
      ...,
      verbose = NULL,
      error = "cancel"
    ) {
      log$cmds <- c(log$cmds, conda_cmd)
      return(list(
        status = 0L,
        stdout = '{"platform": "win-arm64"}',
        stderr = ""
      ))
    },
    packages_solve_native = function(..., platform) {
      log$solves <- c(log$solves, platform)
      return(identical(platform, "win-64"))
    }
  )
  testthat::expect_identical(
    suppressMessages(resolve_create_platform(
      micromamba_backend(),
      packages = "r-base",
      platform = NULL,
      channels = "conda-forge",
      channel_priority = "strict",
      additional_channels = NULL,
      verbose = "output"
    )),
    "win-64"
  )
  testthat::expect_identical(log$cmds, "info")
  testthat::expect_identical(log$solves, c("win-arm64", "win-64"))
})

testthat::test_that("define_platform() on Windows solves an env_file as micromamba create gets it", {
  log <- local_windows_arm64(native = FALSE, emulated = TRUE)
  testthat::expect_identical(
    suppressMessages(define_platform(
      micromamba_backend(),
      NULL,
      env_file = "stat-env.yml"
    )),
    "win-64"
  )
  for (solve in log$solves) {
    testthat::expect_identical(solve$packages_arg, c("-f", "stat-env.yml"))
  }
  testthat::expect_identical(solve_platforms(log), c("win-arm64", "win-64"))
})

testthat::test_that("create_env()'s platform uses the win-64 fallback for specs and env_file", {
  # resolve_create_platform() is where create_env() calls
  # define_platform(), for every backend, as for Rosetta 2. A given
  # `platform` is passed as is, and an empty environment is not solved.
  log <- local_windows_arm64(native = FALSE, emulated = TRUE)
  platform_for <- function(packages, platform = NULL, env_file = NULL) {
    return(suppressMessages(resolve_create_platform(
      micromamba_backend(),
      packages = packages,
      platform = platform,
      channels = "conda-forge",
      channel_priority = "strict",
      additional_channels = NULL,
      verbose = "output",
      env_file = env_file
    )))
  }
  testthat::expect_identical(
    platform_for("r-base"),
    "win-64"
  )
  testthat::expect_identical(
    platform_for(NULL, env_file = "stat-env.yml"),
    "win-64"
  )
  testthat::expect_identical(
    vapply(log$solves, function(s) s$packages_arg[[1L]], character(1L)),
    c("r-base", "r-base", "-f", "-f")
  )

  log$solves <- list()
  testthat::expect_null(platform_for(NULL))
  testthat::expect_identical(
    platform_for(NULL, platform = "win-arm64"),
    "win-arm64"
  )
  testthat::expect_identical(
    platform_for("zlib", platform = "win-arm64"),
    "win-arm64"
  )
  testthat::expect_identical(
    platform_for(NULL, platform = "win-arm64", env_file = "env.yml"),
    "win-arm64"
  )
  testthat::expect_length(log$solves, 0L)
})

testthat::test_that("define_platform() on Windows solves nothing for an empty request", {
  log <- local_windows_arm64(
    native = function() stop("must not solve"),
    emulated = must_not_solve
  )
  testthat::expect_null(define_platform(
    micromamba_backend(),
    NULL,
    verbose = "output"
  ))
  testthat::expect_null(define_platform(
    micromamba_backend(),
    character(0L),
    verbose = "output"
  ))
  testthat::expect_identical(log$platform_queries, 0L)
  testthat::expect_length(log$solves, 0L)
})

# A micromamba environment directory with `conda-meta/history` and one
# package record per platform in `subdirs`.
local_env_dir_with_records <- function(
  subdirs = character(0L),
  envir = parent.frame()
) {
  env_dir <- fs::path(withr::local_tempdir(.local_envir = envir), "env")
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  fs::file_create(fs::path(env_dir, "conda-meta", "history"))
  for (i in seq_along(subdirs)) {
    jsonlite::write_json(
      list(name = paste0("pkg", i), version = "1.0", subdir = subdirs[[i]]),
      fs::path(env_dir, "conda-meta", paste0("pkg", i, "-1.0-0.json")),
      auto_unbox = TRUE
    )
  }
  return(env_dir)
}

testthat::test_that("install_packages()'s platform uses both fallbacks for an empty environment", {
  # resolve_install_platform() is where install_packages() calls
  # define_platform(), for every backend: only for an environment
  # with neither a recorded platform nor packages other than `noarch` ones,
  # such as the empty "condathis-env" that install_packages() creates.
  platform_for <- function(env_dir, packages = c("r-base", "zlib")) {
    return(suppressMessages(resolve_install_platform(
      micromamba_backend(),
      env_dir = env_dir,
      packages = packages,
      channels = "conda-forge",
      channel_priority = "flexible",
      additional_channels = "bioconda",
      verbose = "output"
    )))
  }
  empty_env <- local_env_dir_with_records()
  check_fallback <- function(log, platforms) {
    emulated <- platforms[[2L]]
    testthat::expect_identical(
      platform_for(empty_env),
      emulated
    )
    testthat::expect_identical(solve_platforms(log), platforms)
    # Both solves get the install request.
    for (solve in log$solves) {
      testthat::expect_identical(solve$packages_arg, c("r-base", "zlib"))
      testthat::expect_identical(solve$channels, "conda-forge")
      testthat::expect_identical(solve$channel_priority, "flexible")
      testthat::expect_identical(solve$additional_channels, "bioconda")
      testthat::expect_identical(solve$verbose, "silent")
    }

    # After the first install, the records give the platform: nothing is
    # solved again. Records of several platforms, or one that cannot be
    # read, leave the platform to micromamba, with no fallback either.
    log$solves <- list()
    testthat::expect_identical(
      platform_for(local_env_dir_with_records(c(emulated, "noarch"))),
      emulated
    )
    testthat::expect_null(
      platform_for(local_env_dir_with_records(c(emulated, "linux-64")))
    )
    broken_env <- local_env_dir_with_records("noarch")
    writeLines("{ not json", fs::path(broken_env, "conda-meta", "x-1-0.json"))
    testthat::expect_null(platform_for(broken_env))
    testthat::expect_length(log$solves, 0L)

    # Regression test: only `noarch` packages, such as `tzdata`, work on
    # every platform, but they kept the next install from the fallback.
    testthat::expect_identical(
      platform_for(local_env_dir_with_records(c("noarch", "noarch"))),
      emulated
    )
    testthat::expect_identical(solve_platforms(log), platforms)
  }
  log <- local_windows_arm64(native = FALSE, emulated = TRUE)
  check_fallback(log, platforms = c("win-arm64", "win-64"))
  log <- local_apple_silicon(
    native = FALSE,
    rosetta_running = TRUE,
    rosetta = TRUE
  )
  check_fallback(log, platforms = c("osx-arm64", "osx-64"))
})

testthat::test_that("install_packages()'s platform reads no package records where no fallback exists", {
  # Regression test: the records of every environment without a recorded
  # platform were read for every install, on every OS, although only Apple
  # Silicon and Windows have an emulation fallback.
  testthat::local_mocked_bindings(
    read_conda_package_records = function(...) stop("must not read"),
    env_has_platform_packages = function(...) stop("must not read"),
    define_platform = function(...) stop("must not fall back"),
    micromamba_native_platform = function(...) stop("must not ask")
  )
  platform_for <- function(env_dir) {
    return(resolve_install_platform(
      micromamba_backend(),
      env_dir = env_dir,
      packages = "zlib",
      channels = "conda-forge",
      channel_priority = "strict",
      additional_channels = NULL,
      verbose = "output"
    ))
  }
  for (sys_arch in c("Linux-x86_64", "Linux-aarch64", "Darwin-x86_64")) {
    testthat::local_mocked_bindings(get_sys_arch = function() sys_arch)
    testthat::expect_false(has_platform_fallback(), info = sys_arch)
    testthat::expect_null(
      platform_for(local_env_dir_with_records()),
      info = sys_arch
    )
    env_dir <- local_env_dir_with_records("osx-64")
    testthat::expect_null(platform_for(env_dir), info = sys_arch)
    # The platform that `create_env(platform = )` records is still read.
    cat("platform: linux-aarch64", file = fs::path(env_dir, ".mambarc"))
    testthat::expect_identical(
      platform_for(env_dir),
      "linux-aarch64",
      info = sys_arch
    )
    # So is the platform of the marker, which comes first.
    write_backend_marker(env_dir, "micromamba", platform = "osx-64")
    testthat::expect_identical(
      platform_for(env_dir),
      "osx-64",
      info = sys_arch
    )
  }
  for (sys_arch in c("Darwin-arm64", "Windows-x86-64", "Windows-aarch64")) {
    testthat::local_mocked_bindings(get_sys_arch = function() sys_arch)
    testthat::expect_true(has_platform_fallback(), info = sys_arch)
  }
})

# A stub backend (helper-stub-backend.R) whose backend_can_solve() answers
# from `solves` (a named logical vector: platform -> answer) and whose
# backend_native_platform() gives `native`. Both record their calls.
local_platform_stub <- function(
  name,
  solves = logical(0L),
  native = NA_character_,
  envir = parent.frame()
) {
  stub <- local_stub_backend(
    name,
    backend_can_solve = function(backend, ..., platform) {
      answer <- solves[platform]
      if (is.na(names(answer))) {
        stop("unexpected platform ", platform)
      }
      return(unname(answer))
    },
    backend_native_platform = function(backend) native,
    envir = envir
  )
  return(stub)
}

stub_solve_platforms <- function(stub) {
  return(vapply(
    stub_calls(stub, "backend_can_solve"),
    function(call) call$args$platform,
    character(1L)
  ))
}

testthat::test_that("define_platform() asks backend_can_solve() of any backend on Apple Silicon", {
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    is_rosetta_running = function() TRUE
  )
  stub <- local_platform_stub(
    "stub-platform-mac",
    solves = c(`osx-arm64` = FALSE, `osx-64` = TRUE)
  )
  testthat::expect_message(
    res <- define_platform(
      stub$backend,
      c("r-base", "zlib"),
      channels = "conda-forge",
      channel_priority = "flexible",
      additional_channels = "bioconda",
      verbose = "output"
    ),
    regexp = "Using Rosetta 2 emulation."
  )
  testthat::expect_identical(res, "osx-64")
  testthat::expect_identical(
    stub_solve_platforms(stub),
    c("osx-arm64", "osx-64")
  )
  # The whole request, by name.
  args <- stub_calls(stub, "backend_can_solve")[[1L]]$args
  testthat::expect_identical(args$packages, c("r-base", "zlib"))
  testthat::expect_null(args$env_file)
  testthat::expect_identical(args$channels, "conda-forge")
  testthat::expect_identical(args$channel_priority, "flexible")
  testthat::expect_identical(args$additional_channels, "bioconda")
  # The native platform is not asked on macOS.
  testthat::expect_length(stub_calls(stub, "backend_native_platform"), 0L)

  # An env_file is passed as is: the backend reads it.
  stub <- local_platform_stub(
    "stub-platform-mac-file",
    solves = c(`osx-arm64` = FALSE, `osx-64` = TRUE)
  )
  testthat::expect_identical(
    suppressMessages(define_platform(
      stub$backend,
      NULL,
      env_file = "stat-env.yml"
    )),
    "osx-64"
  )
  args <- stub_calls(stub, "backend_can_solve")[[1L]]$args
  testthat::expect_null(args$packages)
  testthat::expect_identical(args$env_file, "stat-env.yml")
})

testthat::test_that("define_platform() asks the native platform of any backend on Windows", {
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Windows-x86-64",
    is_rosetta_running = function() stop("must not probe Rosetta 2")
  )
  stub <- local_platform_stub(
    "stub-platform-win",
    solves = c(`win-arm64` = FALSE, `win-64` = TRUE),
    native = "win-arm64"
  )
  msgs <- character(0L)
  withCallingHandlers(
    res <- define_platform(stub$backend, "r-base", verbose = "output"),
    message = function(m) {
      msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  testthat::expect_identical(res, "win-64")
  testthat::expect_identical(
    stub_solve_platforms(stub),
    c("win-arm64", "win-64")
  )
  testthat::expect_length(msgs, 1L)
  testthat::expect_match(
    msgs,
    "Using x64 emulation for \"win-64\" packages.",
    fixed = TRUE
  )
  testthat::expect_length(stub_calls(stub, "backend_native_platform"), 1L)

  # A backend that solves for win-64 already needs no fallback.
  stub <- local_platform_stub(
    "stub-platform-win64",
    solves = logical(0L),
    native = "win-64"
  )
  testthat::expect_null(define_platform(stub$backend, "r-base"))
  testthat::expect_length(stub_calls(stub, "backend_can_solve"), 0L)
})

testthat::test_that("define_platform() never falls back with the defaults of a backend", {
  # A backend without backend_can_solve() and backend_native_platform():
  # both defaults give `NA`, so the backend solves natively and reports its
  # own error.
  stub <- local_stub_backend(
    "stub-platform-defaults",
    backend_can_solve = NULL,
    backend_native_platform = NULL
  )
  for (sys_arch in c("Darwin-arm64", "Windows-aarch64", "Linux-x86_64")) {
    testthat::local_mocked_bindings(
      get_sys_arch = function() sys_arch,
      is_rosetta_running = function() TRUE
    )
    testthat::expect_no_message(
      res <- define_platform(stub$backend, "r-base", verbose = "output")
    )
    testthat::expect_null(res)
  }
  # A given platform is used as is.
  testthat::expect_identical(
    define_platform(stub$backend, "r-base", platform = "osx-64"),
    "osx-64"
  )
})

testthat::test_that("define_platform() reads a failing probe of a backend as no fallback", {
  # An error from backend_can_solve() or backend_native_platform() counts
  # as `NA`: a broken probe never stops a create.
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    is_rosetta_running = function() TRUE
  )
  stub <- local_stub_backend(
    "stub-platform-broken",
    backend_can_solve = function(...) stop("no network"),
    backend_native_platform = function(...) stop("no binary")
  )
  testthat::expect_null(define_platform(stub$backend, "r-base"))
  testthat::local_mocked_bindings(get_sys_arch = function() "Windows-aarch64")
  testthat::expect_null(define_platform(stub$backend, "r-base"))

  # A value that breaks the contract aborts, naming the backend.
  stub <- local_stub_backend(
    "stub-platform-invalid",
    backend_can_solve = function(...) "yes"
  )
  testthat::local_mocked_bindings(get_sys_arch = function() "Darwin-arm64")
  cnd <- rlang::catch_cnd(
    define_platform(stub$backend, "r-base"),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "stub-platform-invalid",
    fixed = TRUE
  )
})

testthat::test_that("a failed download of micromamba in a platform probe is raised at once", {
  # Regression test: the probes of the micromamba backend install
  # micromamba, as the create that follows would. A failed download there
  # counted as "cannot tell", so the create downloaded micromamba a second
  # time, and waited for every mirror again.
  install_failure <- function(...) {
    condathis_abort(
      "Every download mirror was tried.",
      class = c(
        "condathis_install_micromamba_download_failed",
        "condathis_install_error_missing_bzip2"
      )
    )
  }
  stub <- local_stub_backend(
    "stub-platform-download",
    backend_can_solve = install_failure,
    backend_native_platform = install_failure
  )
  for (sys_arch in c("Darwin-arm64", "Windows-aarch64")) {
    testthat::local_mocked_bindings(
      get_sys_arch = function() sys_arch,
      is_rosetta_running = function() TRUE,
      is_windows = function() identical(sys_arch, "Windows-aarch64")
    )
    testthat::expect_error(
      define_platform(stub$backend, "r-base"),
      class = "condathis_install_micromamba_download_failed"
    )
  }

  # Through create_env() with the micromamba backend: one download, and
  # the classes of a failed create, as when micromamba's own create chose
  # the platform.
  condathis::with_sandbox_dir({
    installs <- 0L
    testthat::local_mocked_bindings(
      get_sys_arch = function() "Darwin-arm64",
      is_rosetta_running = function() TRUE,
      get_best_micromamba_path = function() NULL,
      install_micromamba = function(...) {
        installs <<- installs + 1L
        install_failure()
      }
    )
    cnd <- rlang::catch_cnd(
      create_env(
        "r-base",
        env_name = "download-env",
        method = "micromamba",
        verbose = "silent"
      ),
      classes = "error"
    )
    testthat::expect_identical(installs, 1L)
    testthat::expect_identical(
      class(cnd)[1:3],
      c(
        "condathis_create_env_failed",
        "condathis_backend_error",
        "condathis_install_micromamba_download_failed"
      )
    )
    testthat::expect_s3_class(
      cnd$parent,
      "condathis_install_micromamba_download_failed"
    )
    testthat::expect_false(
      fs::dir_exists(fs::path(get_condathis_path(), "envs", "download-env"))
    )
  })
})

testthat::test_that("env_platform() reads the platform that micromamba create records", {
  env_dir <- withr::local_tempdir()
  testthat::expect_null(env_platform(env_dir))
  rc_path <- fs::path(env_dir, ".mambarc")
  # As micromamba writes it: one line, without a final newline.
  cat("platform: win-64", file = rc_path)
  testthat::expect_identical(env_platform(env_dir), "win-64")
  writeLines(c("channels:", "  - conda-forge", "platform: 'osx-64'  "), rc_path)
  testthat::expect_identical(env_platform(env_dir), "osx-64")
  # Not a top-level `platform` key.
  writeLines(c("# platform: win-64", "  platform: win-64"), rc_path)
  testthat::expect_null(env_platform(env_dir))
})

testthat::test_that("env_platform() reads the platform of the backend marker first", {
  # condathis records the platform of a new environment in its marker, for
  # every backend; micromamba also writes it to the `.mambarc`.
  env_dir <- withr::local_tempdir()
  write_backend_marker(env_dir, "stub-backend")
  testthat::expect_null(env_platform(env_dir))
  testthat::expect_null(env_platform(env_dir, read_records = FALSE))
  write_backend_marker(env_dir, "stub-backend", platform = "osx-64")
  testthat::expect_identical(env_platform(env_dir), "osx-64")
  # Also where no fallback exists: the marker is not a package record.
  testthat::expect_identical(
    env_platform(env_dir, read_records = FALSE),
    "osx-64"
  )
  cat("platform: win-64", file = fs::path(env_dir, ".mambarc"))
  testthat::expect_identical(env_platform(env_dir), "osx-64")

  # A marker that cannot be read, or with a platform that condathis does
  # not know, is passed over.
  marker_path <- fs::path(env_dir, ".condathis", "backend.json")
  for (text in c(
    "{ not json",
    "[1, 2]",
    '{"backend": "x", "platform": "Linux-64"}',
    '{"backend": "x", "platform": ["osx-64", "win-64"]}',
    '{"backend": "x", "platform": null}'
  )) {
    writeLines(text, marker_path)
    testthat::expect_null(read_backend_marker_platform(env_dir), info = text)
    testthat::expect_identical(env_platform(env_dir), "win-64", info = text)
  }
})

testthat::test_that("env_platform() falls back to the platform of the package records", {
  # An environment without a recorded platform, created by an older
  # condathis, by another tool, or by install_packages() into an empty
  # environment: the `subdir` of its records, without `noarch`.
  env_dir <- withr::local_tempdir()
  meta_dir <- fs::path(env_dir, "conda-meta")
  fs::dir_create(meta_dir)
  fs::file_create(fs::path(meta_dir, "history"))
  write_record <- function(name, subdir = NULL) {
    record <- list(name = name, version = "1.0", build = "0")
    record[["subdir"]] <- subdir
    jsonlite::write_json(
      record,
      fs::path(meta_dir, paste0(name, "-1.0-0.json")),
      auto_unbox = TRUE
    )
  }
  testthat::expect_null(env_platform(env_dir))
  testthat::expect_false(env_has_platform_packages(env_dir))

  # Only `noarch` packages work on any platform.
  write_record("tzdata", subdir = "noarch")
  testthat::expect_null(env_platform(env_dir))
  testthat::expect_false(env_has_platform_packages(env_dir))

  write_record("zlib", subdir = "osx-64")
  write_record("zstd", subdir = "osx-64")
  testthat::expect_identical(env_platform(env_dir), "osx-64")
  testthat::expect_true(env_has_platform_packages(env_dir))
  # Where no emulation fallback exists, only the marker and the `.mambarc`
  # are read.
  testthat::expect_null(env_platform(env_dir, read_records = FALSE))

  # A record that cannot be read, or that has no `subdir`, is skipped.
  writeLines("{ not json", fs::path(meta_dir, "broken-1.0-0.json"))
  writeLines("[1, 2]", fs::path(meta_dir, "array-1.0-0.json"))
  write_record("nosubdir")
  testthat::expect_identical(env_platform(env_dir), "osx-64")

  # The recorded platform comes first.
  cat("platform: win-64", file = fs::path(env_dir, ".mambarc"))
  testthat::expect_identical(env_platform(env_dir), "win-64")
  writeLines("channels: []", fs::path(env_dir, ".mambarc"))
  testthat::expect_identical(env_platform(env_dir), "osx-64")

  # Packages of two platforms: no guess.
  write_record("bzip2", subdir = "linux-64")
  testthat::expect_null(env_platform(env_dir))

  # A record that cannot be read, or that has no `subdir`, may be of any
  # platform.
  for (name in c("bzip2", "zlib", "zstd")) {
    fs::file_delete(fs::path(meta_dir, paste0(name, "-1.0-0.json")))
  }
  testthat::expect_true(env_has_platform_packages(env_dir))
  fs::file_delete(fs::path(
    meta_dir,
    c("broken-1.0-0.json", "array-1.0-0.json")
  ))
  testthat::expect_true(env_has_platform_packages(env_dir))
  fs::file_delete(fs::path(meta_dir, "nosubdir-1.0-0.json"))
  testthat::expect_false(env_has_platform_packages(env_dir))

  # Not an environment: no `conda-meta/history`.
  fs::file_delete(fs::path(meta_dir, "history"))
  testthat::expect_null(env_platform(env_dir))
  testthat::expect_null(env_platform(fs::path(env_dir, "missing")))
  testthat::expect_false(
    env_has_platform_packages(fs::path(env_dir, "missing"))
  )
})

testthat::test_that("resolve_install_platform() solves nothing for an environment that does not exist", {
  # Reached only when the existence check failed: the backend then reports
  # the missing environment, as before.
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    define_platform = function(...) stop("must not fall back")
  )
  testthat::expect_null(resolve_install_platform(
    micromamba_backend(),
    env_dir = fs::path(withr::local_tempdir(), "missing-env"),
    packages = "zlib",
    channels = "conda-forge",
    channel_priority = "strict",
    additional_channels = NULL
  ))
})
