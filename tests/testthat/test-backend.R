# A deliberately dumb, directory-existence-as-database fake backend - not a
# `rattlerthis` reimplementation. Its only job is exercising the
# registry/dispatch/resolve_backend() code paths against a genuinely
# independent second backend class, without a compiled Rust toolchain or any
# network access. Its signatures are the contract signatures of
# ?register_backend, defaults included.
new_fake_backend_vtable <- function(root) {
  list(
    backend_create_env = function(
      backend,
      packages = NULL,
      env_file = NULL,
      env_name = "condathis-env",
      channels = "conda-forge",
      channel_priority = c("strict", "flexible", "disabled"),
      additional_channels = NULL,
      platform = NULL,
      overwrite = FALSE,
      verbose = c("output", "silent", "cmd", "spinner", "full")
    ) {
      fs::dir_create(fs::path(root, "envs", env_name))
      invisible(TRUE)
    },
    backend_install = function(
      backend,
      packages,
      env_name = "condathis-env",
      channels = "conda-forge",
      channel_priority = c("strict", "flexible", "disabled"),
      additional_channels = NULL,
      platform = NULL,
      verbose = c("output", "silent", "cmd", "spinner", "full")
    ) {
      invisible(TRUE)
    },
    backend_remove_env = function(
      backend,
      env_name = "condathis-env",
      verbose = c("output", "silent", "cmd", "spinner", "full")
    ) {
      fs::dir_delete(fs::path(root, "envs", env_name))
      invisible(TRUE)
    },
    backend_list_envs = function(backend, verbose = "silent") {
      envs_dir <- fs::path(root, "envs")
      if (isFALSE(fs::dir_exists(envs_dir))) {
        return(character(0L))
      }
      as.character(fs::path_file(fs::dir_ls(envs_dir, type = "directory")))
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
        build_string = character(0L),
        channel = character(0L),
        platform = character(0L),
        stringsAsFactors = FALSE
      )
    },
    backend_get_env_dir = function(backend, env_name = "condathis-env") {
      fs::path(fs::path_real(root), "envs", env_name)
    },
    backend_get_install_dir = function(backend) {
      fs::path_real(root)
    },
    backend_resolve_run = function(
      backend,
      cmd,
      args = character(0L),
      env_name = "condathis-env",
      verbose = "silent",
      base_env = NULL
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
      unregister_backend(name)
    },
    envir = envir
  )
  return(invisible(fake))
}

# A classed backend object from `new_fake_backend_vtable()`, not registered.
new_fake_backend <- function(class_name, envir = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = envir)
  fs::dir_create(fs::path(root, "envs"))
  return(structure(
    new_fake_backend_vtable(root),
    class = c(class_name, "condathis_backend")
  ))
}

# --- Registry mechanics (no network) --------------------------------------

testthat::test_that("register_backend rejects an incomplete vtable", {
  incomplete <- structure(
    list(backend_create_env = function(...) NULL),
    class = c("condathis_backend_incomplete_test", "condathis_backend")
  )
  cnd <- rlang::catch_cnd(register_backend("incomplete-test", incomplete))
  testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
  testthat::expect_s3_class(cnd, "condathis_error")
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
  testthat::expect_s3_class(cnd, "condathis_error")
})

testthat::test_that("unregister_backend removes the registry entry and its S3 methods", {
  root <- withr::local_tempdir()
  fs::dir_create(fs::path(root, "envs"))
  fake <- structure(
    new_fake_backend_vtable(root),
    class = c("condathis_backend_unreg_test", "condathis_backend")
  )
  register_backend("unreg-test", fake)
  testthat::expect_true("unreg-test" %in% list_registered_backend_names())

  s3_table <- asNamespace("condathis")[[".__S3MethodsTable__."]]
  testthat::expect_true(exists(
    "backend_env_exists.condathis_backend_unreg_test",
    envir = s3_table,
    inherits = FALSE
  ))

  testthat::expect_true(unregister_backend("unreg-test"))
  testthat::expect_false("unreg-test" %in% list_registered_backend_names())
  testthat::expect_false(exists(
    "backend_env_exists.condathis_backend_unreg_test",
    envir = s3_table,
    inherits = FALSE
  ))
})

testthat::test_that("unregister_backend is a silent no-op for an unregistered name", {
  testthat::expect_no_error({
    result <- unregister_backend("never-was-registered-xyz")
    testthat::expect_false(result)
  })
})

testthat::test_that("unregister_backend validates its name argument", {
  testthat::expect_error(
    unregister_backend(NA),
    class = "condathis_backend_invalid_name"
  )
  testthat::expect_error(
    unregister_backend(c("a", "b")),
    class = "condathis_backend_invalid_name"
  )
})

testthat::test_that("register_backend and unregister_backend reject malformed names", {
  testthat::skip_on_cran()
  # Regression test: only "a single, non-missing string" was checked, so
  # "", "a b" or a name with a path separator became a `method` value.
  fake <- new_fake_backend("condathis_backend_bad_name_test")
  # Also names that are not the same directory on every OS: Windows drops
  # a final `.`, and opens a device for `nul` or `com1`, with or without
  # an extension.
  bad_names <- list(
    "",
    "a b",
    "1abc",
    "-x",
    "a/b",
    "a:b",
    NA_character_,
    1L,
    "foo.",
    "foo..",
    "nul",
    "NUL",
    "con",
    "aux.backend",
    "com1",
    "LPT9.x"
  )
  for (name in bad_names) {
    cnd <- rlang::catch_cnd(register_backend(name, fake), classes = "error")
    testthat::expect_identical(
      class(cnd)[1:3],
      c(
        "condathis_backend_invalid_name",
        "condathis_invalid_arg",
        "condathis_error"
      ),
      info = deparse(name)
    )
    cnd <- rlang::catch_cnd(unregister_backend(name), classes = "error")
    testthat::expect_identical(
      class(cnd)[1:3],
      c(
        "condathis_backend_invalid_name",
        "condathis_invalid_arg",
        "condathis_error"
      ),
      info = deparse(name)
    )
  }
  # The rules allow these.
  for (name in c("a", "my.backend", "my_backend-2", "Rattle", "console")) {
    register_backend(name, fake)
    testthat::expect_true(name %in% list_registered_backend_names())
    testthat::expect_true(unregister_backend(name))
  }
})

testthat::test_that("register_backend and unregister_backend refuse reserved names", {
  # Regression test: register_backend("auto", ...) succeeded, and
  # unregister_backend("micromamba") left no backend registered at all.
  fake <- new_fake_backend("condathis_backend_reserved_test")
  for (name in c("auto", "native", "micromamba")) {
    cnd <- rlang::catch_cnd(register_backend(name, fake), classes = "error")
    testthat::expect_identical(
      class(cnd)[1:4],
      c(
        "condathis_backend_reserved_name",
        "condathis_backend_invalid_name",
        "condathis_invalid_arg",
        "condathis_error"
      ),
      info = name
    )
    testthat::expect_error(
      unregister_backend(name),
      class = "condathis_backend_reserved_name"
    )
  }
  testthat::expect_false("auto" %in% list_registered_backend_names())
  testthat::expect_true("micromamba" %in% list_registered_backend_names())
  # The built-in backend still works.
  testthat::expect_identical(
    resolve_backend(method = "micromamba")$name,
    "micromamba"
  )
})

testthat::test_that("the entries of the condathis root are reserved names, in any case", {
  testthat::skip_on_cran()
  # The root of a backend is `<condathis root>/<name>`: a backend named
  # "envs" or "pkgs" would get the directories of micromamba.
  fake <- new_fake_backend("condathis_backend_root_entry_test")
  for (name in c(
    "envs",
    "pkgs",
    "micromamba",
    "condabin",
    "Scripts",
    "condathis-micromamba.yaml",
    "cache",
    "home",
    "channels",
    "locks",
    "Locks",
    "tmp",
    "bin",
    "lib",
    "etc",
    "conda-meta",
    "Envs",
    "PKGS",
    "MicroMamba",
    "CondaBin",
    "scripts",
    "Auto",
    "NATIVE"
  )) {
    cnd <- rlang::catch_cnd(register_backend(name, fake), classes = "error")
    testthat::expect_identical(
      class(cnd)[1:4],
      c(
        "condathis_backend_reserved_name",
        "condathis_backend_invalid_name",
        "condathis_invalid_arg",
        "condathis_error"
      ),
      info = name
    )
    testthat::expect_false(
      name %in% setdiff(list_registered_backend_names(), "micromamba")
    )
    testthat::expect_error(
      unregister_backend(name),
      class = "condathis_backend_reserved_name"
    )
  }
  cnd <- rlang::catch_cnd(register_backend("Envs", fake), classes = "error")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "entries there",
    fixed = TRUE
  )
})

testthat::test_that("a name that differs only in case from another backend name is refused", {
  # Regression test: "abc" and "ABC", or a third-party "Rattler" next to the
  # known "rattler", both registered. On macOS and Windows their roots are
  # one directory, so both backends owned every environment in it.
  fake_a <- new_fake_backend("condathis_backend_case_a_test")
  fake_b <- new_fake_backend("condathis_backend_case_b_test")
  register_backend("case-test", fake_a)
  withr::defer(unregister_backend("case-test"))
  for (name in c("Case-Test", "CASE-TEST", "Rattler", "RATTLER")) {
    cnd <- rlang::catch_cnd(register_backend(name, fake_b), classes = "error")
    testthat::expect_identical(
      class(cnd)[1:4],
      c(
        "condathis_backend_name_conflict",
        "condathis_backend_invalid_name",
        "condathis_invalid_arg",
        "condathis_error"
      ),
      info = name
    )
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "differs only in case",
      fixed = TRUE
    )
    testthat::expect_false(name %in% list_registered_backend_names())
  }
  # The same name again replaces its backend, and the known name itself is
  # the one its package registers.
  testthat::expect_no_error(register_backend("case-test", fake_a))
  testthat::expect_no_error(register_backend("rattler", fake_b))
  withr::defer(unregister_backend("rattler"))
})

testthat::test_that("a name whose root path is not a directory is refused", {
  fake <- new_fake_backend("condathis_backend_root_file_test")
  root <- get_condathis_path()
  fs::dir_create(root)
  taken <- fs::path(root, "root-file-test")
  fs::file_create(taken)
  withr::defer(fs::file_delete(taken))
  cnd <- rlang::catch_cnd(
    register_backend("root-file-test", fake),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_backend_root_conflict",
      "condathis_backend_invalid_name",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  testthat::expect_false(
    "root-file-test" %in% list_registered_backend_names()
  )
  # A directory of that name is the root, and is fine.
  dir_name <- "root-dir-test"
  fs::dir_create(fs::path(root, dir_name))
  withr::defer(fs::dir_delete(fs::path(root, dir_name)))
  testthat::expect_no_error(register_backend(dir_name, fake))
  withr::defer(unregister_backend(dir_name))
})

testthat::test_that("the built-in backend is registered by .onLoad()", {
  testthat::expect_true("micromamba" %in% list_registered_backend_names())
  testthat::expect_s3_class(
    get_backend("micromamba"),
    "condathis_backend_micromamba"
  )
})

testthat::test_that("register_backend requires its own class that inherits condathis_backend", {
  # Regression test: a backend whose only class was "condathis_backend"
  # registered backend_*.condathis_backend methods, which then answered
  # for every backend as an S3 fallback.
  root <- withr::local_tempdir()
  vtable <- new_fake_backend_vtable(root)
  s3_table <- asNamespace("condathis")[[".__S3MethodsTable__."]]
  # A first class that other objects carry, or the S3 fallback "default",
  # would register methods that catch objects that are not this backend.
  bad_classes <- list(
    "condathis_backend",
    c("condathis_backend", "condathis_backend_x"),
    "condathis_backend_no_parent",
    c("my_backend", "other_class"),
    c("list", "condathis_backend"),
    c("default", "condathis_backend"),
    c("data.frame", "condathis_backend")
  )
  for (backend_class in bad_classes) {
    cnd <- rlang::catch_cnd(
      register_backend(
        "bad-class-test",
        structure(vtable, class = backend_class)
      ),
      classes = "error"
    )
    testthat::expect_identical(
      class(cnd)[1:2],
      c("condathis_backend_contract_violation", "condathis_error"),
      info = paste(backend_class, collapse = ", ")
    )
  }
  testthat::expect_false(
    "bad-class-test" %in% list_registered_backend_names()
  )
  for (shared_class in c(
    "condathis_backend",
    "list",
    "data.frame"
  )) {
    testthat::expect_false(
      exists(
        paste0("backend_env_exists.", shared_class),
        envir = s3_table,
        inherits = FALSE
      ),
      info = shared_class
    )
  }
  # The method for "default" is the default of condathis, not the
  # function of the refused object.
  testthat::expect_identical(
    get("backend_env_exists.default", envir = s3_table, inherits = FALSE),
    backend_env_exists.default
  )
  # Not a list at all.
  not_a_list <- structure(
    function(...) NULL,
    class = c("x_be", "condathis_backend")
  )
  testthat::expect_error(
    register_backend("bad-class-test", not_a_list),
    class = "condathis_backend_contract_violation"
  )
})

testthat::test_that("register_backend rejects functions that lack the contract arguments", {
  # Regression test: only is.function() was checked, so a function with
  # the wrong formals failed later, at call time, with "unused argument".
  root <- withr::local_tempdir()
  vtable <- new_fake_backend_vtable(root)
  vtable$backend_create_env <- function(backend) NULL
  vtable$backend_env_exists <- function(backend, verbose = "silent") FALSE
  bad <- structure(
    vtable,
    class = c("condathis_backend_bad_formals_test", "condathis_backend")
  )
  cnd <- rlang::catch_cnd(register_backend("bad-formals", bad))
  testthat::expect_identical(
    class(cnd)[1:2],
    c("condathis_backend_contract_violation", "condathis_error")
  )
  msg <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(msg, "backend_create_env()", fixed = TRUE)
  testthat::expect_match(msg, "`env_file`", fixed = TRUE)
  testthat::expect_match(msg, "backend_env_exists()", fixed = TRUE)
  testthat::expect_match(msg, "`env_name`", fixed = TRUE)
  testthat::expect_false("bad-formals" %in% list_registered_backend_names())

  # `...` takes any argument, so it is enough.
  vtable$backend_create_env <- function(backend, ...) NULL
  vtable$backend_env_exists <- function(...) FALSE
  ok <- structure(
    vtable,
    class = c("condathis_backend_dots_formals_test", "condathis_backend")
  )
  testthat::expect_no_error(register_backend("dots-formals", ok))
  withr::defer(unregister_backend("dots-formals"))
})

testthat::test_that("register_backend checks the new arguments of contract version 2", {
  # backend_install() gets `platform`, backend_resolve_run() `base_env`.
  root <- withr::local_tempdir()
  vtable <- new_fake_backend_vtable(root)
  vtable$backend_install <- function(
    backend,
    packages,
    env_name,
    channels,
    channel_priority,
    additional_channels,
    verbose
  ) {
    NULL
  }
  vtable$backend_resolve_run <- function(
    backend,
    cmd,
    args,
    env_name,
    verbose
  ) {
    NULL
  }
  vtable$backend_can_solve <- function(backend, packages, platform) NA
  bad <- structure(
    vtable,
    class = c("condathis_backend_v1_formals_test", "condathis_backend")
  )
  cnd <- rlang::catch_cnd(
    register_backend("v1-formals", bad),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
  msg <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(
    msg,
    "`backend_install()` lacks `platform`",
    fixed = TRUE
  )
  testthat::expect_match(
    msg,
    "`backend_resolve_run()` lacks `base_env`",
    fixed = TRUE
  )
  testthat::expect_match(msg, "backend_can_solve()", fixed = TRUE)
  testthat::expect_match(msg, "`env_file`", fixed = TRUE)
  testthat::expect_false("v1-formals" %in% list_registered_backend_names())
})

testthat::test_that("a backend needs only the three required functions", {
  not_implemented <- function(...) stop("not implemented")
  minimal <- structure(
    list(
      backend_create_env = not_implemented,
      backend_install = not_implemented,
      backend_resolve_run = not_implemented
    ),
    class = c("condathis_backend_minimal_test", "condathis_backend")
  )
  register_backend("minimal-test", minimal)
  withr::defer(unregister_backend("minimal-test"))
  testthat::expect_true("minimal-test" %in% list_registered_backend_names())
  s3_table <- asNamespace("condathis")[[".__S3MethodsTable__."]]
  for (generic in backend_required_hooks) {
    testthat::expect_true(
      exists(
        paste0(generic, ".condathis_backend_minimal_test"),
        envir = s3_table,
        inherits = FALSE
      ),
      info = generic
    )
  }
  # The optional functions get no method of the class: the defaults
  # answer.
  for (generic in backend_optional_hooks) {
    testthat::expect_false(
      exists(
        paste0(generic, ".condathis_backend_minimal_test"),
        envir = s3_table,
        inherits = FALSE
      ),
      info = generic
    )
  }
  backend <- get_backend("minimal-test")
  testthat::expect_true(backend_available(backend))
  testthat::expect_null(backend_clean_cache(backend, verbose = "silent"))
  testthat::expect_true(backend_quiesce(backend))
  testthat::expect_identical(backend_native_platform(backend), NA_character_)
  testthat::expect_identical(
    backend_can_solve(backend, packages = "x", platform = "linux-64"),
    NA
  )
  testthat::expect_identical(backend_list_envs(backend), character(0L))
  testthat::expect_false(backend_env_exists(backend, env_name = "x"))

  # Each required function is required. A `NULL` element counts as
  # missing.
  for (generic in backend_required_hooks) {
    incomplete <- minimal
    incomplete[generic] <- list(NULL)
    cnd <- rlang::catch_cnd(
      register_backend("minimal-incomplete", incomplete),
      classes = "error"
    )
    testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      generic,
      fixed = TRUE,
      info = generic
    )
  }
  # An optional element that is neither a function nor NULL is refused.
  not_a_function <- minimal
  not_a_function$backend_list_envs <- "envs"
  cnd <- rlang::catch_cnd(
    register_backend("minimal-not-function", not_a_function),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Not a function or `NULL`: backend_list_envs.",
    fixed = TRUE
  )
  testthat::expect_false(
    "minimal-not-function" %in% list_registered_backend_names()
  )
})

testthat::test_that("an own backend_get_env_dir() needs its own listing functions", {
  # Regression test: a backend with only its own backend_get_env_dir()
  # registered, but the default listing looked in `<root>/envs`, so it
  # never found its own environments: create_env() succeeded, list_envs()
  # was empty, and a second create_env() refused to delete the environment
  # as a directory that is not one.
  root <- withr::local_tempdir()
  vtable <- new_fake_backend_vtable(root)
  vtable[c("backend_get_install_dir")] <- list(NULL)
  for (generic in c("backend_list_envs", "backend_env_exists")) {
    partial <- vtable
    partial[generic] <- list(NULL)
    cnd <- rlang::catch_cnd(
      register_backend(
        "own-env-dir-test",
        structure(
          partial,
          class = c("condathis_backend_own_env_dir_test", "condathis_backend")
        )
      ),
      classes = "error"
    )
    testthat::expect_identical(
      class(cnd)[1:2],
      c("condathis_backend_contract_violation", "condathis_error"),
      info = generic
    )
    message <- cli::ansi_strip(conditionMessage(cnd))
    testthat::expect_match(message, generic, fixed = TRUE, info = generic)
    testthat::expect_match(message, "backend_get_env_dir", fixed = TRUE)
  }
  testthat::expect_false(
    "own-env-dir-test" %in% list_registered_backend_names()
  )
  testthat::expect_no_error(register_backend(
    "own-env-dir-test",
    structure(
      vtable,
      class = c("condathis_backend_own_env_dir_test", "condathis_backend")
    )
  ))
  withr::defer(unregister_backend("own-env-dir-test"))
})

testthat::test_that("an own backend_get_install_dir() needs its own listing functions", {
  # The defaults of backend_get_env_dir(), backend_list_envs() and
  # backend_env_exists() look in backend_root_dir(), so with another root
  # they would never find the backend's environments.
  root <- withr::local_tempdir()
  vtable <- new_fake_backend_vtable(root)
  for (generic in backend_root_hooks) {
    partial <- vtable
    partial[generic] <- list(NULL)
    cnd <- rlang::catch_cnd(
      register_backend(
        "own-root-test",
        structure(
          partial,
          class = c("condathis_backend_own_root_test", "condathis_backend")
        )
      ),
      classes = "error"
    )
    testthat::expect_identical(
      class(cnd)[1:2],
      c("condathis_backend_contract_violation", "condathis_error"),
      info = generic
    )
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      generic,
      fixed = TRUE,
      info = generic
    )
  }
  testthat::expect_false("own-root-test" %in% list_registered_backend_names())
  # Without an own backend_get_install_dir(), the defaults are fine.
  vtable[c(
    "backend_get_install_dir",
    "backend_get_env_dir",
    "backend_list_envs",
    "backend_env_exists"
  )] <- NULL
  testthat::expect_no_error(register_backend(
    "own-root-test",
    structure(
      vtable,
      class = c("condathis_backend_own_root_test", "condathis_backend")
    )
  ))
  withr::defer(unregister_backend("own-root-test"))
})

testthat::test_that("re-registration drops the methods of functions the new object lacks", {
  root <- withr::local_tempdir()
  fs::dir_create(fs::path(root, "envs"))
  vtable <- new_fake_backend_vtable(root)
  vtable$backend_available <- function(backend) FALSE
  full <- structure(
    vtable,
    class = c("condathis_backend_rereg_test", "condathis_backend")
  )
  register_backend("rereg-test", full)
  withr::defer(unregister_backend("rereg-test"))
  s3_table <- asNamespace("condathis")[[".__S3MethodsTable__."]]
  method <- "backend_available.condathis_backend_rereg_test"
  testthat::expect_true(exists(method, envir = s3_table, inherits = FALSE))
  testthat::expect_false(backend_available(get_backend("rereg-test")))

  lean <- unclass(full)
  lean$backend_available <- NULL
  lean <- structure(
    lean,
    class = c("condathis_backend_rereg_test", "condathis_backend")
  )
  register_backend("rereg-test", lean)
  testthat::expect_false(exists(method, envir = s3_table, inherits = FALSE))
  # The default answers now.
  testthat::expect_true(backend_available(get_backend("rereg-test")))
  testthat::expect_true(exists(
    "backend_env_exists.condathis_backend_rereg_test",
    envir = s3_table,
    inherits = FALSE
  ))
})

# The code of the example of ?register_backend, as a file to source. In the
# source tree it is man/examples/backend-stub.R. A release tarball has no
# man/examples/, so the code then comes from man/register_backend.Rd, where
# roxygen copied it. `R CMD check` runs the tests without man/, so the code
# then comes from the installed help page.
local_backend_example_file <- function(
  source_file = testthat::test_path(
    "..",
    "..",
    "man",
    "examples",
    "backend-stub.R"
  ),
  rd = NULL,
  envir = parent.frame()
) {
  if (isTRUE(file.exists(source_file))) {
    return(source_file)
  }
  if (is.null(rd)) {
    rd_file <- testthat::test_path("..", "..", "man", "register_backend.Rd")
    if (isTRUE(file.exists(rd_file))) {
      rd <- tools::parse_Rd(rd_file)
    }
  }
  if (is.null(rd)) {
    rd_db <- tryCatch(tools::Rd_db("condathis"), error = function(e) list())
    rd <- rd_db[["register_backend.Rd"]]
  }
  if (is.null(rd)) {
    return(NULL)
  }
  example_file <- withr::local_tempfile(fileext = ".R", .local_envir = envir)
  tools::Rd2ex(rd, out = example_file)
  if (isFALSE(file.exists(example_file))) {
    return(NULL)
  }
  return(example_file)
}

testthat::test_that("the documented example backend registers", {
  # The example of ?register_backend: its functions take `...` or their
  # exact contract arguments, and its install directory exists, as the
  # contract requires. The test fails, and does not pass silently, when the
  # example cannot be found.
  example_file <- local_backend_example_file()
  if (is.null(example_file)) {
    testthat::fail(
      "The example of ?register_backend was not found, in man/examples/ or in the installed help."
    )
    return(invisible(NULL))
  }
  example_env <- new.env(parent = globalenv())
  sys.source(example_file, envir = example_env)
  # The example unregisters its backend again.
  testthat::expect_false("mybackend" %in% list_registered_backend_names())
  mybackend <- example_env$mybackend
  testthat::expect_true(is.list(mybackend))
  register_backend("mybackend", mybackend)
  withr::defer(unregister_backend("mybackend"))
  # The example leaves the root to condathis: backend_root_dir().
  root <- backend_root_dir("mybackend")
  testthat::expect_false(fs::dir_exists(root))
  withr::defer(
    if (isTRUE(fs::dir_exists(root))) {
      fs::dir_delete(root)
    }
  )
  install_dir <- install_dir_for_backend(get_backend("mybackend"))
  testthat::expect_true(fs::dir_exists(install_dir))
  testthat::expect_identical(
    as.character(install_dir),
    as.character(fs::path_real(install_dir))
  )
  testthat::expect_identical(
    as.character(install_dir),
    as.character(backend_root_dir("mybackend"))
  )
})

testthat::test_that("the example backend is found without man/examples/", {
  # Regression test: under `R CMD check` man/examples/ does not exist, and
  # the test above passed without checking anything. The code then comes
  # from the help page. Here the help page is parsed from
  # man/register_backend.Rd, or under `R CMD check` read from the installed
  # help, as the test above does.
  rd_file <- testthat::test_path("..", "..", "man", "register_backend.Rd")
  rd <- if (isTRUE(file.exists(rd_file))) tools::parse_Rd(rd_file)
  example_file <- local_backend_example_file(
    source_file = fs::path(withr::local_tempdir(), "no-such-file.R"),
    rd = rd
  )
  testthat::expect_false(is.null(example_file))
  testthat::expect_true(file.exists(example_file))
  example_env <- new.env(parent = globalenv())
  sys.source(example_file, envir = example_env)
  testthat::expect_s3_class(example_env$mybackend, "condathis_backend")
  testthat::expect_false("mybackend" %in% list_registered_backend_names())
})

testthat::test_that("the generics declare the contract defaults", {
  # Regression test: backend_remove_env() declared verbose in another order
  # (silent first) than the other mutation generics.
  for (generic in c(
    "backend_create_env",
    "backend_install",
    "backend_remove_env",
    "backend_clean_cache"
  )) {
    testthat::expect_identical(
      eval(formals(get(generic))$verbose),
      condathis_verbose_values,
      info = generic
    )
  }
  testthat::expect_identical(
    eval(formals(micromamba_backend_remove_env)$verbose),
    condathis_verbose_values
  )
  for (generic in c(
    "backend_list_envs",
    "backend_env_exists",
    "backend_list_packages",
    "backend_resolve_run"
  )) {
    testthat::expect_identical(
      formals(get(generic))$verbose,
      "silent",
      info = generic
    )
  }
  # The micromamba backend implements exactly the generic signatures, and
  # so do the defaults.
  backend <- micromamba_backend()
  testthat::expect_true(all(names(backend) %in% backend_contract_names))
  testthat::expect_identical(
    setdiff(backend_contract_names, names(backend)),
    "backend_quiesce"
  )
  for (generic in names(backend)) {
    testthat::expect_identical(
      formals(backend[[generic]]),
      formals(get(generic)),
      info = generic
    )
  }
  for (generic in backend_optional_hooks) {
    testthat::expect_identical(
      formals(get(paste0(generic, ".default"))),
      formals(get(generic)),
      info = generic
    )
  }
  for (generic in backend_required_hooks) {
    testthat::expect_false(
      exists(paste0(generic, ".default"), inherits = TRUE),
      info = generic
    )
  }
  testthat::expect_identical(formals(backend_install)$platform, NULL)
  testthat::expect_true("platform" %in% names(formals(backend_install)))
  testthat::expect_identical(
    utils::tail(names(formals(backend_install)), 2L),
    c("platform", "verbose")
  )
  testthat::expect_identical(
    utils::tail(names(formals(backend_resolve_run)), 2L),
    c("base_env", "timeout")
  )
  testthat::expect_identical(
    utils::tail(names(formals(backend_resolve_run_in_dir)), 2L),
    c("base_env", "timeout")
  )
  testthat::expect_identical(formals(backend_resolve_run)$timeout, Inf)
  testthat::expect_identical(formals(backend_quiesce)$timeout, 30)
})

testthat::test_that("timeout reaches only the resolution functions that take it", {
  # `timeout` came after the other arguments of contract version 2: a
  # function without it still registers, and never gets it.
  root <- withr::local_tempdir()
  vtable <- new_fake_backend_vtable(root)
  testthat::expect_false(
    "timeout" %in% names(formals(vtable$backend_resolve_run))
  )
  old_style <- structure(
    vtable,
    class = c("condathis_backend_old_resolve_test", "condathis_backend")
  )
  testthat::expect_no_error(register_backend("old-resolve", old_style))
  withr::defer(unregister_backend("old-resolve"))
  testthat::expect_length(
    backend_resolve_args(old_style, "backend_resolve_run", timeout = 5),
    0L
  )
  vtable$backend_resolve_run <- function(backend, cmd, ...) NULL
  vtable$backend_resolve_run_in_dir <- function(
    backend,
    cmd,
    args = character(0L),
    env_dir,
    verbose = "silent",
    base_env = NULL,
    timeout = Inf
  ) {
    NULL
  }
  new_style <- structure(
    vtable,
    class = c("condathis_backend_new_resolve_test", "condathis_backend")
  )
  testthat::expect_identical(
    backend_resolve_args(new_style, "backend_resolve_run", timeout = 5),
    list(timeout = 5)
  )
  testthat::expect_identical(
    backend_resolve_args(new_style, "backend_resolve_run_in_dir", timeout = 5),
    list(timeout = 5)
  )
})

# --- method validation (no network) ---------------------------------------

testthat::test_that("an invalid method has the new and the old class", {
  for (method in list("not-a-backend", NA_character_, 1L, c("a", "b"))) {
    cnd <- rlang::catch_cnd(validate_method_arg(method), classes = "error")
    testthat::expect_identical(
      class(cnd)[1:4],
      c(
        "condathis_invalid_method",
        "condathis_invalid_method_arg",
        "condathis_invalid_arg",
        "condathis_error"
      ),
      info = deparse(method)
    )
  }
  cnd <- rlang::catch_cnd(validate_method_arg("micromamb"), classes = "error")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Did you mean \"micromamba\"?",
    fixed = TRUE
  )
})

testthat::test_that("a verbose level passed by position as method gets a hint", {
  testthat::skip_on_cran()
  # Regression test: since 0.2.0 `method` comes before `verbose`, so
  # list_envs("silent") from 0.1.4 aborted with no hint about the move.
  cnd <- rlang::catch_cnd(list_envs("silent"), classes = "error")
  testthat::expect_s3_class(cnd, "condathis_invalid_method")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Pass `verbose = \"silent\"` by name.",
    fixed = TRUE
  )
  cnd <- rlang::catch_cnd(env_exists("x", "silent"), classes = "error")
  testthat::expect_s3_class(cnd, "condathis_invalid_method")
  testthat::expect_s3_class(cnd, "condathis_invalid_method_arg")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "`method` now comes before `verbose`",
    fixed = TRUE
  )
  for (level in condathis_verbose_values) {
    for (cnd in list(
      rlang::catch_cnd(list_envs(level), classes = "error"),
      rlang::catch_cnd(remove_env("x", level), classes = "error"),
      rlang::catch_cnd(list_packages("x", level), classes = "error")
    )) {
      testthat::expect_s3_class(cnd, "condathis_invalid_method")
      testthat::expect_match(
        cli::ansi_strip(conditionMessage(cnd)),
        paste0("verbose = \"", level, "\""),
        fixed = TRUE,
        info = level
      )
    }
  }
  # 0.1.4 also accepted TRUE and FALSE for verbose.
  cnd <- rlang::catch_cnd(list_envs(FALSE), classes = "error")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "Pass `verbose = FALSE` by name.",
    fixed = TRUE
  )
  # Other values get no such hint.
  cnd <- rlang::catch_cnd(list_envs("bogus"), classes = "error")
  testthat::expect_no_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "verbose",
    fixed = TRUE
  )
})

testthat::test_that("the verbose hint is only given where verbose can follow method", {
  # About a second or more on Windows: not on CRAN.
  testthat::skip_on_cran()
  # Regression test: get_env_dir() and get_install_dir() have no `verbose`,
  # so the hint "Pass `verbose = ...` by name" led to "unused argument".
  # `method` is checked before any backend call.
  testthat::local_mocked_bindings(
    native_cmd = function(...) stop("native_cmd() must not run here.")
  )
  with_sandbox_dir({
    for (cnd in list(
      rlang::catch_cnd(get_install_dir("silent"), classes = "error"),
      rlang::catch_cnd(get_env_dir("x", "silent"), classes = "error"),
      rlang::catch_cnd(get_install_dir(FALSE), classes = "error"),
      # Called directly, there is no exported caller to name.
      rlang::catch_cnd(validate_method_arg("silent"), classes = "error")
    )) {
      testthat::expect_s3_class(cnd, "condathis_invalid_method")
      testthat::expect_no_match(
        cli::ansi_strip(conditionMessage(cnd)),
        "verbose",
        fixed = TRUE
      )
    }
  })
  # The rule, on explicit formals.
  testthat::expect_true(
    takes_method_before_verbose(c("env_name", "method", "verbose"))
  )
  testthat::expect_true(takes_method_before_verbose(c("method", "verbose")))
  testthat::expect_false(takes_method_before_verbose(c("env_name", "method")))
  testthat::expect_false(takes_method_before_verbose("method"))
  testthat::expect_false(takes_method_before_verbose(
    c("...", "env_name", "method", "verbose")
  ))
  testthat::expect_false(takes_method_before_verbose(
    c("cmd", "...", "env_name", "method", "verbose")
  ))
  testthat::expect_false(takes_method_before_verbose(character(0L)))
  # The formals of the function whose frame is the caller.
  probe <- function(env_name, method, verbose) {
    return(caller_formal_names(rlang::current_env()))
  }
  testthat::expect_identical(probe(), c("env_name", "method", "verbose"))
  testthat::expect_identical(caller_formal_names(globalenv()), character(0L))
  testthat::expect_identical(caller_formal_names(NULL), character(0L))
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
  id <- "deprecated_method_native"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))

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
  # Counted before it is signaled: a handler that stops at the warning, as
  # `options(warn = 2)` does, uses it up too, so only the first call fails.
  reset_warn_once(id)
  cnd <- rlang::catch_cnd(resolve_method_alias("native"), classes = "warning")
  testthat::expect_s3_class(cnd, "condathis_deprecated_method_native")
  testthat::expect_no_warning(resolve_method_alias("native"))
  # reset_warn_once() resets it.
  reset_warn_once(id)
  testthat::expect_warning(
    resolve_method_alias("native"),
    class = "condathis_deprecated_method_native"
  )
})

testthat::test_that("method = 'native' is a soft deprecation", {
  withr::local_options(lifecycle_verbosity = NULL)
  id <- "deprecated_method_native"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  # A call from another package's namespace neither warns nor uses up the
  # once-per-session warning.
  testthat::expect_no_warning(
    testthat::expect_identical(
      resolve_method_alias("native", user_env = asNamespace("tools")),
      "micromamba"
    )
  )
  testthat::expect_warning(
    resolve_method_alias("native", user_env = globalenv()),
    class = "condathis_deprecated_method_native"
  )
  # resolve_backend() passes `user_env` on.
  reset_warn_once(id)
  testthat::expect_no_warning(
    resolved <- resolve_backend(
      method = "native",
      user_env = asNamespace("tools")
    )
  )
  testthat::expect_identical(resolved$name, "micromamba")
  testthat::expect_false(isTRUE(condathis_warn_once_state[[id]]))
  # The exported functions pass their own caller, and resolve the alias
  # before resolve_backend().
  testthat::local_mocked_bindings(
    resolve_backend = function(env_name = NULL, method = "auto", ...) {
      rlang::abort(method, class = "stub_resolved")
    }
  )
  calls <- list(
    create_env = quote(create_env(env_name = "e", method = "native")),
    install_packages = quote(
      install_packages("zlib", env_name = "e", method = "native")
    ),
    validate_env = quote(validate_env(env_name = "e", method = "native")),
    remove_env = quote(remove_env("e", method = "native")),
    run = quote(run("echo", method = "native")),
    run_bin = quote(run_bin("echo", method = "native"))
  )
  for (fn in names(calls)) {
    reset_warn_once(id)
    pkg_env <- new.env(parent = asNamespace("tools"))
    assign(fn, get(fn), envir = pkg_env)
    pkg_fn <- rlang::new_function(list(), calls[[fn]], env = pkg_env)
    testthat::expect_no_warning(
      cnd <- rlang::catch_cnd(pkg_fn(), classes = "stub_resolved")
    )
    testthat::expect_identical(conditionMessage(cnd), "micromamba", info = fn)
    testthat::expect_false(isTRUE(condathis_warn_once_state[[id]]), info = fn)
    # From the tests of this package: the warning.
    testthat::expect_warning(
      rlang::catch_cnd(eval(calls[[fn]]), classes = "stub_resolved"),
      class = "condathis_deprecated_method_native",
      info = fn
    )
  }
})

testthat::test_that("validate_method_arg() reads the 0.1.4 default vector as its first element", {
  # rlang::arg_match() in 0.1.4 gave the first element of the default
  # `method = c("native", "auto")` of create_env() and run().
  testthat::expect_identical(validate_method_arg(c("native", "auto")), "native")
  testthat::expect_identical(validate_method_arg(c("auto", "native")), "auto")
  for (bad in list(
    c("auto", "micromamba"),
    c("native", "native"),
    c("auto", "auto"),
    c("native", "auto", "micromamba"),
    c("native", NA)
  )) {
    testthat::expect_error(
      validate_method_arg(bad),
      class = "condathis_invalid_method",
      info = deparse(bad)
    )
  }
})

# --- resolve_backend() precedence -----------------------------------------
# These touch a real `env_name`, so `find_owning_backends()` also probes the
# real "micromamba" backend as part of iterating every registered backend.
# That probe answers from the file system when the environment has no
# directory under the micromamba root, so these need no micromamba binary
# and no network.

testthat::test_that("resolve_backend resolves a brand-new environment via an explicit method", {
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
  testthat::skip_on_cran()

  fake_1 <- register_fake_backend("fake-rp-collision-1")
  fake_2 <- register_fake_backend("fake-rp-collision-2")
  backend_create_env(fake_1, env_name = "rp-collision-env")
  backend_create_env(fake_2, env_name = "rp-collision-env")

  res <- run_pipeline(
    run_step("echo", "hi"),
    run_step("cat"),
    env_name = "rp-collision-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(127L, 127L))
  testthat::expect_match(
    res$processes[[1]]$stderr,
    "more than one backend"
  )

  testthat::expect_error(
    object = run_pipeline(
      run_step("echo", "hi"),
      run_step("cat"),
      env_name = "rp-collision-env",
      verbose = "silent",
      error = "cancel"
    ),
    class = "condathis_backend_ambiguous_env"
  )
})

test_that("run_pipeline executes through a non-micromamba backend", {
  # `run_pipeline()` previously rejected every backend except
  # `"micromamba"` (`condathis_pipeline_backend_unsupported`). It now
  # resolves each stage through the backend's own `backend_resolve_run()`,
  # so any registered backend executes. The fake backend resolves commands
  # to bare names with no activation variables, which is enough to show the
  # dispatch path actually runs instead of aborting.
  testthat::skip_on_cran()

  fake <- register_fake_backend("fake-rp-supported")
  backend_create_env(fake, env_name = "rp-supported-env")

  res <- run_pipeline(
    run_step("echo", "hi"),
    run_step("cat"),
    env_name = "rp-supported-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
  testthat::expect_match(res$processes[[2L]]$stdout, "hi")
})

test_that("run_pipeline still reports a genuinely missing env as missing", {
  # The half of the old unsupported-backend test that still matters: a
  # nonexistent environment is reported as missing, not silently executed.
  testthat::skip_on_cran()

  register_fake_backend("fake-rp-missing")

  res <- run_pipeline(
    run_step("echo", "hi"),
    run_step("cat"),
    env_name = "rp-never-created-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(127L, 127L))
  testthat::expect_match(res$processes[[1]]$stderr, "does not exist")

  testthat::expect_error(
    object = run_pipeline(
      run_step("echo", "hi"),
      run_step("cat"),
      env_name = "rp-never-created-env",
      verbose = "silent",
      error = "cancel"
    ),
    class = "condathis_pipeline_env_not_found"
  )
})

test_that("run_pipeline lets any command's explicit method disambiguate a shared env_name", {
  # Only the FIRST command referencing a given env_name used to be
  # consulted for its `method` - a second command's explicit override was
  # silently dropped. Here the *second* command supplies the explicit
  # method; if it were ignored, resolution would stay ambiguous and abort
  # with `condathis_backend_ambiguous_env` instead of landing on the
  # specific backend and running.
  #
  # The observable changed when `run_pipeline()` learned to execute through
  # any backend: successful disambiguation used to show up as the
  # "cannot execute through yet" rejection message, and now shows up as the
  # pipeline actually running.
  testthat::skip_on_cran()

  fake_1 <- register_fake_backend("fake-rp-disambig-1")
  fake_2 <- register_fake_backend("fake-rp-disambig-2")
  backend_create_env(fake_1, env_name = "rp-disambig-env")
  backend_create_env(fake_2, env_name = "rp-disambig-env")

  res <- run_pipeline(
    run_step("echo", "hi"),
    run_step(
      "cat",
      env_name = "rp-disambig-env",
      method = "fake-rp-disambig-2"
    ),
    env_name = "rp-disambig-env",
    verbose = "silent",
    error = "continue"
  )
  testthat::expect_equal(res$statuses, c(0L, 0L))
  testthat::expect_match(res$processes[[2L]]$stdout, "hi")
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

testthat::test_that("condathis.backend_priority is an ordering hint, not an allowlist", {
  # Regression test: the option used to be intersected with the registered
  # backends, so naming only an unregistered backend made method = "auto"
  # abort "no backend available" while a working registered backend was
  # right there.
  withr::local_options(
    condathis.backend_priority = "definitely-not-a-registered-backend"
  )
  resolved <- resolve_backend(method = "auto")
  testthat::expect_equal(resolved$name, "micromamba")
})

testthat::test_that("a backend class cannot be registered under two names", {
  # Regression test: S3 methods are keyed on the class, the registry on the
  # name. Registering micromamba_backend() as "mm2" and unregistering "mm2"
  # removed the methods of the built-in micromamba backend for the session.
  cnd <- rlang::catch_cnd(register_backend("mm2", micromamba_backend()))
  testthat::expect_s3_class(cnd, "condathis_backend_class_conflict")
  testthat::expect_false("mm2" %in% list_registered_backend_names())
  testthat::expect_no_error(get_install_dir())

  # An unclassed list cannot be registered either.
  root <- withr::local_tempdir()
  testthat::expect_error(
    register_backend("plain-list-backend", new_fake_backend_vtable(root)),
    class = "condathis_backend_contract_violation"
  )
})


# --- Default backend priority (decision D1, no network) -------------------

testthat::test_that("new environments go to micromamba by default, also with another backend registered", {
  # Regression test: the default priority was c("rattler", "micromamba"),
  # so loading a backend package named "rattler" sent every new
  # environment of method = "auto" to it.
  withr::local_options(condathis.backend_priority = NULL)
  stub <- local_stub_backend("rattler")
  testthat::expect_identical(
    backend_names_by_priority(),
    c("micromamba", "rattler")
  )
  resolved <- resolve_backend(
    env_name = "priority-default-new-env",
    method = "auto",
    mutating = TRUE
  )
  testthat::expect_identical(resolved$name, "micromamba")
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("condathis.backend_priority sends new environments to another backend", {
  stub <- local_stub_backend("stub-priority-opt-in")
  withr::local_options(condathis.backend_priority = "stub-priority-opt-in")
  testthat::expect_identical(
    backend_names_by_priority()[[1L]],
    "stub-priority-opt-in"
  )
  suppressMessages(create_env(
    env_name = "priority-opt-in-env",
    verbose = "silent"
  ))
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 1L)
  testthat::expect_true(
    fs::dir_exists(fs::path(stub$root, "envs", "priority-opt-in-env"))
  )
})

testthat::test_that("an invalid condathis.backend_priority warns once and is ignored", {
  id <- "invalid_backend_priority_option"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  for (value in list(1, NA_character_, c("micromamba", NA), list("x"))) {
    reset_warn_once(id)
    withr::local_options(condathis.backend_priority = value)
    cnd <- rlang::catch_cnd(
      priority <- backend_names_by_priority(),
      classes = "warning"
    )
    testthat::expect_identical(
      class(cnd)[1:2],
      c("condathis_invalid_backend_priority_option", "condathis_warning"),
      info = deparse(value)
    )
    testthat::expect_identical(
      suppressWarnings(backend_names_by_priority())[[1L]],
      "micromamba"
    )
    # Once per session: the second call is silent.
    testthat::expect_no_warning(backend_names_by_priority())
  }
})

# --- Probe failures reach resolve_backend() (rule R5, no network) ---------

testthat::test_that("resolve_backend() aborts a mutating call when a probe fails, and warns a read-only one", {
  # Regression test: resolve_backend() did not pass `mutating` on, so a
  # failed probe of a call that changes the environment only warned and
  # the environment looked new.
  local_stub_backend(
    "stub-resolve-probe-fail",
    backend_env_exists = function(...) {
      rlang::abort("listing failed", class = "stub_listing_failed")
    }
  )
  mutate <- function() {
    resolve_backend(env_name = "probe-env", method = "auto", mutating = TRUE)
  }
  cnd <- rlang::catch_cnd(mutate(), classes = "error")
  testthat::expect_s3_class(cnd, "condathis_backend_probe_failed")
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_s3_class(cnd$parent, "stub_listing_failed")
  # The error names the caller of resolve_backend().
  testthat::expect_identical(conditionCall(cnd), quote(mutate()))

  testthat::expect_warning(
    resolved <- resolve_backend(
      env_name = "probe-env",
      method = "auto",
      mutating = FALSE
    ),
    class = "condathis_backend_query_failed"
  )
  testthat::expect_identical(resolved$name, "micromamba")
})

testthat::test_that("resolve_backend() conditions have the root classes", {
  fake <- register_fake_backend("fake-root-class")
  backend_create_env(fake, env_name = "root-class-env")
  testthat::expect_error(
    resolve_backend(
      env_name = "root-class-env",
      method = "micromamba",
      mutating = TRUE
    ),
    class = "condathis_error"
  )
  testthat::expect_warning(
    resolve_backend(
      env_name = "root-class-env",
      method = "micromamba",
      mutating = FALSE
    ),
    class = "condathis_warning"
  )
  reset_warn_once("deprecated_method_native")
  withr::defer(reset_warn_once("deprecated_method_native"))
  testthat::expect_warning(
    resolve_method_alias("native"),
    class = "condathis_warning"
  )
  testthat::expect_error(
    resolve_backend_by_priority("not-registered-xyz"),
    class = "condathis_error"
  )
})

testthat::test_that("an unavailable backend is still found, but gets no new environment (R6)", {
  stub <- local_stub_backend(
    "stub-unavailable-owner",
    available = FALSE,
    envs = "unavailable-env"
  )
  withr::local_options(condathis.backend_priority = "stub-unavailable-owner")
  resolved <- resolve_backend(env_name = "unavailable-env", method = "auto")
  testthat::expect_identical(resolved$name, "stub-unavailable-owner")
  testthat::expect_true(env_exists("unavailable-env"))
  resolved_new <- resolve_backend(
    env_name = "unavailable-new-env",
    method = "auto",
    mutating = TRUE
  )
  testthat::expect_identical(resolved_new$name, "micromamba")
})

testthat::test_that("an invalid value of backend_available() aborts", {
  # Regression test: a value other than TRUE or FALSE, such as "yes", was
  # read as "unavailable", so `method = "auto"` silently picked the next
  # backend.
  stub <- local_stub_backend("stub-available-invalid", available = "yes")
  withr::local_options(condathis.backend_priority = "stub-available-invalid")
  cnd <- rlang::catch_cnd(
    resolve_backend(
      env_name = "available-new-env",
      method = "auto",
      mutating = TRUE
    ),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_backend_invalid_return",
      "condathis_backend_contract_violation",
      "condathis_error"
    )
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "stub-available-invalid", fixed = TRUE)
  testthat::expect_match(message, "backend_available()", fixed = TRUE)
})

# --- What backends receive (verbose-arg, no network) ----------------------

testthat::test_that("backends get verbose as exactly one of the five strings", {
  # Regression test (A13): backend_create_env() got TRUE or the whole
  # default vector, backend_remove_env() the silent-first vector, and
  # backend_env_exists() FALSE.
  stub <- local_stub_backend("stub-verbose-one")
  m <- stub$name
  suppressMessages({
    create_env(env_name = "verbose-one-env", method = m)
    install_packages(
      "pkg-a",
      env_name = "verbose-one-env",
      method = m,
      verbose = TRUE
    )
    list_packages(env_name = "verbose-one-env", method = m, verbose = "cmd")
    env_exists("verbose-one-env", method = m, verbose = FALSE)
    list_envs(method = m, verbose = "full")
    remove_env(env_name = "verbose-one-env", method = m)
  })
  calls <- stub_calls(stub)
  generics <- vapply(calls, function(x) x$generic, character(1L))
  with_verbose <- c(
    "backend_create_env",
    "backend_install",
    "backend_remove_env",
    "backend_list_envs",
    "backend_env_exists",
    "backend_list_packages"
  )
  testthat::expect_true(all(with_verbose %in% generics))
  for (call in calls[generics %in% with_verbose]) {
    testthat::expect_true("verbose" %in% names(call$args), info = call$generic)
    testthat::expect_true(
      rlang::is_string(call$args$verbose) &&
        isTRUE(call$args$verbose %in% condathis_verbose_values),
      info = paste(call$generic, deparse(call$args$verbose))
    )
  }
  # The defaults of the exported functions reach the backend as one string.
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[1L]]$args$verbose,
    "output"
  )
  testthat::expect_identical(
    stub_calls(stub, "backend_install")[[1L]]$args$verbose,
    "output"
  )
  testthat::expect_identical(
    stub_calls(stub, "backend_list_packages")[[1L]]$args$verbose,
    "cmd"
  )
  remove_calls <- stub_calls(stub, "backend_remove_env")
  testthat::expect_identical(
    remove_calls[[length(remove_calls)]]$args$verbose,
    "output"
  )
  # Probes print nothing.
  for (call in stub_calls(stub, "backend_env_exists")) {
    testthat::expect_identical(call$args$verbose, "silent")
  }
})

# --- Mutation results (mutation-results, no network) ----------------------

testthat::test_that("create_env(), install_packages() and remove_env() accept any backend return value", {
  # Regression test (A3): the three functions read the result with `$`, so
  # a backend returning TRUE failed with "$ operator is invalid for atomic
  # vectors" after the change was made, and `$` partial-matched
  # `stdout_file` as `stdout`.
  returns <- list(TRUE, NULL, list(stdout_file = "x"))
  for (i in seq_along(returns)) {
    value <- returns[[i]]
    info <- deparse(value)
    # The stub's root is known only after it is registered.
    box <- new.env(parent = emptyenv())
    stub <- local_stub_backend(
      paste0("stub-return-", i),
      backend_create_env = function(backend, env_name = "condathis-env", ...) {
        fs::dir_create(fs::path(box$root, "envs", env_name))
        return(value)
      },
      backend_install = function(...) value,
      backend_remove_env = function(backend, env_name = "condathis-env", ...) {
        fs::dir_delete(fs::path(box$root, "envs", env_name))
        return(value)
      }
    )
    box$root <- stub$root
    m <- stub$name

    res <- create_env(env_name = "return-env", method = m, verbose = "silent")
    testthat::expect_identical(res$status, 0L, info = info)
    testthat::expect_identical(res$stdout, NA_character_, info = info)
    res <- install_packages(
      "pkg-a",
      env_name = "return-env",
      method = m,
      verbose = "silent"
    )
    testthat::expect_identical(res$status, 0L, info = info)
    testthat::expect_identical(res$stdout, NA_character_, info = info)
    res <- remove_env(env_name = "return-env", method = m, verbose = "silent")
    testthat::expect_identical(res$status, 0L, info = info)
    testthat::expect_identical(res$stdout, NA_character_, info = info)
    testthat::expect_false(
      fs::dir_exists(fs::path(stub$root, "envs", "return-env")),
      info = info
    )
  }
})

testthat::test_that("a non-zero status from a backend counts as a failure", {
  stub <- local_stub_backend(
    "stub-return-status",
    envs = "status-env",
    backend_create_env = function(...) list(status = 1L),
    backend_install = function(...) list(status = 1L),
    backend_remove_env = function(...) list(status = 1L)
  )
  m <- stub$name
  testthat::expect_error(
    create_env(env_name = "status-new-env", method = m, verbose = "silent"),
    class = "condathis_create_env_failed"
  )
  testthat::expect_error(
    install_packages(
      "pkg-a",
      env_name = "status-env",
      method = m,
      verbose = "silent"
    ),
    class = "condathis_install_packages_failed"
  )
  testthat::expect_error(
    remove_env(env_name = "status-env", method = m, verbose = "silent"),
    class = "condathis_remove_env_failed"
  )
})

# --- Backend failures (backend-error-wrap, no network) --------------------

testthat::test_that("a failing backend raises the same classes on every backend", {
  # Regression test (A14): a failed operation raised the backend's own
  # class only, so callers could not catch it the same way on every
  # backend.
  boom <- function(...) {
    rlang::abort("Backend exploded.", class = "stub_boom")
  }
  stub <- local_stub_backend(
    "stub-boom",
    envs = "boom-env",
    backend_create_env = boom,
    backend_install = boom,
    backend_remove_env = boom,
    backend_list_packages = boom
  )
  m <- stub$name
  calls <- list(
    create_env = function() {
      create_env(env_name = "boom-new-env", method = m, verbose = "silent")
    },
    install_packages = function() {
      install_packages(
        "pkg-a",
        env_name = "boom-env",
        method = m,
        verbose = "silent"
      )
    },
    remove_env = function() {
      remove_env(env_name = "boom-env", method = m, verbose = "silent")
    },
    list_packages = function() {
      list_packages(env_name = "boom-env", method = m, verbose = "silent")
    }
  )
  for (fn in names(calls)) {
    cnd <- rlang::catch_cnd(calls[[fn]](), classes = "error")
    testthat::expect_s3_class(cnd, paste0("condathis_", fn, "_failed"))
    testthat::expect_s3_class(cnd, "condathis_backend_error")
    testthat::expect_s3_class(cnd, "condathis_error")
    testthat::expect_s3_class(cnd$parent, "stub_boom")
    testthat::expect_true(rlang::cnd_inherits(cnd, "stub_boom"))
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      m,
      fixed = TRUE,
      info = fn
    )
  }
})

# --- Missing environments (missing-env-policy, no network) ----------------

testthat::test_that("backends never get a missing environment from condathis", {
  # The contract in ?register_backend: condathis checks existence before
  # backend_install(), backend_remove_env() and backend_list_packages(),
  # so those functions never see a missing environment.
  stub <- local_stub_backend("stub-missing-env")
  m <- stub$name
  testthat::expect_error(
    remove_env(env_name = "never-created", method = m, verbose = "silent"),
    class = "condathis_env_not_found"
  )
  testthat::expect_error(
    list_packages(env_name = "never-created", method = m, verbose = "silent"),
    class = "condathis_env_not_found"
  )
  testthat::expect_error(
    install_packages(
      "pkg-a",
      env_name = "never-created",
      method = m,
      verbose = "silent"
    ),
    class = "condathis_env_not_found"
  )
  for (generic in c(
    "backend_install",
    "backend_remove_env",
    "backend_list_packages",
    "backend_resolve_run",
    "backend_create_env"
  )) {
    testthat::expect_length(stub_calls(stub, generic), 0L)
  }
})
# --- Conda directories of child processes ---------------------------------

# Runs `run()`, `run_bin()` and `run_pipeline()`, the last two with both
# `activate` values, with an `Rscript` that saves its own environment, and
# returns the package-cache and envs-path variables each child got, by
# entry point. An unset variable is `""`.
child_conda_dir_vars <- function(env_name, method) {
  rscript <- get_condathis_rscript_path()
  var_names <- c("CONDA_PKGS_DIRS", "MAMBA_PKGS_DIRS", "CONDA_ENVS_PATH")
  run_bin_with <- function(activate) {
    return(function(script) {
      run_bin(
        rscript,
        "--vanilla",
        script,
        env_name = env_name,
        method = method,
        activate = activate,
        verbose = "silent"
      )
    })
  }
  run_pipeline_with <- function(activate) {
    return(function(script) {
      run_pipeline(
        run_step(rscript, "--vanilla", script),
        run_step(
          rscript,
          "--vanilla",
          "-e",
          "invisible(readLines(file('stdin')))"
        ),
        env_name = env_name,
        method = method,
        activate = activate,
        verbose = "silent"
      )
    })
  }
  entry_points <- list(
    run = function(script) {
      run(
        rscript,
        "--vanilla",
        script,
        env_name = env_name,
        method = method,
        verbose = "silent"
      )
    },
    run_bin = run_bin_with(TRUE),
    run_bin_no_activate = run_bin_with(FALSE),
    run_pipeline = run_pipeline_with(TRUE),
    run_pipeline_no_activate = run_pipeline_with(FALSE)
  )
  dump_dir <- withr::local_tempdir()
  result <- list()
  for (entry_point in names(entry_points)) {
    dump_path <- fs::path(dump_dir, paste0(entry_point, ".rds"))
    script_path <- fs::path(dump_dir, paste0(entry_point, ".R"))
    writeLines(
      paste0(
        "saveRDS(as.list(Sys.getenv()), file = ",
        deparse(as.character(dump_path)),
        ")"
      ),
      script_path
    )
    entry_points[[entry_point]](as.character(script_path))
    child_env <- readRDS(dump_path)
    result[[entry_point]] <- vapply(
      var_names,
      function(nm) as.character(child_env[[nm]] %||% ""),
      character(1L)
    )
  }
  return(result)
}

testthat::test_that("a child of a non-micromamba backend does not get the micromamba roots", {
  # Regression tests:
  # - get_clean_conda_envvars() took CONDA_PKGS_DIRS, MAMBA_PKGS_DIRS and
  #   CONDA_ENVS_PATH from the micromamba root for every child, so a
  #   command of a rattler or other third-party backend used the
  #   micromamba package cache and envs directory;
  # - run_pipeline(activate = FALSE) then set CONDA_ENVS_PATH to the
  #   backend's own envs directory, while run(), run_bin() and
  #   run_pipeline(activate = TRUE) set it to "".
  testthat::skip_on_cran()

  fake <- register_fake_backend("fake-child-roots")
  backend_create_env(fake, env_name = "child-roots-env")
  fake_envs_dir <- fs::path_dir(
    backend_get_env_dir(fake, env_name = "child-roots-env")
  )
  # A Conda tool in the environment keeps its package cache in the
  # backend's own root.
  fake_pkgs_dir <- fs::path(fs::path_dir(fake_envs_dir), "conda-pkgs")
  # The session's own values must not reach the child either.
  withr::local_envvar(
    CONDA_PKGS_DIRS = "/user/pkgs",
    MAMBA_PKGS_DIRS = "/user/pkgs",
    CONDA_ENVS_PATH = "/user/envs"
  )

  child_vars <- child_conda_dir_vars(
    env_name = "child-roots-env",
    method = "fake-child-roots"
  )
  testthat::expect_length(child_vars, 5L)
  for (entry_point in names(child_vars)) {
    vars <- unname(child_vars[[entry_point]])
    testthat::expect_identical(
      as.character(fs::path_norm(vars[1:2])),
      rep(as.character(fs::path_norm(fake_pkgs_dir)), 2L),
      info = entry_point
    )
    testthat::expect_identical(
      as.character(fs::path_norm(vars[[3L]])),
      as.character(fs::path_norm(fake_envs_dir)),
      info = entry_point
    )
  }
})

testthat::test_that("a child of the micromamba backend keeps the micromamba roots", {
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()

  create_polyglot_env("child-roots-micromamba-env")
  root_dir <- install_dir_for_backend(micromamba_backend())
  expected <- fs::path_norm(c(
    fs::path(root_dir, "pkgs"),
    fs::path(root_dir, "pkgs"),
    fs::path(root_dir, "envs")
  ))

  child_vars <- child_conda_dir_vars(
    env_name = "child-roots-micromamba-env",
    method = "micromamba"
  )
  testthat::expect_length(child_vars, 5L)
  for (entry_point in names(child_vars)) {
    testthat::expect_identical(
      as.character(fs::path_norm(unname(child_vars[[entry_point]]))),
      as.character(expected),
      info = entry_point
    )
  }
})

# The process ID written to `pid_file`, or `NA` after 20 seconds.
wait_for_child_pid_file <- function(pid_file) {
  for (i in seq_len(200L)) {
    if (isTRUE(file.exists(pid_file))) {
      pid <- suppressWarnings(as.integer(readLines(pid_file, warn = FALSE)))
      if (isTRUE(length(pid) == 1L && !is.na(pid))) {
        return(pid)
      }
    }
    Sys.sleep(0.1)
  }
  return(NA_integer_)
}

testthat::test_that("with_sandbox_dir stops a process left by a command of another backend", {
  # Regression test: a child of a non-micromamba backend got "" for
  # CONDA_ENVS_PATH, CONDA_PKGS_DIRS and MAMBA_PKGS_DIRS. A process it left
  # running, with no CONDA_PREFIX and nothing on its command line inside
  # the sandbox, kept running after with_sandbox_dir() returned.
  testthat::skip_on_cran()

  rscript <- get_condathis_rscript_path()
  # Every file is outside the sandbox: only the child's environment ties
  # the leftover process to it.
  outside_dir <- withr::local_tempdir()
  pid_file <- file.path(outside_dir, "leftover.pid")
  sleeper <- file.path(outside_dir, "sleeper.R")
  spawner <- file.path(outside_dir, "spawner.R")
  # The temporary directory of the sleeper, which is killed before it can
  # delete its own `tempdir()`. The per-call `TMPDIR` of run_bin() is gone
  # when it starts, and R would fall back to the system's.
  sleeper_tmp <- file.path(outside_dir, "sleeper-tmp")
  dir.create(sleeper_tmp)
  writeLines(
    c(
      "writeLines(as.character(Sys.getpid()), commandArgs(TRUE)[[1L]])",
      "Sys.sleep(60)"
    ),
    sleeper
  )
  writeLines(
    c(
      "args <- commandArgs(TRUE)",
      "lib_paths <- strsplit(args[[1L]], .Platform$path.sep, fixed = TRUE)",
      ".libPaths(c(lib_paths[[1L]], .libPaths()))",
      "tmp <- args[[2L]]",
      # `system2(wait = FALSE)` does not outlive this script on Windows.
      paste(
        "processx::process$new(args[[3L]], args[-(1:3)],",
        "env = c('current', TMPDIR = tmp, TMP = tmp, TEMP = tmp),",
        "cleanup = FALSE)"
      )
    ),
    spawner
  )
  lib_paths <- paste(.libPaths(), collapse = .Platform$path.sep)

  leftover_pid <- NA_integer_
  # Stops the leftover process if with_sandbox_dir() did not.
  withr::defer({
    if (isTRUE(run_family_pid_running(leftover_pid))) {
      tryCatch(
        ps::ps_kill(ps::ps_handle(leftover_pid)),
        error = function(e) NULL
      )
    }
  })
  with_sandbox_dir({
    root <- fs::path(Sys.getenv("HOME"), "fake-sandbox-root")
    fs::dir_create(fs::path(root, "envs"))
    fake <- structure(
      new_fake_backend_vtable(root),
      class = c("condathis_backend_fake_sandbox_child", "condathis_backend")
    )
    register_backend("fake-sandbox-child", fake)
    withr::defer(unregister_backend("fake-sandbox-child"))
    backend_create_env(fake, env_name = "sandbox-child-env")

    # No pipes: the leftover process would hold them open.
    res <- run_bin(
      rscript,
      "--vanilla",
      spawner,
      lib_paths,
      sleeper_tmp,
      rscript,
      "--vanilla",
      sleeper,
      pid_file,
      env_name = "sandbox-child-env",
      method = "fake-sandbox-child",
      activate = FALSE,
      verbose = "silent",
      stdout = file.path(outside_dir, "stdout.txt"),
      stderr = file.path(outside_dir, "stderr.txt")
    )
    testthat::expect_identical(res$status, 0L)
    leftover_pid <- wait_for_child_pid_file(pid_file)
    testthat::expect_false(is.na(leftover_pid))
    testthat::expect_true(run_family_pid_running(leftover_pid))
  })
  # A killed process can take a moment to go away: Windows ends it
  # asynchronously, and on Linux it is a zombie until it is reaped.
  gone <- FALSE
  for (i in seq_len(50L)) {
    if (isFALSE(run_family_pid_running(leftover_pid))) {
      gone <- TRUE
      break
    }
    Sys.sleep(0.1)
  }
  testthat::expect_true(gone)
})
