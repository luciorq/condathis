# Parse command output text

Parses output from a
[`run()`](https://luciorq.github.io/condathis/reference/run.md) result
into trimmed text lines.

## Usage

``` r
parse_output(res, stream = c("stdout", "stderr", "both", "plain"))
```

## Arguments

- res:

  Either a process result list (with `stdout` and/or `stderr`) or a
  character vector when `stream = "plain"`.

- stream:

  Character string selecting the output source. Supported values are
  `"stdout"`, `"stderr"`, `"both"`, and `"plain"`. Defaults to
  `"stdout"`.

## Value

A character vector with one trimmed line per element.

## Examples

``` r
# Example result object from condathis::run()
res <- list(
  stdout = "line1\nline2\nline3\n",
  stderr = "error1\nerror2\n"
)

# Parse the standard output
parse_output(res, stream = "stdout")
#> [1] "line1" "line2" "line3"

# Parse the standard error
parse_output(res, stream = "stderr")
#> [1] "error1" "error2"

# Merge both
parse_output(res, stream = "both")
#> [1] "line1"  "line2"  "line3"  "error1" "error2"

# Parse plain text
plain_text <- "This is line one.\nThis is line two.\nThis is line three."
parse_output(plain_text, stream = "plain")
#> [1] "This is line one."   "This is line two."   "This is line three."
```
