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
  `"zlib[md5=...]"` or `"zlib<2.*"`, never counts as satisfied. A spec
  for a virtual package, whose name starts with `__` (`"__cuda=12"`,
  `"__unix"`), is not checked: it describes the host, and an environment
  never lists it. `packages = <specs>` still works, as in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
  and `packages = NULL` only checks that the environment exists. It is
  deprecated. It warns once per session (class
  `condathis_deprecated_packages_arg`) when the call comes from the
  console, a script or the tests of the package that makes it. Calls
  made inside other packages do not warn.

  These values abort with class
  `condathis_validate_env_invalid_packages`:

  - A named argument that `validate_env()` does not have. Names are
    never abbreviated.

  - A value that is not a character vector.

  - `NA` or `""`.

  - A file name that ends in `.yml` or `.yaml`.

  These classes abort too:

  - `condathis_validate_env_positional_env_name`  
    `env_name` is not given, the specs are two or more unnamed
    arguments, and the last of them is one string that names an existing
    environment. Specs given with `packages =` or as one vector are
    never checked this way.

  - `condathis_parse_match_spec_invalid_name`  
    a spec that condathis cannot read, such as `"::"`.

  - `condathis_parse_match_spec_invalid_url`  
    the URL of a package file that condathis cannot read.

  Both parse errors also have class `condathis_invalid_arg`. They abort
  with `error = "continue"` too.

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

- channels:

  `NULL` (the default) or a non-empty character vector of channel names
  or URLs. With `NULL`, a spec without a channel matches a package from
  any channel. Otherwise, a spec without a channel must match a package
  from one of `channels`, compared as in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).
  A spec with a channel ignores `channels`. When a package matches a
  spec but comes from a channel that is not in `channels`, the error
  names that channel. There is no `additional_channels`: put those
  channels in `channels`. Invalid values abort with class
  `condathis_validate_env_invalid_channels`.

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
package. Otherwise, with `error = "cancel"`, it aborts with one of these
classes:

- `condathis_validate_env_env_not_found` (also
  `condathis_env_not_found`)  
  the environment does not exist.

- `condathis_validate_env_unsatisfied`  
  a spec is not satisfied or the platform differs. The message lists
  each spec that is not satisfied.

With `error = "continue"`, it returns `FALSE` with two attributes.
`reason` is one of `"env_not_found"`, `"platform_mismatch"` and
`"unsatisfied"`. `unsatisfied` is a character vector of the specs that
are not satisfied (every spec when the environment does not exist).
`validate_env()` reports a platform mismatch before unsatisfied specs.

A backend failure aborts with either value of `error`, with the class
`condathis_validate_env_failed` (also `condathis_backend_error`).

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
  error if it fails. In that case,
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  aborts with the class `condathis_backend_probe_failed`.

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
condathis::with_sandbox_dir({
  # A missing environment: FALSE, with the reason
  res <- condathis::validate_env(
    "polyglot",
    env_name = "no-such-env",
    error = "continue"
  )
  print(res)
})
#> [1] FALSE
#> attr(,"reason")
#> [1] "env_not_found"
#> attr(,"unsatisfied")
#> [1] "polyglot"

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
