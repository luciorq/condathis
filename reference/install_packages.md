# Install packages in a Conda environment

Installs packages into an existing environment, from package specs or
from an environment file given by
[`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md).
`install_packages()` creates the default environment `"condathis-env"`,
empty, when it does not exist. Any other environment that does not exist
aborts with class `condathis_install_packages_env_not_found` (also
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
  `"bioconda::samtools"`. At least one spec is required.

  Or one environment file that is solved, given by
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md),
  such as `env_definition("environment.yml")` or a list of specs,
  without package specs. Its packages are installed into the
  environment, solved with the packages it has. With micromamba, this is
  `micromamba install -f <file>`, which also uses the channels that the
  file names. Without package specs, `install_packages()` does not warn
  about the channels in `conda-meta/history`. These abort before
  anything runs, with class
  `condathis_install_packages_unsupported_definition` (also
  `condathis_invalid_arg`):

  - A lock file, such as an `@EXPLICIT` or conda-lock file. It lists
    every package of an environment: create the environment again with
    `create_env(env_definition(<file>), overwrite = TRUE)`.

  - A file that the backend cannot read, or a backend that cannot
    install from a file (also `condathis_backend_unsupported`).

  Package specs and a definition together, or two definitions, abort
  with class `condathis_install_packages_conflicting_args`. A file that
  does not exist aborts with class
  `condathis_install_packages_missing_env_file`.

  `packages = <specs>` still works. It is deprecated. It warns once per
  session (class `condathis_deprecated_packages_arg`) when the call
  comes from the console, a script or the tests of the package that
  makes it. Calls made inside other packages do not warn.
  `packages = NULL` and `packages = character(0)` install nothing and
  return status 0, as in 0.1.4.

  Invalid specs abort with these classes:

  - `condathis_install_packages_missing_packages`: no specs and no
    [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md),
    unless `packages = NULL` or `packages = character(0)` was given.

  - `condathis_install_packages_invalid_packages`: a named argument that
    `install_packages()` does not have (the error names the closest
    argument; names are never abbreviated, so `p =` aborts too), a value
    that is not a character vector, `NA` or `""`, or a file name that
    ends in `.yml`, `.yaml`, `.json` or `.lock` (pass it with
    [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md)).

  - `condathis_install_packages_positional_env_name`: `env_name` is not
    given, the specs are two or more unnamed arguments, and the last of
    them is one string that names an existing environment. Name the
    argument, as in `env_name = "my-env"`. Specs given with `packages =`
    or as one vector are never checked this way.

  - `condathis_install_packages_failed`: the backend cannot read a spec,
    such as `"::"`.

  - `condathis_parse_match_spec_invalid_name` (also
    `condathis_invalid_arg`): the same, when the `conda-meta/history` of
    the environment records channels, because condathis then reads the
    specs first.

  - `condathis_parse_match_spec_invalid_url` (also
    `condathis_invalid_arg`): the same, for the URL of a package file.

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

  A non-empty character vector of channel names or URLs, in priority
  order. For a package from another channel, either name the channel in
  the spec (`"bioconda::samtools"`) or add it here, as in
  `channels = c("conda-forge", "bioconda")`. Invalid values, such as
  `NULL`, `NA` or `""`, abort with class  
  `condathis_install_packages_invalid_channels`. condathis 0.1.4 also
  used `"bioconda"` by default. When `channels` is not given and the
  backend finds no package for a spec, the error says that the default
  changed.

  The `conda-meta/history` of the environment records the channels of
  its packages. Pass each of them in `channels` or
  `additional_channels`. A channel named in a spec counts as passed.
  When the call leaves out one of them, `install_packages()` warns with
  class  
  `condathis_install_packages_missing_previous_channels`.

- additional_channels:

  `NULL` (the default) or a non-empty character vector of channel names
  or URLs, used after `channels`. Invalid values abort with these
  classes:

  - `condathis_install_packages_invalid_channels`

  - `condathis_invalid_additional_channels`

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
[`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md),
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
  # Add `python` to the `fastqc-env` environment, for scripts that read
  # the reports of `fastqc`. Keep unrelated tools in separate
  # environments, so that their dependencies cannot conflict.
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
