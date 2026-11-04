# The life cycle of the environment directory of create_env(), which the
# front end owns for every backend (see with_env_dir_replacement()): a
# stale directory is deleted, an existing environment is moved aside and
# moved back when the create fails, and a failed new environment is
# deleted. The tests run on the micromamba backend and on a stub backend.
# Most of them replace a fake environment without micromamba; the last
# ones use a real micromamba with the local channel.

# --- Exact environment directories -----------------------------------------

testthat::test_that("is_exact_env_dir accepts only the directory of that exact name", {
  # Regression test: `delete_stale_env_dir()` checked only the lexical
  # path. On Windows `<root>/envs/myenv.` opens `<root>/envs/myenv`, so the
  # cleanup for "myenv." deleted the real "myenv". The real path that the
  # file system returns must end with the requested name, as stored.
  envs <- "C:/Users/me/AppData/Local/R/data/R/condathis/envs"
  myenv <- paste0(envs, "/myenv")

  testthat::expect_true(is_exact_env_dir(myenv, envs, "myenv"))
  # Trailing separators and backslashes, as Windows APIs can return them.
  testthat::expect_true(
    is_exact_env_dir(paste0(myenv, "/"), paste0(envs, "/"), "myenv")
  )
  testthat::expect_true(
    is_exact_env_dir(
      gsub("/", "\\\\", myenv),
      gsub("/", "\\\\", envs),
      "myenv"
    )
  )

  # Windows drops the trailing dot of "myenv.".
  testthat::expect_false(is_exact_env_dir(myenv, envs, "myenv."))
  # A case-insensitive lookup (Windows, macOS) opens "MyEnv" for "myenv".
  testthat::expect_false(
    is_exact_env_dir(paste0(envs, "/MyEnv"), envs, "myenv")
  )
  # A Windows 8.3 short name opens the long name.
  testthat::expect_false(is_exact_env_dir(myenv, envs, "MYENV~1"))
  # A symbolic link opens a directory with the same name elsewhere.
  testthat::expect_false(
    is_exact_env_dir("D:/elsewhere/myenv", envs, "myenv")
  )
  # A path that could not be resolved is never taken for the environment.
  testthat::expect_false(is_exact_env_dir(NA_character_, envs, "myenv"))
  testthat::expect_false(is_exact_env_dir(myenv, NA_character_, "myenv"))
})

testthat::test_that("delete_stale_env_dir keeps the directory another name resolves to", {
  # Simulates the Windows resolution of the original failure on every OS:
  # "myenv." passes every lexical check, but its path opens "myenv". The
  # name check is disabled here, so only the real-path check can stop the
  # deletion.
  backend <- micromamba_backend()
  envs_dir <- fs::path(install_dir_for_backend(backend), "envs")
  real_env_dir <- fs::path(envs_dir, "condathis-stale-guard-env")
  marker <- fs::path(real_env_dir, "marker.txt")
  fs::dir_create(real_env_dir)
  withr::defer(fs::dir_delete(real_env_dir))
  fs::file_create(marker)

  testthat::local_mocked_bindings(
    is_valid_env_name = function(env_name) TRUE,
    real_path_or_na = function(path) {
      path <- as.character(path)
      if (endsWith(path, "condathis-stale-guard-env.")) {
        path <- sub("\\.$", "", path)
      }
      return(as.character(fs::path_real(path)))
    }
  )

  testthat::expect_error(
    delete_stale_env_dir(backend, "condathis-stale-guard-env."),
    class = "condathis_unsafe_env_dir_delete"
  )
  testthat::expect_true(fs::file_exists(marker))
})

testthat::test_that("delete_stale_env_dir refuses a name that differs only in case", {
  # On Windows and macOS (case-insensitive by default) `<root>/envs/caseenv`
  # opens `<root>/envs/CaseEnv`. micromamba lists "CaseEnv", so "caseenv"
  # looked absent and its stale-directory cleanup deleted "CaseEnv". On
  # Linux the path does not exist and cannot be resolved, which is refused
  # too.
  backend <- micromamba_backend()
  envs_dir <- fs::path(install_dir_for_backend(backend), "envs")
  env_dir <- fs::path(envs_dir, "CondathisCaseEnv")
  marker <- fs::path(env_dir, "marker.txt")
  fs::dir_create(env_dir)
  withr::defer(fs::dir_delete(env_dir))
  fs::file_create(marker)

  testthat::expect_error(
    delete_stale_env_dir(backend, "condathiscaseenv"),
    class = "condathis_unsafe_env_dir_delete"
  )
  testthat::expect_true(fs::file_exists(marker))
})

testthat::test_that("delete_stale_env_dir still deletes the stale directory of that exact name", {
  backend <- micromamba_backend()
  env_dir <- fs::path(
    install_dir_for_backend(backend),
    "envs",
    "condathis-stale-exact-env"
  )
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  withr::defer(if (fs::dir_exists(env_dir)) fs::dir_delete(env_dir))

  delete_stale_env_dir(backend, "condathis-stale-exact-env")
  testthat::expect_false(fs::dir_exists(env_dir))
})

testthat::test_that("delete_stale_env_dir() refusals have the root class", {
  testthat::expect_error(
    delete_stale_env_dir(micromamba_backend(), "../escape"),
    class = "condathis_error"
  )
})

testthat::test_that("the trash directory is not an environment", {
  testthat::expect_false(is_valid_env_name(env_trash_name()))
  # The cheap probe skips it.
  root <- withr::local_tempdir()
  fs::dir_create(fs::path(root, "envs", env_trash_name()))
  testthat::local_mocked_bindings(get_condathis_path = function() root)
  testthat::expect_false(backend_has_env_dirs("micromamba"))
  fs::dir_create(fs::path(root, "envs", "real-env"))
  testthat::expect_true(backend_has_env_dirs("micromamba"))
})

testthat::test_that("copies go into the trash also after fs::file_temp_push()", {
  # Regression test: `fs::file_temp()` returned a pushed path, whatever its
  # directory, so the environment could be moved outside the trash.
  backend <- micromamba_backend()
  pushed <- file.path(withr::local_tempdir(), "pushed")
  fs::file_temp_push(pushed)
  withr::defer(try(fs::file_temp_pop(), silent = TRUE))
  path <- new_trash_path(backend)
  testthat::expect_identical(
    as.character(fs::path_dir(path)),
    as.character(env_trash_dir(backend))
  )
  testthat::expect_false(identical(path, pushed))
})

# --- with_env_dir_replacement(), on both kinds of backend ------------------

lifecycle_kinds <- c("micromamba", "stub")

# The backend of `kind`: the micromamba backend, or a stub that keeps its
# environments in the root that condathis assigns. The existence check
# reads the file system, so no micromamba process starts: an environment
# is a directory with `conda-meta/history`. Only the micromamba backend is
# asked whether its binary lives in the environment.
local_lifecycle_backend <- function(kind, envir = parent.frame()) {
  if (identical(kind, "micromamba")) {
    backend <- micromamba_backend()
  } else {
    backend <- local_stub_backend(
      "stub-lifecycle",
      default_root = TRUE,
      envir = envir
    )$backend
  }
  testthat::local_mocked_bindings(
    backend_env_exists = function(backend, env_name, verbose = "silent") {
      history <- fs::path(
        env_dir_for_backend(backend, env_name),
        "conda-meta",
        "history"
      )
      return(isTRUE(unname(fs::file_exists(history))))
    },
    micromamba_binary_in_env_dir = function(backend, env_name) {
      if (isFALSE(inherits(backend, "condathis_backend_micromamba"))) {
        stop("Only the micromamba backend is asked for its binary.")
      }
      return(NULL)
    },
    .env = envir
  )
  return(backend)
}

# A fake environment `env_name` of `backend`, with `old-file` in it.
# Deleted at the end of the test, with the trash.
local_fake_env <- function(backend, env_name, envir = parent.frame()) {
  env_dir <- env_dir_for_backend(backend, env_name)
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  fs::file_create(fs::path(env_dir, "conda-meta", "history"))
  fs::file_create(fs::path(env_dir, "old-file"))
  local_env_dir_cleanup(backend, env_name, envir = envir)
  return(env_dir)
}

local_env_dir_cleanup <- function(backend, env_name, envir = parent.frame()) {
  env_dir <- env_dir_for_backend(backend, env_name)
  trash_dir <- env_trash_dir(backend)
  withr::defer(
    {
      if (fs::dir_exists(env_dir)) {
        fs::dir_delete(env_dir)
      }
      if (fs::dir_exists(trash_dir)) fs::dir_delete(trash_dir)
    },
    envir = envir
  )
  return(invisible(env_dir))
}

# What a successful create leaves: a new environment with `file` in it.
make_new_env <- function(env_dir, file = "new-file") {
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  fs::file_create(fs::path(env_dir, "conda-meta", "history"))
  fs::file_create(fs::path(env_dir, file))
  return(list(status = 0L))
}

# Run `create(env_dir)` as create_env() runs the backend's create.
replace_with <- function(backend, env_name, create) {
  env_dir <- env_dir_for_backend(backend, env_name)
  return(with_env_dir_replacement(
    backend,
    env_name = env_name,
    expr = create(env_dir)
  ))
}

# The entries of the trash directory of `create_env(overwrite = TRUE)`.
trash_entries <- function(backend = micromamba_backend()) {
  trash_dir <- env_trash_dir(backend)
  if (isFALSE(fs::dir_exists(trash_dir))) {
    return(character(0L))
  }
  return(as.character(fs::dir_ls(trash_dir, all = TRUE)))
}

testthat::test_that("a successful replacement deletes the old environment", {
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-replace-discard-env"
    env_dir <- local_fake_env(backend, env_name)
    seen_free <- NA
    res <- replace_with(backend, env_name, function(env_dir) {
      # The backend gets a free environment directory.
      seen_free <<- isFALSE(fs::dir_exists(env_dir))
      return(make_new_env(env_dir))
    })
    testthat::expect_identical(res$status, 0L, info = kind)
    testthat::expect_true(seen_free, info = kind)
    testthat::expect_true(fs::file_exists(fs::path(env_dir, "new-file")))
    testthat::expect_false(fs::file_exists(fs::path(env_dir, "old-file")))
    testthat::expect_length(trash_entries(backend), 0L)
  }
})

testthat::test_that("a failed replacement moves the old environment back", {
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-replace-restore-env"
    env_dir <- local_fake_env(backend, env_name)
    # A handler of the caller already sees the old environment.
    seen_in_handler <- NA
    testthat::expect_error(
      withCallingHandlers(
        replace_with(backend, env_name, function(env_dir) {
          # The old environment is out of the way while the backend runs.
          testthat::expect_false(fs::dir_exists(env_dir))
          fs::dir_create(env_dir)
          fs::file_create(fs::path(env_dir, "partial-file"))
          stop("create failed")
        }),
        error = function(cnd) {
          seen_in_handler <<- fs::file_exists(fs::path(env_dir, "old-file"))
        }
      ),
      "create failed",
      fixed = TRUE
    )
    testthat::expect_true(seen_in_handler, info = kind)
    testthat::expect_true(fs::file_exists(fs::path(env_dir, "old-file")))
    testthat::expect_false(fs::file_exists(fs::path(env_dir, "partial-file")))
    testthat::expect_length(trash_entries(backend), 0L)
  }
})

testthat::test_that("an interrupted replacement moves the old environment back", {
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-replace-interrupt-env"
    env_dir <- local_fake_env(backend, env_name)
    res <- tryCatch(
      replace_with(backend, env_name, function(env_dir) {
        fs::dir_create(env_dir)
        fs::file_create(fs::path(env_dir, "partial-file"))
        rlang::interrupt()
      }),
      interrupt = function(cnd) "interrupted"
    )
    testthat::expect_identical(res, "interrupted", info = kind)
    testthat::expect_true(fs::file_exists(fs::path(env_dir, "old-file")))
    testthat::expect_false(fs::file_exists(fs::path(env_dir, "partial-file")))
    testthat::expect_length(trash_entries(backend), 0L)
  }
})

testthat::test_that("an interrupt while the old copy is deleted keeps the new environment", {
  # Regression test: the restore of `on.exit()` still saw the set-aside
  # path, deleted the new environment and moved back a half-deleted copy.
  testthat::local_mocked_bindings(
    discard_set_aside_env_dir = function(set_aside) rlang::interrupt()
  )
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-replace-discard-interrupt-env"
    env_dir <- local_fake_env(backend, env_name)
    res <- tryCatch(
      replace_with(backend, env_name, make_new_env),
      interrupt = function(cnd) "interrupted"
    )
    testthat::expect_identical(res, "interrupted", info = kind)
    testthat::expect_true(fs::file_exists(fs::path(env_dir, "new-file")))
    testthat::expect_false(fs::file_exists(fs::path(env_dir, "old-file")))
  }
})

testthat::test_that("an environment that cannot be moved aside is left as it was", {
  # On Windows, a rename fails while a program uses a file in the
  # environment. The backend must not run then: micromamba would delete
  # part of it. Only the micromamba backend keeps the class that names it.
  testthat::local_mocked_bindings(
    rename_path = function(from, to) "The process cannot access the file."
  )
  expected <- list(
    micromamba = c(
      "condathis_micromamba_env_set_aside_failed",
      "condathis_env_set_aside_failed"
    ),
    stub = "condathis_env_set_aside_failed"
  )
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-replace-busy-env"
    env_dir <- local_fake_env(backend, env_name)
    cnd <- rlang::catch_cnd(
      replace_with(backend, env_name, function(env_dir) {
        stop("The backend must not run.")
      }),
      classes = "error"
    )
    testthat::expect_identical(
      class(cnd),
      c(
        expected[[kind]],
        "condathis_error",
        "rlang_error",
        "error",
        "condition"
      ),
      info = kind
    )
    message <- cli::ansi_strip(conditionMessage(cnd))
    testthat::expect_match(
      message,
      "The environment is unchanged.",
      fixed = TRUE
    )
    testthat::expect_match(
      message,
      "The process cannot access the file.",
      fixed = TRUE
    )
    testthat::expect_true(fs::file_exists(fs::path(env_dir, "old-file")))
    testthat::expect_length(trash_entries(backend), 0L)
  }
})

testthat::test_that("an environment that cannot be moved back is kept and named in the error", {
  real_rename_path <- rename_path
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-replace-stuck-env"
    local_fake_env(backend, env_name)
    calls <- 0L
    testthat::local_mocked_bindings(
      rename_path = function(from, to) {
        calls <<- calls + 1L
        if (calls > 1L) {
          return("Access is denied.")
        }
        return(real_rename_path(from, to))
      }
    )

    # No warning: a warning signaled while the error is on its way can
    # replace it (for example under `options(warn = 2)`).
    warnings <- list()
    cnd <- withCallingHandlers(
      rlang::catch_cnd(
        replace_with(backend, env_name, function(env_dir) {
          stop("create failed")
        }),
        classes = "error"
      ),
      warning = function(cnd) {
        warnings[[length(warnings) + 1L]] <<- cnd
        invokeRestart("muffleWarning")
      }
    )
    testthat::expect_length(warnings, 0L)
    testthat::expect_s3_class(cnd, "simpleError")
    testthat::expect_s3_class(cnd, "condathis_env_not_restored")
    kept <- trash_entries(backend)
    testthat::expect_length(kept, 1L)
    testthat::expect_true(fs::file_exists(fs::path(kept, "old-file")))
    testthat::expect_identical(cnd$kept_env_dir, kept)
    message <- conditionMessage(cnd)
    testthat::expect_match(message, "create failed", fixed = TRUE)
    testthat::expect_match(message, "kept in", fixed = TRUE)
    testthat::expect_match(message, basename(kept), fixed = TRUE)
    testthat::expect_match(message, "Access is denied.", fixed = TRUE)

    # The next replacement keeps that copy: it has no `.discard` marker.
    testthat::local_mocked_bindings(rename_path = real_rename_path)
    local_fake_env(backend, "condathis-replace-other-env")
    replace_with(backend, "condathis-replace-other-env", make_new_env)
    testthat::expect_true(fs::file_exists(fs::path(kept, "old-file")))
  }
})

testthat::test_that("an interrupted replacement that cannot be moved back warns", {
  real_rename_path <- rename_path
  expected <- list(
    micromamba = c(
      "condathis_micromamba_env_restore_failed",
      "condathis_env_restore_failed"
    ),
    stub = "condathis_env_restore_failed"
  )
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-replace-stuck-interrupt-env"
    local_fake_env(backend, env_name)
    calls <- 0L
    testthat::local_mocked_bindings(
      rename_path = function(from, to) {
        calls <<- calls + 1L
        if (calls > 1L) {
          return("Access is denied.")
        }
        return(real_rename_path(from, to))
      }
    )

    warnings <- list()
    res <- withCallingHandlers(
      tryCatch(
        replace_with(backend, env_name, function(env_dir) {
          rlang::interrupt()
        }),
        interrupt = function(cnd) "interrupted"
      ),
      condathis_env_restore_failed = function(cnd) {
        warnings[[length(warnings) + 1L]] <<- cnd
        invokeRestart("muffleWarning")
      }
    )
    testthat::expect_identical(res, "interrupted", info = kind)
    testthat::expect_length(warnings, 1L)
    testthat::expect_identical(
      class(warnings[[1L]]),
      c(
        expected[[kind]],
        "condathis_warning",
        "rlang_warning",
        "warning",
        "condition"
      ),
      info = kind
    )
    kept <- trash_entries(backend)
    testthat::expect_length(kept, 1L)
    testthat::expect_identical(warnings[[1L]]$kept_env_dir, kept)
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(warnings[[1L]])),
      basename(kept),
      fixed = TRUE
    )
    testthat::local_mocked_bindings(rename_path = real_rename_path)
  }
})

testthat::test_that("a replacement deletes only the old copies marked for deletion", {
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-replace-purge-env"
    local_fake_env(backend, env_name)
    trash_dir <- env_trash_dir(backend)
    # Left by a delete that failed after a successful create.
    discarded <- fs::path(trash_dir, "old-copy")
    fs::dir_create(fs::path(discarded, "conda-meta"))
    fs::file_create(paste0(discarded, ".discard"))
    # In use by a replacement in another process, or not restored.
    in_use <- fs::path(trash_dir, "in-use-copy")
    fs::dir_create(fs::path(in_use, "conda-meta"))

    replace_with(backend, env_name, make_new_env)
    testthat::expect_false(fs::dir_exists(discarded), info = kind)
    testthat::expect_false(fs::file_exists(paste0(discarded, ".discard")))
    testthat::expect_true(fs::dir_exists(in_use), info = kind)
  }
})

testthat::test_that("a failed or interrupted create of a new environment deletes what it left", {
  # Regression test: micromamba writes `conda-meta/history` before the
  # downloads, so a download error left an "environment", and the identical
  # retry aborted with `condathis_create_env_exists`.
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-new-env-fail-env"
    env_dir <- local_env_dir_cleanup(backend, env_name)
    # Deleted before the caller's handlers run.
    seen_in_handler <- NA
    testthat::expect_error(
      withCallingHandlers(
        replace_with(backend, env_name, function(env_dir) {
          make_new_env(env_dir)
          stop("create failed")
        }),
        error = function(cnd) {
          seen_in_handler <<- fs::dir_exists(env_dir)
        }
      ),
      "create failed",
      fixed = TRUE
    )
    testthat::expect_false(seen_in_handler, info = kind)
    testthat::expect_false(fs::dir_exists(env_dir))

    res <- tryCatch(
      replace_with(backend, env_name, function(env_dir) {
        make_new_env(env_dir)
        rlang::interrupt()
      }),
      interrupt = function(cnd) "interrupted"
    )
    testthat::expect_identical(res, "interrupted", info = kind)
    testthat::expect_false(fs::dir_exists(env_dir))

    replace_with(backend, env_name, make_new_env)
    testthat::expect_true(
      fs::file_exists(fs::path(env_dir, "conda-meta", "history"))
    )
    testthat::expect_length(trash_entries(backend), 0L)
  }
})

testthat::test_that("a directory that is not an environment is deleted before the create", {
  # A failed create can leave a directory without `conda-meta/history`, as
  # micromamba does for a non-native platform. The backend never sees it.
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-stale-dir-env"
    env_dir <- local_env_dir_cleanup(backend, env_name)
    fs::dir_create(env_dir)
    fs::file_create(fs::path(env_dir, "stale-file"))
    seen_free <- NA
    replace_with(backend, env_name, function(env_dir) {
      seen_free <<- isFALSE(fs::dir_exists(env_dir))
      return(make_new_env(env_dir))
    })
    testthat::expect_true(seen_free, info = kind)
    testthat::expect_false(fs::file_exists(fs::path(env_dir, "stale-file")))
    testthat::expect_true(fs::file_exists(fs::path(env_dir, "new-file")))
  }
})

testthat::test_that("a failed existence check stops the replacement and changes nothing", {
  # Rule R5: read as "absent", the check would delete a real environment as
  # a stale directory. The backend's error goes on unchanged, so that
  # with_backend_errors() in create_env() gives it the classes of a failed
  # create, as micromamba's own replacement code did.
  for (kind in lifecycle_kinds) {
    backend <- local_lifecycle_backend(kind)
    env_name <- "condathis-replace-probe-env"
    env_dir <- local_fake_env(backend, env_name)
    testthat::local_mocked_bindings(
      backend_env_exists = function(...) {
        rlang::abort("listing failed", class = "stub_listing_failed")
      }
    )
    cnd <- rlang::catch_cnd(
      replace_with(backend, env_name, function(env_dir) {
        stop("The backend must not run.")
      }),
      classes = "error"
    )
    testthat::expect_s3_class(cnd, "stub_listing_failed")
    testthat::expect_true(fs::file_exists(fs::path(env_dir, "old-file")))
    testthat::expect_length(trash_entries(backend), 0L)

    # A value that is not TRUE or FALSE is not read as "absent" either.
    testthat::local_mocked_bindings(backend_env_exists = function(...) "yes")
    cnd <- rlang::catch_cnd(
      replace_with(backend, env_name, function(env_dir) {
        stop("The backend must not run.")
      }),
      classes = "error"
    )
    testthat::expect_s3_class(cnd, "condathis_backend_invalid_return")
    testthat::expect_true(fs::file_exists(fs::path(env_dir, "old-file")))
    testthat::expect_length(trash_entries(backend), 0L)
  }
})

testthat::test_that("micromamba_binary_in_env_dir() finds a micromamba inside the environment", {
  backend <- micromamba_backend()
  env_name <- "condathis-binary-probe-env"
  env_dir <- env_dir_for_backend(backend, env_name)
  fs::dir_create(fs::path(env_dir, "bin"))
  withr::defer(fs::dir_delete(env_dir))
  binary <- fs::path(env_dir, "bin", "micromamba")
  fs::file_create(binary)

  testthat::local_mocked_bindings(get_best_micromamba_path = function() binary)
  testthat::expect_identical(
    micromamba_binary_in_env_dir(backend, env_name),
    "bin/micromamba"
  )
  testthat::expect_null(
    micromamba_binary_in_env_dir(backend, "condathis-binary-other-env")
  )
  testthat::local_mocked_bindings(get_best_micromamba_path = function() NULL)
  testthat::expect_null(micromamba_binary_in_env_dir(backend, env_name))
})

testthat::test_that("a replacement runs a micromamba that lives in the environment from its new place", {
  # Only for the micromamba backend: local_lifecycle_backend() fails the
  # test when another backend is asked for the binary.
  backend <- local_lifecycle_backend("micromamba")
  env_name <- "condathis-replace-binary-env"
  local_fake_env(backend, env_name)
  testthat::local_mocked_bindings(
    micromamba_binary_in_env_dir = function(backend, env_name) "bin/micromamba"
  )
  withr::local_options(condathis.micromamba_path = NULL)
  seen_path <- NULL
  replace_with(backend, env_name, function(env_dir) {
    seen_path <<- getOption("condathis.micromamba_path")
    return(make_new_env(env_dir))
  })
  testthat::expect_match(seen_path, "/bin/micromamba$")
  testthat::expect_match(seen_path, env_trash_name(), fixed = TRUE)
  testthat::expect_null(getOption("condathis.micromamba_path"))

  stub <- local_lifecycle_backend("stub")
  local_fake_env(stub, env_name)
  seen_path <- "unset"
  replace_with(stub, env_name, function(env_dir) {
    seen_path <<- getOption("condathis.micromamba_path")
    return(make_new_env(env_dir))
  })
  testthat::expect_null(seen_path)
})

# --- create_env() and the life cycle ----------------------------------------

testthat::test_that("create_env() reports an environment it could not move back", {
  # The wrapper keeps the class and the field of the backend's error, so a
  # handler of condathis_create_env_failed finds the kept copy.
  kept <- list(path = "/root/envs/#trash/1a2b", target = "/t", reason = "")
  cnd <- rlang::catch_cnd(
    with_backend_errors(
      stop(note_kept_env_dir(simpleError("solve failed"), kept, "e")),
      fn = "create_env",
      backend_name = "micromamba",
      action = "create environment 'e'"
    ),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_create_env_failed")
  testthat::expect_s3_class(cnd, "condathis_env_not_restored")
  testthat::expect_identical(cnd$kept_env_dir, kept$path)
})

# A stub backend that is the only backend condathis sees, with its
# environments in the root that condathis assigns. Its create records
# whether the environment directory was free, and runs `create(env_dir)`
# when one is set in `state`.
local_create_stub <- function(name, envir = parent.frame()) {
  state <- new.env(parent = emptyenv())
  state$free <- logical(0L)
  state$create <- make_new_env
  stub <- local_stub_backend(
    name,
    default_root = TRUE,
    backend_create_env = function(backend, env_name = "condathis-env", ...) {
      env_dir <- fs::path(backend_root_dir(name), "envs", env_name)
      state$free <- c(state$free, isFALSE(fs::dir_exists(env_dir)))
      return(state$create(env_dir))
    },
    envir = envir
  )
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() name,
    .env = envir
  )
  stub$state <- state
  return(stub)
}

testthat::test_that("create_env(overwrite = TRUE) gives every backend a free directory and keeps the old environment on failure", {
  stub <- local_create_stub("stub-lifecycle-create")
  create_env(env_name = "life-env", verbose = "silent")
  env_dir <- get_env_dir("life-env")
  fs::file_create(fs::path(env_dir, "old-file"))

  res <- create_env(env_name = "life-env", overwrite = TRUE, verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(stub$state$free, c(TRUE, TRUE))
  testthat::expect_false(fs::file_exists(fs::path(env_dir, "old-file")))
  testthat::expect_identical(
    read_backend_marker(env_dir)$backend,
    "stub-lifecycle-create"
  )

  # A failed create moves the old environment back, before the caller's
  # handlers run.
  fs::file_create(fs::path(env_dir, "old-file"))
  stub$state$create <- function(env_dir) {
    make_new_env(env_dir, file = "partial-file")
    rlang::abort("solve failed", class = "stub_solve_failed")
  }
  seen_in_handler <- NA
  cnd <- rlang::catch_cnd(
    withCallingHandlers(
      create_env(
        "pkg",
        env_name = "life-env",
        overwrite = TRUE,
        verbose = "silent"
      ),
      condathis_create_env_failed = function(cnd) {
        seen_in_handler <<- fs::file_exists(fs::path(env_dir, "old-file"))
      }
    ),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_create_env_failed")
  testthat::expect_true(rlang::cnd_inherits(cnd, "stub_solve_failed"))
  testthat::expect_true(seen_in_handler)
  testthat::expect_true(fs::file_exists(fs::path(env_dir, "old-file")))
  testthat::expect_false(fs::file_exists(fs::path(env_dir, "partial-file")))
  testthat::expect_true(env_exists("life-env"))
  testthat::expect_length(trash_entries(stub$backend), 0L)

  # So does a non-zero status, which counts as a failure.
  stub$state$create <- function(env_dir) {
    make_new_env(env_dir, file = "partial-file")
    return(list(status = 1L))
  }
  testthat::expect_error(
    create_env(env_name = "life-env", overwrite = TRUE, verbose = "silent"),
    class = "condathis_create_env_failed"
  )
  testthat::expect_true(fs::file_exists(fs::path(env_dir, "old-file")))
  testthat::expect_false(fs::file_exists(fs::path(env_dir, "partial-file")))

  # A failed create of a new environment leaves nothing.
  testthat::expect_error(
    create_env(env_name = "life-new-env", verbose = "silent"),
    class = "condathis_create_env_failed"
  )
  testthat::expect_false(fs::dir_exists(get_env_dir("life-new-env")))
  testthat::expect_false(env_exists("life-new-env"))
})

testthat::test_that("create_env() names an environment that it could not move back", {
  stub <- local_create_stub("stub-lifecycle-stuck")
  create_env(env_name = "stuck-env", verbose = "silent")
  stub$state$create <- function(env_dir) stop("solve failed")
  real_rename_path <- rename_path
  calls <- 0L
  testthat::local_mocked_bindings(
    rename_path = function(from, to) {
      calls <<- calls + 1L
      if (calls > 1L) {
        return("Access is denied.")
      }
      return(real_rename_path(from, to))
    }
  )
  cnd <- rlang::catch_cnd(
    create_env(env_name = "stuck-env", overwrite = TRUE, verbose = "silent"),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_create_env_failed")
  testthat::expect_s3_class(cnd, "condathis_env_not_restored")
  kept <- trash_entries(stub$backend)
  testthat::expect_length(kept, 1L)
  testthat::expect_identical(cnd$kept_env_dir, kept)
  testthat::expect_true(
    fs::file_exists(fs::path(kept, ".condathis", "backend.json"))
  )
})

# --- With a real micromamba ---------------------------------------------------

testthat::test_that("create_env(overwrite = TRUE) replaces a micromamba environment", {
  # Contract (decision D4): `overwrite = TRUE` leaves exactly the requested
  # environment. Also checks the `cmd` field: the exact micromamba command
  # line.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "micromamba-overwrite-env"
  create_polyglot_env(env_name)
  withr::defer(remove_env(env_name, verbose = "silent"))
  backend <- micromamba_backend()
  testthat::expect_true(
    "polyglot" %in% backend_list_packages(backend, env_name)$name
  )
  extra_file <- fs::path(env_dir_for_backend(backend, env_name), "extra-file")
  fs::file_create(extra_file)

  res <- create_env(
    env_name = env_name,
    channels = polyglot_channel(),
    overwrite = TRUE,
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(
    nrow(backend_list_packages(backend, env_name)),
    0L
  )
  testthat::expect_false(fs::file_exists(extra_file))
  testthat::expect_length(trash_entries(backend), 0L)
  testthat::expect_match(res$cmd, "--override-channels", fixed = TRUE)
  testthat::expect_match(res$cmd, env_name, fixed = TRUE)
})

testthat::test_that("a failed create_env(overwrite = TRUE) keeps the environment", {
  # Regression test: `micromamba create --yes` deletes an existing prefix
  # before it solves, so a misspelled spec with `overwrite = TRUE` lost the
  # environment.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "micromamba-overwrite-fail-env"
  create_polyglot_env(env_name)
  backend <- micromamba_backend()
  env_dir <- env_dir_for_backend(backend, env_name)
  extra_file <- fs::path(env_dir, "extra-file")
  fs::file_create(extra_file)

  # The environment is back before the caller's handlers run.
  seen_in_handler <- NA
  cnd <- rlang::catch_cnd(
    withCallingHandlers(
      create_env(
        "condathis-no-such-package",
        env_name = env_name,
        channels = polyglot_channel(),
        overwrite = TRUE,
        verbose = "silent"
      ),
      condathis_create_env_failed = function(cnd) {
        seen_in_handler <<- fs::file_exists(extra_file)
      }
    ),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_create_env_failed")
  testthat::expect_true(seen_in_handler)
  testthat::expect_true(env_exists(env_name))
  testthat::expect_true(
    "polyglot" %in% list_packages(env_name)$name
  )
  testthat::expect_true(fs::file_exists(extra_file))
  testthat::expect_length(trash_entries(backend), 0L)
  res <- run("polyglot", env_name = env_name, verbose = "silent")
  testthat::expect_identical(res$status, 0L)
})

# A local channel whose one package, `condathis-missing-file`, has no file:
# the solve works, and the download fails.
local_broken_channel <- function(.local_envir = parent.frame()) {
  channel_dir <- fs::path(
    withr::local_tempdir(.local_envir = .local_envir),
    "broken-channel"
  )
  fs::dir_create(fs::path(channel_dir, "noarch"))
  record <- list(
    name = "condathis-missing-file",
    version = "0.1.0",
    build = "0",
    build_number = 0L,
    depends = list(),
    subdir = "noarch",
    noarch = "generic",
    md5 = strrep("0", 32L),
    sha256 = strrep("0", 64L),
    size = 1L
  )
  repodata <- list(
    info = list(subdir = "noarch"),
    packages = list(`condathis-missing-file-0.1.0-0.tar.bz2` = record),
    packages.conda = structure(list(), names = character(0L))
  )
  jsonlite::write_json(
    repodata,
    fs::path(channel_dir, "noarch", "repodata.json"),
    auto_unbox = TRUE
  )
  channel_dir <- normalizePath(channel_dir, winslash = "/", mustWork = TRUE)
  return(paste0("file://", if (isTRUE(is_windows())) "/", channel_dir))
}

testthat::test_that("a failed create of a new environment leaves no environment", {
  # Regression test: micromamba writes `conda-meta/history` before the
  # downloads, so a download error left an "environment", and the identical
  # retry aborted with `condathis_create_env_exists`.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "micromamba-new-env-fail-env"
  channel <- local_broken_channel()
  for (attempt in 1:2) {
    cnd <- rlang::catch_cnd(
      create_env(
        "condathis-missing-file",
        env_name = env_name,
        channels = channel,
        verbose = "silent"
      ),
      classes = "error"
    )
    testthat::expect_s3_class(cnd, "condathis_create_env_failed")
    testthat::expect_false(env_exists(env_name))
    testthat::expect_false(
      fs::dir_exists(env_dir_for_backend(micromamba_backend(), env_name))
    )
  }
})
