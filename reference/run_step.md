# Describe one command of a pipeline

Builds one step for
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md).
`run_step()` takes the same command, arguments and `env_name` as
[`run()`](https://luciorq.github.io/condathis/reference/run.md), but
**it does not run anything**. It only records the command, so
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
can start every step together and connect them with pipes.

## Usage

``` r
run_step(cmd, ..., env_name = NULL, method = NULL, stderr)
```

## Arguments

- cmd:

  Character string, the command to run: a single, non-empty string. Its
  arguments go in `...`.

- ...:

  Arguments of the command, unnamed, as in
  [`run()`](https://luciorq.github.io/condathis/reference/run.md). Each
  element of a character, numeric or logical vector is one argument.
  `run_step()` drops `NULL` values and writes numbers in full, never in
  scientific notation: it stores `100000` as `"100000"`. `NA`, named
  arguments, and values that are not atomic vectors (for example lists)
  abort with class `condathis_run_step_invalid_args`.

- env_name:

  Character string with the environment the command runs in, or an
  environment given by
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md).
  Defaults to `NULL`: the `env_name` of
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md).
  A name must follow the rules of the `env_name` argument of
  [`run()`](https://luciorq.github.io/condathis/reference/run.md).
  Invalid values abort with class `condathis_invalid_env_name`.

- method:

  Character string naming the backend for this step, as the `method` of
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md).
  Defaults to `NULL`: the `method` of
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md).
  Steps that share an environment must agree on it.
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  checks whether the backend is registered when it runs, before it
  starts anything.

- stderr:

  Standard error target for this step, replacing the `stderr` of
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md):
  `"|"` to capture it, `NULL` to discard it, `""` to send it to the
  standard error of the R process, `"2>&1"` to send it to the standard
  output of the step (the next command, or the `stdout` target of
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  for the last step), or a file path. When not given, the step uses the
  `stderr` of
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md).

## Value

An object of class `condathis_run_step`, for
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
which prints as the command line and its environment.
[`c()`](https://luciorq.github.io/condathis/reference/c.condathis_run_step.md)
combines steps into a list of steps of class `condathis_run_steps`,
which [`c()`](https://rdrr.io/r/base/c.html) extends again.
`c(step_1, step_2)`, `c(c(step_1, step_2), step_3)` and
`Reduce(c, steps)` all give a list for `run_pipeline(!!!steps)`.
[`c()`](https://rdrr.io/r/base/c.html) with a value that is not a step
gives a plain list, as the default
[`c()`](https://rdrr.io/r/base/c.html) does.

## Details

`run_step()` checks arguments when it builds the step, so it reports a
mistake on the line that made it. Each invalid argument aborts with
class `condathis_run_step_invalid_<argument>`, for example
`condathis_run_step_invalid_cmd`, and with the shared classes
`condathis_invalid_<argument>` and `condathis_invalid_arg`.

## See also

Other commands:
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md),
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)

## Examples

``` r
condathis::run_step(
  "pigz", "--decompress", "--stdout", "reads.fastq.gz",
  env_name = "pigz-env"
)
#> <run_step> pigz --decompress --stdout reads.fastq.gz [env: pigz-env]
condathis::run_step(
  "rg", "--count", "^@read",
  env_name = condathis::env_path("/opt/envs/ripgrep")
)
#> <run_step> rg --count ^@read [env: /opt/envs/ripgrep]

# Combine steps with `c()`, then pass them to `run_pipeline()` with `!!!`
steps <- c(
  condathis::run_step("seq", "1", "10"),
  condathis::run_step("head", "-n", "3")
)
steps
#> <run_steps> 2 steps
#> [1] <run_step> seq 1 10 [env: pipeline default]
#> [2] <run_step> head -n 3 [env: pipeline default]
```
