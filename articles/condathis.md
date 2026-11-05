# Introduction to condathis

## Introduction

Running command line (CLI) tools from R can extend your analysis, but it
often comes with challenges. How do you ensure that the tool is
installed? How do you manage its dependencies without conflicting with
other software on your system? How do you make your analysis
reproducible for others?

`condathis` runs any CLI tool in an isolated, reproducible Conda
environment, powered by `micromamba`.

## The Problem: Reproducible CLI Execution

Imagine you want to analyze a BAM file using `samtools`, a popular
bioinformatics tool. You could write an R script that calls `samtools`
using [`system()`](https://rdrr.io/r/base/system.html), but this
approach has some drawbacks:

1.  **Installation:** Your script depends on `samtools` being installed
    and available in the system’s `PATH`. If you share your script with
    a colleague, they will need to install it manually. They might
    install a different version, which could lead to different results.
2.  **Conflicts:** Installing `samtools` and its dependencies might
    conflict with other tools already installed on the system.
3.  **Reproducibility:** It’s hard to guarantee that your analysis will
    run the same way on different machines or at a later time. The
    software environment is not explicitly defined.

## The `condathis` Solution

`condathis` solves this by creating isolated environments for your
tools.

### Step 1: Create an Environment

Create a Conda environment that contains `samtools` with
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).
Pass the package specs first, here `samtools` 1.22.1 from the `bioconda`
channel. Name the environment with `env_name`. `channels` lists, in
priority order, the channels for the other packages: here `conda-forge`
and then `bioconda`.

``` r

create_env(
  "bioconda::samtools==1.22.1",
  env_name = "samtools-env",
  channels = c("conda-forge", "bioconda")
)
```

This command will:

1.  Download `micromamba` if no usable copy is found. It is a single,
    self-contained executable that stays in the `condathis` data
    directory and does not interfere with your system.
2.  Create a new Conda environment named `samtools-env`.
3.  Install `samtools` into that environment.

### Step 2: Run the Tool

Now that we have our environment, we can use
[`run()`](https://luciorq.github.io/condathis/reference/run.md) to
execute `samtools` commands. `condathis` includes an example BAM file
that we can use for this demonstration.

Let’s use `samtools view` to inspect the header of our example BAM file.

``` r

# Get the path to the example BAM file
bam_file <- system.file("extdata", "example.bam", package = "condathis")

# Run samtools view -H on the BAM file
run("samtools", "view", "-H", bam_file, env_name = "samtools-env")
```

[`run()`](https://luciorq.github.io/condathis/reference/run.md)
activates the environment and runs the command in it. The output of the
command is printed to the R console. It ends with a line that records
this call and the version of `samtools` that ran it:

    @SQ     SN:chr1 LN:249250621
    @SQ     SN:chr2 LN:243199373
    ...
    @PG     ID:samtools.2   PN:samtools PP:samtools.1   VN:1.22.1 CL:samtools view -H .../example.bam

To use the output in R instead, pass `verbose = "silent"` and read the
result of
[`run()`](https://luciorq.github.io/condathis/reference/run.md) with
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md),
which returns one string per line.

### Putting It All Together

Here is a complete, reproducible example.

``` r

# Load the package
library(condathis)

# Create an environment with samtools 1.22.1
create_env(
  "bioconda::samtools==1.22.1",
  env_name = "samtools-env",
  channels = c("conda-forge", "bioconda")
)

# Get the path to the example BAM file
bam_file <- system.file("extdata", "example.bam", package = "condathis")

# Run samtools to view the header
run(
  "samtools", "view", "-H", bam_file,
  env_name = "samtools-env"
)

# Clean up the environment
remove_env(env_name = "samtools-env")
```

## Why `condathis`?

By using `condathis`, you get:

- **Isolation:** Dependencies for each tool are kept separate, avoiding
  conflicts.
- **Reproducibility:** Your R script defines and creates the software
  environment it needs. Pin the versions in the package specs, as in
  `"bioconda::samtools==1.22.1"`, and everyone who runs it gets the same
  tools.
- **Simplicity:** You can manage everything from within R, without
  needing to manually use the command line to manage Conda environments.

## Next Steps

- [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  adds packages to an existing environment, and
  [`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md)
  lists them.
- [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  connects commands with pipes, as `|` does in a shell, each in its own
  environment if needed.
- [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  lets [`run()`](https://luciorq.github.io/condathis/reference/run.md)
  use an environment created outside `condathis`.
- [`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md)
  lists the environments of `condathis`,
  [`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)
  removes one, and
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  deletes the downloaded package files.
