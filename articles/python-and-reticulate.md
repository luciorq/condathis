# Running Python Code with condathis and reticulate

## Two Ways to Use Python from R

`condathis` gives you a Python interpreter, and the packages it needs,
in an isolated Conda environment. There are two ways to use that
interpreter from R:

- **As a separate process.**
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  start `python` as a child process, the same way they start any other
  command line tool. Data moves through files, command line arguments,
  standard input and standard output. Every call is a fresh interpreter,
  and a crash in Python can never take down your R session.
- **Embedded in R with `reticulate`.** `reticulate` loads the
  interpreter from the same environment into the R process. Python
  objects stay in memory between calls and convert directly to R
  objects.

This article shows both, starting from the same environment. The process
approach needs nothing beyond `condathis`. The embedded approach also
needs the `reticulate` package.

## Creating the Environment

Pin the Python version and the packages you need. `condathis` resolves
everything from `conda-forge`, including the interpreter itself, so no
system Python is involved.

``` r

create_env(
  "python=3.13", "numpy", "pandas",
  env_name = "py-data-env",
  verbose = "silent"
)
```

Check what the solver installed:

``` r

pkgs <- list_packages(env_name = "py-data-env", verbose = "silent")
pkgs[pkgs$name %in% c("python", "numpy", "pandas"), c("name", "version")]
#> # A tibble: 3 × 2
#>   name   version
#>   <chr>  <chr>  
#> 1 numpy  2.5.4  
#> 2 pandas 3.1.1  
#> 3 python 3.13.18
```

Add packages later with
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md).
`micromamba` solves the environment again as a whole, and it may update
packages that are already installed. Pin their versions to keep them.

## Python as a Command Line Tool

### One-liners

`python -c` runs a short piece of code.
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md)
turns the captured standard output into a character vector, one element
per line.

``` r

res <- run(
  "python", "-c", "import sys; print(sys.version)",
  env_name = "py-data-env",
  verbose = "silent"
)

parse_output(res)
#> [1] "3.13.18 | packaged by conda-forge | (main, Oct 26 2026, 11:38:18) [GCC 15.3.0]"
```

### Scripts and Arguments

Longer code belongs in a script file. Arguments after the script path
reach Python in `sys.argv`, so R can pass file paths and parameters
without building code strings.

``` r

script_path <- fs::file_temp(pattern = "summarize-", ext = "py")

writeLines(
  con = script_path,
  text = c(
    "import json",
    "import sys",
    "import pandas as pd",
    "",
    "csv_path, group_col = sys.argv[1], sys.argv[2]",
    "df = pd.read_csv(csv_path)",
    "summary = df.groupby(group_col).mean(numeric_only=True).round(2)",
    "print(summary.reset_index().to_json(orient='records'))"
  )
)
```

R writes the input data to a CSV file. Python reads it, summarizes it
with `pandas`, and prints JSON to standard output. `jsonlite` turns that
JSON back into a data frame.

``` r

csv_path <- fs::file_temp(pattern = "iris-", ext = "csv")
utils::write.csv(iris, csv_path, row.names = FALSE)

res <- run(
  "python", script_path, csv_path, "Species",
  env_name = "py-data-env",
  verbose = "silent"
)

jsonlite::fromJSON(parse_output(res))
#>      Species Sepal.Length Sepal.Width Petal.Length Petal.Width
#> 1     setosa         5.01        3.43         1.46        0.25
#> 2 versicolor         5.94        2.77         4.26        1.33
#> 3  virginica         6.59        2.97         5.55        2.03
```

Files and JSON keep the boundary between the two languages explicit.
Each side only needs to agree on a file format, not on in-memory types.

### Code Through Standard Input

`python -` reads its program from standard input. With `stdin = "|"`,
[`run()`](https://luciorq.github.io/condathis/reference/run.md) writes
the `input` argument to the process, so code generated in R never
touches the disk.

``` r

py_code <- c(
  "import numpy as np",
  "rng = np.random.default_rng(seed=42)",
  "x = rng.normal(loc=10, scale=2, size=10_000)",
  "print(f'{x.mean():.3f} {x.std():.3f}')"
)

res <- run(
  "python", "-",
  env_name = "py-data-env",
  stdin = "|",
  input = paste0(py_code, collapse = "\n"),
  verbose = "silent"
)

parse_output(res)
#> [1] "9.980 2.013"
```

### Handling Python Errors

A Python exception makes the interpreter exit with a non-zero status. By
default, [`run()`](https://luciorq.github.io/condathis/reference/run.md)
turns that into an R error that includes the Python traceback from
standard error. Use `error = "continue"` to inspect the failure
yourself.

``` r

res <- run(
  "python", "-c", "import not_installed_module",
  env_name = "py-data-env",
  error = "continue",
  verbose = "silent"
)

res$status
#> [1] 1
tail(parse_output(res, stream = "stderr"), 1)
#> [1] "ModuleNotFoundError: No module named 'not_installed_module'"
```

### `run()` or `run_bin()`

Both functions run `python` from the environment, and start it directly,
with the variables of the environment’s activation. The activation is
recorded once per environment and reused until the environment or the
session’s environment variables change. Repeated short calls are fast
with both. They differ in how they find the program:

- [`run()`](https://luciorq.github.io/condathis/reference/run.md) always
  activates the environment, and finds `python` on the activated `PATH`,
  where the environment’s directories come first.
- [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  resolves the `python` binary inside the environment first. With
  `activate = FALSE`, it starts it without the activation variables.

``` r

res <- run_bin(
  "python", "-c", "import numpy; print(numpy.__version__)",
  env_name = "py-data-env",
  verbose = "silent"
)

parse_output(res)
#> [1] "2.5.4"
```

### Chaining Python with Other Tools

[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
connects commands with operating system pipes, like `|` in a shell. Each
stage is described with
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md),
which takes the same command and arguments as
[`run()`](https://luciorq.github.io/condathis/reference/run.md) but does
not run anything by itself. Each stage can live in its own environment,
given as `env_name` to
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md).
Stages without one use the `env_name` of
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
as both do here. A Python stage generates records and a second Python
stage, started with `-u` for unbuffered output, filters them as they
arrive.

``` r

producer <- paste(
  "import csv, sys",
  "w = csv.writer(sys.stdout, lineterminator='\\n')",
  "w.writerows((i, i * i) for i in range(1, 11))",
  sep = "\n"
)

consumer <- paste(
  "import csv, sys",
  "for i, sq in csv.reader(sys.stdin):",
  "    if int(sq) % 2 == 0:",
  "        print(f'{i} squared is {sq}')",
  sep = "\n"
)

res <- run_pipeline(
  run_step("python", "-c", producer),
  run_step("python", "-u", "-c", consumer),
  env_name = "py-data-env",
  verbose = "silent"
)

res$statuses
#> [1] 0 0
parse_output(res)
#> [1] "2 squared is 4"    "4 squared is 16"   "6 squared is 36"  
#> [4] "8 squared is 64"   "10 squared is 100"
```

The data between the two stages never passes through R.
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md)
reads the standard output of the last stage. `res$processes` holds the
full result of every stage. The producer sets `lineterminator='\n'`
because Python already translates `\n` to the platform’s line ending on
standard output. The default `\r\n` would become `\r\r\n` on Windows,
and the consumer would read empty rows.

## Embedding the Interpreter with reticulate

`reticulate` can bind to any Python interpreter. Point it at the one in
the `condathis` environment and `reticulate` uses exactly the packages
that `condathis` installed.

### Finding the Interpreter

Ask Python itself for its path. This works on every platform, including
Windows, where `python.exe` lives in the environment root rather than in
`bin/`. Relative to the environment directory, which
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md)
returns, the path is `bin/python` on Linux and macOS, and `python.exe`
on Windows.

``` r

python_path <- parse_output(
  run(
    "python", "-c", "import sys; print(sys.executable)",
    env_name = "py-data-env",
    verbose = "silent"
  )
)

fs::path_rel(python_path, get_env_dir(env_name = "py-data-env"))
#> bin/python
```

### Binding reticulate

`reticulate` recognizes the interpreter as part of a Conda environment
and prepares it differently on each platform:

- **Linux and macOS.** `reticulate` looks for a Conda executable to
  inspect the environment. `micromamba` works for that, so point the
  `RETICULATE_CONDA` environment variable at the binary that `condathis`
  manages.
  [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
  returns its path, and downloads it first if it is missing. Also point
  `MAMBA_ROOT_PREFIX` at the `condathis` data directory. Without it,
  `micromamba` aborts when it starts and the default root prefix of its
  own (`$XDG_DATA_HOME/mamba`, else `~/.local/share/mamba`) exists and
  is not a Conda environment. Without this step, `reticulate` searches
  `PATH` for `micromamba`, `mamba` or `conda`. On a machine with none of
  them, `use_python()` fails.
- **Windows.** The Python DLL loads its dependencies from the
  environment’s library folders, which must be on `PATH`. `reticulate`
  tries to add them by activating the environment through the Conda
  executable, which does not work with `micromamba`. Instead, copy
  `PATH` from an activated
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) call
  into the session.

``` r

if (.Platform$OS.type == "windows") {
  activated_path <- parse_output(
    run(
      "python", "-c", "import os; print(os.environ['PATH'])",
      env_name = "py-data-env",
      verbose = "silent"
    )
  )
  Sys.setenv(PATH = activated_path)
} else {
  Sys.setenv(
    RETICULATE_CONDA = install_micromamba(verbose = "silent"),
    MAMBA_ROOT_PREFIX = get_install_dir(method = "micromamba")$path
  )
}
```

Then call
[`reticulate::use_python()`](https://rstudio.github.io/reticulate/reference/use_python.html)
before anything else initializes Python in the session.
`required = TRUE` makes `reticulate` fail loudly instead of falling back
to a different interpreter.

``` r

reticulate::use_python(python_path, required = TRUE)

# reticulate now uses the interpreter of the environment
identical(
  normalizePath(reticulate::py_config()$python),
  normalizePath(python_path)
)
#> [1] TRUE
```

Setting the `RETICULATE_PYTHON` environment variable to the same path,
for example in a project `.Renviron` file, has the same effect. It also
applies to sessions that load `reticulate` before your code runs, such
as the RStudio and Positron IDEs.

### Calling Python Objects from R

Modules imported with
[`reticulate::import()`](https://rstudio.github.io/reticulate/reference/import.html)
behave like R lists of functions. Arguments and results convert between
R and Python types automatically.

``` r

np <- reticulate::import("numpy", convert = FALSE)

m <- np$arange(12L)$reshape(3L, 4L)
m
#> array([[ 0,  1,  2,  3],
#>        [ 4,  5,  6,  7],
#>        [ 8,  9, 10, 11]])

reticulate::py_to_r(m$sum(axis = 0L))
#> [1] 12 15 18 21
```

A `pandas` data frame converts to an R data frame, and back.

``` r

py_df <- reticulate::r_to_py(mtcars)
py_summary <- py_df$groupby("cyl")$agg(list(mpg = "mean", hp = "max"))

py_summary
#>            mpg     hp
#> cyl                  
#> 4.0  26.663636  113.0
#> 6.0  19.742857  175.0
#> 8.0  15.100000  335.0

r_summary <- reticulate::py_to_r(py_summary)
class(r_summary)
#> [1] "data.frame"
r_summary
#>        mpg  hp
#> 4 26.66364 113
#> 6 19.74286 175
#> 8 15.10000 335
```

### Running Python Chunks in a Document

`reticulate` also provides the knitr engine for `python` chunks in R
Markdown and Quarto documents rendered with knitr. After the
`use_python()` call above, every `python` chunk in this document runs in
the same embedded interpreter. Objects created in R are available in
Python as `r.<name>`.

``` r

cutoff <- 20
```

``` python
import pandas as pd

cars = r.mtcars
efficient = cars[cars["mpg"] > r.cutoff][["mpg", "cyl", "hp"]]
efficient.sort_values("mpg", ascending=False).head()
#>                  mpg  cyl     hp
#> Toyota Corolla  33.9  4.0   65.0
#> Fiat 128        32.4  4.0   66.0
#> Lotus Europa    30.4  4.0  113.0
#> Honda Civic     30.4  4.0   52.0
#> Fiat X1-9       27.3  4.0   66.0
```

Python objects are available in R as `reticulate::py$<name>`.

``` r

nrow(reticulate::py$efficient)
#> [1] 14
```

### Things to Know

- **One interpreter per R session.** Once `reticulate` initializes
  Python, it cannot switch to another one. Restart R to use a different
  environment, or run each interpreter in its own background R process,
  as shown in the next section.
- **Install packages with condathis.** Use
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  to add Python packages to the environment.
  [`reticulate::py_install()`](https://rstudio.github.io/reticulate/reference/py_install.html)
  and
  [`reticulate::py_require()`](https://rstudio.github.io/reticulate/reference/py_require.html)
  manage their own environments and do not know about `condathis`
  environments. Packages installed while Python is already loaded are
  importable in the same session. Upgrading a package that is already
  imported needs an R restart.
- **No activation for the embedded interpreter.**
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  activate the environment for every call. The embedded interpreter
  starts inside the R process, so variables set by packages’
  `activate.d` scripts are absent. Pure Python packages are not
  affected. If a package depends on such a variable, set it with
  [`Sys.setenv()`](https://rdrr.io/r/base/Sys.setenv.html) before you
  import the package.
- **A crash in Python is a crash in R.** A segmentation fault in a
  compiled Python extension ends the R session too. Use
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) or
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  for code that you do not trust to be stable.

## Many Python Interpreters with mirai

The single-interpreter limit applies to one R process, not to one
analysis. `mirai` runs R code in background R processes called daemons.
Each daemon is a separate R session, so each one can bind `reticulate`
to a different Python.

Starting every daemon inside an activated `condathis` environment gives
you:

- One persistent Python interpreter per environment, all usable from the
  same R session.
- Different Python versions and incompatible package sets side by side.
- Full activation, including variables set by packages’ `activate.d`
  scripts, which the embedded interpreter in the main session lacks.
- Crash isolation: a Python crash ends one daemon, not your R session.

This section uses three more packages:

- `mirai` launches the daemons and sends them tasks.
- `arrow` moves tables between R and Python, and between processes.
- `mori` shares R objects with the daemons through shared memory,
  without copying them.

### Two Environments with Different Packages

One environment handles coordinate projections with `pyproj`, on Python
3.13. The other one clusters points with `scikit-learn`, on Python 3.12.
Both have `pyarrow`, the bridge for moving tables.

``` r

create_env(
  "python=3.13", "numpy", "pyproj", "pyarrow",
  env_name = "py-geo-env",
  verbose = "silent"
)

create_env(
  "python=3.12", "scikit-learn", "pandas", "pyarrow",
  env_name = "py-ml-env",
  verbose = "silent"
)
```

### Launching Activated Daemons

Each environment gets its own `mirai` compute profile, so a task can
name the environment it needs. Setting up a profile with a `url` and no
launcher only opens the connection point. No daemon starts yet.

Arrow tables are external pointers, so R’s default serialization cannot
send them to another process.
[`mirai::serial_config()`](https://nanonext.r-lib.org/reference/serial_config.html)
registers the Arrow IPC stream format for them.

``` r

arrow_serial <- mirai::serial_config(
  class = "ArrowTabular",
  sfunc = function(x) arrow::write_to_raw(x),
  ufunc = function(x) arrow::read_ipc_stream(x, as_data_frame = FALSE)
)

for (profile in c("geo", "ml")) {
  mirai::daemons(
    url = mirai::local_url(),
    serial = arrow_serial,
    .compute = profile
  )
}
```

The two hooks wrap the `arrow` functions instead of passing them
directly. A function from a package carries that package’s namespace
when it is serialized. Each daemon would therefore load the R `arrow`
package as soon as it received the configuration. That matters on
Windows, where `pyarrow` must be imported before the R `arrow` package
loads. Both ship a library named `arrow.dll`, and Windows reuses the one
already loaded in the process. If the R package loads first,
`import pyarrow` fails with “DLL load failed”.

The daemon itself is an `Rscript` process started by
`micromamba run -n <env>`, which activates the environment first.
`--no-rc` and `--no-env` make `micromamba` ignore your configuration
files and `MAMBA_*` settings, as `condathis` does with its own
`--rc-file`. `-r` sets the root prefix to the `condathis` data
directory. `MAMBA_ROOT_PREFIX` sets it too: `micromamba` reads it before
`-r`, also with `--no-env`. It aborts at the start when its own default
root prefix exists and is not a Conda environment.
`mirai::nextget("url")` returns the address the daemon must connect to.

``` r

umamba_path <- install_micromamba(verbose = "silent")
root_dir <- get_install_dir(method = "micromamba")$path
rscript_path <- fs::path(
  R.home("bin"),
  if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript"
)

launch_env_daemon <- function(env_name, profile) {
  url <- mirai::nextget("url", .compute = profile)
  processx::process$new(
    command = umamba_path,
    args = c(
      "--no-rc", "--no-env", "-r", root_dir,
      "run", "-n", env_name,
      rscript_path, "-e", sprintf("mirai::daemon('%s')", url)
    ),
    env = c("current", MAMBA_ROOT_PREFIX = root_dir),
    cleanup_tree = TRUE
  )
}

daemon_procs <- list(
  geo = launch_env_daemon("py-geo-env", profile = "geo"),
  ml = launch_env_daemon("py-ml-env", profile = "ml")
)
```

The daemons start from `processx`, the same library `condathis` uses for
every command.
[`mirai::remote_config()`](https://mirai.r-lib.org/reference/remote_config.html)
with `micromamba` as the command also works on Linux and macOS. On
Windows it fails, because R’s
[`system2()`](https://rdrr.io/r/base/system2.html) launches `micromamba`
in a way that breaks its activation scripts.

Keep `daemon_procs` referenced while the daemons run.
`cleanup_tree = TRUE` stops a daemon and its children if its handle is
garbage collected.

### Binding reticulate in Each Daemon

Inside an activated daemon, `PATH` starts with the environment’s binary
directories. `Sys.which("python")` therefore finds that environment’s
interpreter. On Windows, that same activated `PATH` also gives the
Python DLL its dependencies. On Linux and macOS, the daemons inherit
`RETICULATE_CONDA` from the main session.
[`mirai::everywhere()`](https://mirai.r-lib.org/reference/everywhere.html)
runs the setup code on every daemon of a profile and waits for the
daemons to connect. The setup stops with an error if `reticulate` bound
to any Python outside the activated environment. It imports `pyarrow`
before anything in the daemon uses the R `arrow` package, which avoids
the Windows library clash described above.

``` r

bind_python <- quote({
  reticulate::use_python(Sys.which("python"), required = TRUE)
  env_dir <- normalizePath(Sys.getenv("CONDA_PREFIX"), winslash = "/")
  py_exe <- normalizePath(reticulate::py_config()$python, winslash = "/")
  if (!startsWith(py_exe, env_dir)) {
    stop("reticulate bound to ", py_exe, " instead of ", env_dir)
  }
  invisible(reticulate::import("pyarrow"))
})

mirai::everywhere(bind_python, .compute = "geo")
mirai::everywhere(bind_python, .compute = "ml")
```

Ask both daemons about themselves at the same time. `mirai()` returns
immediately, and `[]` waits for the result.

``` r

daemon_info <- function() {
  list(
    pid = Sys.getpid(),
    env = basename(Sys.getenv("CONDA_PREFIX")),
    python = as.character(reticulate::py_config()$version),
    PROJ_DATA = nzchar(Sys.getenv("PROJ_DATA"))
  )
}

geo_info <- mirai::mirai(daemon_info(), daemon_info = daemon_info, .compute = "geo")
ml_info <- mirai::mirai(daemon_info(), daemon_info = daemon_info, .compute = "ml")

str(list(geo = geo_info[], ml = ml_info[], main = Sys.getpid()))
#> List of 3
#>  $ geo :List of 4
#>   ..$ pid      : int 13870
#>   ..$ env      : chr "py-geo-env"
#>   ..$ python   : chr "3.13"
#>   ..$ PROJ_DATA: logi TRUE
#>  $ ml  :List of 4
#>   ..$ pid      : int 13880
#>   ..$ env      : chr "py-ml-env"
#>   ..$ python   : chr "3.12"
#>   ..$ PROJ_DATA: logi FALSE
#>  $ main: int 12933
```

Each daemon is its own process with its own Python version. `PROJ_DATA`
is set only in the geo daemon. The `proj` package sets it in its
activation script, and `pyproj` needs it to find its projection
database. That is the activation step the embedded interpreter in the
main session skips.

### Sharing Input Data with mori

[`mori::share()`](https://rdrr.io/pkg/mori/man/share.html) copies an R
object into shared memory once. Every process on the machine can then
read the same physical memory. When `mirai` sends a shared object to a
daemon, it sends only the name of the shared memory region.

``` r

set.seed(42)
n_points <- 1e6
points <- data.frame(
  lon = stats::runif(n_points, min = -74.25, max = -73.70),
  lat = stats::runif(n_points, min = 40.50, max = 40.90)
)

points_shared <- mori::share(points)

c(
  plain = length(serialize(points, NULL)),
  shared = length(serialize(points_shared, NULL))
)
#>    plain   shared 
#> 16000190      270
```

Keep `points_shared` referenced in the main session until the daemons
are done with it. The shared region is freed when the last reference in
the main session is garbage collected.

`mori` shares R objects between R processes. Python cannot read them
directly. Arrow is the bridge from R to Python inside each daemon.

### Projecting Coordinates in the First Environment

The geo daemon maps the shared data frame, converts it to an Arrow
table, and passes that to Python. `reticulate` hands Arrow tables to
`pyarrow` through the Arrow C data interface, which shares the buffers
instead of copying them. `pyproj` projects longitude and latitude to
Universal Transverse Mercator (UTM) zone 18N, in meters. The result
returns to the main session as an Arrow table.

``` r

geo_task <- mirai::mirai(
  {
    pa <- reticulate::import("pyarrow")
    pyproj <- reticulate::import("pyproj")

    py_tbl <- reticulate::r_to_py(arrow::arrow_table(points))
    transformer <- pyproj$Transformer$from_crs(
      "EPSG:4326", "EPSG:32618",
      always_xy = TRUE
    )
    xy <- transformer$transform(
      py_tbl$column("lon")$to_numpy(),
      py_tbl$column("lat")$to_numpy()
    )

    projected <- pa$table(reticulate::dict(x = xy[[1]], y = xy[[2]]))
    reticulate::py_to_r(projected)
  },
  points = points_shared,
  .compute = "geo"
)

projected <- geo_task[]
projected
#> Table
#> 1000000 rows x 2 columns
#> $x <double>
#> $y <double>
```

### Clustering in the Second Environment

The Arrow table goes straight to the ml daemon. That daemon has a
different Python and none of the geo packages. It converts the table to
a `pandas` data frame and clusters the points with `scikit-learn`.

``` r

ml_task <- mirai::mirai(
  {
    sklearn_cluster <- reticulate::import("sklearn.cluster")
    pd_df <- reticulate::r_to_py(projected)$to_pandas()

    kmeans <- sklearn_cluster$KMeans(
      n_clusters = 4L,
      n_init = "auto",
      random_state = 1L
    )
    labels <- kmeans$fit_predict(pd_df)

    arrow::arrow_table(cluster = as.integer(reticulate::py_to_r(labels)))
  },
  projected = projected,
  .compute = "ml"
)

clusters <- ml_task[]
table(as.vector(clusters$cluster))
#> 
#>      0      1      2      3 
#> 250438 250767 249785 249010
```

The main session coordinated both steps without loading Python itself.
The `reticulate` binding to `py-data-env` from the earlier section is
unaffected.

### Sharing Tables Directly Between Python Processes

Passing results through the main session is convenient for moderate
sizes. For large tables, write them once to an Arrow IPC file instead.
Any other process can memory-map that file and read the columns without
loading or copying them.

``` r

ipc_path <- fs::file_temp(pattern = "projected-", ext = "arrow")

mirai::mirai(
  {
    pa <- reticulate::import("pyarrow")
    pa_ipc <- reticulate::import("pyarrow.ipc")
    py_tbl <- reticulate::r_to_py(projected)

    sink <- pa$OSFile(ipc_path, "wb")
    writer <- pa_ipc$new_file(sink, py_tbl$schema)
    writer$write_table(py_tbl)
    writer$close()
    sink$close()
    reticulate::py_to_r(py_tbl$num_rows)
  },
  projected = projected,
  ipc_path = ipc_path,
  .compute = "geo"
)[]
#> [1] 1000000

mirai::mirai(
  {
    pa <- reticulate::import("pyarrow")
    pa_ipc <- reticulate::import("pyarrow.ipc")
    py_tbl <- pa_ipc$open_file(pa$memory_map(ipc_path, "r"))$read_all()
    reticulate::py_to_r(py_tbl$num_rows)
  },
  ipc_path = ipc_path,
  .compute = "ml"
)[]
#> [1] 1000000
```

The geo daemon reports the rows it wrote, and the ml daemon the rows it
read from the file. The file format is the same in every `pyarrow`
version and in the R `arrow` package, so the two environments do not
need matching versions.

### Stopping the Daemons

`daemons(0)` stops the daemons of a profile. Each Python interpreter
exits with its daemon, and `micromamba run` exits after it.

``` r

mirai::daemons(0, .compute = "geo")
mirai::daemons(0, .compute = "ml")

for (proc in daemon_procs) {
  proc$wait(timeout = 10000)
}
vapply(daemon_procs, function(proc) proc$is_alive(), logical(1))
#>   geo    ml 
#> FALSE FALSE
```

## Choosing an Approach

| Need | Use |
|----|----|
| Isolation from the R session, crash safety | [`run()`](https://luciorq.github.io/condathis/reference/run.md) or [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md) |
| Several Python versions in one analysis | [`run()`](https://luciorq.github.io/condathis/reference/run.md) or [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md), one environment each |
| Streaming data through other command line tools | [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md) with [`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md) |
| Python objects kept in memory between calls | `reticulate` |
| Direct conversion of data frames and arrays | `reticulate` |
| Python chunks in R Markdown or Quarto | `reticulate` |
| Several persistent interpreters, each fully activated | `reticulate` in `mirai` daemons |

In every case, `condathis` owns the environment. The same
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
call reproduces it on any machine. To share the environment as a file,
write its package specs, with versions pinned, to an environment YAML
file and pass it as `env_file` to
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).

## Cleaning Up

``` r

remove_env(env_name = "py-data-env")
#> ✔ Environment py-data-env successfully removed.
remove_env(env_name = "py-geo-env")
#> ✔ Environment py-geo-env successfully removed.
remove_env(env_name = "py-ml-env")
#> ✔ Environment py-ml-env successfully removed.
```
