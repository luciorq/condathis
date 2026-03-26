create_libmambapy_env <- function(
  package_string = "conda-forge::libmambapy>=2.5.0",
  env_name = "libmambapy-test-env",
  verbose = "silent",
  overwrite = FALSE
) {
  if (isFALSE(env_exists(env_name, verbose = verbose))) {
    create_env(
      packages = package_string,
      env_name = env_name,
      verbose = verbose,
      overwrite = overwrite
    )
  }
}

parse_match_spec_py <- function(
  package_string,
  env_name = "libmambapy-test-env",
  verbose = "silent"
) {
  create_libmambapy_env(
    env_name = env_name,
    verbose = verbose
  )
  py_code <- paste0(
    "from libmambapy.specs import MatchSpec as msp; ",
    "ms=msp.parse('",
    package_string,
    "'); ",
    "print(str(ms)); ",
    "print(str(ms.name)); ",
    "print(str(ms.name_space)); ",
    "ch=ms.channel; ",
    "print('None' if ch is None else str(ch)); ",
    "print('None' if ch is None else str(ch.location)); ",
    "print('None' if ch is None else str(ch.platform_filters)); ",
    "print(str(ms.version)); ",
    "print(str(ms.build_string)); ",
    "print(str(ms.platforms)); ",
    "print(str(ms.track_features))"
  )

  run_res <- run(
    "python",
    "-c",
    py_code,
    env_name = env_name,
    verbose = verbose
  )
  output_lines <- parse_output(run_res, stream = "stdout")
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

ms_compare_version_py <- function(
  version_string,
  spec_string,
  env_name = "libmambapy-test-env",
  verbose = "silent"
) {
  create_libmambapy_env(
    env_name = env_name,
    verbose = verbose
  )
  py_code <- paste0(
    "import libmambapy.specs as specs; ",
    "version_to_check = specs.Version.parse('",
    version_string,
    "'); ",
    "v_spec = specs.VersionSpec.parse('",
    spec_string,
    "'); ",
    "is_satisfied = v_spec.contains(version_to_check); ",
    "print(is_satisfied)"
  )

  run_res <- run(
    "python",
    "-c",
    py_code,
    env_name = env_name,
    verbose = verbose
  )
  output_lines <- parse_output(run_res, stream = "stdout")
  return(identical(output_lines[1], "True"))
}
