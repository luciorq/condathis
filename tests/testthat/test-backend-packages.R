# On-demand loading of the backend packages that condathis knows by name
# (R/backend-packages.R). `load_backend_namespace()` is mocked: setup.R
# makes every package read as not installed, and the tests here replace it
# with a function that registers a stub backend named "rattler", as the
# `.onLoad()` of rattlerthis does. No real package is ever loaded.
#
# On CRAN, of the tests that use a sandbox (with_sandbox_dir()) or other R
# sessions, only the one of `method` naming a known backend runs: each takes
# about a second on Windows, where listing the processes is slow.

# A stub backend named "rattler" with the root that condathis assigns,
# unregistered again, and a mock of `load_backend_namespace()` that
# registers it. `state$loads` counts the calls of the mock. `register =
# FALSE` makes the load succeed without registering.
local_known_rattler <- function(register = TRUE, envir = parent.frame()) {
  reset_known_backend_state()
  reset_warn_once(known_backend_warn_id("rattler"))
  withr::defer(reset_known_backend_state(), envir = envir)
  withr::defer(reset_warn_once(known_backend_warn_id("rattler")), envir = envir)
  stub <- local_stub_backend("rattler", default_root = TRUE, envir = envir)
  unregister_backend("rattler")
  state <- new.env(parent = emptyenv())
  state$loads <- 0L
  state$stub <- stub
  testthat::local_mocked_bindings(
    load_backend_namespace = function(pkg) {
      state$loads <- state$loads + 1L
      if (isTRUE(register)) {
        register_backend("rattler", stub$backend)
      }
      return(TRUE)
    },
    .env = envir
  )
  return(state)
}

# Makes `<backend_root_dir(name)>/envs/<env_name>` a conda prefix.
make_known_env <- function(env_name, name = "rattler") {
  env_dir <- fs::path(backend_root_dir(name), "envs", env_name)
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  fs::file_create(fs::path(env_dir, "conda-meta", "history"))
  return(invisible(env_dir))
}

testthat::test_that("the known backend packages are a table, not dependencies", {
  testthat::expect_identical(
    known_backend_packages,
    c(rattler = "rattlerthis")
  )
  description <- read.dcf(system.file("DESCRIPTION", package = "condathis"))
  testthat::expect_identical(nrow(description), 1L)
  for (field in intersect(
    c("Depends", "Imports", "Suggests", "Enhances", "LinkingTo"),
    colnames(description)
  )) {
    testthat::expect_false(
      grepl("rattlerthis", description[1L, field], fixed = TRUE),
      info = field
    )
  }
})

testthat::test_that("method names a known backend: its package is loaded", {
  with_sandbox_dir({
    state <- local_known_rattler()
    testthat::expect_false("rattler" %in% list_registered_backend_names())
    testthat::expect_identical(validate_method_arg("rattler"), "rattler")
    testthat::expect_true("rattler" %in% list_registered_backend_names())
    testthat::expect_identical(state$loads, 1L)
    # Registered now: not loaded again.
    testthat::expect_identical(
      list_envs(method = "rattler")$env_name,
      character(0L)
    )
    testthat::expect_identical(state$loads, 1L)
  })
})

testthat::test_that("a known backend with environments is loaded for method = 'auto'", {
  testthat::skip_on_cran()
  with_sandbox_dir({
    state <- local_known_rattler()
    make_known_env("rt-env")
    # An owner search.
    resolved <- resolve_backend(env_name = "rt-env", method = "auto")
    testthat::expect_identical(resolved$name, "rattler")
    testthat::expect_identical(state$loads, 1L)
  })
  with_sandbox_dir({
    state <- local_known_rattler()
    make_known_env("rt-env")
    # A query over every backend.
    envs <- list_envs()
    testthat::expect_identical(envs$backend, "rattler")
    testthat::expect_identical(envs$env_name, "rt-env")
    testthat::expect_identical(state$loads, 1L)
  })
  with_sandbox_dir({
    state <- local_known_rattler()
    make_known_env("rt-env")
    testthat::expect_true(env_exists("rt-env"))
    testthat::expect_identical(state$loads, 1L)
  })
  with_sandbox_dir({
    state <- local_known_rattler()
    make_known_env("rt-env")
    testthat::expect_true("rattler" %in% get_install_dir()$backend)
    testthat::expect_identical(state$loads, 1L)
  })
})

testthat::test_that("an empty root of a known backend loads nothing", {
  testthat::skip_on_cran()
  # get_install_dir() creates the root of every registered backend, so the
  # bare root must not load the package in every later session.
  with_sandbox_dir({
    state <- local_known_rattler()
    root <- backend_root_dir("rattler")
    fs::dir_create(fs::path(root, "envs", env_trash_name()))
    invisible(list_envs())
    testthat::expect_false(env_exists("rt-env"))
    invisible(get_install_dir())
    resolve_backend(env_name = "rt-env", method = "auto")
    testthat::expect_identical(state$loads, 0L)
    testthat::expect_false("rattler" %in% list_registered_backend_names())
    # Cache directories that are empty but for a lock file, as a clean of
    # the backend leaves them, load nothing.
    fs::dir_create(fs::path(root, c("pkgs", "repodata_cache")))
    fs::file_create(fs::path(root, "pkgs", ".cache.lock"))
    testthat::expect_identical(
      load_known_backends(caches = TRUE),
      character(0L)
    )
    testthat::expect_identical(state$loads, 0L)
    # A cache in the root loads it only for clean_cache().
    fs::file_create(fs::path(root, "pkgs", "foo-1.0-0.lock"))
    fs::dir_create(fs::path(root, "pkgs", "foo-1.0-0"))
    invisible(list_envs())
    testthat::expect_identical(state$loads, 0L)
    testthat::expect_identical(load_known_backends(caches = TRUE), "rattler")
    testthat::expect_identical(state$loads, 1L)
  })
  with_sandbox_dir({
    state <- local_known_rattler()
    fs::dir_create(fs::path(backend_root_dir("rattler"), "repodata_cache"))
    fs::file_create(fs::path(
      backend_root_dir("rattler"),
      "repodata_cache",
      "abc.json"
    ))
    invisible(suppressMessages(clean_cache(verbose = "silent")))
    testthat::expect_identical(state$loads, 1L)
    testthat::expect_true("rattler" %in% list_registered_backend_names())
  })
})

testthat::test_that("method names a known backend whose package is not installed", {
  reset_known_backend_state()
  withr::defer(reset_known_backend_state())
  # setup.R: every package reads as not installed.
  cnd <- rlang::catch_cnd(validate_method_arg("rattler"), classes = "error")
  testthat::expect_identical(
    class(cnd)[1:5],
    c(
      "condathis_backend_not_installed",
      "condathis_invalid_method",
      "condathis_invalid_method_arg",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Backend rattler needs the rattlerthis package.",
    fixed = TRUE
  )
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Install it.",
    fixed = TRUE
  )
  # Exported functions report it for the user's call.
  cnd <- rlang::catch_cnd(list_envs(method = "rattler"), classes = "error")
  testthat::expect_s3_class(cnd, "condathis_backend_not_installed")
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "list_envs"
  )
  testthat::expect_false("rattler" %in% list_registered_backend_names())
})

testthat::test_that("a known backend package that fails to load is tried once", {
  reset_known_backend_state()
  withr::defer(reset_known_backend_state())
  loads <- 0L
  testthat::local_mocked_bindings(
    load_backend_namespace = function(pkg) {
      loads <<- loads + 1L
      return(structure(
        FALSE,
        condition = simpleError("the shared library could not be loaded")
      ))
    }
  )
  for (i in 1:2) {
    cnd <- rlang::catch_cnd(validate_method_arg("rattler"), classes = "error")
    testthat::expect_identical(
      class(cnd)[1:5],
      c(
        "condathis_backend_load_failed",
        "condathis_invalid_method",
        "condathis_invalid_method_arg",
        "condathis_invalid_arg",
        "condathis_error"
      ),
      info = i
    )
    testthat::expect_match(
      conditionMessage(cnd$parent),
      "shared library",
      fixed = TRUE
    )
  }
  testthat::expect_identical(loads, 1L)
  # A package that is not installed is checked again on every call: it may
  # be installed later in the session.
  reset_known_backend_state()
  testthat::local_mocked_bindings(
    load_backend_namespace = function(pkg) {
      loads <<- loads + 1L
      return(structure(
        FALSE,
        condition = structure(
          class = c("packageNotFoundError", "error", "condition"),
          list(
            message = "there is no package called 'rattlerthis'",
            call = NULL
          )
        )
      ))
    }
  )
  for (i in 1:2) {
    testthat::expect_error(
      validate_method_arg("rattler"),
      class = "condathis_backend_not_installed"
    )
  }
  testthat::expect_identical(loads, 3L)
})

testthat::test_that("a known backend package that does not register is reported", {
  testthat::skip_on_cran()
  with_sandbox_dir({
    state <- local_known_rattler(register = FALSE)
    cnd <- rlang::catch_cnd(validate_method_arg("rattler"), classes = "error")
    testthat::expect_s3_class(cnd, "condathis_backend_load_failed")
    testthat::expect_s3_class(cnd, "condathis_invalid_method")
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "did not register the backend",
      fixed = TRUE
    )
    testthat::expect_error(
      validate_method_arg("rattler"),
      class = "condathis_backend_load_failed"
    )
    testthat::expect_identical(state$loads, 1L)
    # With environments, method = "auto" warns once, and goes on.
    make_known_env("rt-env")
    testthat::expect_warning(
      envs <- list_envs(),
      class = "condathis_backend_load_failed"
    )
    testthat::expect_identical(nrow(envs), 0L)
  })
})

testthat::test_that("a loaded package whose backend was unregistered is not reloaded", {
  reset_known_backend_state()
  withr::defer(reset_known_backend_state())
  loads <- 0L
  testthat::local_mocked_bindings(
    backend_namespace_loaded = function(pkg) TRUE,
    load_backend_namespace = function(pkg) {
      loads <<- loads + 1L
      return(TRUE)
    }
  )
  cnd <- rlang::catch_cnd(validate_method_arg("rattler"), classes = "error")
  testthat::expect_s3_class(cnd, "condathis_backend_load_failed")
  testthat::expect_s3_class(cnd, "condathis_invalid_method_arg")
  msg <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(
    msg,
    "rattlerthis is loaded but backend rattler is not registered; it was unregistered in this session.",
    fixed = TRUE
  )
  testthat::expect_match(msg, "Restart R to use it.", fixed = TRUE)
  testthat::expect_identical(loads, 0L)
})

testthat::test_that("the .onLoad() of a backend package does not load it again", {
  testthat::skip_on_cran()
  with_sandbox_dir({
    state <- local_known_rattler()
    make_known_env("rt-env")
    inner <- list()
    # A backend's .onLoad() that calls condathis functions taking `method`.
    testthat::local_mocked_bindings(
      load_backend_namespace = function(pkg) {
        state$loads <- state$loads + 1L
        inner$envs <<- list_envs()
        inner$cnd <<- rlang::catch_cnd(
          validate_method_arg("rattler"),
          classes = "error"
        )
        register_backend("rattler", state$stub$backend)
        return(TRUE)
      }
    )
    testthat::expect_identical(list_envs()$env_name, "rt-env")
    testthat::expect_identical(state$loads, 1L)
    # Inside, the backend was not registered yet, and nothing recursed.
    testthat::expect_identical(nrow(inner$envs), 0L)
    testthat::expect_s3_class(inner$cnd, "condathis_invalid_method")
    testthat::expect_false(known_backend_state$loading)
  })
})

testthat::test_that("an invalid method names the installed known backends", {
  reset_known_backend_state()
  withr::defer(reset_known_backend_state())
  testthat::local_mocked_bindings(backend_package_installed = function(pkg) {
    identical(pkg, "rattlerthis")
  })
  testthat::expect_identical(installed_known_backend_names(), "rattler")
  cnd <- rlang::catch_cnd(validate_method_arg("rattlr"), classes = "error")
  msg <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(
    msg,
    "Also installed: \"rattler\", loaded on first use.",
    fixed = TRUE
  )
  testthat::expect_match(msg, "Did you mean \"rattler\"?", fixed = TRUE)
  # Not installed: not named.
  testthat::local_mocked_bindings(backend_package_installed = function(pkg) {
    FALSE
  })
  cnd <- rlang::catch_cnd(validate_method_arg("rattlr"), classes = "error")
  testthat::expect_no_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Also installed",
    fixed = TRUE
  )
})

testthat::test_that("an environment of a known backend that is not installed is not given a second owner", {
  testthat::skip_on_cran()
  # Without rattlerthis, create_env("x", method = <another backend>) made a
  # second owner of `<root>/rattler/envs/x`, and once rattlerthis was
  # back every call on `x` aborted as ambiguous.
  reset_known_backend_state()
  reset_warn_once(known_backend_warn_id("rattler"))
  withr::defer(reset_known_backend_state())
  withr::defer(reset_warn_once(known_backend_warn_id("rattler")))
  with_sandbox_dir({
    stub <- local_stub_backend("stub-second-owner")
    env_dir <- make_known_env("shared-env")
    cnd <- rlang::catch_cnd(
      create_env(
        env_name = "shared-env",
        method = "stub-second-owner",
        verbose = "silent"
      ),
      classes = "error"
    )
    testthat::expect_identical(
      class(cnd)[1:3],
      c(
        "condathis_backend_not_installed",
        "condathis_backend_mismatch",
        "condathis_error"
      )
    )
    msg <- cli::ansi_strip(conditionMessage(cnd))
    testthat::expect_match(
      msg,
      "Environment shared-env belongs to backend rattler, whose package rattlerthis is not installed.",
      fixed = TRUE
    )
    testthat::expect_match(msg, "Install rattlerthis, or delete", fixed = TRUE)
    testthat::expect_identical(
      rlang::call_name(conditionCall(cnd)),
      "create_env"
    )
    testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
    for (fn in list(
      function() remove_env("shared-env", method = "micromamba"),
      function() {
        install_packages(
          "pkg-a",
          env_name = "shared-env",
          method = "stub-second-owner"
        )
      }
    )) {
      testthat::expect_error(fn(), class = "condathis_backend_not_installed")
    }
    testthat::expect_true(fs::dir_exists(env_dir))

    # A query warns once per session, and goes on without it.
    testthat::expect_warning(
      path <- get_env_dir("shared-env"),
      class = "condathis_backend_not_installed"
    )
    testthat::expect_false(identical(
      as.character(path),
      as.character(env_dir)
    ))
    testthat::expect_no_warning(get_env_dir("shared-env"))
    reset_warn_once(known_backend_warn_id("rattler"))
    testthat::expect_warning(
      envs <- list_envs(),
      class = "condathis_backend_not_installed"
    )
    testthat::expect_false("shared-env" %in% envs$env_name)
    testthat::expect_no_warning(env_exists("shared-env"))
    testthat::expect_false(env_exists("shared-env"))
  })
})

testthat::test_that("the positional env_name check finds an environment of a known backend that is not loaded", {
  testthat::skip_on_cran()
  # Regression test: abort_on_positional_env_name() probed only the
  # registered backends, before resolve_backend() loaded any known one, so
  # `install_packages("pkga", "foo")` in a fresh session, with "foo" an
  # environment of rattler, went to micromamba as two specs.
  with_sandbox_dir({
    state <- local_known_rattler()
    make_known_env("rt-pos-env")
    testthat::local_mocked_bindings(
      resolve_backend = function(...) stop("The specs must not be used.")
    )
    for (fn in c("create_env", "install_packages")) {
      cnd <- rlang::catch_cnd(
        if (identical(fn, "create_env")) {
          create_env("pkga", "rt-pos-env", verbose = "silent")
        } else {
          install_packages("pkga", "rt-pos-env", verbose = "silent")
        },
        classes = "error"
      )
      testthat::expect_s3_class(
        cnd,
        paste0("condathis_", fn, "_positional_env_name")
      )
    }
    testthat::expect_identical(state$loads, 1L)
  })
  # Not installed: its directory counts too.
  reset_known_backend_state()
  withr::defer(reset_known_backend_state())
  with_sandbox_dir({
    make_known_env("rt-pos-env")
    testthat::local_mocked_bindings(
      resolve_backend = function(...) stop("The specs must not be used.")
    )
    testthat::expect_error(
      install_packages("pkga", "rt-pos-env", verbose = "silent"),
      class = "condathis_install_packages_positional_env_name"
    )
    testthat::expect_error(
      validate_env("pkga", "rt-pos-env"),
      class = "condathis_validate_env_positional_env_name"
    )
  })
})

testthat::test_that("the priority option loads a known backend for a new environment", {
  testthat::skip_on_cran()
  # Regression test: with the package installed but not loaded,
  # `options(condathis.backend_priority = c("rattler", "micromamba"))` was
  # ignored until another call loaded the package, so the backend of a new
  # environment depended on what ran earlier in the session.
  with_sandbox_dir({
    state <- local_known_rattler()
    resolved <- withr::with_options(
      list(condathis.backend_priority = c("rattler", "micromamba")),
      resolve_backend(env_name = "new-env", method = "auto", mutating = TRUE)
    )
    testthat::expect_identical(resolved$name, "rattler")
    testthat::expect_identical(state$loads, 1L)
  })
  # Not named by the option: nothing is loaded.
  with_sandbox_dir({
    state <- local_known_rattler()
    resolved <- resolve_backend(
      env_name = "new-env",
      method = "auto",
      mutating = TRUE
    )
    testthat::expect_identical(resolved$name, "micromamba")
    testthat::expect_identical(state$loads, 0L)
  })
  # A package that cannot be loaded warns once, and the next backend is
  # used.
  with_sandbox_dir({
    state <- local_known_rattler(register = FALSE)
    withr::with_options(
      list(condathis.backend_priority = c("rattler", "micromamba")),
      {
        cnd <- testthat::expect_warning(
          resolved <- resolve_backend(
            env_name = "new-env",
            method = "auto",
            mutating = TRUE
          ),
          class = "condathis_backend_load_failed"
        )
        testthat::expect_identical(resolved$name, "micromamba")
        msg <- cli::ansi_strip(conditionMessage(cnd))
        testthat::expect_match(
          msg,
          "Option `condathis.backend_priority` names backend rattler, but its package rattlerthis loaded without registering it.",
          fixed = TRUE
        )
        testthat::expect_no_warning(
          resolve_backend(
            env_name = "new-env",
            method = "auto",
            mutating = TRUE
          )
        )
      }
    )
  })
})

testthat::test_that("a package that loaded without registering is not called unloadable", {
  testthat::skip_on_cran()
  # Regression test: these messages said that the package "could not be
  # loaded".
  with_sandbox_dir({
    state <- local_known_rattler(register = FALSE)
    env_dir <- make_known_env("rt-noreg-env")
    cnd <- testthat::expect_warning(
      list_envs(),
      class = "condathis_backend_load_failed"
    )
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "but its package rattlerthis loaded without registering it.",
      fixed = TRUE
    )
    cnd <- rlang::catch_cnd(
      create_env(env_name = "rt-noreg-env", verbose = "silent"),
      classes = "error"
    )
    testthat::expect_s3_class(cnd, "condathis_backend_load_failed")
    msg <- cli::ansi_strip(conditionMessage(cnd))
    testthat::expect_match(
      msg,
      "Environment rt-noreg-env belongs to backend rattler, whose package rattlerthis loaded without registering it.",
      fixed = TRUE
    )
    testthat::expect_match(msg, "Update rattlerthis, or delete", fixed = TRUE)
    testthat::expect_no_match(msg, "could not be loaded", fixed = TRUE)
  })
})

testthat::test_that("an invalid method does not offer a known backend that failed to load", {
  # Regression test: after a failed load, the name was still offered as
  # "loaded on first use", and failed again from the recorded failure.
  reset_known_backend_state()
  withr::defer(reset_known_backend_state())
  testthat::local_mocked_bindings(
    backend_package_installed = function(pkg) identical(pkg, "rattlerthis"),
    load_backend_namespace = function(pkg) {
      return(structure(
        FALSE,
        condition = simpleError("the shared library could not be loaded")
      ))
    }
  )
  testthat::expect_identical(installed_known_backend_names(), "rattler")
  testthat::expect_error(
    validate_method_arg("rattler"),
    class = "condathis_backend_load_failed"
  )
  testthat::expect_identical(installed_known_backend_names(), character(0L))
  cnd <- rlang::catch_cnd(validate_method_arg("rattlr"), classes = "error")
  msg <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_no_match(msg, "Also installed", fixed = TRUE)
  testthat::expect_no_match(msg, "Did you mean \"rattler\"", fixed = TRUE)
})

testthat::test_that("the error for a missing environment names a known backend that owns it", {
  testthat::skip_on_cran()
  # Regression test: once the once-per-session warning was used, run()
  # said that the environment does not exist, and create_env() that it
  # belongs to a backend whose package is not installed.
  reset_known_backend_state()
  reset_warn_once(known_backend_warn_id("rattler"))
  withr::defer(reset_known_backend_state())
  withr::defer(reset_warn_once(known_backend_warn_id("rattler")))
  with_sandbox_dir({
    env_dir <- make_known_env("rt-missing-env")
    testthat::expect_warning(
      list_envs(),
      class = "condathis_backend_not_installed"
    )
    cnd <- rlang::catch_cnd(
      run("ls", env_name = "rt-missing-env", verbose = "silent"),
      classes = "error"
    )
    testthat::expect_s3_class(cnd, "condathis_run_env_not_found")
    testthat::expect_s3_class(cnd, "condathis_env_not_found")
    msg <- cli::ansi_strip(conditionMessage(cnd))
    testthat::expect_match(
      msg,
      "Environment rt-missing-env belongs to backend rattler, whose package rattlerthis is not installed.",
      fixed = TRUE
    )
    testthat::expect_match(msg, "Install rattlerthis, or delete", fixed = TRUE)
    testthat::expect_no_match(msg, "does not exist", fixed = TRUE)
    # Another missing environment keeps the usual message.
    cnd <- rlang::catch_cnd(
      run("ls", env_name = "other-missing-env", verbose = "silent"),
      classes = "error"
    )
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "Environment other-missing-env does not exist.",
      fixed = TRUE
    )
  })
})
