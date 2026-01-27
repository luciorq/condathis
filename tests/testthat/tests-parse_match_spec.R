# Tests for parse_match_spec following libmamba implementation
# See: https://github.com/mamba-org/mamba/blob/main/libmamba/src/specs/match_spec.cpp

testthat::test_that("parse_match_spec parses basic package name", {
  spec <- parse_match_spec("numpy")
  expect_null(spec$channel)
  expect_null(spec$subdir)
  expect_null(spec$namespace)
  expect_equal(spec$name, "numpy")
  expect_null(spec$version)
  expect_null(spec$build)
})

testthat::test_that("parse_match_spec parses space-separated name version build", {
  # "foo 1.0 py27_0" -> name=foo, version=1.0, build=py27_0
  spec <- parse_match_spec("foo 1.0 py27_0")
  expect_null(spec$channel)
  expect_equal(spec$name, "foo")
  expect_equal(spec$version, "1.0")
  expect_equal(spec$build, "py27_0")
  expect_equal(spec$version_min, "1.0")
  expect_equal(spec$version_max, "1.0")

  # Uppercase name
  spec <- parse_match_spec("FOO 1.0 py27_0")
  expect_equal(spec$name, "FOO")
  expect_equal(spec$version, "1.0")
  expect_equal(spec$build, "py27_0")
})

testthat::test_that("parse_match_spec parses version with glob", {
  # "numpy 1.8*"
  spec <- parse_match_spec("numpy 1.8*")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, "1.8*")
  expect_equal(spec$version_min, "1.8")
  expect_null(spec$version_max)
  expect_null(spec$build)
})

testthat::test_that("parse_match_spec parses space-separated version (no glob appended)", {
  # "numpy 1.8.1" -> version is "1.8.1" (libmamba does NOT append *)
  spec <- parse_match_spec("numpy 1.8.1")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, "1.8.1")
  expect_equal(spec$version_min, "1.8.1")
  expect_equal(spec$version_max, "1.8.1")
  expect_null(spec$build)
})

testthat::test_that("parse_match_spec parses version with operators", {
  # "numpy >=1.8"
  spec <- parse_match_spec("numpy >=1.8")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, ">=1.8")
  expect_equal(spec$version_min, "1.8")
  expect_null(spec$version_max)
  expect_null(spec$build)

  # "numpy ==1.8.1"
  spec <- parse_match_spec("numpy ==1.8.1")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, "==1.8.1")
  expect_equal(spec$version_min, "1.8.1")
  expect_equal(spec$version_max, "1.8.1")
  expect_null(spec$build)
})

testthat::test_that("parse_match_spec parses OR operator in version (|)", {
  # "numpy 1.8|1.9" -> version with OR, NOT version|build
  # In libmamba, | is OR operator for versions
  spec <- parse_match_spec("numpy 1.8|1.9")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, "1.8|1.9")
  expect_null(spec$build)
})

testthat::test_that("parse_match_spec parses version range", {
  # "numpy >=1.8,<2"
  spec <- parse_match_spec("numpy >=1.8,<2")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, ">=1.8,<2")
  expect_equal(spec$version_min, "1.8")
  expect_equal(spec$version_max, "2")
  expect_null(spec$build)
})

testthat::test_that("parse_match_spec parses version range with build", {
  # "numpy >=1.8,<2 py27_0" -> space-separated build
  spec <- parse_match_spec("numpy >=1.8,<2 py27_0")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, ">=1.8,<2")
  expect_equal(spec$build, "py27_0")
  expect_equal(spec$version_min, "1.8")
  expect_equal(spec$version_max, "2")
})

testthat::test_that("parse_match_spec parses =-separated version and build", {
  # "numpy=1.8.1=py27_0"
  spec <- parse_match_spec("numpy=1.8.1=py27_0")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, "=1.8.1")
  expect_equal(spec$build, "py27_0")
  expect_equal(spec$version_min, "1.8.1")
  expect_equal(spec$version_max, "1.8.1")

  # "numpy 1.8.1 py27_0" (space-separated)
  spec <- parse_match_spec("numpy 1.8.1 py27_0")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, "1.8.1")
  expect_equal(spec$build, "py27_0")
})

testthat::test_that("parse_match_spec parses channel::spec format", {
  # "conda-forge::numpy>=1.8<2"
  spec <- parse_match_spec("conda-forge::numpy>=1.8<2")
  expect_equal(spec$channel, "conda-forge")
  expect_null(spec$subdir)
  expect_null(spec$namespace)
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, ">=1.8<2")
  expect_equal(spec$version_min, "1.8")
  expect_equal(spec$version_max, "2")

  # "conda-forge::numpy>=1.8,<2" (with comma)
  spec <- parse_match_spec("conda-forge::numpy>=1.8,<2")
  expect_equal(spec$channel, "conda-forge")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, ">=1.8,<2")
  expect_equal(spec$version_min, "1.8")
  expect_equal(spec$version_max, "2")
})

testthat::test_that("parse_match_spec parses channel/subdir::spec format", {
  # "conda-forge/linux-64::numpy"
  spec <- parse_match_spec("conda-forge/linux-64::numpy")
  expect_equal(spec$channel, "conda-forge")
  expect_equal(spec$subdir, "linux-64")
  expect_equal(spec$name, "numpy")
})

testthat::test_that("parse_match_spec parses wildcard version", {
  # "numpy=*"
  spec <- parse_match_spec("numpy=*")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, "=*")
  expect_null(spec$version_min)
  expect_null(spec$version_max)
  expect_null(spec$build)
})

testthat::test_that("parse_match_spec parses build with glob", {
  # "numpy=1.11.2=*nomkl*"
  spec <- parse_match_spec("numpy=1.11.2=*nomkl*")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, "=1.11.2")
  expect_equal(spec$build, "*nomkl*")
  expect_equal(spec$version_min, "1.11.2")
  expect_equal(spec$version_max, "1.11.2")
})

testthat::test_that("parse_match_spec handles trailing = (faulty specs)", {
  # "numpy=" -> stripped to "numpy"
  spec <- parse_match_spec("numpy=")
  expect_equal(spec$name, "numpy")
  expect_null(spec$version)
  expect_null(spec$build)
})

testthat::test_that("parse_match_spec parses bracket attributes", {
  # "numpy[build=py311*]"
  spec <- parse_match_spec("numpy[build=py311*]")
  expect_equal(spec$name, "numpy")
  expect_null(spec$version)
  expect_equal(spec$build, "py311*")

  # "numpy[build=*h8685306*]"
  spec <- parse_match_spec("numpy[build=*h8685306*]")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$build, "*h8685306*")

  # "numpy[version=1.8]"
  spec <- parse_match_spec("numpy[version=1.8]")
  expect_equal(spec$name, "numpy")
  expect_equal(spec$version, "1.8")
})

testthat::test_that("parse_match_spec handles faulty bracket specs", {
  # "numpy=[build=py311*]" -> libmamba strips trailing = before brackets
  spec <- parse_match_spec("numpy=[build=py311*]")
  expect_equal(spec$name, "numpy")
  expect_null(spec$version)
  expect_equal(spec$build, "py311*")
})

testthat::test_that("parse_match_spec first bracket attribute wins", {
  # "numpy[build=py311*][build=*h8685306*][build=allala]"
  # First build value should be used (rightmost bracket is parsed first, but
  # each key only set once)
  spec <- parse_match_spec(
    "numpy[build=py311*][build=*h8685306*][build=allala]"
  )
  expect_equal(spec$name, "numpy")
  # When parsing backwards, the rightmost bracket is processed first
  # So "allala" is set first, then subsequent builds are ignored
  expect_equal(spec$build, "allala")
})

testthat::test_that("parse_match_spec parses complex channel/subdir/namespace specs", {
  # "conda-forge/linux-64::scikit-learn"
  spec <- parse_match_spec("conda-forge/linux-64::scikit-learn")
  expect_equal(spec$channel, "conda-forge")
  expect_equal(spec$subdir, "linux-64")
  expect_equal(spec$name, "scikit-learn")
})

testthat::test_that("parse_match_spec errors on empty input", {
  expect_error(
    parse_match_spec(""),
    class = "condathis_parse_match_spec_empty_string"
  )
  expect_error(
    parse_match_spec(NULL),
    class = "condathis_parse_match_spec_empty_string"
  )
})

# Comprehensive test list based on libmamba test patterns
allowed_specs_list <- list(
  list(
    spec_string = "foo 1.0 py27_0",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "foo",
      version = "1.0",
      version_min = "1.0",
      version_max = "1.0",
      build = "py27_0"
    )
  ),
  list(
    spec_string = "FOO 1.0 py27_0",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "FOO",
      version = "1.0",
      version_min = "1.0",
      version_max = "1.0",
      build = "py27_0"
    )
  ),
  list(
    spec_string = "numpy",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = NULL,
      version_min = NULL,
      version_max = NULL,
      build = NULL
    )
  ),
  list(
    spec_string = "numpy 1.8*",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = "1.8*",
      version_min = "1.8",
      version_max = NULL,
      build = NULL
    )
  ),
  list(
    spec_string = "numpy 1.8.1",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = "1.8.1",
      version_min = "1.8.1",
      version_max = "1.8.1",
      build = NULL
    )
  ),
  list(
    spec_string = "numpy >=1.8",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = ">=1.8",
      version_min = "1.8",
      version_max = NULL,
      build = NULL
    )
  ),
  list(
    spec_string = "numpy ==1.8.1",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = "==1.8.1",
      version_min = "1.8.1",
      version_max = "1.8.1",
      build = NULL
    )
  ),
  # In libmamba, | is OR operator, NOT version|build separator
  list(
    spec_string = "numpy 1.8|1.9",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = "1.8|1.9",
      version_min = NULL,
      version_max = NULL,
      build = NULL
    )
  ),
  list(
    spec_string = "numpy >=1.8,<2",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = ">=1.8,<2",
      version_min = "1.8",
      version_max = "2",
      build = NULL
    )
  ),
  list(
    spec_string = "numpy 1.8.1 py27_0",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = "1.8.1",
      version_min = "1.8.1",
      version_max = "1.8.1",
      build = "py27_0"
    )
  ),
  list(
    spec_string = "numpy=1.8.1=py27_0",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = "=1.8.1",
      version_min = "1.8.1",
      version_max = "1.8.1",
      build = "py27_0"
    )
  ),
  list(
    spec_string = "conda-forge::numpy>=1.8<2",
    expected = list(
      channel = "conda-forge",
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = ">=1.8<2",
      version_min = "1.8",
      version_max = "2",
      build = NULL
    )
  ),
  list(
    spec_string = "conda-forge::numpy>=1.8,<2",
    expected = list(
      channel = "conda-forge",
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = ">=1.8,<2",
      version_min = "1.8",
      version_max = "2",
      build = NULL
    )
  ),
  list(
    spec_string = "numpy=1.11.2=*nomkl*",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = "=1.11.2",
      version_min = "1.11.2",
      version_max = "1.11.2",
      build = "*nomkl*"
    )
  ),
  list(
    spec_string = "numpy[build=py311*]",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = NULL,
      version_min = NULL,
      version_max = NULL,
      build = "py311*"
    )
  ),
  list(
    spec_string = "numpy[build=*h8685306*]",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = NULL,
      version_min = NULL,
      version_max = NULL,
      build = "*h8685306*"
    )
  ),
  list(
    spec_string = "numpy=[build=py311*]",
    expected = list(
      channel = NULL,
      subdir = NULL,
      namespace = NULL,
      name = "numpy",
      version = NULL,
      version_min = NULL,
      version_max = NULL,
      build = "py311*"
    )
  ),
  list(
    spec_string = "conda-forge/linux-64::scikit-learn[build=py311*]",
    expected = list(
      channel = "conda-forge",
      subdir = "linux-64",
      namespace = NULL,
      name = "scikit-learn",
      version = NULL,
      version_min = NULL,
      version_max = NULL,
      build = "py311*"
    )
  )
)

for (i in seq_along(allowed_specs_list)) {
  spec_data <- allowed_specs_list[[i]]
  spec_string <- spec_data$spec_string
  expected <- spec_data$expected

  test_name <- paste0("parse_match_spec: ", spec_string)
  test_that(test_name, {
    parsed_spec <- parse_match_spec(spec_string)

    expect_equal(
      parsed_spec$channel,
      expected$channel,
      label = paste("channel for", spec_string)
    )
    expect_equal(
      parsed_spec$subdir,
      expected$subdir,
      label = paste("subdir for", spec_string)
    )
    expect_equal(
      parsed_spec$namespace,
      expected$namespace,
      label = paste("namespace for", spec_string)
    )
    expect_equal(
      parsed_spec$name,
      expected$name,
      label = paste("name for", spec_string)
    )
    expect_equal(
      parsed_spec$version,
      expected$version,
      label = paste("version for", spec_string)
    )
    expect_equal(
      parsed_spec$version_min,
      expected$version_min,
      label = paste("version_min for", spec_string)
    )
    expect_equal(
      parsed_spec$version_max,
      expected$version_max,
      label = paste("version_max for", spec_string)
    )
    expect_equal(
      parsed_spec$build,
      expected$build,
      label = paste("build for", spec_string)
    )
  })
}
