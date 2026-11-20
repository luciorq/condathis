# The Python state of the R session never reaches a process of condathis
# (decision D18 of feat-run-unify): the commands of the run family, and
# micromamba, which runs pip or uv for the `pip:` section of an environment
# file and `pip inspect` for list_packages().

test_that("every child loses the Python variables of the session", {
  python_vars <- c(
    PYTHONHOME = "/nonexistent",
    PYTHONPATH = "/host/pythonpath",
    PYTHONUSERBASE = "/host/userbase",
    PYTHONSTARTUP = "/host/startup.py",
    UV_PYTHON = "/host/venv/bin/python",
    UV_SYSTEM_PYTHON = "1",
    UV_PROJECT_ENVIRONMENT = "/host/venv"
  )
  withr::local_envvar(c(python_vars, PYTHONNOUSERSITE = "0"))
  child_env <- build_child_env(tmp_dir = withr::local_tempdir())
  for (name in names(python_vars)) {
    testthat::expect_false(name %in% names(child_env), info = name)
  }
  testthat::expect_identical(child_env[["PYTHONNOUSERSITE"]], "1")
  # The pip settings that sent an install elsewhere or stopped it
  # (decision D22); the index, certificate and proxy settings stay.
  local({
    withr::local_envvar(
      PIP_USER = "1",
      PIP_REQUIRE_VIRTUALENV = "1",
      PIP_REQUIRE_VENV = "1",
      PIP_TARGET = "/host/target",
      PIP_PREFIX = "/host/prefix",
      PIP_ROOT = "/host/root",
      PIP_INDEX_URL = "https://index.example/simple",
      PIP_CERT = "/etc/ca.pem",
      PIP_CONFIG_FILE = "/host/pip.conf",
      https_proxy = "http://proxy.example:3128"
    )
    pip_env <- build_child_env(tmp_dir = withr::local_tempdir())
    testthat::expect_identical(pip_env[["PIP_USER"]], "false")
    testthat::expect_identical(pip_env[["PIP_REQUIRE_VIRTUALENV"]], "false")
    for (name in c(
      "PIP_REQUIRE_VENV",
      "PIP_TARGET",
      "PIP_PREFIX",
      "PIP_ROOT"
    )) {
      testthat::expect_false(name %in% names(pip_env), info = name)
    }
    testthat::expect_identical(
      pip_env[["PIP_INDEX_URL"]],
      "https://index.example/simple"
    )
    testthat::expect_identical(pip_env[["PIP_CERT"]], "/etc/ca.pem")
    testthat::expect_identical(pip_env[["PIP_CONFIG_FILE"]], "/host/pip.conf")
    testthat::expect_identical(
      pip_env[["https_proxy"]],
      "http://proxy.example:3128"
    )
  })
  # The activation of an environment comes later, and may set them.
  child_env <- build_child_env(
    tmp_dir = withr::local_tempdir(),
    overlay = c(PYTHONPATH = "/env/lib/extra")
  )
  testthat::expect_identical(child_env[["PYTHONPATH"]], "/env/lib/extra")
  # The session itself keeps them.
  testthat::expect_identical(Sys.getenv("PYTHONPATH"), "/host/pythonpath")
})

test_that("an activated virtual environment of the session is undone", {
  venv <- withr::local_tempdir(pattern = "venv-")
  # The rule off Windows splits PATH on ":", so on Windows (where the
  # directory starts with a drive letter) it gets a POSIX name, and the
  # virtual environment check reads the real directory.
  posix_venv <- if (isTRUE(is_windows())) "/home/user/venv" else venv
  is_venv_posix <- function(dir) {
    if (isTRUE(is_windows())) {
      dir <- sub(posix_venv, venv, dir, fixed = TRUE)
    }
    return(is_python_venv(dir))
  }
  venv_bin <- file.path(posix_venv, "bin")
  env <- list(
    PATH = paste(c("/usr/bin", venv_bin, "/bin"), collapse = ":"),
    VIRTUAL_ENV = posix_venv,
    VIRTUAL_ENV_PROMPT = "(venv) ",
    OTHER = "kept"
  )
  # Without pyvenv.cfg, the directory is not a virtual environment: a
  # stray VIRTUAL_ENV removes no PATH entry.
  testthat::expect_identical(
    undo_host_venv(env, on_windows = FALSE, is_venv = is_venv_posix),
    env
  )
  file.create(file.path(venv, "pyvenv.cfg"))
  undone <- undo_host_venv(env, on_windows = FALSE, is_venv = is_venv_posix)
  testthat::expect_identical(
    undone,
    list(PATH = "/usr/bin:/bin", OTHER = "kept")
  )
  # A trailing separator of the value changes nothing.
  env_slash <- env
  env_slash$VIRTUAL_ENV <- paste0(posix_venv, "/")
  testthat::expect_identical(
    undo_host_venv(env_slash, on_windows = FALSE, is_venv = is_venv_posix),
    list(PATH = "/usr/bin:/bin", OTHER = "kept")
  )
  # On Windows, `Scripts`, compared without case and separator style, and
  # names compared without case.
  env_windows <- list(
    Path = paste(
      c(
        "C:\\Windows",
        paste0(toupper(gsub("/", "\\", venv, fixed = TRUE)), "\\SCRIPTS\\"),
        "C:\\Tools"
      ),
      collapse = ";"
    ),
    virtual_env = venv,
    Virtual_Env_Prompt = "(venv) "
  )
  testthat::expect_identical(
    undo_host_venv(env_windows, on_windows = TRUE),
    list(Path = "C:\\Windows;C:\\Tools")
  )
  # isolate_host_env() undoes it for every child, also when the session set
  # VIRTUAL_ENV with Sys.setenv(), as reticulate does.
  withr::local_envvar(VIRTUAL_ENV = venv)
  withr::local_path(
    file.path(venv, if (isTRUE(is_windows())) "Scripts" else "bin"),
    action = "prefix"
  )
  child_env <- build_child_env(tmp_dir = withr::local_tempdir())
  testthat::expect_false("VIRTUAL_ENV" %in% names(child_env))
  testthat::expect_false(path_names_any(
    env_block_path(child_env),
    file.path(venv, if (isTRUE(is_windows())) "Scripts" else "bin")
  ))
})

test_that("what reticulate changed when it started Python is undone", {
  # reticulate (1.47.0) puts the `lib` directories of its python, and of
  # the real path of that python, in front of LD_LIBRARY_PATH on Linux,
  # and replaces PATH with the activated PATH of a Conda python.
  testthat::expect_null(reticulate_host_state(python = NULL))
  root <- withr::local_tempdir(pattern = "reticulate-")
  if (isTRUE(is_windows())) {
    # dirname() writes `/` on Windows, as reticulate's python path has it.
    root <- normalizePath(root, winslash = "/")
  }
  base <- file.path(root, "base")
  venv <- file.path(root, "venv")
  fs::dir_create(file.path(c(base, venv), "bin"))
  fs::dir_create(file.path(c(base, venv), "lib"))
  file.create(file.path(base, "bin", "python3"))
  python <- file.path(venv, "bin", "python")
  file.create(python)
  # A python that is no link: its path and its real path give the same
  # directory, written twice, as reticulate writes it.
  real_lib <- file.path(
    dirname(dirname(normalizePath(python, mustWork = FALSE))),
    "lib"
  )
  state <- reticulate_host_state(python, on_windows = FALSE, on_linux = TRUE)
  testthat::expect_identical(state$prefix, venv)
  testthat::expect_identical(
    state$ld_library_path,
    c(file.path(venv, "lib"), real_lib)
  )
  testthat::expect_identical(
    reticulate_host_state(python, on_windows = FALSE, on_linux = FALSE),
    list(prefix = venv, ld_library_path = character(0L))
  )
  testthat::expect_identical(
    reticulate_host_state(python, on_windows = TRUE, on_linux = FALSE)$prefix,
    file.path(venv, "bin")
  )
  if (isFALSE(is_windows())) {
    # A venv python is a link to the python it was made from.
    unlink(python)
    file.symlink(file.path(base, "bin", "python3"), python)
    state <- reticulate_host_state(python, on_windows = FALSE, on_linux = TRUE)
    testthat::expect_identical(
      state$ld_library_path,
      c(
        file.path(venv, "lib"),
        file.path(dirname(dirname(normalizePath(python))), "lib")
      )
    )
    testthat::expect_identical(
      basename(dirname(state$ld_library_path[[2L]])),
      "base"
    )
  }

  # LD_LIBRARY_PATH: reticulate's entries leave, then R's own part, and
  # what the user set stays.
  reticulate <- list(
    prefix = "/opt/venv",
    ld_library_path = c("/opt/venv/lib", "/opt/basepy/lib")
  )
  r_startup <- c(LD_LIBRARY_PATH = "/opt/R/lib")
  env <- list(
    LD_LIBRARY_PATH = "/opt/venv/lib:/opt/basepy/lib:/opt/R/lib:/user/lib",
    PATH = "/usr/bin"
  )
  isolated <- isolate_host_env(
    env,
    r_prefix = NULL,
    on_windows = FALSE,
    is_prefix = function(dir) FALSE,
    r_startup = r_startup,
    reticulate = reticulate
  )
  testthat::expect_identical(isolated$LD_LIBRARY_PATH, "/user/lib")
  # Without reticulate's entries in front, nothing of them is removed.
  env_user <- list(LD_LIBRARY_PATH = "/user/lib:/opt/venv/lib:/opt/basepy/lib")
  testthat::expect_identical(
    undo_reticulate_library_path(
      env_user,
      reticulate$ld_library_path,
      on_windows = FALSE
    ),
    env_user
  )
  # An unset LD_LIBRARY_PATH became `<entries>:NA`; it is unset again.
  testthat::expect_identical(
    undo_reticulate_library_path(
      list(LD_LIBRARY_PATH = "/opt/venv/lib:/opt/basepy/lib:NA", A = "a"),
      reticulate$ld_library_path,
      on_windows = FALSE
    ),
    list(A = "a")
  )
  # Not on Windows, where reticulate does not change it.
  env_windows <- list(LD_LIBRARY_PATH = "/opt/venv/lib:/opt/basepy/lib")
  testthat::expect_identical(
    undo_reticulate_library_path(
      env_windows,
      reticulate$ld_library_path,
      on_windows = TRUE
    ),
    env_windows
  )

  # PATH: the binary directories of a Conda python leave PATH. A root that
  # is no Conda prefix removes nothing, and the root changes no other
  # variable.
  conda_env <- "/opt/conda/envs/r-reticulate"
  env <- list(
    PATH = paste0(conda_env, "/bin:/opt/conda/condabin:/usr/bin"),
    MY_VAR = "kept"
  )
  isolated <- isolate_host_env(
    env,
    r_prefix = NULL,
    on_windows = FALSE,
    is_prefix = function(dir) identical(dir, conda_env),
    r_startup = NULL,
    reticulate = list(prefix = conda_env, ld_library_path = character(0L))
  )
  testthat::expect_identical(
    isolated,
    list(PATH = "/opt/conda/condabin:/usr/bin", MY_VAR = "kept")
  )
  testthat::expect_identical(
    isolate_host_env(
      env,
      r_prefix = NULL,
      on_windows = FALSE,
      is_prefix = function(dir) FALSE,
      r_startup = NULL,
      reticulate = list(prefix = conda_env, ld_library_path = character(0L))
    ),
    env
  )
  # On Windows the root is the directory of python.exe, and every binary
  # directory of it leaves PATH.
  conda_env_windows <- "C:\\conda\\envs\\r-reticulate"
  env_windows <- list(
    Path = paste(
      c(
        conda_env_windows,
        paste0(conda_env_windows, "\\Library\\bin"),
        paste0(conda_env_windows, "\\Scripts"),
        "C:\\Windows"
      ),
      collapse = ";"
    )
  )
  testthat::expect_identical(
    isolate_host_env(
      env_windows,
      r_prefix = NULL,
      on_windows = TRUE,
      is_prefix = function(dir) identical(dir, conda_env_windows),
      r_startup = NULL,
      reticulate = list(
        prefix = conda_env_windows,
        ld_library_path = character(0L)
      )
    ),
    list(Path = "C:\\Windows")
  )

  # The python of the session: none unless reticulate is loaded and
  # started one.
  session_python <- reticulate_session_python()
  testthat::expect_true(
    is.null(session_python) || rlang::is_string(session_python)
  )
  if (isFALSE(isNamespaceLoaded("reticulate"))) {
    testthat::expect_null(session_python)
    testthat::expect_null(reticulate_host_state())
  }
})

test_that("the activation of a pixi global binary that started R is undone", {
  # A pixi global binary starts R with the whole activation of its
  # environment, recorded in its trampoline configuration, compiler
  # variables included, with no backups to restore.
  pixi_home <- withr::local_tempdir(pattern = "pixi-home-")
  for (on_windows in c(FALSE, TRUE)) {
    info <- paste("on_windows:", on_windows)
    prefix <- file.path(pixi_home, "envs", if (on_windows) "rw" else "r")
    fs::dir_create(file.path(prefix, "conda-meta"))
    config_dir <- file.path(pixi_home, "bin", "trampoline_configuration")
    fs::dir_create(config_dir)
    exe <- if (on_windows) {
      paste0(gsub("/", "\\", prefix, fixed = TRUE), "\\Scripts\\R.exe")
    } else {
      file.path(prefix, "bin", "R")
    }
    sysroot <- file.path(prefix, "sysroot")
    jsonlite::write_json(
      list(
        exe = exe,
        path_diff = file.path(prefix, "bin"),
        env = list(
          CC = "x86_64-conda-linux-gnu-cc",
          CFLAGS = "-O2 -isystem /p/include",
          CONDA_BUILD_SYSROOT = sysroot,
          CONDA_BUILD_CROSS_COMPILATION = "",
          XDG_DATA_DIRS = "/p/share:/usr/share",
          PATH = "/must/not/matter"
        )
      ),
      file.path(config_dir, if (on_windows) "Rw.json" else "R.json"),
      auto_unbox = TRUE
    )
    vars <- read_trampoline_env_vars(
      prefix,
      on_windows = on_windows,
      use_cache = FALSE
    )
    testthat::expect_false("PATH" %in% names(vars), info = info)
    testthat::expect_identical(vars$CONDA_BUILD_SYSROOT, sysroot, info = info)
    env <- list(
      CONDA_PREFIX = prefix,
      CC = "x86_64-conda-linux-gnu-cc",
      CFLAGS = "-O2 -user",
      CONDA_BUILD_SYSROOT = sysroot,
      CONDA_BUILD_CROSS_COMPILATION = "",
      XDG_DATA_DIRS = "/p/share:/usr/share",
      XDG_DATA_DIRS_CONDA_BACKUP = "/usr/share",
      PATH = "/usr/bin"
    )
    isolated <- isolate_host_env(
      env,
      r_prefix = NULL,
      on_windows = on_windows,
      r_startup = NULL
    )
    # Exactly the recorded values leave, a value that the user changed
    # since stays, and a backup is restored first.
    for (name in c(
      "CC",
      "CONDA_BUILD_SYSROOT",
      "CONDA_BUILD_CROSS_COMPILATION"
    )) {
      testthat::expect_null(isolated[[name]], info = paste(info, name))
    }
    testthat::expect_identical(isolated$CFLAGS, "-O2 -user", info = info)
    testthat::expect_identical(
      isolated$XDG_DATA_DIRS,
      "/usr/share",
      info = info
    )
  }
  # A prefix that is not an environment of pixi global has none.
  testthat::expect_identical(
    read_trampoline_env_vars(
      file.path(pixi_home, "elsewhere"),
      on_windows = FALSE,
      use_cache = FALSE
    ),
    list()
  )
})

test_that("micromamba's own processes get the pip and venv overrides", {
  root <- withr::local_tempdir()
  # The pip settings come from `python_isolation_envvars()` for every
  # child (decision D22); create and install also lose any VIRTUAL_ENV.
  for (cmd in c("create", "install")) {
    overlay <- micromamba_cmd_overlay(cmd, c("-n", "e"), root_dir = root)
    for (name in c("VIRTUAL_ENV", "VIRTUAL_ENV_PROMPT")) {
      testthat::expect_true(
        name %in% names(overlay) && is.na(overlay[[name]]),
        info = paste(cmd, name)
      )
    }
  }
  overlay <- micromamba_cmd_overlay("list", c("-n", "e"), root_dir = root)
  testthat::expect_identical(
    overlay[["PIP_CONFIG_FILE"]],
    if (isTRUE(is_windows())) "nul" else "/dev/null"
  )
  testthat::expect_identical(overlay[["PIP_USER"]], "false")
  testthat::expect_true(is.na(overlay[["PIP_PATH"]]))
  testthat::expect_true(is.na(overlay[["PIP_LOCAL"]]))
  testthat::expect_identical(
    micromamba_pip_inspect_vars(on_windows = TRUE)[["PIP_CONFIG_FILE"]],
    "nul"
  )
  # The index, credential, certificate and proxy settings pass through.
  withr::local_envvar(
    PIP_INDEX_URL = "https://index.example/simple",
    PIP_CERT = "/etc/ca.pem",
    PIP_USER = "1",
    VIRTUAL_ENV = "/not/a/venv",
    PIP_REQUIRE_VIRTUALENV = "1",
    PIP_TARGET = "/host/target",
    PIP_PREFIX = "/host/prefix",
    PIP_ROOT = "/host/root",
    https_proxy = "http://proxy.example:3128",
    CONDA_OVERRIDE_CUDA = "12.4"
  )
  child_env <- build_child_env(
    tmp_dir = withr::local_tempdir(),
    overlay = micromamba_cmd_overlay("create", c("-n", "e"), root_dir = root)
  )
  testthat::expect_identical(child_env[["PIP_REQUIRE_VIRTUALENV"]], "false")
  for (name in c("PIP_TARGET", "PIP_PREFIX", "PIP_ROOT")) {
    testthat::expect_false(name %in% names(child_env), info = name)
  }
  testthat::expect_identical(
    child_env[["PIP_INDEX_URL"]],
    "https://index.example/simple"
  )
  testthat::expect_identical(child_env[["PIP_CERT"]], "/etc/ca.pem")
  testthat::expect_identical(
    child_env[["https_proxy"]],
    "http://proxy.example:3128"
  )
  testthat::expect_identical(child_env[["CONDA_OVERRIDE_CUDA"]], "12.4")
  testthat::expect_identical(child_env[["PIP_USER"]], "false")
  testthat::expect_false("VIRTUAL_ENV" %in% names(child_env))
  # Other commands get the pip settings of every child (decision D22),
  # and keep a VIRTUAL_ENV that names no virtual environment.
  child_env <- build_child_env(
    tmp_dir = withr::local_tempdir(),
    overlay = micromamba_cmd_overlay("info", "--json", root_dir = root)
  )
  testthat::expect_identical(child_env[["PIP_USER"]], "false")
  testthat::expect_identical(child_env[["VIRTUAL_ENV"]], "/not/a/venv")
})

test_that("micromamba list runs in its temporary directory", {
  # A `pip` package in the working directory of R ran in place of the
  # environment's pip, as `python -m pip` imports from there first.
  seen <- new.env(parent = emptyenv())
  seen$wd <- list()
  root <- withr::local_tempdir()
  fake_micromamba <- file.path(root, "micromamba")
  file.create(fake_micromamba)
  testthat::local_mocked_bindings(
    get_best_micromamba_path = function(...) fake_micromamba,
    install_dir_for_backend = function(...) root,
    ensure_condathis_rc_file = function(...) file.path(root, "rc.yaml"),
    execute_command = function(..., wd = NULL) {
      seen$wd <- c(seen$wd, list(wd))
      return(list(status = 0L, stdout = "", stderr = "", timeout = FALSE))
    }
  )
  native_cmd("list", c("-n", "e", "--json"), verbose = "silent")
  native_cmd("create", c("-n", "e"), "pkg", verbose = "silent")
  testthat::expect_length(seen$wd, 2L)
  testthat::expect_true(rlang::is_string(seen$wd[[1L]]))
  testthat::expect_match(seen$wd[[1L]], "mamba-tmp", fixed = TRUE)
  testthat::expect_null(seen$wd[[2L]])
})

test_that("the pip entries of an environment file are read and checked", {
  text <- c(
    "name: x",
    "channels: [conda-forge]",
    "dependencies:",
    "  - python",
    "  - pip",
    "  - pip:",
    "    - six==1.17.0  # a comment",
    "    - '-r requirements.txt'",
    "",
    "    # a comment line",
    "    - \"./local-pkg\"",
    "  - zlib"
  )
  testthat::expect_identical(
    env_file_pip_entries(text),
    c("six==1.17.0", "-r requirements.txt", "./local-pkg")
  )
  testthat::expect_identical(
    env_file_pip_entries(c("dependencies:", "  - pip: [six, ./x]")),
    c("six", "./x")
  )
  testthat::expect_identical(
    env_file_pip_entries(c("dependencies:", "  - pip")),
    character(0L)
  )
  relative <- c(
    "-r requirements.txt",
    "-rrequirements.txt",
    "--requirement=reqs/a.txt",
    "-c constraints.txt",
    "-e .",
    "--editable ../pkg",
    "--find-links=./wheels",
    "./pkg",
    "sub/dir",
    "pkg-1.0-py3-none-any.whl",
    "pkg @ ./x",
    "file:../x"
  )
  not_relative <- c(
    "six==1.17.0",
    "numpy>=1.26",
    "pkg[extra]==1",
    "-r /abs/requirements.txt",
    "-e git+https://example.org/x.git#egg=x",
    "--index-url https://example.org/simple",
    "/abs/pkg-1.0-py3-none-any.whl",
    "C:\\pkgs\\pkg-1.0-py3-none-any.whl",
    "~/pkg.whl",
    "$HOME/pkg.whl",
    "pkg @ https://example.org/pkg.whl",
    "pkg @ file:///abs/pkg.whl"
  )
  for (entry in relative) {
    testthat::expect_true(pip_entry_is_relative(entry), info = entry)
  }
  for (entry in not_relative) {
    testthat::expect_false(pip_entry_is_relative(entry), info = entry)
  }
})

test_that("an environment file in a read-only directory is copied or refused", {
  # micromamba writes the requirements of a `pip:` section to a file next
  # to the environment file. Writability is mocked, so this runs on every
  # OS and as any user.
  dir <- withr::local_tempdir(pattern = "env-file-")
  tmp_dir <- withr::local_tempdir(pattern = "mamba-tmp")
  pip_file <- file.path(dir, "pip-env.yml")
  writeLines(
    c("dependencies:", "  - python", "  - pip", "  - pip:", "    - six"),
    pip_file
  )
  plain_file <- file.path(dir, "plain-env.yml")
  writeLines(c("dependencies:", "  - python"), plain_file)
  relative_file <- file.path(dir, "relative-env.yml")
  writeLines(
    c("dependencies:", "  - pip", "  - pip:", "    - -r requirements.txt"),
    relative_file
  )
  writable <- function(dir) TRUE
  read_only <- function(dir) FALSE
  testthat::expect_null(micromamba_pip_env_file(NULL, tmp_dir))
  testthat::expect_identical(
    micromamba_pip_env_file(pip_file, tmp_dir, is_writable = writable),
    pip_file
  )
  testthat::expect_identical(
    micromamba_pip_env_file(plain_file, tmp_dir, is_writable = read_only),
    plain_file
  )
  # A file without pip is never probed: on Windows the probe creates a file
  # in the user's directory.
  never_asked <- function(dir) stop("is_writable() was called", call. = FALSE)
  testthat::expect_identical(
    micromamba_pip_env_file(plain_file, tmp_dir, is_writable = never_asked),
    plain_file
  )
  copy <- micromamba_pip_env_file(pip_file, tmp_dir, is_writable = read_only)
  testthat::expect_identical(copy, file.path(tmp_dir, "pip-env.yml"))
  testthat::expect_identical(readLines(copy), readLines(pip_file))
  testthat::expect_error(
    micromamba_pip_env_file(relative_file, tmp_dir, is_writable = read_only),
    class = "condathis_micromamba_env_file_dir_not_writable"
  )
  # The backend refuses it before micromamba starts.
  testthat::local_mocked_bindings(
    dir_is_writable = function(dir) FALSE,
    native_cmd = function(...) stop("micromamba must not start", call. = FALSE)
  )
  testthat::expect_error(
    micromamba_backend_create_env(
      micromamba_backend(),
      env_file = relative_file,
      env_name = "never-created",
      verbose = "silent"
    ),
    class = "condathis_micromamba_env_file_dir_not_writable"
  )
})

test_that("clean_cache() deletes the user site directory of the moved home", {
  testthat::skip_on_cran()
  condathis::with_sandbox_dir({
    testthat::local_mocked_bindings(
      native_cmd = function(...) {
        stop("no micromamba command expected", call. = FALSE)
      }
    )
    root <- get_condathis_path()
    site <- fs::path(root, "home", ".local", "lib", "python3.12")
    fs::dir_create(site)
    fs::file_touch(fs::path(site, "six.py"))
    registry <- fs::path(root, "home", ".conda", "environments.txt")
    fs::dir_create(fs::path_dir(registry))
    fs::file_touch(registry)
    clean_cache(verbose = "silent")
    testthat::expect_false(fs::dir_exists(fs::path(root, "home", ".local")))
    testthat::expect_true(fs::file_exists(registry))
  })
})

# The integration tests below need conda-forge and build a tiny wheel, so
# pip installs it from a path, without an index.

python_iso_wheel <- function(env_name, dir) {
  wheel <- file.path(dir, "Tiny_Pkg-0.1.0-py3-none-any.whl")
  wheel_code <- paste(
    "import base64, hashlib, sys, zipfile",
    "info = 'Tiny_Pkg-0.1.0.dist-info/'",
    "files = {'tinypkg/__init__.py': b'x = 1\\n',",
    "  info + 'METADATA': b'Metadata-Version: 2.1\\nName: Tiny_Pkg\\nVersion: 0.1.0\\n',",
    "  info + 'WHEEL': b'Wheel-Version: 1.0\\nGenerator: test\\nRoot-Is-Purelib: true\\nTag: py3-none-any\\n'}",
    "digest = lambda v: base64.urlsafe_b64encode(hashlib.sha256(v).digest()).rstrip(b'=').decode()",
    "record = ['%s,sha256=%s,%d' % (k, digest(v), len(v)) for k, v in files.items()]",
    "record.append(info + 'RECORD,,')",
    "z = zipfile.ZipFile(sys.argv[1], 'w')",
    "[z.writestr(k, v) for k, v in files.items()]",
    "z.writestr(info + 'RECORD', '\\n'.join(record) + '\\n')",
    "z.close()",
    sep = "\n"
  )
  run(
    "python",
    "-I",
    "-c",
    wheel_code,
    wheel,
    env_name = env_name,
    verbose = "silent"
  )
  return(normalizePath(wheel, winslash = "/", mustWork = TRUE))
}

# Where `import tinypkg` finds the package in an environment, or `NA`.
python_iso_tinypkg_dir <- function(env_name) {
  res <- run(
    "python",
    "-I",
    "-c",
    "import os, tinypkg; print(os.path.dirname(tinypkg.__file__))",
    env_name = env_name,
    error = "continue",
    verbose = "silent"
  )
  if (isFALSE(identical(res$status, 0L))) {
    return(NA_character_)
  }
  return(normalizePath(trimws(res$stdout), winslash = "/", mustWork = FALSE))
}

python_iso_env_file <- function(dir, wheel, uv = FALSE) {
  path <- file.path(dir, "pip-env.yml")
  writeLines(
    c(
      "channels:",
      "  - conda-forge",
      "dependencies:",
      "  - python=3.12",
      "  - pip",
      if (isTRUE(uv)) "  - uv",
      "  - pip:",
      paste0("    - ", wheel)
    ),
    path
  )
  return(path)
}

python_iso_remove_env <- function(env_name, envir = parent.frame()) {
  withr::defer(
    {
      if (isTRUE(env_exists(env_name, method = "micromamba"))) {
        remove_env(env_name, method = "micromamba", verbose = "silent")
      }
    },
    envir = envir
  )
}

# A real virtual environment, made by the python of `env_name`.
python_iso_venv <- function(env_name, dir) {
  venv <- file.path(dir, "host-venv")
  run(
    "python",
    "-m",
    "venv",
    "--without-pip",
    venv,
    env_name = env_name,
    verbose = "silent"
  )
  return(normalizePath(venv, winslash = "/", mustWork = TRUE))
}

test_that("python in the run family and micromamba never sees the Python state of the session", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  local_child_tempdir()
  base_env <- "pyiso-base"
  python_iso_remove_env(base_env)
  create_env(
    "python=3.12",
    "pip",
    env_name = base_env,
    method = "micromamba",
    verbose = "silent"
  )
  work <- normalizePath(
    withr::local_tempdir(pattern = "pyiso-"),
    winslash = "/"
  )
  wheel <- python_iso_wheel(base_env, work)
  venv <- python_iso_venv(base_env, work)
  venv_bin <- file.path(venv, if (isTRUE(is_windows())) "Scripts" else "bin")

  # A PYTHONPATH and a user site that hold a fake tinypkg: pip once saw
  # them as "already satisfied", and python found them first.
  fake_site <- file.path(work, "fake-site")
  dir.create(file.path(fake_site, "tinypkg"), recursive = TRUE)
  writeLines("x = 'host'", file.path(fake_site, "tinypkg", "__init__.py"))
  dir.create(file.path(fake_site, "Tiny_Pkg-0.1.0.dist-info"))
  writeLines(
    c("Metadata-Version: 2.1", "Name: Tiny_Pkg", "Version: 0.1.0"),
    file.path(fake_site, "Tiny_Pkg-0.1.0.dist-info", "METADATA")
  )
  writeLines("", file.path(fake_site, "Tiny_Pkg-0.1.0.dist-info", "RECORD"))
  pip_target <- file.path(work, "pip-target")
  dir.create(pip_target)

  # The commands of the run family, with Sys.setenv() as reticulate does.
  local({
    withr::local_envvar(
      PYTHONPATH = fake_site,
      PYTHONHOME = file.path(work, "no-such-home"),
      PYTHONUSERBASE = file.path(work, "userbase"),
      VIRTUAL_ENV = venv
    )
    withr::local_path(venv_bin, action = "prefix")
    for (activate in c(TRUE, FALSE)) {
      res <- run(
        "python",
        "-c",
        "import sys, os; print(sys.prefix); print(os.environ.get('VIRTUAL_ENV', '')); print(os.pathsep.join(p.replace(os.sep, '/') for p in sys.path))",
        env_name = base_env,
        activate = activate,
        verbose = "silent"
      )
      out <- strsplit(trimws(res$stdout), "\r?\n")[[1L]]
      info <- paste("activate:", activate)
      testthat::expect_identical(
        normalizePath(out[[1L]], winslash = "/"),
        normalizePath(get_env_dir(base_env), winslash = "/"),
        info = info
      )
      testthat::expect_identical(out[[2L]], "", info = info)
      testthat::expect_no_match(out[[3L]], fake_site, fixed = TRUE, info = info)
    }
  })

  # micromamba create with every variable that sent the pip packages
  # elsewhere or stopped pip.
  env_vars <- "pyiso-envvars"
  python_iso_remove_env(env_vars)
  local({
    withr::local_envvar(
      PYTHONPATH = fake_site,
      PYTHONUSERBASE = fake_site,
      PIP_USER = "1",
      PIP_REQUIRE_VIRTUALENV = "1",
      PIP_TARGET = pip_target,
      VIRTUAL_ENV = venv
    )
    create_env(
      env_definition(python_iso_env_file(
        withr::local_tempdir(pattern = "pyiso-file-"),
        wheel
      )),
      env_name = env_vars,
      method = "micromamba",
      verbose = "silent"
    )
  })
  installed <- python_iso_tinypkg_dir(env_vars)
  testthat::expect_true(startsWith(
    installed,
    normalizePath(get_env_dir(env_vars), winslash = "/")
  ))
  testthat::expect_length(list.files(pip_target), 0L)
  testthat::expect_false(dir.exists(
    fs::path(get_condathis_path(), "home", ".local")
  ))

  # The same settings in a pip configuration file, in a directory that
  # micromamba cannot write next to (where the OS allows it).
  env_conf <- "pyiso-pipconf"
  python_iso_remove_env(env_conf)
  pip_conf <- file.path(work, "pip.conf")
  writeLines(
    c("[global]", "require-virtualenv = true", "[install]", "user = true"),
    pip_conf
  )
  file_dir <- withr::local_tempdir(pattern = "pyiso-ro-")
  env_file <- python_iso_env_file(file_dir, wheel)
  read_only <- isFALSE(is_windows())
  if (isTRUE(read_only)) {
    Sys.chmod(file_dir, "0555")
    withr::defer(Sys.chmod(file_dir, "0755"))
    # A user that can write anyway (root) tests the pip.conf case only.
    read_only <- isFALSE(dir_is_writable(file_dir))
  }
  local({
    withr::local_envvar(PIP_CONFIG_FILE = pip_conf)
    create_env(
      env_definition(env_file),
      env_name = env_conf,
      method = "micromamba",
      verbose = "silent"
    )
  })
  installed <- python_iso_tinypkg_dir(env_conf)
  testthat::expect_true(startsWith(
    installed,
    normalizePath(get_env_dir(env_conf), winslash = "/")
  ))
  if (isTRUE(read_only)) {
    relative_dir <- withr::local_tempdir(pattern = "pyiso-ro-rel-")
    writeLines(
      c("dependencies:", "  - pip", "  - pip:", "    - -r requirements.txt"),
      file.path(relative_dir, "rel-env.yml")
    )
    Sys.chmod(relative_dir, "0555")
    withr::defer(Sys.chmod(relative_dir, "0755"))
    testthat::expect_error(
      create_env(
        env_definition(file.path(relative_dir, "rel-env.yml")),
        env_name = "pyiso-never",
        method = "micromamba",
        verbose = "silent"
      ),
      class = "condathis_micromamba_env_file_dir_not_writable"
    )
    testthat::expect_false(env_exists("pyiso-never", method = "micromamba"))
  }

  # list_packages() from a working directory with a `pip` package, and
  # with the pip settings that restricted `pip inspect`.
  run(
    "python",
    "-m",
    "pip",
    "install",
    "--no-index",
    "--no-deps",
    "--no-cache-dir",
    "--disable-pip-version-check",
    wheel,
    env_name = base_env,
    verbose = "silent"
  )
  cwd <- file.path(work, "cwd")
  dir.create(file.path(cwd, "pip"), recursive = TRUE)
  marker <- file.path(work, "CWD_PIP_RAN")
  writeLines(
    c(
      paste0("open(", deparse(marker), ", 'w').close()"),
      "print('{\"version\": \"1\", \"installed\": []}')"
    ),
    file.path(cwd, "pip", "__main__.py")
  )
  file.create(file.path(cwd, "pip", "__init__.py"))
  local({
    withr::local_dir(cwd)
    withr::local_envvar(PIP_USER = "1", PIP_PATH = fake_site)
    pkgs <- list_packages(base_env, method = "micromamba", verbose = "silent")
    testthat::expect_true("Tiny_Pkg" %in% pkgs$name)
  })
  testthat::expect_false(file.exists(marker))
})

test_that("pip install in the run family installs into the environment whatever the pip settings of the session", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  local_child_tempdir()
  env_name <- "pyiso-pipinstall"
  python_iso_remove_env(env_name)
  create_env(
    "python=3.12",
    "pip",
    env_name = env_name,
    method = "micromamba",
    verbose = "silent"
  )
  work <- normalizePath(
    withr::local_tempdir(pattern = "pyiso-pip-"),
    winslash = "/"
  )
  wheel <- python_iso_wheel(env_name, work)
  env_dir <- normalizePath(get_env_dir(env_name), winslash = "/")
  pip_install <- function() {
    run(
      "python",
      "-m",
      "pip",
      "install",
      "--no-index",
      "--no-deps",
      "--no-cache-dir",
      "--disable-pip-version-check",
      wheel,
      env_name = env_name,
      error = "continue",
      verbose = "silent"
    )
  }
  pip_uninstall <- function() {
    run(
      "python",
      "-m",
      "pip",
      "uninstall",
      "-y",
      "--disable-pip-version-check",
      "Tiny_Pkg",
      env_name = env_name,
      error = "continue",
      verbose = "silent"
    )
  }
  # A home and configuration directories of the test, where pip looks for
  # its user configuration file on each OS. On Windows, pip finds the home
  # through USERPROFILE, not HOME, and reads `<home>/pip/pip.ini` and the
  # roaming application data folder of the profile, not APPDATA.
  conf_home <- file.path(work, "home")
  conf_dirs <- c(
    file.path(work, "xdg-config", "pip"),
    file.path(conf_home, ".config", "pip"),
    file.path(conf_home, ".pip"),
    file.path(conf_home, "pip"),
    file.path(conf_home, "Library", "Application Support", "pip"),
    file.path(conf_home, "AppData", "Roaming", "pip"),
    file.path(work, "appdata", "pip")
  )
  scenarios <- list(
    pip_user = list(vars = c(PIP_USER = "1"), conf = NULL),
    require_virtualenv = list(
      vars = c(PIP_REQUIRE_VIRTUALENV = "1"),
      conf = NULL
    ),
    pip_conf = list(
      vars = character(0L),
      conf = c("[global]", "require-virtualenv = true", "user = true")
    ),
    install_target = list(
      vars = c(
        PIP_TARGET = file.path(work, "target"),
        PIP_PREFIX = file.path(work, "prefix")
      ),
      conf = NULL
    )
  )
  for (case in names(scenarios)) {
    scenario <- scenarios[[case]]
    local({
      if (isFALSE(is.null(scenario$conf))) {
        for (dir in conf_dirs) {
          dir.create(dir, recursive = TRUE, showWarnings = FALSE)
          writeLines(scenario$conf, file.path(dir, "pip.conf"))
          writeLines(scenario$conf, file.path(dir, "pip.ini"))
        }
        withr::defer(unlink(
          c(
            file.path(work, "xdg-config"),
            conf_home,
            file.path(work, "appdata")
          ),
          recursive = TRUE
        ))
        conf_vars <- c(
          HOME = conf_home,
          XDG_CONFIG_HOME = file.path(work, "xdg-config"),
          PIP_CONFIG_FILE = NA
        )
        if (isTRUE(is_windows())) {
          conf_vars <- c(
            conf_vars,
            USERPROFILE = conf_home,
            APPDATA = file.path(work, "appdata")
          )
        }
        withr::local_envvar(conf_vars)
        # The child's pip reads the file: the overrides, not a missing
        # file, are why the install works.
        conf_list <- run(
          "python",
          "-m",
          "pip",
          "config",
          "list",
          env_name = env_name,
          verbose = "silent"
        )
        testthat::expect_match(
          conf_list$stdout,
          "require-virtualenv='true'",
          fixed = TRUE,
          info = case
        )
      }
      if (isTRUE(length(scenario$vars) > 0L)) {
        withr::local_envvar(scenario$vars)
      }
      res <- pip_install()
      testthat::expect_identical(
        res$status,
        0L,
        info = paste(case, res$stderr)
      )
      installed <- python_iso_tinypkg_dir(env_name)
      testthat::expect_true(startsWith(installed, env_dir), info = case)
      pip_uninstall()
    })
    testthat::expect_false(dir.exists(file.path(work, "target")), info = case)
    testthat::expect_false(dir.exists(file.path(work, "prefix")), info = case)
    testthat::expect_false(
      dir.exists(file.path(conf_home, ".local")),
      info = case
    )
  }
})

test_that("uv in micromamba create never installs into a virtual environment of the session", {
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  local_child_tempdir()
  base_env <- "pyiso-uv-base"
  python_iso_remove_env(base_env)
  create_env(
    "python=3.12",
    env_name = base_env,
    method = "micromamba",
    verbose = "silent"
  )
  work <- normalizePath(
    withr::local_tempdir(pattern = "pyiso-uv-"),
    winslash = "/"
  )
  wheel <- python_iso_wheel(base_env, work)
  venv <- python_iso_venv(base_env, work)
  venv_python <- file.path(
    venv,
    if (isTRUE(is_windows())) "Scripts/python.exe" else "bin/python"
  )
  env_uv <- "pyiso-uv"
  python_iso_remove_env(env_uv)
  local({
    withr::local_envvar(
      VIRTUAL_ENV = venv,
      UV_PYTHON = venv_python,
      UV_SYSTEM_PYTHON = "1"
    )
    create_env(
      env_definition(python_iso_env_file(
        withr::local_tempdir(pattern = "pyiso-uv-file-"),
        wheel,
        uv = TRUE
      )),
      env_name = env_uv,
      method = "micromamba",
      verbose = "silent"
    )
  })
  installed <- python_iso_tinypkg_dir(env_uv)
  testthat::expect_true(startsWith(
    installed,
    normalizePath(get_env_dir(env_uv), winslash = "/")
  ))
  venv_files <- list.files(venv, recursive = TRUE)
  testthat::expect_false(any(grepl("tinypkg|Tiny_Pkg", venv_files)))
})

test_that("dir_is_writable() answers for a writable directory on every rule", {
  dir <- withr::local_tempdir(pattern = "writable-")
  testthat::expect_true(dir_is_writable(dir, on_windows = FALSE))
  testthat::expect_true(dir_is_writable(dir, on_windows = TRUE))
  # The Windows probe leaves nothing behind.
  testthat::expect_identical(
    list.files(dir, all.files = TRUE, no.. = TRUE),
    character(0L)
  )
  missing_dir <- file.path(dir, "missing")
  testthat::expect_false(dir_is_writable(missing_dir, on_windows = FALSE))
  testthat::expect_false(dir_is_writable(missing_dir, on_windows = TRUE))
})
