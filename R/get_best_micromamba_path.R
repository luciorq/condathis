#' Return the Path of the Best Micromamba Installation to Use
#'
#' Searches multiple locations for a working micromamba binary, in priority
#' order. Returns the first path that has a valid micromamba with a version
#' meeting the minimum requirement.
#'
#' Discovery priority:
#' 1. User override via `getOption("condathis.micromamba_path")`
#' 2. User override via `CONDATHIS_MICROMAMBA_PATH` environment variable
#' 3. condathis internal managed path (`micromamba_bin_path()`)
#' 4. R-in-conda: micromamba adjacent to R's own installation prefix
#' 5. Active conda environment (`CONDA_PREFIX`)
#' 6. condathis managed micromamba-env fallback
#' 7. System PATH (`Sys.which("micromamba")`)
#'
#' @keywords internal
#' @noRd
get_best_micromamba_path <- function() {
  paths_to_check <- character(0L)

  # --- Priority 1: User override via R option ---
  user_opt <- getOption("condathis.micromamba_path", default = NULL)
  if (!is.null(user_opt) && nzchar(user_opt)) {
    paths_to_check <- c(paths_to_check, user_opt)
  }

  # --- Priority 2: User override via env var ---
  user_env <- Sys.getenv("CONDATHIS_MICROMAMBA_PATH", unset = "")
  if (nzchar(user_env)) {
    paths_to_check <- c(paths_to_check, user_env)
  }

  # --- Priority 3: condathis internal managed path ---
  paths_to_check <- c(paths_to_check, micromamba_bin_path())

  # --- Priority 4: R-in-conda detection ---
  # If R itself is installed in a conda environment, check for micromamba

  # adjacent to R's prefix (e.g., /path/to/conda-env/lib/R is R.home(),
  # so the conda prefix is two levels up: /path/to/conda-env)
  r_prefix <- tryCatch(
    {
      r_home <- R.home()
      base::normalizePath(
        base::file.path(r_home, "..", ".."),
        mustWork = FALSE
      )
    },
    error = function(e) NULL
  )
  if (!is.null(r_prefix) && nzchar(r_prefix)) {
    paths_to_check <- c(
      paths_to_check,
      fs::path(r_prefix, "bin", "micromamba"),
      fs::path(r_prefix, "Library", "bin", "micromamba.exe")
    )
  }

  # --- Priority 5: Active conda environment (CONDA_PREFIX) ---
  conda_prefix <- Sys.getenv("CONDA_PREFIX", unset = "")
  if (nzchar(conda_prefix)) {
    paths_to_check <- c(
      paths_to_check,
      fs::path(conda_prefix, "bin", "micromamba"),
      fs::path(conda_prefix, "Library", "bin", "micromamba.exe")
    )
  }

  # --- Priority 6: condathis managed micromamba-env ---
  paths_to_check <- c(
    paths_to_check,
    fs::path(get_install_dir(), "envs", "micromamba-env", "bin", "micromamba"),
    fs::path(
      get_install_dir(),
      "envs",
      "micromamba-env",
      "Library",
      "bin",
      "micromamba.exe"
    )
  )

  # --- Priority 7: System PATH ---
  sys_which_path <- Sys.which("micromamba")
  if (nzchar(sys_which_path)) {
    paths_to_check <- c(paths_to_check, sys_which_path)
  }

  # Deduplicate while preserving priority order
  paths_to_check <- unique(paths_to_check)

  # Return the first path with a valid version
  for (path in paths_to_check) {
    if (is_umamba_version_available(path)) {
      return(fs::path(path))
    }
  }
  return(NULL)
}
