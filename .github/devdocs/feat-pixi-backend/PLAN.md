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
