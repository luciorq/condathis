# Install micromamba

Downloads the `micromamba` binary that `condathis` uses and installs it
in the condathis data directory, at the path that
[`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md)
returns. The functions that need micromamba call it when no usable
binary is found (see *micromamba discovery* in
[condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)),
for the default version. They first show a message of class
`condathis_micromamba_downloading` that names the version and the path,
unless their `verbose` is `"silent"`. You need to call it only to choose
the version, or to install micromamba ahead of time.

## Usage

``` r
install_micromamba(
  micromamba_version = "2.10.0-0",
  timeout = 3600,
  download_method = "auto",
  force = FALSE,
  verbose = c("output", "silent", "cmd", "spinner", "full"),
  timeout_limit = NULL
)
```

## Arguments

- micromamba_version:

  Character string with the micromamba version, in the format
  `"X.Y.Z-N"` (version and build number), for example `"2.10.0-0"`, the
  default. `condathis` does not use versions older than 2.8.1. Invalid
  values abort with these classes:

  - `condathis_install_micromamba_invalid_micromamba_version`: another
    format.

  - `condathis_install_micromamba_unsupported_version`: a version older
    than 2.8.1.

  With `micromamba_version`, an installed binary is kept only when its
  version (`X.Y.Z`) is the requested one. When it reports another
  version, or its version cannot be read, `install_micromamba()`
  installs the requested version. Without `micromamba_version`, it
  always keeps an installed binary, unless `force = TRUE`.

- timeout:

  Numeric download timeout in seconds, a single non-negative number.
  `Inf` means no limit. Defaults to `3600`. Each download uses the
  larger of this value and `getOption("timeout")`, so `0` means no limit
  only when `getOption("timeout")` is `0` too. The function lowers
  values above 2147483 seconds (about 24.8 days) to 2147483. Other
  values abort with class  
  `condathis_install_micromamba_invalid_timeout`.

- download_method:

  Character string with the download method of
  [`utils::download.file()`](https://rdrr.io/r/utils/download.file.html):
  one of `"auto"` (the default), `"internal"`, `"libcurl"`, `"wget"`,
  `"curl"` or `"wininet"`. It is ignored when the `curl` package 5.0.0
  or later is installed, because then
  [`curl::curl_download()`](https://jeroen.r-universe.dev/curl/reference/curl_download.html)
  is used. Other values abort with class  
  `condathis_install_micromamba_invalid_download_method`.

- force:

  Logical value. `TRUE` downloads micromamba also when a binary is
  already installed. Defaults to `FALSE`. A value that is not `TRUE` or
  `FALSE` aborts with class
  `condathis_install_micromamba_invalid_force`.

- verbose:

  Character string that controls the console output. One of `"output"`,
  `"silent"`, `"cmd"`, `"spinner"` or `"full"`. `"output"` and `"full"`
  show the progress of the download and the messages of `condathis`, for
  example that `micromamba` is already installed, that the file of a
  mirror failed the checks, or that the download succeeded. The other
  levels show none of them. Every level except `"silent"` shows the
  warning of class `condathis_install_micromamba_checksum_unavailable`
  (see Details and
  [condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)).

  `TRUE` means `"output"` and `FALSE` means `"silent"`. Invalid values
  abort with class `condathis_invalid_verbose`. The default is shown in
  Usage.

- timeout_limit:

  Deprecated. Use `timeout`. A value warns with class
  `condathis_deprecated_arg` and is used as `timeout`. Passing both
  aborts with class  
  `condathis_install_micromamba_conflicting_args`.

## Value

The path of the micromamba binary, an `fs_path`, invisibly: the path
that
[`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md)
returns. A failed download aborts with class
`condathis_install_micromamba_download_failed`.

## Details

The binary is the build for the platform of the running R (see
[`get_sys_arch()`](https://luciorq.github.io/condathis/reference/get_sys_arch.md)):
`linux-64`, `linux-aarch64`, `linux-ppc64le`, `osx-64`, `osx-arm64`,
`win-64` or `win-arm64`. A native ARM64 R on Windows gets `win-arm64`.
An x64 R on an ARM64 PC gets `win-64`, which runs through x64 emulation.
Every R of a user shares the installed binary. So on an ARM64 PC, the
binary installed first stays until you replace it, for example with
`force = TRUE`. Either binary works with both builds of R: micromamba
builds environments for its own platform.

`install_micromamba()` tries the compressed archive first, from the
micromamba releases on GitHub, then from the conda-forge channel on
anaconda.org and prefix.dev. It extracts the archive with R's internal
`tar`, so no system `tar` or `bzip2` is needed. When every archive
fails, it downloads the standalone binary from GitHub. A mirror fails
when the download fails, or when the file does not extract, does not
run, or does not match the SHA256 checksum published with the release.
Then it tries the next mirror. It replaces an installed binary only with
a download that passed these checks, also with `force = TRUE`.

The checksum is downloaded from the GitHub release when the binary is
installed. When it cannot be downloaded or read, or the SHA256 hash of
the binary cannot be computed, `install_micromamba()` still installs the
binary, so that mirrors work when GitHub cannot be reached, but warns
with class `condathis_install_micromamba_checksum_unavailable`. It warns
for every `verbose` level except `"silent"`, also when a function that
needs micromamba installs it. A checksum that does not match warns with
class `condathis_install_micromamba_checksum_mismatch`, also when
`verbose` is `"silent"`, and that binary is not installed. The hash is
computed with
[`tools::sha256sum()`](https://rdrr.io/r/tools/sha256sum.html) on R
4.5.0 or later, else with the `digest` package when it is installed,
else with the `sha256sum` or `shasum` program, or on Windows `certutil`.

## See also

Other setup:
[`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md),
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md),
[`get_sys_arch()`](https://luciorq.github.io/condathis/reference/get_sys_arch.md),
[`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md),
[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # Install the default version of micromamba
  condathis::install_micromamba()

  # Install a specific version (2.8.1 or newer): it replaces a binary of
  # another version
  condathis::install_micromamba(micromamba_version = "2.9.0-0")

  # Without `micromamba_version`, the installed binary is kept unless
  # `force = TRUE`
  condathis::install_micromamba(force = TRUE)
})
} # }
```
