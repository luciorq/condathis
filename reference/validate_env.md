# Check that an environment has the requested packages

Checks that an environment exists, and that its installed packages
satisfy every package match spec. `validate_env()` is a query: it never
creates or changes an environment. With the micromamba backend, it
reports an environment that does not exist without starting a process or
installing micromamba. When no micromamba binary is installed, the
micromamba backend reads the `envs` directory of its data directory and
the package records in `conda-meta/` instead. It never installs
micromamba.

## Usage

``` r
validate_env(
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = "silent",
  channels = NULL,
  platform = NULL,
  error = c("cancel", "continue")
)
```

## Arguments

- ...:

  Package match specs (MatchSpec strings), unnamed, as in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md):
  character strings or character vectors, in order. With no specs,
  `validate_env()` only checks that the environment exists. An installed
  package satisfies a spec when it matches the name, version, build
  string and channel of the spec, as *Existing environments* in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  describes. The name match ignores case: `"PyYAML"` matches `pyyaml`. A
  spec without a channel matches a package from `channels` (see below).
  A spec with a channel, such as `"conda-forge::zlib"`, matches only a
  package from that channel. A spec that is not compared, such as
  `"zlib[md5=...]"` or `"zlib<2.*"`, never counts as satisfied. These
  values abort with class `condathis_validate_env_invalid_packages`:

  - A named argument that `validate_env()` does not have.

  - A value that is not a character vector.

  - `NA` or `""`.

  - A file name that ends in `.yml` or `.yaml`.

  `validate_env()` aborts with class
  `condathis_validate_env_positional_env_name` when `env_name` is not
  given and the last of two or more specs names an existing environment.
  A spec that condathis cannot read, such as `"::"`, aborts with class
  `condathis_parse_match_spec_invalid_name`. For the URL of a package
  file, the class is `condathis_parse_match_spec_invalid_url`. Both
  errors also have class `condathis_invalid_arg`. They abort with
  `error = "continue"` too.

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
  on first use. It aborts with class `condathis_backend_not_installed`
  when the package is not installed. `"native"` is a deprecated alias
  for `"micromamba"` (warns once per session). If you name a backend
  other than the owner, functions that change the environment abort with
  class `condathis_backend_mismatch`. The others warn
  (`condathis_backend_mismatch_warning`) and use the owner. An
  environment found under several backends aborts with
  `condathis_backend_ambiguous_env` unless `method` names one of them.
  Invalid values abort with class `condathis_invalid_method`.

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

- channels:

  `NULL` (the default) or a non-empty character vector of channel names
  or URLs. With `NULL`, a spec without a channel matches a package from
  any channel. Otherwise, a spec without a channel must match a package
  from one of `channels`, compared as in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).
  A spec with a channel ignores `channels`. There is no
  `additional_channels`: put those channels in `channels`. Invalid
  values abort with class `condathis_validate_env_invalid_channels`.

- platform:

  `NULL` (the default) or a known conda platform name, such as
  `"linux-64"`, as `platform` of
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  accepts. When given, the packages of the environment must be built for
  it (`noarch` packages match any platform). Other values abort with
  class `condathis_validate_env_invalid_platform`.

- error:

  Character string. What happens when the environment does not exist or
  does not have the requested packages: `"cancel"` (the default) aborts,
  and `"continue"` returns `FALSE`. A backend failure always aborts.
  Invalid values abort with class `condathis_invalid_error`.

## Value

`TRUE`, invisibly, when the environment exists and has every requested
package. Otherwise, with `error = "cancel"`, it aborts. The class is
`condathis_validate_env_env_not_found` (also `condathis_env_not_found`)
when the environment does not exist. The class is
`condathis_validate_env_unsatisfied` when a spec is not satisfied or the
platform differs. The message lists each spec that is not satisfied.
With `error = "continue"`, it returns `FALSE` with two attributes.
`reason` is one of `"env_not_found"`, `"platform_mismatch"` and
`"unsatisfied"`. `unsatisfied` is a character vector of the specs that
are not satisfied (every spec when the environment does not exist).
`validate_env()` reports a platform mismatch before unsatisfied specs. A
backend failure aborts with class `condathis_validate_env_failed` (also
`condathis_backend_error`).

## Details

It uses the same check as `create_env(overwrite = FALSE)`. A spec
without a channel must match a package from `channels`, or from any
channel when `channels` is `NULL` (the default). Given
`channels = c(channels, additional_channels)` of a
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
call (by default `"conda-forge"`), `validate_env()` gives the same
answer as that call, with two exceptions. They exist because
`validate_env()` only reads:

- When `method` names a backend that does not own the environment,
  `validate_env()` warns with class `condathis_backend_mismatch_warning`
  and checks the environment with its owner.
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  aborts with class `condathis_backend_mismatch`.

- When a backend cannot tell whether the environment exists,
  `validate_env()` still lists its packages, and reports the listing's
  error if it fails.
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  aborts with class `condathis_backend_probe_failed`.

## See also

[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for every condition class.

Other environments:
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md),
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)

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

  # TRUE, invisibly.
  condathis::validate_env("polyglot", env_name = "polyglot-env")

  # Also TRUE: `polyglot` comes from `channel`, as `create_env()` with
  # the same channels requires.
  condathis::validate_env(
    "polyglot",
    env_name = "polyglot-env",
    channels = channel
  )

  # FALSE, with the reason and the specs that are not satisfied.
  res <- condathis::validate_env(
    "polyglot>=2",
    env_name = "polyglot-env",
    error = "continue"
  )
  print(attr(res, "reason"))
  #> [1] "unsatisfied"
  attr(res, "unsatisfied")
  #> [1] "polyglot>=2"
})
} # }
```
