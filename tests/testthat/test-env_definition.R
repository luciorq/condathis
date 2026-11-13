rlang_tail <- c("rlang_error", "error", "condition")

catch_error <- function(expr) {
  return(rlang::catch_cnd(expr, classes = "error"))
}

# A package listing with the six columns of the backend contract.
definition_pkgs_df <- function(name = character(0L), platform = "noarch") {
  n <- length(name)
  return(data.frame(
    name = as.character(name),
    version = rep_len("1.0", n),
    build_number = rep_len(0L, n),
    build_string = rep_len("h0_0", n),
    channel = rep_len("conda-forge", n),
    platform = rep_len(platform, n),
    stringsAsFactors = FALSE
  ))
}

# A stub backend that is the only one condathis sees (see
# helper-stub-backend.R). `installed` is what its listing returns once an
# environment was created.
local_definition_stub <- function(
  name,
  ...,
  envs = character(0L),
  installed = definition_pkgs_df(),
  envir = parent.frame()
) {
  overrides <- list(...)
  if (isFALSE("backend_list_packages" %in% names(overrides))) {
    overrides$backend_list_packages <- function(backend, ...) installed
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

# A description as a backend returns it.
lock_description <- function(
  platforms = "linux-64",
  records = data.frame(
    name = "pkg",
    version = "1.0",
    build_string = "h0_0",
    platform = platforms[[1L]],
    stringsAsFactors = FALSE
  )
) {
  return(list(
    supported = TRUE,
    format = "explicit",
    kind = "lock",
    platforms = platforms,
    reason = NA,
    records = records
  ))
}

local_definition_file <- function(
  name = "environment.yml",
  lines = "dependencies: []",
  envir = parent.frame()
) {
  path <- fs::path(withr::local_tempdir(.local_envir = envir), name)
  writeLines(lines, path)
  return(as.character(path))
}

# --- The object -------------------------------------------------------------

testthat::test_that("env_definition() makes the path absolute against the working directory", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  # On macOS, getwd() resolves the /var -> /private/var symbolic link of
  # tempdir(), so compare against the working directory, not `dir`.
  wd <- getwd()
  definition <- env_definition("sub/../environment.yml")
  testthat::expect_s3_class(definition, "condathis_env_definition")
  testthat::expect_identical(
    definition$path,
    as.character(fs::path_norm(fs::path_abs("environment.yml")))
  )
  testthat::expect_true(fs::is_absolute_path(definition$path))
  testthat::expect_null(definition$format)
  testthat::expect_identical(definition$options, list())
  # A later setwd() does not change it.
  withr::local_dir(tempdir())
  testthat::expect_identical(
    definition$path,
    as.character(fs::path_norm(fs::path(wd, "environment.yml")))
  )
})

testthat::test_that("env_definition() expands ~ and keeps symbolic links", {
  testthat::expect_identical(
    env_definition("~/environment.yml")$path,
    as.character(fs::path_norm(fs::path_expand("~/environment.yml")))
  )
  dir <- withr::local_tempdir()
  fs::dir_create(fs::path(dir, "real"))
  fs::link_create(fs::path(dir, "real"), fs::path(dir, "link"))
  path <- fs::path(dir, "link", "environment.yml")
  # Not resolved to `real/`: pip `-r` paths in the file stay relative to
  # the directory the user named.
  testthat::expect_identical(
    env_definition(path)$path,
    as.character(fs::path_norm(path))
  )
})

testthat::test_that("env_definition() keeps format and options as given", {
  definition <- env_definition(
    "ci.lock",
    format = "conda-lock-v1",
    categories = c("main", "dev")
  )
  testthat::expect_identical(definition$format, "conda-lock-v1")
  testthat::expect_identical(
    definition$options,
    list(categories = c("main", "dev"))
  )
  # condathis does not interpret them.
  definition <- env_definition("x", format = "Some-Future-Format", foo = list(1))
  testthat::expect_identical(definition$format, "Some-Future-Format")
  testthat::expect_identical(definition$options, list(foo = list(1)))
})

testthat::test_that("env_definition() has format() and print() methods", {
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  definition <- env_definition("environment.yml")
  testthat::expect_identical(
    format(definition),
    paste0("<env_definition> ", definition$path)
  )
  testthat::expect_output(
    out <- withVisible(print(definition)),
    "<env_definition> ",
    fixed = TRUE
  )
  testthat::expect_false(out$visible)
  testthat::expect_identical(out$value, definition)
  definition <- env_definition(
    "ci.lock",
    format = "conda-lock-v1",
    categories = "main"
  )
  testthat::expect_identical(
    format(definition),
    paste0(
      "<env_definition> ",
      definition$path,
      " (format: conda-lock-v1; options: categories)"
    )
  )
})

testthat::test_that("env_definition() rejects invalid arguments", {
  path_class <- c(
    "condathis_env_definition_invalid_path",
    "condathis_invalid_path",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  testthat::expect_identical(class(catch_error(env_definition())), path_class)
  for (bad in list(NA_character_, "", c("a", "b"), 1L, NULL, list("a"))) {
    testthat::expect_identical(
      class(catch_error(env_definition(bad))),
      path_class,
      info = deparse(bad)
    )
  }
  # URLs are out of scope: a definition must never download anything.
  for (url in c(
    "https://example.org/environment.yml",
    "file:///tmp/environment.yml",
    "s3://bucket/conda-lock.yml"
  )) {
    cnd <- catch_error(env_definition(url))
    testthat::expect_identical(class(cnd), path_class, info = url)
    testthat::expect_match(conditionMessage(cnd), "URL", fixed = TRUE)
  }
  # A Windows path is a path.
  testthat::expect_s3_class(
    env_definition("C:/env/environment.yml"),
    "condathis_env_definition"
  )

  format_class <- c(
    "condathis_env_definition_invalid_format",
    "condathis_invalid_format",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  for (bad in list(NA_character_, "", c("a", "b"), 1L, TRUE)) {
    testthat::expect_identical(
      class(catch_error(env_definition("a.yml", format = bad))),
      format_class,
      info = deparse(bad)
    )
  }

  options_class <- c(
    "condathis_env_definition_invalid_options",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  testthat::expect_identical(
    class(catch_error(env_definition("a.yml", NULL, "main"))),
    options_class
  )
  testthat::expect_identical(
    class(catch_error(env_definition("a.yml", a = 1, a = 2))),
    options_class
  )
})

testthat::test_that("a malformed env_definition object aborts where it is used", {
  invalid_class <- c(
    "condathis_env_definition_invalid",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  good <- env_definition("environment.yml")
  malformed <- list(
    new_env_definition("relative.yml"),
    new_env_definition(NA_character_),
    new_env_definition("https://example.org/e.yml"),
    structure(list(path = good$path, format = 1), class = class(good)),
    new_env_definition(good$path, options = list(1)),
    structure("a.yml", class = "condathis_env_definition")
  )
  for (x in malformed) {
    testthat::expect_identical(
      class(catch_error(validate_env_definition_object(x))),
      invalid_class
    )
  }
  # create_env() checks it before any backend call.
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  testthat::expect_identical(
    class(catch_error(create_env(new_env_definition("relative.yml")))),
    invalid_class
  )
  testthat::expect_identical(
    class(validate_env_definition_object(good)),
    "condathis_env_definition"
  )
})

# --- create_env() and its `...` ---------------------------------------------

testthat::test_that("create_env() passes an env_definition() to the backend as env_file", {
  stub <- local_definition_stub("stub-def-basic")
  path <- local_definition_file()
  res <- create_env(env_definition(path), env_name = "def-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  call <- stub_calls(stub, "backend_create_env")[[1L]]
  testthat::expect_null(call$args$packages)
  testthat::expect_identical(call$args$env_file, env_definition(path)$path)
  # The stub takes `...`, so it gets the definition too.
  testthat::expect_identical(call$args$definition, env_definition(path))
  # Without a description, the request goes on as before.
  testthat::expect_length(stub_calls(stub, "backend_describe_definition"), 0L)
})

testthat::test_that("create_env() takes at most one env_definition() and no specs with it", {
  conflicting_class <- c(
    "condathis_create_env_conflicting_args",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  path_a <- local_definition_file("a.yml")
  path_b <- local_definition_file("b.yml")
  for (call in list(
    quote(create_env(env_definition(path_a), env_definition(path_b))),
    quote(create_env(env_definition(path_a), "zlib")),
    quote(create_env("zlib", env_definition(path_a))),
    quote(create_env(env_definition(path_a), env_file = path_b))
  )) {
    testthat::expect_identical(
      class(catch_error(eval(call))),
      conflicting_class,
      info = deparse(call)
    )
  }
})

testthat::test_that("create_env() rejects an env_definition() of a missing file", {
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  missing_path <- fs::path(withr::local_tempdir(), "missing.yml")
  cnd <- catch_error(create_env(env_definition(missing_path)))
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
  testthat::expect_match(conditionMessage(cnd), "missing.yml", fixed = TRUE)
})

testthat::test_that("create_env() with an existing environment never compares a definition", {
  stub <- local_definition_stub("stub-def-exists", envs = "exists-env")
  path <- local_definition_file()
  cnd <- catch_error(
    create_env(env_definition(path), env_name = "exists-env", verbose = "silent")
  )
  testthat::expect_s3_class(cnd, "condathis_create_env_exists")
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

# --- The deprecated `env_file` ----------------------------------------------

testthat::test_that("create_env(env_file =) still works, as an env_definition()", {
  withr::local_options(lifecycle_verbosity = NULL)
  id <- "deprecated_env_file_arg"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  stub <- local_definition_stub("stub-def-env-file")
  dir <- withr::local_tempdir()
  writeLines("dependencies: []", fs::path(dir, "environment.yml"))
  withr::local_dir(dir)
  testthat::expect_warning(
    res <- create_env(
      env_file = "environment.yml",
      env_name = "file-env",
      verbose = "silent"
    ),
    class = "condathis_deprecated_env_file_arg"
  )
  testthat::expect_identical(res$status, 0L)
  call <- stub_calls(stub, "backend_create_env")[[1L]]
  # The same request as env_definition(): an absolute path.
  testthat::expect_identical(
    call$args$env_file,
    env_definition("environment.yml")$path
  )
  testthat::expect_identical(
    call$args$definition,
    env_definition("environment.yml")
  )
  # Once per session.
  testthat::expect_no_warning(create_env(
    env_file = "environment.yml",
    env_name = "file-env-2",
    verbose = "silent"
  ))
})

testthat::test_that("create_env(env_file =) warns only for direct use", {
  withr::local_options(lifecycle_verbosity = NULL)
  id <- "deprecated_env_file_arg"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  stub <- local_definition_stub("stub-def-env-file-soft")
  path <- local_definition_file()
  # A function of another package's namespace.
  pkg_env <- new.env(parent = asNamespace("tools"))
  pkg_env$create_env <- create_env
  pkg_env$path <- path
  pkg_fn <- function(env_name) {
    return(create_env(env_file = path, env_name = env_name, verbose = "silent"))
  }
  environment(pkg_fn) <- pkg_env
  testthat::expect_no_warning(res <- pkg_fn("soft-env"))
  testthat::expect_identical(res$status, 0L)
  testthat::expect_false(isTRUE(condathis_warn_once_state[[id]]))
  # From the console (the global environment).
  global_fn <- function(env_name) {
    return(create_env(env_file = path, env_name = env_name, verbose = "silent"))
  }
  # Its frame's top environment is the global environment.
  global_env <- new.env(parent = globalenv())
  global_env$path <- path
  environment(global_fn) <- global_env
  testthat::expect_warning(
    global_fn("soft-env-2"),
    class = "condathis_deprecated_env_file_arg"
  )
  testthat::expect_no_warning(global_fn("soft-env-3"))
})

testthat::test_that("an invalid env_file aborts before its deprecation warning", {
  withr::local_options(lifecycle_verbosity = NULL)
  id <- "deprecated_env_file_arg"
  reset_warn_once(id)
  withr::defer(reset_warn_once(id))
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  testthat::expect_no_warning(
    cnd <- catch_error(create_env(env_file = "definitely-missing.yml"))
  )
  testthat::expect_s3_class(cnd, "condathis_create_env_missing_env_file")
  testthat::expect_no_warning(cnd <- catch_error(create_env(env_file = 1L)))
  testthat::expect_s3_class(cnd, "condathis_create_env_invalid_env_file")
})

# --- Backends without the `definition` argument -----------------------------

# A backend whose functions have exactly the formals of the rattlerthis
# backend (rattlerthis R/condathis-backend.R): no `definition`, no `...`.
# `backend_install` replaces its install function; `record$root` is its
# root and `record$install` records the calls of the default install.
local_formals_backend <- function(
  name,
  backend_install = NULL,
  envir = parent.frame()
) {
  root <- withr::local_tempdir(.local_envir = envir)
  record <- new.env(parent = emptyenv())
  record$root <- root
  record$create <- list()
  record$can_solve <- list()
  record$install <- list()
  backend <- structure(
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
        record$create[[length(record$create) + 1L]] <- as.list(environment())
        fs::dir_create(fs::path(root, "envs", env_name))
        return(list(status = 0L))
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
        record$install[[length(record$install) + 1L]] <- as.list(environment())
        return(list(status = 0L))
      },
      backend_resolve_run = function(
        backend,
        cmd,
        args = character(0L),
        env_name = "condathis-env",
        verbose = "silent",
        base_env = NULL,
        timeout = Inf
      ) {
        return(list(command = cmd, args = args, env = NULL, dir = NULL))
      },
      backend_get_install_dir = function(backend) root,
      backend_get_env_dir = function(backend, env_name = "condathis-env") {
        return(fs::path(root, "envs", env_name))
      },
      backend_list_envs = function(backend, verbose = "silent") {
        return(as.character(fs::path_file(
          fs::dir_ls(fs::path(root, "envs"), type = "directory")
        )))
      },
      backend_env_exists = function(backend, env_name, verbose = "silent") {
        return(isTRUE(fs::dir_exists(fs::path(root, "envs", env_name))))
      },
      backend_can_solve = function(
        backend,
        packages = NULL,
        env_file = NULL,
        channels = "conda-forge",
        channel_priority = c("strict", "flexible", "disabled"),
        additional_channels = NULL,
        platform
      ) {
        record$can_solve[[length(record$can_solve) + 1L]] <- as.list(
          environment()
        )
        return(TRUE)
      }
    ),
    class = c(
      paste0("condathis_backend_test_", gsub("-", "_", name)),
      "condathis_backend"
    )
  )
  if (is.function(backend_install)) {
    backend$backend_install <- backend_install
  }
  fs::dir_create(fs::path(root, "envs"))
  register_backend(name, backend)
  withr::defer(unregister_backend(name), envir = envir)
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() name,
    .env = envir
  )
  return(record)
}

testthat::test_that("a backend with the rattlerthis formals keeps working with a plain definition", {
  record <- local_formals_backend("formals-only")
  # rattlerthis's own tests compare its functions with the generics of
  # condathis: they must stay identical.
  backend <- get_backend("formals-only")
  for (generic in c("backend_create_env", "backend_install", "backend_can_solve")) {
    testthat::expect_identical(
      formals(backend[[generic]]),
      formals(get(generic)),
      info = generic
    )
  }
  path <- local_definition_file()
  res <- create_env(env_definition(path), env_name = "plain", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(record$create, 1L)
  testthat::expect_identical(record$create[[1L]]$env_file, env_definition(path)$path)
  testthat::expect_false("definition" %in% names(record$create[[1L]]))
  # And with the deprecated env_file.
  withr::local_options(lifecycle_verbosity = "quiet")
  res <- create_env(env_file = path, env_name = "plain-2", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(record$create[[2L]]$env_file, env_definition(path)$path)
  # The emulation probe gets the file too, without `definition`.
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    is_rosetta_running = function() TRUE
  )
  res <- create_env(env_definition(path), env_name = "plain-3", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    record$can_solve[[1L]]$env_file,
    env_definition(path)$path
  )
  testthat::expect_false("definition" %in% names(record$can_solve[[1L]]))
})

testthat::test_that("a definition with format or options aborts for a backend without the argument", {
  record <- local_formals_backend("formals-only-2")
  path <- local_definition_file("ci.lock")
  for (definition in list(
    env_definition(path, format = "conda-lock-v1"),
    env_definition(path, categories = "main")
  )) {
    cnd <- catch_error(
      create_env(definition, env_name = "unsupported", verbose = "silent")
    )
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_unsupported_definition",
        "condathis_backend_unsupported",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      )
    )
    testthat::expect_match(conditionMessage(cnd), "formals-only-2", fixed = TRUE)
  }
  testthat::expect_length(record$create, 0L)
  testthat::expect_false(env_exists("unsupported"))
  # The hint names a registered backend that reads the format.
  cnd <- catch_error(create_env(
    env_definition(path, format = "conda-lock-v1"),
    env_name = "unsupported",
    verbose = "silent"
  ))
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "micromamba",
    fixed = TRUE
  )
})

# --- backend_describe_definition() ------------------------------------------

testthat::test_that("the default description is NA, or FALSE for details a backend cannot get", {
  record <- local_formals_backend("formals-only-3")
  backend <- get_backend("formals-only-3")
  path <- local_definition_file()
  testthat::expect_identical(
    backend_describe_definition_checked(backend, env_definition(path)),
    definition_description()
  )
  value <- backend_describe_definition_checked(
    backend,
    env_definition(path, format = "environment-yaml")
  )
  testthat::expect_false(value$supported)
  testthat::expect_identical(value$format, "environment-yaml")
  testthat::expect_true(is.na(value$kind))
  testthat::expect_identical(backend_definition_formats(backend), character(0L))
  # A backend that takes `...` can get them.
  stub <- local_stub_backend("stub-def-dots")
  testthat::expect_identical(
    backend_describe_definition_checked(
      stub$backend,
      env_definition(path, format = "environment-yaml")
    ),
    definition_description()
  )
})

testthat::test_that("a description that is FALSE aborts before any lock or create", {
  stub <- local_definition_stub(
    "stub-def-false",
    backend_describe_definition = function(backend, definition, ...) {
      return(list(supported = FALSE, reason = "Not a format I read."))
    }
  )
  testthat::local_mocked_bindings(
    local_env_lock = function(...) stop("local_env_lock() must not be called")
  )
  path <- local_definition_file()
  cnd <- catch_error(create_env(env_definition(path), env_name = "x"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_unsupported_definition",
      "condathis_backend_unsupported",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_match(conditionMessage(cnd), "Not a format I read.", fixed = TRUE)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  call <- stub_calls(stub, "backend_describe_definition")[[1L]]
  testthat::expect_identical(call$args$definition, env_definition(path))
  testthat::expect_null(call$args$platform)
})

testthat::test_that("a description that fails counts as NA, and an invalid one aborts", {
  stub <- local_definition_stub(
    "stub-def-error",
    backend_describe_definition = function(backend, ...) stop("broken")
  )
  path <- local_definition_file()
  res <- create_env(env_definition(path), env_name = "x", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 1L)

  check <- function(value) {
    return(validate_backend_return(
      value,
      generic = "backend_describe_definition",
      backend_name = "b"
    ))
  }
  for (bad in list(
    TRUE,
    list(supported = "yes"),
    list(supported = TRUE, kind = "solved"),
    list(supported = TRUE, kind = "lock", platforms = NA_character_),
    list(supported = TRUE, kind = "lock", records = data.frame(name = "a")),
    list(supported = TRUE, format = 1),
    data.frame(supported = TRUE)
  )) {
    testthat::expect_error(
      check(bad),
      class = "condathis_backend_invalid_return"
    )
  }
  # Missing elements get their defaults; `kind` counts only when supported.
  testthat::expect_identical(
    check(list(supported = TRUE, kind = "request")),
    definition_description(supported = TRUE, kind = "request")
  )
  testthat::expect_identical(
    check(list(supported = NA, kind = "lock")),
    definition_description()
  )
  testthat::expect_identical(
    validate_backend_return(
      NULL,
      generic = "backend_definition_formats",
      backend_name = "b"
    ),
    character(0L)
  )
  testthat::expect_error(
    validate_backend_return(
      NA_character_,
      generic = "backend_definition_formats",
      backend_name = "b"
    ),
    class = "condathis_backend_invalid_return"
  )
})

testthat::test_that("a request is solved for the platform, with the definition", {
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    is_rosetta_running = function() TRUE
  )
  stub <- local_definition_stub(
    "stub-def-request",
    backend_describe_definition = function(backend, ...) {
      return(list(supported = TRUE, format = "environment-yaml", kind = "request"))
    },
    backend_can_solve = function(backend, ..., platform) {
      return(identical(platform, "osx-64"))
    }
  )
  path <- local_definition_file()
  create_env(env_definition(path), env_name = "request-env", verbose = "silent")
  solves <- stub_calls(stub, "backend_can_solve")
  testthat::expect_length(solves, 2L)
  testthat::expect_identical(solves[[1L]]$args$definition, env_definition(path))
  testthat::expect_identical(solves[[1L]]$args$env_file, env_definition(path)$path)
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[1L]]$args$platform,
    "osx-64"
  )
  # A request may come with channels.
  create_env(
    env_definition(path),
    env_name = "request-env-2",
    channels = "bioconda",
    verbose = "silent"
  )
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[2L]]$args$channels,
    "bioconda"
  )
})

testthat::test_that("a lock is never solved, and gets a platform it lists", {
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    is_rosetta_running = function() TRUE
  )
  platforms <- "osx-arm64"
  stub <- local_definition_stub(
    "stub-def-lock",
    installed = definition_pkgs_df("pkg"),
    backend_describe_definition = function(backend, ...) {
      return(lock_description(platforms = platforms))
    },
    backend_native_platform = function(backend) "osx-arm64",
    backend_can_solve = function(backend, ...) stop("a lock is never solved")
  )
  path <- local_definition_file("explicit.txt", "@EXPLICIT")
  # The native platform: `platform` stays NULL.
  res <- create_env(env_definition(path), env_name = "lock-native", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_null(stub_calls(stub, "backend_create_env")[[1L]]$args$platform)
  # A given platform that it lists.
  platforms <- c("osx-arm64", "linux-64")
  create_env(
    env_definition(path),
    env_name = "lock-given",
    platform = "linux-64",
    verbose = "silent"
  )
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[2L]]$args$platform,
    "linux-64"
  )
  # The emulated platform, when only it is listed.
  platforms <- c("osx-64", "noarch")
  msgs <- character(0L)
  withCallingHandlers(
    create_env(env_definition(path), env_name = "lock-emulated", verbose = "output"),
    message = function(m) {
      msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  testthat::expect_match(paste(msgs, collapse = "\n"), "Rosetta 2", fixed = TRUE)
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[3L]]$args$platform,
    "osx-64"
  )
  testthat::expect_identical(
    read_backend_marker(fs::path(stub$root, "envs", "lock-emulated"))$platform,
    "osx-64"
  )
  testthat::expect_length(stub_calls(stub, "backend_can_solve"), 0L)
})

testthat::test_that("a lock for other platforms aborts before any work", {
  stub <- local_definition_stub(
    "stub-def-not-locked",
    backend_describe_definition = function(backend, ...) {
      return(lock_description(platforms = c("win-64", "noarch")))
    },
    backend_native_platform = function(backend) "linux-64"
  )
  path <- local_definition_file("explicit.txt", "@EXPLICIT")
  not_locked_class <- c(
    "condathis_create_env_platform_not_locked",
    "condathis_create_env_platform_mismatch",
    "condathis_create_platform_mismatch",
    "condathis_error",
    rlang_tail
  )
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Linux-x86_64",
    local_env_lock = function(...) stop("local_env_lock() must not be called")
  )
  cnd <- catch_error(create_env(env_definition(path), env_name = "x"))
  testthat::expect_identical(class(cnd), not_locked_class)
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "linux-64", fixed = TRUE)
  testthat::expect_match(message, "win-64", fixed = TRUE)
  cnd <- catch_error(
    create_env(env_definition(path), env_name = "x", platform = "osx-64")
  )
  testthat::expect_identical(class(cnd), not_locked_class)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("a lock without platforms, or a backend without a native platform, is left to the backend", {
  platforms <- NULL
  stub <- local_definition_stub(
    "stub-def-unknown-platform",
    installed = definition_pkgs_df("pkg"),
    backend_describe_definition = function(backend, ...) {
      return(lock_description(platforms = platforms, records = NULL))
    }
  )
  path <- local_definition_file("explicit.txt", "@EXPLICIT")
  create_env(env_definition(path), env_name = "a", verbose = "silent")
  testthat::expect_null(stub_calls(stub, "backend_create_env")[[1L]]$args$platform)
  create_env(env_definition(path), env_name = "b", platform = "linux-64", verbose = "silent")
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[2L]]$args$platform,
    "linux-64"
  )
  # The stub's backend_native_platform() is NA.
  platforms <- "win-64"
  create_env(env_definition(path), env_name = "c", verbose = "silent")
  testthat::expect_null(stub_calls(stub, "backend_create_env")[[3L]]$args$platform)
})

testthat::test_that("a lock with channels, additional_channels or channel_priority aborts", {
  stub <- local_definition_stub(
    "stub-def-lock-channels",
    backend_describe_definition = function(backend, ...) lock_description(),
    backend_native_platform = function(backend) "linux-64"
  )
  path <- local_definition_file("explicit.txt", "@EXPLICIT")
  for (call in list(
    quote(create_env(env_definition(path), channels = "conda-forge")),
    quote(create_env(env_definition(path), additional_channels = "bioconda")),
    quote(create_env(env_definition(path), channel_priority = "strict"))
  )) {
    cnd <- catch_error(eval(call))
    testthat::expect_identical(
      class(cnd),
      c(
        "condathis_create_env_conflicting_args",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = deparse(call)
    )
  }
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("a lock that gives an empty environment fails and keeps the old one", {
  installed <- definition_pkgs_df()
  stub <- local_definition_stub(
    "stub-def-empty",
    envs = "kept-env",
    backend_list_packages = function(backend, ...) installed,
    backend_describe_definition = function(backend, ...) lock_description(),
    backend_native_platform = function(backend) "linux-64"
  )
  path <- local_definition_file("explicit.txt", "@EXPLICIT")
  cnd <- catch_error(
    create_env(env_definition(path), env_name = "empty-env", verbose = "silent")
  )
  testthat::expect_s3_class(cnd, "condathis_create_env_failed")
  testthat::expect_s3_class(cnd, "condathis_backend_error")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd$parent)),
    "lists 1 package",
    fixed = TRUE
  )
  testthat::expect_false(fs::dir_exists(fs::path(stub$root, "envs", "empty-env")))
  # With overwrite = TRUE, the existing environment comes back.
  fs::file_create(fs::path(stub$root, "envs", "kept-env", "marker-file"))
  cnd <- catch_error(create_env(
    env_definition(path),
    env_name = "kept-env",
    overwrite = TRUE,
    verbose = "silent"
  ))
  testthat::expect_s3_class(cnd, "condathis_create_env_failed")
  testthat::expect_true(fs::file_exists(
    fs::path(stub$root, "envs", "kept-env", "marker-file")
  ))
  # An environment with packages passes.
  installed <- definition_pkgs_df("pkg")
  res <- create_env(env_definition(path), env_name = "full-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
})

# --- install_packages() -----------------------------------------------------

request_description <- function() {
  return(list(supported = TRUE, format = "environment-yaml", kind = "request"))
}

collect_messages <- function(expr) {
  msgs <- character(0L)
  value <- withCallingHandlers(
    expr,
    message = function(m) {
      msgs <<- c(msgs, cli::ansi_strip(conditionMessage(m)))
      invokeRestart("muffleMessage")
    }
  )
  return(list(value = value, messages = paste(msgs, collapse = "\n")))
}

testthat::test_that("install_packages() installs a request file with the backend's install", {
  stub <- local_definition_stub(
    "stub-inst-request",
    envs = "inst-env",
    backend_describe_definition = function(backend, ...) request_description()
  )
  path <- local_definition_file()
  out <- collect_messages(
    install_packages(env_definition(path), env_name = "inst-env", verbose = "output")
  )
  testthat::expect_identical(out$value$status, 0L)
  call <- stub_calls(stub, "backend_install")[[1L]]
  testthat::expect_null(call$args$packages)
  testthat::expect_identical(call$args$env_file, env_definition(path)$path)
  testthat::expect_identical(call$args$definition, env_definition(path))
  testthat::expect_match(out$messages, "successfully installed", fixed = TRUE)
  testthat::expect_match(out$messages, basename(path), fixed = TRUE)
  describe <- stub_calls(stub, "backend_describe_definition")
  testthat::expect_length(describe, 1L)
  testthat::expect_identical(describe[[1L]]$args$definition, env_definition(path))
  # No warning about the channels of the environment: the file can name
  # its own.
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("install_packages() passes a file the backend cannot tell about", {
  stub <- local_definition_stub("stub-inst-na", envs = "inst-env-na")
  path <- local_definition_file("deps.txt", "pkg")
  res <- install_packages(
    env_definition(path),
    env_name = "inst-env-na",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    stub_calls(stub, "backend_install")[[1L]]$args$env_file,
    env_definition(path)$path
  )
})

testthat::test_that("install_packages() sends a lock to create_env(), before any lock", {
  stub <- local_definition_stub(
    "stub-inst-lock",
    envs = "inst-env",
    backend_describe_definition = function(backend, ...) lock_description()
  )
  testthat::local_mocked_bindings(
    local_env_lock = function(...) stop("local_env_lock() must not be called")
  )
  path <- local_definition_file("explicit.txt", "@EXPLICIT")
  cnd <- catch_error(install_packages(env_definition(path), env_name = "inst-env"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_install_packages_unsupported_definition",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "lock file", fixed = TRUE)
  testthat::expect_match(message, "overwrite = TRUE", fixed = TRUE)
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
})

testthat::test_that("install_packages() aborts for a file the backend cannot read", {
  stub <- local_definition_stub(
    "stub-inst-false",
    envs = "inst-env",
    backend_describe_definition = function(backend, ...) {
      return(list(supported = FALSE, reason = "Not a format I read."))
    }
  )
  testthat::local_mocked_bindings(
    local_env_lock = function(...) stop("local_env_lock() must not be called")
  )
  path <- local_definition_file()
  cnd <- catch_error(install_packages(env_definition(path), env_name = "inst-env"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_install_packages_unsupported_definition",
      "condathis_backend_unsupported",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_match(conditionMessage(cnd), "Not a format I read.", fixed = TRUE)
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
})

testthat::test_that("install_packages() needs a backend install that takes the file", {
  # The rattlerthis formals: backend_install() takes neither `env_file`
  # nor `definition`.
  record <- local_formals_backend("formals-inst")
  fs::dir_create(fs::path(record$root, "envs", "inst-env"))
  path <- local_definition_file()
  cnd <- catch_error(install_packages(
    env_definition(path),
    env_name = "inst-env",
    verbose = "silent"
  ))
  testthat::expect_s3_class(cnd, "condathis_install_packages_unsupported_definition")
  testthat::expect_s3_class(cnd, "condathis_backend_unsupported")
  testthat::expect_match(
    conditionMessage(cnd),
    "does not install packages from a file",
    fixed = TRUE
  )
  testthat::expect_length(record$install, 0L)
  # Package specs still work with it.
  res <- install_packages("pkg", env_name = "inst-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(record$install[[1L]]$packages, "pkg")
})

testthat::test_that("install_packages() gives the path to an install that takes only env_file", {
  seen <- new.env(parent = emptyenv())
  seen$calls <- list()
  record <- local_formals_backend(
    "formals-inst-file",
    backend_install = function(
      backend,
      packages,
      env_name = "condathis-env",
      channels = "conda-forge",
      channel_priority = c("strict", "flexible", "disabled"),
      additional_channels = NULL,
      platform = NULL,
      verbose = c("output", "silent", "cmd", "spinner", "full"),
      env_file = NULL
    ) {
      seen$calls[[length(seen$calls) + 1L]] <- as.list(environment())
      return(list(status = 0L))
    }
  )
  fs::dir_create(fs::path(record$root, "envs", "inst-env"))
  path <- local_definition_file()
  res <- install_packages(env_definition(path), env_name = "inst-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(seen$calls[[1L]]$env_file, env_definition(path)$path)
  testthat::expect_null(seen$calls[[1L]]$packages)
  testthat::expect_false("definition" %in% names(seen$calls[[1L]]))
  # A format or options need the `definition` argument.
  cnd <- catch_error(install_packages(
    env_definition(path, format = "environment-yaml"),
    env_name = "inst-env",
    verbose = "silent"
  ))
  testthat::expect_s3_class(cnd, "condathis_install_packages_unsupported_definition")
  testthat::expect_length(seen$calls, 1L)
})

testthat::test_that("install_packages() and validate_env() take one definition and no specs with it", {
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  path_a <- local_definition_file("a.yml")
  path_b <- local_definition_file("b.yml")
  missing_path <- fs::path(withr::local_tempdir(), "missing.yml")
  for (fn in c("install_packages", "validate_env")) {
    f <- get(fn)
    conflicting_class <- c(
      paste0("condathis_", fn, "_conflicting_args"),
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
    testthat::expect_identical(
      class(catch_error(f(env_definition(path_a), env_definition(path_b)))),
      conflicting_class,
      info = fn
    )
    testthat::expect_identical(
      class(catch_error(f(env_definition(path_a), "zlib"))),
      conflicting_class,
      info = fn
    )
    testthat::expect_identical(
      class(catch_error(f(env_definition(missing_path)))),
      c(
        paste0("condathis_", fn, "_missing_env_file"),
        "condathis_invalid_env_file",
        "condathis_invalid_arg",
        "condathis_error",
        rlang_tail
      ),
      info = fn
    )
    testthat::expect_s3_class(
      catch_error(f(new_env_definition("relative.yml"))),
      "condathis_env_definition_invalid"
    )
  }
})

testthat::test_that("install_packages() from a file keeps the rules for a missing environment", {
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    is_rosetta_running = function() TRUE
  )
  stub <- local_definition_stub(
    "stub-inst-missing",
    backend_describe_definition = function(backend, ...) request_description(),
    backend_can_solve = function(backend, ..., platform) {
      return(identical(platform, "osx-64"))
    }
  )
  path <- local_definition_file()
  cnd <- catch_error(install_packages(env_definition(path), env_name = "no-such-env"))
  testthat::expect_s3_class(cnd, "condathis_install_packages_env_not_found")
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  # The default environment is created empty, then gets the file, for
  # the emulated platform when the file solves only there.
  res <- install_packages(env_definition(path), verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  creates <- stub_calls(stub, "backend_create_env")
  testthat::expect_length(creates, 1L)
  testthat::expect_null(creates[[1L]]$args$env_file)
  install <- stub_calls(stub, "backend_install")[[1L]]
  testthat::expect_identical(install$args$platform, "osx-64")
  testthat::expect_identical(install$args$env_file, env_definition(path)$path)
  solves <- stub_calls(stub, "backend_can_solve")
  testthat::expect_identical(solves[[1L]]$args$definition, env_definition(path))
  testthat::expect_identical(solves[[1L]]$args$env_file, env_definition(path)$path)
})

# --- Existing environments and locks ----------------------------------------

testthat::test_that("create_env() keeps an environment that has exactly the packages of a lock", {
  installed <- definition_pkgs_df("pkg", platform = "linux-64")
  stub <- local_definition_stub(
    "stub-cmp-lock",
    envs = "lock-env",
    backend_list_packages = function(backend, ...) installed,
    backend_describe_definition = function(backend, ...) lock_description(),
    backend_native_platform = function(backend) "linux-64"
  )
  path <- local_definition_file("explicit.txt", "@EXPLICIT")
  out <- collect_messages(
    create_env(env_definition(path), env_name = "lock-env", verbose = "output")
  )
  testthat::expect_identical(out$value$status, 0L)
  testthat::expect_true(is.na(out$value$cmd))
  testthat::expect_match(out$messages, "already has the packages of lock file", fixed = TRUE)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  # Packages that pip installed are left out.
  pip <- definition_pkgs_df("requests", platform = "linux-x86_64")
  pip$channel <- "pypi"
  installed <- rbind(definition_pkgs_df("pkg", platform = "linux-64"), pip)
  res <- create_env(env_definition(path), env_name = "lock-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  # Another version, and a package the lock does not list.
  installed <- definition_pkgs_df(c("pkg", "extra"), platform = "linux-64")
  installed$version[[1L]] <- "2.0"
  cnd <- catch_error(create_env(env_definition(path), env_name = "lock-env"))
  testthat::expect_identical(
    class(cnd),
    c("condathis_create_env_exists", "condathis_error", rlang_tail)
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "pkg-1.0-h0_0", fixed = TRUE)
  testthat::expect_match(message, "pkg-2.0-h0_0", fixed = TRUE)
  testthat::expect_match(message, "extra-1.0-h0_0", fixed = TRUE)
  testthat::expect_match(message, "overwrite = TRUE", fixed = TRUE)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  # A given platform is checked first.
  installed <- definition_pkgs_df("pkg", platform = "osx-arm64")
  cnd <- catch_error(create_env(
    env_definition(path),
    env_name = "lock-env",
    platform = "linux-64"
  ))
  testthat::expect_s3_class(cnd, "condathis_create_env_platform_mismatch")
})

testthat::test_that("create_env() compares only the records for the platform of the lock", {
  installed <- definition_pkgs_df(c("pkg", "shared"), platform = "linux-64")
  installed$platform[[2L]] <- "noarch"
  records <- data.frame(
    name = c("pkg", "pkg", "shared"),
    version = c("1.0", "1.0", "1.0"),
    build_string = c("h0_0", "h9_0", "h0_0"),
    platform = c("linux-64", "osx-arm64", "noarch"),
    stringsAsFactors = FALSE
  )
  stub <- local_definition_stub(
    "stub-cmp-platform",
    envs = "lock-env",
    backend_list_packages = function(backend, ...) installed,
    backend_describe_definition = function(backend, ...) {
      return(lock_description(platforms = c("linux-64", "osx-arm64"), records = records))
    },
    backend_native_platform = function(backend) "linux-64"
  )
  testthat::local_mocked_bindings(get_sys_arch = function() "Linux-x86_64")
  path <- local_definition_file("conda-lock.yml", "version: 1")
  res <- create_env(env_definition(path), env_name = "lock-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  # For osx-arm64, the build differs.
  cnd <- catch_error(create_env(
    env_definition(path),
    env_name = "lock-env",
    platform = "osx-arm64"
  ))
  testthat::expect_s3_class(cnd, "condathis_create_env_platform_mismatch")
})

testthat::test_that("create_env() never compares a request, or a lock without records", {
  value <- request_description()
  stub <- local_definition_stub(
    "stub-cmp-none",
    envs = "exists-env",
    backend_describe_definition = function(backend, ...) value,
    backend_native_platform = function(backend) "linux-64"
  )
  path <- local_definition_file()
  cnd <- catch_error(create_env(env_definition(path), env_name = "exists-env"))
  testthat::expect_s3_class(cnd, "condathis_create_env_exists")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "only with a lock file",
    fixed = TRUE
  )
  value <- lock_description(records = NULL)
  cnd <- catch_error(create_env(env_definition(path), env_name = "exists-env"))
  testthat::expect_s3_class(cnd, "condathis_create_env_exists")
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "does not report",
    fixed = TRUE
  )
  # A record without a build string is not compared either.
  value <- lock_description(records = data.frame(
    name = "pkg",
    version = "1.0",
    build_string = NA_character_,
    platform = "linux-64",
    stringsAsFactors = FALSE
  ))
  cnd <- catch_error(create_env(env_definition(path), env_name = "exists-env"))
  testthat::expect_s3_class(cnd, "condathis_create_env_exists")
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
})

testthat::test_that("lock comparisons name a few differences, then how many more", {
  records <- data.frame(
    name = c("a", "b"),
    version = "1.0",
    build_string = "h0_0",
    platform = "linux-64",
    stringsAsFactors = FALSE
  )
  installed <- definition_pkgs_df(c("A", paste0("x", 1:8)), platform = "linux-64")
  comparison <- compare_lock_records(installed, records, target = "linux-64")
  testthat::expect_false(comparison$satisfied)
  # Names compare in lower case.
  testthat::expect_identical(comparison$missing, "b-1.0-h0_0")
  testthat::expect_length(comparison$unexpected, 8L)
  bullets <- cli::ansi_strip(lock_difference_bullets(comparison))
  testthat::expect_match(bullets[[2L]], "x5-1.0-h0_0", fixed = TRUE)
  testthat::expect_no_match(bullets[[2L]], "x6-1.0-h0_0", fixed = TRUE)
  testthat::expect_match(bullets[[2L]], "and 3 more", fixed = TRUE)
  testthat::expect_match(bullets[[3L]], "linux-64", fixed = TRUE)
  # Without a target, any platform of the lock.
  records$platform[[2L]] <- "osx-arm64"
  comparison <- compare_lock_records(
    definition_pkgs_df("b", platform = "osx-arm64"),
    records
  )
  testthat::expect_true(comparison$satisfied)
  testthat::expect_identical(comparison$target, "osx-arm64")
  testthat::expect_true(lock_records_comparable(lock_description(records = records)))
  testthat::expect_false(lock_records_comparable(request_description()))
  testthat::expect_identical(lock_targets(records, NA_character_), c("linux-64", "osx-arm64"))
  testthat::expect_identical(lock_targets(records[0L, ], NA_character_), NA_character_)
})

# --- validate_env() ---------------------------------------------------------

testthat::test_that("validate_env() compares an environment with the records of a lock", {
  installed <- definition_pkgs_df("pkg", platform = "linux-64")
  records <- data.frame(
    name = c("pkg", "pkg"),
    version = c("1.0", "1.0"),
    build_string = c("h0_0", "h1_0"),
    platform = c("linux-64", "osx-arm64"),
    stringsAsFactors = FALSE
  )
  stub <- local_definition_stub(
    "stub-val-lock",
    envs = "lock-env",
    backend_list_packages = function(backend, ...) installed,
    backend_describe_definition = function(backend, ...) {
      return(lock_description(platforms = c("linux-64", "osx-arm64"), records = records))
    }
  )
  path <- local_definition_file("conda-lock.yml", "version: 1")
  res <- withVisible(validate_env(env_definition(path), env_name = "lock-env"))
  testthat::expect_true(res$value)
  testthat::expect_false(res$visible)
  out <- collect_messages(
    validate_env(env_definition(path), env_name = "lock-env", verbose = "output")
  )
  testthat::expect_match(out$messages, "has the packages of lock file", fixed = TRUE)
  # A given platform is compared first.
  res <- validate_env(
    env_definition(path),
    env_name = "lock-env",
    platform = "osx-arm64",
    error = "continue"
  )
  testthat::expect_false(res)
  testthat::expect_identical(attr(res, "reason"), "platform_mismatch")
  # A package more.
  installed <- definition_pkgs_df(c("pkg", "extra"), platform = "linux-64")
  res <- validate_env(env_definition(path), env_name = "lock-env", error = "continue")
  testthat::expect_false(res)
  testthat::expect_identical(attr(res, "reason"), "unsatisfied")
  testthat::expect_identical(attr(res, "unsatisfied"), character(0L))
  testthat::expect_identical(attr(res, "unexpected"), "extra-1.0-h0_0")
  cnd <- catch_error(validate_env(env_definition(path), env_name = "lock-env"))
  testthat::expect_identical(
    class(cnd),
    c("condathis_validate_env_unsatisfied", "condathis_error", rlang_tail)
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "extra-1.0-h0_0", fixed = TRUE)
  testthat::expect_match(message, "linux-64", fixed = TRUE)
  # A missing environment: every record is unsatisfied.
  res <- validate_env(env_definition(path), env_name = "no-env", error = "continue")
  testthat::expect_identical(attr(res, "reason"), "env_not_found")
  testthat::expect_identical(attr(res, "unsatisfied"), c("pkg-1.0-h0_0", "pkg-1.0-h1_0"))
  # A platform that the lock does not list.
  cnd <- catch_error(validate_env(
    env_definition(path),
    env_name = "lock-env",
    platform = "win-64"
  ))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_validate_env_unsupported_definition",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_length(stub_calls(stub, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(stub, "backend_install"), 0L)
})

testthat::test_that("validate_env() aborts for a definition it cannot compare", {
  value <- request_description()
  stub <- local_definition_stub(
    "stub-val-request",
    envs = "val-env",
    backend_describe_definition = function(backend, ...) value
  )
  path <- local_definition_file()
  unsupported_class <- c(
    "condathis_validate_env_unsupported_definition",
    "condathis_invalid_arg",
    "condathis_error",
    rlang_tail
  )
  for (error in c("cancel", "continue")) {
    # Also for a missing environment: the definition is checked first.
    for (env_name in c("val-env", "no-env")) {
      cnd <- catch_error(validate_env(
        env_definition(path),
        env_name = env_name,
        error = error
      ))
      testthat::expect_identical(class(cnd), unsupported_class, info = env_name)
    }
  }
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "only with a lock file",
    fixed = TRUE
  )
  value <- list(supported = NA)
  testthat::expect_identical(
    class(catch_error(validate_env(env_definition(path), env_name = "val-env"))),
    unsupported_class
  )
  value <- list(supported = FALSE, reason = "Not a format I read.")
  cnd <- catch_error(validate_env(env_definition(path), env_name = "val-env"))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_validate_env_unsupported_definition",
      "condathis_backend_unsupported",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  testthat::expect_match(conditionMessage(cnd), "Not a format I read.", fixed = TRUE)
  testthat::expect_length(stub_calls(stub, "backend_list_packages"), 0L)
})

# --- Routing with method = "auto" -------------------------------------------

testthat::test_that("method = 'auto' gives a new environment to the first backend that reads the definition", {
  first <- local_stub_backend(
    "stub-route-a",
    backend_describe_definition = function(backend, ...) {
      return(list(supported = FALSE, reason = "Not mine."))
    }
  )
  second <- local_stub_backend("stub-route-b")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-route-a", "stub-route-b")
  )
  path <- local_definition_file()
  res <- create_env(env_definition(path), env_name = "routed", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(stub_calls(first, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(second, "backend_create_env"), 1L)
  # Asked once, before and under the environment lock.
  testthat::expect_length(stub_calls(first, "backend_describe_definition"), 1L)
  testthat::expect_identical(
    read_backend_marker(fs::path(second$root, "envs", "routed"))$backend,
    "stub-route-b"
  )
  # An explicit method is never rerouted.
  cnd <- catch_error(create_env(
    env_definition(path),
    env_name = "routed-2",
    method = "stub-route-a"
  ))
  testthat::expect_s3_class(cnd, "condathis_create_env_unsupported_definition")
  testthat::expect_match(conditionMessage(cnd), "Not mine.", fixed = TRUE)
  # An existing environment keeps its backend.
  fs::dir_create(fs::path(first$root, "envs", "owned-by-a"))
  cnd <- catch_error(create_env(
    env_definition(path),
    env_name = "owned-by-a",
    overwrite = TRUE
  ))
  testthat::expect_s3_class(cnd, "condathis_create_env_unsupported_definition")
  testthat::expect_length(stub_calls(second, "backend_create_env"), 1L)
  testthat::expect_length(stub_calls(first, "backend_create_env"), 0L)
})

testthat::test_that("method = 'auto' skips a backend that cannot get the format of a definition", {
  record <- local_formals_backend("formals-route")
  stub <- local_stub_backend("stub-route-dots")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("formals-route", "stub-route-dots")
  )
  path <- local_definition_file("ci.lock")
  res <- create_env(
    env_definition(path, format = "x-format"),
    env_name = "routed-format",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_length(record$create, 0L)
  testthat::expect_identical(
    stub_calls(stub, "backend_create_env")[[1L]]$args$definition$format,
    "x-format"
  )
  # A plain definition stays with the first backend.
  create_env(env_definition(path), env_name = "routed-plain", verbose = "silent")
  testthat::expect_length(record$create, 1L)
})

testthat::test_that("method = 'auto' aborts when no available backend reads the definition", {
  first <- local_stub_backend(
    "stub-none-a",
    backend_describe_definition = function(backend, ...) {
      return(list(supported = FALSE, reason = "Not mine."))
    }
  )
  second <- local_stub_backend(
    "stub-none-b",
    backend_describe_definition = function(backend, ...) {
      return(list(supported = FALSE, reason = "Nor mine."))
    }
  )
  # Not available, so not tried, but its formats name it in the hint.
  third <- local_stub_backend(
    "stub-none-c",
    available = FALSE,
    backend_definition_formats = function(backend) c("my-format", "other")
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-none-a", "stub-none-b", "stub-none-c"),
    local_env_lock = function(...) stop("local_env_lock() must not be called")
  )
  path <- local_definition_file("env.custom")
  cnd <- catch_error(create_env(
    env_definition(path, format = "my-format"),
    env_name = "nowhere"
  ))
  testthat::expect_identical(
    class(cnd),
    c(
      "condathis_create_env_unsupported_definition",
      "condathis_backend_unsupported",
      "condathis_invalid_arg",
      "condathis_error",
      rlang_tail
    )
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "No available backend", fixed = TRUE)
  testthat::expect_match(message, "stub-none-a: Not mine.", fixed = TRUE)
  testthat::expect_match(message, "stub-none-b: Nor mine.", fixed = TRUE)
  testthat::expect_match(message, "is read by: stub-none-c", fixed = TRUE)
  testthat::expect_length(stub_calls(first, "backend_create_env"), 0L)
  testthat::expect_length(stub_calls(second, "backend_create_env"), 0L)
  testthat::expect_identical(backend_definition_formats(third$backend), c("my-format", "other"))
})

testthat::test_that("registered S3 methods match the generics, and optional arguments reach the function", {
  ns <- asNamespace("condathis")
  for (generic in c("backend_create_env", "backend_install", "backend_can_solve")) {
    method <- utils::getS3method(generic, "condathis_backend_micromamba", envir = ns)
    # R CMD check compares a method with its generic.
    testthat::expect_identical(formals(method), formals(get(generic)), info = generic)
  }
  # A function without optional arguments is its own method, as
  # rattlerthis's tests require.
  record <- local_formals_backend("formals-s3")
  backend <- get_backend("formals-s3")
  testthat::expect_identical(
    utils::getS3method("backend_create_env", class(backend)[[1L]], envir = ns),
    backend$backend_create_env
  )
  # The wrapper forwards every argument, a missing one too.
  seen <- new.env(parent = emptyenv())
  fn <- function(
    backend,
    packages = NULL,
    env_file = NULL,
    channels = "conda-forge",
    channel_priority = c("strict", "flexible", "disabled"),
    additional_channels = NULL,
    platform,
    definition = NULL
  ) {
    seen$platform_missing <- missing(platform)
    seen$definition <- definition
    return(identical(channels, "x"))
  }
  method <- backend_s3_method(fn, "backend_can_solve")
  testthat::expect_identical(formals(method), formals(backend_can_solve))
  testthat::expect_true(method(NULL, channels = "x"))
  testthat::expect_true(seen$platform_missing)
  # backend_call() gives `definition` only to a function that takes it.
  stub_like <- structure(list(backend_can_solve = fn), class = "x")
  backend_call(
    "backend_can_solve",
    stub_like,
    platform = "linux-64",
    .optional = list(definition = "d")
  )
  testthat::expect_identical(seen$definition, "d")
  testthat::expect_false(seen$platform_missing)
  testthat::expect_identical(
    backend_call(
      "backend_can_solve",
      structure(list(), class = "condathis_backend"),
      platform = "linux-64",
      .optional = list(definition = "d")
    ),
    NA
  )
})
