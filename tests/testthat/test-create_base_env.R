testthat::test_that("Create base env", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  install_dir <- get_install_dir(method = "micromamba")$path
  if (fs::dir_exists(fs::path(install_dir, "envs", "condathis-env"))) {
    fs::dir_delete(fs::path(install_dir, "envs", "condathis-env"))
  }
  create_base_env(verbose = "silent")
  testthat::expect_true(
    fs::file_exists(
      fs::path(
        install_dir,
        "envs",
        "condathis-env",
        "conda-meta",
        "history"
      )
    )
  )
})

testthat::test_that("create_base_env() creates the environment with the given backend", {
  # Regression test: create_base_env() had no `method` and always created
  # through "auto", so run(method = "a") created condathis-env under the
  # first backend in priority order and then warned that the environment
  # belonged to another backend.
  stub_a <- local_stub_backend("stub-base-a")
  stub_b <- local_stub_backend("stub-base-b")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() c("stub-base-b", "stub-base-a")
  )

  testthat::expect_no_warning(
    create_base_env(method = "stub-base-a", verbose = "silent")
  )
  testthat::expect_true(
    fs::dir_exists(fs::path(stub_a$root, "envs", "condathis-env"))
  )
  testthat::expect_false(
    fs::dir_exists(fs::path(stub_b$root, "envs", "condathis-env"))
  )
  testthat::expect_length(stub_calls(stub_a, "backend_create_env"), 1L)
  testthat::expect_length(stub_calls(stub_b, "backend_create_env"), 0L)

  # An existing environment is kept: no second creation.
  create_base_env(method = "stub-base-a", verbose = "silent")
  testthat::expect_length(stub_calls(stub_a, "backend_create_env"), 1L)
})

testthat::test_that("create_base_env() returns NULL invisibly", {
  local_stub_backend("stub-base-invisible", envs = "condathis-env")
  testthat::local_mocked_bindings(
    backend_names_by_priority = function() "stub-base-invisible"
  )
  res <- withVisible(create_base_env(method = "stub-base-invisible"))
  testthat::expect_false(res$visible)
  testthat::expect_null(res$value)
})

testthat::test_that("parallel run() calls on a fresh root create one default environment", {
  testthat::skip_on_cran()
  testthat::skip_if_not_installed("callr")
  # run() can be called from several R sessions at once. Each call that
  # finds no "condathis-env" creates it, under the lock of the
  # environment, and create_env() keeps an environment that another
  # session created meanwhile.
  umamba_path <- local_sandbox_micromamba()
  with_sandbox_dir({
    root <- get_condathis_path()
    testthat::expect_false(fs::dir_exists(fs::path(root, "envs")))
    sync_dir <- withr::local_tempdir()
    go_file <- file.path(sync_dir, "go")
    # The sessions close when `local()` ends, before the sandbox is deleted.
    results <- local({
      frame <- environment()
      sessions <- lapply(seq_len(4L), function(i) {
        local_lock_session(
          micromamba_path = as.character(umamba_path),
          env = frame
        )
      })
      for (i in seq_along(sessions)) {
        sessions[[i]]$call(
          function(ready_file, go_file, rscript) {
            file.create(ready_file)
            # Start together.
            while (isFALSE(file.exists(go_file))) {
              Sys.sleep(0.01)
            }
            out <- character(0L)
            for (j in seq_len(3L)) {
              res <- condathis::run(
                rscript,
                "-e",
                "cat('ok')",
                env_name = "condathis-env",
                verbose = "silent"
              )
              out <- c(out, paste(res$status, res$stdout))
            }
            return(out)
          },
          args = list(
            ready_file = file.path(sync_dir, paste0("ready-", i)),
            go_file = go_file,
            rscript = run_family_rscript()
          )
        )
      }
      lock_wait_until(
        function() {
          all(file.exists(file.path(
            sync_dir,
            paste0("ready-", seq_along(sessions))
          )))
        },
        what = "the sessions to start"
      )
      file.create(go_file)
      lapply(sessions, function(session) {
        state <- session$poll_process(300000L)
        if (isFALSE(identical(state, "ready"))) {
          return("timeout")
        }
        out <- session$read()
        if (isFALSE(is.null(out$error))) {
          return(conditionMessage(out$error))
        }
        return(out$result)
      })
    })
    for (out in results) {
      testthat::expect_identical(out, rep("0 ok", 3L))
    }
    testthat::expect_identical(list_conda_prefix_envs(root), "condathis-env")
    entries <- read_dir_names(fs::path(root, "envs"))
    testthat::expect_identical(
      entries[entries != env_trash_name()],
      "condathis-env"
    )
  })
})
