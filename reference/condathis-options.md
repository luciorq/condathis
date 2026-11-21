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
  must report a compatible version (2.8.1 or newer). Otherwise,
  `condathis` uses the next candidate. Default: `NULL` (unset).

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

For example, this call in an `.Rprofile` file uses a specific
`micromamba` binary, and creates new environments with the `"rattler"`
backend when the `rattlerthis` package is installed (`micromamba` stays
the fallback):

    options(
      condathis.micromamba_path = "/opt/micromamba/bin/micromamba",
      condathis.backend_priority = c("rattler", "micromamba")
    )

## Environment variables read by condathis

Set these in the shell, in an `.Renviron` file, or with
[`base::Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html).

- `CONDATHIS_MICROMAMBA_PATH`:

  Path to a `micromamba` binary. Same effect as the
  `condathis.micromamba_path` option, with lower priority than that
  option.

- `CONDA_PREFIX`:

  Prefix of the Conda environment active in the calling shell.
  `condathis` reads it to look for `micromamba` inside that prefix
  during discovery, and to remove the activation of the R session from
  child processes (see *The activation of the R session* below). It
  never passes it on to child processes.

- `PATH`:

  Searched for `micromamba` as the last discovery fallback. Also the
  base `PATH` of child processes, without the binary directories of the
  Conda and pixi environments that the R session runs in (see below).
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  and
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  put the environment's binary directories in front of it.

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

For example, this line of an `.Renviron` file names the same
`micromamba` binary as the option above:

    CONDATHIS_MICROMAMBA_PATH=/opt/micromamba/bin/micromamba

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
  platform default. That default is under
  `~/Library/Application Support`, which contains a space, and
  `micromamba run` can fail on paths with spaces.

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
[`curl::curl_download()`](https://rdrr.io/pkg/curl/man/curl_download.html)
when `curl` 5.0.0 or later is installed, and with
[`utils::download.file()`](https://rdrr.io/r/utils/download.file.html)
otherwise. Both honor the standard proxy variables, such as
`http_proxy`, `https_proxy`, and `no_proxy`.

The processes that `condathis` starts, `micromamba` included, inherit
these variables from the R session, so `micromamba` downloads packages
through the same proxy. It ignores the proxy settings of your `.condarc`
and `.mambarc` files (see `CONDARC` below).

These variables also reach every process unchanged, on purpose:

- Certificates:

  `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `PIP_CERT` and the other
  certificate variables of the tools that a process runs.

- Package indexes and credentials of pip and uv:

  Such as `PIP_INDEX_URL`, `PIP_EXTRA_INDEX_URL`, `PIP_CONFIG_FILE`
  (except for `micromamba list`, see below), `UV_INDEX_URL` and `NETRC`.
  `micromamba create` installs the `pip:` section of an environment file
  with them.

- `CONDA_OVERRIDE_*`:

  Such as `CONDA_OVERRIDE_CUDA`, `CONDA_OVERRIDE_GLIBC` and
  `CONDA_OVERRIDE_OSX`. They set the virtual packages (`__cuda`,
  `__glibc`, `__osx`) that `micromamba` solves for, also with
  `--no-env`. For example, `CONDA_OVERRIDE_CUDA = "12.4"` gets the CUDA
  builds of packages on a machine without a GPU.

## Environment variables set or cleared in child processes

Every process `condathis` starts, whether `micromamba` itself or a
command run by
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
or
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
starts from a copy of the calling session's environment, without the
activation of the R session (see *The activation of the R session*
below). `condathis` then applies the overrides below to that copy only.
`condathis` never modifies the calling R session. A process that you
start yourself does not get these overrides. Pass `--no-rc` and
`--no-env` to `micromamba` or `conda` to ignore your own Conda settings.

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

  Set to `""` for every command of an environment, also when the
  activation of the micromamba backend sets `MAMBA_ROOT_PREFIX`, as it
  does on Windows. `micromamba` itself gets the condathis data directory
  as its root prefix, with `-r` and in `MAMBA_ROOT_PREFIX`. Without
  `MAMBA_ROOT_PREFIX`, micromamba (2.8.1 to 2.10.0 checked) refuses to
  start, even for `--version`, when its default root prefix exists but
  is not a Conda environment. The default root prefix is
  `$XDG_DATA_HOME/mamba`, else `~/.local/share/mamba`, on Windows else
  `mamba` in the roaming application data folder.

- `CONDA_PREFIX`, `MAMBA_PREFIX`:

  Set to `""`.

- `CONDA_DEFAULT_ENV`, `MAMBA_DEFAULT_ENV`:

  Set to `""`.

- `CONDA_PROMPT_MODIFIER`, `MAMBA_PROMPT_MODIFIER`:

  Set to `""`.

- `CONDA_SHLVL`, `MAMBA_SHLVL`:

  Set to `"0"`. The commands of
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  and
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  get `"1"` (see below).

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

  Removed, with every other `R_*` variable (see *The startup of R*
  below), so an R installed in a Conda environment does not pick up the
  R installation of the calling session.

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
  of the condathis data directory. So `micromamba` does not rewrite
  `~/.conda/environments.txt` (see Details in
  [`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).
  The scripts that packages run when they are installed or removed by
  these commands see this value too. On Windows, micromamba looks there
  for the Start Menu shortcuts of the removed packages.

Python, pip and uv: the Python state of the R session never reaches a
process of `condathis`. So the python of an environment finds only its
own modules, and `micromamba create` installs the `pip:` section of an
environment file into the environment, never elsewhere. For every
process, `micromamba` itself and the commands of
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
and
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
with and without activation:

- `PYTHONHOME`, `PYTHONPATH`, `PYTHONUSERBASE`, `PYTHONSTARTUP`:

  Removed. To give a command a `PYTHONPATH`, set it in the command, such
  as `run("env", "PYTHONPATH=/my/modules", "python", "script.py")` on
  Linux and macOS, or add the directory to `sys.path` in the script.

- `PYTHONNOUSERSITE`:

  Set to `"1"`: the user's site directory (`~/.local/lib/python3.*`, on
  Windows a `Python` directory in `APPDATA`) is not on `sys.path`.

- `UV_PYTHON`, `UV_SYSTEM_PYTHON`, `UV_PROJECT_ENVIRONMENT`:

  Removed, so `uv` uses the python of the environment.

- `PIP_USER`, `PIP_REQUIRE_VIRTUALENV`:

  Set to `"false"`, which overrides `user` and `require-virtualenv` in a
  pip configuration file; `PIP_REQUIRE_VENV`, an alias that pip also
  reads, is removed. Otherwise pip installed into the user's site
  directory, or failed: the user's site directory is off, and a Conda
  environment is not a virtual environment. So
  `run("python", "-m", "pip", "install", ...)` installs into the
  environment.

- `PIP_TARGET`, `PIP_PREFIX`, `PIP_ROOT`:

  Removed, whatever their value. A `target`, `prefix` or `root` in a pip
  configuration file still applies (an environment variable cannot unset
  it). To install elsewhere, pass `--target` or `--prefix` to pip in the
  command.

An activated virtual environment of the session (`VIRTUAL_ENV`) is
undone as well (see *The activation of the R session* below). The
activation of the environment of a command comes after all this, so a
variable that an `activate.d` script sets reaches the command.

For `micromamba create` and `micromamba install`, which run pip, or uv
when the environment file lists it, for the `pip:` section,
`VIRTUAL_ENV` and `VIRTUAL_ENV_PROMPT` are also removed, whatever their
value.

For `micromamba list`, which
[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md)
runs, and which runs `python -m pip inspect` in the environment:
`PIP_CONFIG_FILE` is the null device (`/dev/null`, on Windows `nul`), so
pip reads no configuration file, `PIP_USER` is `"false"`, `PIP_PATH` and
`PIP_LOCAL` are removed, and the working directory is a temporary
directory, not the one of R. pip then reports only the packages of the
environment.

Every other `PIP_*` and `UV_*` variable reaches pip and uv unchanged.

*The activation of the R session.* R can run in an activated Conda or
pixi environment, or in several nested ones: R installed in a Conda
environment, R started from a shell where `conda activate` or
`pixi shell` ran, or R started through a pixi global binary. The
processes that `condathis` starts do not get that activation, within the
limits below. So a program of R's own environment does not run in place
of one that the environment of the command lacks. Before the overrides
above, `condathis` changes the copy of the session's environment this
way:

- `PATH`:

  The binary directories of these Conda prefixes are removed: the
  prefixes of `CONDA_PREFIX`, of every `CONDA_PREFIX_<n>` and
  `CONDA_ENV_SHLVL_<n>_CONDA_PREFIX`, and the prefix that R itself is
  installed in. Only a directory with a `conda-meta` directory counts as
  a prefix. Other entries stay, such as the `condabin` directory of
  `conda init` and `~/.pixi/bin`. One exception on Windows: a command
  that is a program of R's own prefix, such as
  `file.path(R.home("bin"), "Rscript.exe")`, gets the binary directories
  of that prefix back at the end of its `PATH`, because it loads its
  DLLs from there.

- `CONDA_PREFIX_<n>`, `CONDA_ENV_SHLVL_<n>_*`, `CONDA_EXE`,
  `CONDA_PYTHON_EXE`, `_CE_CONDA`, `_CE_M`, `MAMBA_EXE`:

  Removed. These variables record the activation of the session.

- `PIXI_PROJECT_*`, `PIXI_WORKSPACE_*`, `PIXI_ENVIRONMENT_*`,
  `PIXI_PROMPT`, `PIXI_IN_SHELL`, `PIXI_EXE`:

  Removed. Other `PIXI_*` variables, such as `PIXI_HOME`, stay.

- `CONDA_BACKUP_<X>`, `<X>_CONDA_BACKUP`, `CONDA_ENV_SHLVL_<n>_<X>`:

  The value of `<X>` before the activation, saved by the activation
  scripts of compiler and other packages, or by pixi. `<X>` gets that
  value back, as the deactivation scripts do: an empty backup of the
  first two forms removes `<X>`. The backups are removed.

- Variables of `conda-meta/state` and `etc/conda/env_vars.d`:

  A variable that these files of the prefixes above set is removed when
  the session has exactly that value.

- Variables of a pixi global binary:

  When one of the prefixes above is an environment of `pixi global`, a
  variable that its binaries set when they start is removed when the
  session has exactly that value. pixi records them in
  `bin/trampoline_configuration` of its home. R started through such a
  binary gets the whole activation of its environment, such as the
  compiler variables `CC`, `CFLAGS` and `CONDA_BUILD_SYSROOT`, and a
  compiler of the environment of a command would see them.

- `VIRTUAL_ENV`, `VIRTUAL_ENV_PROMPT`:

  When `VIRTUAL_ENV` names a Python virtual environment (a directory
  with `pyvenv.cfg`), both are removed, and its `bin` directory (on
  Windows `Scripts`) leaves `PATH`. Activating a virtual environment
  sets them, and so does reticulate inside the R session when it uses
  one, also through
  [`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html).

- What reticulate changed for its python:

  When reticulate has started Python in the R session, the `lib`
  directories that it put in front of `LD_LIBRARY_PATH` on Linux (of its
  python and of the python a virtual environment was made from) are
  removed. For a python of a Conda environment, reticulate puts the
  binary directories of that environment in front of `PATH`; they are
  removed as those of the prefixes above.

Some changes cannot be undone. A value that an `activate.d` script of
the session's environment set stays, unless it saved a backup above or a
pixi global binary recorded it, and so does a `PATH` entry such a script
added. For example, R installed in a Conda environment that has the
compiler packages, and started from a shell where that environment was
activated, passes `CC`, `CFLAGS`, `CONDA_BUILD_SYSROOT` and the other
compiler variables of that environment to the processes it starts. The
binary directory of an environment that no variable names any more stays
too, such as the one of a pixi global binary that started the shell
before another one replaced its `CONDA_PREFIX`. reticulate moves the
directory of a python that is neither in a virtual nor in a Conda
environment, such as `/usr/bin`, to the front of `PATH`; it stays there.
On macOS, when `/usr/local/opt/openblas` exists, loading reticulate sets
`OPENBLAS` and, when it is unset, `OMP_NUM_THREADS=1`; they stay too.

*The startup of R.* R also changes its own environment when it starts,
and the processes that `condathis` starts do not get those changes
either. So an R of the environment of the command never loads packages
built for the R of the session, and a program of the environment never
loads R's libraries or certificates:

- `R_*`, `_R_*`:

  Removed, also a variable the user set, such as `R_LIBS_USER` or
  `R_PROFILE_USER`: only R reads them, and an R that the command starts
  sets its own. The R of the session keeps them.

- `EDITOR`, `PAGER`, `MAKE`, `SED`, `TAR`, `LN_S`, `CURL_CA_BUNDLE`,
  `MSYS2_ENV_CONV_EXCL`:

  Removed when the session has exactly the value that R's startup gives
  them (`etc/Renviron` of R). A value the user set stays, such as
  `EDITOR=nvim`.

- `LD_LIBRARY_PATH`, `DYLD_FALLBACK_LIBRARY_PATH`, `DYLD_LIBRARY_PATH`:

  The directories that R put in front (`etc/ldpaths` of R) are removed.
  The directories after them stay.

- `PATH` on Windows:

  The Rtools directories that R put in front (`R_RTOOLS45_PATH`) are
  removed. A command finds Rtools only when the `PATH` that R started
  with has it.

`condathis` learns the values of R's startup by starting R's own
`Rscript` once per R session, without the user's `.Renviron` and
`.Rprofile`. When that fails, only the `R_*` variables and the Rtools
directories are removed.

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
When the `PATH` of an activation names none of the environment's binary
directories, `condathis` puts them in front of it.

In both modes and for every backend, a command of
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
and
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
runs in exactly one activated environment, whatever the R session runs
in: `CONDA_SHLVL` and `MAMBA_SHLVL` are `"1"`, and
`CONDA_PROMPT_MODIFIER` and `MAMBA_PROMPT_MODIFIER` are `""`, whatever
the activation set.

With `activate = FALSE`,
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
and
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
set this fixed set instead, without any backend code and without the
`activate.d` scripts and `env_vars.d` files of the packages:

- `CONDA_PREFIX`, `CONDA_DEFAULT_ENV`:

  The environment directory and its name. For an environment given by
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
  the name is its directory.

- `CONDA_SHLVL`, `MAMBA_SHLVL`:

  Set to `"1"`.

- `CONDA_PROMPT_MODIFIER`, `MAMBA_PROMPT_MODIFIER`:

  Set to `""`.

- `PATH`:

  The environment's binary directories, in front of the `PATH` described
  above.

`TMPDIR` and `CONDA_ENVS_PATH` are the same as with `activate = TRUE`:
they come from the clean variables above.

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
    backend, in the `envs` directory of the condathis data directory.
    `condathis` ignores an environment of that name that another backend
    created.

7.  A `micromamba` on `PATH`.

A candidate that is a binary exposed by `pixi global` (a trampoline,
with a `trampoline_configuration/<name>.json` file next to it) is
replaced by the binary that it starts, the `exe` of that file, so the
activation of the pixi environment that the trampoline sets never
reaches `micromamba`. The option and the variable keep the value you
set.

A compatible version is 2.8.1 or newer. When no candidate is compatible,
the first function that needs `micromamba` calls
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
which downloads the default version into the managed location. That
function says so first, unless its `verbose` is `"silent"`, with a
message of class `condathis_micromamba_downloading`. Queries, such as
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
never download it.

## Interactive sessions

In interactive sessions, `condathis` shows spinners for every `verbose`
level except `"silent"`. A session is interactive when
[`rlang::is_interactive()`](https://rlang.r-lib.org/reference/is_interactive.html)
returns `TRUE`.
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
shows the progress of its download only in interactive sessions, and
only when its `verbose` is `"output"` or `"full"`. When another function
installs micromamba because no usable binary was found, the progress
shows only with `verbose = "full"`. Set the `rlang_interactive` option
to `FALSE` to turn spinners and progress off in an interactive session.

## See also

[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
[`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md),
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md),
[`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html),
[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)

## Examples

``` r
# Redirect all condathis data to temporary directories
condathis::with_sandbox_dir({
  print(condathis::get_install_dir()$path)
})
#> [1] "/tmp/Rtmpzrm4bi/condathis-sandbox-2add34a53058/data/R/condathis"
```
