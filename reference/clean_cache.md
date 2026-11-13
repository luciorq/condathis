# Clean the package caches of condathis

Removes the package and metadata caches of condathis and of every
registered backend, and nothing else:

- For the built-in micromamba backend, the package cache, `pkgs`, and
  the repodata cache, `cache`, in its data directory (see
  [`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).

- For every other backend, its own package and metadata caches, and
  `conda-pkgs` in its data directory. `conda-pkgs` is the package cache
  of the Conda tools that run in its environments (see *Child processes*
  in
  [`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)).

- The contents of the condathis cache directory,
  `tools::R_user_dir("condathis", "cache")`.

`clean_cache()` never deletes the per-user caches of conda, mamba and
micromamba, such as `~/.cache/conda`, which other tools share.

## Usage

``` r
clean_cache(verbose = c("output", "silent", "cmd", "spinner", "full"))
```

## Arguments

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

## Value

A `condathis_result` object, invisibly: a classed list with `status`,
`stdout`, `stderr`, `timeout`, `pid`, `cmd` and `env_name`. The values
come from the micromamba command that ran, and `cmd` is its command
line. When no micromamba command ran, `status` is `0`, `timeout` is
`FALSE` and the other fields are `NA`. `pid` is always `NA`, and so is
`env_name`: the caches are not tied to an environment.

## Details

Environments keep the files of their packages. These files usually share
disk space with the package cache through hard links. You free that
space only by also removing those environments (see
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md)
and
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)).

When the micromamba package cache does not exist, micromamba has nothing
to clean. `clean_cache()` then starts no process and does not install
micromamba. It still deletes the repodata cache and clears the condathis
cache directory.

`clean_cache()` loads a backend whose package condathis knows, such as
`"rattler"` of the `rattlerthis` package, when its data directory has
caches or environments. When that package is not installed,
`clean_cache()` does not clean its caches and warns with class
`condathis_backend_not_installed`.

`clean_cache()` waits until no other R session creates an environment or
installs packages. Those sessions wait until it is done (see *Other R
sessions* in
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)).

When a backend fails to clean its caches, `clean_cache()` still cleans
the caches of the other backends and the directories above. Then it
aborts with the first failure. That error has the classes
`condathis_clean_cache_failed` and `condathis_backend_error`, and the
error of the backend as its parent. When `clean_cache()` cannot delete a
directory itself, it aborts with class `condathis_clean_cache_failed`
the same way.

## Removing everything

`clean_cache()` keeps micromamba and the environments. To remove
everything that `condathis` installed, delete its data and cache
directories, in an R session that runs no `condathis` command at the
same time:

    unlink(condathis::get_install_dir()$path, recursive = TRUE)
    unlink(tools::R_user_dir("condathis", "cache"), recursive = TRUE)

The condathis data directory, the `path` of the `"micromamba"` row of
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
holds the micromamba binary that
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
downloaded, every environment, the package and repodata caches, the lock
files and the configuration file that `condathis` writes for micromamba.
The data directories of the other backends that use
[`backend_root_dir()`](https://luciorq.github.io/condathis/reference/backend_root_dir.md)
are inside it.
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)
also lists the data directory of a registered backend that chose its
own.

This leaves alone what `condathis` did not install: a micromamba that
`condathis` found elsewhere (see *micromamba discovery* in
[condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)),
environments that you passed as
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
the lines that micromamba added to `~/.conda/environments.txt`, the pip
cache on macOS and Windows (see
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)),
and on Windows the Start Menu shortcuts that `condathis` 0.1.4 and
earlier added (see
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)).

## See also

[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for every condition class.

Other setup:
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
[`get_sys_arch()`](https://luciorq.github.io/condathis/reference/get_sys_arch.md),
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
[`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md),
[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)

## Examples

``` r
condathis::with_sandbox_dir({
  condathis::clean_cache(verbose = "output")
})
#> ✔ Cache successfully removed.
```
