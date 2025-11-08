# Install Micromamba Binaries in the `condathis` Controlled Path

Downloads and installs the Micromamba binaries in the path managed by
the `condathis` package. Micromamba is a lightweight implementation of
the Conda package manager and provides an efficient way to create and
manage conda environments.

## Usage

``` r
install_micromamba(
  micromamba_version = "2.3.3-0",
  timeout_limit = 3600,
  download_method = "auto",
  force = FALSE,
  verbose = c("output", "silent", "cmd", "spinner", "full")
)
```

## Arguments

- micromamba_version:

  Character string specifying the version of Micromamba to download.
  Defaults to `"2.3.3-0"`.

- timeout_limit:

  Numeric value specifying the timeout limit for downloading the
  Micromamba binaries, in seconds. Defaults to `3600` seconds (1 hour).

- download_method:

  Character string passed to the `method` argument of the
  [`utils::download.file()`](https://rdrr.io/r/utils/download.file.html)
  function used for downloading the binaries. Defaults to `"auto"`.

- force:

  Logical. If set to TRUE, the download and installation of the
  Micromamba binaries will be forced, even if they already exist in the
  system or `condathis` controlled path. Defaults to FALSE.

- verbose:

  Character string indicating the verbosity level of the function. Can
  be one of `"full"`, `"output"`, `"silent"`. Defaults to `"output"`.

## Value

Invisibly returns the path to the installed Micromamba binary.

## Details

This function checks if Micromamba is already installed in the
`condathis` controlled path. If not, it downloads the specified version
from the official GitHub releases and installs it. On Windows, it
ensures the binary is downloaded correctly by setting the download mode
to `"wb"`. If the download fails, appropriate error messages are
displayed.

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
