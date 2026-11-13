# List packages in a Conda environment

Returns the packages installed in a Conda environment, as a data frame.

## Usage

``` r
list_packages(env_name = "condathis-env", method = "auto", verbose = "silent")
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

A data frame (a tibble) with one row per installed package, returned
visibly. Six columns are guaranteed on every backend:

- `name` (chr): the package name.

- `version` (chr): the package version.

- `build_number` (int): the build number.

- `build_string` (chr): the build string.

- `channel` (chr): a channel name or URL.

- `platform` (chr): the platform subdirectory, such as `"linux-64"` or
  `"noarch"`.

The list includes the packages that pip or uv installed into the
environment, with every backend. It shows them as micromamba does:
channel `"pypi"`, build string `"pypi_0"`, build number 0, and the
platform as pip reports it, such as `"linux-x86_64"`. Only the
environment's own `site-packages` counts, not the user's site directory
or `PYTHONPATH`.

Other columns vary by backend. Do not rely on them in code that must
work with every backend. The `"micromamba"` backend today also includes
`base_url`, `dist_name`, `md5`, `sha256` and `url`.

`list_packages()` shows the password and the token of a channel URL as
`*****`, as micromamba does (`https://user:*****@host/channel`,
`https://host/t/*****/channel`).

It aborts with these classes:

- `condathis_list_packages_env_not_found` (also
  `condathis_env_not_found`): a missing environment.

- `condathis_list_packages_failed` (also `condathis_backend_error`): a
  failed listing. A listing without the six columns also has the class
  `condathis_backend_invalid_return`.

## Details

`list_packages()` is a query: it never creates an environment, also not
the default `"condathis-env"`. A missing environment aborts. When the
environment has no directory, as on a new data directory,
`list_packages()` does not start or install micromamba. When no
micromamba binary is installed, the micromamba backend reads the `envs`
directory of its data directory and the package records in `conda-meta/`
instead. It never installs micromamba.

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
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md),
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

  # Create a Conda environment with `polyglot`
  condathis::create_env(
    "polyglot",
    env_name = "polyglot-env",
    channels = channel
  )
  # List the packages of the environment `polyglot-env`
  dat <- condathis::list_packages("polyglot-env")
  print(dat[, c("name", "version", "channel")])
})
} # }
```
