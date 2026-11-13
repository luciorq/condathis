# On CRAN, of the tests that use a sandbox (with_sandbox_dir()) or other R
# sessions, only the one of `verbose` and the success message runs: each
# takes about a second on Windows, where listing the processes is slow.

testthat::test_that("clean_cache outputs are captured", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  # This is needed for a full cache clean otherwhise, micromamba keeps
  # + the packages that are used in envs.
  for (env_name in list_envs(verbose = "silent")$env_name) {
    remove_env(env_name = env_name, verbose = "silent")
  }
  r_user_cache <- fs::path(
    tools::R_user_dir(package = "condathis", which = "cache")
  )
  if (isFALSE(fs::dir_exists(r_user_cache))) {
    fs::dir_create(r_user_cache, recurse = TRUE)
  }
  fs::file_touch(fs::path(r_user_cache, "dummy-file", ext = "txt"))

  testthat::expect_message(
    object = {
      clean_cache()
    },
    class = "rlang_message",
    regexp = ".*Cache successfully removed.*"
  ) |>
    testthat::capture_output()

  testthat::expect_message(
    object = {
      clean_cache(verbose = "output")
    },
    class = "rlang_message",
    regexp = ".*Cache successfully removed.*"
  ) |>
    testthat::capture_output()

  # The first call removed the micromamba package cache, and without one
  # clean_cache() starts no process. Give micromamba a cache to clean, so
  # "full" echoes its command line.
  fs::dir_create(fs::path(get_condathis_path(), "pkgs"))
  testthat::expect_message(
    object = {
      clean_cache(verbose = "full")
    },
    class = "rlang_message",
    regexp = ".*Cache successfully removed.*"
  ) |>
    testthat::capture_output() |>
    stringr::str_detect(pattern = "^Running.*") |>
    testthat::expect_true()

  fs::dir_create(fs::path(get_condathis_path(), "pkgs"))
  testthat::expect_message(
    object = {
      clean_cache(verbose = "full")
    },
    class = "rlang_message",
    regexp = ".*Cache successfully removed.*"
  ) |>
    testthat::capture_output() |>
    stringr::str_detect(pattern = "^Running.*") |>
    testthat::expect_true()

  testthat::expect_false(
    fs::file_exists(fs::path(r_user_cache, "dummy-file", ext = "txt"))
  )
  testthat::expect_true(fs::dir_exists(r_user_cache))
})

testthat::test_that("clean_cache returns a condathis_result object", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  cache_res <- clean_cache(verbose = "silent")
  testthat::expect_s3_class(cache_res, "condathis_result")
  testthat::expect_equal(cache_res$status, 0L)
  testthat::expect_true(is.na(cache_res$env_name))

  # With a cache to clean, `cmd` is the command line that ran, with every
  # flag, not a shortened summary.
  fs::dir_create(fs::path(get_condathis_path(), "pkgs"))
  cache_res <- clean_cache(verbose = "silent")
  testthat::expect_true(rlang::is_string(cache_res$cmd))
  for (flag in c("clean", "--yes", "--force-pkgs-dirs")) {
    testthat::expect_match(cache_res$cmd, flag, fixed = TRUE)
  }
  # `--all` also deletes the user's whole `<user cache>/conda`.
  testthat::expect_no_match(cache_res$cmd, "--all", fixed = TRUE)
})

testthat::test_that("clean_cache() never touches the user's ~/.mamba/pkgs", {
  # Regression test: micromamba's fallback package-cache list included the
  # user's global `~/.mamba/pkgs`, and `clean --all --force-pkgs-dirs`
  # deleted it.
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    # libmamba's fallback package cache (`%APPDATA%/.mamba/pkgs` on Windows).
    user_pkgs <- if (isTRUE(is_windows())) {
      fs::path(Sys.getenv("APPDATA"), ".mamba", "pkgs")
    } else {
      fs::path_home(".mamba", "pkgs")
    }
    fs::dir_create(user_pkgs)
    sentinel <- fs::path(user_pkgs, "keep-me.txt")
    writeLines("user cache", sentinel)
    # Without a condathis package cache, clean_cache() starts no process,
    # and this test would pass without running micromamba.
    pkgs_dir <- fs::path(get_condathis_path(), "pkgs")
    fs::dir_create(pkgs_dir)
    clean_cache(verbose = "silent")
    # `--force-pkgs-dirs` removed it: micromamba ran.
    testthat::expect_false(fs::dir_exists(pkgs_dir))
    testthat::expect_true(fs::file_exists(sentinel))
  })
})

testthat::test_that("clean_cache() starts no process when there is no micromamba cache", {
  testthat::skip_on_cran()
  # Regression test: clean_cache() always ran `micromamba clean`, which
  # downloaded micromamba when none was installed, only to clean an empty
  # cache.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        stop("clean_cache() must not start micromamba without a cache")
      },
      install_micromamba = function(...) {
        stop("clean_cache() must not install micromamba")
      }
    )
    r_user_cache <- fs::path(
      tools::R_user_dir(package = "condathis", which = "cache")
    )
    fs::dir_create(r_user_cache)
    fs::file_touch(fs::path(r_user_cache, "dummy-file.txt"))

    res <- clean_cache(verbose = "silent")
    testthat::expect_s3_class(res, "condathis_result")
    testthat::expect_identical(res$status, 0L)
    testthat::expect_identical(res$cmd, NA_character_)
    testthat::expect_identical(res$env_name, NA_character_)
    testthat::expect_false(res$timeout)
    # The condathis cache directory is still cleared.
    testthat::expect_false(
      fs::file_exists(fs::path(r_user_cache, "dummy-file.txt"))
    )
    testthat::expect_false(fs::dir_exists(get_condathis_path()))
  })
})

testthat::test_that("clean_cache() reports the command that native_cmd() ran", {
  testthat::skip_on_cran()
  # Regression test: `cmd` was a hard-coded summary without the flags
  # that really ran.
  condathis::with_sandbox_dir({
    fs::dir_create(fs::path(get_condathis_path(), "pkgs"))
    seen <- new.env()
    testthat::local_mocked_bindings(
      native_cmd = function(conda_cmd, conda_args = NULL, ...) {
        seen$args <- c(conda_cmd, conda_args)
        return(list(
          status = 0L,
          stdout = "",
          stderr = "",
          timeout = FALSE,
          pid = 42L,
          cmd = "'/x/micromamba' 'clean' '--yes' '--force-pkgs-dirs'"
        ))
      }
    )
    res <- clean_cache(verbose = "silent")
    testthat::expect_identical(
      res$cmd,
      "'/x/micromamba' 'clean' '--yes' '--force-pkgs-dirs'"
    )
    testthat::expect_identical(res$pid, 42L)
    testthat::expect_identical(
      seen$args[1:3],
      c("clean", "--yes", "--force-pkgs-dirs")
    )

    # A result without `cmd` reports NA, never an invented command.
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        return(list(status = 0L, stdout = "", stderr = "", timeout = FALSE))
      }
    )
    testthat::expect_identical(
      clean_cache(verbose = "silent")$cmd,
      NA_character_
    )
  })
})

testthat::test_that("clean_cache() validates verbose and reports success with a check mark", {
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("no process may start")
    )
    cnd <- testthat::expect_error(
      clean_cache(verbose = "bogus"),
      class = "condathis_invalid_verbose"
    )
    testthat::expect_s3_class(cnd, "condathis_error")
    testthat::expect_identical(
      rlang::call_name(conditionCall(cnd)),
      "clean_cache"
    )

    msg <- testthat::expect_message(
      clean_cache(verbose = "output"),
      regexp = "Cache successfully removed"
    )
    # The success bullet (rule R3), not the warning bullet `!`.
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(msg)),
      "^(\u2714|v) Cache"
    )
  })
})

testthat::test_that("clean_cache() keeps the user's conda cache directory", {
  # Regression test (footprint): `micromamba clean --all` also deletes the
  # whole `<user cache>/conda` (micromamba >= 2.6.1), so clean_cache()
  # deleted the user's `~/.cache/conda` with the files of other tools.
  # The user cache is `XDG_CACHE_HOME`, else `~/.cache`. On Windows the
  # fallback is the local application data folder, which ignores the
  # environment variables of the sandbox, so the case without
  # `XDG_CACHE_HOME` runs on Linux and macOS only.
  testthat::skip_on_cran()
  local_sandbox_micromamba()
  cases <- if (isTRUE(is_windows())) "set" else c("set", "unset")
  for (case in cases) {
    condathis::with_sandbox_dir({
      if (identical(case, "unset")) {
        Sys.unsetenv("XDG_CACHE_HOME")
        user_cache <- fs::path_home(".cache")
      } else {
        user_cache <- Sys.getenv("XDG_CACHE_HOME")
      }
      sentinels <- fs::path(
        user_cache,
        c(
          "conda/keepme/f",
          "conda/pkgs/cache/shards/user-shard.msgpack.zst",
          "mamba/keepme/f"
        )
      )
      fs::dir_create(fs::path_dir(sentinels))
      for (sentinel in sentinels) {
        writeLines("user file", sentinel)
      }
      root <- get_condathis_path()
      # A cache for micromamba to clean, so that it runs.
      fs::dir_create(fs::path(root, "pkgs", "cache"))
      root_shard <- fs::path(
        root,
        "cache",
        "conda",
        "pkgs",
        "cache",
        "shards",
        "root-shard.msgpack.zst"
      )
      fs::dir_create(fs::path_dir(root_shard))
      writeLines("condathis file", root_shard)

      res <- clean_cache(verbose = "silent")
      testthat::expect_identical(res$status, 0L, info = case)
      testthat::expect_true(rlang::is_string(res$cmd), info = case)
      testthat::expect_true(all(fs::file_exists(sentinels)), info = case)
      testthat::expect_identical(
        unname(vapply(sentinels, readLines, character(1L))),
        rep("user file", length(sentinels)),
        info = case
      )
      # Everything clean_cache() cleaned before is still cleaned.
      testthat::expect_false(
        fs::dir_exists(fs::path(root, "pkgs")),
        info = case
      )
      testthat::expect_false(
        fs::dir_exists(fs::path(root, "cache")),
        info = case
      )
    })
  }
})

# --- Every registered backend (backend contract v2) -------------------------

testthat::test_that("clean_cache() runs every backend's hook, then raises the first failure", {
  testthat::skip_on_cran()
  # Regression test: clean_cache() cleaned only the micromamba caches, and
  # a failure would have stopped the backends after it.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("no micromamba cache, no process")
    )
    stub_a <- local_stub_backend(
      "stub-cache-a",
      backend_clean_cache = function(backend, ...) {
        stop("stub-cache-a could not clean")
      }
    )
    stub_b <- local_stub_backend(
      "stub-cache-b",
      backend_clean_cache = function(backend, ...) {
        cli::cli_abort(
          "stub-cache-b could not clean either",
          class = "condathis_stub_cache_error"
        )
      }
    )
    stub_c <- local_stub_backend(
      "stub-cache-c",
      backend_clean_cache = function(backend, ...) {
        return(list(status = 0L, cmd = "stub clean"))
      }
    )
    testthat::local_mocked_bindings(
      backend_names_by_priority = function() {
        c("stub-cache-a", "micromamba", "stub-cache-b", "stub-cache-c")
      }
    )
    r_user_cache <- fs::path(
      tools::R_user_dir(package = "condathis", which = "cache")
    )
    fs::dir_create(r_user_cache)
    fs::file_touch(fs::path(r_user_cache, "dummy-file.txt"))
    conda_pkgs <- fs::path(stub_c$root, "conda-pkgs")
    fs::dir_create(conda_pkgs)
    fs::file_touch(fs::path(conda_pkgs, "pkg.conda"))

    cnd <- NULL
    msgs <- testthat::capture_messages(
      cnd <- testthat::expect_error(
        clean_cache(verbose = "output"),
        class = "condathis_clean_cache_failed"
      )
    )
    testthat::expect_identical(
      class(cnd)[1:3],
      c(
        "condathis_clean_cache_failed",
        "condathis_backend_error",
        "condathis_error"
      )
    )
    testthat::expect_identical(
      rlang::call_name(conditionCall(cnd)),
      "clean_cache"
    )
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "Backend stub-cache-a failed to clean its caches.",
      fixed = TRUE
    )
    testthat::expect_match(
      conditionMessage(cnd$parent),
      "stub-cache-a could not clean",
      fixed = TRUE
    )
    # No success message after a failure.
    testthat::expect_no_match(
      paste(msgs, collapse = ""),
      "Cache successfully removed"
    )
    # Every backend ran, and everything else was cleaned.
    for (stub in list(stub_a, stub_b, stub_c)) {
      testthat::expect_length(stub_calls(stub, "backend_clean_cache"), 1L)
    }
    testthat::expect_identical(
      stub_calls(stub_c, "backend_clean_cache")[[1L]]$args$verbose,
      "output"
    )
    testthat::expect_false(fs::dir_exists(conda_pkgs))
    testthat::expect_false(
      fs::file_exists(fs::path(r_user_cache, "dummy-file.txt"))
    )

    # The condathis classes of a backend's error stay on the error.
    testthat::local_mocked_bindings(
      backend_names_by_priority = function() {
        c("micromamba", "stub-cache-b", "stub-cache-a")
      }
    )
    cnd <- testthat::expect_error(
      clean_cache(verbose = "silent"),
      class = "condathis_clean_cache_failed"
    )
    testthat::expect_identical(
      class(cnd)[1:4],
      c(
        "condathis_clean_cache_failed",
        "condathis_backend_error",
        "condathis_stub_cache_error",
        "condathis_error"
      )
    )
    testthat::expect_length(stub_calls(stub_a, "backend_clean_cache"), 2L)
  })
})

testthat::test_that("a micromamba failure keeps the micromamba status classes", {
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    fs::dir_create(fs::path(get_condathis_path(), "pkgs"))
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        rlang::abort(
          "Command failed with status 1",
          class = "system_command_status_error",
          status = 1L,
          stdout = "",
          stderr = "critical libmamba could not clean"
        )
      }
    )
    stub <- local_stub_backend("stub-cache-after")
    testthat::local_mocked_bindings(
      backend_names_by_priority = function() c("micromamba", "stub-cache-after")
    )
    cnd <- testthat::expect_error(
      clean_cache(verbose = "silent"),
      class = "condathis_clean_cache_failed"
    )
    testthat::expect_identical(
      class(cnd)[1:5],
      c(
        "condathis_clean_cache_failed",
        "condathis_backend_error",
        "condathis_micromamba_status_error",
        "condathis_cmd_status_error",
        "condathis_error"
      )
    )
    testthat::expect_identical(cnd$parent$status, 1L)
    # Regression test: the error had the class, but not its fields, so a
    # handler for `condathis_micromamba_status_error` got `status = NULL`.
    testthat::expect_identical(cnd$status, 1L)
    testthat::expect_identical(cnd$stderr, "critical libmamba could not clean")
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "Backend micromamba failed to clean its caches.",
      fixed = TRUE
    )
    testthat::expect_length(stub_calls(stub, "backend_clean_cache"), 1L)
    testthat::expect_identical(
      tryCatch(
        clean_cache(verbose = "silent"),
        condathis_micromamba_status_error = function(e) e$status
      ),
      1L
    )
  })
})

testthat::test_that("clean_cache() checks what backend_clean_cache() returns", {
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    status <- NULL
    stub <- local_stub_backend(
      "stub-cache-result",
      backend_clean_cache = function(backend, ...) {
        return(status)
      }
    )
    testthat::local_mocked_bindings(
      backend_names_by_priority = function() {
        c("micromamba", "stub-cache-result")
      }
    )
    # A non-zero status without an error is a failure.
    status <- list(status = 3L, stdout = "out", stderr = "err")
    cnd <- testthat::expect_error(
      clean_cache(verbose = "silent"),
      class = "condathis_clean_cache_failed"
    )
    testthat::expect_s3_class(cnd, "condathis_backend_error")
    testthat::expect_identical(cnd$status, 3L)
    testthat::expect_identical(cnd$stderr, "err")
    testthat::expect_match(
      cli::ansi_strip(conditionMessage(cnd)),
      "returned exit status 3 from `backend_clean_cache()`",
      fixed = TRUE
    )
    # A status that is not a whole number breaks the contract.
    status <- list(status = "done")
    cnd <- testthat::expect_error(
      clean_cache(verbose = "silent"),
      class = "condathis_backend_invalid_return"
    )
    testthat::expect_s3_class(cnd, "condathis_backend_contract_violation")
    # Any other value counts as an empty list. The result is micromamba's,
    # which ran no command here.
    for (status in list(NULL, list(), "cleaned", list(status = 0, cmd = "x"))) {
      res <- clean_cache(verbose = "silent")
      testthat::expect_s3_class(res, "condathis_result")
      testthat::expect_identical(res$status, 0L)
      testthat::expect_identical(res$cmd, NA_character_)
    }
  })
  testthat::expect_null(new_clean_cache_result(NULL, backend_name = "x"))
  res <- new_clean_cache_result(
    list(status = 0, pid = 7, cmd = "x clean", timeout = TRUE, other = 1),
    backend_name = "x"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_identical(res$pid, 7L)
  testthat::expect_identical(res$cmd, "x clean")
  testthat::expect_true(res$timeout)
  testthat::expect_identical(res$env_name, NA_character_)
})

testthat::test_that("clean_cache() empties the conda-pkgs of every backend root", {
  testthat::skip_on_cran()
  # Regression test (Q9): children of a backend other than micromamba get
  # `<root>/conda-pkgs` as their package cache, and nothing emptied it.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("no micromamba cache, no process")
    )
    # The root condathis assigns, and a root of the backend's own.
    stub_default <- local_stub_backend(
      "stub-pkgs-default",
      envs = "kept-env",
      default_root = TRUE
    )
    stub_own <- local_stub_backend("stub-pkgs-own", envs = "kept-env")
    default_root <- backend_root_dir("stub-pkgs-default")
    known_root <- backend_root_path("rattler")
    pkgs_dirs <- fs::path(
      c(default_root, stub_own$root, known_root),
      "conda-pkgs"
    )
    for (pkgs_dir in pkgs_dirs) {
      fs::dir_create(fs::path(pkgs_dir, "pkg-1.0-0"))
      fs::file_touch(fs::path(pkgs_dir, "urls.txt"))
    }
    # What is not condathis's stays: environments, the backend's own
    # caches, and micromamba's root.
    keep <- c(
      fs::path(default_root, "envs", "kept-env", "conda-meta", "history"),
      fs::path(default_root, "pkgs", "own-cache.json"),
      fs::path(stub_own$root, "envs", "kept-env", "file.txt"),
      fs::path(get_condathis_path(), "conda-pkgs", "not-a-backend-root.txt")
    )
    fs::dir_create(fs::path_dir(keep))
    fs::file_touch(keep)

    res <- clean_cache(verbose = "silent")
    testthat::expect_identical(res$status, 0L)
    testthat::expect_false(any(fs::dir_exists(pkgs_dirs)))
    testthat::expect_true(all(fs::file_exists(keep)))
  })
})

testthat::test_that("clean_cache() keeps a conda-pkgs directory outside the backend's root", {
  testthat::skip_on_cran()
  # Regression test: for a backend that keeps its environments in
  # `<dir>/envs` outside its root, clean_cache() deleted `<dir>/conda-pkgs`,
  # which can belong to another tool.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("no micromamba cache, no process")
    )
    shared <- fs::path_real(withr::local_tempdir())
    user_file <- fs::path(shared, "conda-pkgs", "user-cache-file")
    fs::dir_create(fs::path_dir(user_file))
    writeLines("precious", user_file)
    stub <- local_stub_backend(
      "stub-pkgs-far",
      backend_get_env_dir = function(backend, env_name = "condathis-env") {
        return(fs::path(shared, "envs", env_name))
      }
    )
    res <- clean_cache(verbose = "silent")
    testthat::expect_identical(res$status, 0L)
    testthat::expect_true(fs::file_exists(user_file))
  })
})

testthat::test_that("clean_cache() warns about the caches of a known backend that is not installed", {
  testthat::skip_on_cran()
  reset_known_backend_state()
  withr::defer(reset_known_backend_state())
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("no micromamba cache, no process")
    )
    root <- backend_root_path("rattler")
    # Only environments: no cache, no warning. setup.R makes every known
    # backend package read as not installed.
    fs::dir_create(fs::path(root, "envs", "rt-env", "conda-meta"))
    fs::file_touch(fs::path(root, "envs", "rt-env", "conda-meta", "history"))
    fs::dir_create(fs::path(root, "conda-pkgs"))
    testthat::expect_no_warning(clean_cache(verbose = "silent"))
    testthat::expect_false(fs::dir_exists(fs::path(root, "conda-pkgs")))
    # What a clean of the backend leaves: empty cache directories, one with
    # its lock file. Nothing is left to clean, so no warning.
    fs::dir_create(fs::path(root, c("pkgs", "repodata_cache")))
    fs::file_create(fs::path(root, "pkgs", ".cache.lock"))
    testthat::expect_no_warning(clean_cache(verbose = "silent"))

    # A cache that only the backend can clean: a warning on every call.
    fs::dir_create(fs::path(root, "pkgs", "foo-1.0-0"))
    for (i in 1:2) {
      cnd <- testthat::expect_warning(
        clean_cache(verbose = "silent"),
        class = "condathis_backend_not_installed"
      )
      testthat::expect_s3_class(cnd, "condathis_warning")
      testthat::expect_match(
        cli::ansi_strip(conditionMessage(cnd)),
        "The caches of backend rattler",
        fixed = TRUE
      )
      testthat::expect_match(
        cli::ansi_strip(conditionMessage(cnd)),
        "rattlerthis is not installed",
        fixed = TRUE
      )
    }
    testthat::expect_true(fs::dir_exists(fs::path(root, "pkgs")))
  })
})

testthat::test_that("a known backend whose package fails to load gets one warning per call", {
  testthat::skip_on_cran()
  reset_known_backend_state()
  reset_warn_once(known_backend_warn_id("rattler"))
  withr::defer(reset_known_backend_state())
  withr::defer(reset_warn_once(known_backend_warn_id("rattler")))
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("no micromamba cache, no process"),
      load_backend_namespace = function(pkg) {
        return(structure(FALSE, condition = simpleError("broken package")))
      },
      backend_package_installed = function(pkg) TRUE
    )
    fs::dir_create(fs::path(backend_root_path("rattler"), "repodata_cache"))
    fs::file_create(fs::path(
      backend_root_path("rattler"),
      "repodata_cache",
      "abc.json"
    ))
    for (i in 1:2) {
      warnings <- list()
      withCallingHandlers(
        clean_cache(verbose = "silent"),
        warning = function(w) {
          warnings[[length(warnings) + 1L]] <<- w
          invokeRestart("muffleWarning")
        }
      )
      testthat::expect_length(warnings, 1L)
      testthat::expect_s3_class(warnings[[1L]], "condathis_backend_load_failed")
    }
  })
})

testthat::test_that("clean_cache() waits for every backend before it deletes anything", {
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("no micromamba cache, no process")
    )
    events <- character(0L)
    stub <- local_stub_backend(
      "stub-cache-quiesce",
      backend_quiesce = function(backend, timeout = 30) {
        state <- if (fs::dir_exists(pkgs_dir)) "present" else "gone"
        events <<- c(events, paste("quiesce", timeout, state))
        return(invisible(TRUE))
      },
      backend_clean_cache = function(backend, ...) {
        events <<- c(events, "clean")
        return(NULL)
      }
    )
    pkgs_dir <- fs::path(stub$root, "conda-pkgs")
    fs::dir_create(pkgs_dir)
    clean_cache(verbose = "silent")
    testthat::expect_identical(events, c("quiesce 30 present", "clean"))
    testthat::expect_false(fs::dir_exists(pkgs_dir))
  })
})

testthat::test_that("an invalid value of backend_quiesce() names clean_cache()", {
  testthat::skip_on_cran()
  # Regression test: the warning's error named the internal
  # `quiesce_registered_backends()`.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("no micromamba cache, no process")
    )
    stub <- local_stub_backend(
      "stub-cache-quiesce-invalid",
      backend_quiesce = function(backend, ...) "yes"
    )
    cnd <- testthat::expect_warning(
      clean_cache(verbose = "silent"),
      class = "condathis_backend_quiesce_failed"
    )
    testthat::expect_s3_class(cnd$parent, "condathis_backend_invalid_return")
    testthat::expect_identical(
      rlang::call_name(conditionCall(cnd$parent)),
      "clean_cache"
    )
    unregister_backend("stub-cache-quiesce-invalid")
  })
})

testthat::test_that("clean_cache() creates no root", {
  testthat::skip_on_cran()
  # Regression test: nothing may be created to clean nothing, not the
  # condathis data directory and not the root of any backend.
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) stop("no micromamba cache, no process"),
      install_micromamba = function(...) stop("no micromamba install")
    )
    stub <- local_stub_backend("stub-no-root", default_root = TRUE)
    res <- clean_cache(verbose = "silent")
    testthat::expect_identical(res$status, 0L)
    testthat::expect_false(fs::dir_exists(get_condathis_path()))
    testthat::expect_false(fs::dir_exists(backend_root_path("stub-no-root")))
    testthat::expect_false(fs::dir_exists(backend_root_path("rattler")))
  })
})
