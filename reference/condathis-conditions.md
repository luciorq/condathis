# Condition classes of condathis

Every error that `condathis` raises has the class `condathis_error`, and
every warning has the class `condathis_warning`. Each condition also has
more specific classes. Use them to handle one kind of problem with
[`base::tryCatch()`](https://rdrr.io/r/base/conditions.html),
[`base::withCallingHandlers()`](https://rdrr.io/r/base/conditions.html)
or
[`rlang::try_fetch()`](https://rlang.r-lib.org/reference/try_fetch.html),
and to test for it with `testthat::expect_error(class = )`. Do not match
the text of a message: it can change in any release.

## The class scheme

The classes of a condition go from the most specific to the most
general:

1.  The class of the function and the problem,
    `condathis_<function>_<problem>`, with the full name of the exported
    function. For example:

    - `condathis_create_env_exists`

    - `condathis_run_bin_env_not_found`

2.  Older names of that class, kept so that existing handlers still work
    (see *Renamed classes*). Some classes carry further names that this
    page does not list: do not rely on them.

3.  Shared classes for the kind of problem. For example:

    - `condathis_invalid_overwrite` and `condathis_invalid_arg`

    - `condathis_env_not_found`

4.  The root class, `condathis_error` or `condathis_warning`.

The rlang package adds its own classes after these, such as
`rlang_error`, `error` and `condition`.

For example, `create_env(overwrite = "yes")` aborts with these classes:

    c(
      "condathis_create_env_invalid_overwrite",
      "condathis_create_invalid_overwrite_arg",
      "condathis_invalid_overwrite",
      "condathis_invalid_arg",
      "condathis_error"
    )

The checks of `verbose`, `method` and `error` are the same in every
function, so their errors have only shared classes, for example:

    c(
      "condathis_invalid_verbose",
      "condathis_invalid_arg",
      "condathis_error"
    )

Handle the most general class that fits. A handler for
`condathis_env_not_found` catches a missing environment in every
function, and a handler for `condathis_error` catches every error of
`condathis`.

## Shared classes

- `condathis_invalid_arg`  
  An argument has an invalid value. `condathis` checks the arguments
  before it changes anything, so such an error has no side effects.

- `condathis_invalid_<argument>`  
  An invalid value of one argument, with its exact name. It always comes
  with the class `condathis_invalid_arg`. For example:

  - `condathis_invalid_env_name`

  - `condathis_invalid_packages`

  - `condathis_invalid_channels`

  - `condathis_invalid_method`

  - `condathis_invalid_verbose`

  - `condathis_invalid_error`

  - `condathis_invalid_timeout`

- `condathis_parse_match_spec_invalid_name`  
  `condathis_parse_match_spec_invalid_url`  
  A package spec that condathis cannot read, such as `"::"`, or the URL
  of a package file whose name is not `<name>-<version>-<build>`.
  `condathis` reads the specs when it compares them with an existing
  environment, in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  and
  [`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md).
  Also `condathis_invalid_arg`.

- `condathis_env_not_found`  
  The environment does not exist. A missing environment is created only
  by [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  and
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
  and only the default `"condathis-env"`. With `error = "continue"`, the
  run family returns status 127 instead. When the environment is in the
  data directory of a backend whose package cannot be used, the message
  names that backend (see the class `condathis_backend_not_installed`
  below).

- `condathis_backend_error`  
  A backend failed. The function classes are:

  - `condathis_<function>_failed`

  - `condathis_<function>_resolve_failed`  
    a command or its activation could not be resolved.

  - `condathis_backend_probe_failed`

  The backend's error is the parent, so its classes are found by
  [`rlang::cnd_inherits()`](https://rlang.r-lib.org/reference/cnd_inherits.html).
  The `condathis_*` classes of the backend's error are also copied, for
  example:

  - `condathis_micromamba_status_error`

- `condathis_backend_probe_failed`  
  A backend could not tell whether the environment exists.
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  and
  [`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)
  then stop before they change anything. Also `condathis_backend_error`.

- `condathis_backend_query_failed` (a warning)  
  With `method = "auto"`, a query of one backend failed, and the
  function skipped that backend.

- `condathis_backend_invalid_return`  
  A backend returned a value that breaks the contract of
  [`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md).
  The message names the backend. Also:

  - `condathis_backend_contract_violation`

  For the value of `backend_resolve_run()`, the first class is:

  - `condathis_backend_resolve_run_invalid`

- `condathis_backend_contract_violation`  
  A backend breaks the contract, when it is registered or in a return
  value.

- `condathis_backend_not_installed`  
  The package of a backend that condathis knows, such as `"rattler"` of
  the `rattlerthis` package, is not installed. It is:

  - an error when `method` names that backend (with the classes of an
    invalid `method`).

  - an error when a call would change an environment in the data
    directory of that backend (with `condathis_backend_mismatch`).

  - a warning when a query skips the environments of that backend (once
    per session).

  - a warning when
    [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
    cannot clean its caches.

- `condathis_backend_load_failed`  
  The same, when the package is installed but failed to load, did not
  register its backend, or its backend was unregistered in this session.
  The error of the load is the parent. Also a warning, once per session,
  when `condathis` tried to load the package. It tries this when its
  backend has environments or caches, or when the option
  `condathis.backend_priority` names it.

- `condathis_link_scripts_skipped` (a warning)  
  The backend did not run the pre-link, post-link or pre-unlink scripts
  of some packages, which micromamba runs, so these packages may not
  work. The call itself succeeded. The warning has the fields `backend`,
  `env_name`, `packages` (the package names, sorted) and `scripts` (a
  data frame with the columns `package` and `script`).

- `condathis_backend_quiesce_failed` (a warning)  
  [`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)
  or
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  could not tell whether a backend still works in the R process, and
  went on.

- `condathis_env_lock_waiting` (a message, neither an error nor a
  warning)  
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  or
  [`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)
  waits for another R session that changes the same environment (see
  *Other R sessions* in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)).

- `condathis_cache_lock_waiting` (a message)  
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  waits for other R sessions that create environments or install
  packages, or these wait for a
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  of another session.

- `condathis_micromamba_downloading` (a message)  
  A function that needs `micromamba` found no usable binary and
  downloads the default version with
  [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md).
  The message names the version and the path. `verbose = "silent"` hides
  it.

- `condathis_env_lock_unavailable` (a warning, once per session)  
  The lock of the environment or of the package caches could not be
  taken, for example on a file system that cannot lock files. The call
  went on without it.

- `condathis_status_error`  
  A command of
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  or
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  exited with a status other than 0.

- `condathis_timeout_error`  
  A command of
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  or
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  ran longer than `timeout` and was killed.

- `condathis_micromamba_status_error`  
  A `micromamba` command that condathis started for the micromamba
  backend failed. It carries the fields `status` and `stderr`, also when
  it is the class of a backend failure that condathis re-raised.

- Deprecated arguments and values, which still work but will be removed
  (warnings):

  - `condathis_deprecated_packages_arg`  
    for `packages =` in
    [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
    [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
    and
    [`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md):
    once per session and function, for calls from the console, a script
    or the tests of the calling package. Calls made inside other
    packages do not warn. `options(lifecycle_verbosity = "warning")`
    makes those calls warn too, and `"quiet"` turns the warning off.

  - `condathis_deprecated_env_file_arg`  
    for `env_file =` in
    [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md):
    pass an
    [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md)
    in `...` instead. The same rule as for `packages =`.

  - `condathis_deprecated_method_native`  
    for `method = "native"` (once per session).
    [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
    [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
    [`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md),
    [`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md),
    [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
    [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
    apply the same rule as for `packages =`.

  - `condathis_deprecated_arg`  
    for `timeout_limit` in
    [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md).

## Error fields

The status and timeout errors of
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
and
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
carry these fields, so a handler does not need to read the message:

- `status`: the exit status, an integer. It is `-9` for a timeout, and
  `127` for a command that could not start. A command killed by signal
  `n` has the status `128 + n` in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) on
  Linux and macOS, as in a shell. In
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  and
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
  the status is `-n`.

- `stdout`, `stderr`: the captured output, or `NA` when that stream was
  not captured.

- `timeout`: `TRUE` for a timeout, `FALSE` otherwise.

The errors of
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
also carry `result`, the `condathis_pipeline` result, and `statuses`,
the status of each command.

## Classes of each function

Each function also raises the shared classes above. The checks of
`verbose`, `method` and `error` raise only shared classes.

### create_env()

The classes of
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).
Arguments:

- `condathis_create_env_invalid_packages`

- `condathis_create_env_positional_env_name`

- `condathis_create_env_invalid_env_name`

- `condathis_create_env_invalid_channels`

- `condathis_create_env_invalid_channel_priority`

- `condathis_create_env_invalid_platform`

- `condathis_create_env_invalid_env_file`  
  an invalid value of the deprecated `env_file`.

- `condathis_create_env_missing_env_file`  
  the file of an
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md)
  or of `env_file` does not exist.

- `condathis_create_env_invalid_overwrite`

- `condathis_create_env_conflicting_args`  
  package specs and an
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md),
  two definitions, a definition and `env_file`, or `channels`,
  `additional_channels` or `channel_priority` with a lock file given by
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md).
  The deprecated `env_file` ignores them, as in 0.1.4.

- `condathis_create_env_unsupported_definition`  
  the backend cannot read the
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md),
  or no available backend can with `method = "auto"`. Also
  `condathis_backend_unsupported`.

The environment:

- `condathis_create_env_exists`  
  it exists, and `overwrite = FALSE` cannot keep it. A lock file keeps
  it only when the environment has exactly the packages of the lock.

- `condathis_create_env_platform_mismatch`

- `condathis_create_env_platform_not_locked`  
  a lock file lists none of the platforms that
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  can use. Also `condathis_create_env_platform_mismatch`.

The backend:

- `condathis_create_env_failed`  
  also when a lock file that lists packages gives an empty environment.

- `condathis_create_env_link_scripts_skipped` (a warning)

### install_packages()

The classes of
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md).
Arguments:

- `condathis_install_packages_missing_packages`

- `condathis_install_packages_invalid_packages`

- `condathis_install_packages_positional_env_name`

- `condathis_install_packages_invalid_env_name`

- `condathis_install_packages_invalid_channels`

- `condathis_install_packages_invalid_channel_priority`

- `condathis_install_packages_conflicting_args`  
  package specs and an
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md),
  or two definitions.

- `condathis_install_packages_missing_env_file`  
  the file of an
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md)
  does not exist.

- `condathis_install_packages_unsupported_definition`  
  a lock file, or a file that the backend cannot read or install from
  (then also `condathis_backend_unsupported`).

The environment:

- `condathis_install_packages_env_not_found`

The backend:

- `condathis_install_packages_failed`

- `condathis_install_packages_link_scripts_skipped` (a warning)

- `condathis_install_packages_missing_previous_channels` (a warning)  
  a channel the environment was built from is not in the call. This
  holds on every backend that records the channels in
  `conda-meta/history`.

### remove_env()

The classes of
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md):

- `condathis_remove_env_invalid_env_name`

- `condathis_remove_env_env_not_found`

- `condathis_remove_env_failed`

- `condathis_remove_env_link_scripts_skipped` (a warning)  
  pre-unlink scripts.

### clean_cache()

The classes of
[`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md):

- `condathis_clean_cache_failed`  
  a backend failed to clean its caches, or `condathis` could not empty
  one of its own cache directories. `condathis` raises it after it
  cleaned the other backends and directories.

  - A backend failure also has `condathis_backend_error`, with the error
    of the backend as the parent. For a non-zero `status` that the
    backend returned without an error, it has the fields `status`,
    `stdout` and `stderr` instead.

  - A directory failure has the error of the deletion as the parent.

- `condathis_backend_invalid_return`  
  a backend returned a `status` that is not a whole number.

- `condathis_backend_not_installed` and `condathis_backend_load_failed`
  (warnings)  
  name a backend whose caches were not cleaned.

### validate_env()

The classes of
[`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md).
Arguments:

- `condathis_validate_env_invalid_packages`

- `condathis_validate_env_positional_env_name`

- `condathis_validate_env_invalid_env_name`

- `condathis_validate_env_invalid_channels`

- `condathis_validate_env_invalid_platform`

- `condathis_validate_env_conflicting_args`  
  package specs and an
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md),
  or two definitions.

- `condathis_validate_env_missing_env_file`  
  the file of an
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md)
  does not exist.

- `condathis_validate_env_unsupported_definition`  
  a file that cannot be compared: a request such as `environment.yml`, a
  lock whose packages the backend does not report, or a lock without
  packages for `platform`. Also `condathis_backend_unsupported` when the
  backend cannot read the file.

The environment:

- `condathis_validate_env_env_not_found`

- `condathis_validate_env_unsatisfied`  
  a spec is not satisfied, or the environment does not have exactly the
  packages of a lock file.

The backend:

- `condathis_validate_env_failed`

### Queries

These are the classes of the queries, with the name of the function as
`<function>`. The queries are
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md),
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md)
and
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md).

- `condathis_<function>_invalid_env_name`  
  for the functions that take `env_name`.

- `condathis_list_packages_env_not_found`

- `condathis_<function>_failed`  
  not for
  [`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md).

### install_micromamba()

The classes of
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md).
Arguments:

- `condathis_install_micromamba_invalid_micromamba_version`

- `condathis_install_micromamba_invalid_timeout`

- `condathis_install_micromamba_invalid_download_method`

- `condathis_install_micromamba_invalid_force`

- `condathis_install_micromamba_conflicting_args`  
  `timeout` and `timeout_limit`.

Then:

- `condathis_install_micromamba_unsupported_version`

- `condathis_install_micromamba_download_failed`

The warnings about the SHA256 check of a download:

- `condathis_install_micromamba_checksum_unavailable`  
  the binary is installed without the check. `verbose = "silent"` hides
  it.

- `condathis_install_micromamba_checksum_mismatch`  
  the binary is not installed. Shown also with `verbose = "silent"`.

### The micromamba backend

- `condathis_micromamba_downloading` (a message)  
  no usable binary was found, so it is downloaded.

- `condathis_micromamba_status_error`  
  a `micromamba` command failed.

- `condathis_micromamba_bin_path_not_executable`

- `condathis_micromamba_version_not_detected`

- `condathis_micromamba_not_available_for_arch`

### Replacing an environment

For
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
with `overwrite = TRUE`, on every backend, three classes apply:

- `condathis_env_set_aside_failed`  
  the existing environment could not be moved aside, so it is unchanged.

- `condathis_env_not_restored`  
  the create failed and the old environment could not be moved back. The
  error has the field `kept_env_dir` with where it is kept.

- `condathis_env_restore_failed` (a warning)  
  the same after an interrupt, also with `kept_env_dir`.

The micromamba backend adds:

- `condathis_micromamba_env_set_aside_failed`

- `condathis_micromamba_env_restore_failed`

When `condathis` replaces, removes or cleans up an environment, it
refuses to delete or move a directory that is not exactly
`<root>/envs/<env_name>`. The error has one of these classes:

- `condathis_unsafe_env_dir_delete`

- `condathis_unsafe_env_dir_move`

### run() and run_bin()

The classes of
[`run()`](https://luciorq.github.io/condathis/reference/run.md) and
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
with `run` or `run_bin` as `<function>`. Arguments:

- `condathis_<function>_invalid_cmd`

- `condathis_<function>_invalid_args`  
  a value in `...`, also `condathis_invalid_cmd_args`.

- `condathis_<function>_invalid_input`

- `condathis_<function>_invalid_binary`

- `condathis_<function>_invalid_env_name`

- `condathis_<function>_invalid_<argument>`  
  for `timeout`, `supervise`, `cleanup_tree`, `linux_pdeathsig`,
  `stdin`, `stdout`, `stderr` and, for
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  `activate`.

Then:

- `condathis_<function>_env_not_found`

- `condathis_<function>_resolve_failed`

- `condathis_<function>_status_error`

- `condathis_<function>_timeout_error`

A failed activation of the micromamba backend adds the classes of its
error to the resolve error:

- On Linux and macOS, an `activate.d` script that exits with a non-zero
  status adds two classes:

  - `condathis_micromamba_status_error`

  - `condathis_cmd_status_error`

- A missing or unreadable activation result adds
  `condathis_activation_dump_error`.

- A missing environment directory adds
  `condathis_activation_env_not_found`.

### run_pipeline()

The classes of
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md).
Arguments:

- `condathis_run_pipeline_invalid_step`

- `condathis_run_pipeline_too_few_commands`

- `condathis_run_pipeline_conflicting_method`

- `condathis_run_pipeline_invalid_env_name`

- `condathis_run_pipeline_invalid_input`

- `condathis_run_pipeline_invalid_binary`

- `condathis_run_pipeline_invalid_<argument>`  
  for `timeout`, `supervise`, `cleanup_tree`, `linux_pdeathsig`,
  `activate`, `stdin`, `stdout` and `stderr`.

Then:

- `condathis_run_pipeline_env_not_found`

- `condathis_run_pipeline_resolve_failed`

- `condathis_run_pipeline_status_error`

- `condathis_run_pipeline_timeout_error`

### run_step()

The classes of
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md):

- `condathis_run_step_invalid_cmd`

- `condathis_run_step_invalid_args`

- `condathis_run_step_invalid_env_name`

- `condathis_run_step_invalid_method`

- `condathis_run_step_invalid_stderr`

### env_path()

The classes of
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md):

- `condathis_env_path_invalid_path`  
  the `path` argument.

- `condathis_env_path_invalid`  
  a malformed
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  object. It is also the second class of a `path` error.

- `condathis_env_path_read_only`  
  passed to a function that takes only names.

- `condathis_env_path_unsupported_method`  
  a `method` that names a backend that cannot run commands in such an
  environment, also `condathis_backend_unsupported`.

- `condathis_env_path_not_found`  
  `condathis_env_path_not_conda_env`  
  also `condathis_env_not_found`.

### env_definition()

The classes of
[`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md):

- `condathis_env_definition_invalid_path`  
  the `path` argument, also a URL. Also `condathis_invalid_path`.

- `condathis_env_definition_invalid_format`

- `condathis_env_definition_invalid_options`  
  an unnamed or repeated option in `...`.

- `condathis_env_definition_invalid`  
  a malformed
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md)
  object, found by the function that gets it.

A definition passed to a function that takes only package specs or names
aborts with the class of the invalid argument of that function.

### parse_output()

The classes of
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md):

- `condathis_parse_output_invalid_res`

- `condathis_parse_output_invalid_stream`

- `condathis_parse_output_invalid_trim`

- `condathis_parse_output_binary_stream`  
  a raw stream cannot be parsed as text.

### with_sandbox_dir()

The classes of
[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md):

- `condathis_with_sandbox_dir_cleanup_failed` (a warning)  
  the sandbox could not be deleted.

### Backend selection (`method`)

The classes of the choice of a backend with `method`:

- `condathis_backend_not_registered`

- `condathis_backend_none_available`

- `condathis_backend_mismatch`  
  a change to an environment of another backend.

- `condathis_backend_ambiguous_env`  
  several backends have the environment.

- `condathis_backend_not_installed`  
  `condathis_backend_load_failed`  
  the package of the backend cannot be used.

The warnings:

- `condathis_backend_mismatch_warning`

- `condathis_backend_marker_mismatch`

- `condathis_invalid_backend_priority_option`

### register_backend() and unregister_backend()

The classes of
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)
and
[`unregister_backend()`](https://luciorq.github.io/condathis/reference/unregister_backend.md):

- `condathis_backend_invalid_name`

- `condathis_backend_reserved_name`

- `condathis_backend_root_conflict`  
  the condathis data directory has an entry of that name that is not a
  directory.

- `condathis_backend_name_conflict`  
  the name differs only in case from another backend name.

- `condathis_backend_class_conflict`

- `condathis_backend_contract_violation`

A backend gives its own condition the class
`condathis_backend_unsupported` when it cannot honor an argument, and
never the class `condathis_backend_error`.

## Renamed classes

These classes of `condathis` 0.1.4 were renamed to follow the scheme.
Each old name is kept as an extra class until `condathis` 1.0, so
existing handlers keep working. Use the new names in new code. Each item
gives the new class, then the old one:

- `condathis_create_env_invalid_overwrite`  
  old: `condathis_create_invalid_overwrite_arg`

- `condathis_create_env_missing_env_file`  
  old: `condathis_create_missing_env_file`

- `condathis_remove_env_env_not_found`  
  old: `condathis_error_env_remove`

- `condathis_list_packages_env_not_found`  
  old: `condathis_list_packages_missing_env`

- `condathis_install_micromamba_download_failed`  
  old: `condathis_install_error_missing_bzip2`

- `condathis_micromamba_bin_path_not_executable`  
  old: `condathis_umamba_bin_path_not_executable`

- `condathis_micromamba_version_not_detected`  
  old: `condathis_umamba_version_not_detected`

- `condathis_micromamba_not_available_for_arch`  
  old: `condathis_umamba_not_available_for_arch`

- `condathis_micromamba_status_error`  
  old: `condathis_cmd_status_error`

- `condathis_run_invalid_cmd`  
  old: `condathis_run_null_cmd`

- `condathis_run_invalid_stdin`  
  `condathis_run_bin_invalid_stdin`  
  old: `condathis_run_stdin_error`

- `condathis_run_bin_status_error`  
  old: `condathis_run_status_error`

- `condathis_run_invalid_args`  
  `condathis_run_bin_invalid_args`  
  (a named value) old: `rlib_error_dots_named`, `rlib_error_dots`

`condathis_install_error_missing_bzip2` is deprecated: a failed download
does not depend on `bzip2`.

## See also

[condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md),
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)

## Examples

``` r
condathis::with_sandbox_dir({
  # A missing environment, in any function
  print(tryCatch(
    condathis::list_packages(env_name = "no-such-env"),
    condathis_env_not_found = function(cnd) "not found"
  ))

  # An invalid argument aborts before anything runs
  print(tryCatch(
    condathis::create_env(env_name = "my-env", overwrite = "yes"),
    condathis_invalid_arg = function(cnd) class(cnd)
  ))
})
#> [1] "not found"
#> [1] "condathis_create_env_invalid_overwrite"
#> [2] "condathis_create_invalid_overwrite_arg"
#> [3] "condathis_invalid_overwrite"           
#> [4] "condathis_invalid_arg"                 
#> [5] "condathis_error"                       
#> [6] "rlang_error"                           
#> [7] "error"                                 
#> [8] "condition"                             

if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # The fields of a status error. The command is the Rscript of this R,
  # run in the default environment, which is created empty.
  rscript <- file.path(
    R.home("bin"),
    if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
  )
  tryCatch(
    condathis::run(rscript, "-e", "quit(status = 3)", verbose = "silent"),
    condathis_status_error = function(cnd) cnd$status
  )
})
} # }
```
