# Pixi environments in condathis

## Context

The question: can condathis, with the rattler backend of rattlerthis, run
commands in an environment of a project created with the pixi CLI?

A pixi project keeps its environments in `<project>/.pixi/envs/<name>`.
Each one is an ordinary Conda prefix with a `conda-meta` directory.
condathis 0.2.0 already runs commands in such a prefix through
`env_path()`, with any backend that has `backend_resolve_run_in_dir()`.
Both the micromamba backend and the rattler backend have it.

```r
p <- condathis::env_path("path/to/project/.pixi/envs/default")
condathis::run("python", "--version", env_name = p, method = "rattler")
```

No backend is specific to pixi today.
This folder records what works now and what a pixi backend would add.

Since 2026-11-13, `create_env()` also takes an environment file through
`env_definition()` (see `../feat-env-file/PLAN.md`, and the contract in
`../feat-backend-abstraction/PLAN.md` decisions 13 to 18). The research
for it covered pixi and pixi.lock. Its findings are in "Files and pixi
(2026-11-13)" below.

## Findings (2026-11-11)

Setup:

- Linux x86_64, R 4.5.3, pixi 0.84.2.
- condathis `main` (0.2.0.9000), installed in a scratch library.
- rattlerthis 0.0.0.9002 with rattler 0.55.5 (the build of the
  2026-11-10 crate bump).
- `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME` and
  `XDG_STATE_HOME` pointed to a scratch directory.
- Environment: `rattlerthis/data-raw/logo/.pixi/envs/default` (the pixi
  project of the rattlerthis logo; conda-forge `python`, `librsvg`,
  `fonttools`, `font-ttf-dejavu`).

Results:

| Check | Result |
|---|---|
| `run("python", ...)`, `method = "rattler"` | Runs the environment's own `python`. `CONDA_PREFIX` is the pixi prefix. `CONDA_DEFAULT_ENV` is `default`. |
| `run("python", ...)`, `method = "micromamba"` | Same output as the rattler backend. |
| `run("rsvg-convert", "--version")`, rattler | Runs the environment's `rsvg-convert` 2.62.4. |
| `run_pipeline()` with two `python` steps, rattler | Works. The second step reads the output of the first. |
| `install_packages("zlib", env_name = p)` | Aborts with `condathis_env_path_read_only`, as designed. |

The run did not write to `~/.cache/conda`.

## Limits of `env_path()` for pixi environments

1. **Run only.**
   Environments given by path are read-only for condathis.
   `run()`, `run_bin()` and `run_pipeline()` accept them.
   `create_env()`, `install_packages()`, `remove_env()`, `validate_env()`,
   `env_exists()`, `list_packages()` and `get_env_dir()` reject them.
   `list_envs()` does not list them.
   pixi stays the owner of the environment.
2. **Conda activation only.**
   condathis runs the activation of the prefix: `PATH`, `CONDA_PREFIX`
   and the scripts in `etc/conda/activate.d`.
   It does not run the activation that pixi adds from the manifest:
   - the `[activation]` `env` table and `scripts` of `pixi.toml`;
   - the `PIXI_*` variables (`PIXI_PROJECT_ROOT`, `PIXI_PROJECT_NAME`,
     `PIXI_PROJECT_MANIFEST`, `PIXI_ENVIRONMENT_NAME`,
     `PIXI_ENVIRONMENT_PLATFORMS`, `PIXI_WORKSPACE_*`, `PIXI_PROMPT`,
     `PIXI_EXE`, `PIXI_IN_SHELL`), from `pixi shell-hook --shell bash`;
   - pixi tasks.
3. **Different environment name.**
   condathis sets `CONDA_DEFAULT_ENV` to the name of the directory
   (`default`), as micromamba does for a prefix.
   pixi sets it to the project name (`rattlerthis-logo` in the test
   project).
   A tool that reads `CONDA_DEFAULT_ENV` sees a different value.
4. **The environment must exist.**
   condathis does not run `pixi install`.
   It checks that the directory exists and has `conda-meta`.
   A missing or partly installed environment aborts with class
   `condathis_env_path_not_found` or `condathis_env_path_not_conda_env`.
5. **Detached environments.**
   With the pixi setting `detached-environments`, the environment is not
   in `<project>/.pixi/envs/`.
   The user must give its real location to `env_path()`.
6. **Platforms.**
   The test ran on Linux only.
   The rattlerthis tests for `env_path()` passed on omicron (macOS arm64)
   and kappa (Windows 11) on 2026-11-10, but with a plain Conda prefix,
   not one made by pixi:
   `tests/testthat/test-condathis-conformance.R:1198` and
   `tests/testthat/test-parity-childenv.R:337` in rattlerthis.

## What a pixi backend could add

Not decided. Options for later:

- **A helper that finds the prefix.**
  For example, `pixi_env_path(project = ".", environment = "default")`
  reads the manifest and the pixi settings and returns an `env_path()`
  object.
  It removes limit 5 and needs no new backend.
- **pixi activation.**
  Run the activation of the manifest (limits 2 and 3).
  Two ways: call `pixi shell-hook` (needs the pixi binary), or read
  `pixi.toml` in R or in rattlerthis (needs a TOML parser, and must follow
  pixi's rules for features and environments).
- **A full backend that delegates to pixi.**
  `create_env()` and `install_packages()` would change the manifest and
  run `pixi install`.
  This conflicts with the condathis model of environments under
  `backend_root_dir()` with names as identity, so it needs its own
  design.
- **pixi.lock in a rattler-based backend.** Added 2026-11-13. A backend
  built on the `rattler_lock` crate, such as rattlerthis, can create an
  environment from a pixi.lock without the pixi binary and without a
  manifest (see "What a pixi-style backend would take" below). The
  environment then belongs to condathis, under its own name, which fits
  the condathis model. It does not run pixi activation (limit 2).

## Files and pixi (2026-11-13)

Research for `env_definition()`, on Linux, in isolated runs (`HOME`,
the `XDG_*` variables and the package caches in a scratch directory)
with pixi 0.84.2, micromamba 2.10.0, and conda 26.9.4 with the
conda-lockfiles plugin 0.2.2. Also read: the docs of the `rattler_lock`
crate, the sources of mamba 2.10.0 and of conda-lockfiles, and the
rattlerthis sources.

### pixi never reads a foreign file directly

- `pixi init --import <file>` takes an environment YAML file only.
  `pixi import` takes `--format conda-env` or `--format pypi-txt`, and
  tries each in turn without `--format`. Both convert the file into a
  pixi manifest (`pixi.toml`). They do not install from it.
- `pixi import` of an `@EXPLICIT` file (pixi's own export) failed with
  "Tried all formats for input file, but none were successful".
- In pixi, `.txt` means pip requirements. micromamba reads a `.txt`
  file as conda package specs.
- `pixi init --import` turned the channel `nodefaults` of an
  environment YAML file into the URL
  `https://conda.anaconda.org/nodefaults/` in `pixi.toml` and
  `pixi.lock`. Not followed up.
- `pixi exec` and `pixi global install` take package specs on the
  command line only, never a file.
- `pixi install --frozen` installs `pixi.lock` without a solve. It did
  so even when the manifest had drifted (it named a package that does
  not exist), where `pixi install --locked` failed with "lock file not
  up-to-date with the workspace". But it needs a manifest: in a
  directory with only `pixi.lock`, it failed with "could not find
  pixi.toml or pyproject.toml with tool.pixi".
- pixi exports to formats that micromamba reads:
  `pixi workspace export conda-explicit-spec` (an `@EXPLICIT` file with
  a `# platform:` line and md5 hashes) and
  `pixi workspace export conda-environment` (environment YAML). It has
  no conda-lock export. micromamba 2.10.0 installed pixi's
  `@EXPLICIT` export.

### pixi.lock versions

pixi 0.84.2 writes `version: 7`: a top-level `platforms:` list, the
channels of each environment, and the packages of each platform with
URL, sha256, md5 and size. pixi moved to version 7 in 0.68.0 (May 2026).

| Reader | pixi.lock v6 | pixi.lock v7 |
|---|---|---|
| conda 26.9.4 + conda-lockfiles 0.2.2 | Yes. Format `rattler-lock-v6` (aliases `pixi`, `pixi-lock-v6`). Reads the `default` environment only. | No: "field 'version': Input should be less than or equal to 6". conda-lockfiles issue #178 and PR #143 ask for v7; their state was not checked. |
| micromamba 2.10.0 | No. The mamba sources have no pixi.lock code. | No. Named `pixi.lock`: read as a spec list, and it fetched from conda.anaconda.org despite `--override-channels`. Renamed `pixi-lock.yml`: "unknown version '7'", and an empty prefix left behind. Renamed `pixi.lock.yml`: an empty environment, exit status 0. |
| `rattler_lock` crate 0.34.x | Yes | Yes. `LockFile::from_path()`, `environment(name)`, `default_environment()`, and `Environment::conda_repodata_records(platform)`, whose records feed rattler's installer without a solve. Its docs list versions 1 to 7. Only the docs were read; nothing was run. |
| rattlerthis (`rt_read_env_file()`) | No: `pixi.lock` is read as a plain spec list (`src/rust/src/envfile/tests.rs:30`). | No |
| condathis micromamba backend | Refused, with a reason | Refused, with a reason |

The conda-lockfiles names are versioned and never change meaning
(`conda-lock-v1`, `rattler-lock-v6`). The unversioned aliases (`pixi`,
`conda-lock`) follow the newest version. `?env_definition` lists
`"rattler-lock-v6"`, `"rattler-lock-v7"` and `"pixi"` as the
conventional `format` names for pixi.lock.

### What the condathis micromamba backend does with pixi.lock

It refuses it before anything runs, under any name and any of those
format names:

- It detects a pixi.lock from the contents: a top-level `version:` and
  `environments:` (`micromamba_sniff_definition()`,
  `R/backend-micromamba-definition.R:313-317`). The format names
  `rattler-lock-v6`, `rattler-lock-v7` and `pixi` map to the same case
  (`micromamba_format_aliases`, lines 37-49).
- `backend_describe_definition()` returns `supported = FALSE` with the
  reason "micromamba does not read pixi.lock files. Use a backend that
  reads them, or export the environment to an @EXPLICIT or conda-lock
  file." (line 121). `create_env()` aborts with class
  `condathis_create_env_unsupported_definition` (also
  `condathis_backend_unsupported` and `condathis_invalid_arg`). With
  `method = "auto"`, the error lists each backend that was tried with
  its reason.
- A directory is refused too: "micromamba reads an environment file,
  not a directory." (lines 122-124).
- `create_env("pixi.lock")`, with the file name as a package spec,
  aborts with a hint to use `env_definition()` (`is_env_file_name()`,
  `R/validate_args.R:308-310`).

Tests: `test-backend-micromamba.R:1235-1247` (refused under its name and
with `format = "pixi"` or `"rattler-lock-v7"`) and
`test-backend-micromamba.R:1640-1646` (refused by `create_env()` before
anything runs), and `test-create_env.R:136`.

### What a pixi-style backend would take

The pixi findings are one reason why `env_definition()` is not tied to
one file of one extension (see `../feat-env-file/PLAN.md`):

- **A backend that calls the pixi binary** needs a workspace: a
  directory with `pixi.toml` (or `pyproject.toml`) and `pixi.lock`, and
  the name of a pixi environment. `env_definition()` allows that:
  `path` can be a directory (the existence check accepts one, and the
  micromamba backend refuses it), and named options in `...` go to the
  backend unread, as in
  `env_definition("path/to/project", environment = "test")`.
- **A backend that reads pixi.lock itself**, through `rattler_lock`,
  needs only the lock and an environment name:
  `env_definition("pixi.lock", environment = "test")`, with `"default"`
  when the option is not given. It reports the lock as `kind = "lock"`,
  with `platforms` from the lock and `records` from
  `conda_repodata_records()`, so the condathis lock rules (platform
  choice, no channel arguments, the empty-environment check) and the
  lock comparison of `validate_env()` apply. It must refuse what it
  cannot install: PyPI entries (or hand them to a pip step, as
  rattlerthis does for YAML `pip:` sections) and source packages.
- Relative paths in a v7 lock are relative to the lock file.
  `env_definition()` keeps the path absolute but does not resolve
  symbolic links, and `rattler_lock` reads with a base directory
  (`LockFile::from_reader(reader, base_dir)`).
- A backend that does not know the option `environment` must refuse it
  (contract rule, `../feat-backend-abstraction/PLAN.md` decision 15).
  The micromamba backend does: it takes only `categories`.

## Reproduce

```sh
cd path/to/pixi/project && pixi install
```

```r
library(rattlerthis)
p <- condathis::env_path("path/to/pixi/project/.pixi/envs/default")
code <- paste(
  "import os, sys;",
  "print(sys.executable, os.environ.get('CONDA_PREFIX'),",
  "os.environ.get('CONDA_DEFAULT_ENV'))"
)
for (m in c("rattler", "micromamba")) {
  r <- condathis::run("python", "-c", code, env_name = p, method = m,
    verbose = "silent")
  cat(m, ":", r$stdout)
}
```

Run it with the `XDG_*` variables pointed to a scratch directory, so that
micromamba and the package caches stay out of the home directory.
