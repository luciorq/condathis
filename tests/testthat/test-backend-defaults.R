# The default functions of the backend contract (R/backend-defaults.R),
# each against a stub backend without the function: no micromamba, no
# network. The stubs keep their environments in `backend_root_dir(name)`
# (`default_root = TRUE`), inside the sandbox of the test process.

# Writes a conda prefix: `conda-meta/history` and one package record per
# element of `records` (a list of record fields).
write_conda_prefix <- function(env_dir, records = list()) {
  meta_dir <- fs::path(env_dir, "conda-meta")
  fs::dir_create(meta_dir)
  fs::file_create(fs::path(meta_dir, "history"))
  for (record in records) {
    record_file <- fs::path(
      meta_dir,
      paste0(record$name, "-", record$version, "-", record$build, ".json")
    )
    jsonlite::write_json(record, record_file, auto_unbox = TRUE)
  }
  return(invisible(env_dir))
}

# A package record as conda and micromamba write it.
conda_record <- function(name, version = "1.0", files = list()) {
  return(list(
    name = name,
    version = version,
    build = "h0_0",
    build_number = 0L,
    subdir = "noarch",
    channel = "https://conda.anaconda.org/conda-forge/noarch",
    url = paste0(
      "https://conda.anaconda.org/conda-forge/noarch/",
      name,
      "-",
      version,
      "-h0_0.conda"
    ),
    md5 = "d41d8cd98f00b204e9800998ecf8427e",
    sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    files = files
  ))
}

testthat::test_that("backend_root_dir() is the condathis root for micromamba, a subdirectory for others", {
  root <- get_condathis_path()
  testthat::expect_identical(
    as.character(backend_root_dir("micromamba")),
    as.character(realize_existing_part(root))
  )
  testthat::expect_identical(
    as.character(backend_root_dir("rattler")),
    as.character(fs::path(realize_existing_part(root), "rattler"))
  )
  testthat::expect_true(fs::is_absolute_path(backend_root_dir("x-backend")))
  testthat::expect_s3_class(backend_root_dir("x-backend"), "fs_path")
  # Never created.
  testthat::expect_false(fs::dir_exists(backend_root_dir("x-backend")))
})

testthat::test_that("backend_root_dir() checks the name", {
  for (name in list("", "a b", "1x", NA_character_, 1L, c("a", "b"))) {
    testthat::expect_error(
      backend_root_dir(name),
      class = "condathis_backend_invalid_name"
    )
  }
  for (name in c("auto", "native", "envs", "PKGS", "condabin", "cache")) {
    testthat::expect_error(
      backend_root_dir(name),
      class = "condathis_backend_reserved_name"
    )
  }
  testthat::expect_no_error(backend_root_dir("micromamba"))
})

testthat::test_that("backend_root_dir() follows R_USER_DATA_DIR and realizes the existing part", {
  real_dir <- fs::path_real(withr::local_tempdir())
  data_dir <- fs::path(real_dir, "data")
  fs::dir_create(data_dir)
  link_dir <- fs::path(real_dir, "data-link")
  if (isTRUE(is_windows())) {
    Sys.junction(as.character(data_dir), as.character(link_dir))
  } else {
    fs::link_create(data_dir, link_dir)
  }
  # Deleted before the temporary directory: on Windows, unlink() of the
  # directory leaves the junction, and with it the directory, behind.
  withr::defer(unlink(as.character(link_dir)))
  withr::local_envvar(R_USER_DATA_DIR = as.character(link_dir))
  # Through the link, only the existing part is realized.
  testthat::expect_identical(
    tolower_on_windows(as.character(backend_root_dir("rattler"))),
    tolower_on_windows(as.character(
      fs::path(data_dir, "R", "condathis", "rattler")
    ))
  )
  testthat::expect_false(fs::dir_exists(fs::path(data_dir, "R")))
  # Once the root exists, it is its real path.
  fs::dir_create(fs::path(link_dir, "R", "condathis", "rattler"))
  testthat::expect_identical(
    tolower_on_windows(as.character(backend_root_dir("rattler"))),
    tolower_on_windows(as.character(fs::path_real(
      fs::path(data_dir, "R", "condathis", "rattler")
    )))
  )
  # The sandbox moves it.
  with_sandbox_dir({
    testthat::expect_false(startsWith(
      as.character(backend_root_dir("rattler")),
      as.character(real_dir)
    ))
  })
})

testthat::test_that("the default root is created only by get_install_dir() and changes", {
  stub <- local_stub_backend("stub-default-root", default_root = TRUE)
  m <- stub$name
  root <- backend_root_dir(m)
  testthat::expect_false(fs::dir_exists(root))

  # Queries create nothing.
  testthat::expect_identical(
    list_envs(method = m)$env_name,
    character(0L)
  )
  testthat::expect_false(env_exists("default-root-env", method = m))
  env_dir <- get_env_dir("default-root-env", method = m)
  testthat::expect_identical(
    as.character(env_dir),
    as.character(fs::path(root, "envs", "default-root-env"))
  )
  testthat::expect_false(fs::dir_exists(root))
  testthat::expect_false(backend_has_env_dirs(m))

  # get_install_dir() creates it, in its real form.
  install_dir <- get_install_dir(method = m)
  testthat::expect_identical(install_dir$backend, m)
  testthat::expect_true(fs::dir_exists(root))
  testthat::expect_identical(
    install_dir$path,
    as.character(fs::path_real(root))
  )
  # An empty root has no environment.
  testthat::expect_false(backend_has_env_dirs(m))
  testthat::expect_false(backend_has_cache_entries(m))
  # Empty cache directories, and ones with only a lock file (what a
  # backend's clean can leave), are not caches.
  fs::dir_create(fs::path(root, c("pkgs", "repodata_cache")))
  fs::file_create(fs::path(root, "pkgs", ".cache.lock"))
  testthat::expect_false(backend_has_cache_entries(m))
  fs::file_create(fs::path(root, "repodata_cache", "abc.json"))
  testthat::expect_true(backend_has_cache_entries(m))
  fs::file_delete(fs::path(root, "repodata_cache", "abc.json"))
  fs::dir_create(fs::path(root, "pkgs", "foo-1.0-0"))
  testthat::expect_true(backend_has_cache_entries(m))
  fs::dir_delete(fs::path(root, c("pkgs", "repodata_cache")))
  fs::file_create(fs::path(root, "cache.lock"))
  testthat::expect_false(backend_has_cache_entries(m))
  fs::file_create(fs::path(root, "cache.json"))
  testthat::expect_true(backend_has_cache_entries(m))
  fs::file_delete(fs::path(root, c("cache.lock", "cache.json")))
  fs::dir_create(fs::path(root, "pkgs"))
  fs::file_create(fs::path(root, "pkgs", "urls.txt"))
  testthat::expect_true(backend_has_cache_entries(m))

  # A create (of the stub) makes an environment the defaults find.
  suppressMessages(create_env(env_name = "default-root-env", method = m))
  testthat::expect_true(backend_has_env_dirs(m))
  testthat::expect_true(env_exists("default-root-env", method = m))
  testthat::expect_identical(
    list_envs(method = m)$env_name,
    "default-root-env"
  )
  testthat::expect_identical(
    resolve_backend(env_name = "default-root-env")$name,
    m
  )
  # The marker of condathis is in the environment that the default
  # backend_get_env_dir() names.
  testthat::expect_identical(
    read_backend_marker(env_dir)$backend,
    m
  )
})

testthat::test_that("the default listing reports only conda prefixes in <root>/envs", {
  stub <- local_stub_backend(
    "stub-default-listing",
    default_root = TRUE,
    envs = "real-env"
  )
  backend <- stub$backend
  envs_dir <- fs::path(backend_root_dir(stub$name), "envs")
  # Not environments: a directory without conda-meta/history, the trash
  # (even with a history), a file, and a link to a prefix elsewhere.
  fs::dir_create(fs::path(envs_dir, "no-history-env"))
  write_conda_prefix(fs::path(envs_dir, env_trash_name()))
  fs::file_create(fs::path(envs_dir, "a-file"))
  outside <- write_conda_prefix(fs::path(withr::local_tempdir(), "outside"))
  link <- fs::path(envs_dir, "linked-env")
  if (isTRUE(is_windows())) {
    Sys.junction(as.character(outside), as.character(link))
  } else {
    fs::link_create(outside, link)
  }
  testthat::expect_identical(backend_list_envs(backend), "real-env")
  testthat::expect_identical(
    list_envs(method = stub$name)$env_name,
    "real-env"
  )
  testthat::expect_true(backend_env_exists(backend, "real-env"))
  for (env_name in c(
    "no-history-env",
    "linked-env",
    "a-file",
    "missing-env"
  )) {
    testthat::expect_false(
      backend_env_exists(backend, env_name),
      info = env_name
    )
  }
  # No root at all: no environment, and nothing created.
  other <- local_stub_backend("stub-default-no-root", default_root = TRUE)
  testthat::expect_identical(backend_list_envs(other$backend), character(0L))
  testthat::expect_false(backend_env_exists(other$backend, "real-env"))
  testthat::expect_false(fs::dir_exists(backend_root_dir(other$name)))
})

testthat::test_that("the default backend_list_packages() reads the records with micromamba's columns", {
  stub <- local_stub_backend(
    "stub-default-packages",
    default_root = TRUE,
    envs = "empty-env",
    backend_list_packages = NULL
  )
  backend <- stub$backend
  envs_dir <- fs::path(backend_root_dir(stub$name), "envs")
  write_conda_prefix(
    fs::path(envs_dir, "pkgs-env"),
    records = list(conda_record("zeta"), conda_record("alpha", "2.1"))
  )

  pkgs <- list_packages(env_name = "pkgs-env", method = stub$name)
  testthat::expect_s3_class(pkgs, "tbl_df")
  testthat::expect_named(
    pkgs,
    c(
      "base_url",
      "build_number",
      "build_string",
      "channel",
      "dist_name",
      "md5",
      "name",
      "platform",
      "sha256",
      "url",
      "version"
    )
  )
  testthat::expect_identical(pkgs$name, c("alpha", "zeta"))
  testthat::expect_identical(pkgs$version, c("2.1", "1.0"))
  testthat::expect_identical(pkgs$build_number, c(0L, 0L))
  testthat::expect_identical(pkgs$channel, c("conda-forge", "conda-forge"))
  testthat::expect_identical(
    pkgs$base_url[[1L]],
    "https://conda.anaconda.org/conda-forge"
  )
  testthat::expect_identical(pkgs$platform, c("noarch", "noarch"))
  testthat::expect_identical(pkgs$dist_name[[1L]], "alpha-2.1-h0_0")

  # An empty environment: zero rows, micromamba's eight columns.
  empty <- list_packages(env_name = "empty-env", method = stub$name)
  testthat::expect_s3_class(empty, "tbl_df")
  testthat::expect_identical(nrow(empty), 0L)
  testthat::expect_named(
    empty,
    c(
      "base_url",
      "build_number",
      "build_string",
      "channel",
      "dist_name",
      "name",
      "platform",
      "version"
    )
  )

  # Called for a missing environment, as after a failed probe.
  cnd <- rlang::catch_cnd(
    backend_list_packages(backend, env_name = "missing-env"),
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

testthat::test_that("the default backend_remove_env() deletes the history first, then the directory", {
  stub <- local_stub_backend(
    "stub-default-remove",
    default_root = TRUE,
    backend_remove_env = NULL
  )
  backend <- stub$backend
  envs_dir <- fs::path(backend_root_dir(stub$name), "envs")
  env_dir <- write_conda_prefix(
    fs::path(envs_dir, "remove-env"),
    records = list(conda_record("plain"))
  )
  fs::dir_create(fs::path(env_dir, "lib", "nested"))
  fs::file_create(fs::path(env_dir, "lib", "nested", "file.txt"))

  res <- remove_env(
    env_name = "remove-env",
    method = stub$name,
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_false(fs::dir_exists(env_dir))
  testthat::expect_false(env_exists("remove-env", method = stub$name))
  # The trash holds nothing afterwards.
  testthat::expect_identical(
    length(fs::dir_ls(fs::path(envs_dir, env_trash_name()), all = TRUE)),
    0L
  )

  # When the delete stops half way, the environment is already gone from
  # every listing.
  env_dir <- write_conda_prefix(fs::path(envs_dir, "half-env"))
  testthat::local_mocked_bindings(
    delete_env_dir_via_trash = function(...) stop("interrupted delete")
  )
  testthat::expect_error(
    backend_remove_env(backend, env_name = "half-env", verbose = "silent"),
    "interrupted delete"
  )
  testthat::expect_true(fs::dir_exists(env_dir))
  testthat::expect_false(
    fs::file_exists(fs::path(env_dir, "conda-meta", "history"))
  )
  testthat::expect_false(backend_env_exists(backend, "half-env"))
})

testthat::test_that("the default backend_remove_env() deletes file by file when the move fails", {
  # On NTFS a directory with an open file below it usually cannot be
  # renamed. Then the files are deleted one by one, and a file that cannot
  # be deleted is moved into the trash for a later purge.
  stub <- local_stub_backend(
    "stub-default-remove-busy",
    default_root = TRUE,
    backend_remove_env = NULL
  )
  backend <- stub$backend
  envs_dir <- fs::path(backend_root_dir(stub$name), "envs")
  env_dir <- write_conda_prefix(fs::path(envs_dir, "busy-env"))
  fs::dir_create(fs::path(env_dir, "bin"))
  busy_file <- fs::path(env_dir, "bin", "busy-tool")
  writeLines("in use", busy_file)
  fs::file_create(fs::path(env_dir, "bin", "other-tool"))

  real_rename_path <- rename_path
  testthat::local_mocked_bindings(
    rename_path = function(from, to) {
      if (identical(as.character(from), as.character(env_dir))) {
        return("The process cannot access the file.")
      }
      return(real_rename_path(from, to))
    },
    delete_env_file = function(path) {
      if (identical(as.character(path), as.character(busy_file))) {
        return(FALSE)
      }
      fs::file_delete(path)
      return(TRUE)
    }
  )
  res <- backend_remove_env(backend, env_name = "busy-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_false(fs::dir_exists(env_dir))
  trash_dir <- fs::path(envs_dir, env_trash_name())
  leftovers <- fs::dir_ls(trash_dir, all = TRUE)
  testthat::expect_length(leftovers, 1L)
  testthat::expect_true(endsWith(as.character(leftovers), ".discard"))
  testthat::expect_identical(readLines(leftovers), "in use")
  # A later call deletes it.
  purge_env_trash_dir(trash_dir)
  testthat::expect_length(fs::dir_ls(trash_dir, all = TRUE), 0L)
})

testthat::test_that("the default backend_remove_env() deletes links, never what they point to", {
  # Regression test: on the file-by-file path, `fs::file_delete()` deleted a
  # link to a directory with `fs::dir_delete()`, which deleted every file
  # in the directory outside the environment that it pointed to.
  stub <- local_stub_backend(
    "stub-default-remove-link",
    default_root = TRUE,
    backend_remove_env = NULL
  )
  backend <- stub$backend
  envs_dir <- fs::path(backend_root_dir(stub$name), "envs")
  outside <- withr::local_tempdir()
  fs::dir_create(fs::path(outside, "sub"))
  outside_files <- fs::path(outside, c("keep.txt", "sub/keep.txt"))
  for (path in outside_files) {
    writeLines("precious", path)
  }
  # Symbolic links need extra privileges on Windows: a junction is the
  # link to a directory there, and a hard link the link to a file.
  link_dir <- function(target, link) {
    if (isTRUE(is_windows())) {
      Sys.junction(as.character(target), as.character(link))
    } else {
      fs::link_create(target, link)
    }
  }
  make_env <- function(env_name) {
    env_dir <- write_conda_prefix(fs::path(envs_dir, env_name))
    fs::dir_create(fs::path(env_dir, "share"))
    link_dir(outside, fs::path(env_dir, "data-link"))
    link_dir(outside, fs::path(env_dir, "share", "nested-link"))
    fs::link_create(
      outside_files[[1L]],
      fs::path(env_dir, "file-link"),
      symbolic = isFALSE(is_windows())
    )
    return(env_dir)
  }
  # The move into the trash.
  env_dir <- make_env("link-env")
  res <- backend_remove_env(backend, env_name = "link-env", verbose = "silent")
  testthat::expect_identical(res$status, 0L)
  testthat::expect_false(fs::dir_exists(env_dir))
  testthat::expect_true(all(fs::file_exists(outside_files)))

  # File by file, when the directory cannot be moved.
  env_dir <- make_env("link-busy-env")
  real_rename_path <- rename_path
  testthat::local_mocked_bindings(
    rename_path = function(from, to) {
      if (identical(as.character(from), as.character(env_dir))) {
        return("The process cannot access the file.")
      }
      return(real_rename_path(from, to))
    }
  )
  res <- backend_remove_env(
    backend,
    env_name = "link-busy-env",
    verbose = "silent"
  )
  testthat::expect_identical(res$status, 0L)
  testthat::expect_false(fs::dir_exists(env_dir))
  testthat::expect_true(all(fs::file_exists(outside_files)))
  testthat::expect_true(fs::dir_exists(fs::path(outside, "sub")))
})

testthat::test_that("the default backend_remove_env() reports missing environments and pre-unlink scripts", {
  stub <- local_stub_backend(
    "stub-default-remove-checks",
    default_root = TRUE,
    backend_remove_env = NULL
  )
  backend <- stub$backend
  envs_dir <- fs::path(backend_root_dir(stub$name), "envs")

  # Called for a missing environment, as after a failed probe.
  cnd <- rlang::catch_cnd(
    backend_remove_env(backend, env_name = "missing-env", verbose = "silent"),
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
  # A directory that is not an environment is deleted as stale, and the
  # environment is still reported missing.
  stale_dir <- fs::path(envs_dir, "stale-env")
  fs::dir_create(stale_dir)
  testthat::expect_error(
    backend_remove_env(backend, env_name = "stale-env", verbose = "silent"),
    class = "condathis_remove_env_env_not_found"
  )
  testthat::expect_false(fs::dir_exists(stale_dir))

  # The pre-unlink scripts are not run, and their packages are reported.
  env_dir <- write_conda_prefix(
    fs::path(envs_dir, "scripts-env"),
    records = list(
      conda_record("plink", files = list("bin/.plink-pre-unlink.sh")),
      conda_record("plain", files = list("bin/plain"))
    )
  )
  fs::dir_create(fs::path(env_dir, "bin"))
  marker <- fs::path(withr::local_tempdir(), "ran")
  writeLines(
    paste0("touch '", marker, "'"),
    fs::path(env_dir, "bin", ".plink-pre-unlink.sh")
  )
  fs::file_create(fs::path(env_dir, "bin", "plain"))
  # A script that no record lists is reported under its file name.
  fs::file_create(fs::path(env_dir, "bin", ".orphan-pre-unlink.sh"))
  res <- backend_remove_env(
    backend,
    env_name = "scripts-env",
    verbose = "silent"
  )
  testthat::expect_identical(
    res$link_scripts_skipped,
    data.frame(
      package = c("orphan", "plink"),
      script = c("pre-unlink", "pre-unlink"),
      stringsAsFactors = FALSE
    )
  )
  testthat::expect_false(fs::file_exists(marker))
  testthat::expect_false(fs::dir_exists(env_dir))

  # Without scripts: zero rows.
  env_dir <- write_conda_prefix(fs::path(envs_dir, "no-scripts-env"))
  testthat::expect_identical(
    env_pre_unlink_scripts(env_dir),
    empty_link_scripts()
  )
  res <- backend_remove_env(
    backend,
    env_name = "no-scripts-env",
    verbose = "silent"
  )
  testthat::expect_identical(nrow(res$link_scripts_skipped), 0L)
})

testthat::test_that("the defaults of the new optional functions", {
  stub <- local_stub_backend(
    "stub-default-new-hooks",
    backend_available = NULL,
    backend_clean_cache = NULL,
    backend_quiesce = NULL,
    backend_native_platform = NULL,
    backend_can_solve = NULL
  )
  backend <- stub$backend
  for (generic in c(
    "backend_available",
    "backend_clean_cache",
    "backend_quiesce",
    "backend_native_platform",
    "backend_can_solve"
  )) {
    testthat::expect_null(backend[[generic]], info = generic)
  }
  testthat::expect_true(backend_available(backend))
  testthat::expect_null(backend_clean_cache(backend, verbose = "output"))
  testthat::expect_invisible(backend_quiesce(backend, timeout = 1))
  testthat::expect_true(backend_quiesce(backend))
  testthat::expect_identical(backend_native_platform(backend), NA_character_)
  testthat::expect_identical(
    backend_can_solve(backend, packages = "pkg-a", platform = "osx-64"),
    NA
  )
  # Through the checked wrappers.
  testthat::expect_identical(
    backend_native_platform_checked(backend),
    NA_character_
  )
  testthat::expect_identical(
    backend_can_solve_checked(backend, packages = "pkg-a", platform = "osx-64"),
    NA
  )
  testthat::expect_true(quiesce_registered_backends(timeout = 1))
  # No hook was recorded: the defaults of condathis answered.
  testthat::expect_length(stub_calls(stub), 0L)
})

testthat::test_that("conda_record_channel() names the channels that micromamba names", {
  # Regression test: packages of `defaults` were listed by their URL with
  # the rattler backend; micromamba lists its conda-compatible custom
  # channels by name.
  urls <- paste0(
    "https://repo.anaconda.com/pkgs/",
    c("main", "r", "pro", "msys2", "free")
  )
  shown <- conda_record_channel(
    paste0(urls, "/"),
    platform = rep("linux-64", length(urls)),
    base_url = urls
  )
  msys2 <- if (isTRUE(is_windows())) "pkgs/msys2" else urls[[4L]]
  testthat::expect_identical(
    shown,
    c("pkgs/main", "pkgs/r", "pkgs/pro", msys2, urls[[5L]])
  )
  testthat::expect_identical(
    conda_record_channel(
      "https://conda.anaconda.org/conda-forge/linux-64",
      platform = "linux-64",
      base_url = "https://conda.anaconda.org/conda-forge"
    ),
    "conda-forge"
  )
})

testthat::test_that("an environment directory gets its trash marker only after it was moved", {
  # Regression test: the `.discard` marker was written before the rename, so
  # a purge of the trash in another R session between the two deleted the
  # marker of a copy that was not there yet, and the copy then stayed in
  # the trash for good.
  stub <- local_stub_backend(
    "stub-trash-order",
    default_root = TRUE,
    backend_remove_env = NULL
  )
  backend <- stub$backend
  envs_dir <- fs::path(backend_root_dir(stub$name), "envs")
  env_dir <- write_conda_prefix(fs::path(envs_dir, "trash-order-env"))
  marker_at_rename <- NA
  real_rename_path <- rename_path
  testthat::local_mocked_bindings(
    rename_path = function(from, to) {
      if (identical(as.character(from), as.character(env_dir))) {
        marker_at_rename <<- fs::file_exists(paste0(to, ".discard"))
      }
      return(real_rename_path(from, to))
    }
  )
  res <- backend_remove_env(
    backend,
    env_name = "trash-order-env",
    verbose = "silent"
  )
  testthat::expect_false(isTRUE(marker_at_rename))
  testthat::expect_false(is.na(marker_at_rename))
  testthat::expect_false(fs::dir_exists(env_dir))
  trash_dir <- fs::path(envs_dir, env_trash_name())
  testthat::expect_length(fs::dir_ls(trash_dir, all = TRUE), 0L)
})

testthat::test_that("conda_record_base_url() leaves a login out, as micromamba lists it", {
  # micromamba 2.10.0 writes `http://user:*****@host/ch/noarch/x.conda` as
  # the record's url and lists `http://host/ch` as its base_url; a token
  # stays (`/t/*****/`).
  testthat::expect_identical(
    conda_record_base_url(
      c(
        "http://rt-user:*****@127.0.0.1:1/chA/noarch/foo-1.0-0.tar.bz2",
        "http://127.0.0.1:1/t/*****/chA/noarch/foo-1.0-0.tar.bz2",
        "https://conda.anaconda.org/conda-forge/linux-64/x-1-0.conda",
        NA
      ),
      platform = c("noarch", "noarch", "linux-64", "noarch")
    ),
    c(
      "http://127.0.0.1:1/chA",
      "http://127.0.0.1:1/t/*****/chA",
      "https://conda.anaconda.org/conda-forge",
      NA
    )
  )
})
