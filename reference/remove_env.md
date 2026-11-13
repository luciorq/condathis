# Remove a Conda environment

Removes an environment managed by `condathis`.

## Usage

``` r
remove_env(
  env_name = "condathis-env",
  method = "auto",
  verbose = c("output", "silent", "cmd", "spinner", "full")
)
```

## Arguments

- env_name:

  Character string with the environment name. It must be a plain
  directory name that is valid on Linux, macOS and Windows:

  - Not empty, and not `.` or `..`.

  - Not starting with `-`, and not ending with `.`.

  - Without path separators, `:`, `#`, whitespace, control characters or
    `<>"|?*`.

  - Not a Windows device name, such as `NUL` or `COM1` (see *Environment
    names* in
    [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)).

  Invalid values abort with class `condathis_invalid_env_name`.
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  and
  [`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)
  also accept an
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  value. The other functions reject it with class
  `condathis_env_path_read_only`.

- method:

  Character string naming the backend. `"auto"` (the default) uses the
  backend that owns `env_name` when it exists, and otherwise the first
  available backend in `getOption("condathis.backend_priority")` order
  (see
  [condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)).
  Any name from
  [`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md)
  selects that backend, and `"micromamba"` is built in. The name of a
  backend whose package `condathis` knows, such as `"rattler"` of the
  `rattlerthis` package, also selects it. `condathis` loads the package
  on first use. `"native"` is a deprecated alias for `"micromamba"`
  (warns once per session). The 0.1.4 default `c("native", "auto")` is
  read as `"native"`.

  If you name a backend other than the owner, functions that change the
  environment abort. The others warn and use the owner. The classes:

  - `condathis_backend_not_installed`: the package of the named backend
    is not installed.

  - `condathis_backend_mismatch`: the named backend does not own the
    environment, and the function changes it.

  - `condathis_backend_mismatch_warning` (a warning): the same, for a
    function that does not change the environment.

  - `condathis_backend_ambiguous_env`: several backends have an
    environment of that name, and `method` names none of them.

  - `condathis_invalid_method`: an invalid value.

- verbose:

  Character string that controls the console output. One of:

  - `"output"`: show the output of the command and the messages of
    `condathis`.

  - `"silent"`: show nothing.

  - `"cmd"`: show the command line.

  - `"spinner"`: show only a spinner.

  - `"full"`: show the command line, the output, and the backend's own
    log.

  `TRUE` means `"output"` and `FALSE` means `"silent"`. Every level
  except `"silent"` shows a spinner in interactive sessions. It also
  shows these messages and this warning when they occur (see
  [condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)):

  - `condathis_micromamba_downloading` (a message): no usable
    `micromamba` was found, so it is downloaded. Queries, such as
    [`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
    never download it.

  - `condathis_env_lock_waiting` and `condathis_cache_lock_waiting`
    (messages): the call waits for another R session.

  - `condathis_install_micromamba_checksum_unavailable` (a warning): the
    checksum of the downloaded `micromamba` could not be checked.

  Invalid values abort with class `condathis_invalid_verbose`. The
  default is shown in Usage.

  The command line shown, the `cmd` of a result and the messages of
  `condathis` show the password and the token of a URL as `*****`.
  `micromamba` does the same (`https://user:*****@host/channel`,
  `https://host/t/*****/channel`). The command still gets them.

## Value

A `condathis_result` object, invisibly: a classed list with `status`,
`stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`. `cmd` is the
command line that the backend ran, or `NA` when the backend reports
none. `stdout`, `stderr` and `pid` are `NA` when the backend reports
none, and `pid` always is with micromamba. An environment that does not
exist aborts with class `condathis_remove_env_env_not_found` (also
`condathis_env_not_found` and the 0.1.4 class
`condathis_error_env_remove`). `remove_env()` deletes nothing then, not
even a leftover directory of that name. A backend failure aborts with
class `condathis_remove_env_failed` (also `condathis_backend_error`),
with the backend's error as the parent. micromamba runs the `pre-unlink`
scripts of packages before it removes them. A backend that does not
makes `remove_env()` warn with class
`condathis_remove_env_link_scripts_skipped` (also
`condathis_link_scripts_skipped`). The warning names the packages.

## Details

With the micromamba backend, `remove_env()` does not change
`~/.conda/environments.txt`, the registry that conda and mamba share. A
line that
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
added to that file stays (see Details in
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).
On Windows, it also leaves the Start Menu shortcuts that `condathis`
0.1.4 and earlier added for packages such as `spyder`. Delete them from
the Start Menu.

## Other R sessions

Only one R session at a time changes an environment.
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
and `remove_env()` hold a lock on the environment name while they work,
with every backend. A call for an environment that another R session is
changing waits until that session is done. After two seconds, the call
says so with a message of class `condathis_env_lock_waiting`.
`verbose = "silent"` hides this message. Ctrl-C stops the wait.
[`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
waits until no other R session creates an environment or installs
packages. Those calls wait while it cleans. Each wait gives a message of
class `condathis_cache_lock_waiting`. A lock lasts only as long as its
session, also when the session crashes or is killed. The lock files are
in the directory `locks` of the condathis data directory (see
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).
Where files cannot be locked, such as on some network file systems, the
call goes on without the lock. When it changes something, it warns once
per session with class `condathis_env_lock_unavailable`.

## See also

[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for every condition class.

Other environments:
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md),
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md),
[`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md)

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # A local channel shipped with condathis, with `polyglot`: a
  # dependency-free script that runs on Linux, macOS and Windows.
  channel <- system.file(
    "extdata", "polyglot-channel",
    package = "condathis"
  )
  condathis::create_env(
    "polyglot",
    env_name = "polyglot-env",
    channels = channel
  )
  condathis::remove_env(env_name = "polyglot-env")
})
} # }
```
