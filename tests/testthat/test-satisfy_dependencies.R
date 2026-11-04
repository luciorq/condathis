testthat::test_that("satisfies_dependencies returns null for null input", {
  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = character(0),
    env_name = "numpy-test-env"
  )
  testthat::expect_equal(is_satisfied_vector, logical(0))
})

testthat::test_that("satisfies_dependencies returns correct results", {
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  if (env_exists("numpy-test-env")) {
    remove_env("numpy-test-env", verbose = "silent")
  }

  pkg_str_vector_test <- c("python", "conda-forge::numpy>=1.8,<2|1.9")

  create_env(
    pkg_str_vector_test,
    env_name = "numpy-test-env",
    verbose = "silent",
    overwrite = FALSE
  )

  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = pkg_str_vector_test,
    env_name = "numpy-test-env"
  )

  testthat::expect_length(is_satisfied_vector, length(pkg_str_vector_test))

  testthat::expect_type(is_satisfied_vector, "logical")
  # is not an S3 class object
  testthat::expect_s3_class(is_satisfied_vector, NA)

  testthat::expect_true(all(is_satisfied_vector))

  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = c(
      pkg_str_vector_test,
      "conda-forge::pandas==1.8.1"
    ),
    env_name = "numpy-test-env"
  )

  testthat::expect_length(is_satisfied_vector, length(pkg_str_vector_test) + 1L)

  testthat::expect_false(is_satisfied_vector[length(is_satisfied_vector)])

  # Package names compare without case, as in libmamba: micromamba
  # installs `python` for the spec "PYTHON".
  is_satisfied_vector <- satisfies_dependencies(
    pkg_str_vector = "PYTHON",
    env_name = "numpy-test-env"
  )

  testthat::expect_length(is_satisfied_vector, 1L)
  testthat::expect_true(is_satisfied_vector)
})

testthat::test_that("the create_env() shortcut checks build, channel, brackets and platform", {
  # Regression test: only name and version were compared, so create_env()
  # reported success without installing anything for requests that pinned
  # a different build, channel, bracket constraint or platform.
  installed <- data.frame(
    name = "zlib",
    version = "1.3.2",
    build_string = "h25fd6f3_3",
    build_number = 3L,
    channel = "conda-forge"
  )
  sat <- function(spec, channels = NULL) {
    requested <- if (!is.null(channels)) normalize_channel_name(channels)
    spec_satisfied_by(spec, installed, requested)
  }
  testthat::expect_true(sat("zlib"))
  testthat::expect_true(sat("zlib>=1.3"))
  testthat::expect_true(sat("zlib=1.3.2=h25fd6f3_3"))
  testthat::expect_true(sat("zlib=1.3.2=h25fd*"))
  testthat::expect_false(sat("zlib=*=this_build_does_not_exist"))
  testthat::expect_true(sat("conda-forge::zlib"))
  testthat::expect_false(sat("bioconda::zlib"))
  testthat::expect_false(sat("zlib[build_number=4]"))
  testthat::expect_true(sat(
    "zlib",
    channels = "https://conda.anaconda.org/conda-forge/"
  ))
  testthat::expect_false(sat("zlib", channels = "bioconda"))
})

testthat::test_that("package names compare without case", {
  # Regression test: names compared with case, so with decision D4 a second,
  # identical create_env("ZLIB", env_name = "x") aborted with
  # condathis_create_env_exists, although micromamba had installed `zlib`.
  installed <- data.frame(
    name = c("zlib", "pyyaml", "r-base"),
    version = c("1.3.2", "6.0.3", "4.5.1"),
    build_string = "h0_0",
    build_number = 0L,
    channel = "conda-forge"
  )
  sat <- function(spec) spec_satisfied_by(spec, installed, "conda-forge")
  testthat::expect_true(sat("ZLIB"))
  testthat::expect_true(sat("Zlib>=1.3"))
  testthat::expect_true(sat("PyYAML"))
  testthat::expect_true(sat("R-base=4.5"))
  testthat::expect_true(sat("conda-forge::PyYAML"))
  testthat::expect_false(sat("ZLIB<1"))
  testthat::expect_false(sat("PyYAML-extra"))
  testthat::expect_identical(
    packages_satisfied_by(c("ZLIB", "PyYAML"), installed, "conda-forge"),
    c(TRUE, TRUE)
  )
})

testthat::test_that("bracket constraints on version, build, build_number and channel are compared", {
  # Regression test: every spec with brackets counted as not satisfied, so
  # with decision D4 a second, identical create_env("python[version='>=3.11']",
  # env_name = "x") aborted with condathis_create_env_exists.
  installed <- data.frame(
    name = "zlib",
    version = "1.3.2",
    build_string = "h25fd6f3_3",
    build_number = 3L,
    channel = "conda-forge"
  )
  sat <- function(spec) spec_satisfied_by(spec, installed, "conda-forge")
  testthat::expect_true(sat("zlib[version='>=1.3']"))
  testthat::expect_true(sat("zlib[version=\">=1.3,<2\"]"))
  testthat::expect_false(sat("zlib[version='<1']"))
  testthat::expect_true(sat("zlib[build=h25fd*]"))
  testthat::expect_true(sat("zlib[build_string=h25fd6f3_3]"))
  testthat::expect_false(sat("zlib[build=h0_0]"))
  testthat::expect_true(sat("zlib[build_number=3]"))
  testthat::expect_true(sat("zlib[build_number='>=3']"))
  testthat::expect_true(sat("zlib[build_number='<4']"))
  testthat::expect_true(sat("zlib[build_number=*]"))
  testthat::expect_false(sat("zlib[build_number='>3']"))
  testthat::expect_false(sat("zlib[build_number=2]"))
  testthat::expect_false(sat("zlib[build_number=two]"))
  testthat::expect_true(sat("zlib 1.3.*[build_number=3]"))
  testthat::expect_true(sat("zlib[version='>=1.3', build_number=3]"))
  testthat::expect_false(sat("zlib[version='>=1.3', build_number=4]"))
  testthat::expect_true(sat("zlib[channel=conda-forge]"))
  testthat::expect_false(sat("zlib[channel=bioconda]"))
  # Keys that the package listing cannot answer never count as satisfied.
  testthat::expect_false(sat("zlib[md5=0123456789abcdef]"))
  testthat::expect_false(sat("zlib[sha256=abc]"))
  testthat::expect_false(sat("zlib[subdir=linux-64]"))
  testthat::expect_false(sat("zlib[url=https://example.org/zlib.conda]"))
  testthat::expect_false(sat("zlib[build_number=3, md5=abc]"))
})

testthat::test_that("build strings are compared only with letters, digits, `_`, `.` and `*`", {
  # Regression test: `utils::glob2rx()` read `?` as a wildcard and `+` as
  # a regular expression, and `"zlib=1.3.1=(("` failed with a raw
  # regular-expression error. micromamba 2.9.0 and 2.10.0 read the
  # characters `?+()[]{}|\^$` as a regular expression in their own dialect,
  # rattler reads `?` and `[...]` as glob wildcards when there is a `*`,
  # and `^...$` has a different regular-expression dialect in each tool,
  # so such build strings are not compared.
  testthat::expect_true(build_string_matches("h4ab18f5_1", "h4ab18f5_1"))
  testthat::expect_true(build_string_matches("h4ab*", "h4ab18f5_1"))
  testthat::expect_true(build_string_matches("*_1", "h4ab18f5_1"))
  testthat::expect_true(build_string_matches("*", "h4ab18f5_1"))
  testthat::expect_true(build_string_matches("h4**_1", "h4ab18f5_1"))
  testthat::expect_true(build_string_matches("py3.10*", "py3.10_0"))
  testthat::expect_false(build_string_matches("py3.10*", "py3x10_0"))
  testthat::expect_false(build_string_matches("h4ab", "h4ab18f5_1"))
  not_compared <- c(
    "^h4ab.*_1$",
    "^h[0-9a-f]+_[01]$",
    "h?ab18f5_1",
    "h4ab+",
    "h[4]ab*",
    "((",
    "h((x",
    "^((x$",
    "^h4ab",
    "h4ab.*$",
    "h4ab|x"
  )
  for (pattern in not_compared) {
    testthat::expect_false(build_string_is_compared(pattern), info = pattern)
    testthat::expect_false(
      build_string_matches(pattern, "h4ab18f5_1"),
      info = pattern
    )
    testthat::expect_false(
      build_string_matches(pattern, pattern),
      info = pattern
    )
  }
  # A very long build string returns FALSE instead of a regex error.
  testthat::expect_false(
    build_string_matches(strrep("a", 4000L), "h4ab18f5_1")
  )

  installed <- data.frame(
    name = "zlib",
    version = "1.3.1",
    build_string = "h4ab18f5_1",
    build_number = 1L,
    channel = "conda-forge"
  )
  specs <- c(
    "zlib=1.3.1=((",
    "zlib=1.3.1=^h4ab.*$",
    "zlib[build='h?ab*']",
    "zlib=1.3.1=h4ab*",
    "zlib[build=h4ab18f5_1]"
  )
  check <- check_env_request(
    installed_pkgs_df = installed,
    packages = specs,
    channels = "conda-forge"
  )
  testthat::expect_identical(check$unsatisfied, specs[1:3])
  testthat::expect_identical(check$uncompared_builds, specs[1:3])
  unsatisfied <- check$unsatisfied
  uncompared <- check$uncompared
  uncompared_versions <- check$uncompared_versions
  uncompared_builds <- check$uncompared_builds
  bullets <- cli::format_inline(unsatisfied_spec_bullets(check)[[2L]])
  testthat::expect_match(bullets, "Build strings with characters", fixed = TRUE)
  testthat::expect_match(bullets, "zlib=1.3.1=((", fixed = TRUE)
})

testthat::test_that("specs_with_uncompared_brackets() names the specs that never count as satisfied", {
  testthat::expect_identical(
    specs_with_uncompared_brackets(c(
      "zlib",
      "zlib[build_number=3]",
      "zlib[md5=abc]",
      "conda-forge::zlib[version='>=1', sha256=abc]",
      "zlib[build_number='== 3']"
    )),
    c(
      "zlib[md5=abc]",
      "conda-forge::zlib[version='>=1', sha256=abc]",
      "zlib[build_number='== 3']"
    )
  )
  testthat::expect_identical(
    specs_with_uncompared_brackets(character(0L)),
    character(0L)
  )
})

testthat::test_that("specs with a version that is not compared are named and never satisfied", {
  installed <- data.frame(
    name = "zlib",
    version = "1.3.1",
    build_string = "h4ab18f5_1",
    build_number = 1L,
    channel = "conda-forge",
    platform = "linux-64",
    stringsAsFactors = FALSE
  )
  specs <- c(
    "zlib>=1.3.*",
    "zlib<2.*",
    "zlib[version='<=1.3.*']",
    "zlib~=1.3*",
    "zlib=1.*.1",
    "zlib!=1.2*",
    "zlib >=1.2.*,<2",
    "zlib>=1.3*",
    "zlib=1.3.*.*",
    "zlib 1.*.*,<2",
    "zlib>=*",
    "zlib>=,<2",
    "zlib=1.3.1*",
    "zlib~=1",
    "zlib>=1.3,",
    "zlib>==1.3",
    "zlib (>=1.2,<2)|=3",
    "zlib[version='(1.3.1, ==1.3*)']"
  )
  # The check returned for every spec: it looped forever on these before.
  # `zlib=1.3.*.*` counted as satisfied before, and `zlib>=1.3*`,
  # `zlib>=,<2`, `zlib=1.3.1*`, `zlib~=1` and `zlib>=1.3,` too, but
  # micromamba does not install zlib 1.3.1 for them. A version with
  # parentheses is compared with the same atom rules: `(>=1.2,<2)|=3` is
  # satisfied, and `==1.3*` after another atom is not compared.
  check <- check_env_request(
    installed_pkgs_df = installed,
    packages = specs,
    channels = "conda-forge"
  )
  not_compared <- c(
    "zlib<2.*",
    "zlib[version='<=1.3.*']",
    "zlib~=1.3*",
    "zlib=1.*.1",
    "zlib!=1.2*",
    "zlib>=1.3*",
    "zlib=1.3.*.*",
    "zlib 1.*.*,<2",
    "zlib>=*",
    "zlib>=,<2",
    "zlib=1.3.1*",
    "zlib~=1",
    "zlib>=1.3,",
    "zlib>==1.3",
    "zlib[version='(1.3.1, ==1.3*)']"
  )
  testthat::expect_identical(check$unsatisfied, not_compared)
  testthat::expect_identical(check$uncompared_versions, not_compared)
  testthat::expect_identical(check$uncompared, character(0L))
  testthat::expect_identical(
    specs_with_uncompared_versions(c("zlib", "zlib>=1.3.*", "zlib<2.*")),
    "zlib<2.*"
  )

  # The bullet that names them.
  unsatisfied <- check$unsatisfied
  uncompared <- check$uncompared
  uncompared_versions <- check$uncompared_versions
  bullets <- cli::format_inline(unsatisfied_spec_bullets(check)[[2L]])
  testthat::expect_match(bullets, "are not compared", fixed = TRUE)
  testthat::expect_match(bullets, "zlib<2.*", fixed = TRUE)
})

testthat::test_that("build_number_spec_contains() reads operators as libmamba does", {
  testthat::expect_true(build_number_spec_contains(3L, "3"))
  testthat::expect_true(build_number_spec_contains(3L, "=3"))
  # micromamba 2.9.0 and 2.10.0 reject `==` for a build number.
  testthat::expect_false(build_number_spec_contains(3L, "==3"))
  testthat::expect_true(build_number_spec_contains("3", ">= 3"))
  testthat::expect_true(build_number_spec_contains(3L, ">2"))
  testthat::expect_true(build_number_spec_contains(3L, "<=3"))
  testthat::expect_true(build_number_spec_contains(3L, "<4"))
  testthat::expect_true(build_number_spec_contains(3L, "!=2"))
  testthat::expect_true(build_number_spec_contains(3L, "*"))
  testthat::expect_false(build_number_spec_contains(3L, "!=3"))
  testthat::expect_false(build_number_spec_contains(3L, ">3"))
  testthat::expect_false(build_number_spec_contains(3L, "<3"))
  testthat::expect_false(build_number_spec_contains(3L, "abc"))
  testthat::expect_false(build_number_spec_contains(3L, ">=3,<5"))
  testthat::expect_false(build_number_spec_contains(NA_integer_, "3"))
  testthat::expect_false(build_number_spec_contains(NULL, "3"))
})

testthat::test_that("version numerals beyond the integer range compare correctly", {
  # Regression test: numerals were parsed with as.integer(), so values above
  # 2^31 - 1 became NA and compared as equal to anything.
  testthat::expect_no_warning(version_spec_contains("3000000000", "==1"))
  testthat::expect_false(version_spec_contains("3000000000", "==1"))
  testthat::expect_false(version_spec_contains("1.0.20240101123456", "==1.0.5"))
  testthat::expect_true(version_spec_contains("3000000000", ">2"))
  testthat::expect_true(version_spec_contains("1.0.20240101123456", "1.0.*"))
})

testthat::test_that("normalize_channel_name() reduces URLs and local paths", {
  # A local channel becomes an absolute path, as micromamba and rattler
  # record it: `~` is the home directory and a relative path starts at the
  # working directory.
  work_dir <- withr::local_tempdir()
  home_dir <- withr::local_tempdir()
  withr::local_dir(work_dir)
  withr::local_envvar(HOME = home_dir, USERPROFILE = home_dir)
  in_case <- function(x) if (isTRUE(is_windows())) tolower(x) else x
  # `fs::path_norm()`: on macOS, `TMPDIR` ends in `/`, so the temporary
  # directories have `T//Rtmp...` in their path.
  slashed <- function(x) as.character(fs::path_norm(gsub("\\\\", "/", x)))
  testthat::expect_identical(
    normalize_channel_name(c(
      "conda-forge",
      "https://conda.anaconda.org/conda-forge/",
      "conda-forge/label/main",
      "file:///C:/channels/chan-a",
      "file:///srv/channels/chan-b",
      "/srv/channels/chan-b/",
      "/srv/channels/./other/../chan-b",
      "C:\\channels\\chan-a",
      "C:/channels/chan-a",
      "./channels/chan-c",
      "~/chan-d",
      "file:///srv/my%20channels/chan-e"
    )),
    c(
      "conda-forge",
      "conda-forge",
      "conda-forge/label/main",
      in_case("C:/channels/chan-a"),
      in_case("/srv/channels/chan-b"),
      in_case("/srv/channels/chan-b"),
      in_case("/srv/channels/chan-b"),
      in_case("C:/channels/chan-a"),
      in_case("C:/channels/chan-a"),
      in_case(paste0(slashed(getwd()), "/channels/chan-c")),
      in_case(paste0(slashed(home_dir), "/chan-d")),
      in_case("/srv/my channels/chan-e")
    )
  )
})

testthat::test_that("local channels with the same directory name stay different", {
  # Regression test: a local or file:// channel was reduced to its last
  # directory name, so an environment built from one local channel passed
  # validate_env(channels = <another local channel with that name>), and
  # create_env(overwrite = FALSE) kept it instead of using that channel.
  testthat::expect_false(identical(
    normalize_channel_name("file:///srv/a/polyglot-channel"),
    normalize_channel_name("/home/u/other/polyglot-channel")
  ))
  installed <- data.frame(
    name = "polyglot",
    version = "0.1.0",
    build_number = 0L,
    build_string = "h4616a5c_0",
    channel = "file:///srv/a/polyglot-channel",
    platform = "noarch",
    stringsAsFactors = FALSE
  )
  sat <- function(spec, channels) {
    return(spec_satisfied_by(
      spec,
      installed,
      requested_channel_names(channels)
    ))
  }
  testthat::expect_true(sat("polyglot", "/srv/a/polyglot-channel"))
  testthat::expect_true(sat("polyglot", "file:///srv/a/polyglot-channel/"))
  testthat::expect_false(sat("polyglot", "/home/u/other/polyglot-channel"))
  testthat::expect_false(sat("polyglot", "file:///srv/b/polyglot-channel"))
  # A channel name in a spec is a channel on conda.anaconda.org, not a
  # local channel with that directory name.
  testthat::expect_false(sat("polyglot-channel::polyglot", "conda-forge"))
  testthat::expect_true(
    sat("file:///srv/a/polyglot-channel::polyglot", "conda-forge")
  )
})

testthat::test_that("normalize_channel_name() drops the credentials of channel URLs", {
  # Regression test: a channel URL with a token or a user and password
  # never matched the installed channel, which micromamba records without
  # them. A second, identical create_env() with such a channel aborted with
  # condathis_create_env_exists, and validate_env() returned FALSE, with
  # both backends.
  testthat::expect_identical(
    normalize_channel_name(c(
      # Requested, recorded by micromamba, and listed by rattler.
      "http://127.0.0.1:18765/t/tk-0123456789abcdef/polyglot-channel",
      "http://127.0.0.1:18765/polyglot-channel",
      "http://127.0.0.1:18765/t/********/polyglot-channel/",
      "http://127.0.0.1:18765/t/*****/polyglot-channel",
      "http://user:s3cr3t@127.0.0.1:18765/plain/polyglot-channel",
      "http://user:*****@127.0.0.1:18765/plain/polyglot-channel",
      "https://conda.anaconda.org/t/abc-123/private"
    )),
    c(
      "127.0.0.1:18765/polyglot-channel",
      "127.0.0.1:18765/polyglot-channel",
      "127.0.0.1:18765/polyglot-channel",
      "127.0.0.1:18765/polyglot-channel",
      "127.0.0.1:18765/plain/polyglot-channel",
      "127.0.0.1:18765/plain/polyglot-channel",
      "private"
    )
  )
  installed <- data.frame(
    name = c("polyglot", "zlib"),
    version = c("0.1.0", "1.3.1"),
    build_number = 0L,
    build_string = "h0_0",
    channel = c(
      "http://127.0.0.1:18765/polyglot-channel",
      "http://127.0.0.1:18765/plain/polyglot-channel"
    ),
    platform = "noarch",
    stringsAsFactors = FALSE
  )
  token_url <- "http://127.0.0.1:18765/t/tk-0123456789abcdef/polyglot-channel"
  auth_url <- "http://user:s3cr3t@127.0.0.1:18765/plain/polyglot-channel"
  testthat::expect_identical(
    packages_satisfied_by(c("polyglot", "zlib"), installed, token_url),
    c(TRUE, FALSE)
  )
  testthat::expect_identical(
    packages_satisfied_by(c("polyglot", "zlib"), installed, auth_url),
    c(FALSE, TRUE)
  )
  testthat::expect_true(
    spec_satisfied_by(paste0(token_url, "::polyglot"), installed, NULL)
  )
  # Another host or path is still another channel.
  testthat::expect_false(spec_satisfied_by(
    "polyglot",
    installed,
    requested_channel_names(
      "http://127.0.0.1:18766/t/tk-0123456789abcdef/polyglot-channel"
    )
  ))
})

testthat::test_that("normalize_channel_name() hides /t/<word> parts, in paths too", {
  # Regression test: micromamba hides every `/t/<word>` of its JSON output
  # as a channel token, local paths included, and condathis hides them in
  # the channels of the history and of list_packages() (see
  # `hide_secrets()`). A channel with such a part in its path did not
  # compare equal to the same channel passed again.
  in_case <- function(x) if (isTRUE(is_windows())) tolower(x) else x
  testthat::expect_identical(
    normalize_channel_name(c(
      "/srv/t/chan1/polyglot-channel",
      "/srv/t/chan1/polyglot-channel/noarch",
      "file:///srv/t/chan1/polyglot-channel",
      "file:///srv/t/*****/polyglot-channel/",
      "C:\\Users\\me\\t\\chan1\\polyglot-channel",
      "file:///C:/Users/me/t/chan1/polyglot-channel",
      "file:///C:/Users/me/t/*****/polyglot-channel",
      # A token channel on another host, with the token after the host and
      # inside the path.
      "https://repo.example.org/t/tk-0123456789/chan",
      "https://repo.example.org/t/*****/chan",
      "https://repo.example.org/org/t/tk-0123456789/chan",
      "https://repo.example.org/org/t/*****/chan",
      # A token that is hidden only up to the `_`, as micromamba hides it.
      "https://repo.example.org/t/ab_cd/chan",
      "https://repo.example.org/t/*****_cd/chan"
    )),
    c(
      rep(in_case("/srv/t/*****/polyglot-channel"), 4L),
      rep(in_case("C:/Users/me/t/*****/polyglot-channel"), 3L),
      rep("repo.example.org/chan", 2L),
      rep("repo.example.org/org/t/*****/chan", 2L),
      rep("repo.example.org/t/*****_cd/chan", 2L)
    )
  )
  installed <- data.frame(
    name = c("polyglot", "zlib"),
    version = c("0.1.0", "1.3.1"),
    build_number = 0L,
    build_string = "h0_0",
    # As list_packages() lists them.
    channel = c(
      "file:///srv/t/*****/polyglot-channel",
      "https://repo.example.org/org/t/*****/chan"
    ),
    platform = "noarch",
    stringsAsFactors = FALSE
  )
  local_channel <- "file:///srv/t/chan1/polyglot-channel"
  token_channel <- "https://repo.example.org/org/t/tk-0123456789/chan"
  testthat::expect_identical(
    packages_satisfied_by(c("polyglot", "zlib"), installed, local_channel),
    c(TRUE, FALSE)
  )
  testthat::expect_identical(
    packages_satisfied_by(c("polyglot", "zlib"), installed, token_channel),
    c(FALSE, TRUE)
  )
  testthat::expect_true(
    spec_satisfied_by(paste0(local_channel, "::polyglot"), installed, NULL)
  )
  # The hidden part is lost, so a channel that differs only there compares
  # equal; a difference elsewhere still counts.
  testthat::expect_true(spec_satisfied_by(
    "polyglot",
    installed,
    requested_channel_names("/srv/t/chan2/polyglot-channel")
  ))
  testthat::expect_false(spec_satisfied_by(
    "polyglot",
    installed,
    requested_channel_names("/srv/u/chan1/polyglot-channel")
  ))
  # On Windows a path is put in lower case only after that: micromamba and
  # condathis hide only a lower-case `/t/<word>`, so an upper-case one
  # still tells two channels apart.
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  testthat::expect_identical(
    normalize_channel_name(c(
      "C:\\Data\\t\\proj-a\\channel",
      "file:///C:/Data/t/*****/channel",
      "C:\\Data\\T\\proj-a\\channel",
      "file:///C:/Data/T/proj-b/channel"
    )),
    c(
      rep("c:/data/t/*****/channel", 2L),
      "c:/data/t/proj-a/channel",
      "c:/data/t/proj-b/channel"
    )
  )
  installed$channel[[1L]] <- "file:///C:/Data/T/proj-b/channel"
  testthat::expect_false(spec_satisfied_by(
    "polyglot",
    installed,
    requested_channel_names("C:\\Data\\T\\proj-a\\channel")
  ))
  testthat::expect_true(spec_satisfied_by(
    "polyglot",
    installed,
    requested_channel_names("c:\\data\\T\\PROJ-B\\channel")
  ))
})

testthat::test_that("a platform filter and defaults match the installed channel", {
  # Regression test: channels = "defaults", or a channel that ends in a
  # platform subdirectory, never matched the installed channel, so
  # create_env(overwrite = FALSE) was not idempotent for them and
  # validate_env(channels = ...) returned FALSE.
  testthat::expect_identical(
    normalize_channel_name(c(
      "conda-forge/linux-64",
      "conda-forge[linux-64]",
      "conda-forge [noarch, linux-64]",
      "https://conda.anaconda.org/conda-forge/noarch/",
      "https://repo.anaconda.com/pkgs/main",
      "https://repo.anaconda.com/pkgs/main/linux-64",
      "linux-64"
    )),
    c(
      "conda-forge",
      "conda-forge",
      "conda-forge",
      "conda-forge",
      "pkgs/main",
      "pkgs/main",
      "linux-64"
    )
  )
  testthat::expect_identical(
    normalize_channel_name("file:///srv/chan/noarch"),
    normalize_channel_name("/srv/chan")
  )
  testthat::expect_identical(
    requested_channel_names(c("defaults", "conda-forge", "pkgs/main")),
    c("defaults", "conda-forge", "pkgs/main", "pkgs/r", "pkgs/msys2")
  )
  installed <- data.frame(
    name = c("zlib", "polyglot"),
    version = c("1.3.2", "0.1.0"),
    build_number = 0L,
    build_string = "h0_0",
    # micromamba lists a package from `defaults` under `pkgs/main`.
    channel = c("pkgs/main", "file:///srv/chan"),
    platform = c("linux-64", "noarch"),
    stringsAsFactors = FALSE
  )
  sat <- function(spec, channels = NULL) {
    requested <- if (!is.null(channels)) requested_channel_names(channels)
    return(spec_satisfied_by(spec, installed, requested))
  }
  testthat::expect_true(sat("zlib", "defaults"))
  testthat::expect_true(sat("defaults::zlib"))
  testthat::expect_true(sat("zlib", "https://repo.anaconda.com/pkgs/main"))
  testthat::expect_false(sat("zlib", "conda-forge"))
  testthat::expect_false(sat("zlib", "pkgs/r"))
  testthat::expect_true(sat("polyglot", "file:///srv/chan/noarch"))
  testthat::expect_true(sat("polyglot", "/srv/chan[noarch]"))
  testthat::expect_false(sat("polyglot", "defaults"))
})

testthat::test_that("normalize_channel_name() compares http(s) URLs by their channel path", {
  # Regression test: every URL was reduced to its last path component, so
  # a label channel never matched its name (the environment was rebuilt on
  # every call), and channels on different hosts compared equal.
  testthat::expect_identical(
    normalize_channel_name(c(
      "https://conda.anaconda.org/conda-forge/label/dev",
      "http://conda.anaconda.org/conda-forge/label/dev/",
      "conda-forge/label/dev",
      "https://repo.prefix.dev/my-org/channel",
      "https://Repo.Prefix.DEV/my-org/channel/",
      "https://repo.prefix.dev/universe",
      "https://example.org/universe",
      "https://example.org"
    )),
    c(
      "conda-forge/label/dev",
      "conda-forge/label/dev",
      "conda-forge/label/dev",
      "repo.prefix.dev/my-org/channel",
      "repo.prefix.dev/my-org/channel",
      "repo.prefix.dev/universe",
      "example.org/universe",
      "example.org"
    )
  )
  # Two hosts with the same last component stay different.
  testthat::expect_false(identical(
    normalize_channel_name("https://repo.prefix.dev/universe"),
    normalize_channel_name("https://example.org/universe")
  ))
})

testthat::test_that("a label channel and a prefix.dev channel satisfy their own specs", {
  # micromamba reports a conda.anaconda.org channel by name and any other
  # channel by URL; other backends can report every channel by URL.
  installed <- data.frame(
    name = c("zlib", "polyglot"),
    version = c("1.3.1", "0.1.0"),
    build_number = c(0L, 0L),
    build_string = c("h0_0", "h4616a5c_0"),
    channel = c(
      "https://conda.anaconda.org/conda-forge/label/dev/",
      "https://repo.prefix.dev/universe"
    ),
    platform = c("linux-64", "noarch"),
    stringsAsFactors = FALSE
  )
  sat <- function(spec, channels) {
    return(spec_satisfied_by(
      spec,
      installed,
      normalize_channel_name(channels)
    ))
  }
  testthat::expect_true(sat("zlib", "conda-forge/label/dev"))
  testthat::expect_false(sat("zlib", "conda-forge"))
  testthat::expect_false(sat("zlib", "dev"))
  testthat::expect_true(sat("polyglot", "https://repo.prefix.dev/universe"))
  testthat::expect_false(sat("polyglot", "https://example.org/universe"))
  testthat::expect_false(sat("polyglot", "universe"))
})

testthat::test_that("spec_satisfied_by() reads columns by exact name", {
  # Regression test: `$` warned on a tibble without `build_string`, and
  # matched partial names on a data frame.
  installed <- data.frame(
    name = "zlib",
    version = "1.3.1",
    build_string_extra = "h0_0",
    channel = "conda-forge",
    stringsAsFactors = FALSE
  )
  class(installed) <- c("tbl_df", "tbl", "data.frame")
  testthat::expect_no_warning(
    res <- spec_satisfied_by("zlib=1.3.1=h0*", installed, NULL)
  )
  testthat::expect_false(res)
  testthat::expect_true(spec_satisfied_by("zlib=1.3.1", installed, NULL))
})
