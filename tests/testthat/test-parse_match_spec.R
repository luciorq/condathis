# Tests for parse_match_spec following libmamba implementation
# See: https://github.com/mamba-org/mamba/blob/main/libmamba/src/specs/match_spec.cpp

testthat::test_that("parse_match_spec matches libmambapy implementation", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()
  testthat::skip_on_ci()

  condathis::create_env(
    packages = "conda-forge::libmambapy>=2.5.0",
    env_name = "libmambapy-test-env",
    verbose = "silent",
    overwrite = TRUE
  )

  parse_match_spec_py <- function(
    package_string,
    env_name = "libmambapy-test-env",
    verbose = "silent"
  ) {
    run_res <- condathis::run(
      "python",
      "-c",
      paste0(
        "from libmambapy.specs import MatchSpec as msp;ms=msp.parse('",
        package_string,
        "');",
        "print(str(ms));",
        "print(str(ms.name));",
        "print(str(ms.name_space));",
        "print(str(ms.channel));",
        "print(str(ms.channel.location));",
        "print(str(ms.channel.platform_filters));",
        "print(str(ms.version));",
        "print(str(ms.build_string));",
        "print(str(ms.platforms));",
        "print(str(ms.track_features));"
      ),
      env_name = env_name,
      verbose = verbose
    )
    output_lines <- condathis::parse_output(run_res, stream = "stdout")
    return(list(
      formatted_spec = output_lines[1],
      name = output_lines[2],
      name_space = output_lines[3],
      channel = output_lines[4],
      channel_location = output_lines[5],
      channel_platform_filters = output_lines[6],
      version = output_lines[7],
      build_string = output_lines[8],
      platforms = output_lines[9],
      track_features = output_lines[10]
    ))
  }

  spec_str <- "bioconda/linux-64:python >=3.11,<3.14|3.12[channel=conda-forge,subdir=osx-64,namespace=yyy]"

  spec_r <- parse_match_spec(spec_str)
  spec_py <- parse_match_spec_py(spec_str)

  testthat::expect_equal(spec_r, spec_py)
})
