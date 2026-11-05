testthat::test_that("validate_env_name rejects names that leave the envs directory", {
  # Regression test: only the type was checked, so `""`, `".."` or `"../x"`
  # resolved to `<root>/envs`, `<root>` or a directory outside the root,
  # and remove_env()/create_env() deleted it.
  bad <- c(
    "",
    ".",
    "..",
    "../x",
    "a/b",
    "a\\b",
    "-n",
    "a b",
    "a:b",
    "a#b",
    "a*b",
    "a\tb",
    "a|b"
  )
  for (nm in bad) {
    testthat::expect_error(
      validate_env_name(nm, class = "test_invalid_env_name"),
      class = "condathis_invalid_env_name",
      info = deparse(nm)
    )
  }
  for (nm in c("env", "my.env_1", "py+3", "condathis", "\u00fcn\u00ef")) {
    testthat::expect_no_error(validate_env_name(nm, class = "x"))
  }
})

testthat::test_that("remove_env() and create_env() never delete outside the envs directory", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    create_env(env_name = "keep-me", verbose = "silent")
    root <- get_install_dir()$path
    for (nm in c("", "..", "../x")) {
      testthat::expect_error(
        remove_env(nm),
        class = "condathis_invalid_env_name"
      )
      testthat::expect_error(
        create_env(env_name = nm, verbose = "silent"),
        class = "condathis_invalid_env_name"
      )
    }
    testthat::expect_error(
      run_pipeline(
        run_step("a"),
        run_step("b"),
        env_name = "..",
        verbose = "silent"
      ),
      class = "condathis_invalid_env_name"
    )
    testthat::expect_error(
      run_step("a", env_name = ".."),
      class = "condathis_invalid_env_name"
    )
    testthat::expect_true(fs::dir_exists(fs::path(root, "envs", "keep-me")))
    testthat::expect_error(
      delete_stale_env_dir(micromamba_backend(), ".."),
      class = "condathis_unsafe_env_dir_delete"
    )
  })
})

testthat::test_that("validate_env_name rejects trailing dots and Windows device names on every OS", {
  # Regression test: Windows drops a trailing dot from a path component, so
  # `<root>/envs/myenv.` opened `<root>/envs/myenv`. `remove_env("myenv.")`
  # and `create_env(env_name = "myenv.")` found no environment "myenv.",
  # but the directory existed, and the stale-directory cleanup deleted the
  # real "myenv". Device names such as "nul" open a device, not a directory.
  # The names are rejected on every OS, so an environment name is portable.
  bad <- c(
    "myenv.",
    "a.",
    "...",
    "CON",
    "con",
    "Prn",
    "aux",
    "NUL",
    "nul.txt",
    "AUX.tar.gz",
    "com1",
    "COM9",
    "lpt1",
    "LPT9.env",
    "conin$",
    "CONOUT$",
    "COM\u00b9",
    "lpt\u00b3"
  )
  for (nm in bad) {
    testthat::expect_error(
      validate_env_name(nm, class = "test_invalid_env_name"),
      class = "condathis_invalid_env_name",
      info = nm
    )
    testthat::expect_error(
      validate_env_name(nm, class = "test_invalid_env_name"),
      class = "test_invalid_env_name",
      info = nm
    )
    testthat::expect_false(is_valid_env_name(nm), info = nm)
  }
  # Names that only contain a device name, or a dot inside, stay valid.
  good <- c(
    "condathis-env",
    "my.env",
    "env.d",
    "console",
    "con-env",
    "nul-env",
    "auxiliary",
    "com",
    "com10",
    "lpt",
    "conda",
    "python3.12"
  )
  for (nm in good) {
    testthat::expect_no_error(validate_env_name(nm, class = "x"))
    testthat::expect_true(is_valid_env_name(nm), info = nm)
  }
})

testthat::test_that("validate_env_name names the reason in the error message", {
  cnd <- rlang::catch_cnd(validate_env_name("myenv.", class = "x"))
  testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
  testthat::expect_match(conditionMessage(cnd), "ends with", fixed = TRUE)

  cnd <- rlang::catch_cnd(validate_env_name("nul.txt", class = "x"))
  testthat::expect_match(conditionMessage(cnd), "device name", fixed = TRUE)
})

testthat::test_that("is_valid_env_name is FALSE for values that are not a single string", {
  # `delete_stale_env_dir()` calls `is_valid_env_name()` on its own as the
  # last check before a deletion, so `NA` must never pass as valid.
  for (value in list(NA_character_, NA, NULL, character(0L), c("a", "b"), 1L)) {
    testthat::expect_false(is_valid_env_name(value), info = deparse(value))
  }
})

testthat::test_that("remove_env() and create_env() reject 'myenv.' before touching 'myenv'", {
  # Regression test for the Windows failure: the directory of "myenv" must
  # survive a call with "myenv.". Validation runs before any backend call,
  # so this needs no micromamba.
  envs_dir <- fs::path(install_dir_for_backend(micromamba_backend()), "envs")
  env_dir <- fs::path(envs_dir, "condathis-trailing-dot-env")
  marker <- fs::path(env_dir, "marker.txt")
  fs::dir_create(env_dir)
  withr::defer(fs::dir_delete(env_dir))
  fs::file_create(marker)

  testthat::expect_error(
    remove_env("condathis-trailing-dot-env."),
    class = "condathis_remove_env_invalid_env_name"
  )
  testthat::expect_error(
    create_env(
      env_name = "condathis-trailing-dot-env.",
      verbose = "silent"
    ),
    class = "condathis_create_invalid_env_name"
  )
  testthat::expect_error(
    env_exists("condathis-trailing-dot-env."),
    class = "condathis_invalid_env_name"
  )
  testthat::expect_true(fs::file_exists(marker))
})

testthat::test_that("validate_env_name() gives every invalid env_name the shared classes", {
  # Regression test: a value that is not a string (env_name = 1) got only
  # the function's own class, while "..", for example, also got
  # condathis_invalid_env_name.
  f <- function(env_name) {
    validate_env_name(
      env_name,
      class = c("condathis_f_invalid_env_name", "condathis_f_old")
    )
  }
  expected <- c(
    "condathis_f_invalid_env_name",
    "condathis_f_old",
    "condathis_invalid_env_name",
    "condathis_invalid_arg",
    "condathis_error",
    "rlang_error",
    "error",
    "condition"
  )
  for (bad in list(1, NA_character_, NULL, c("a", "b"), TRUE, "..", "a/b")) {
    cnd <- rlang::catch_cnd(f(bad), classes = "error")
    testthat::expect_identical(class(cnd), expected, info = deparse(bad))
    testthat::expect_identical(conditionCall(cnd), quote(f(bad)))
  }
  cnd <- rlang::catch_cnd(f(), classes = "error")
  testthat::expect_identical(class(cnd), expected)
  testthat::expect_match(conditionMessage(cnd), "absent", fixed = TRUE)
})

testthat::test_that("validate_env_name() rejects env_path() with the shared class", {
  cnd <- rlang::catch_cnd(
    validate_env_name(
      env_path(tempdir()),
      class = "condathis_f_invalid_env_name"
    ),
    classes = "error"
  )
  testthat::expect_s3_class(cnd, "condathis_env_path_read_only")
  testthat::expect_s3_class(cnd, "condathis_f_invalid_env_name")
  testthat::expect_s3_class(cnd, "condathis_invalid_env_name")
  testthat::expect_s3_class(cnd, "condathis_invalid_arg")
})

testthat::test_that("the leading-dash reason does not name a backend", {
  cnd <- rlang::catch_cnd(
    validate_env_name("-n", class = "x"),
    classes = "error"
  )
  message <- cli::ansi_strip(conditionMessage(cnd))
  testthat::expect_match(message, "command-line option", fixed = TRUE)
  testthat::expect_false(grepl("micromamba", message, fixed = TRUE))
})

testthat::test_that("every function that takes env_name rejects env_name = 1 with the shared class", {
  # Validation runs before any backend call (rule R2), so this needs no
  # micromamba. A backend call would fail the test.
  testthat::local_mocked_bindings(
    resolve_backend = function(...) stop("resolve_backend() must not be called")
  )
  calls <- list(
    create_env = quote(create_env(env_name = 1, verbose = "silent")),
    install_packages = quote(install_packages(
      "python",
      env_name = 1,
      verbose = "silent"
    )),
    remove_env = quote(remove_env(env_name = 1, verbose = "silent")),
    list_packages = quote(list_packages(env_name = 1, verbose = "silent")),
    env_exists = quote(env_exists(env_name = 1)),
    get_env_dir = quote(get_env_dir(env_name = 1)),
    validate_env = quote(validate_env(env_name = 1)),
    run = quote(run("echo", env_name = 1, verbose = "silent")),
    run_bin = quote(run_bin("echo", env_name = 1, verbose = "silent")),
    run_pipeline = quote(run_pipeline(
      run_step("a"),
      run_step("b"),
      env_name = 1,
      verbose = "silent"
    )),
    run_step = quote(run_step("a", env_name = 1))
  )
  for (fn in names(calls)) {
    cnd <- rlang::catch_cnd(eval(calls[[fn]]), classes = "error")
    for (cls in c(
      "condathis_invalid_env_name",
      "condathis_invalid_arg",
      "condathis_error"
    )) {
      testthat::expect_true(inherits(cnd, cls), info = paste(fn, cls))
    }
    testthat::expect_false(
      grepl("must not be called", conditionMessage(cnd), fixed = TRUE),
      info = fn
    )
  }
})
