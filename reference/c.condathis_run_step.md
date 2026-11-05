# Combine pipeline steps into a list of steps

[`c()`](https://rdrr.io/r/base/c.html) on classed lists splices their
fields into one list and drops the class. For steps it returns a list of
steps instead, of class `condathis_run_steps`, so
`run_pipeline(!!!c(step_1, step_2))` works. Its own
[`c()`](https://rdrr.io/r/base/c.html) method keeps it that way:
`c(c(step_1, step_2), step_3)`, `c(step_1, c(step_2, step_3))` and
`Reduce(c, steps)` give one flat list of steps. Plain lists of steps are
flattened into the result, and `NULL` values are dropped, as by
[`c()`](https://rdrr.io/r/base/c.html), so `c(step_1, if (gz) step_2)`
works.

## Usage

``` r
# S3 method for class 'condathis_run_step'
c(...)

# S3 method for class 'condathis_run_steps'
c(...)

# S3 method for class 'condathis_run_steps'
x[i]

# S3 method for class 'condathis_run_steps'
as.list(x, ...)
```

## Arguments

- ...:

  `condathis_run_step` objects, lists of them, `NULL`, or other values.

- x:

  A `condathis_run_steps` object.

- i:

  Index of the steps to keep.

## Value

A `condathis_run_steps` object (a list of `condathis_run_step` objects)
when every value is a step, a list of steps or `NULL`. Otherwise the
plain list that the default [`c()`](https://rdrr.io/r/base/c.html)
gives, with the steps as elements. `[` keeps the class, and
[`as.list()`](https://rdrr.io/r/base/list.html) removes it.

## Details

Any other value gives a plain list, as the default
[`c()`](https://rdrr.io/r/base/c.html) does, and
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
reports the values that are not steps. So
`do.call(run_pipeline, c(steps, list(verbose = "silent")))` works.

[`c()`](https://rdrr.io/r/base/c.html) dispatches on its first argument
only: `c(steps, step)` with a plain list or `NULL` as `steps` uses the
default method and splits `step` into its fields. Write
`c(steps, list(step))` there, or start from a step.
