# Create a Conda environment

Creates a Conda environment from package specs or from an environment
file. With `overwrite = FALSE` (the default), `create_env()` never
replaces an existing environment. It keeps the environment when it
already has the requested packages. Otherwise, it aborts (see *Existing
environments*).

## Usage

``` r
create_env(
  ...,
  env_name = "condathis-env",
  method = "auto",
  verbose = c("output", "silent", "cmd", "spinner", "full"),
  channels = "conda-forge",
  additional_channels = NULL,
  channel_priority = c("strict", "flexible", "disabled"),
  platform = NULL,
  env_file = NULL,
  overwrite = FALSE
)
```

## Arguments

- ...:

  Package match specs (MatchSpec strings), unnamed: character strings or
  character vectors, in order. Examples: `"python=3.13"`,
  `"bioconda::fastqc==0.12.1"`. With no specs, `create_env()` creates an
  empty environment. Any other value aborts with class
  `condathis_create_env_invalid_packages`. Such values are:

  - A named argument that `create_env()` does not have. Names are never
    abbreviated: `env =` and `pack =` abort too. The error names the
    closest argument.

  - A value that is not a character vector.

  - `NA` or `""`.

  - A file name that ends in `.yml` or `.yaml`. Pass it as `env_file`.

  `packages = <specs>` still works, and `packages = NULL` creates an
  empty environment. It is deprecated. It warns once per session (class
  `condathis_deprecated_packages_arg`) when the call comes from the
  console, a script or the tests of the package that makes it. Calls
  made inside other packages do not warn.

  `create_env()` aborts with class
  `condathis_create_env_positional_env_name` when `env_name` is not
  given, the specs are two or more unnamed arguments, and the last of
  them is one string that names an existing environment. Name the
  argument, as in `env_name = "my-env"`. Specs given with `packages =`
  or as one vector are never checked this way.

- env_name:

  Character string with the environment name. It must be a plain
  directory name that is valid on Linux, macOS and Windows:

  - Not empty, and not `.` or `..`.

  - Not starting with `-`, and not ending with `.`.

  - Without path separators, `:`, `#`, whitespace, control characters or
    `<>"|?*`.

  - Not a Windows device name, such as `NUL` or `COM1` (see *Environment
    names* in `create_env()`).

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
  `condathis_create_env_invalid_channels`. condathis 0.1.4 also used
  `"bioconda"` by default. When `channels` is not given and the backend
  finds no package for a spec, the error says that the default changed.

- additional_channels:

  `NULL` (the default) or a non-empty character vector of channel names
  or URLs, used after `channels`. Invalid values abort with these
  classes:

  - `condathis_create_env_invalid_channels`

  - `condathis_invalid_additional_channels`

- channel_priority:

  Channel priority mode: `"strict"` (the default), `"flexible"` or
  `"disabled"`. With `"strict"`, when several channels have a package,
  the solver uses only the builds from the first of them. This keeps the
  solution reproducible. The mamba documentation recommends this
  setting. Invalid values abort with class
  `condathis_create_env_invalid_channel_priority`.

- platform:

  `NULL` (the default) or the platform for the solver: a known conda
  platform (subdir) name in lower case, such as `"linux-64"`,
  `"linux-aarch64"`, `"osx-64"`, `"osx-arm64"`, `"win-64"`,
  `"win-arm64"` or `"emscripten-wasm32"`. Other values abort with class
  `condathis_create_env_invalid_platform` before anything runs. The
  message suggests a close name, such as `"linux-aarch64"` for
  `"linux-arm64"`. When the channels have no packages for a known
  platform, the backend fails. Then `create_env()` aborts with class
  `condathis_create_env_failed`. With `NULL`, condathis can fall back to
  an emulated platform. This happens when the package specs or the
  `env_file` cannot be installed for the native platform, dependencies
  included, but can for the emulated one. This works with every backend
  that can tell whether a request solves for a platform, micromamba
  included. On Apple Silicon, condathis uses `"osx-64"` when Rosetta 2
  is available. With a backend that solves for `"win-arm64"`, condathis
  uses `"win-64"` through x64 emulation. The `win-arm64` micromamba,
  which a native ARM64 R on Windows installs, is such a backend.
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  later installs packages for the platform that the environment was
  created for, given or emulated. For an existing environment, see
  *Existing environments*.

- env_file:

  `NULL` (the default) or the path of an environment YAML file. With the
  micromamba backend, condathis passes it to `micromamba create -f`. No
  backend applies the `variables:` of a YAML file: the commands that run
  in the environment do not get them. Do not use both package specs and
  `env_file`: that aborts with class
  `condathis_create_env_conflicting_args`. A file that does not exist
  aborts with class `condathis_create_env_missing_env_file`.

- overwrite:

  `TRUE` or `FALSE` (the default). With `FALSE`, `create_env()` never
  replaces an existing environment. `create_env()` keeps the environment
  and runs nothing when it has every requested package (see *Existing
  environments*) or when no package is requested. It returns status 0.
  Otherwise, and always when `env_file` is set, `create_env()` aborts
  with class `condathis_create_env_exists`. Use
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  to add packages to an existing environment. Use
  [`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md)
  to check one. With `TRUE`, `create_env()` creates the environment
  again from scratch, also when it exists or was built for another
  `platform`. When `create_env()` fails to create the new environment (a
  misspelled package, a download error), it keeps the existing one as it
  was. When it cannot move the existing one aside first (on Windows,
  while a program uses one of its files), it aborts with class
  `condathis_create_env_failed` and changes nothing. Invalid values
  abort with class `condathis_create_env_invalid_overwrite`.

## Value

A `condathis_result` object, invisibly: a classed list with `status`,
`stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`. `cmd` is the
command line that the backend ran, or `NA` when the backend reports
none. `cmd`, `stdout` and `stderr` are `NA` when nothing ran (an
existing environment that already has the requested packages). `stdout`,
`stderr` and `pid` are `NA` when the backend reports none, and `pid`
always is with micromamba. A backend failure aborts with class
`condathis_create_env_failed` (also `condathis_backend_error`), with the
backend's error as the parent. micromamba runs the link scripts of
packages (`pre-link` and `post-link`). A backend that does not, such as
`"rattler"` of the `rattlerthis` package, makes `create_env()` warn. The
warning names the packages, which may not work. Its classes are
`condathis_link_scripts_skipped` and  
`condathis_create_env_link_scripts_skipped`.

## Details

With the micromamba backend, `create_env()` adds the new environment to
`~/.conda/environments.txt`, the registry that conda and mamba share. It
does so only when micromamba needs your home directory, for example for
channel credentials you saved there (see Details in
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).

## Existing environments

With `overwrite = FALSE`, `create_env()` compares an existing
environment with the request.
[`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md)
makes the same comparison.

An installed package satisfies a spec when it matches the name, version,
build string and channel of the spec. The name match ignores case:
`"PyYAML"` matches `pyyaml`. A spec without a channel must match a
package from `channels` or `additional_channels`. The channel comparison
ignores credentials and platform subdirectories, and compares a local
channel by its absolute path. `"defaults"` matches the `pkgs/main` and
`pkgs/r` packages it installs. The comparison uses only these bracket
constraints: `version`, `build`, `build_number` and `channel`. `>=1.2.*`
is read as `>=1.2`, as micromamba does. A build string matches with `*`
as its only wildcard.

A package from another channel does not satisfy a spec without a
channel. An environment built with condathis 0.1.4, which also used
`"bioconda"` by default, can have such packages. The error then names
the channel of the package. Add that channel to `channels`, or name it
in the spec, as in `"bioconda::samtools"`.

Specs for virtual packages, whose names start with `__`, such as
`"__cuda=12"`, `"__unix"` or `"__glibc>=2.17"`, are not compared. They
describe the host, not the environment, and are never installed. The
solver checked them when it created the environment. `create_env()` and
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
still pass them to the backend.

A spec that condathis cannot compare, or that micromamba, rattler and
conda read differently, never counts as satisfied. `create_env()` then
aborts for it with class `condathis_create_env_exists`. These are specs
with:

- Another bracket constraint, such as `"zlib[md5=...]"`, or a group in
  parentheses at the end, such as `"zlib (>=1.2,<2)"` (read as bracket
  constraints).

- A version with `*` after `>`, `<`, `<=` or `~=` (`"zlib<2.*"`).

- A version with `*` in its middle (`"zlib=1.*.3"`, `"zlib=1.3.*.*"`),
  in `!=1.2*` or in `=1.2*`.

- A version with `*` after `>=`, other than a single `.*` at the end
  (`"zlib>=1.2*"`).

- `~=` with a one-part version (`"zlib~=1"`), an operator with no
  version (`"zlib>=*"`), a missing operand (`"zlib>=1.2,"`), a
  `build_number` with `==` (`"zlib[build_number='==0']"`), or a version
  that micromamba rejects (`"zlib>==1.2"`).

- A build string with a character other than a letter, a digit, `_`, `.`
  and `*`, such as a regular expression (`"zlib=1.3.1=^h4.*$"`) or `?`.

A spec that condathis cannot read aborts with one of these classes, and
also with class `condathis_invalid_arg`:

- `condathis_parse_match_spec_invalid_name`: a spec such as `"::"`.

- `condathis_parse_match_spec_invalid_url`: the URL of a package file
  whose name is not `<name>-<version>-<build>`.

For a new environment, only the backend reads the specs. A spec it
cannot read aborts with class `condathis_create_env_failed`.

When `platform` is given, the platform of the installed packages must be
`platform` (`noarch` packages match any platform). A different platform
aborts with class `condathis_create_env_platform_mismatch`, and
`create_env()` keeps the environment. With `platform = NULL`, the
platform is not compared.

## Other R sessions

Only one R session at a time changes an environment. `create_env()`,
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
and
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

## Environment names

An `env_name` cannot be a Windows device name, on any OS. These names
are `CON`, `PRN`, `AUX`, `NUL`, `CONIN$`, `CONOUT$`, `COM1` to `COM9`
and `LPT1` to `LPT9`, and `COM` or `LPT` followed by a superscript one,
two or three. The match ignores letter case and also applies with an
extension, such as `nul.txt`.

## See also

[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for every condition class, and
[condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)
for the options that choose the backend.

Other environments:
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
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

  # Create a Conda environment from that channel, without network access
  # once micromamba is installed.
  condathis::create_env(
    "polyglot",
    env_name = "polyglot-env",
    channels = channel
  )

  # A second call keeps the environment: it already has `polyglot`.
  condathis::create_env(
    "polyglot",
    env_name = "polyglot-env",
    channels = channel
  )

  # Create an empty environment.
  condathis::create_env(env_name = "empty-env")

  # Create a Conda environment and install the CLI `fastqc` in it.
  # Explicitly using the channel `bioconda` and version `0.12.1`.
  condathis::create_env(
    "bioconda::fastqc==0.12.1",
    env_name = "fastqc-env",
    verbose = "output"
  )
})
} # }
```
