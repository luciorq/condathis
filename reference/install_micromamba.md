# Install micromamba binaries in the managed condathis path

Downloads and installs the `micromamba` executable used by `condathis`.

## Usage

``` r
install_micromamba(
  micromamba_version = "2.8.1-0",
  timeout_limit = 3600,
  download_method = "auto",
  force = FALSE,
  verbose = c("output", "silent", "cmd", "spinner", "full")
)
```

## Arguments

- micromamba_version:

  Character string with the micromamba version. Defaults to `"2.8.1-0"`.

- timeout_limit:

  Numeric download timeout in seconds. Defaults to `3600`.

- download_method:

  Character string passed as the download method when
  [`utils::download.file()`](https://rdrr.io/r/utils/download.file.html)
  is used. Defaults to `"auto"`.

- force:

  Logical value that controls forced reinstallation. Defaults to
  `FALSE`.

- verbose:

  Character string controlling console output. Supported values are
  `"output"`, `"silent"`, `"cmd"`, `"spinner"`, and `"full"`. Defaults
  to `"output"`.

## Value

The installed micromamba binary path (a `fs_path`/character string),
invisibly - not a `condathis_result` object like
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md),
and
[`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
return. This is intentional, not an oversight: those functions each wrap
a single `micromamba` subprocess call, so a real
status/stdout/stderr/pid is available to report. `install_micromamba()`
downloads and extracts a binary directly (no `micromamba` subprocess
involved at all), so there is no real process result to expose - the
installed path is the only meaningful thing to return, exactly like
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md)/[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)/[`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md).
On failure, this function always raises an error rather than returning a
partial or invalid path.

## Details

Download mirrors are tried in order until one succeeds. When system
`tar` and `bzip2` are available, a compressed archive may be used first.
Otherwise, or when extraction fails, a standalone binary is downloaded.

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Install the default version of Micromamba
  condathis::install_micromamba()

  # Install a specific version of Micromamba
  condathis::install_micromamba(micromamba_version = "2.0.2-2")

  # Force reinstallation of Micromamba
  condathis::install_micromamba(force = TRUE)
})
} # }
```
