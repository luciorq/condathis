#' Condition classes of condathis
#'
#' @description
#' Every error that `condathis` raises has the class `condathis_error`, and
#' every warning has the class `condathis_warning`. Each condition also has
#' more specific classes. Use them to handle one kind of problem with
#' [base::tryCatch()], [base::withCallingHandlers()] or
#' [rlang::try_fetch()], and to test for it with
#' `testthat::expect_error(class = )`. Do not match the text of a message:
#' it can change in any release.
#'
#' @section The class scheme:
#' The classes of a condition go from the most specific to the most general:
#'
#' 1. The class of the function and the problem,
#'    `condathis_<function>_<problem>`, with the full name of the exported
#'    function. For example, `condathis_create_env_exists` or
#'    `condathis_run_bin_env_not_found`.
#' 2. Older names of that class, kept so that existing handlers still work
#'    (see *Renamed classes*). Some classes carry further names that this
#'    page does not list: do not rely on them.
#' 3. Shared classes for the kind of problem, for example
#'    `condathis_invalid_overwrite` and `condathis_invalid_arg`, or
#'    `condathis_env_not_found`.
#' 4. The root class, `condathis_error` or `condathis_warning`.
#'
#' The rlang package adds its own classes after these, such as
#' `rlang_error`, `error` and `condition`.
#'
#' For example, `create_env(overwrite = "yes")` aborts with the classes
#' `c("condathis_create_env_invalid_overwrite",
#' "condathis_create_invalid_overwrite_arg", "condathis_invalid_overwrite",
#' "condathis_invalid_arg", "condathis_error")`.
#'
#' The checks of `verbose`, `method` and `error` are the same in every
#' function, so their errors have only shared classes, for example
#' `c("condathis_invalid_verbose", "condathis_invalid_arg",
#' "condathis_error")`.
#'
#' Handle the most general class that fits. A handler for
#' `condathis_env_not_found` catches a missing environment in every
#' function, and a handler for `condathis_error` catches every error of
#' `condathis`.
#'
#' @section Shared classes:
#' * `condathis_invalid_arg`: an argument has an invalid value. `condathis`
#'   checks the arguments before it changes anything, so such an error has
#'   no side effects.
#' * `condathis_invalid_<argument>`: an invalid value of one argument, with
#'   its exact name. For example, `condathis_invalid_env_name`,
#'   `condathis_invalid_packages`, `condathis_invalid_channels`,
#'   `condathis_invalid_method`, `condathis_invalid_verbose`,
#'   `condathis_invalid_error` or `condathis_invalid_timeout`. It always
#'   comes with `condathis_invalid_arg`.
#' * `condathis_parse_match_spec_invalid_name` and
#'   `condathis_parse_match_spec_invalid_url`: a package spec that condathis
#'   cannot read, such as `"::"`, or the URL of a package file whose name is
#'   not `<name>-<version>-<build>`. `condathis` reads the specs when it
#'   compares them with an existing environment, in [create_env()],
#'   [install_packages()] and [validate_env()]. Also
#'   `condathis_invalid_arg`.
#' * `condathis_env_not_found`: the environment does not exist. Only
#'   [run()], [run_bin()], [run_pipeline()] and [install_packages()] create
#'   a missing environment, and only the default `"condathis-env"`. With
#'   `error = "continue"`, the run family returns status 127 instead. When
#'   the environment is in the data directory of a backend whose package
#'   cannot be used (see `condathis_backend_not_installed`), the message
#'   names that backend.
#' * `condathis_backend_error`: a backend failed. The function classes are
#'   `condathis_<function>_failed`, `condathis_<function>_resolve_failed` (a
#'   command or its activation could not be resolved) and
#'   `condathis_backend_probe_failed`. The backend's error is the parent, so
#'   [rlang::cnd_inherits()] finds its classes. The `condathis_*` classes of
#'   the backend's error are also copied, for example
#'   `condathis_micromamba_status_error`.
#' * `condathis_backend_probe_failed`: a backend could not tell whether the
#'   environment exists. [create_env()], [install_packages()] and
#'   [remove_env()] then stop before they change anything. Also
#'   `condathis_backend_error`.
#' * `condathis_backend_query_failed` (a warning): with `method = "auto"`, a
#'   query of one backend failed, and the function skipped that backend.
#' * `condathis_backend_invalid_return`: a backend returned a value that
#'   breaks the contract of [register_backend()]. The message names the
#'   backend. Also `condathis_backend_contract_violation`. For the value of
#'   `backend_resolve_run()`, the first class is
#'   `condathis_backend_resolve_run_invalid`.
#' * `condathis_backend_contract_violation`: a backend breaks the contract,
#'   when it is registered or in a return value.
#' * `condathis_backend_not_installed`: the package of a backend that
#'   condathis knows, such as `"rattler"` of the `rattlerthis` package, is
#'   not installed. An error when `method` names that backend (with the
#'   classes of an invalid `method`). Also an error when a call would
#'   change an environment in the data directory of that backend (with
#'   `condathis_backend_mismatch`). A warning when a query skips the
#'   environments of that backend (once per session). Also a warning when
#'   [clean_cache()] cannot clean its caches.
#' * `condathis_backend_load_failed`: the same, when the package is
#'   installed but failed to load, did not register its backend, or its
#'   backend was unregistered in this session. The error of the load is the
#'   parent. Also a warning, once per session, when `condathis` tried to
#'   load the package. It tries this when its backend has environments or
#'   caches, or when the option `condathis.backend_priority` names it.
#' * `condathis_link_scripts_skipped` (a warning): the backend did not run
#'   the pre-link, post-link or pre-unlink scripts of some packages, which
#'   micromamba runs, so these packages may not work. The call itself
#'   succeeded. The warning has the fields `backend`, `env_name`, `packages`
#'   (the package names, sorted) and `scripts` (a data frame with the
#'   columns `package` and `script`).
#' * `condathis_backend_quiesce_failed` (a warning): [with_sandbox_dir()]
#'   or [clean_cache()] could not tell whether a backend still works in the
#'   R process, and went on.
#' * `condathis_env_lock_waiting` (a message, neither an error nor a
#'   warning): [create_env()], [install_packages()] or [remove_env()] waits
#'   for another R session that changes the same environment (see *Other R
#'   sessions* in [create_env()]).
#' * `condathis_cache_lock_waiting` (a message): [clean_cache()] waits for
#'   other R sessions that create environments or install packages, or
#'   these wait for a [clean_cache()] of another session.
#' * `condathis_env_lock_unavailable` (a warning, once per session): the
#'   lock of the environment or of the package caches could not be taken,
#'   for example on a file system that cannot lock files. The call went on
#'   without it.
#' * `condathis_status_error`: a command of [run()], [run_bin()] or
#'   [run_pipeline()] exited with a status other than 0.
#' * `condathis_timeout_error`: a command of [run()], [run_bin()] or
#'   [run_pipeline()] ran longer than `timeout` and was killed.
#' * `condathis_micromamba_status_error`: a `micromamba` command that
#'   condathis started for the micromamba backend failed. It carries the
#'   fields `status` and `stderr`, also when it is the class of a backend
#'   failure that condathis re-raised.
#' * Deprecated arguments and values, which still work but will be
#'   removed (warnings). `condathis_deprecated_packages_arg` is for
#'   `packages =` in [create_env()], [install_packages()] and
#'   [validate_env()] (once per session and function).
#'   `condathis_deprecated_method_native` is for `method = "native"` (once
#'   per session). `condathis_deprecated_arg` is for `timeout_limit` in
#'   [install_micromamba()].
#'
#' @section Error fields:
#' The status and timeout errors of [run()], [run_bin()] and
#' [run_pipeline()] carry these fields, so a handler does not need to read
#' the message:
#'
#' * `status`: the exit status, an integer. It is `-9` for a timeout, and
#'   `127` for a command that could not start. A command killed by signal
#'   `n` has the status `128 + n` in [run()] on Linux and macOS, as in a
#'   shell. In [run_bin()] and [run_pipeline()], the status is `-n`.
#' * `stdout`, `stderr`: the captured output, or `NA` when that stream was
#'   not captured.
#' * `timeout`: `TRUE` for a timeout, `FALSE` otherwise.
#'
#' The errors of [run_pipeline()] also carry `result`, the
#' `condathis_pipeline` result, and `statuses`, the status of each command.
#'
#' @section Classes of each function:
#' Each function also raises the shared classes above. The checks of
#' `verbose`, `method` and `error` raise only shared classes.
#'
#' \describe{
#'   \item{[create_env()]}{
#'     Arguments: `condathis_create_env_invalid_packages`,
#'     `condathis_create_env_positional_env_name`,
#'     `condathis_create_env_invalid_env_name`,
#'     `condathis_create_env_invalid_channels`,
#'     `condathis_create_env_invalid_channel_priority`,
#'     `condathis_create_env_invalid_platform`,
#'     `condathis_create_env_invalid_env_file`,
#'     `condathis_create_env_missing_env_file`,
#'     `condathis_create_env_invalid_overwrite` and
#'     `condathis_create_env_conflicting_args` (package specs and
#'     `env_file`). The environment: `condathis_create_env_exists` (it
#'     exists, and `overwrite = FALSE` cannot keep it) and
#'     `condathis_create_env_platform_mismatch`. The backend:
#'     `condathis_create_env_failed`, and the warning
#'     `condathis_create_env_link_scripts_skipped`.
#'   }
#'   \item{[install_packages()]}{
#'     Arguments: `condathis_install_packages_missing_packages`,
#'     `condathis_install_packages_invalid_packages`,
#'     `condathis_install_packages_positional_env_name`,
#'     `condathis_install_packages_invalid_env_name`,
#'     `condathis_install_packages_invalid_channels` and
#'     `condathis_install_packages_invalid_channel_priority`. The
#'     environment: `condathis_install_packages_env_not_found`. The backend:
#'     `condathis_install_packages_failed`, and the warning
#'     `condathis_install_packages_link_scripts_skipped`. The warning
#'     `condathis_install_packages_missing_previous_channels` says that a
#'     channel the environment was built from is not in the call. This holds
#'     on every backend that records the channels in `conda-meta/history`.
#'   }
#'   \item{[remove_env()]}{
#'     `condathis_remove_env_invalid_env_name`,
#'     `condathis_remove_env_env_not_found`,
#'     `condathis_remove_env_failed`, and the warning
#'     `condathis_remove_env_link_scripts_skipped` (pre-unlink scripts).
#'   }
#'   \item{[clean_cache()]}{
#'     `condathis_clean_cache_failed`: a backend failed to clean its caches,
#'     or `condathis` could not empty one of its own cache directories. A
#'     backend failure also has `condathis_backend_error`, with the error of
#'     the backend as the parent. For a non-zero `status` that the backend
#'     returned without an error, it has the fields `status`, `stdout` and
#'     `stderr` instead. A directory failure has the error of the deletion
#'     as the parent. `condathis` raises it after it cleaned the other
#'     backends and directories. A `status` that is not a whole
#'     number aborts with `condathis_backend_invalid_return`. The warnings
#'     `condathis_backend_not_installed` and `condathis_backend_load_failed`
#'     name a backend whose caches were not cleaned.
#'   }
#'   \item{[validate_env()]}{
#'     Arguments: `condathis_validate_env_invalid_packages`,
#'     `condathis_validate_env_positional_env_name`,
#'     `condathis_validate_env_invalid_env_name`,
#'     `condathis_validate_env_invalid_channels` and
#'     `condathis_validate_env_invalid_platform`. The environment:
#'     `condathis_validate_env_env_not_found` and
#'     `condathis_validate_env_unsatisfied`. The backend:
#'     `condathis_validate_env_failed`.
#'   }
#'   \item{[env_exists()], [list_envs()], [list_packages()], [get_env_dir()]
#'     and [get_install_dir()]}{
#'     `condathis_<function>_invalid_env_name` for the functions that take
#'     `env_name`, `condathis_list_packages_env_not_found`, and
#'     `condathis_<function>_failed` (not for [get_env_dir()]).
#'   }
#'   \item{[install_micromamba()]}{
#'     Arguments: `condathis_install_micromamba_invalid_micromamba_version`,
#'     `condathis_install_micromamba_invalid_timeout`,
#'     `condathis_install_micromamba_invalid_download_method`,
#'     `condathis_install_micromamba_invalid_force` and
#'     `condathis_install_micromamba_conflicting_args` (`timeout` and
#'     `timeout_limit`). Then `condathis_install_micromamba_unsupported_version`
#'     and `condathis_install_micromamba_download_failed`. The warnings
#'     `condathis_install_micromamba_checksum_unavailable` and
#'     `condathis_install_micromamba_checksum_mismatch` concern the SHA256
#'     check of a download.
#'   }
#'   \item{The micromamba backend}{
#'     `condathis_micromamba_status_error` (a `micromamba` command failed),
#'     `condathis_micromamba_bin_path_not_executable`,
#'     `condathis_micromamba_version_not_detected`,
#'     and `condathis_micromamba_not_available_for_arch`.
#'   }
#'   \item{Replacing an environment}{
#'     For [create_env()] with `overwrite = TRUE`, on every backend, three
#'     classes apply. `condathis_env_set_aside_failed`: the existing
#'     environment could not be moved aside, so it is unchanged.
#'     `condathis_env_not_restored`: the create failed and the old
#'     environment could not be moved back. The error has the field
#'     `kept_env_dir` with where it is kept. The warning
#'     `condathis_env_restore_failed`: the same after an interrupt, also
#'     with `kept_env_dir`. The micromamba backend adds
#'     `condathis_micromamba_env_set_aside_failed` and
#'     `condathis_micromamba_env_restore_failed`. When `condathis` replaces,
#'     removes or cleans up an environment, it refuses to delete or move a
#'     directory that is not exactly `<root>/envs/<env_name>`. The error has
#'     the class `condathis_unsafe_env_dir_delete` or
#'     `condathis_unsafe_env_dir_move`.
#'   }
#'   \item{[run()] and [run_bin()]}{
#'     Arguments, with `run` or `run_bin` as `<function>`:
#'     `condathis_<function>_invalid_cmd`,
#'     `condathis_<function>_invalid_args` (a value in `...`, also
#'     `condathis_invalid_cmd_args`),
#'     `condathis_<function>_invalid_input`,
#'     `condathis_<function>_invalid_binary`,
#'     `condathis_<function>_invalid_env_name` and
#'     `condathis_<function>_invalid_<argument>` for `timeout`, `supervise`,
#'     `cleanup_tree`, `linux_pdeathsig`, `stdin`, `stdout`, `stderr` and,
#'     for [run_bin()], `activate`. Then
#'     `condathis_<function>_env_not_found`,
#'     `condathis_<function>_resolve_failed`,
#'     `condathis_<function>_status_error` and
#'     `condathis_<function>_timeout_error`. A failed activation of the
#'     micromamba backend adds the classes of its error to the resolve
#'     error. On Linux and macOS, an `activate.d` script that exits with a
#'     non-zero status adds `condathis_micromamba_status_error` and
#'     `condathis_cmd_status_error`.
#'     A missing or unreadable activation result adds
#'     `condathis_activation_dump_error`, and a missing environment
#'     directory adds `condathis_activation_env_not_found`.
#'   }
#'   \item{[run_pipeline()]}{
#'     Arguments: `condathis_run_pipeline_invalid_step`,
#'     `condathis_run_pipeline_too_few_commands`,
#'     `condathis_run_pipeline_conflicting_method`,
#'     `condathis_run_pipeline_invalid_env_name`,
#'     `condathis_run_pipeline_invalid_input`,
#'     `condathis_run_pipeline_invalid_binary` and
#'     `condathis_run_pipeline_invalid_<argument>` for `timeout`,
#'     `supervise`, `cleanup_tree`, `linux_pdeathsig`, `activate`, `stdin`,
#'     `stdout` and `stderr`. Then `condathis_run_pipeline_env_not_found`,
#'     `condathis_run_pipeline_resolve_failed`,
#'     `condathis_run_pipeline_status_error` and
#'     `condathis_run_pipeline_timeout_error`.
#'   }
#'   \item{[run_step()]}{
#'     `condathis_run_step_invalid_cmd`, `condathis_run_step_invalid_args`,
#'     `condathis_run_step_invalid_env_name`,
#'     `condathis_run_step_invalid_method` and
#'     `condathis_run_step_invalid_stderr`.
#'   }
#'   \item{[env_path()]}{
#'     `condathis_env_path_invalid_path` (the `path` argument),
#'     `condathis_env_path_invalid` (a malformed `env_path()` object. It is
#'     also the second class of a `path` error),
#'     `condathis_env_path_read_only` (passed to a function that takes only
#'     names), `condathis_env_path_unsupported_method` (a `method` that
#'     names a backend that cannot run commands in such an environment,
#'     also `condathis_backend_unsupported`), and
#'     `condathis_env_path_not_found` and
#'     `condathis_env_path_not_conda_env` (also `condathis_env_not_found`).
#'   }
#'   \item{[parse_output()]}{
#'     `condathis_parse_output_invalid_res`,
#'     `condathis_parse_output_invalid_stream`,
#'     `condathis_parse_output_invalid_trim` and
#'     `condathis_parse_output_binary_stream` (a raw stream cannot be
#'     parsed as text).
#'   }
#'   \item{[with_sandbox_dir()]}{
#'     The warning `condathis_with_sandbox_dir_cleanup_failed`: the sandbox
#'     could not be deleted.
#'   }
#'   \item{Backend selection (`method`)}{
#'     `condathis_backend_not_registered`,
#'     `condathis_backend_none_available`, `condathis_backend_mismatch` (a
#'     change to an environment of another backend),
#'     `condathis_backend_ambiguous_env` (several backends have the
#'     environment), `condathis_backend_not_installed` and
#'     `condathis_backend_load_failed` (the package of the backend cannot be
#'     used), and the warnings `condathis_backend_mismatch_warning`,
#'     `condathis_backend_marker_mismatch` and
#'     `condathis_invalid_backend_priority_option`.
#'   }
#'   \item{[register_backend()] and [unregister_backend()]}{
#'     `condathis_backend_invalid_name`, `condathis_backend_reserved_name`,
#'     `condathis_backend_root_conflict` (the condathis data directory has
#'     an entry of that name that is not a directory),
#'     `condathis_backend_name_conflict` (the name differs only in case from
#'     another backend name), `condathis_backend_class_conflict` and
#'     `condathis_backend_contract_violation`. A backend gives its own
#'     condition the class `condathis_backend_unsupported` when it cannot
#'     honor an argument, and never the class `condathis_backend_error`.
#'   }
#' }
#'
#' @section Renamed classes:
#' These classes of `condathis` 0.1.4 were renamed to follow the scheme.
#' Each old name is kept as an extra class until `condathis` 1.0, so
#' existing handlers keep working. Use the new names in new code.
#'
#' | New class | Old class |
#' |:----------|:----------|
#' | `condathis_create_env_invalid_overwrite` | `condathis_create_invalid_overwrite_arg` |
#' | `condathis_create_env_missing_env_file` | `condathis_create_missing_env_file` |
#' | `condathis_remove_env_env_not_found` | `condathis_error_env_remove` |
#' | `condathis_list_packages_env_not_found` | `condathis_list_packages_missing_env` |
#' | `condathis_install_micromamba_download_failed` | `condathis_install_error_missing_bzip2` |
#' | `condathis_micromamba_bin_path_not_executable` | `condathis_umamba_bin_path_not_executable` |
#' | `condathis_micromamba_version_not_detected` | `condathis_umamba_version_not_detected` |
#' | `condathis_micromamba_not_available_for_arch` | `condathis_umamba_not_available_for_arch` |
#' | `condathis_micromamba_status_error` | `condathis_cmd_status_error` |
#' | `condathis_run_invalid_cmd` | `condathis_run_null_cmd` |
#' | `condathis_run_invalid_stdin`, `condathis_run_bin_invalid_stdin` | `condathis_run_stdin_error` |
#' | `condathis_run_bin_status_error` | `condathis_run_status_error` |
#' | `condathis_run_invalid_args`, `condathis_run_bin_invalid_args` (a named value) | `rlib_error_dots_named`, `rlib_error_dots` |
#'
#' `condathis_install_error_missing_bzip2` is deprecated: a failed download
#' does not depend on `bzip2`.
#'
#' @examples
#' condathis::with_sandbox_dir({
#'   # A missing environment, in any function
#'   print(tryCatch(
#'     condathis::list_packages(env_name = "no-such-env"),
#'     condathis_env_not_found = function(cnd) "not found"
#'   ))
#'
#'   # An invalid argument aborts before anything runs
#'   print(tryCatch(
#'     condathis::create_env(env_name = "my-env", overwrite = "yes"),
#'     condathis_invalid_arg = function(cnd) class(cnd)
#'   ))
#' })
#'
#' \dontrun{
#' condathis::with_sandbox_dir({
#'   # The fields of a status error. The command is the Rscript of this R,
#'   # run in the default environment, which is created empty.
#'   rscript <- file.path(
#'     R.home("bin"),
#'     if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
#'   )
#'   tryCatch(
#'     condathis::run(rscript, "-e", "quit(status = 3)", verbose = "silent"),
#'     condathis_status_error = function(cnd) cnd$status
#'   )
#' })
#' }
#'
#' @seealso [condathis-options], [register_backend()]
#'
#' @name condathis-conditions
#' @aliases condathis_conditions
NULL
