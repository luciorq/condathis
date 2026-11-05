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
