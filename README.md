
# condathis

<!-- badges: start -->
<!-- badges: end -->

## `condathis` R package

Run anything that is available through conda environments.

Traditionally [Conda Environments][conda-env-ref] have been designed to solve a problem related to Python Programming and specially tailored for interactive usage.

With `condathis` we want to leverage another great functionality of Conda environments that is running CLI software in isolated environments, without affecting (and also not being affected by) the main R environment.

This is especially relevant to the Bioinformatics and Computational Biology fields where most of the preprocessing of raw data files is made using Linux/Unix command line tools that benefit from running on isolation.
Where in the later step data is imported into R for interactive analysis.

The focus of this package is to support CLI tools installed inside conda environments.

Providing an API to call those tools in isolation from the main R process.

Despite the name, the main interface we use to access software installed in conda environments is actually [micromamba][micromamba-ref], a lightweight and open-source reimplementation of the conda package manager.

Since this package **is not intended to solve the problem of running Python conde**, `micromamba` is also an advantage tool, since it is lighter and does not come with a default version of Python.
If you intend to run Python code chunks or scripts side by side with R code, in activated Conda environments, check [reticulate][reticulate-ref] or [basilisk][basilisk-ref], as they were built to provide this exact solution.

This tool can even be used for running R scripts in separate environments.

---

[conda-env-ref]: https://conda.io/projects/conda/en/latest/user-guide/getting-started.html
[micromamba-ref]: https://mamba.readthedocs.io/en/latest/user_guide/micromamba.html
[reticulate-ref]: https://rstudio.github.io/reticulate/
[basilisk-ref]: https://www.bioconductor.org/packages/release/bioc/html/basilisk.html
