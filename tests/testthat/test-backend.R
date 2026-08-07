# A deliberately dumb, directory-existence-as-database fake backend — not a
# `rattlerthis` reimplementation. Its only job is exercising the
# registry/dispatch/resolve_backend() code paths against a genuinely
# independent second backend class, without a compiled Rust toolchain or any
# network access.
new_fake_backend_vtable <- function(root) {
  list(
    backend_create_env = function(
      backend,
      packages = NULL,
      env_file = NULL,
      env_name = "condathis-env",
      channels = NULL,
      channel_priority = NULL,
      additional_channels = NULL,
      platform = NULL,
      overwrite = FALSE,
      verbose = "silent"
    ) {
      fs::dir_create(fs::path(root, "envs", env_name))
      invisible(TRUE)
    },
    backend_install = function(
      backend,
      packages,
      env_name = "condathis-env",
      channels = NULL,
      channel_priority = NULL,
      additional_channels = NULL,
      verbose = "silent"
    ) {
      invisible(TRUE)
    },
    backend_remove_env = function(
      backend,
      env_name = "condathis-env",
      verbose = "silent"
    ) {
      fs::dir_delete(fs::path(root, "envs", env_name))
      invisible(TRUE)
    },
    backend_list_envs = function(backend, verbose = "silent") {
      envs_dir <- fs::path(root, "envs")
      if (isFALSE(fs::dir_exists(envs_dir))) {
        return(character(0L))
      }
      fs::path_file(fs::dir_ls(envs_dir, type = "directory"))
    },
    backend_env_exists = function(backend, env_name, verbose = "silent") {
      fs::dir_exists(fs::path(root, "envs", env_name))
    },
    backend_list_packages = function(
      backend,
      env_name = "condathis-env",
      verbose = "silent"
    ) {
      data.frame(
        name = character(0L),
        version = character(0L),
        build_number = integer(0L),
        channel = character(0L)
      )
    },
    backend_get_env_dir = function(backend, env_name = "condathis-env") {
      fs::path(root, "envs", env_name)
    },
    backend_get_install_dir = function(backend) {
      root
    },
    backend_resolve_run = function(
      backend,
      cmd,
      args = character(0L),
      env_name = "condathis-env",
      verbose = "silent"
    ) {
      list(command = cmd, args = args, env = character(0L), dir = NULL)
    },
    backend_available = function(backend) TRUE
  )
}

#' Register a fake backend for the duration of the calling test, then
#' unregister it (`withr`-scoped, so it never leaks into other test files).
register_fake_backend <- function(name, envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  fs::dir_create(fs::path(root, "envs"))
  fake <- structure(
    new_fake_backend_vtable(root),
    class = c(paste0("condathis_backend_", name), "condathis_backend")
  )
  register_backend(name, fake)
  withr::defer(
    {
      if (exists(name, envir = backend_registry, inherits = FALSE)) {
        rm(list = name, envir = backend_registry)
      }
    },
    envir = envir
  )
  return(invisible(fake))
}

# --- Registry mechanics (no network) --------------------------------------

testthat::test_that("register_backend rejects an incomplete vtable", {
  incomplete <- structure(
    list(backend_create_env = function(...) NULL),
    class = c("condathis_backend_incomplete_test", "condathis_backend")
  )
  cnd <- rlang::catch_cnd(register_backend("incomplete-test", incomplete))
  testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
  testthat::expect_false("incomplete-test" %in% list_registered_backend_names())
})

testthat::test_that("register_backend accepts a complete vtable, and re-registration overwrites cleanly", {
  register_fake_backend("fake-registry-test")
  testthat::expect_true(
    "fake-registry-test" %in% list_registered_backend_names()
  )
  testthat::expect_no_error(register_fake_backend("fake-registry-test"))
  testthat::expect_true(
    "fake-registry-test" %in% list_registered_backend_names()
  )
})

testthat::test_that("get_backend errors clearly for an unregistered name", {
  cnd <- rlang::catch_cnd(get_backend("totally-unregistered-backend"))
  testthat::expect_s3_class(cnd, "condathis_backend_not_registered")
})

# --- method = "native" deprecation alias (no network) ---------------------

testthat::test_that("method = 'native' resolves to 'micromamba'", {
  suppressWarnings({
    testthat::expect_equal(resolve_method_alias("native"), "micromamba")
  })
  testthat::expect_equal(resolve_method_alias("micromamba"), "micromamba")
  testthat::expect_equal(resolve_method_alias("auto"), "auto")
})

testthat::test_that("method = 'native' warns exactly once per session", {
  old_warned <- condathis_native_warned$warned
  withr::defer({
    condathis_native_warned$warned <- old_warned
  })
  condathis_native_warned$warned <- FALSE

  warn_count <- 0
  handler <- function(w) {
    warn_count <<- warn_count + 1
    invokeRestart("muffleWarning")
  }
  withCallingHandlers(
    resolve_method_alias("native"),
    condathis_deprecated_method_native = handler
  )
  withCallingHandlers(
    resolve_method_alias("native"),
    condathis_deprecated_method_native = handler
  )
  testthat::expect_equal(warn_count, 1L)
})

# --- resolve_backend() precedence -----------------------------------------
# These touch a real `env_name`, so `find_owning_backends()` also probes the
# real "micromamba" backend as part of iterating every registered backend —
# needs micromamba installed/network for that first probe.

testthat::test_that("resolve_backend resolves a brand-new environment via an explicit method", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  register_fake_backend("fake-new-env")
  resolved <- resolve_backend(
    env_name = "brand-new-env-explicit",
    method = "fake-new-env",
    mutating = TRUE
  )
  testthat::expect_equal(resolved$name, "fake-new-env")
})

testthat::test_that("resolve_backend resolves a brand-new environment via condathis.backend_priority", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  register_fake_backend("fake-priority")
  withr::local_options(
    condathis.backend_priority = c("fake-priority", "micromamba")
  )
  resolved <- resolve_backend(
    env_name = "brand-new-env-priority",
    method = "auto",
    mutating = TRUE
  )
  testthat::expect_equal(resolved$name, "fake-priority")
})

testthat::test_that("resolve_backend reads the existing owner under method = 'auto'", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  fake <- register_fake_backend("fake-existing-auto")
  backend_create_env(fake, env_name = "existing-env-auto")

  resolved <- resolve_backend(
    env_name = "existing-env-auto",
    method = "auto",
    mutating = FALSE
  )
  testthat::expect_equal(resolved$name, "fake-existing-auto")
})

testthat::test_that("resolve_backend resolves an explicit method matching the actual owner without warning", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  fake <- register_fake_backend("fake-existing-match")
  backend_create_env(fake, env_name = "existing-env-match")

  resolved <- resolve_backend(
    env_name = "existing-env-match",
    method = "fake-existing-match",
    mutating = TRUE
  )
  testthat::expect_equal(resolved$name, "fake-existing-match")
})

# --- Mismatch handling ------------------------------------------------------

testthat::test_that("resolve_backend aborts on a mutating call with a mismatched method", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  fake <- register_fake_backend("fake-mismatch-mutating")
  backend_create_env(fake, env_name = "mismatch-env-mutating")

  cnd <- rlang::catch_cnd(
    resolve_backend(
      env_name = "mismatch-env-mutating",
      method = "micromamba",
      mutating = TRUE
    )
  )
  testthat::expect_s3_class(cnd, "condathis_backend_mismatch")
})

testthat::test_that("resolve_backend warns and uses the actual owner on a read-only mismatched call", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  fake <- register_fake_backend("fake-mismatch-readonly")
  backend_create_env(fake, env_name = "mismatch-env-readonly")

  warned <- FALSE
  resolved <- withCallingHandlers(
    resolve_backend(
      env_name = "mismatch-env-readonly",
      method = "micromamba",
      mutating = FALSE
    ),
    condathis_backend_mismatch_warning = function(w) {
      warned <<- TRUE
      invokeRestart("muffleWarning")
    }
  )
  testthat::expect_true(warned)
  testthat::expect_equal(resolved$name, "fake-mismatch-readonly")
})

# --- Collision handling (decision 12) ---------------------------------------

testthat::test_that("resolve_backend detects a cross-backend collision and asks for disambiguation", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  fake_1 <- register_fake_backend("fake-collision-1")
  fake_2 <- register_fake_backend("fake-collision-2")
  backend_create_env(fake_1, env_name = "collision-env")
  backend_create_env(fake_2, env_name = "collision-env")

  cnd <- rlang::catch_cnd(
    resolve_backend(
      env_name = "collision-env",
      method = "auto",
      mutating = FALSE
    )
  )
  testthat::expect_s3_class(cnd, "condathis_backend_ambiguous_env")

  resolved <- resolve_backend(
    env_name = "collision-env",
    method = "fake-collision-2",
    mutating = FALSE
  )
  testthat::expect_equal(resolved$name, "fake-collision-2")
})

testthat::test_that("env_exists() reduces a cross-backend collision with any(), no error", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  fake_1 <- register_fake_backend("fake-any-1")
  fake_2 <- register_fake_backend("fake-any-2")
  backend_create_env(fake_1, env_name = "any-collision-env")
  backend_create_env(fake_2, env_name = "any-collision-env")

  testthat::expect_true(env_exists("any-collision-env"))
  testthat::expect_false(env_exists("definitely-not-an-env-anywhere"))
})

# --- run_pipeline() layered error = "continue"/"cancel" handling -----------
# These build on the collision handling above, but exercise run_pipeline()'s
# own precreate_envs(), which must translate a resolve_backend() abort into
# its error_var-gated "missing"/fail-fast contract instead of letting it
# escape uncaught.

test_that("run_pipeline degrades an ambiguous-backend collision under error = 'continue', aborts under 'cancel'", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  fake_1 <- register_fake_backend("fake-rp-collision-1")
  fake_2 <- register_fake_backend("fake-rp-collision-2")
  backend_create_env(fake_1, env_name = "rp-collision-env")
  backend_create_env(fake_2, env_name = "rp-collision-env")

  res <- run_pipeline(
    cmds = list(
      c("echo", "hi"),
      c("cat")
    ),
    env_name = "rp-collision-env",
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(127L, 127L))
  testthat::expect_match(
    res$processes[[1]]$stderr,
    "more than one backend"
  )

  testthat::expect_error(
    object = run_pipeline(
      cmds = list(
        c("echo", "hi"),
        c("cat")
      ),
      env_name = "rp-collision-env",
      error = "cancel"
    ),
    class = "condathis_backend_ambiguous_env"
  )
})

test_that("run_pipeline reports an unsupported-backend env distinctly from a genuinely missing one", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  fake <- register_fake_backend("fake-rp-unsupported")
  backend_create_env(fake, env_name = "rp-unsupported-env")

  res <- run_pipeline(
    cmds = list(
      c("echo", "hi"),
      c("cat")
    ),
    env_name = "rp-unsupported-env",
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(127L, 127L))
  testthat::expect_match(
    res$processes[[1]]$stderr,
    "cannot execute through yet"
  )
  testthat::expect_no_match(
    res$processes[[1]]$stderr,
    "does not exist"
  )

  testthat::expect_error(
    object = run_pipeline(
      cmds = list(c("echo", "hi"), c("cat")),
      env_name = "rp-unsupported-env",
      error = "cancel"
    ),
    class = "condathis_pipeline_backend_unsupported"
  )
})

test_that("run_pipeline lets any command's explicit method disambiguate a shared env_name", {
  # Only the FIRST command referencing a given env_name used to be
  # consulted for its `method` — a second command's explicit override was
  # silently dropped. Here the *second* command supplies the explicit
  # method; if it were ignored, resolution would stay ambiguous (`"more
  # than one backend"`) instead of landing on the specific backend
  # (`"cannot execute through yet"`, since it isn't `"micromamba"`).
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  fake_1 <- register_fake_backend("fake-rp-disambig-1")
  fake_2 <- register_fake_backend("fake-rp-disambig-2")
  backend_create_env(fake_1, env_name = "rp-disambig-env")
  backend_create_env(fake_2, env_name = "rp-disambig-env")

  res <- run_pipeline(
    cmds = list(
      c("echo", "hi"),
      list(
        cmd = c("cat"),
        env_name = "rp-disambig-env",
        method = "fake-rp-disambig-2"
      )
    ),
    env_name = "rp-disambig-env",
    error = "continue"
  )
  testthat::expect_match(
    res$processes[[1]]$stderr,
    "cannot execute through yet"
  )
})

# --- Tibble shape (decision 10) ----------------------------------------------

testthat::test_that("get_install_dir()/list_envs() return tibbles, 1 vs 2+ registered backends", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  dirs_one <- get_install_dir(method = "micromamba")
  testthat::expect_s3_class(dirs_one, "data.frame")
  testthat::expect_named(dirs_one, c("backend", "path"))
  testthat::expect_equal(nrow(dirs_one), 1L)

  register_fake_backend("fake-tibble-shape")
  dirs_two <- get_install_dir(method = "auto")
  testthat::expect_named(dirs_two, c("backend", "path"))
  testthat::expect_true(
    all(c("micromamba", "fake-tibble-shape") %in% dirs_two$backend)
  )

  envs_one <- list_envs(method = "micromamba")
  testthat::expect_named(envs_one, c("backend", "env_name", "path"))
})
