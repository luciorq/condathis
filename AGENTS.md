# AGENTS.md

This file helps Gemini assist with development tasks for the `condathis`
R package.

## Project Overview

**`condathis`** is an R package designed to simplify the execution of
command-line interface (CLI) tools within isolated and reproducible
environments.

The package’s primary goal is to solve reproducibility and
dependency-conflict problems that arise when calling system tools from
R. It achieves this by using `micromamba` to create and manage sandboxed
Conda environments, allowing R users to run any CLI tool with specific
dependencies.

**Core Functionality:**

- Create isolated Conda environments
  ([`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)).
- Run CLI commands within a specified environment
  ([`run()`](https://luciorq.github.io/condathis/reference/run.md)).
- Manage environments and installations from within R.

**Key Technologies:**

- **Language:** R (requires R ≥ 4.3)
- **Core External Tool:** `micromamba` (which the package already
  manages internally).
- **Core R Dependencies:**
  - `processx`: For running and managing external processes (like
    `micromamba`).
  - `withr`: For managing state and environment variables during
    execution.
  - `fs`: For file system operations.
  - `cli`: For creating a rich command-line user interface, including
    error messages.
- **Testing:** `testthat` (≥ 3.0.0).
- **Task Runner:** `just` (a `justfile` is present in the repository).

## Project Structure

- `R/`: Contains all R source code for the package functions.
- `DESCRIPTION`: The package’s metadata file. This is the canonical
  source for all R dependencies (Imports, Suggests).
- `NAMESPACE`: Manages function visibility and imports.
- `tests/`: Root directory for tests.
  - `tests/testthat/`: Contains all `testthat` test scripts (e.g.,
    `test-run.R`).
- `man/`: Documentation files (generated from Roxygen comments in `R/`)
  it is generated automatically and should never be modified manually.
- `README.qmd`: The Quarto markdown source used to generate `README.md`.
- `justfile`: A task runner file with recipes for common development
  commands (lint, test, document, check, build-readme, build-vignette).
- `inst/extdata/`: Contains example data files used for tests and
  examples.
- `vignettes/`: Contains package vignettes (long-form documentation) in
  Quarto markdown format.
- `NEWS.md`: Changelog file documenting changes across versions.

## Coding Standards

When assisting with development, use the following standard R package
development commands prefer using `tidyverse` packages and functions,
like `dplyr` and `tibble`. Prefer `rlang` functions. Prefer `ggplot2`
for plots and charts. Prefer `cli` for messages and error messages. When
writing Quarto documents prefer using the following code chunk header
syntax:

`{r} #| label: setup #| include: false #| eval: true`

than `{r setup, include=FALSE eval=TRUE}`.

## Example snippets

> NOTE: Pay attention that the
> [`run()`](https://luciorq.github.io/condathis/reference/run.md)
> function do not require named arguments for `command` and `args`, they
> can be passed positionally without a vector wrapping the arguments as
> the function uses `...`.

``` r
library(condathis)

# Create an environment with samtools
create_env(
  packages = "samtools",
  channels = c("bioconda", "conda-forge"),
  env_name = "samtools-env"
)

# Get the path to the example BAM file
bam_file <- system.file("extdata", "example.bam", package = "condathis")

# Run samtools to view the header
run(
  "samtools", "view", "-H", bam_file,
  env_name = "samtools-env"
)

# Clean up the environment
remove_env("samtools-env")
```

### 1. Setup and Dependencies

- **Install Development Dependencies:**
  - `just install-deps`

### 2. Running Tests

- **Run all tests:**
  - `just test` (This already runs lint and document before testing)
- **Run a specific test file:**
  - `devtools::load_all(); devtools::test_file("tests/testthat/test-run.R");`

### 3. Documentation

- **Render the `README.md` from `README.qmd`:**
  - `just build-readme`
- **Update documentation (roxygen comments):**
  - `just document`

### 4. Code Linting and Styling

- **Lint the package:**
  - `just lint`

### 5. Package Check

- **Run a full R CMD check:**
  - `just check`
