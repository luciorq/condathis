# This file is part of the standard setup for testthat.
# It is recommended that you do not modify it.
#
# Where should you do additional test configuration?
# Learn more about the roles of various files in:
# * https://r-pkgs.org/tests.html
# * https://testthat.r-lib.org/reference/test_package.html#special-files

library(testthat)
library(condathis)

# On CRAN, the tests run in one process. Parallel workers, with the
# processes that the tests start, can use more than 2.5 times as much CPU
# time as elapsed time, which CRAN's checks report.
if (!identical(Sys.getenv("NOT_CRAN"), "true")) {
  Sys.setenv(TESTTHAT_PARALLEL = "false")
}

testthat::test_check("condathis")
