# List Conda environments managed by condathis

Returns a data frame of the environments under the data directory of
each registered backend. It leaves out environments that `condathis`
does not manage.

## Usage

``` r
list_envs(method = "auto", verbose = "silent")
```

## Arguments

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

A data frame (a tibble) with one row per environment and the columns
`backend` (chr), `env_name` (chr) and `path` (chr). The rows follow the
backend order of `method`. When the listing fails for the backend that
`method` names, `list_envs()` aborts with class
`condathis_list_envs_failed` (also `condathis_backend_error`). With
`method = "auto"`, `list_envs()` skips a backend whose listing fails and
warns with class `condathis_backend_query_failed`. It aborts only when
every backend fails.

## Details

`list_envs()` is a query: it never creates an environment. On a new data
directory, with no environment yet, it returns a data frame with no
rows. It does not start or install micromamba. When no micromamba binary
is installed, the micromamba backend reads the `envs` directory of its
data directory and the package records in `conda-meta/` instead. It
never installs micromamba.

## See also

[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for every condition class.

Other environments:
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
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

  # Create environments
  condathis::create_env(
    "polyglot",
    env_name = "polyglot-env",
    channels = channel
  )
  condathis::create_env(env_name = "empty-env")

  # List environments
  print(condathis::list_envs()$env_name)
  #> [1] "empty-env"    "polyglot-env"
})
} # }
```
