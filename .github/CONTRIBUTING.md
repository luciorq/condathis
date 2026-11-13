# Contributing to condathis

This outlines how to propose a change to condathis.
For a detailed discussion on contributing to this and other R packages,
please see the [development contributing guide](https://rstd.io/tidy-contrib) and
our [code review principles](https://code-review.tidyverse.org/).

## Fixing typos

You can fix typos, spelling mistakes,
or grammatical errors in the documentation directly using the GitHub web interface,
as long as the changes are made in the _source_ file.
This generally means you'll need to edit [roxygen2 comments](https://roxygen2.r-lib.org/articles/roxygen2.html) in an `.R`,
not a `.Rd` file.
You can find the `.R` file that generates the `.Rd` by reading the comment in the first line.

## Bigger changes

If you want to make a bigger change,
it's a good idea to first file an issue and make sure someone from the team agrees that it's needed.
If you've found a bug, please file an issue that illustrates the bug with a minimal
[reprex](https://www.tidyverse.org/help/#reprex) (this will also help you write a unit test, if needed).
See our guide on [how to create a great issue](https://code-review.tidyverse.org/issues/) for more advice.

### Pull request process

* Fork the package and clone onto your computer.
  If you haven't done this before, we recommend using
  `usethis::create_from_github("luciorq/condathis", fork = TRUE)`.

* Install all development dependencies with `devtools::install_dev_deps()`,
  and then make sure the package passes R CMD check
  by running `devtools::check()`.
  You need R 4.3 or later and the [Quarto](https://quarto.org) command
  line tool, which builds the vignettes.
  If R CMD check doesn't pass cleanly,
  it's a good idea to ask for help before continuing.
  `devtools::check()`, `devtools::test()` and `testthat::test_local()`
  set `NOT_CRAN=true` when it is unset, so they run the full test suite:
  it needs the internet to download micromamba and Conda packages, and it
  runs in temporary sandboxes.
  To run only the tests that CRAN runs, set `NOT_CRAN=false`, for example
  with `Sys.setenv(NOT_CRAN = "false")` before `devtools::test()`.

* Run the tests in a UTF-8 locale: under the C locale, a pip test in
  `test-list_packages_pypi.R` cannot read pip's JSON output.
  Start R in the foreground: an R started in the background (with `&`)
  ignores interrupts, and the interrupt test in `test-env_lock.R` then
  skips.
  `testthat::skip_if_offline()` looks up a host name itself: behind a
  proxy that looks up names for you, the network tests skip although
  downloads work.

* Create a Git branch for your pull request (PR).
  We recommend using `usethis::pr_init("brief-description-of-change")`.

* Make your changes, commit to git, and then create a PR by running
  `usethis::pr_push()`, and following the prompts in your browser.
  The title of your PR should briefly describe the change.
  The body of your PR should contain `Fixes #issue-number`.

* For user-facing changes, add a bullet under the development version
  heading at the top of `NEWS.md`, in the section that fits
  (such as Breaking changes).
  Follow the style described in <https://style.tidyverse.org/news.html>.

### Code style

* New code should follow the tidyverse [style guide](https://style.tidyverse.org).
  Format R code with [Air](https://posit-dev.github.io/air/)
  (`air format <file>`), and please don't reformat code that has
  nothing to do with your PR.

* We use [roxygen2](https://CRAN.R-project.org/package=roxygen2),
  with [Markdown syntax](https://roxygen2.r-lib.org/articles/rd-formatting.html),
  for documentation.

* We use [testthat](https://CRAN.R-project.org/package=testthat) for unit tests.
  Contributions with test cases included are easier to accept.

## Code of Conduct

Please note that the condathis project is released with a
[Contributor Code of Conduct](./CODE_OF_CONDUCT.md) derived from the [Contributor Covenant](https://www.contributor-covenant.org/) v2.1.
By contributing to this project you agree to abide by its terms.
