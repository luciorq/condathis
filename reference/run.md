# Run a command inside a Conda environment

Executes a command in a Conda environment managed by `condathis`. The
command is run through `micromamba run` using the internal Conda root.

## Usage

``` r
run(
  cmd,
  ...,
  env_name = "condathis-env",
  method = c("native", "auto"),
  verbose = c("output", "silent", "cmd", "spinner", "full"),
  error = c("cancel", "continue"),
  stdout = "|",
  stderr = "|",
  stdin = NULL
)
```

## Arguments

- cmd:

  Character string with the command to execute.

- ...:

  Additional unnamed command arguments passed to `cmd`.

- env_name:

  Character string with the target environment name. Defaults to
  `"condathis-env"`. If the default environment does not exist, it is
  created automatically.

- method:

  Character string with the backend execution strategy. Supported values
  are `"native"` and `"auto"`. Defaults to `"native"`. This argument is
  soft-deprecated and currently does not change behavior.

- verbose:

  Character string controlling console output. Supported values are
  `"output"`, `"silent"`, `"cmd"`, `"spinner"`, and `"full"`. Defaults
  to `"output"`. Logical values are accepted for backward compatibility:
  `TRUE` maps to `"output"` and `FALSE` maps to `"silent"`.

- error:

  Character string that controls error behavior. Supported values are
  `"cancel"` and `"continue"`. Defaults to `"cancel"`.

- stdout:

  Standard output target. Defaults to `"|"` (capture stdout in the
  returned object). Provide a file path to redirect stdout to a file.

- stderr:

  Standard error target. Defaults to `"|"` (capture stderr in the
  returned object). Provide a file path to redirect stderr to a file.

- stdin:

  Standard input source. Defaults to `NULL` (no stdin stream). Provide a
  file path to use file contents as stdin.

## Value

A process result list (from
[`processx::run()`](http://processx.r-lib.org/reference/run.md)) with
command output, error output, exit status, and timeout information.

## Details

This function is the main execution entry point in `condathis`. Use it
to run CLI tools with reproducible dependencies isolated in Conda
environments.

## See also

[`install_micromamba`](https://luciorq.github.io/condathis/reference/install_micromamba.md),
[`create_env`](https://luciorq.github.io/condathis/reference/create_env.md)

## Examples

``` r
if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  ## Create env
  create_env("bioconda::samtools", env_name = "samtools-env")

  ## Run a command in a specific Conda environment
  samtools_res <- run(
    "samtools", "view",
    fs::path_package("condathis", "extdata", "example.bam"),
    env_name = "samtools-env",
    verbose = "silent"
  )
  parse_output(samtools_res)[1]
  #> [1] "SOLEXA-1GA-1_6_FC20ET7:6:92:473:531\t0\tchr1\t10156..."
})
} # }
```
