# Split the output of a command into lines

Splits an output stream of a
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
or
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
result into lines.

## Usage

``` r
parse_output(
  res,
  stream = c("stdout", "stderr", "both", "plain"),
  trim = FALSE
)
```

## Arguments

- res:

  A [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  or
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  result, another list with `stdout` or `stderr` elements, or a
  character vector for `stream = "plain"`. For a pipeline result,
  `"stdout"` is the output of the last command, the only one whose
  standard output is captured. `"stderr"` joins the captured standard
  error of every command, in command order. `parse_output()` cannot
  split a raw stream, from `binary = TRUE`, into lines. Use the raw
  vector itself, for example with
  [`writeBin()`](https://rdrr.io/r/base/readBin.html).

- stream:

  Character string selecting the output source: `"stdout"` (the
  default), `"stderr"`, `"both"` or `"plain"`.

  - `"stdout"` and `"stderr"` abort when that stream was not captured
    (redirected to a file or discarded, `NA` in the result).

  - `"both"` gives all of the standard output, then all of the standard
    error. The order in which the command wrote to the two streams is
    lost. `parse_output()` leaves out a stream that was not captured. It
    aborts only if neither stream was captured.

  - `"plain"` reads `res` itself, a character vector without missing
    values. `parse_output()` joins its elements with line ends.

  Other values abort with class `condathis_invalid_stream`.

- trim:

  Logical. Whether to remove whitespace at the start and end of each
  line, and blank lines at the start and end of the output. Defaults to
  `FALSE`. Values other than `TRUE` and `FALSE` abort with class
  `condathis_invalid_trim`.

## Value

A character vector with one line per element, without line ends.
`character(0)` for empty output. A `res` that cannot be read aborts with
class `condathis_parse_output_invalid_res` (also
`condathis_invalid_res`), and a raw stream with
`condathis_parse_output_binary_stream`.

## Details

Lines end at a line feed, a carriage return and line feed pair, or a
carriage return alone, so the result is the same on every operating
system. `parse_output()` removes the line ends, and a line end at the
end of the output does not start one more, empty line. It keeps the rest
of the text as the command wrote it: spaces and tabs at the start and
end of lines, and blank lines. Empty output gives `character(0)`.

`trim = TRUE` also removes whitespace at the start and end of each line,
and blank lines at the start and end of the output. This is useful for a
single value, such as a version string. It changes tab-separated output
with empty first or last fields, and indented text such as YAML.

## See also

Other commands:
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)

## Examples

``` r
# A list with the output fields of a `run()` result
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

# Whitespace is kept: the empty first field of this tab-separated line
# stays in place
parse_output("\tchr1\t100\n", stream = "plain")
#> [1] "\tchr1\t100"

# Remove it when only the text matters
parse_output("  2.9.0  \n\n", stream = "plain", trim = TRUE)
#> [1] "2.9.0"
```
