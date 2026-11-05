# Options and environment variables used by condathis

`condathis` reads a small set of R options and environment variables to
locate `micromamba`, choose a backend, and resolve its data directories.
It also builds an isolated environment for every child process it
spawns. That isolation clears or overrides many `CONDA_*` and `MAMBA_*`
variables, so values set in the calling session never reach `micromamba`
or the tools it runs.

This page leaves out fallbacks that apply only when the variables listed
here are unset, such as `HOMEDRIVE` and `HOMEPATH` on Windows.

## R options

Set these with [`base::options()`](https://rdrr.io/r/base/options.html),
for example in an `.Rprofile` file.

- `condathis.micromamba_path`:

  Character string. Path to a `micromamba` binary to use instead of the
  one managed by `condathis`. It has the highest priority in the
  `micromamba` discovery order (see *micromamba discovery*). The binary
  must report a compatible version. Otherwise, `condathis` uses the next
  candidate. Default: `NULL` (unset).

- `condathis.backend_priority`:

  Character vector. The order of the registered backends for
  `method = "auto"`. A new environment goes to the first available
  backend in this order: in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
  and when
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  or
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  create `"condathis-env"`.
  [`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md)
  and
  [`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)
  report the backends in this order. The vector sets an order, not an
  allowlist: registered backends missing from the vector come after the
  listed ones, in alphabetical order. `condathis` loads a backend
  package that it knows, such as `"rattler"` of `rattlerthis`, when the
  vector lists the backend and a new environment needs a backend. The
  vector therefore applies even when nothing else loaded the package.
  Other names that are not registered are ignored. A value that is not a
  character vector without `NA` warns once per session with class
  `condathis_invalid_backend_priority_option` and is ignored. Default:
  `"micromamba"`, so loading another backend package does not change
  where `condathis` creates new environments. An existing environment
  always uses the backend that owns it.

- `timeout`:

  Numeric. Base R download timeout in seconds. While
  [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
  downloads the binary, `condathis` uses the larger of this value and
  the `timeout` argument as the limit for each download. The limit
  applies to both `curl` and
  [`utils::download.file()`](https://rdrr.io/r/utils/download.file.html).
  `Inf`, or `0` when both values are `0`, means no limit. `condathis`
  lowers a finite limit above 2147483 seconds (about 24.8 days) to that
  value, because older `libcurl` versions reject larger values.
  `condathis` ignores a session value that is not a single, non-negative
  number. It restores the session value afterwards.

## Environment variables read by condathis

Set these in the shell, in an `.Renviron` file, or with
[`base::Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html).

- `CONDATHIS_MICROMAMBA_PATH`:

  Path to a `micromamba` binary. Same effect as the
  `condathis.micromamba_path` option, with lower priority than that
  option.

- `CONDA_PREFIX`:

  Prefix of the Conda environment active in the calling shell.
  `condathis` reads it only to look for `micromamba` inside that prefix
  during discovery. It never passes it on to child processes.

- `PATH`:

  Searched for `micromamba` as the last discovery fallback. Also the
  base `PATH` for child processes.
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  and
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  prepend the environment's binary directories to it.

- `PATHEXT`:

  Windows only. Extensions tried when a command name is resolved inside
  an environment. Default when unset: `.COM;.EXE;.BAT;.CMD`.

- `TAR`:

  A system `tar` program, as used by base R: a program name, looked up
  on `PATH`, or the path of an executable file.
  [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
  extracts the micromamba archive with R's internal `tar`, and uses this
  program only when that fails. It skips the value `internal`, an empty
  value, and a program that cannot be found or run, and uses `tar` on
  `PATH` instead. `TAR` does not support arguments.

## Environment variables that set data and cache directories

`condathis` keeps `micromamba`, its environments and its package cache
in the condathis data directory,
`tools::R_user_dir("condathis", "data")` (see
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).
Every other backend keeps its environments and caches in a directory of
its name inside it, such as `R/condathis/rattler` (see
[`backend_root_dir()`](https://luciorq.github.io/condathis/reference/backend_root_dir.md)).
These variables move those directories through the rules of
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html). Backends
have no options or environment variables of their own for them.

- `R_USER_DATA_DIR`:

  Base data directory. Takes precedence over `XDG_DATA_HOME`. The
  condathis data directory is its `R/condathis` subdirectory.

- `XDG_DATA_HOME`:

  Base data directory when `R_USER_DATA_DIR` is unset. On macOS, when
  both are unset, `condathis` uses `~/.local/share` instead of the
  platform default under `~/Library/Application Support`. The platform
  default contains a space, and `micromamba run` can fail on paths with
  spaces.

- `R_USER_CACHE_DIR`, `XDG_CACHE_HOME`:

  Base cache directory, in that order.
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  empties its `R/condathis` subdirectory.

- `HOME`, `USERPROFILE`, `APPDATA`, `LOCALAPPDATA`:

  Home and application data directories.
  [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html) uses
  them when none of the variables above is set: on Windows, `APPDATA`
  for the data directory and `LOCALAPPDATA` for the cache directory.

`condathis` creates the condathis data directory only when a call needs
it. Queries, such as
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md)
and
[`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md),
create no environment and never install `micromamba`.
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)
and
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md)
create only the data directory.

[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)
sets all the data and cache variables above to temporary directories.
Environments, packages and the `micromamba` binary that `condathis`
installs inside it, with every backend, then stay out of your own
directories.

## Environment variables for downloads

[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
downloads with
[`curl::curl_download()`](https://jeroen.r-universe.dev/curl/reference/curl_download.html)
when `curl` 5.0.0 or later is installed, and with
[`utils::download.file()`](https://rdrr.io/r/utils/download.file.html)
otherwise. Both honor the standard proxy variables, such as
`http_proxy`, `https_proxy`, and `no_proxy`.

## Environment variables set or cleared in child processes

Every process `condathis` starts, whether `micromamba` itself or a
command run by
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
or
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
starts from a copy of the calling session's environment. `condathis`
then applies the overrides below to that copy only. `condathis` never
modifies the calling R session. A process that you start yourself does
not get these overrides. Pass `--no-rc` and `--no-env` to `micromamba`
or `conda` to ignore your own Conda settings.

Cleared or reset, so that the user's own Conda or Mamba setup does not
interfere:

- `CONDARC`, `MAMBARC`:

  Set to `""`. With the micromamba backend, `condathis` also calls
  `micromamba` with `--no-env` and with `--rc-file` pointing at
  `condathis-micromamba.yaml` in the condathis data directory. So
  `micromamba` ignores the user's configuration files and `MAMBA_*`
  settings. That file pins `pkgs_dirs` to the `condathis` package cache,
  and sets `shortcuts: false`, so that micromamba adds no Start Menu
  shortcuts on Windows. One exception: micromamba extracts packages in
  subprocesses (`micromamba package extract`) that it starts without
  these options. These subprocesses still read the user's configuration
  files, such as `~/.condarc`, `~/.mambarc` and those in
  `XDG_CONFIG_HOME`. They also read the `MAMBA_*` variables that are not
  listed here.

- `CONDA_ROOT_PREFIX`, `MAMBA_ROOT_PREFIX`:

  Set to `""` for every command of an environment. `MAMBA_ROOT_PREFIX`
  is set to `""` also when the activation of the micromamba backend sets
  it, as it does on Windows. `micromamba` itself gets the condathis data
  directory as its root prefix, with `-r` and in `MAMBA_ROOT_PREFIX`.
  Without `MAMBA_ROOT_PREFIX`, micromamba (2.8.1 to 2.10.0 checked)
  refuses to start, even for `--version`, when its default root prefix
  exists but is not a Conda environment. The default root prefix is
  `$XDG_DATA_HOME/mamba`, else `~/.local/share/mamba`, on Windows else
  `mamba` in the roaming application data folder.

- `CONDA_PREFIX`, `MAMBA_PREFIX`, `CONDA_DEFAULT_ENV`,
  `MAMBA_DEFAULT_ENV`, `CONDA_PROMPT_MODIFIER`, `MAMBA_PROMPT_MODIFIER`:

  Set to `""`.

- `CONDA_SHLVL`, `MAMBA_SHLVL`:

  Set to `"0"`.

- `CONDA_PKGS_DIRS`, `MAMBA_PKGS_DIRS`:

  For `micromamba` and the commands of its environments, environments
  given by
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  included: the `pkgs/` directory of the condathis data directory.
  Packages are cached only there. The user's own `~/.mamba/pkgs` cache
  is never read or written, and
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  never cleans it. For the commands of other backends' environments: the
  directory `conda-pkgs/` next to the `envs/` directory that holds the
  environment, in the backend's data directory. A Conda tool run in such
  an environment caches its packages there, and
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  empties it. It is `""` when the environment is not in a directory
  named `envs`. An environment given by
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  that such a backend runs gets the backend's own `conda-pkgs/`, not one
  next to the environment. With `activate = TRUE`, the activation of
  such a backend can set another value (see
  [`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)).

- `MAMBA_ENVS_PATH`, `MAMBA_ENVS_DIRS`:

  Set to `""`.

- `CONDA_ENVS_DIRS`:

  Removed from the child environment.

- `CONDA_ENVS_PATH`:

  For `micromamba` and the commands of its environments, environments
  given by
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  included: the `envs/` directory of the condathis data directory. For
  the commands of other backends' environments: the parent directory of
  the environment, and for an environment given by
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
  the backend's own `envs/` directory. The value is the same with
  `activate = TRUE` and `activate = FALSE`. With activation, the backend
  can set another value.

- `R_HOME`:

  Set to `""`, so an R installed in a Conda environment does not pick up
  the R installation of the calling session.

- `TMPDIR`:

  Set to a new temporary directory for each call. `condathis` removes it
  when the call returns.

- `TMP`:

  On Windows, for every `micromamba` command: a directory in its
  `TMPDIR`. micromamba writes its temporary files there, such as the
  batch files of `micromamba run`, so they are removed with that
  directory, also when the command is stopped. The `activate.d` scripts
  see this value while the activation is recorded. A value that they
  build from it names the session's `TMP`, unless they wrote something
  in that directory: then the value names that directory, which the
  command finds in its `TMPDIR`, and the activation is recorded again
  for every command. The commands of
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  and
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  keep the session's value, unless an `activate.d` script sets one.
  `TEMP` is never changed.

- `XDG_CACHE_HOME`:

  For every `micromamba` command: the `cache/` directory of the
  condathis data directory. There micromamba keeps its repodata cache,
  instead of in `~/.cache/conda`, and the `mamba/proc` directory of
  `micromamba run`. The scripts that packages run when they are
  installed or removed see this value too. The `activate.d` scripts,
  while the activation is recorded, and the commands of
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  and
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  keep the session's value.

- `HOME` (`USERPROFILE` on Windows):

  For `micromamba env list`, `micromamba env remove` and, unless it
  needs your home directory, `micromamba create`: the `home/` directory
  of the condathis data directory. So `micromamba` does not change
  `~/.conda/environments.txt` (see Details in
  [`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).
  The scripts that packages run when they are installed or removed by
  these commands see this value too. On Windows, micromamba looks there
  for the Start Menu shortcuts of the removed packages.

- `PYTHONNOUSERSITE`, `PYTHONPATH`, `PYTHONHOME`:

  For `micromamba list`, which
  [`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md)
  runs: `PYTHONNOUSERSITE` is `"1"` and the other two are removed, so
  pip reports only the packages of the environment.

With the default `activate = TRUE` of
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
and
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
`condathis` applies activation variables on top. For the micromamba
backend, these are the variables that a real `micromamba run` activation
sets. They include the variables from `activate.d` scripts shipped by
the installed packages. These scripts run with the command's `TMPDIR`,
user cache and working directory. `condathis` records the variables once
per environment and R session. It reuses them until the environment (its
packages, its `activate.d` scripts or `env_vars.d` files) or the
session's environment variables change. It starts the command itself.
Values that name the command's `TMPDIR` are recorded again for every
command. Values that name the working directory are recorded again in
another working directory. For other backends, the backend package sets
the activation variables (see
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)).

With `activate = FALSE`,
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
applies no activation variables and only prepends the environment's
binary directories to `PATH`.
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
sets this fixed set instead:

- `CONDA_PREFIX`, `CONDA_DEFAULT_ENV`:

  The environment directory and its name. For an environment given by
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
  the name is its directory.

- `CONDA_SHLVL`, `MAMBA_SHLVL`:

  Set to `"1"`.

- `CONDA_PROMPT_MODIFIER`, `MAMBA_PROMPT_MODIFIER`:

  Set to `"(<env_name>) "`.

- `PATH`:

  The environment's binary directories, prepended to the session `PATH`.

`CONDA_ENVS_PATH` is the same as with `activate = TRUE`: it comes from
the clean variables above.

On Windows, variable names are matched case-insensitively. An override
replaces any inherited spelling of the same name, such as `Path`.

## micromamba discovery

`condathis` uses the first candidate that exists and reports a
compatible version:

1.  The `condathis.micromamba_path` option.

2.  The `CONDATHIS_MICROMAMBA_PATH` environment variable.

3.  The binary managed by `condathis`, see
    [`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md).

4.  A `micromamba` next to the running R, when R is installed in a Conda
    environment.

5.  A `micromamba` inside `CONDA_PREFIX`.

6.  A `micromamba` in the `micromamba-env` environment of the micromamba
    backend, `<condathis data directory>/envs/micromamba-env`.
    `condathis` ignores an environment of that name that another backend
    created.

7.  A `micromamba` on `PATH`.

When no candidate is compatible,
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
downloads the pinned version into the managed location.

## Interactive sessions

`condathis` shows spinners for every `verbose` level except `"silent"`,
and only when
[`rlang::is_interactive()`](https://rlang.r-lib.org/reference/is_interactive.html)
returns `TRUE`. The same holds for the download progress of
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md).
Set the `rlang_interactive` option to `FALSE` to turn them off in an
interactive session.

## See also

[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
[`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md),
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md),
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html),
[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)

## Examples

``` r
# Set options in an .Rprofile file. For example, use a specific
# micromamba binary, and create new environments with the "rattler"
# backend when the rattlerthis package is installed (micromamba stays
# the fallback):
#   options(
#     condathis.micromamba_path = "/opt/micromamba/bin/micromamba",
#     condathis.backend_priority = c("rattler", "micromamba")
#   )
# The same binary, as a line of an .Renviron file:
#   CONDATHIS_MICROMAMBA_PATH=/opt/micromamba/bin/micromamba

# Redirect all condathis data to temporary directories
condathis::with_sandbox_dir({
  print(condathis::get_install_dir()$path)
})
#> [1] "/tmp/RtmpxiirNk/condathis-sandbox-2b1e77067219/data/R/condathis"
```
