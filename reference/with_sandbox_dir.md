# Execute Code in a Temporary Directory

Runs user-defined code inside a temporary directory, setting up a
temporary working environment. This function is intended for use in
examples and tests and ensures that no data is written to the user's
file space. Environment variables such as `HOME`, `APPDATA`,
`R_USER_DATA_DIR`, `XDG_DATA_HOME`, `LOCALAPPDATA`, and `USERPROFILE`
are redirected to temporary directories.

## Usage

``` r
with_sandbox_dir(code, .local_envir = base::parent.frame())
```

## Arguments

- code:

  [expression](https://rdrr.io/r/base/expression.html) An expression
  containing the user-defined code to be executed in the temporary
  environment.

- .local_envir:

  [environment](https://rdrr.io/r/base/environment.html) The environment
  to use for scoping.

## Value

Returns `NULL` invisibly.

## Details

This function is not designed for direct use by package users. It is
primarily used to create an isolated environment during examples and
tests. The temporary directories are created automatically and cleaned
up after execution.

## Examples

``` r
condathis::with_sandbox_dir(print(fs::path_home()))
#> /tmp/RtmpFsS4yt/tmp-home1d10375baeb3
condathis::with_sandbox_dir(print(tools::R_user_dir("condathis")))
#> [1] "/tmp/RtmpFsS4yt/tmp-data1d1035b3775f/R/condathis"
```
