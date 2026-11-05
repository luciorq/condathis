# Install packages in a Conda environment

Installs packages into an existing environment. `install_packages()`
creates the default environment `"condathis-env"`, empty, when it does
not exist. Any other environment that does not exist aborts with class
`condathis_install_packages_env_not_found` (also
`condathis_env_not_found`). Create it with
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
first.

## Usage

``` r
install_packages(
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = c("output", "silent", "cmd", "spinner", "full"),
  channels = "conda-forge",
  additional_channels = NULL,
  channel_priority = c("strict", "flexible", "disabled")
)
```

## Arguments

- ...:

  Package match specs (MatchSpec strings) to install, unnamed: character
  strings or character vectors, in order. Examples: `"python=3.13"`,
  `"bioconda::samtools"`. At least one spec is required. No specs abort
  with class `condathis_install_packages_missing_packages`. Any other
  value aborts with class `condathis_install_packages_invalid_packages`.
  Such values are:

  - A named argument that `install_packages()` does not have. The error
    names the closest argument.

  - A value that is not a character vector.

  - `NA` or `""`.

  - A file name that ends in `.yml` or `.yaml`.

  `packages = <specs>` still works. It is deprecated and warns once per
  session (class `condathis_deprecated_packages_arg`).
  `install_packages()` aborts with class
  `condathis_install_packages_positional_env_name` when `env_name` is
  not given and the last of two or more specs names an existing
  environment. Name the argument, as in `env_name = "my-env"`. A spec
  that the backend cannot read, such as `"::"`, aborts with class
  `condathis_install_packages_failed`. When the `conda-meta/history` of
  the environment records channels, condathis reads the specs first.
  Then such a spec aborts with class
  `condathis_parse_match_spec_invalid_name`. For the URL of a package
  file, the class is `condathis_parse_match_spec_invalid_url`. Both
  errors also have class `condathis_invalid_arg`.

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

  A non-empty character vector of channel names or URLs, in priority
  order. For a package from another channel, either name the channel in
  the spec (`"bioconda::samtools"`) or add it here, as in
  `channels = c("conda-forge", "bioconda")`. Invalid values, such as
  `NULL`, `NA` or `""`, abort with class
  `condathis_install_packages_invalid_channels`. The
  `conda-meta/history` of the environment records the channels of its
  packages. When the call leaves out one of them, `install_packages()`
  warns with class
  `condathis_install_packages_missing_previous_channels`. Add that
  channel to `channels` or `additional_channels`. A channel named in a
  spec counts as included.

- additional_channels:

  `NULL` (the default) or a non-empty character vector of channel names
  or URLs, used after `channels`. Invalid values abort with class
  `condathis_install_packages_invalid_channels` (also
  `condathis_invalid_additional_channels`).

- channel_priority:

  Channel priority mode: `"strict"` (the default), `"flexible"` or
  `"disabled"`, as in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).
  Invalid values abort with class
  `condathis_install_packages_invalid_channel_priority`.

## Value

A `condathis_result` object, invisibly: a classed list with `status`,
`stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`. `cmd` is the
command line that the backend ran, or `NA` when the backend reports
none. `stdout`, `stderr` and `pid` are `NA` when the backend reports
none, and `pid` always is with micromamba. A backend failure aborts with
class `condathis_install_packages_failed` (also
`condathis_backend_error`), with the backend's error as the parent.
micromamba runs the link scripts of packages. A backend that does not
makes `install_packages()` warn with class
`condathis_install_packages_link_scripts_skipped` (also
`condathis_link_scripts_skipped`). The warning names the packages.

## Details

`install_packages()` installs packages for the platform of the
environment, with every backend. That platform is the one the
environment was created for (see `platform` in
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)).
Otherwise, on Apple Silicon and on Windows, it is the platform of the
environment's packages that are not `noarch`. An environment with no
packages other than `noarch` ones, such as a new `"condathis-env"`, gets
the emulation fallback of
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
instead. Packages that cannot be installed for the native platform then
use an emulated platform, when they can be installed there. That
platform is `"osx-64"` on Apple Silicon when Rosetta 2 is running. On
Windows with a backend that solves for `"win-arm64"`, such as the
`win-arm64` micromamba, it is `"win-64"`. Later installs then use the
same platform.

## Other R sessions

Only one R session at a time changes an environment.
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
`install_packages()` and
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)
hold a lock on the environment name while they work, with every backend.
A call for an environment that another R session is changing waits until
that session is done. After two seconds, the call says so with a message
of class `condathis_env_lock_waiting`. `verbose = "silent"` hides this
message. Ctrl-C stops the wait.
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
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md),
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

  # Install `polyglot` into an existing, empty environment.
  condathis::create_env(env_name = "my-env")
  condathis::install_packages(
    "polyglot",
    env_name = "my-env",
    channels = channel
  )

  condathis::create_env(
    "bioconda::fastqc",
    env_name = "fastqc-env"
  )
  # Install the package `python` in the `fastqc-env` environment.
  # Keep unrelated tools in separate environments, so that their
  # dependencies cannot conflict.
  # `bioconda` is passed again, because `fastqc` came from it: leaving out
  # a channel the environment was built from warns. `conda-forge` comes
  # first: with strict channel priority, the first channel wins.
  condathis::install_packages(
    "python",
    env_name = "fastqc-env",
    channels = c("conda-forge", "bioconda")
  )
})
} # }
```
