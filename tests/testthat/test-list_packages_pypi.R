# The PyPI packages of an environment in list_packages(): micromamba
# 2.10.0 asks the environment's pip (or uv), and condathis's default
# reader, which every backend without its own listing uses, reads the same
# distributions from site-packages (read_pypi_package_records() in
# R/backend-defaults.R). The frames must be identical.

# A fake conda prefix with the package records `records` (a named list of
# lists: name, version, build, subdir) and the `site-packages` directory of
# its python (`site_dir`, relative). Returns the environment directory.
local_fake_prefix <- function(
  records,
  site_dir,
  .local_envir = parent.frame()
) {
  env_dir <- fs::path(
    withr::local_tempdir(.local_envir = .local_envir),
    "fake-env"
  )
  fs::dir_create(fs::path(env_dir, "conda-meta"))
  fs::file_create(fs::path(env_dir, "conda-meta", "history"))
  for (record in records) {
    record$build_number <- 0L
    record$channel <- "https://conda.anaconda.org/conda-forge"
    record$url <- paste0(
      "https://conda.anaconda.org/conda-forge/",
      record$subdir,
      "/",
      record$name,
      "-",
      record$version,
      "-",
      record$build,
      ".conda"
    )
    jsonlite::write_json(
      record,
      fs::path(
        env_dir,
        "conda-meta",
        paste0(record$name, "-", record$version, "-", record$build, ".json")
      ),
      auto_unbox = TRUE
    )
  }
  fs::dir_create(fs::path(env_dir, site_dir))
  return(env_dir)
}

# A distribution in `site_dir`: an `<entry>` directory with `metadata`
# (lines) in `METADATA` (or `PKG-INFO` for `.egg-info`) and `installer` in
# `INSTALLER` (no file when `NULL`).
add_fake_dist <- function(site_dir, entry, metadata, installer = NULL) {
  dist_dir <- fs::path(site_dir, entry)
  fs::dir_create(dist_dir)
  metadata_file <- if (isTRUE(endsWith(entry, ".egg-info"))) {
    "PKG-INFO"
  } else {
    "METADATA"
  }
  writeLines(metadata, fs::path(dist_dir, metadata_file))
  if (isFALSE(is.null(installer))) {
    writeLines(installer, fs::path(dist_dir, "INSTALLER"))
  }
  return(invisible(dist_dir))
}

testthat::test_that("the default listing reads the PyPI packages that pip or uv installed", {
  py <- list(
    name = "python",
    version = "3.12.4",
    build = "h1_cpython",
    subdir = "linux-64"
  )
  pip <- list(
    name = "pip",
    version = "24.0",
    build = "pyh1_0",
    subdir = "noarch"
  )
  pyyaml <- list(
    name = "pyyaml",
    version = "6.0",
    build = "py312h1_0",
    subdir = "linux-64"
  )
  site <- "lib/python3.12/site-packages"
  env_dir <- local_fake_prefix(list(py, pip, pyyaml), site)
  site_dir <- fs::path(env_dir, site)
  add_fake_dist(
    site_dir,
    "Tiny_Pkg-0.1.0.dist-info",
    c("Metadata-Version: 2.1", "Name: Tiny_Pkg", "Version: 0.1.0"),
    "pip"
  )
  add_fake_dist(
    site_dir,
    "uvpkg-2.0.dist-info",
    c("Name:  uvpkg", "Version:\t2.0", "", "Name: not-a-header"),
    "uv\n"
  )
  # Conda's own distributions, and one without an installer: not listed.
  add_fake_dist(
    site_dir,
    "pip-24.0.dist-info",
    c("Name: pip", "Version: 24.0"),
    "conda"
  )
  add_fake_dist(
    site_dir,
    "wheel-0.4.dist-info",
    c("Name: wheel", "Version: 0.4")
  )
  # The Conda package `pyyaml` keeps its row; pip's `PyYAML` has another
  # name, as for micromamba.
  add_fake_dist(
    site_dir,
    "PyYAML-6.0.1.dist-info",
    c("Name: PyYAML", "Version: 6.0.1"),
    "pip"
  )
  # pip skips the names of the standard library.
  add_fake_dist(
    site_dir,
    "wsgiref-0.1.dist-info",
    c("Name: wsgiref", "Version: 0.1"),
    "pip"
  )
  # Without a Name, pip skips the distribution.
  add_fake_dist(site_dir, "noname-1.0.dist-info", "Version: 1.0", "pip")
  # An egg-info directory that pip installed.
  add_fake_dist(
    site_dir,
    "legacy_pkg-1.0-py3.12.egg-info",
    c("Name: legacy-pkg", "Version: 1.0"),
    "pip"
  )
  # One distribution per normalized name: the first.
  add_fake_dist(
    site_dir,
    "Dup.Pkg-1.0.dist-info",
    c("Name: Dup.Pkg", "Version: 1.0"),
    "pip"
  )
  add_fake_dist(
    site_dir,
    "dup_pkg-2.0.dist-info",
    c("Name: dup_pkg", "Version: 2.0"),
    "pip"
  )
  # Other entries are not distributions.
  fs::dir_create(fs::path(site_dir, "tinypkg"))
  writeLines("x", fs::path(site_dir, "distutils-precedence.pth"))

  pkgs <- read_env_package_records(env_dir, "fake-env")
  pypi <- pkgs[pkgs$channel == "pypi", , drop = FALSE]
  testthat::expect_identical(
    pypi$name,
    c("Dup.Pkg", "PyYAML", "Tiny_Pkg", "legacy-pkg", "uvpkg")
  )
  testthat::expect_identical(
    pypi$version,
    c("1.0", "6.0.1", "0.1.0", "1.0", "2.0")
  )
  testthat::expect_identical(unique(pypi$build_string), "pypi_0")
  testthat::expect_identical(unique(pypi$build_number), 0L)
  testthat::expect_identical(unique(pypi$base_url), "https://pypi.org/")
  testthat::expect_identical(unique(pypi$md5), "")
  testthat::expect_identical(unique(pypi$sha256), "")
  testthat::expect_identical(unique(pypi$url), "")
  testthat::expect_identical(
    pypi$dist_name[pypi$name == "Tiny_Pkg"],
    "Tiny_Pkg-0.1.0-pypi_0"
  )
  testthat::expect_identical(
    unique(pypi$platform),
    paste0("linux-", Sys.info()[["machine"]])
  )
  # Sorted by name in the C locale, Conda rows included.
  testthat::expect_identical(pkgs$name, sort(pkgs$name, method = "radix"))
  testthat::expect_identical(
    pkgs$name[pkgs$channel != "pypi"],
    c("pip", "python", "pyyaml")
  )
  # The same rows through the default backend function.
  local_stub_backend(
    "stub-pypi",
    default_root = TRUE,
    backend_list_packages = NULL
  )
  stub_env <- fs::path(backend_root_dir("stub-pypi"), "envs", "pypi-env")
  fs::dir_create(fs::path_dir(stub_env))
  fs::dir_copy(env_dir, stub_env)
  listed <- list_packages("pypi-env", method = "stub-pypi")
  testthat::expect_identical(listed$name, pkgs$name)
  testthat::expect_identical(listed$platform, pkgs$platform)
  # A PyPI row is not a platform of the environment.
  testthat::expect_identical(env_package_platforms(listed), "linux-64")
})

testthat::test_that("without pip, uv's normalized names; without pip and uv, or python, no PyPI rows", {
  py <- list(
    name = "python",
    version = "3.13.1",
    build = "h1_cp313t",
    subdir = "osx-arm64"
  )
  uv <- list(name = "uv", version = "0.5", build = "h1_0", subdir = "osx-arm64")
  six <- list(
    name = "six",
    version = "1.16",
    build = "pyh1_0",
    subdir = "noarch"
  )
  # A free-threading build keeps its packages in lib/python3.13t.
  site <- "lib/python3.13t/site-packages"
  env_dir <- local_fake_prefix(list(py, uv, six), site)
  site_dir <- fs::path(env_dir, site)
  add_fake_dist(
    site_dir,
    "Tiny_Pkg-0.1.0.dist-info",
    c("Name: Tiny_Pkg", "Version: 0.1.0"),
    "uv"
  )
  # A Conda package's name, also when uv installed it, is left out.
  add_fake_dist(
    site_dir,
    "six-1.17.dist-info",
    c("Name: six", "Version: 1.17"),
    "uv"
  )
  # So is the name of an entry that pip and uv did not install.
  add_fake_dist(
    site_dir,
    "conda_only-1.0.dist-info",
    c("Name: conda-only", "Version: 1.0"),
    "conda"
  )
  add_fake_dist(
    site_dir,
    "Conda.Only-2.0.dist-info",
    c("Name: Conda.Only", "Version: 2.0"),
    "pip"
  )
  pkgs <- read_env_package_records(env_dir, "fake-env")
  pypi <- pkgs[pkgs$channel == "pypi", , drop = FALSE]
  testthat::expect_identical(pypi$name, "tiny-pkg")
  testthat::expect_identical(pypi$dist_name, "tiny-pkg-0.1.0-pypi_0")
  # uv's rows have the platform of the environment.
  testthat::expect_identical(pypi$platform, "osx-arm64")
  testthat::expect_identical(
    python_site_packages_dir(env_dir, pkgs[pkgs$name == "python", ]),
    site_dir
  )

  # No pip and no uv.
  fs::file_delete(fs::dir_ls(fs::path(env_dir, "conda-meta"), glob = "*uv-*"))
  testthat::expect_false(
    "pypi" %in% read_env_package_records(env_dir, "fake-env")$channel
  )

  # No python package: micromamba's listing fails without a python
  # program, and the default listing has only the Conda packages.
  pip <- list(
    name = "pip",
    version = "24.0",
    build = "pyh1_0",
    subdir = "noarch"
  )
  env_dir <- local_fake_prefix(list(pip), site)
  add_fake_dist(
    fs::path(env_dir, site),
    "Tiny_Pkg-0.1.0.dist-info",
    c("Name: Tiny_Pkg", "Version: 0.1.0"),
    "pip"
  )
  testthat::expect_identical(
    read_env_package_records(env_dir, "fake-env")$name,
    "pip"
  )

  # A record's `python_site_packages_path` wins; Windows uses Lib.
  win_py <- list(
    name = "python",
    version = "3.12.4",
    build = "h1_cpython",
    subdir = "win-64"
  )
  env_dir <- local_fake_prefix(list(win_py), "Lib/site-packages")
  py_row <- read_conda_package_records(env_dir, "fake-env")
  testthat::expect_identical(
    python_site_packages_dir(env_dir, py_row),
    fs::path(env_dir, "Lib", "site-packages")
  )
  record_file <- fs::dir_ls(fs::path(env_dir, "conda-meta"), glob = "*.json")
  record <- jsonlite::read_json(record_file)
  record$python_site_packages_path <- "Lib/other-site"
  jsonlite::write_json(record, record_file, auto_unbox = TRUE)
  testthat::expect_identical(
    python_site_packages_dir(env_dir, py_row),
    fs::path(env_dir, "Lib/other-site")
  )
})

testthat::test_that("the platform of a PyPI row is pip's", {
  row <- function(subdir, version = "3.12.4") {
    return(data.frame(platform = subdir, version = version))
  }
  testthat::expect_identical(pip_platform_tag(row("osx-arm64")), "darwin-arm64")
  testthat::expect_identical(pip_platform_tag(row("osx-64")), "darwin-x86_64")
  testthat::expect_identical(
    pip_platform_tag(row("linux-64")),
    paste0("linux-", Sys.info()[["machine"]])
  )
  testthat::local_mocked_bindings(windows_native_machine = function() "ARM64")
  testthat::expect_identical(pip_platform_tag(row("win-arm64")), "win32-ARM64")
  # CPython 3.12 reads the processor through WMI, 3.11 the emulated
  # process's variables.
  testthat::expect_identical(pip_platform_tag(row("win-64")), "win32-ARM64")
  testthat::expect_identical(
    pip_platform_tag(row("win-64", "3.11.9")),
    "win32-AMD64"
  )
  testthat::local_mocked_bindings(windows_native_machine = function() "AMD64")
  testthat::expect_identical(pip_platform_tag(row("win-64")), "win32-AMD64")
  testthat::expect_identical(
    pip_platform_tag(row("win-32", "3.10.1")),
    "win32-AMD64"
  )
})

testthat::test_that("micromamba and the default listing give one frame for an environment with pip packages", {
  testthat::skip_on_cran()
  # pip's JSON output has text that is not ASCII (names of maintainers),
  # which jsonlite cannot read in a session that is not UTF-8, such as one
  # in the C locale.
  if (isFALSE(isTRUE(l10n_info()[["UTF-8"]]))) {
    testthat::skip(
      "The R session is not in a UTF-8 locale: run the tests in one."
    )
  }
  # A real environment: python and pip from conda-forge, and a package that
  # pip installs from a wheel built here, with no index.
  testthat::skip_if_offline()
  env_name <- "pypi-list-env"
  withr::defer({
    if (isTRUE(env_exists(env_name, method = "micromamba"))) {
      remove_env(env_name, method = "micromamba", verbose = "silent")
    }
  })
  create_env(
    "python=3.12",
    "pip",
    env_name = env_name,
    method = "micromamba",
    verbose = "silent"
  )
  wheel_dir <- withr::local_tempdir(pattern = "pypi-wheel-")
  wheel <- file.path(wheel_dir, "Tiny_Pkg-0.1.0-py3-none-any.whl")
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
    verbose = "silent"
  )

  backend <- micromamba_backend()
  micromamba_pkgs <- list_packages(env_name, method = "micromamba")
  default_pkgs <- backend_list_packages.default(backend, env_name = env_name)
  testthat::expect_identical(default_pkgs, micromamba_pkgs)
  tiny <- micromamba_pkgs[micromamba_pkgs$name == "Tiny_Pkg", , drop = FALSE]
  testthat::expect_identical(nrow(tiny), 1L)
  testthat::expect_identical(tiny$channel, "pypi")
  testthat::expect_identical(tiny$version, "0.1.0")
  # The platform is what the environment's pip reports.
  pip_platform <- run(
    "python",
    "-c",
    "import platform, sys; print(sys.platform + '-' + platform.machine())",
    env_name = env_name,
    verbose = "silent"
  )
  testthat::expect_identical(tiny$platform, trimws(pip_platform$stdout))
  # The listing without a micromamba binary reads the same.
  local({
    testthat::local_mocked_bindings(native_cmd_if_installed = function(...) {
      NULL
    })
    testthat::expect_identical(
      list_packages(env_name, method = "micromamba"),
      micromamba_pkgs
    )
  })

  # pip also reports the user's site directory and PYTHONPATH, which are
  # not in the environment; condathis's listings leave them out. The user
  # site is moved into a temporary directory first: the sandbox of the
  # tests does not move it when the session sets PYTHONUSERBASE.
  user_base <- normalizePath(
    withr::local_tempdir(pattern = "pypi-userbase-"),
    winslash = "/"
  )
  withr::local_envvar(PYTHONUSERBASE = user_base)
  user_site <- trimws(
    run(
      "python",
      "-c",
      "import site; print(site.getusersitepackages())",
      env_name = env_name,
      verbose = "silent"
    )$stdout
  )
  testthat::expect_true(startsWith(
    normalizePath(user_site, winslash = "/", mustWork = FALSE),
    user_base
  ))
  python_path <- withr::local_tempdir(pattern = "pypi-pythonpath-")
  add_fake_dist(
    user_site,
    "User_Site_Pkg-1.0.dist-info",
    c("Name: User_Site_Pkg", "Version: 1.0"),
    "pip"
  )
  withr::defer(fs::dir_delete(fs::path(
    user_site,
    "User_Site_Pkg-1.0.dist-info"
  )))
  add_fake_dist(
    python_path,
    "Py_Path_Pkg-1.0.dist-info",
    c("Name: Py_Path_Pkg", "Version: 1.0"),
    "pip"
  )
  withr::local_envvar(PYTHONPATH = python_path)
  inspect <- run(
    "python",
    "-m",
    "pip",
    "inspect",
    "--local",
    env_name = env_name,
    verbose = "silent"
  )
  inspected <- jsonlite::fromJSON(inspect$stdout)$installed$metadata$name
  testthat::expect_true(all(c("User_Site_Pkg", "Py_Path_Pkg") %in% inspected))
  testthat::expect_identical(
    list_packages(env_name, method = "micromamba"),
    micromamba_pkgs
  )
  testthat::expect_identical(
    backend_list_packages.default(backend, env_name = env_name),
    micromamba_pkgs
  )
})

testthat::test_that("micromamba and the default listing give one frame for an environment with uv and no pip", {
  testthat::skip_on_cran()
  # micromamba asks uv when the environment has no pip: the names are
  # normalized, and the platform is a Conda one, the one of python (also in
  # an emulated environment, such as win-64 on Windows ARM).
  testthat::skip_if_offline()
  # uv locks the environment with a file in the temporary directory of the
  # system (`TMP` on Windows, which the commands keep), and leaves it there.
  local_child_tempdir()
  env_name <- "pypi-uv-env"
  withr::defer({
    if (isTRUE(env_exists(env_name, method = "micromamba"))) {
      remove_env(env_name, method = "micromamba", verbose = "silent")
    }
  })
  create_env(
    "python=3.12",
    "uv",
    env_name = env_name,
    method = "micromamba",
    verbose = "silent"
  )
  # python brings pip with micromamba: remove pip alone.
  native_cmd(
    conda_cmd = "remove",
    conda_args = c("-n", env_name, "-y", "--force"),
    "pip",
    verbose = "silent"
  )
  env_dir <- get_env_dir(env_name, method = "micromamba")
  python <- if (isTRUE(is_windows())) {
    fs::path(env_dir, "python.exe")
  } else {
    fs::path(env_dir, "bin", "python")
  }
  wheel_dir <- withr::local_tempdir(pattern = "pypi-wheel-")
  wheel <- file.path(wheel_dir, "Tiny_Pkg-0.1.0-py3-none-any.whl")
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
  run(
    "uv",
    "pip",
    "install",
    "--python",
    python,
    "--offline",
    "--no-deps",
    "--no-cache",
    wheel,
    env_name = env_name,
    verbose = "silent"
  )

  micromamba_pkgs <- list_packages(env_name, method = "micromamba")
  testthat::expect_false("pip" %in% micromamba_pkgs$name)
  testthat::expect_true("uv" %in% micromamba_pkgs$name)
  tiny <- micromamba_pkgs[micromamba_pkgs$channel == "pypi", , drop = FALSE]
  testthat::expect_identical(tiny$name, "tiny-pkg")
  testthat::expect_identical(
    tiny$platform,
    micromamba_pkgs$platform[micromamba_pkgs$name == "python"]
  )
  testthat::expect_identical(
    backend_list_packages.default(micromamba_backend(), env_name = env_name),
    micromamba_pkgs
  )
})

testthat::test_that("micromamba_pypi_uv_platform() gives uv's PyPI rows the platform of python", {
  # On Windows ARM, an emulated win-64 environment: micromamba gives the
  # rows that uv reports its own platform.
  pkgs_df <- data.frame(
    name = c("python", "uv", "tiny-pkg"),
    channel = c("conda-forge", "conda-forge", "pypi"),
    platform = c("win-64", "win-64", "win-arm64"),
    stringsAsFactors = FALSE
  )
  testthat::expect_identical(
    micromamba_pypi_uv_platform(pkgs_df)$platform,
    c("win-64", "win-64", "win-64")
  )
  # With pip, the platform is pip's own tag, and is kept.
  with_pip <- rbind(
    pkgs_df,
    data.frame(
      name = "pip",
      channel = "conda-forge",
      platform = "noarch",
      stringsAsFactors = FALSE
    )
  )
  with_pip$platform[3L] <- "win32-ARM64"
  testthat::expect_identical(micromamba_pypi_uv_platform(with_pip), with_pip)
  # Without python, or without PyPI rows, nothing changes.
  no_python <- pkgs_df[-1L, , drop = FALSE]
  testthat::expect_identical(micromamba_pypi_uv_platform(no_python), no_python)
  no_pypi <- pkgs_df[-3L, , drop = FALSE]
  testthat::expect_identical(micromamba_pypi_uv_platform(no_pypi), no_pypi)
  testthat::expect_identical(micromamba_pypi_uv_platform(list()), list())
})
