# AGENTS.md

This file describes how to assist with development tasks for the `condathis` R package.

## Project Overview

**`condathis`** is an R package designed to simplify the execution of command-line interface (CLI) tools within isolated and reproducible environments.

The package's primary goal is to solve reproducibility and dependency-conflict problems that arise when calling system tools from R.
It achieves this by using `micromamba` to create and manage sandboxed Conda environments, allowing R users to run any CLI tool with specific dependencies.

**Core Functionality:**

* Create isolated Conda environments (`create_env()`).
* Run CLI commands within a specified environment (`run()`).
* Manage environments and installations from within R.

**Key Technologies:**

* **Language:** R (requires R >= 4.3)
* **Core External Tool:** `micromamba` (which the package already manages internally).
* **Core R Dependencies:** `processx` and `ps` (processes), `rlang` and `cli` (conditions and messages), `fs` and `filelock` (files and locks), `withr`, `jsonlite`, `stringr`.
* **Testing:** `testthat` (>= 3.2.1).
* **Task Runner:** `just` (a `justfile` is present in the repository).

## Project Structure

* `R/`: Contains all R source code for the package functions.
* `DESCRIPTION`: The package's metadata file. This is the canonical source for all R dependencies (Imports, Suggests).
* `NAMESPACE`: Manages function visibility and imports.
* `tests/`: Root directory for tests.
  * `tests/testthat/`: Contains all `testthat` test scripts (e.g., `test-run.R`).
* `man/`: Documentation files (generated from Roxygen comments in `R/`) it is generated automatically and should never be modified manually.
* `README.qmd`: The Quarto markdown source used to generate `README.md`.
* `justfile`: A task runner file with recipes for common development commands (lint, test, test-file, document, check, build-readme, build-vignettes).
* `inst/extdata/`: Contains example data files used for tests and examples. `inst/extdata/README.md` describes each file, its source and where it is used.
* `vignettes/`: Contains package vignettes (long-form documentation) in Quarto markdown format.
* `NEWS.md`: Changelog file documenting changes across versions.

## Coding Standards

Never delete files without explicit instructions.

In `R/`, use only the packages in `Imports` of `DESCRIPTION` (cli, filelock, fs, jsonlite, processx, ps, rlang, stringr, withr, tools, utils). Do not add dependencies such as dplyr or tibble: data frames get the tibble class without the tibble package.

Prefer `rlang` for guard clauses, error handling, condition classes, and defensive programming.
Prefer `cli` for messages and error messages.
Prefer `testthat` for tests.
Prefer `fs` for file system operations.

Prefer **Quarto Markdown** for documentation and vignettes.

When writing Quarto documents prefer using the following code chunk header syntax:

````txt
```{r}
#| label: setup
#| include: false
#| eval: true
```
````

than `{r setup, include=FALSE eval=TRUE}`.

## Example snippets

> NOTE: `run()` takes the command as `cmd` and its arguments in `...`: pass them positionally, one string each, without wrapping them in a vector. Name every other argument, such as `env_name`.

```r
library(condathis)

# Create an environment with samtools
create_env(
  "bioconda::samtools",
  channels = c("conda-forge", "bioconda"),
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
remove_env(env_name = "samtools-env")
```

### 1. Setup and Dependencies

* **Install Development Dependencies:**
  * `just install-deps`

### 2. Running Tests

* **Run a specific test file:**
  * `just test-file run`
  * When writing new tests, always run individual test files instead of running full test suite:
    * `just test-file <FUNCTION_NAME>` (for `tests/testthat/test-<FUNCTION_NAME>.R`)
    * It is the same as running: `R -q -s -e 'devtools::load_all();devtools::test_active_file("tests/testthat/test-run.R");'`

* **Run all tests:**
  * `just test` (runs all examples, then the full test suite with `devtools::test()`; it does not lint or document, so run `just lint` and `just document` on purpose: `just lint` reformats `R/` and `tests/` with Air, rewrites `@return` to `@returns`, runs `just document` (which also runs `usethis::use_tidy_description()`) and rewrites `.gitignore` and `.Rbuildignore`)

### Testing rules

* The full suite (`NOT_CRAN=true`, with internet access) must pass with no failures and no skips, apart from tests for another operating system.
* `devtools::test()`, `devtools::check()` and `testthat::test_local()` set `NOT_CRAN=true` when it is unset. To run or time the tests that CRAN runs, set `NOT_CRAN=false`, or run `tests/testthat.R` against the installed package.
* Start R in the foreground: an R started with `&` ignores SIGINT, and the interrupt test in `test-env_lock.R` then skips.
* Run the tests in a UTF-8 locale.
* The tests run in sandboxes. For any other R, micromamba or conda run, set `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `HOME` to temporary directories: the XDG variables win over `HOME`, and micromamba 2.9 and later writes to `$XDG_CACHE_HOME/conda`.

### 3. Documentation

* **Render the `README.md` from `README.qmd`:**
  * `just build-readme`

* **Update documentation (roxygen comments):**
  * `just document`

### 4. Code Linting and Styling

* **Lint the package:**
  * `just lint`

### 5. Package Check

* **Run a full R CMD check:**
  * `just check`
