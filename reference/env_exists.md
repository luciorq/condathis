# Check whether a Conda environment exists

Checks whether an environment name is present in the environments
managed by `condathis`.

## Usage

``` r
env_exists(env_name = "condathis-env", method = "auto", verbose = "silent")
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
  Functions that take only names reject an
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  value with class `condathis_env_path_read_only`.
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  and
  [`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)
  accept one.

- method:

  Character string naming the backend to query. `"auto"` (the default)
  covers every registered backend, in
  `getOption("condathis.backend_priority")` order, also a backend that
  reports itself unavailable. Any name from
  [`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md)
  queries only that backend. `"micromamba"` is built in. The name of a
  backend whose package condathis knows, such as `"rattler"` of the
  `rattlerthis` package, also queries only that backend. condathis loads
  that package. When it is not installed, the call aborts with class
  `condathis_backend_not_installed`. `"native"` is a deprecated alias
  for `"micromamba"` (warns once per session). Invalid values abort with
  class `condathis_invalid_method`.

- verbose:

  Character string that controls the console output. One of:

  - `"output"`: show the output of the command and the messages of
    condathis.

  - `"silent"`: show nothing.

  - `"cmd"`: show the command line.

  - `"spinner"`: show only a spinner.

  - `"full"`: show the command line, the output, and the backend's own
    log.

  `TRUE` means `"output"` and `FALSE` means `"silent"`. Every level
  except `"silent"` shows a spinner in interactive sessions. Invalid
  values abort with class `condathis_invalid_verbose` (see
  [condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)).
  The default is shown in Usage.

  The command line shown, the `cmd` of a result and the messages of
  `condathis` show the password and the token of a URL as `*****`.
  `micromamba` does the same (`https://user:*****@host/channel`,
  `https://host/t/*****/channel`). The command still gets them.

## Value

`TRUE` when a queried backend reports the environment. `FALSE` when
every queried backend reports it absent. When the query fails for the
backend that `method` names, `env_exists()` aborts with class
`condathis_env_exists_failed` (also `condathis_backend_error`). With
`method = "auto"`, `env_exists()` skips a backend whose query fails and
warns with class `condathis_backend_query_failed`. It aborts only when
every backend fails.

## Details

`env_exists()` is a query: it never creates an environment. When
`env_name` has no directory under a backend's data directory, as on a
new data directory, `env_exists()` returns `FALSE`. It does not start or
install micromamba. When no micromamba binary is installed, the
micromamba backend reads the `envs` directory of its data directory and
the package records in `conda-meta/` instead. It never installs
micromamba.

## See also

[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for every condition class.

Other environments:
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md),
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

  # Create the environment
  condathis::create_env(
    "polyglot",
    env_name = "polyglot-env",
    channels = channel
  )

  # Check if the environment exists
  print(condathis::env_exists("polyglot-env"))
  #> [1] TRUE

  # Check for a non-existent environment
  condathis::env_exists("non-existent-env")
  #> [1] FALSE
})
} # }
```
