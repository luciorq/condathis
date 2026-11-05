# condathis

> Run command line tools in a **reproducible** and **isolated** way,
> right from R.

[`system()`](https://rdrr.io/r/base/system.html) calls that work on your
machine often break on others. `condathis` creates self-contained
environments for your command line tools, so your R code runs reliably
for you, your colleagues, and your future self.

## A Quick Example

Two commands install `cowpy` in its own isolated environment and run it:

``` r

# 1. Install 'cowpy' into an environment named 'cowpy-env'
condathis::create_env("cowpy", env_name = "cowpy-env")
#> v Environment cowpy-env successfully created.

# 2. Run it!
# Example showing redirection from a file to the Standard Input (STDIN)
temp_file <- tempfile()
writeLines("{condathis} is awesome!", temp_file)
condathis::run("cowpy", stdin = temp_file, env_name = "cowpy-env")
#>  _________________________
#> < {condathis} is awesome! >
#>  -------------------------
#>      \   ^__^
#>       \  (oo)\_______
#>          (__)\       )\/\
#>            ||----w |
#>            ||     ||
```

For something fancier, use `rich-cli` to format messages:

``` r

condathis::create_env("rich-cli", env_name = "rich-cli-env")
#> v Environment rich-cli-env successfully created.

condathis::run(
  "rich", "[b]Condathis[/b] is awesome!", "-p", "-a", "ascii",
  env_name = "rich-cli-env"
)
#> +-----------------------+
#> | Condathis is awesome! |
#> +-----------------------+
```

You can package any command line tool with your R script, and it runs on
any machine where its packages are available.

## Installation

Install the release version of the package from
[CRAN](https://CRAN.R-project.org/package=condathis):

``` r

install.packages("condathis")
```

Or get the development version from
[R-Universe](https://luciorq.r-universe.dev/condathis):

``` r

install.packages("condathis", repos = c("https://luciorq.r-universe.dev", getOption("repos")))
```

## Why `condathis`?

R’s [`system()`](https://rdrr.io/r/base/system.html) and
[`system2()`](https://rdrr.io/r/base/system2.html) depend on tools being
installed on the host system. This creates a few problems:

- **Reproducibility:** Will your script from last year still work? Will
  your collaborator be able to run your code if they have a different
  version of a tool?
- **Conflicts:** What if two different tools need two different versions
  of the same dependency?

`condathis` solves these issues by creating isolated environments for
each tool.

### Reproducibility: An Example

Let’s say you’re using `fastqc` for quality control in a bioinformatics
pipeline. Different versions of `fastqc` can produce slightly different
results.

With `condathis`, you can lock in a specific version:

``` r

fastq_file <- system.file("extdata", "sample1_L001_R1_001.fastq.gz", package = "condathis")
temp_out_dir <- file.path(tempdir(), "output")
fs::dir_create(temp_out_dir)

# Always use fastqc version 0.12.1
condathis::create_env(
  "fastqc==0.12.1",
  env_name = "fastqc-0.12.1",
  channels = c("conda-forge", "bioconda")
)
#> v Environment fastqc-0.12.1 successfully created.
condathis::run("fastqc", fastq_file, "-o", temp_out_dir, env_name = "fastqc-0.12.1")
#> application/gzip
#> Started analysis of sample1_L001_R1_001.fastq.gz
#> Approx 90% complete for sample1_L001_R1_001.fastq.gz
#> Analysis complete for sample1_L001_R1_001.fastq.gz
```

Now your analysis uses the same `fastqc` version, regardless of where or
when it runs.

### Isolation: An Example

Need a specific version of a tool like `curl` that is different from the
one your system or R provides?

The `libcurl` that R uses:

``` r

as.character(libcurlVersion())
#> [1] "8.23.0"
```

A specific `curl` version, isolated with `condathis`:

``` r

condathis::create_env(
  "curl==8.10.1",
  env_name = "curl-env"
)
#> v Environment curl-env successfully created.

# Capture the output as an R object, then read its first line
out <- condathis::run(
  "curl", "--version",
  env_name = "curl-env",
  verbose = "silent"
)

condathis::parse_output(out)[1]
#> [1] "curl 8.10.1 (x86_64-conda-linux-gnu) libcurl/8.10.1 OpenSSL/3.6.5 zlib/1.3.2 zstd/1.5.7 libssh2/1.11.1 nghttp2/1.70.0"
```

This lets you run tools with conflicting dependencies side by side.

## How It Works

`condathis` relies on
[**`micromamba`**](https://mamba.readthedocs.io/en/latest/user_guide/micromamba.html)
to bring **reproducibility and isolation**. `micromamba` is a package
manager that “does not need a base environment and does not come with a
default version of Python”. `condathis` downloads `micromamba` when it
first needs it and finds no usable copy. It keeps `micromamba` and the
environments in its own data directory (see
[`condathis::get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).
Environments stay there until you remove them.
[`condathis::list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md)
lists them, `condathis::get_env_dir("cowpy-env")` returns the directory
of one, `condathis::remove_env("cowpy-env")` removes it, and
[`condathis::clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
deletes the downloaded package files.

`micromamba` is the built-in *backend* of `condathis`. Other packages
can add backends with
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md).
New environments use `micromamba` unless you pass `method` (for example
`method = "rattler"`, which needs the `rattlerthis` package, not yet on
CRAN) or set `options(condathis.backend_priority = ...)`.

Already have an environment created outside `condathis`, for example by
`conda`, `mamba`, or `micromamba` itself? Pass its directory as
`env_name = condathis::env_path("/path/to/env")` to
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
or
[`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)
to run commands from it. `condathis` never modifies such an environment.
It runs commands in it with `micromamba` by default.

## Known Caveats

No shell is involved, so shell syntax in an argument is passed
literally.

- Shell builtins, such as `echo` or `dir` on Windows, are not available
  as commands. To use shell features, run a shell explicitly, for
  example `condathis::run("bash", "-c", "...")`.
- Shell operators such as `|` and `>` are not interpreted.
  - Instead of `>`, use the `stdout`/`stderr` arguments (a file path
    redirects to that file).
  - Instead of `cmd1 | cmd2`, use
    [`condathis::run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
    with one
    [`condathis::run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)
    per command, as in
    `run_pipeline(run_step("cmd1"), run_step("cmd2", env_name = "other-env"))`.
    It connects the commands (optionally each in its own Conda
    environment) via kernel-level pipes. Alternatively, call
    [`condathis::run()`](https://luciorq.github.io/condathis/reference/run.md)
    several times and use the `stdout`/`stdin` file arguments to pass
    data between the calls.
  - `stdin` accepts a file path. Set it to `"|"` together with the
    `input` argument to write in-memory data (character or raw vector)
    directly to a command’s standard input. This works with
    [`run()`](https://luciorq.github.io/condathis/reference/run.md),
    [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
    and
    [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md).
- A `~` in a command argument is not expanded.
  - Expand such paths in R, for example with
    [`path.expand()`](https://rdrr.io/r/base/path.expand.html) or
    [`fs::path_expand()`](https://fs.r-lib.org/reference/path_expand.html).
  - Relative paths, such as `"data/sample.fastq"` or
    `"../sample.fastq"`, work: they are relative to the working
    directory of R.

## Learn More

- [`vignette("condathis")`](https://luciorq.github.io/condathis/articles/condathis.md)
  walks through a complete example.
- The [articles](https://luciorq.github.io/condathis/articles/) on the
  package website show how to use Python with `reticulate`, and how to
  stream binary data through pipelines.
