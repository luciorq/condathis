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

The installed micromamba binary path, invisibly.

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
