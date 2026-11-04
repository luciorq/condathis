#' Get the data directories of the backends
#'
#' Returns the data directory of each registered backend. The
#' `"micromamba"` backend uses the condathis data directory,
#' `tools::R_user_dir("condathis", "data")` (see [condathis-options] for
#' the variables that move it). Every other backend uses the directory of
#' its name inside it, [backend_root_dir()], unless it chooses its own. An
#' example is `<condathis data directory>/rattler` for the `"rattler"`
#' backend.
#'
#' @param method Character string naming the backend to report. `"auto"`
#'   (the default) covers every registered backend, in
#'   `getOption("condathis.backend_priority")` order, also a backend that
#'   reports itself unavailable. Any name from
#'   [list_registered_backend_names()] reports only that backend, and
#'   `"micromamba"` is built in. The name of a backend whose package
#'   `condathis` knows, such as `"rattler"` of the `rattlerthis` package,
#'   also reports only that backend. `condathis` loads the package. It
#'   aborts with class `condathis_backend_not_installed` when the package
#'   is not installed. `"native"` is a deprecated alias for `"micromamba"`
#'   (warns once per session). Invalid values abort with class
#'   `condathis_invalid_method`.
#'
#' @details
#' On macOS, when neither `R_USER_DATA_DIR` nor `XDG_DATA_HOME` is set, the
#' condathis data directory is `~/.local/share/R/condathis`, a path without
#' spaces. `micromamba run` can fail on paths that contain spaces.
#'
#' The data directories of the other backends that use [backend_root_dir()]
#' are inside the condathis data directory. So deleting it deletes their
#' environments and caches too. Each backend keeps its environments in the
#' `envs` directory of its own data directory.
#'
#' `micromamba` adds each environment that it creates to
#' `~/.conda/environments.txt` (in `%USERPROFILE%` on Windows), the list of
#' environments that conda and mamba share. It creates that file when it
#' is missing. To leave the file alone, `condathis` runs
#' `micromamba create`, `micromamba env list` and `micromamba env remove`
#' with the `home/` directory of the data directory as their home.
#' [create_env()] still runs micromamba with your home directory when
#' micromamba needs something from there. It then adds the environment to
#' your list. This happens for channel credentials that you saved (with
#' `micromamba auth login`, an `anaconda-client` token, or a `.netrc`
#' file), and for an `env_file` that names your home directory (`~/`,
#' `$HOME`) or installs pip packages. Listing and removing environments
#' never change the file, so the line of an environment that
#' [remove_env()] deleted stays. Both conda and mamba drop such lines the
#' next time they list environments. A `~` at the start of a channel, of a
#' package path and of the path of `env_file` always means your own home
#' directory.
#'
#' The pip that installs the pip packages of an `env_file` keeps its cache
#' in the `cache/` directory of the data directory on Linux, which
#' [clean_cache()] deletes. On macOS and Windows, it keeps its cache in
#' your own user cache (`~/Library/Caches/pip`,
#' `%LOCALAPPDATA%\pip\Cache`).
#'
#' @returns A data frame (a tibble) with one row per backend covered by
#'   `method`, and the character columns `backend` and `path`. `path` is
#'   the real, absolute path of the data directory of the backend, which is
#'   created when it does not exist yet. `get_install_dir()` creates no
#'   environment and does not install micromamba. When the backend that
#'   `method` names fails, `get_install_dir()` aborts with class
#'   `condathis_get_install_dir_failed` (also `condathis_backend_error`).
#'   With `method = "auto"`, `get_install_dir()` skips a backend that
#'   fails, with a warning of class `condathis_backend_query_failed`.
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   # One row per backend: its name and its data directory,
#'   # <data dir>/R/condathis for micromamba
#'   print(condathis::get_install_dir())
#' })
#'
#' @seealso [backend_root_dir()], [condathis-options]
#' @family setup
#'
#' @export
get_install_dir <- function(method = "auto") {
  method <- resolve_method_alias(validate_method_arg(method))

  # "auto" reports every registered backend, available or not (rule R6),
  # in the order that backend resolution uses.
  auto <- identical(method, "auto")
  backend_names <- if (isTRUE(auto)) backend_names_by_priority() else method

  results <- query_registered_backends(
    backend_names = backend_names,
    query = function(backend) {
      return(as.character(install_dir_for_backend(backend)))
    },
    auto = auto,
    fn = "get_install_dir",
    action = "find its data directory"
  )

  dir_df <- base::data.frame(
    backend = as.character(names(results)),
    path = as.character(unlist(results, use.names = FALSE)),
    stringsAsFactors = FALSE
  )
  return(new_tbl(dir_df))
}
