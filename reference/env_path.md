# Refer to an environment by its path

Marks a directory as a Conda environment to run commands from. Use it
for an environment that `condathis` did not create, such as one created
by another user, or by `conda`, `mamba` or `micromamba` directly. Pass
the result as `env_name` to
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
or
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md).

## Usage

``` r
env_path(path)
```

## Arguments

- path:

  Character string with the path of the environment directory (the
  prefix), absolute or relative to the working directory. `env_path()`
  expands a leading `~`. A value that is not a single, non-empty string
  aborts with class `condathis_env_path_invalid_path` (also
  `condathis_invalid_path`).

## Value

An object of class `condathis_env_path`, holding the absolute path.

## Details

Environments given by path are read-only for `condathis`: only the
[`run()`](https://luciorq.github.io/condathis/reference/run.md) family
accepts them.
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md),
[`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md),
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md)
and
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md)
reject them with an error of class `condathis_env_path_read_only` (also
`condathis_invalid_env_name`), and
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md)
does not list them.

Commands in an environment given by path run with the environment's own
activation. They need a backend that can activate an environment given
by its directory. The micromamba backend can. With `method = "auto"`,
the first such backend in the order of the option
`condathis.backend_priority` runs it, micromamba by default. A `method`
that names a backend that cannot aborts with class
`condathis_env_path_unsupported_method` (also
`condathis_backend_unsupported`).

`env_path()` makes `path` absolute against the working directory at the
time of the call, so a later
[`setwd()`](https://rdrr.io/r/base/getwd.html) does not change which
environment it refers to. The function that gets the path checks it when
the command runs, and honors its `error` argument. The directory must
exist and contain a `conda-meta` directory. Otherwise,
`error = "cancel"` aborts with class `condathis_env_path_not_found` or
`condathis_env_path_not_conda_env` (both also
`condathis_env_not_found`).

Prefer environment names in scripts that other people run: a path is
specific to one machine.

## See also

[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)

Other environments:
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md),
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md),
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md),
[`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md)

## Examples

``` r
condathis::env_path("/opt/conda/envs/shared-tools")
#> <env_path> /opt/conda/envs/shared-tools

if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # An environment created outside condathis, here with micromamba
  # itself, in a directory of our choosing. `--no-rc` and `--no-env`
  # make micromamba ignore your own Conda settings, as condathis does.
  channel <- system.file(
    "extdata", "polyglot-channel",
    package = "condathis"
  )
  prefix <- file.path(tempdir(), "my-prefix-env")
  condathis::install_micromamba()
  processx::run(
    condathis::micromamba_bin_path(),
    c(
      "create", "-y", "--no-rc", "--no-env",
      "-r", file.path(tempdir(), "mamba-root"),
      "-p", prefix, "-c", channel, "--override-channels", "polyglot"
    )
  )

  condathis::run("polyglot", env_name = condathis::env_path(prefix))

  # `with_sandbox_dir()` does not change `tempdir()`: clean up.
  unlink(c(prefix, file.path(tempdir(), "mamba-root")), recursive = TRUE)
})
} # }
```
