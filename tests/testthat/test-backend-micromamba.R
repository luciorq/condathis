# On CRAN, of the tests that use a sandbox (with_sandbox_dir()) or other R
# sessions, only the one of the queries on a fresh root runs: each takes
# about a second on Windows, where listing the processes is slow.

# --- Cheap probes on a fresh root (micromamba-cheap-probe, decision D3) ---

# Makes any micromamba process, or a micromamba install, fail the test.
local_no_micromamba_process <- function(envir = parent.frame()) {
  testthat::local_mocked_bindings(
    native_cmd = function(...) {
      stop("native_cmd() must not run here.")
    },
    install_micromamba = function(...) {
      stop("install_micromamba() must not run here.")
    },
    .env = envir
  )
}

# A fake `native_cmd()` that records its arguments and returns `stdout`.
local_fake_native_cmd <- function(stdout, status = 0L, envir = parent.frame()) {
  record <- new.env(parent = emptyenv())
  record$calls <- list()
  testthat::local_mocked_bindings(
    native_cmd = function(conda_cmd, conda_args = NULL, ..., verbose = NULL) {
      record$calls[[length(record$calls) + 1L]] <- list(
        conda_cmd = conda_cmd,
        conda_args = conda_args,
        verbose = verbose
      )
      return(list(status = status, stdout = stdout, stderr = ""))
    },
    .env = envir
  )
  return(record)
}

# The JSON of `micromamba env list --json` for these environment paths.
env_list_json <- function(paths) {
  return(as.character(jsonlite::toJSON(
    list(envs = as.character(paths)),
    auto_unbox = FALSE
  )))
}

testthat::test_that("micromamba probes start no process and create nothing on a fresh root", {
  testthat::skip_on_cran()
  # Regression test (A2): every call that names an environment probed the
  # micromamba backend through `micromamba env list`, which created the
  # root and installed micromamba when no binary was found, also with
  # another backend's `method`.
  local_no_micromamba_process()
  with_sandbox_dir({
    root <- get_condathis_path()
    testthat::expect_false(fs::dir_exists(root))
    backend <- micromamba_backend()
    testthat::expect_false(backend_env_exists(backend, env_name = "x"))
    testthat::expect_identical(backend_list_envs(backend), character(0L))
    testthat::expect_false(backend_probe_env(backend, env_name = "x"))
    # Nothing was created, not even the root.
    testthat::expect_false(fs::dir_exists(root))

    # An empty `envs/` directory gives the same answer.
    fs::dir_create(fs::path(root, "envs"))
    testthat::expect_false(backend_env_exists(backend, env_name = "x"))
    testthat::expect_identical(backend_list_envs(backend), character(0L))
  })
})

testthat::test_that("queries work on a fresh root without creating an environment", {
  # Decision D3: list_envs(), env_exists(), get_env_dir(), list_packages()
  # on a missing name and get_install_dir() work on a fresh root, without
  # a micromamba process, a micromamba install or a new environment. Only
  # the root directory may be created.
  local_no_micromamba_process()
  with_sandbox_dir({
    root <- get_condathis_path()

    testthat::expect_false(env_exists("x", method = "micromamba"))
    testthat::expect_false(env_exists("x"))
    testthat::expect_false(env_exists("condathis-env"))
    envs <- list_envs(method = "micromamba")
    testthat::expect_identical(nrow(envs), 0L)
    testthat::expect_identical(nrow(list_envs()), 0L)
    testthat::expect_error(
      list_packages(env_name = "x", verbose = "silent"),
      class = "condathis_env_not_found"
    )
    testthat::expect_error(
      list_packages(verbose = "silent"),
      class = "condathis_env_not_found"
    )
    env_dir <- get_env_dir("x")
    testthat::expect_identical(as.character(fs::path_file(env_dir)), "x")
    install_dirs <- get_install_dir()
    testthat::expect_true("micromamba" %in% install_dirs$backend)

    # No environment, and no other directory under the root.
    envs_dir <- fs::path(root, "envs")
    if (isTRUE(fs::dir_exists(envs_dir))) {
      testthat::expect_length(fs::dir_ls(envs_dir, all = TRUE), 0L)
    }
    testthat::expect_false(fs::dir_exists(fs::path(root, "pkgs")))
  })
})

testthat::test_that("an environment directory makes the probe ask micromamba", {
  testthat::skip_on_cran()
  # The cheap probe answers only "no". With a directory, the listing
  # decides, so a real environment is never hidden.
  with_sandbox_dir({
    root <- install_dir_for_backend(micromamba_backend())
    env_dir <- fs::path(root, "envs", "probe-listed-env")
    fs::dir_create(fs::path(env_dir, "conda-meta"))
    record <- local_fake_native_cmd(env_list_json(c(root, env_dir)))
    backend <- micromamba_backend()
    testthat::expect_true(backend_env_exists(
      backend,
      env_name = "probe-listed-env"
    ))
    testthat::expect_length(record$calls, 1L)
    testthat::expect_false(backend_env_exists(backend, env_name = "other-env"))
    # No directory for "other-env": no second listing.
    testthat::expect_length(record$calls, 1L)
  })
})

# No usable micromamba binary. An install, or any process, fails the test.
local_micromamba_not_installed <- function(envir = parent.frame()) {
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function() NULL,
    install_micromamba = function(...) {
      stop("install_micromamba() was called by a query.")
    },
    execute_command = function(...) {
      stop("No process may start here.")
    },
    .env = envir
  )
}

# A package record, as micromamba writes it to `conda-meta/`.
write_package_record <- function(env_dir, record) {
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  record_file <- fs::path(
    env_dir,
    "conda-meta",
    paste0(record$name, "-", record$version, "-", record$build, ".json")
  )
  jsonlite::write_json(record, record_file, auto_unbox = TRUE)
  return(invisible(record_file))
}

testthat::test_that("listings without a micromamba binary read the file system", {
  testthat::skip_on_cran()
  # Regression test (decision D3): with an environment directory under
  # `<root>/envs` and no usable micromamba binary, env_exists(), list_envs()
  # and list_packages() installed micromamba, also with another backend's
  # `method`. A query never installs micromamba.
  local_micromamba_not_installed()
  with_sandbox_dir({
    backend <- micromamba_backend()
    root <- install_dir_for_backend(backend)
    leftover <- fs::path(root, "envs", "leftover")
    fs::dir_create(fs::path(leftover, "conda-meta"))
    fs::file_create(fs::path(leftover, "conda-meta", "history"))
    write_package_record(
      leftover,
      list(
        name = "polyglot",
        version = "0.1.0",
        build = "h4616a5c_0",
        build_number = 0L,
        channel = "conda-forge",
        subdir = "noarch",
        url = "https://conda.anaconda.org/conda-forge/noarch/polyglot-0.1.0-h4616a5c_0.conda",
        md5 = "59a37b1b046df5560f1b25abb0ddf8f8"
      )
    )
    write_package_record(
      leftover,
      list(
        name = "abc",
        version = "1.2",
        build = "h0_3",
        build_number = 3L,
        channel = "conda-forge",
        subdir = "linux-64",
        url = "https://conda.anaconda.org/conda-forge/linux-64/abc-1.2-h0_3.conda"
      )
    )
    # Not a package record: skipped.
    writeLines("{}", fs::path(leftover, "conda-meta", "state.json"))
    empty_env <- fs::path(root, "envs", "empty-env")
    fs::dir_create(fs::path(empty_env, "conda-meta"))
    fs::file_create(fs::path(empty_env, "conda-meta", "history"))
    # micromamba lists only directories with `conda-meta/history`.
    fs::dir_create(fs::path(root, "envs", "stale"))
    fs::dir_create(fs::path(root, "envs", "half", "conda-meta"))

    testthat::expect_identical(
      sort(backend_list_envs(backend)),
      c("empty-env", "leftover")
    )
    testthat::expect_true(backend_env_exists(backend, env_name = "leftover"))
    testthat::expect_false(backend_env_exists(backend, env_name = "stale"))
    testthat::expect_false(backend_env_exists(backend, env_name = "half"))
    testthat::expect_false(backend_env_exists(backend, env_name = "missing"))

    testthat::expect_true(env_exists("leftover"))
    testthat::expect_true(env_exists("leftover", method = "micromamba"))
    testthat::expect_false(env_exists("stale"))
    testthat::expect_true("leftover" %in% list_envs()$env_name)
    testthat::expect_identical(
      as.character(fs::path_file(get_env_dir("leftover"))),
      "leftover"
    )

    pkgs <- list_packages("leftover")
    checked <- validate_backend_return(
      pkgs,
      "backend_list_packages",
      "micromamba"
    )
    testthat::expect_identical(checked$name, c("abc", "polyglot"))
    testthat::expect_identical(checked$version, c("1.2", "0.1.0"))
    testthat::expect_identical(checked$build_number, c(3L, 0L))
    testthat::expect_identical(checked$build_string, c("h0_3", "h4616a5c_0"))
    testthat::expect_identical(checked$platform, c("linux-64", "noarch"))
    testthat::expect_identical(checked$channel, c("conda-forge", "conda-forge"))
    testthat::expect_identical(
      checked$base_url,
      rep("https://conda.anaconda.org/conda-forge", 2L)
    )
    testthat::expect_identical(
      checked$dist_name[[2L]],
      "polyglot-0.1.0-h4616a5c_0"
    )
    testthat::expect_identical(checked$md5[[1L]], NA_character_)

    empty_pkgs <- list_packages("empty-env")
    testthat::expect_identical(nrow(empty_pkgs), 0L)
    testthat::expect_true(
      all(names(backend_list_packages_columns) %in% names(empty_pkgs))
    )

    # A directory that is not an environment: the backend reports it as
    # missing, as micromamba does.
    testthat::expect_error(
      backend_list_packages(backend, env_name = "stale"),
      class = "condathis_env_not_found"
    )
  })
})

testthat::test_that("the file system listings agree with micromamba", {
  # The fallbacks above must give what micromamba itself reports, so that
  # a query and the stale-directory cleanup decide the same way with or
  # without a micromamba binary.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "micromamba-fallback-env"
  create_polyglot_env(env_name)
  backend <- micromamba_backend()
  root <- install_dir_for_backend(backend)
  # A directory that micromamba does not list.
  stale_dir <- fs::path(root, "envs", "fallback-stale-dir", "conda-meta")
  fs::dir_create(stale_dir)
  withr::defer(fs::dir_delete(fs::path_dir(stale_dir)))

  testthat::expect_identical(
    sort(list_conda_prefix_envs(root)),
    sort(backend_list_envs(backend))
  )
  real_pkgs <- backend_list_packages(backend, env_name)
  file_pkgs <- read_conda_package_records(
    env_dir = env_dir_for_backend(backend, env_name),
    env_name = env_name
  )
  for (column in c(
    "name",
    "version",
    "build_number",
    "build_string",
    "platform",
    "dist_name",
    "url"
  )) {
    testthat::expect_identical(
      as.vector(file_pkgs[[column]]),
      as.vector(real_pkgs[[column]]),
      info = column
    )
  }
  # Channels compare as condathis compares them: micromamba lists a channel
  # by name or by URL, and a record can store the other spelling.
  for (column in c("channel", "base_url")) {
    testthat::expect_identical(
      normalize_channel_name(file_pkgs[[column]]),
      normalize_channel_name(real_pkgs[[column]]),
      info = column
    )
  }
})

# A `file://` URL for a local directory, as `polyglot_channel()` builds it.
local_file_url <- function(dir) {
  dir <- normalizePath(dir, winslash = "/", mustWork = TRUE)
  return(paste0("file://", if (isTRUE(is_windows())) "/", dir))
}

# A copy of the polyglot channel, named "url-channel", whose repodata gives
# the package a `url` in another directory, "files". micromamba 2.10.0 and
# later download it from there. Older versions ignore that `url`, so the
# file stays in the channel too.
local_url_channel <- function(.local_envir = parent.frame()) {
  base_dir <- withr::local_tempdir(.local_envir = .local_envir)
  channel_dir <- fs::path(base_dir, "url-channel")
  fs::dir_copy(
    system.file(
      "extdata",
      "polyglot-channel",
      package = "condathis",
      mustWork = TRUE
    ),
    channel_dir
  )
  files_dir <- fs::path(base_dir, "elsewhere", "files")
  fs::dir_create(files_dir)
  file_name <- "polyglot-0.1.0-h4616a5c_0.conda"
  fs::file_copy(
    fs::path(channel_dir, "noarch", file_name),
    fs::path(files_dir, file_name)
  )
  repodata_file <- fs::path(channel_dir, "noarch", "repodata.json")
  repodata <- jsonlite::read_json(repodata_file)
  repodata[["packages.conda"]][[file_name]][["url"]] <- paste0(
    local_file_url(files_dir),
    "/",
    file_name
  )
  jsonlite::write_json(
    repodata,
    repodata_file,
    auto_unbox = TRUE,
    digits = NA,
    pretty = TRUE
  )
  return(local_file_url(channel_dir))
}

testthat::test_that("the micromamba listing reports the channel of the package records", {
  testthat::skip_on_cran()
  # Regression test: since micromamba 2.10.0, a package downloads from the
  # `url` that its channel's repodata gives, and `micromamba list --json`
  # derives the channel from that URL. A package from outside its channel
  # listed another channel than its record, so an identical create_env()
  # aborted, and the listing without a micromamba binary differed.
  with_sandbox_dir({
    backend <- micromamba_backend()
    env_dir <- fs::path(install_dir_for_backend(backend), "envs", "rec-env")
    fs::dir_create(fs::path(env_dir, "conda-meta"))
    fs::file_create(fs::path(env_dir, "conda-meta", "history"))
    # Downloaded from outside its channel.
    write_package_record(
      env_dir,
      list(
        name = "pkga",
        version = "1.0",
        build = "0",
        build_number = 0L,
        channel = "file:///srv/chan",
        subdir = "noarch",
        url = "file:///srv/elsewhere/files/pkga-1.0-0.conda"
      )
    )
    # The channel with the platform subdirectory, as micromamba 1.x
    # recorded it.
    write_package_record(
      env_dir,
      list(
        name = "pkgb",
        version = "2.0",
        build = "h1_0",
        build_number = 1L,
        channel = "https://conda.anaconda.org/conda-forge/linux-64/",
        subdir = "linux-64",
        url = "https://conda.anaconda.org/conda-forge/linux-64/pkgb-2.0-h1_0.conda"
      )
    )
    # No channel, as micromamba 2.10.0 records a conda-lock file's URL
    # channel.
    write_package_record(
      env_dir,
      list(
        name = "pkgc",
        version = "3.0",
        build = "h2_0",
        build_number = 2L,
        channel = "",
        subdir = "linux-64",
        url = "https://repo.prefix.dev/conda-forge/linux-64/pkgc-3.0-h2_0.conda"
      )
    )
    write_package_record(
      env_dir,
      list(
        name = "pkgd",
        version = "4.0",
        build = "pyh_0",
        build_number = 0L,
        channel = "conda-forge",
        subdir = "noarch",
        url = "https://conda.anaconda.org/conda-forge/noarch/pkgd-4.0-pyh_0.conda"
      )
    )
    listed <- data.frame(
      name = c("pkga", "pkgb", "pkgc", "pkgd", "requests"),
      version = c("1.0", "2.0", "3.0", "4.0", "2.32.3"),
      build_string = c("0", "h1_0", "h2_0", "pyh_0", "pypi_0"),
      build_number = c(0L, 1L, 2L, 0L, 0L),
      platform = c("noarch", "linux-64", "linux-64", "noarch", "linux-64"),
      channel = c(
        "file:///srv/elsewhere/files",
        "conda-forge",
        "https://repo.prefix.dev/conda-forge",
        "conda-forge",
        "pypi"
      ),
      base_url = c(
        "file:///srv/elsewhere/files",
        "https://conda.anaconda.org/conda-forge",
        "https://repo.prefix.dev/conda-forge",
        "https://conda.anaconda.org/conda-forge",
        "https://pypi.org/"
      ),
      url = c(
        "file:///srv/elsewhere/files/pkga-1.0-0.conda",
        "https://conda.anaconda.org/conda-forge/linux-64/pkgb-2.0-h1_0.conda",
        "https://repo.prefix.dev/conda-forge/linux-64/pkgc-3.0-h2_0.conda",
        "https://conda.anaconda.org/conda-forge/noarch/pkgd-4.0-pyh_0.conda",
        ""
      ),
      stringsAsFactors = FALSE
    )
    listed$dist_name <- paste(
      listed$name,
      listed$version,
      listed$build_string,
      sep = "-"
    )
    local_fake_native_cmd(
      as.character(jsonlite::toJSON(
        list(log_history = list(), packages = listed),
        auto_unbox = TRUE
      ))
    )
    expected_channel <- c(
      "file:///srv/chan",
      "conda-forge",
      "https://repo.prefix.dev/conda-forge",
      "conda-forge"
    )
    real_pkgs <- backend_list_packages(backend, env_name = "rec-env")
    testthat::expect_identical(real_pkgs$name, listed$name)
    testthat::expect_identical(real_pkgs$channel, c(expected_channel, "pypi"))
    testthat::expect_identical(real_pkgs$base_url, listed$base_url)
    testthat::expect_true(
      spec_satisfied_by(
        "pkga",
        installed_pkgs_df = real_pkgs,
        requested_channels = normalize_channel_name("/srv/chan")
      )
    )

    # Without a micromamba binary, the records give the same listing.
    file_pkgs <- read_conda_package_records(env_dir, "rec-env")
    for (column in c(
      "name",
      "version",
      "build_number",
      "build_string",
      "platform",
      "channel",
      "base_url",
      "dist_name",
      "url"
    )) {
      testthat::expect_identical(
        as.vector(file_pkgs[[column]]),
        as.vector(real_pkgs[[column]][1:4]),
        info = column
      )
    }
  })
})

testthat::test_that("a package downloaded from outside its channel keeps that channel", {
  # Regression test with a real environment: since micromamba 2.10.0, the
  # second of two identical create_env() calls aborted with
  # condathis_create_env_exists for such a package.
  testthat::skip_on_cran()
  skip_if_no_micromamba_offline()
  env_name <- "micromamba-url-channel-env"
  channel <- local_url_channel()
  create_args <- list(
    "polyglot",
    env_name = env_name,
    channels = channel,
    verbose = "silent"
  )
  res <- do.call(create_env, create_args)
  testthat::expect_identical(res$status, 0L)
  withr::defer(remove_env(env_name, verbose = "silent"))

  pkgs <- list_packages(env_name)
  testthat::expect_identical(
    normalize_channel_name(pkgs$channel),
    normalize_channel_name(channel)
  )
  res <- do.call(create_env, create_args)
  testthat::expect_identical(res$status, 0L)
  testthat::expect_true(
    validate_env(
      "polyglot",
      env_name = env_name,
      channels = channel,
      verbose = "silent"
    )
  )

  backend <- micromamba_backend()
  file_pkgs <- read_conda_package_records(
    env_dir = env_dir_for_backend(backend, env_name),
    env_name = env_name
  )
  testthat::expect_identical(as.vector(file_pkgs$url), as.vector(pkgs$url))
  for (column in c("channel", "base_url")) {
    testthat::expect_identical(
      normalize_channel_name(file_pkgs[[column]]),
      normalize_channel_name(pkgs[[column]]),
      info = column
    )
  }
})

testthat::test_that("micromamba_backend_list_envs() reports each environment once", {
  testthat::skip_on_cran()
  # Regression test: one environment under two spellings (for example a
  # registry entry with a symbolic link in its path) gave a duplicate
  # name, which the backend contract forbids.
  with_sandbox_dir({
    root <- install_dir_for_backend(micromamba_backend())
    env_dir <- fs::path(root, "envs", "dup-env")
    fs::dir_create(fs::path(env_dir, "conda-meta"))
    other_spelling <- fs::path(root, "envs", "..", "envs", "dup-env")
    local_fake_native_cmd(env_list_json(c(env_dir, other_spelling, env_dir)))
    envs <- backend_list_envs(micromamba_backend())
    testthat::expect_identical(envs, "dup-env")
    testthat::expect_identical(
      validate_backend_return(envs, "backend_list_envs", "micromamba"),
      "dup-env"
    )
  })
})

testthat::test_that("micromamba_backend_list_envs() reads the file system when micromamba hides the paths", {
  testthat::skip_on_cran()
  # Regression test: micromamba 2.9.0 and later hide every `/t/<word>` of
  # their JSON output as a channel token, paths included (see
  # `hide_secrets()`). Under a root with such a part, `micromamba env list
  # --json` named no environment of the root, so condathis found none:
  # list_envs() was empty, and every call that names an environment
  # aborted with condathis_env_not_found.
  with_sandbox_dir({
    root <- install_dir_for_backend(micromamba_backend())
    for (env_name in c("hidden-env", "other-env")) {
      env_dir <- fs::path(root, "envs", env_name)
      fs::dir_create(fs::path(env_dir, "conda-meta"))
      fs::file_create(fs::path(env_dir, "conda-meta", "history"))
    }
    # What micromamba lists for the root `<dir>/t/proj1/root`.
    hidden_root <- fs::path(withr::local_tempdir(), "t", "*****", "root")
    local_fake_native_cmd(env_list_json(c(
      hidden_root,
      fs::path(hidden_root, "envs", "hidden-env")
    )))
    testthat::expect_identical(
      sort(backend_list_envs(micromamba_backend())),
      c("hidden-env", "other-env")
    )
    testthat::expect_true(
      backend_env_exists(micromamba_backend(), env_name = "hidden-env")
    )
  })
})

testthat::test_that("micromamba_backend_list_envs() keeps the JSON listing off the console", {
  testthat::skip_on_cran()
  # Regression test: `list_envs(verbose = "output")` echoed the raw JSON of
  # `micromamba env list`, because the listing passed no quiet arguments.
  with_sandbox_dir({
    root <- install_dir_for_backend(micromamba_backend())
    env_dir <- fs::path(root, "envs", "quiet-env")
    fs::dir_create(fs::path(env_dir, "conda-meta"))
    record <- local_fake_native_cmd(env_list_json(env_dir))
    for (level in c("output", "silent", "cmd", "spinner")) {
      backend_list_envs(micromamba_backend(), verbose = level)
      call <- record$calls[[length(record$calls)]]
      testthat::expect_true(
        has_arg_sequence(call$conda_args, micromamba_quiet_args),
        info = level
      )
      testthat::expect_false(
        native_cmd_echo(
          output = TRUE,
          conda_args = call$conda_args,
          stderr = "|",
          encoding = "utf-8"
        ),
        info = level
      )
    }
  })
})

testthat::test_that("failed micromamba listings have the new and the old class", {
  testthat::skip_on_cran()
  with_sandbox_dir({
    root <- install_dir_for_backend(micromamba_backend())
    fs::dir_create(fs::path(root, "envs", "status-env", "conda-meta"))
    fs::file_create(fs::path(
      root,
      "envs",
      "status-env",
      "conda-meta",
      "history"
    ))
    local_fake_native_cmd("", status = 1L)
    backend <- micromamba_backend()
    for (cnd in list(
      rlang::catch_cnd(backend_list_envs(backend), classes = "error"),
      rlang::catch_cnd(
        backend_list_packages(backend, env_name = "status-env"),
        classes = "error"
      )
    )) {
      testthat::expect_identical(
        class(cnd)[1:3],
        c(
          "condathis_micromamba_status_error",
          "condathis_cmd_status_error",
          "condathis_error"
        )
      )
    }
  })
})

testthat::test_that("micromamba_backend_list_packages() returns the six contract columns", {
  backend <- micromamba_backend()
  # An environment directory: the backend checks that it exists first.
  meta_dir <- fs::path(env_dir_for_backend(backend, "any-env"), "conda-meta")
  fs::dir_create(meta_dir)
  fs::file_create(fs::path(meta_dir, "history"))
  withr::defer(fs::dir_delete(fs::path_dir(meta_dir)))
  package_json <- paste0(
    "[{\"base_url\": \"https://conda.anaconda.org/conda-forge\",",
    " \"build_number\": 3, \"build_string\": \"h1234_3\",",
    " \"channel\": \"conda-forge\", \"dist_name\": \"xz-5.6.2-h1234_3\",",
    " \"name\": \"xz\", \"platform\": \"linux-64\", \"version\": \"5.6.2\"}]"
  )
  outputs <- list(
    empty_array = "[]",
    empty_packages = "{\"log_history\": [], \"packages\": []}",
    one_package = package_json,
    one_package_2_9 = paste0(
      "{\"log_history\": [], \"packages\": ",
      package_json,
      "}"
    )
  )
  for (shape in names(outputs)) {
    local_fake_native_cmd(outputs[[shape]])
    pkgs <- backend_list_packages(backend, env_name = "any-env")
    checked <- validate_backend_return(
      pkgs,
      "backend_list_packages",
      "micromamba"
    )
    testthat::expect_true(
      all(names(backend_list_packages_columns) %in% names(checked)),
      info = shape
    )
    testthat::expect_type(checked$build_number, "integer")
    if (startsWith(shape, "one_package")) {
      testthat::expect_identical(checked$platform, "linux-64", info = shape)
      testthat::expect_identical(checked$build_string, "h1234_3", info = shape)
    }
  }
})

testthat::test_that("a missing env_file names the file and has both classes", {
  missing_file <- fs::path(withr::local_tempdir(), "no-such-env.yml")
  cnd <- rlang::catch_cnd(
    resolve_create_env_packages_arg(packages = NULL, env_file = missing_file),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd)[1:5],
    c(
      "condathis_create_env_missing_env_file",
      "condathis_create_missing_env_file",
      "condathis_invalid_env_file",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  # Regression test: the message printed the literal text "env_file".
  testthat::expect_match(
    cli::ansi_strip(conditionMessage(cnd)),
    "no-such-env.yml",
    fixed = TRUE
  )
})

testthat::test_that("removing a missing micromamba environment has the shared class", {
  testthat::skip_on_cran()
  local_no_micromamba_process()
  with_sandbox_dir({
    cnd <- rlang::catch_cnd(
      backend_remove_env(
        micromamba_backend(),
        env_name = "never-created-env",
        verbose = "silent"
      ),
      classes = "error"
    )
    testthat::expect_identical(
      class(cnd)[1:4],
      c(
        "condathis_remove_env_env_not_found",
        "condathis_error_env_remove",
        "condathis_env_not_found",
        "condathis_error"
      )
    )
  })
})

testthat::test_that("backend_install() and backend_list_packages() report a missing environment with the shared class", {
  local_no_micromamba_process()
  backend <- micromamba_backend()
  cnd <- rlang::catch_cnd(
    backend_install(backend, "pkg", env_name = "condathis-missing-install"),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_install_packages_env_not_found",
      "condathis_env_not_found",
      "condathis_error"
    )
  )
  cnd <- rlang::catch_cnd(
    backend_list_packages(backend, env_name = "condathis-missing-list"),
    classes = "error"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_list_packages_env_not_found",
      "condathis_list_packages_missing_env",
      "condathis_env_not_found",
      "condathis_error"
    )
  )
})

testthat::test_that("create_env() shows the Rosetta 2 messages at the caller's verbose level", {
  # Regression test: the platform choice passed "silent" to
  # define_platform(), so create_env() never showed the Rosetta 2 messages.
  # The OS is given through mocks, so the test runs on every platform. The
  # front end asks micromamba through backend_can_solve(), which wraps
  # packages_solve_native().
  create_args <- NULL
  env_names <- c("rosetta-env", "rosetta-env-2")
  withr::defer({
    env_dirs <- fs::path(get_condathis_path(), "envs", env_names)
    fs::dir_delete(env_dirs[fs::dir_exists(env_dirs)])
  })
  testthat::local_mocked_bindings(
    get_sys_arch = function() "Darwin-arm64",
    is_rosetta_running = function() TRUE,
    packages_solve_native = function(..., platform, verbose) {
      # The solves never print their output.
      testthat::expect_identical(verbose, "silent")
      return(isFALSE(identical(platform, "osx-arm64")))
    },
    native_cmd = function(
      conda_cmd,
      conda_args = NULL,
      ...,
      verbose = "silent",
      error = "cancel"
    ) {
      if (identical(conda_cmd, "create")) {
        create_args <<- conda_args
        i <- which(conda_args == "-n")
        if (identical(length(i), 1L)) {
          fs::dir_create(fs::path(
            get_condathis_path(),
            "envs",
            conda_args[[i + 1L]],
            "conda-meta"
          ))
        }
      }
      return(list(
        status = 0L,
        stdout = "",
        stderr = "",
        cmd = "micromamba create"
      ))
    }
  )
  msgs <- character(0L)
  withCallingHandlers(
    create_env(
      "pkg",
      env_name = env_names[[1L]],
      method = "micromamba",
      verbose = "output"
    ),
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
  testthat::expect_true(all(c("--platform", "osx-64") %in% create_args))
  testthat::expect_no_message(
    create_env(
      "pkg",
      env_name = env_names[[2L]],
      method = "micromamba",
      verbose = "silent"
    )
  )
})

testthat::test_that("micromamba's create and install pass the platform condathis chose, and solve nothing", {
  testthat::skip_on_cran()
  # The front end chooses the platform (see define_platform()): the
  # micromamba backend only turns it into `--platform`, and solves for its
  # own platform without one.
  with_sandbox_dir({
    testthat::local_mocked_bindings(
      define_platform = function(...) stop("must not choose a platform"),
      packages_solve_native = function(...) stop("must not solve"),
      micromamba_native_platform = function(...) stop("must not ask")
    )
    record <- local_fake_native_cmd(stdout = "")
    backend <- micromamba_backend()
    platform_of_call <- function(i) {
      conda_args <- record$calls[[i]]$conda_args
      j <- which(conda_args == "--platform")
      if (identical(length(j), 0L)) {
        return(NULL)
      }
      testthat::expect_length(j, 1L)
      return(conda_args[[j + 1L]])
    }
    create <- function(platform) {
      return(backend_create_env(
        backend,
        packages = "pkg",
        env_name = "platform-pass-env",
        channels = "conda-forge",
        channel_priority = "strict",
        platform = platform,
        overwrite = FALSE,
        verbose = "silent"
      ))
    }
    create("osx-64")
    testthat::expect_identical(record$calls[[1L]]$conda_cmd, "create")
    testthat::expect_identical(platform_of_call(1L), "osx-64")
    create(NULL)
    testthat::expect_null(platform_of_call(2L))

    env_dir <- env_dir_for_backend(backend, "platform-pass-env")
    fs::dir_create(fs::path(env_dir, "conda-meta"))
    fs::file_create(fs::path(env_dir, "conda-meta", "history"))
    # A `.mambarc` platform is the front end's to read, not the backend's.
    cat("platform: win-64", file = fs::path(env_dir, ".mambarc"))
    backend_install(backend, "zstd", env_name = "platform-pass-env")
    testthat::expect_identical(record$calls[[3L]]$conda_cmd, "install")
    testthat::expect_null(platform_of_call(3L))
    backend_install(
      backend,
      "zstd",
      env_name = "platform-pass-env",
      platform = "win-64"
    )
    testthat::expect_identical(platform_of_call(4L), "win-64")
  })
})

testthat::test_that("micromamba's create hook leaves the environment directory to the front end", {
  testthat::skip_on_cran()
  # condathis gives every backend a free directory (see
  # with_env_dir_replacement()), so the hook only runs `micromamba create`.
  # It neither asks whether the environment exists nor moves or deletes
  # anything, also when a directory is there.
  with_sandbox_dir({
    testthat::local_mocked_bindings(
      backend_env_exists = function(...) stop("must not ask"),
      micromamba_binary_in_env_dir = function(...) stop("must not look")
    )
    record <- local_fake_native_cmd(stdout = "")
    backend <- micromamba_backend()
    env_name <- "hook-only-env"
    env_dir <- env_dir_for_backend(backend, env_name)
    fs::dir_create(fs::path(env_dir, "conda-meta"))
    fs::file_create(fs::path(env_dir, "conda-meta", "history"))
    fs::file_create(fs::path(env_dir, "old-file"))

    res <- backend_create_env(
      backend,
      packages = "pkg",
      env_name = env_name,
      overwrite = TRUE,
      verbose = "silent"
    )
    testthat::expect_identical(res$status, 0L)
    testthat::expect_length(record$calls, 1L)
    testthat::expect_identical(record$calls[[1L]]$conda_cmd, "create")
    testthat::expect_true(all(
      c("-n", env_name, "--yes", "--override-channels") %in%
        record$calls[[1L]]$conda_args
    ))
    testthat::expect_true(fs::file_exists(fs::path(env_dir, "old-file")))
    testthat::expect_false(fs::dir_exists(env_trash_dir(backend)))
  })
})

testthat::test_that("micromamba create gets ~ expanded in package paths and the env_file path", {
  # Regression test (R-12): `micromamba create` can run with the home
  # `<root>/home` (see micromamba_create_keeps_home()), so condathis
  # expands `~` itself, with the home that micromamba would use.
  home <- micromamba_user_home()
  testthat::expect_null(resolve_create_env_packages_arg(NULL, NULL))
  testthat::expect_identical(
    resolve_create_env_packages_arg(c("python=3.13", "~/pkg.conda"), NULL),
    c("python=3.13", paste0(home, "/pkg.conda"))
  )
  env_file <- withr::local_tempfile(fileext = ".yml")
  writeLines("dependencies: []", env_file)
  testthat::expect_identical(
    resolve_create_env_packages_arg(NULL, env_file),
    c("-f", as.character(fs::path(env_file)))
  )
  home_file <- fs::path(fs::path_home(), "backend-micromamba-tilde.yml")
  writeLines("dependencies: []", home_file)
  withr::defer(fs::file_delete(home_file))
  testthat::expect_identical(
    resolve_create_env_packages_arg(NULL, "~/backend-micromamba-tilde.yml"),
    c("-f", paste0(home, "/backend-micromamba-tilde.yml"))
  )
})
