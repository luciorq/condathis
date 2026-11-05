# The native argument probe in fixtures/argv-probe, compiled while the tests
# run and installed from a local conda channel. See
# fixtures/argv-probe/README.md.
#
# Every probe command prints one line per argument: "x" + the hex of its
# UTF-8 bytes, or "-" for an unset environment variable. When no C compiler
# works, Python commands print the same format instead, from a `python`
# environment downloaded from conda-forge.

argv_probe_state <- new.env(parent = emptyenv())

argv_probe_variants <- c(
  `argv-probe` = "",
  `argv-cat` = "-DPROBE_CAT",
  `argv-env` = "-DPROBE_ENV"
)

# The value of each probe line: `NA` for "-", the decoded bytes otherwise.
argv_probe_decode <- function(lines) {
  lines <- sub("\r$", "", lines)
  vapply(
    lines,
    function(line) {
      if (identical(line, "-")) {
        return(NA_character_)
      }
      hex <- substring(line, 2L)
      if (isFALSE(nzchar(hex))) {
        return("")
      }
      starts <- seq(1L, nchar(hex), by = 2L)
      bytes <- as.raw(strtoi(substring(hex, starts, starts + 1L), 16L))
      out <- rawToChar(bytes)
      Encoding(out) <- "UTF-8"
      out
    },
    character(1L),
    USE.NAMES = FALSE
  )
}

# C compilers to try, in order: R's own, then `zig cc`.
argv_probe_compilers <- function() {
  compilers <- list()
  r_cc <- tryCatch(
    system2(
      file.path(R.home("bin"), "R"),
      c("CMD", "config", "CC"),
      stdout = TRUE,
      stderr = FALSE
    ),
    error = function(e) character(),
    warning = function(w) character()
  )
  r_cc <- strsplit(trimws(paste(r_cc, collapse = " ")), "\\s+")[[1L]]
  if (length(r_cc) > 0L && nzchar(Sys.which(r_cc[[1L]]))) {
    compilers[["R"]] <- c(unname(Sys.which(r_cc[[1L]])), r_cc[-1L])
  }
  zig <- Sys.which("zig")
  if (nzchar(zig)) {
    zig_cc <- c(unname(zig), "cc")
    if (isTRUE(is_windows())) {
      arch <- if (grepl("arm|aarch", Sys.info()[["machine"]])) {
        "aarch64"
      } else {
        "x86_64"
      }
      zig_cc <- c(zig_cc, "-target", paste0(arch, "-windows-gnu"))
    }
    compilers[["zig"]] <- zig_cc
  }
  compilers
}

# Flag sets to try with each compiler: without libc first, where the
# platform allows it, then against the C runtime.
argv_probe_flag_sets <- function() {
  if (isTRUE(is_windows())) {
    libs <- c("-lshell32", "-lkernel32")
    return(list(
      freestanding = list(
        flags = c(
          "-O2",
          "-nostdlib",
          "-ffreestanding",
          "-fno-stack-protector",
          "-fno-builtin",
          "-Wl,-e,probe_start"
        ),
        libs = libs
      ),
      hosted = list(flags = c("-O2", "-DPROBE_HOSTED"), libs = libs)
    ))
  }
  hosted <- list(flags = c("-O2", "-DPROBE_HOSTED"), libs = character())
  # macOS supports no programs without libSystem.
  if (isTRUE(is_macos())) {
    return(list(hosted = hosted))
  }
  list(
    freestanding = list(
      flags = c(
        "-O2",
        "-static",
        "-nostdlib",
        "-ffreestanding",
        "-fno-stack-protector",
        "-fno-builtin"
      ),
      libs = character()
    ),
    hosted = hosted
  )
}

# Compiles every variant into `out_dir`, then checks that the probe
# round-trips a few arguments. Returns `TRUE` on success.
argv_probe_try_build <- function(cc, flag_set, out_dir) {
  src <- normalizePath(
    testthat::test_path("fixtures", "argv-probe", "argv-probe.c"),
    mustWork = TRUE
  )
  ext <- if (isTRUE(is_windows())) ".exe" else ""
  fs::dir_create(out_dir)
  for (name in names(argv_probe_variants)) {
    out <- fs::path(out_dir, paste0(name, ext))
    define <- argv_probe_variants[[name]]
    res <- tryCatch(
      processx::run(
        command = cc[[1L]],
        args = c(
          cc[-1L],
          flag_set$flags,
          define[nzchar(define)],
          "-o",
          out,
          src,
          flag_set$libs
        ),
        wd = out_dir,
        error_on_status = FALSE
      ),
      error = function(e) NULL
    )
    if (is.null(res) || res$status != 0L || isFALSE(fs::file_exists(out))) {
      return(FALSE)
    }
  }
  check <- c("a b", "", "\u00fc\n\"")
  res <- tryCatch(
    processx::run(
      command = fs::path(out_dir, paste0("argv-probe", ext)),
      args = check,
      error_on_status = FALSE
    ),
    error = function(e) NULL
  )
  if (is.null(res) || res$status != 0L) {
    return(FALSE)
  }
  identical(argv_probe_decode(strsplit(res$stdout, "\n")[[1L]]), check)
}

# A local conda channel with one package, `argv-probe`, for this platform's
# subdirectory. It installs the three probe binaries into `bin/` (Linux and
# macOS) or `Library/bin/` (Windows).
argv_probe_build_channel <- function(bin_dir, channel_dir) {
  subdir <- is_micromamba_available_for_arch()
  ext <- if (isTRUE(is_windows())) ".exe" else ""
  rel_bin <- if (isTRUE(is_windows())) "Library/bin" else "bin"

  pkg_dir <- fs::path(withr::local_tempdir(), "pkg")
  fs::dir_create(fs::path(pkg_dir, c(rel_bin, "info")))
  rel_paths <- paste0(rel_bin, "/", names(argv_probe_variants), ext)
  for (i in seq_along(rel_paths)) {
    fs::file_copy(
      fs::path(bin_dir, paste0(names(argv_probe_variants)[[i]], ext)),
      fs::path(pkg_dir, rel_paths[[i]])
    )
  }
  # The build string tracks the binaries, so a package cache never serves
  # an older build under the same file name.
  probe_sha <- compute_sha256(fs::path(pkg_dir, rel_paths[[1L]]))
  build <- paste0("h", substr(probe_sha, 1L, 8L), "_0")
  index <- list(
    name = "argv-probe",
    version = "0.1.0",
    build = build,
    build_number = 0L,
    depends = character(),
    license = "MIT",
    subdir = subdir
  )
  jsonlite::write_json(
    index,
    fs::path(pkg_dir, "info", "index.json"),
    auto_unbox = TRUE
  )
  writeLines(rel_paths, fs::path(pkg_dir, "info", "files"))
  paths <- list(
    paths = lapply(rel_paths, function(p) {
      list(
        `_path` = p,
        path_type = "hardlink",
        sha256 = compute_sha256(fs::path(pkg_dir, p)),
        size_in_bytes = as.numeric(fs::file_size(fs::path(pkg_dir, p)))
      )
    }),
    paths_version = 1L
  )
  jsonlite::write_json(
    paths,
    fs::path(pkg_dir, "info", "paths.json"),
    auto_unbox = TRUE
  )

  pkg_file <- paste0("argv-probe-0.1.0-", build, ".tar.bz2")
  fs::dir_create(fs::path(channel_dir, c(subdir, "noarch")))
  tarball <- fs::path(channel_dir, subdir, pkg_file)
  withr::with_dir(pkg_dir, {
    utils::tar(
      tarfile = tarball,
      files = c("info", strsplit(rel_bin, "/", fixed = TRUE)[[1L]][[1L]]),
      compression = "bzip2",
      tar = "internal"
    )
  })

  entry <- c(
    index,
    list(
      md5 = unname(tools::md5sum(tarball)),
      sha256 = compute_sha256(tarball),
      size = as.numeric(fs::file_size(tarball))
    )
  )
  repodata <- function(dir, packages) {
    jsonlite::write_json(
      list(
        info = list(subdir = dir),
        packages = packages,
        `packages.conda` = structure(list(), names = character()),
        repodata_version = 1L
      ),
      fs::path(channel_dir, dir, "repodata.json"),
      auto_unbox = TRUE
    )
  }
  repodata(subdir, stats::setNames(list(entry), pkg_file))
  repodata("noarch", structure(list(), names = character()))

  channel_dir <- normalizePath(channel_dir, winslash = "/", mustWork = TRUE)
  paste0("file://", if (isTRUE(is_windows())) "/", channel_dir)
}

# The compiled probe for this test process, built once: a list with the
# binary directory, the compiler and flag set used, and the channel URL.
# `NULL` when no compiler could build a working probe.
argv_probe_native <- function() {
  if (exists("native", envir = argv_probe_state, inherits = FALSE)) {
    return(argv_probe_state$native)
  }
  native <- NULL
  root <- fs::path(tempdir(), "argv-probe")
  compilers <- argv_probe_compilers()
  flag_sets <- argv_probe_flag_sets()
  for (cc_name in names(compilers)) {
    for (set_name in names(flag_sets)) {
      bin_dir <- fs::path(root, paste0(cc_name, "-", set_name))
      ok <- argv_probe_try_build(
        compilers[[cc_name]],
        flag_sets[[set_name]],
        bin_dir
      )
      if (isTRUE(ok)) {
        native <- list(
          bin_dir = bin_dir,
          compiler = cc_name,
          flags = set_name,
          channel = argv_probe_build_channel(
            bin_dir,
            fs::path(root, "channel")
          )
        )
        break
      }
    }
    if (isFALSE(is.null(native))) {
      break
    }
  }
  assign("native", native, envir = argv_probe_state)
  native
}

# The command (and leading arguments) of each probe: the compiled programs,
# or the Python equivalents when no compiler works.
argv_probe_commands <- function() {
  if (isFALSE(is.null(argv_probe_native()))) {
    return(list(probe = "argv-probe", cat = "argv-cat", env = "argv-env"))
  }
  python <- function(code) c("python", "-c", code)
  list(
    probe = python(paste(
      "import sys",
      paste0(
        "sys.stdout.buffer.write(b''.join(b'x' + ",
        "a.encode('utf-8', 'surrogateescape').hex().encode() + b'\\n' ",
        "for a in sys.argv[1:]))"
      ),
      sep = "; "
    )),
    cat = python(paste(
      "import sys",
      "sys.stdout.buffer.write(sys.stdin.buffer.read())",
      sep = "; "
    )),
    env = python(paste(
      "import os, sys",
      paste0(
        "sys.stdout.buffer.write(b''.join((b'x' + ",
        "os.environ[n].encode('utf-8', 'surrogateescape').hex().encode() ",
        "if n in os.environ else b'-') + b'\\n' for n in sys.argv[1:]))"
      ),
      sep = "; "
    ))
  )
}

# The environment with the probes: built offline from the local channel, or
# a conda-forge `python` environment when no compiler works.
create_argv_probe_env <- function(env_name = "argv-probe-env") {
  native <- argv_probe_native()
  if (is.null(native)) {
    testthat::skip_if_offline()
    return(create_env(
      "conda-forge::python",
      env_name = env_name,
      verbose = "silent"
    ))
  }
  skip_if_no_micromamba_offline()
  create_env(
    "argv-probe",
    env_name = env_name,
    channels = native$channel,
    verbose = "silent"
  )
}
