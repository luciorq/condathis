# Parallel Python Workers with condathis and mizu

## Python Workers Next to Your R Session

[`run()`](https://luciorq.github.io/condathis/reference/run.md) starts a
fresh `python` for every call, and data moves through files and standard
streams. `reticulate` embeds one interpreter in the R process. The
[`mizu`](https://shikokuchuo.net/mizu/) package sits between the two:

- It starts a pool of Python processes once, and they stay alive between
  tasks.
- R vectors, matrices and data frames reach the workers through shared
  memory. Large objects are not copied.
- Tasks run in the background. The R session stays free until you
  collect the results.
- A crash in a worker does not end your R session.

`condathis` provides the interpreter and the packages of the workers.
This article needs the `mizu` R package, and the `pymizu` Python package
in the environment. The `mizu` API is still marked experimental.

## Creating the Environment

`pymizu` is published on PyPI, not on `conda-forge`. An environment YAML
file installs it with `pip`, after `micromamba` installs the Conda
packages.
[`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md)
passes the file to
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).

``` r

env_file <- fs::file_temp(pattern = "py-mizu-", ext = "yml")

writeLines(
  con = env_file,
  text = c(
    "channels:",
    "  - conda-forge",
    "dependencies:",
    "  - python=3.13",
    "  - numpy",
    "  - pandas",
    "  - pyarrow",
    "  - pip",
    "  - pip:",
    "      - pymizu==0.1.1"
  )
)

create_env(
  env_definition(env_file),
  env_name = "py-mizu-env",
  verbose = "silent"
)
```

[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md)
lists the `pip` package with the channel `pypi`.

``` r

pkgs <- list_packages(env_name = "py-mizu-env", verbose = "silent")
pkgs[pkgs$name %in% c("python", "numpy", "pymizu"), c("name", "version", "channel")]
#> # A tibble: 3 × 3
#>   name   version channel    
#>   <chr>  <chr>   <chr>      
#> 1 numpy  2.5.5   conda-forge
#> 2 pymizu 0.1.1   pypi       
#> 3 python 3.13.18 conda-forge
```

## Starting a Pool

[`mizu_py_launcher()`](https://shikokuchuo.net/mizu/reference/mizu_py_launcher.html)
starts the workers with a given Python interpreter. It checks that
`pymizu` imports in that interpreter, so a missing package fails here
and not later in a task.

The launcher starts `python` directly, without the environment’s
activation. On Windows, compiled packages then fail to find their DLLs
in the environment’s `Library\bin` folder. `env_launcher()` below asks
the activated environment for the interpreter path and for `PATH`, and
sets that `PATH` only while the workers start.

``` r

library(mizu)

env_launcher <- function(env_name) {
  info <- parse_output(
    run(
      "python", "-c",
      "import os, sys; print(sys.executable); print(os.environ['PATH'])",
      env_name = env_name,
      verbose = "silent"
    )
  )
  launch <- mizu_py_launcher(python = info[[1]])

  function(token, slot) {
    old_path <- Sys.getenv("PATH")
    on.exit(Sys.setenv(PATH = old_path))
    Sys.setenv(PATH = info[[2]])
    if (missing(slot)) launch(token) else launch(token, slot)
  }
}
```

[`mizu_pool()`](https://shikokuchuo.net/mizu/reference/mizu_pool.html)
starts two workers.

``` r

pool <- mizu_pool(n_workers = 2L, launcher = env_launcher("py-mizu-env"))
```

The workers get the activated `PATH`, but no other activation variables.
If a package needs a variable from an `activate.d` script, set it with
[`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html) before you
start the pool.

## Calling Python Functions

[`mizu_call()`](https://shikokuchuo.net/mizu/reference/mizu_call.html)
names a Python function and its arguments.
[`mizu_submit_call()`](https://shikokuchuo.net/mizu/reference/mizu_call.html)
sends it to the pool and returns at once.
[`mizu_collect()`](https://shikokuchuo.net/mizu/reference/mizu_submit.html)
waits for the result.

``` r

task <- mizu_submit_call(
  pool,
  mizu_call("numpy.quantile", faithful$eruptions, q = c(0.25, 0.5, 0.75))
)

mizu_collect(task)
#> [1] 2.16275 4.00000 4.45425
```

An R numeric vector arrives as a NumPy array. `NA` arrives as a missing
value and comes back as `NA`.

## Running Python Code

With `.source`, the task is a piece of Python code. The named arguments
become Python variables, and the value of the last line is the result.

A data frame arrives as a `pymizu.Frame`. `pyarrow.table()` reads it
without a copy, and `to_pandas()` converts it to a `pandas` data frame.
A `pandas` data frame comes back as an R data frame.

``` r

summarize_py <- "
import pyarrow as pa
df = pa.table(cars).to_pandas()
df.groupby('cyl')[['mpg', 'hp']].mean().reset_index()
"

task <- mizu_submit_call(
  pool,
  mizu_call(.source = summarize_py, cars = mtcars)
)

mizu_collect(task)
#>   cyl      mpg        hp
#> 1   4 26.66364  82.63636
#> 2   6 19.74286 122.28571
#> 3   8 15.10000 209.21429
```

Factor columns cross as factors, in both directions. Some R types cannot
cross, such as functions, formulas and S4 objects. `mizu` raises an
error when you send one.

## Working in the Background

Each submission returns before the task finishes. Submit several tasks,
continue in R, and collect them all when you need the results. The two
workers run the tasks in parallel.

``` r

slow_py <- "
import os, time
time.sleep(1)
os.getpid()
"

tasks <- lapply(1:4, function(i) {
  mizu_submit_call(pool, mizu_call(.source = slow_py))
})

# The R session is free while the workers sleep
invisible(sum(seq_len(1e6)))

system.time({
  pids <- mizu_collect_all(tasks)
})
#>    user  system elapsed 
#>     0.0     0.0     1.9
table(unlist(pids))
#> 
#> 13581 13583 
#>     2     2
```

Four one-second tasks take about two seconds on two workers. Each worker
process ran two of them.

[`mizu_map()`](https://shikokuchuo.net/mizu/reference/mizu_map.html)
applies one Python function to every element of a vector, and splits the
work across the pool.

``` r

log_waiting <- mizu_map(
  pool,
  faithful$waiting[1:6],
  mizu_call("numpy.log"),
  .template = numeric(1)
)

mizu_collect(log_waiting)
#> [1] 4.369448 3.988984 4.304065 4.127134 4.442651 4.007333
```

## Large Data in Shared Memory

`mizu` writes a large object to shared memory once, without serializing
it. The worker reads the values in place. Ten million doubles, 80 MB,
reach Python in a fraction of a second.

``` r

x <- stats::rnorm(1e7)

system.time({
  py_sd <- mizu_collect(mizu_submit_call(pool, mizu_call("numpy.std", x)))
})
#>    user  system elapsed 
#>   0.010   0.007   0.030

all.equal(py_sd, stats::sd(x), tolerance = 1e-6)
#> [1] TRUE
```

NumPy’s `std()` divides by `n` and R’s
[`sd()`](https://rdrr.io/r/stats/sd.html) by `n - 1`. With ten million
values, the difference is below the tolerance.

## Handling Python Errors

A Python exception in a task becomes an R error of class
`mizu_error_remote` when you collect the task. The message holds the
Python exception. The worker keeps running and accepts more tasks.

``` r

task <- mizu_submit_call(pool, mizu_call(.source = "import not_installed_module"))

tryCatch(mizu_collect(task), mizu_error_remote = conditionMessage)
#> [1] "ModuleNotFoundError: No module named 'not_installed_module'"
```

## Pools from Several Environments

Each pool uses the interpreter of one environment. Pools from different
environments can run at the same time, with different Python versions
and package sets. This environment has Python 3.12 and `scikit-learn`.

``` r

ml_env_file <- fs::file_temp(pattern = "py-mizu-ml-", ext = "yml")

writeLines(
  con = ml_env_file,
  text = c(
    "channels:",
    "  - conda-forge",
    "dependencies:",
    "  - python=3.12",
    "  - scikit-learn",
    "  - pandas",
    "  - pyarrow",
    "  - pip",
    "  - pip:",
    "      - pymizu==0.1.1"
  )
)

create_env(
  env_definition(ml_env_file),
  env_name = "py-mizu-ml-env",
  verbose = "silent"
)

ml_pool <- mizu_pool(n_workers = 1L, launcher = env_launcher("py-mizu-ml-env"))
```

Ask both pools for their Python version.

``` r

version_py <- "
import platform
platform.python_version()
"

c(
  data = mizu_collect(mizu_submit_call(pool, mizu_call(.source = version_py))),
  ml = mizu_collect(mizu_submit_call(ml_pool, mizu_call(.source = version_py)))
)
#>      data        ml 
#> "3.13.18" "3.12.16"
```

The `scikit-learn` pool clusters the `faithful` data frame. The labels
come back as an R vector.

``` r

kmeans_py <- "
import pyarrow as pa
from sklearn.cluster import KMeans
df = pa.table(points).to_pandas()
KMeans(n_clusters=2, n_init='auto', random_state=1).fit_predict(df)
"

clusters <- mizu_collect(
  mizu_submit_call(ml_pool, mizu_call(.source = kmeans_py, points = faithful))
)

table(clusters)
#> clusters
#>   0   1 
#> 172 100
```

## Stopping the Pools

[`mizu_pool_stop()`](https://shikokuchuo.net/mizu/reference/mizu_pool_stop.html)
stops the workers and frees the shared memory.

``` r

mizu_pool_stop(pool)
mizu_pool_stop(ml_pool)
```

## Choosing an Approach

| Need | Use |
|----|----|
| One-off scripts, crash safety, no extra R packages | [`run()`](https://luciorq.github.io/condathis/reference/run.md) |
| Python objects kept in memory between calls, Python chunks | `reticulate` |
| Persistent Python workers, parallel tasks, large R data | `mizu` |
| R code next to Python in each process, other machines | `reticulate` in `mirai` daemons |

The article [Running Python Code with condathis and
reticulate](https://luciorq.github.io/condathis/articles/python-and-reticulate.md)
shows the first, second and last approaches.

## Cleaning Up

``` r

remove_env(env_name = "py-mizu-env")
#> ✔ Environment py-mizu-env successfully removed.
remove_env(env_name = "py-mizu-ml-env")
#> ✔ Environment py-mizu-ml-env successfully removed.
```
