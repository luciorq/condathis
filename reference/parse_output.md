# Parse the output of a Condathis command

This function processes the result of a
[`run()`](https://luciorq.github.io/condathis/reference/run.md) call by
parsing the specified output stream (`"stdout"`, `"stderr"`, or
`"both"`) into individual, trimmed lines.

## Usage

``` r
parse_output(res, stream = c("stdout", "stderr", "both", "plain"))
```

## Arguments

- res:

  A list containing the result of
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  typically including `stdout` and `stderr` as character strings.

- stream:

  A character string specifying the data stream to parse. Must be either
  `"stdout"`, `"stderr"`, or `"both"`. Additionally, "plain" can be used
  to provide raw text as the `res` input. Defaults to `"stdout"`.

## Value

A character vector where each element is a trimmed line from the
specified stream.

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

# # Parse plain text
plain_text <- "This is line one.\nThis is line two.\nThis is line three."
parse_output(plain_text, stream = "plain")
#> [1] "This is line one."   "This is line two."   "This is line three."
```
