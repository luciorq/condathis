# Execute code in an isolated temporary environment

Evaluates code with temporary home, data, and cache directories. This is
mainly intended for examples and tests so no user files are written.

## Usage

``` r
with_sandbox_dir(code, .local_envir = base::parent.frame())
```

## Arguments

- code:

  Expression to evaluate in the sandboxed environment.

- .local_envir:

  Environment used for local scoping and evaluation. Defaults to
  [`parent.frame()`](https://rdrr.io/r/base/sys.parent.html).

## Value

`NULL`, invisibly.

## Examples

``` r
condathis::with_sandbox_dir(print(fs::path_home()))
#> /tmp/Rtmp7nn3rS/tmp-home1a23134253aa
condathis::with_sandbox_dir(print(tools::R_user_dir("condathis")))
#> [1] "/tmp/Rtmp7nn3rS/tmp-data1a23347258ca/R/condathis"
```
