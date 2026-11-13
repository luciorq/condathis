# Every file that micromamba writes for condathis stays in the condathis
# root, the data directory of the micromamba backend. Inside
# `with_sandbox_dir()`, every per-user directory micromamba uses (home,
# caches, configuration) is in the sandbox, so a snapshot of the sandbox
# without the root shows every write outside the root.
#
# One write is known and allowed, because micromamba has no setting to
# move it (see the Details of ?get_install_dir): when micromamba needs the
# user's home (saved credentials), create_env() adds its environment to
# `~/.conda/environments.txt`, the registry of conda and mamba.

# Every file and directory under `dir`, except `root` and what is in it:
# a data frame with `path`, `dir` (logical), and `size` and `md5` for files.
footprint_snapshot <- function(dir, root) {
  paths <- as.character(fs::dir_ls(dir, recurse = TRUE, all = TRUE))
  key <- function(x) tolower_on_windows(to_slash_path(x))
  in_root <- key(paths) == key(root) |
    startsWith(key(paths), paste0(key(root), "/"))
  paths <- sort(paths[!in_root])
  is_dir <- fs::dir_exists(paths)
  files <- paths[!is_dir]
  size <- rep(NA_real_, length(paths))
  md5 <- rep(NA_character_, length(paths))
  size[!is_dir] <- as.numeric(fs::file_size(files))
  md5[!is_dir] <- unname(tools::md5sum(files))
  return(data.frame(
    path = paths,
    dir = unname(is_dir),
    size = size,
    md5 = md5,
    stringsAsFactors = FALSE
  ))
}

# What changed between two snapshots: `created`, `deleted` and, for files,
# `changed` paths.
footprint_diff <- function(before, after) {
  common <- intersect(before$path, after$path)
  b <- before[match(common, before$path), ]
  a <- after[match(common, after$path), ]
  changed <- common[
    !a$dir & (a$dir != b$dir | a$size != b$size | a$md5 != b$md5)
  ]
  return(list(
    created = setdiff(after$path, before$path),
    deleted = setdiff(before$path, after$path),
    changed = changed
  ))
}

# Checks that a step changed nothing outside the root, except the paths
# for which `allowed(path)` is `TRUE`.
expect_footprint <- function(
  before,
  after,
  step,
  allowed = function(p) {
    rep(FALSE, length(p))
  }
) {
  diff <- footprint_diff(before, after)
  for (kind in names(diff)) {
    unexpected <- diff[[kind]][!allowed(diff[[kind]])]
    testthat::expect_identical(
      unexpected,
      character(0L),
      info = paste(step, kind)
    )
  }
  return(invisible(diff))
}

# Writes the sentinel files: one in each per-user directory that conda,
# mamba or micromamba use. Returns the paths of the files. The default root
# prefixes of micromamba, `~/micromamba` and `<data>/mamba`, are no Conda
# prefix: micromamba refused to start, even for `--version`, when the one
# it falls back to exists but has no `pkgs`, `envs` or `conda-meta`, until
# condathis gave it `MAMBA_ROOT_PREFIX`.
seed_footprint_sentinels <- function(home, user_cache, data, config, state) {
  sentinel_files <- c(
    fs::path(user_cache, "conda", "keepme", "f"),
    fs::path(
      user_cache,
      "conda",
      "pkgs",
      "cache",
      "shards",
      "user.msgpack.zst"
    ),
    fs::path(user_cache, "mamba", "keepme", "f"),
    fs::path(home, ".cache", "conda", "keepme", "f"),
    fs::path(home, ".conda", "keepme", "f"),
    fs::path(home, ".mamba", "keepme", "f"),
    fs::path(home, ".mamba", "pkgs", "keepme", "f"),
    fs::path(home, "micromamba", "keepme", "f"),
    fs::path(home, "Library", "Caches", "conda", "keepme", "f"),
    fs::path(home, "Library", "Caches", "mamba", "keepme", "f"),
    fs::path(data, c("conda", ".mamba"), "keepme", "f"),
    fs::path(data, "mamba", "keepme", "f"),
    fs::path(config, c("conda", "mamba"), "keepme", "f"),
    fs::path(state, c("conda", "mamba"), "keepme", "f")
  )
  fs::dir_create(fs::path_dir(sentinel_files))
  for (sentinel in sentinel_files) {
    writeLines("user file", sentinel)
  }
  # Comments only: micromamba's package extraction reads these files.
  for (rc_file in fs::path(home, c(".condarc", ".mambarc"))) {
    writeLines("# user file", rc_file)
  }
  return(invisible(sentinel_files))
}

# The registry, seeded with two environments of another tool and the line
# of an environment that no longer exists, in an order micromamba does not
# write. Listing or removing environments with micromamba dropped that line
# and sorted the file.
seed_footprint_registry <- function(home) {
  other_envs <- fs::path(home, "other-tool", "envs", c("env-b", "env-a"))
  fs::dir_create(fs::path(other_envs, "conda-meta"))
  fs::file_create(fs::path(other_envs, "conda-meta", "history"))
  lines <- as.character(c(
    other_envs[[1L]],
    fs::path(home, "other-tool", "envs", "gone"),
    other_envs[[2L]]
  ))
  writeLines(lines, fs::path(home, ".conda", "environments.txt"))
  return(lines)
}

# The environment variables that a child of run(), run_bin() and
# run_pipeline() gets, by entry point: each runs an `Rscript` that saves
# its environment.
footprint_child_vars <- function(env_name, var_names) {
  rscript <- get_condathis_rscript_path()
  dump_dir <- withr::local_tempdir()
  script <- function(name) {
    dump_path <- fs::path(dump_dir, paste0(name, ".rds"))
    script_path <- fs::path(dump_dir, paste0(name, ".R"))
    writeLines(
      paste0(
        "saveRDS(as.list(Sys.getenv()), file = ",
        deparse(as.character(dump_path)),
        ")"
      ),
      script_path
    )
    return(list(script = as.character(script_path), dump = dump_path))
  }
  entry_points <- list(
    run = function(path) {
      run(rscript, "--vanilla", path, env_name = env_name, verbose = "silent")
    },
    run_bin = function(path) {
      run_bin(
        rscript,
        "--vanilla",
        path,
        env_name = env_name,
        verbose = "silent"
      )
    },
    run_pipeline = function(path) {
      run_pipeline(
        run_step(rscript, "--vanilla", path),
        run_step(
          rscript,
          "--vanilla",
          "-e",
          "invisible(readLines(file('stdin')))"
        ),
        env_name = env_name,
        verbose = "silent"
      )
    }
  )
  result <- list()
  for (entry_point in names(entry_points)) {
    files <- script(entry_point)
    entry_points[[entry_point]](files$script)
    child_env <- readRDS(files$dump)
    result[[entry_point]] <- vapply(
      var_names,
      function(nm) {
        found <- match_env_name(names(child_env), nm)
        if (is.na(found)) NA_character_ else as.character(child_env[[found]])
      },
      character(1L)
    )
  }
  return(result)
}

# A local channel with one `noarch` package, `menucheck`, that has a Start
# Menu shortcut (`Menu/condathis-footprint-check.json`, menuinst v1). On
# Windows, micromamba adds the shortcut to the Programs folder of the
# Start Menu, under `USERPROFILE`, unless `shortcuts` is `false`. The
# package has no `info/paths.json`, so micromamba uses `info/files`, and
# its record has `md5` and `size` only. Returns the `file://` URL.
local_menu_channel <- function(envir = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = envir)
  pkg_dir <- fs::path(dir, "src")
  fs::dir_create(fs::path(pkg_dir, c("info", "Menu")))
  menu_path <- "Menu/condathis-footprint-check.json"
  writeLines(
    c(
      "{",
      "  \"menu_name\": \"condathis-footprint-check\",",
      "  \"menu_items\": [{\"name\": \"fpcheck\",",
      "    \"system\": \"%windir%\\\\system32\\\\cmd.exe\",",
      "    \"scriptarguments\": [\"/K\", \"echo\"]}]",
      "}"
    ),
    fs::path(pkg_dir, menu_path)
  )
  record <- c(
    "\"name\": \"menucheck\", \"version\": \"0.1.0\", \"build\": \"0\",",
    "\"build_number\": 0, \"depends\": [], \"noarch\": \"generic\",",
    "\"subdir\": \"noarch\", \"license\": \"MIT\""
  )
  writeLines(c("{", record, "}"), fs::path(pkg_dir, "info", "index.json"))
  writeLines(menu_path, fs::path(pkg_dir, "info", "files"))
  noarch <- fs::path(dir, "channel", "noarch")
  fs::dir_create(noarch)
  pkg <- fs::path(noarch, "menucheck-0.1.0-0.tar.bz2")
  withr::with_dir(
    pkg_dir,
    utils::tar(
      pkg,
      files = c("info", "Menu"),
      compression = "bzip2",
      tar = "internal"
    )
  )
  writeLines(
    c(
      "{\"info\": {\"subdir\": \"noarch\"}, \"packages.conda\": {},",
      "\"packages\": {\"menucheck-0.1.0-0.tar.bz2\": {",
      record,
      paste0(
        ", \"md5\": \"",
        unname(tools::md5sum(as.character(pkg))),
        "\", \"size\": ",
        fs::file_size(pkg),
        "}}}"
      )
    ),
    fs::path(noarch, "repodata.json")
  )
  channel_dir <- normalizePath(
    fs::path(dir, "channel"),
    winslash = "/",
    mustWork = TRUE
  )
  return(paste0("file://", if (isTRUE(is_windows())) "/", channel_dir))
}

# Runs create_env(), install_packages(), the queries, run(), run_bin(),
# run_pipeline(), remove_env() and clean_cache() inside a sandbox, and
# checks the footprint of each step. `xdg_cache = FALSE` unsets
# `XDG_CACHE_HOME`, so micromamba's user cache is `~/.cache`. With
# `menu_channel`, the install step also installs `menucheck` from it. With
# `credentials`, the home has a saved login of `micromamba auth login`,
# and create_env() registers its environment.
check_micromamba_footprint <- function(
  packages,
  channels,
  xdg_cache = TRUE,
  expect_shards = FALSE,
  menu_channel = NULL,
  credentials = FALSE
) {
  condathis::with_sandbox_dir({
    home <- fs::path_home()
    sandbox <- as.character(fs::path_real(fs::path_dir(Sys.getenv("HOME"))))
    config <- Sys.getenv("XDG_CONFIG_HOME")
    state <- Sys.getenv("XDG_STATE_HOME")
    if (isTRUE(xdg_cache)) {
      user_cache <- Sys.getenv("XDG_CACHE_HOME")
    } else {
      Sys.unsetenv("XDG_CACHE_HOME")
      user_cache <- fs::path(home, ".cache")
    }
    sentinels <- seed_footprint_sentinels(
      home = home,
      user_cache = user_cache,
      data = Sys.getenv("R_USER_DATA_DIR"),
      config = config,
      state = state
    )
    if (isTRUE(credentials)) {
      auth_file <- fs::path(home, ".mamba", "auth", "authentication.json")
      fs::dir_create(fs::path_dir(auth_file))
      writeLines("{}", auth_file)
      sentinels <- c(sentinels, auth_file)
    }
    registry <- fs::path(home, ".conda", "environments.txt")
    registry_seed <- seed_footprint_registry(home)
    # The root, and its parent directories, exist before the first snapshot.
    root <- as.character(get_install_dir(method = "micromamba")$path)
    env_name <- "footprint-env"
    env_line <- as.character(fs::path(root, "envs", env_name))
    key <- function(x) tolower_on_windows(to_slash_path(x))
    is_registry <- function(p) key(p) == key(fs::path_real(registry))
    snapshot <- function() footprint_snapshot(sandbox, root)
    session_vars <- c(
      "HOME",
      "USERPROFILE",
      "XDG_CACHE_HOME",
      "XDG_CONFIG_HOME"
    )
    session_values <- vapply(
      session_vars,
      function(nm) {
        value <- Sys.getenv(nm, unset = NA_character_)
        if (is.na(value)) NA_character_ else as.character(value)
      },
      character(1L)
    )

    s0 <- snapshot()
    create_env(
      packages,
      env_name = env_name,
      channels = channels,
      verbose = "silent"
    )
    s1 <- snapshot()
    # With the user's home, micromamba appends the new environment to the
    # registry, with backslashes on Windows. Otherwise its registry is in
    # `<root>/home`.
    registry_lines <- registry_seed
    if (isTRUE(credentials)) {
      registry_lines <- c(registry_seed, env_line)
      expect_footprint(s0, s1, "create_env", allowed = is_registry)
    } else {
      expect_footprint(s0, s1, "create_env")
    }
    testthat::expect_identical(key(readLines(registry)), key(registry_lines))
    if (isTRUE(expect_shards)) {
      shards <- fs::dir_ls(
        fs::path(root, "cache", "conda", "pkgs", "cache", "shards"),
        type = "file"
      )
      testthat::expect_true(length(shards) > 0L)
    }

    install_packages(
      packages,
      env_name = env_name,
      channels = channels,
      verbose = "silent"
    )
    if (isFALSE(is.null(menu_channel))) {
      # No Start Menu shortcut, which on Windows would be in the sandbox's
      # `USERPROFILE`.
      install_packages(
        "menucheck",
        env_name = env_name,
        channels = c(menu_channel, channels),
        verbose = "silent"
      )
      testthat::expect_true(fs::file_exists(fs::path(
        get_env_dir(env_name),
        "Menu",
        "condathis-footprint-check.json"
      )))
    }
    testthat::expect_true(env_exists(env_name))
    testthat::expect_true(env_name %in% list_envs()$env_name)
    list_packages(env_name)
    s2 <- snapshot()
    # The listings no longer rewrite the registry.
    expect_footprint(s1, s2, "install_packages and queries")
    testthat::expect_identical(key(readLines(registry)), key(registry_lines))

    child_vars <- footprint_child_vars(
      env_name,
      c(session_vars, "MAMBA_ROOT_PREFIX")
    )
    for (entry_point in names(child_vars)) {
      testthat::expect_identical(
        child_vars[[entry_point]],
        c(session_values, MAMBA_ROOT_PREFIX = ""),
        info = entry_point
      )
    }
    s3 <- snapshot()
    # `micromamba run`, which records the activation, keeps its `mamba/proc`
    # directory in the root too.
    expect_footprint(s2, s3, "run family")
    testthat::expect_false(fs::dir_exists(fs::path(
      user_cache,
      "mamba",
      "proc"
    )))

    remove_env(env_name, verbose = "silent")
    testthat::expect_false(env_exists(env_name))
    s4 <- snapshot()
    # The removal no longer rewrites the registry either. The line of the
    # removed environment stays, as conda and mamba ignore missing ones.
    expect_footprint(s3, s4, "remove_env")
    testthat::expect_identical(key(readLines(registry)), key(registry_lines))

    testthat::expect_true(fs::dir_exists(fs::path(root, "pkgs")))
    res <- clean_cache(verbose = "silent")
    testthat::expect_true(rlang::is_string(res$cmd))
    s5 <- snapshot()
    expect_footprint(s4, s5, "clean_cache")
    testthat::expect_false(fs::dir_exists(fs::path(root, "pkgs")))
    testthat::expect_false(fs::dir_exists(fs::path(root, "cache")))

    expect_footprint(
      s0,
      s5,
      "all steps",
      allowed = function(p) isTRUE(credentials) & is_registry(p)
    )
    testthat::expect_true(all(fs::file_exists(sentinels)))
  })
}

testthat::test_that("micromamba writes nothing outside the condathis root", {
  # Regression test (footprint): micromamba wrote its repodata cache to
  # `<user cache>/conda`, every listing and remove_env() rewrote
  # `~/.conda/environments.txt`, clean_cache() deleted the whole
  # `<user cache>/conda`, and on Windows packages with a `Menu/*.json`
  # added Start Menu shortcuts. The local channels need no network once the
  # test process has a micromamba binary. Without `XDG_CACHE_HOME`,
  # micromamba on Windows uses the local application data folder, which
  # ignores the environment variables of the sandbox, so that case runs on
  # Linux and macOS only.
  testthat::skip_on_cran()
  local_sandbox_micromamba()
  check_micromamba_footprint(
    "polyglot",
    polyglot_channel(),
    menu_channel = local_menu_channel()
  )
  if (isFALSE(is_windows())) {
    check_micromamba_footprint(
      "polyglot",
      polyglot_channel(),
      xdg_cache = FALSE
    )
  }
})

testthat::test_that("create_env() registers its environment only when micromamba needs the user's home", {
  testthat::skip_on_cran()
  # Regression test (footprint, R-12): `micromamba create` appended every
  # environment to `~/.conda/environments.txt`, and no setting stops it.
  # condathis now gives it another home, except when micromamba needs the
  # user's: here a saved login, which it reads from
  # `~/.mamba/auth/authentication.json`.
  local_sandbox_micromamba()
  check_micromamba_footprint("polyglot", polyglot_channel(), credentials = TRUE)
})

testthat::test_that("the sharded repodata cache of conda-forge stays in the root", {
  # Regression test (footprint): micromamba writes the shards of a channel
  # that has them, such as conda-forge, to
  # `<user cache>/conda/pkgs/cache/shards`, whatever `pkgs_dirs` says. A
  # local `file://` channel never uses shards, so this needs the network.
  testthat::skip_on_cran()
  testthat::skip_if_offline()
  local_sandbox_micromamba()
  check_micromamba_footprint("zlib", "conda-forge", expect_shards = TRUE)
})
