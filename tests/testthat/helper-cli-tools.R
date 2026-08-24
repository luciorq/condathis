# Resolves a conda-forge package name for a CLI tool used by tests, so that
# `echo`/`cat`/`sort`/... are always provided by an installed conda package
# instead of relying on whatever happens to already be on the test host's
# `PATH` (which cannot be assumed on Windows).
test_os_pkg <- function(unix_name, windows_name = paste0("m2-", unix_name)) {
  if (isTRUE(stringr::str_detect(get_sys_arch(), "^Windows"))) {
    return(paste0("conda-forge::", windows_name))
  }
  return(paste0("conda-forge::", unix_name))
}

# Package spec for a test environment with a working R, shared by
# test-create_env.R and test-rethrow_error.R.
#
# On Windows this pins the MinGW GCC *runtime* (not r-base itself) to the
# last known-good build batch: conda-forge rebuilt the whole runtime family
# (libgcc/libgfortran5/libgomp, build suffixes `_2`/`_3`, uploaded
# 2026-08-19/21) and every R.exe/Rscript.exe run against it crashes at
# startup with "*** stack smashing detected ***" (exit status
# -1073740791/0xC0000409, raised by libssp inside that same runtime).
# Bisection evidence, gathered via temporary in-CI diagnostics:
# - A direct full-path `run_bin()` invocation crashes identically, and
#   `where R` resolves the env's own R.exe first, exonerating
#   `micromamba run` PATH/DLL handling.
# - Pinning `r-base>=4.4,<4.5` still crashed, and the failing r-base
#   4.6.1 build (h91b09f7_1, uploaded 2026-06-29) passed CI on
#   2026-08-16, exonerating r-base itself.
# - The `_1` runtime batch (uploaded 2026-07-30) is what that last green
#   run resolved, hence the exact build-string pins below.
# Remove the pins once conda-forge ships a fixed runtime batch.
test_r_base_pkgs <- function() {
  if (isTRUE(stringr::str_detect(get_sys_arch(), "^Windows"))) {
    return(c(
      "r-base>=4.1,<5.0",
      "libgcc=16.1.0=h110b43a_1",
      "libgfortran5=16.1.0=h94075d5_1"
    ))
  }
  return("r-base>=4.1,<5.0")
}
