# Run code with temporary home and data directories

Evaluates code with temporary home, data, cache, configuration and state
directories. It is meant for examples and tests. `condathis` puts the
environments, packages and micromamba binary that it installs into the
sandbox, with every backend, not into your own directories. No Conda
configuration file of yours is in reach.

## Usage

``` r
with_sandbox_dir(code, .local_envir = base::parent.frame())
```

## Arguments

- code:

  Expression to evaluate with the temporary directories.

- .local_envir:

  Environment `code` is evaluated in. Defaults to
  [`parent.frame()`](https://rdrr.io/r/base/sys.parent.html).

## Value

The value of `code`, visible or invisible as in `code`.

## Details

Processes that `condathis` starts ignore the session's Conda settings.
Code that starts micromamba or conda itself must pass `--no-rc` and
`--no-env` to do the same.

The sandbox lasts exactly as long as the call. Before
`with_sandbox_dir()` returns, also after an error in `code`, it does
these steps in this order:

- It restores the working directory.

- It restores every environment variable, including ones that `code`
  set, changed or removed itself.

- It stops the processes that use the sandbox, and their children, if
  they are still running. These are the processes that `condathis`
  starts for `code`. A process counts when its executable or one of its
  arguments is a path inside the sandbox. It also counts when it runs
  with a `condathis` environment or package cache inside the sandbox.
  Other processes started inside `code` keep running, for example the
  `processx` supervisor, `callr` sessions and `mirai` daemons.

- It waits until every backend has finished its work in the R session.

- It deletes the sandbox directories, with every environment, package
  and micromamba binary installed into them. When it cannot delete them,
  `with_sandbox_dir()` warns with class
  `condathis_with_sandbox_dir_cleanup_failed`. An interrupt during this
  cleanup leaves them in the session's temporary directory.

`with_sandbox_dir()` does not reset options and objects that `code`
assigns: `code` runs in `.local_envir`, as with
[`withr::with_envvar()`](https://withr.r-lib.org/reference/with_envvar.html).
It does not change [`tempdir()`](https://rdrr.io/r/base/tempfile.html)
or `TMPDIR` either, so files that `code` writes there stay.

## See also

Other setup:
[`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md),
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
[`get_sys_arch()`](https://luciorq.github.io/condathis/reference/get_sys_arch.md),
[`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
[`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md)

## Examples

``` r
condathis::with_sandbox_dir(print(fs::path_home()))
#> /tmp/Rtmpu60vo2/condathis-sandbox-2b121c577899/home
condathis::with_sandbox_dir(print(tools::R_user_dir("condathis")))
#> [1] "/tmp/Rtmpu60vo2/condathis-sandbox-2b127290eced/data/R/condathis"
```
