# PLAN: Python interop articles (reticulate, mirai, mizu)

## Overview

The website has two worked-example articles about Python:

- `vignettes/articles/python-and-reticulate.qmd`: Python as a command line
  tool (`run()`, `run_bin()`, `run_pipeline()`), embedded with
  `reticulate`, and one `reticulate` per environment in `mirai` daemons,
  with `mori` and Arrow for data.
- `vignettes/articles/python-and-mizu.qmd` (new, 2026-11-16): a pool of
  Python worker processes started by `mizu` from a condathis environment,
  fed with R data through shared memory.

## Decisions

### 2026-11-16: mizu gets its own article

`mizu` 0.1.0 (Charlie Gao, Posit, announced 2026-11-05) starts Python
workers (`pymizu`) directly and moves R data to them in shared memory.
It covers most of what the `mirai` section does for Python-only work,
without `reticulate` in the workers, the Arrow serializer, or the Windows
`arrow.dll` order workaround.

Options offered: replace the `mirai` section with `mizu`; keep both in one
article; or a separate `mizu` article. The user chose the separate article,
and to keep the `mirai` section in the reticulate article, with its prose
trimmed. The two articles link to each other, and both "Choosing an
Approach" tables list `mizu`.

### pymizu comes from PyPI

`pymizu` is on PyPI only (wheels for Linux, macOS and Windows, x86_64 and
arm64, CPython 3.10 to 3.15), not on conda-forge (checked 2026-11-16).
The article installs it with a `pip:` section in an environment YAML file
passed through `env_definition()`, pinned to `pymizu==0.1.1` to match the
R `mizu` 0.1.1 it was tested with.
`list_packages()` shows it with the channel `pypi`.

uv (checked 2026-11-16, micromamba 2.8.1 and 2.10.0): when `uv` is one of
the environment's Conda dependencies, micromamba installs the `pip:`
section with `uv pip install`, without any flag (the `INSTALLER` file of
the package says `uv`; `create_env()` gives the same result).

`use_uv` (`--use-uv`, `use_uv: true` in an rc file, or `MAMBA_USE_UV`) is
meant to do the same for a file without `uv`: add `uv` to the
dependencies and use it for the `pip:` section (mamba PR #3918). It only
affects the `pip:` section of an environment YAML file.
It has no effect in 2.8.1 or 2.10.0, in any of the three forms, for
`create` and `install`: the env gets pip and no `uv`.
`--print-context-only` with trace logging shows why: the `file_specs`
hook reads the YAML before the `use_uv` configurable is computed
(`file_specs` does not list `use_uv` in `.needs()`, and `use_uv` is
defined later in `configuration.cpp`, also on `main`). The upstream test
calls `detail::read_yaml_file(..., true)` directly, so it does not catch
this.
Listing (checked 2026-11-16): which tool *installed* a PyPI package does
not change `list_packages()`; which tool is a *Conda package* of the env
does. With `pip` in the env (always with the micromamba backend, whose
`add_pip_as_python_dependency` default adds it next to `python`), rows
keep the metadata name (`PyJWT`) and pip's platform (`linux-x86_64`),
for pip- and uv-installed packages alike. With `uv` and no `pip` (here
made with `micromamba remove --force pip`), rows have the normalized
name (`pyjwt`) and micromamba's platform (`linux-64`).
`micromamba list --json` (2.8.1 and 2.10.0), `list_packages(method =
"micromamba")` and the file reader (`read_env_package_records()`) agree
in all three cases. Open: whether the rattler backend adds `pip`; if
not, its envs with `uv` take the normalized branch.

condathis does not pass `--use-uv`, and should not: listing `uv` in the
dependencies is the only form that works, and it is visible in the file.
The article keeps pip: one prebuilt wheel with no dependencies gains
nothing from uv, and pip comes with conda-forge's `python` anyway.

### Workers start with the activated PATH

`mizu_py_launcher(python = <env python>)` starts the interpreter with
`system2()`, without the environment's activation: the workers inherit the
R session's environment variables (a test worker saw the R session's own
`CONDA_PREFIX`).
On Windows that broke scikit-learn: `KMeans.fit_predict()` failed with
`OSError: Windows Error 0xc06d007f` (a DLL delay-load error), because
`Library\bin` was not on `PATH`. numpy, pandas and pyarrow worked.
The article therefore defines `env_launcher(env_name)`: one `run()` call
prints `sys.executable` and the activated `PATH`, and the launcher sets that
`PATH` only while `mizu_py_launcher()` spawns the workers.
Other activation variables are not passed; the article says to
`Sys.setenv()` them.
A launcher that runs `micromamba run -n <env> python -m pymizu.child` (or
`pymizu.worker`) through `processx` gives full activation on Linux. The
article leaves it out because it is longer.

## Verification (2026-11-16)

- Linux: `quarto render`, all chunks pass (mizu 0.1.1, pymizu 0.1.1).
  Rendered again on 2026-11-18 against condathis after `e6f1232` (`run()`
  unified, `run_bin()` superseded): all chunks pass, and the registry has
  no `py-mizu` line afterwards. The "Choosing an Approach" table now names
  only `run()`.
- The `pip:` sections of its environment files no longer add the
  environments to `~/.conda/environments.txt` (see
  `../fix-env-registry/PLAN.md`).
- kappa (Windows 11, R 4.6.1): `knitr::knit()`, all chunks pass with
  `env_launcher()`. scikit-learn prints an MKL `OMP_NUM_THREADS` warning
  to the worker's stderr, which is not in the rendered output.
- omicron (macOS arm64): `knitr::knit()`, all chunks pass, with pip
  installing `pymizu` from PyPI. The LuLu firewall holds network access of
  each new env's `python` until the user accepts it; a first run, with
  nobody at the prompt, failed in pip with a name resolution error.
