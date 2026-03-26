# Tests for parse_match_spec following CEP 29 and libmambapy output
# See: https://conda.org/learn/ceps/cep-0029
# See: https://github.com/mamba-org/mamba/blob/main/libmamba/src/specs/match_spec.cpp

# =============================================================================
# Unit tests: No network, no skip. Expected values from libmambapy calibration.
# =============================================================================

testthat::test_that("parse_match_spec rejects invalid input", {
  testthat::expect_error(
    parse_match_spec(NULL),
    class = "condathis_parse_match_spec_invalid_input"
  )
  testthat::expect_error(
    parse_match_spec(42),
    class = "condathis_parse_match_spec_invalid_input"
  )
  testthat::expect_error(
    parse_match_spec(c("a", "b")),
    class = "condathis_parse_match_spec_invalid_input"
  )
})


testthat::test_that("parse_match_spec: bare package name 'numpy'", {
  res <- parse_match_spec("numpy")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$name_space, "")
  testthat::expect_equal(res$channel, "None")
  testthat::expect_equal(res$channel_location, "None")
  testthat::expect_equal(res$channel_platform_filters, "None")
  testthat::expect_equal(res$version, "=*")
  testthat::expect_equal(res$build_string, "*")
  testthat::expect_equal(res$platforms, "None")
  testthat::expect_equal(res$track_features, "None")
})


testthat::test_that("parse_match_spec: channel::name 'conda-forge::numpy'", {
  res <- parse_match_spec("conda-forge::numpy")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$name_space, "")
  testthat::expect_equal(res$channel, "conda-forge")
  testthat::expect_equal(res$channel_location, "conda-forge")
  testthat::expect_equal(res$channel_platform_filters, "set()")
  testthat::expect_equal(res$version, "=*")
  testthat::expect_equal(res$build_string, "*")
  testthat::expect_equal(res$platforms, "None")
  testthat::expect_equal(res$track_features, "None")
})


testthat::test_that("parse_match_spec: channel/subdir::name 'conda-forge/linux-64::numpy>=1.8'", {
  res <- parse_match_spec("conda-forge/linux-64::numpy>=1.8")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$channel, "conda-forge[linux-64]")
  testthat::expect_equal(res$channel_location, "conda-forge")
  testthat::expect_equal(res$channel_platform_filters, "{'linux-64'}")
  testthat::expect_equal(res$version, ">=1.8")
  testthat::expect_equal(res$build_string, "*")
})


testthat::test_that("parse_match_spec: fuzzy version 'numpy=1.8'", {
  res <- parse_match_spec("numpy=1.8")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, "=1.8")
  testthat::expect_equal(res$build_string, "*")
})


testthat::test_that("parse_match_spec: exact version with space 'numpy 1.8'", {
  res <- parse_match_spec("numpy 1.8")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, "==1.8")
  testthat::expect_equal(res$build_string, "*")
})


testthat::test_that("parse_match_spec: exact version with == 'numpy==1.8'", {
  res <- parse_match_spec("numpy==1.8")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, "==1.8")
  testthat::expect_equal(res$build_string, "*")
})


testthat::test_that("parse_match_spec: space-separated version and build 'numpy 1.8 py27_0'", {
  res <- parse_match_spec("numpy 1.8 py27_0")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, "==1.8")
  testthat::expect_equal(res$build_string, "py27_0")
})


testthat::test_that("parse_match_spec: fuzzy version with build 'numpy=1.8=py27_0'", {
  res <- parse_match_spec("numpy=1.8=py27_0")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, "=1.8")
  testthat::expect_equal(res$build_string, "py27_0")
})


testthat::test_that("parse_match_spec: trailing .* stripped 'numpy=1.8.*'", {
  res <- parse_match_spec("numpy=1.8.*")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, "=1.8")
  testthat::expect_equal(res$build_string, "*")
})


testthat::test_that("parse_match_spec: bare trailing * 'python 1.8*'", {
  res <- parse_match_spec("python 1.8*")
  testthat::expect_equal(res$name, "python")
  testthat::expect_equal(res$version, "=1.8")
  testthat::expect_equal(res$build_string, "*")
})


testthat::test_that("parse_match_spec: glob build 'blas * mkl'", {
  res <- parse_match_spec("blas * mkl")
  testthat::expect_equal(res$name, "blas")
  testthat::expect_equal(res$version, "=*")
  testthat::expect_equal(res$build_string, "mkl")
})


testthat::test_that("parse_match_spec: >=, >, <, !=, ~= operators", {
  r1 <- parse_match_spec("numpy>=1.8")
  testthat::expect_equal(r1$version, ">=1.8")

  r2 <- parse_match_spec("numpy>1.8")
  testthat::expect_equal(r2$version, ">1.8")

  r3 <- parse_match_spec("numpy<2.0")
  testthat::expect_equal(r3$version, "<2.0")

  r4 <- parse_match_spec("numpy!=1.8")
  testthat::expect_equal(r4$version, "!=1.8")

  r5 <- parse_match_spec("numpy~=1.8")
  testthat::expect_equal(r5$version, "~=1.8")
})


testthat::test_that("parse_match_spec: version range 'numpy>=1.8,<2.0'", {
  res <- parse_match_spec("numpy>=1.8,<2.0")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, ">=1.8,<2.0")
  testthat::expect_equal(res$build_string, "*")
})


testthat::test_that("parse_match_spec: bracket version override 'numpy[version=\">=1.8\"]'", {
  res <- parse_match_spec("numpy[version=\">=1.8\"]")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, ">=1.8")
})


testthat::test_that("parse_match_spec: bracket build override 'numpy[build=py27*]'", {
  res <- parse_match_spec("numpy[build=py27*]")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$build_string, "py27*")
})


testthat::test_that("parse_match_spec: bracket channel override", {
  res <- parse_match_spec("numpy[channel=conda-forge]")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$channel, "conda-forge")
  testthat::expect_equal(res$channel_location, "conda-forge")
  testthat::expect_equal(res$channel_platform_filters, "set()")
})


testthat::test_that("parse_match_spec: bracket subdir without channel sets platforms", {
  res <- parse_match_spec("numpy[subdir=linux-64]")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$platforms, "{'linux-64'}")
  testthat::expect_equal(res$channel, "None")
})


testthat::test_that("parse_match_spec: bracket subdir with channel sets channel platform_filters", {
  res <- parse_match_spec("conda-forge::numpy[subdir=osx-64]")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$channel, "conda-forge[osx-64]")
  testthat::expect_equal(res$channel_location, "conda-forge")
  testthat::expect_equal(res$channel_platform_filters, "{'osx-64'}")
})


testthat::test_that("parse_match_spec: md5 bracket allocates ExtraMembers -> track_features='set()'", {
  res <- parse_match_spec("numpy[md5=abc123]")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$track_features, "set()")
})


testthat::test_that("parse_match_spec: complex spec with commas and pipes", {
  spec <- "bioconda/linux-64:python >=3.11,<3.14|3.12[channel=conda-forge,subdir=osx-64,namespace=yyy]"
  res <- parse_match_spec(spec)
  testthat::expect_equal(res$name, "python")
  testthat::expect_equal(res$name_space, "bioconda/linux-64")
  testthat::expect_equal(res$channel, "conda-forge[osx-64]")
  testthat::expect_equal(res$channel_location, "conda-forge")
  testthat::expect_equal(res$channel_platform_filters, "{'osx-64'}")
  testthat::expect_equal(res$version, ">=3.11,(<3.14|==3.12)")
})


testthat::test_that("parse_match_spec: empty channel in '::numpy' gives no channel", {
  res <- parse_match_spec("::numpy")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$channel, "None")
  testthat::expect_equal(res$name_space, "")
})


testthat::test_that("parse_match_spec: namespace only 'ns:numpy'", {
  res <- parse_match_spec("ns:numpy")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$name_space, "ns")
  testthat::expect_equal(res$channel, "None")
})


testthat::test_that("parse_match_spec: channel::namespace:spec 'conda-forge:ns:numpy'", {
  res <- parse_match_spec("conda-forge:ns:numpy")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$name_space, "ns")
  testthat::expect_equal(res$channel, "conda-forge")
  testthat::expect_equal(res$channel_location, "conda-forge")
})


testthat::test_that("parse_match_spec: strip spaces after operators 'numpy >= 1.8'", {
  res <- parse_match_spec("numpy >= 1.8")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, ">=1.8")
})


testthat::test_that("parse_match_spec: bioconda::samtools", {
  res <- parse_match_spec("bioconda::samtools")
  testthat::expect_equal(res$name, "samtools")
  testthat::expect_equal(res$channel, "bioconda")
  testthat::expect_equal(res$channel_location, "bioconda")
  testthat::expect_equal(res$channel_platform_filters, "set()")
  testthat::expect_equal(res$version, "=*")
  testthat::expect_equal(res$build_string, "*")
})


testthat::test_that("parse_match_spec: formatted_spec canonical output", {
  # Simple name only

  r1 <- parse_match_spec("numpy")
  testthat::expect_equal(r1$formatted_spec, "numpy")

  # Channel with version
  r2 <- parse_match_spec("conda-forge::numpy>=1.8")
  testthat::expect_equal(r2$formatted_spec, "conda-forge::numpy>=1.8")

  # Fuzzy version with build -> positional format
  r3 <- parse_match_spec("numpy=1.8=py27_0")
  testthat::expect_equal(r3$formatted_spec, "numpy=1.8=py27_0")
})


testthat::test_that("parse_match_spec: formatted_spec with complex version uses brackets", {
  res <- parse_match_spec("numpy>=1.8,<2.0")
  # Complex version (has comma) -> bracket form
  testthat::expect_match(res$formatted_spec, "\\[version=")
})


testthat::test_that("parse_match_spec: bare version with trailing .* 'numpy 1.8.*'", {
  res <- parse_match_spec("numpy 1.8.*")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, "=1.8")
})


testthat::test_that("parse_match_spec: comment stripping", {
  res <- parse_match_spec("numpy >=1.8 # this is a comment")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, ">=1.8")
})


testthat::test_that("parse_match_spec: version with pipe 'numpy>=1.0|<0.5'", {
  res <- parse_match_spec("numpy>=1.0|<0.5")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, ">=1.0|<0.5")
})


testthat::test_that("parse_match_spec: track_features bracket", {
  res <- parse_match_spec("numpy[track_features=mkl]")
  testthat::expect_equal(res$track_features, "{'mkl'}")
})


testthat::test_that("parse_match_spec: multiple bracket attributes", {
  res <- parse_match_spec("numpy[version=\">=1.8\",build=py27*]")
  testthat::expect_equal(res$name, "numpy")
  testthat::expect_equal(res$version, ">=1.8")
  testthat::expect_equal(res$build_string, "py27*")
})


testthat::test_that("parse_match_spec: result is a 10-element named list", {
  res <- parse_match_spec("numpy")
  expected_names <- c(
    "formatted_spec",
    "name",
    "name_space",
    "channel",
    "channel_location",
    "channel_platform_filters",
    "version",
    "build_string",
    "platforms",
    "track_features"
  )
  testthat::expect_type(res, "list")
  testthat::expect_length(res, 10L)
  testthat::expect_named(res, expected_names)
})


testthat::test_that("parse_match_spec: all values are character strings", {
  res <- parse_match_spec("conda-forge::numpy>=1.8")
  for (nm in names(res)) {
    testthat::expect_type(res[[nm]], "character")
  }
})


testthat::test_that("parse_match_spec: channel/subdir with bracket subdir override", {
  res <- parse_match_spec("conda-forge/linux-64::numpy[subdir=osx-64]")

  # The slash-style subdir sets initial filters, bracket subdir does not
  testthat::expect_equal(res$channel_location, "conda-forge")

  # override when filters already exist
  testthat::expect_equal(res$channel_platform_filters, "{'linux-64'}")
})


testthat::test_that("parse_match_spec: namespace in brackets", {
  res <- parse_match_spec("numpy[namespace=myns]")
  testthat::expect_equal(res$name_space, "myns")
})


# =============================================================================
# Integration test: compare R output to libmambapy (skip on CI)
# =============================================================================

testthat::test_that("parse_match_spec matches libmambapy implementation", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  testthat::skip_on_ci()

  # Load helper function
  base::source(testthat::test_path("libmamba_wrappers.R"))

  test_specs <- c(
    "numpy",
    "conda-forge::numpy",
    "conda-forge/linux-64::numpy>=1.8",
    "numpy=1.8",
    "numpy 1.8",
    "numpy==1.8",
    "numpy 1.8 py27_0",
    "numpy=1.8=py27_0",
    "numpy=1.8.*",
    "python 1.8*",
    "blas * mkl",
    "numpy>=1.8",
    "numpy>=1.8,<2.0",
    "numpy[version=\">=1.8\"]",
    "numpy[build=py27*]",
    "numpy[channel=conda-forge]",
    "numpy[md5=abc123]",
    "bioconda::samtools",
    "numpy >= 1.8",
    "numpy!=1.8",
    "numpy~=1.8",
    "numpy>1.8",
    "numpy<2.0",
    "conda-forge/linux-64::numpy[subdir=osx-64]"
  )

  for (spec_str in test_specs) {
    ms_rstats <- parse_match_spec(spec_str)
    ms_py <- parse_match_spec_py(spec_str)
    testthat::expect_equal(
      ms_rstats,
      ms_py,
      info = paste0("Spec: '", spec_str, "'")
    )
  }
})
