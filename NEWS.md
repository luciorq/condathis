## condathis (development version)

### Bug fixes

* On Windows, `run()`, `run_bin()` and `run_pipeline()` with the micromamba
  backend no longer put a second copy of `PATH` entries written with `/` in
  front of your session's `PATH`. micromamba rewrites these entries with `\`,
  and condathis had read the rewritten copies as directories that the
  environment added.

## condathis 0.2.0

condathis 0.2.0 adds pipelines and runs the environment and command
functions through backends.
It makes the exported functions consistent (one argument order, one rule for
missing environments, one set of condition classes).
It no longer changes the files of other Conda tools in your home directory,
except `~/.conda/environments.txt` in one case (see Bug fixes).
Some changes break code written for 0.1.4: they come first, each with what to
write instead.

### Breaking changes

* `create_env()` and `install_packages()` take package specs in `...` and
  every other argument by name, as in
  `create_env("python=3.13", env_name = "py-env")`.
  `packages =` still works, with a deprecation warning once per session and
  function (class `condathis_deprecated_packages_arg`).

* Old positional calls no longer work: name every argument after the
  package specs, as in `install_packages("pkg", env_name = "my-env")`.
  When the last spec names an existing environment, the call aborts and
  says so (class `condathis_<function>_positional_env_name`).
  Any other name is read as one more package spec, and the call fails
  (`install_packages()` first creates a missing `"condathis-env"`, empty).
  A spec that ends in `.yml` or `.yaml` asks for `env_file =`.
  A misspelled argument such as `chanels =` names the closest argument.

* The default `channels` of `create_env()` and `install_packages()` is now
  `"conda-forge"` (it was `c("conda-forge", "bioconda")`).
  For bioconda packages, name the channel in the spec (`"bioconda::samtools"`)
  or pass `channels = c("conda-forge", "bioconda")`.
  `channels = NULL`, `character(0)`, `NA` and `""` abort with class
  `condathis_invalid_channels` (in 0.1.4, `NULL` meant the default).

* The default `channel_priority` of `create_env()` and `install_packages()`
  is now `"strict"` (it was `"disabled"`).
  Pass `channel_priority = "disabled"` for the old solver behavior.

* `create_env(overwrite = FALSE)` never replaces an existing environment.
  It keeps it, with status 0, when it already has the requested packages or
  when nothing is requested.
  Otherwise, and always with `env_file`, it aborts with class
  `condathis_create_env_exists`: use `install_packages()` to add packages,
  or `overwrite = TRUE` to rebuild.
  In 0.1.4, it deleted and rebuilt the environment, which lost the packages
  added later.

* `create_env()` aborts when package specs and `env_file` are both given
  (class `condathis_create_env_conflicting_args`).
  In 0.1.4, it ignored the specs.
  It also aborts, with `platform` and `overwrite = FALSE`, on an existing
  environment built for another platform
  (class `condathis_create_env_platform_mismatch`): pass `overwrite = TRUE`
  to rebuild it for that platform.

* Missing environments are no longer created on the fly: create them with
  `create_env()` first.
  `install_packages()` into a missing environment,
  `list_packages()` of a missing `"condathis-env"`, and `run_bin()` in a
  missing environment (it ran a same-name program from `PATH`) now abort.
  The error has class `condathis_<function>_env_not_found`
  (also `condathis_env_not_found`).
  `run()` and `run_bin()` give status 127 with `error = "continue"`.
  Only the default `"condathis-env"` is created, empty, by
  `install_packages()`, `run()`, `run_bin()` and `run_pipeline()`,
  and only when it is the environment you asked for.

* Environment names must be valid directory names on every OS.
  Names that are empty, `.` or `..`, start with `-` or end with `.` are
  invalid.
  So are names that contain a path separator, `:`, `#`, whitespace or
  `<>"|?*`, and Windows device names such as `nul`.
  They abort in every function (class `condathis_invalid_env_name`).
  `env_path()` still runs commands in an existing environment with such a
  name (its `path` is in `list_envs()`).
  To change one, create it again under a valid name and delete the old
  directory.

* `run_bin()` now activates the environment, with the new argument
  `activate = TRUE`.
  Pass `activate = FALSE` for the 0.1.4 behavior.

* `run()` starts the command itself instead of through `micromamba run`,
  so arguments reach it exactly as given.
  On Windows, `cmd.exe` re-parsed them (`>`, `<`, `|` and `&` became
  redirections, pipes and command separators, and `^` and `%` were
  dropped).
  Shell builtins such as `dir` and `echo` also worked: run a shell
  explicitly for them (see `?run`).
  What `activate.d` scripts print is no longer part of the output.
  `verbose = "cmd"` shows your command, not micromamba's.
  On Linux and macOS, a failing `activate.d` script aborts
  with class `condathis_run_resolve_failed` instead of a status error.

* `run()` and `run_bin()` reject a `cmd` that is not a single, non-empty
  string, such as `c("echo", "x")` (class `condathis_invalid_cmd`).
  Pass the arguments of the command in `...`.
  `NA` in `...` aborts with class `condathis_<function>_invalid_args`
  (0.1.4 passed the string `"NA"`).

* `create_env()`, `install_packages()`, `remove_env()`, `clean_cache()`,
  `run()` and `run_bin()` return a `condathis_result` object, which prints
  as a short summary.
  `status`, `stdout`, `stderr` and `timeout` work as before, and `cmd`,
  `env_name` and `pid` are new (`pid` is `NA` unless `run()` or `run_bin()`
  gets `stdin = "|"`).
  A stream that was not captured is now `NA` instead of `NULL` or `""`:
  test it with `is.na()`.
  `as.list(res)` gives a plain list.

* `get_install_dir()` and `list_envs()` return a data frame (a tibble)
  instead of a character vector: use `get_install_dir("micromamba")$path`
  and `list_envs()$env_name`.

* `method` is a new argument right after `env_name` in `env_exists()`,
  `remove_env()`, `list_packages()` and `get_env_dir()`, and the first
  argument of `list_envs()` and `get_install_dir()`.
  Pass `verbose` by name:
  `list_envs("silent")` and `env_exists("x", "silent")` abort with class
  `condathis_invalid_method`.

* `remove_env()` now defaults to `verbose = "output"` and reports the
  removal.
  `list_packages()` now defaults to `verbose = "silent"` and
  always returns its tibble visibly.

* `env_exists()` and `get_env_dir()` abort when `env_name` is not a single,
  valid name, such as `NULL`, `NA`, a number or several names (class
  `condathis_invalid_env_name`).
  In 0.1.4, `env_exists()` returned `FALSE`, and `get_env_dir()` returned
  one path per name.
  `env_exists()` now defaults to `env_name = "condathis-env"`.

* `install_micromamba()`: `timeout_limit` is renamed `timeout`, in the same
  position (`timeout_limit` still works, with a warning of class
  `condathis_deprecated_arg`).
  An explicit `micromamba_version` now
  replaces an installed binary of another version, and versions older than
  2.8.1 abort with class `condathis_install_micromamba_unsupported_version`.

* `parse_output()` keeps the text as the command wrote it: pass the new
  `trim = TRUE` for the 0.1.4 trimming of whitespace and blank lines.
  Lines end only at `\n`, `\r\n` or `\r`, and empty output gives
  `character(0)` instead of `""`, also with `trim = TRUE`: test for it with
  `length(x) == 0L`.
  `stream = "both"` aborts when neither stream was captured
  (it returned `""`), and `stream = "plain"` aborts on `NA` (it returned
  `"NA"`).

### New features

* Backends: the environment functions and the run family take `method` and
  dispatch to a backend.
  `"micromamba"` is built in, and gets every new
  environment unless you pass `method` or set the option
  `condathis.backend_priority`.
  `"auto"`, the new default of `method`, uses
  the backend that owns an existing environment.

* `method = "rattler"` uses the backend of the rattlerthis package, which
  is not on CRAN.
  condathis loads it when it is installed, and aborts with
  class `condathis_backend_not_installed` otherwise.
  It never downloads micromamba.
  A backend that does not run the link scripts of packages, such as rattler,
  makes the call warn with class `condathis_link_scripts_skipped`.

* Other packages can add a backend with the experimental
  `register_backend()` (see `?register_backend`) and remove it with
  `unregister_backend()`.
  `list_registered_backend_names()` lists the
  backends, and `backend_root_dir()` gives the data directory of one.

* New `run_pipeline()` and `run_step()` run a pipeline (`cmd1 | cmd2`)
  through operating system pipes, each command in its own environment if
  needed: `run_pipeline(run_step("seq", "1", "3"), run_step("cat"))`.
  A command that ends because the next one stopped reading, as `seq` in
  `seq 1 1000000 | head -n 1`, does not count as a failure, also on
  Windows.
  `parse_output()` reads the result.
  Here, `supervise` and `cleanup_tree` default to `TRUE`.

* New `env_path()` refers to an environment created outside condathis by
  its directory, for `run()`, `run_bin()`, `run_pipeline()` and
  `run_step()`:
  `run("python", "--version", env_name = env_path("/opt/envs/py"))`.
  condathis never changes such an environment.

* New `validate_env()` checks that an environment exists and has the
  requested package specs, using the same check as
  `create_env(overwrite = FALSE)`.
  It returns `TRUE` invisibly, or aborts with class
  `condathis_validate_env_unsatisfied` (`condathis_validate_env_env_not_found`
  for a missing environment).
  With `error = "continue"`, it returns `FALSE` instead.

* New arguments of `run()` and `run_bin()`, also in `run_pipeline()`:
  * `timeout` kills the command after that many seconds (status `-9`,
    class `condathis_timeout_error`).
  * `input` writes a character or raw vector to standard input with
    `stdin = "|"`.
  * `binary = TRUE` returns stdout and stderr as raw vectors.
  * `supervise` and, on Linux, `linux_pdeathsig` end the command when R
    ends, even by a crash. `cleanup_tree` ends the processes that the
    command started when it finishes. All three default to `FALSE`.
  * `run_bin()` also gains `method`.

* The errors of a failed or timed-out command of `run()`, `run_bin()` and
  `run_pipeline()` carry the fields `status`, `stdout`, `stderr` and
  `timeout`.

* The micromamba backend records the activation of an environment (its
  `activate.d` scripts included) the first time a command runs in it in an
  R session.
  It reuses that activation, without running the scripts again, until the
  environment or the environment variables of the session change.

* `install_micromamba()` checks each download against the SHA256 checksum
  published with the micromamba release.
  It tries the next mirror when the checksum does not match (warning class
  `condathis_install_micromamba_checksum_mismatch`).
  When no checksum can be read, it installs the binary and warns with class
  `condathis_install_micromamba_checksum_unavailable` when
  `verbose = "output"` or `"full"`.

* Windows on ARM64: a native ARM64 R gets the `win-arm64` micromamba.
  `create_env()` falls back to `win-64` packages, through x64 emulation,
  when a request cannot be installed for `win-arm64`.

* `create_env()`, `install_packages()` and `remove_env()` lock the
  environment: another R session that changes it waits, and says so after
  two seconds (message class `condathis_env_lock_waiting`).
  `clean_cache()` and package installs of other sessions wait for each other.

* New help pages `?condathis-conditions` (condition classes and error
  fields) and `?condathis-options` (options and environment variables).

### Other changes

* `method = "native"`, the 0.1.4 default, still works as a deprecated alias
  for `"micromamba"` (warning class `condathis_deprecated_method_native`).

* Every error has the class `condathis_error` and every warning
  `condathis_warning`, with classes for the function and the problem (see
  `?condathis-conditions`).
  Messages changed too: match classes and error fields, not message text.
  The 0.1.4 classes are kept as extra classes until 1.0:
  * `condathis_create_invalid_overwrite_arg` is now
    `condathis_create_env_invalid_overwrite`.
  * `condathis_create_missing_env_file` is now
    `condathis_create_env_missing_env_file`.
  * `condathis_error_env_remove` is now `condathis_remove_env_env_not_found`.
  * `condathis_list_packages_missing_env` is now
    `condathis_list_packages_env_not_found`.
  * `condathis_cmd_status_error` is now `condathis_micromamba_status_error`,
    with the fields `status` and `stderr`.
  * `condathis_install_error_missing_bzip2` (deprecated) is now
    `condathis_install_micromamba_download_failed`.
  * `condathis_run_null_cmd` is now `condathis_run_invalid_cmd`.
  * `condathis_run_stdin_error` is now `condathis_run_invalid_stdin` and
    `condathis_run_bin_invalid_stdin`.
  * `condathis_run_status_error` of `run_bin()` is now
    `condathis_run_bin_status_error`.
  * `rlib_error_dots_named`, for a named value in `...` of `run()` and
    `run_bin()`, is now `condathis_run_invalid_args` and
    `condathis_run_bin_invalid_args`.
  * `condathis_umamba_*` is now `condathis_micromamba_*`.

* Arguments are checked before anything runs.
  Invalid values of `verbose`,
  `error`, `method`, `channel_priority`, `platform` (with a suggestion,
  such as `"linux-aarch64"` for `"linux-arm64"`) and `env_file`, and
  package specs such as `NA` or `""`, abort with classed errors that name
  your call.
  This happens before micromamba is installed or started.
  `run()` and `run_bin()` check `stdin`, `stdout` and `stderr` before the
  command starts.

* Queries never install micromamba or create an environment:
  `list_envs()`, `env_exists()`, `get_env_dir()`, `get_install_dir()`,
  `list_packages()` and `validate_env()` (`get_env_dir()` and
  `get_install_dir()` create only the data directory).
  Without a usable micromamba, they read the data directory.

* The check that an existing environment has the requested
  packages (`create_env(overwrite = FALSE)`, `validate_env()`) compares the
  name without case, the version, the build string, the channel and the
  platform.
  It also compares the `version`, `build`, `build_number` and `channel`
  bracket constraints.
  0.1.4 compared only the name and the version.
  Channels compare without credentials or platform subdirectory.

* A spec that condathis cannot compare as micromamba reads it never counts
  as satisfied.
  Examples are a bracket constraint other than these (`[md5=...]`), a regular
  expression as build string and some uses of `*`.
  The error names the spec (see `?create_env`).

* `install_packages()` warns (class
  `condathis_install_packages_missing_previous_channels`) when the
  environment has packages from a channel that the call leaves out.
  This happens, for example, with bioconda packages installed with the 0.1.4
  default channels.
  Add that channel to `channels` or `additional_channels`.

* `list_packages()` always has the columns `name`, `version`,
  `build_number` (integer), `build_string`, `channel` and `platform`.
  A failed listing aborts with class `condathis_list_packages_failed`.

* The password and the token of a URL, such as a channel URL, show as
  `*****`, as micromamba shows them.
  This holds in the command line that `verbose = "cmd"` and
  `"full"` print, in the `cmd` of results, in messages, warnings and errors,
  and in `list_packages()`.
  The command still gets them, and `stdout` and `stderr` of results keep
  them.

* `with_sandbox_dir()` returns the value of `code`.
  It also redirects
  `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `R_USER_CONFIG_DIR`, and stops the
  processes that condathis started in it.
  `.local_envir` is now only the environment that `code` runs in.

* condathis keeps files of its own in its data directory
  (`condathis-micromamba.yaml` and the directories `cache`, `home`, `locks`
  and `channels`) and in a `.condathis` directory in each environment that
  it creates.

* Messages use cli's success and information bullets instead of `!`, and
  spell "successfully" correctly.
  `create_env()` says that an existing environment "already has the requested
  packages" instead of "already exists".

* micromamba 2.10.0-0 is installed by default (it was 2.8.1-0).
  Versions from 2.8.1 on still work, and condathis reads the listing format of
  micromamba 2.9 and later.

* condathis now imports filelock (>= 1.0.3) and ps (>= 1.9.3).
  It needs cli (>= 3.4.0), processx (>= 3.9.0) and rlang (>= 1.0.0).

### Bug fixes

* condathis no longer changes the files of other Conda tools in your home
  directory, except `~/.conda/environments.txt` in the case below:
  * `create_env()` no longer deletes `~/.mamba` (`%APPDATA%\.mamba` on
    Windows) when it has no `pkgs` subdirectory.
  * micromamba and the commands of its environments use only the condathis
    package cache, and `clean_cache()` deletes only the caches of
    condathis.
    It deleted the shared `~/.mamba/pkgs` cache and the whole
    `~/.cache/conda` directory.
    It no longer installs micromamba when there is no package cache to
    clean.
  * micromamba keeps its repodata cache in the condathis data directory,
    not in `~/.cache/conda`, and `run()` leaves no `mamba/proc` directory in
    your cache directory.
  * Listing and removing environments no longer rewrite
    `~/.conda/environments.txt`, and `create_env()` adds the environment to
    it only when micromamba needs your home directory (see
    `?get_install_dir`).
  * On Windows, packages no longer add Start Menu shortcuts.
    Shortcuts that 0.1.4 added stay after `remove_env()`.

* condathis no longer changes the environment variables of the R session
  while a command runs.
  In 0.1.4, R code that ran meanwhile, such as a
  condition handler, saw the `R_HOME`, `TMPDIR`, `CONDA_*` and `MAMBA_*`
  values of the child process, and for `run_bin()` its `PATH`.

* `with_sandbox_dir()` restores the working directory and every
  environment variable, those that `code` set included, and deletes the
  sandbox before it returns, also after an error.
  At top level, as in examples, 0.1.4 kept `HOME` and the data directories
  redirected for the rest of the session.
  It also kept the sandbox on disk.

* micromamba now works when its default root prefix
  (`$XDG_DATA_HOME/mamba`, else `~/.local/share/mamba`) exists but is not a
  Conda environment.
  In 0.1.4, no command worked then.

* condathis works when the path of its data directory has a `/t/<name>/`
  part, which micromamba 2.9.0 and later hide as an anaconda.org token.
  With such a micromamba, 0.1.4 failed there with "Failed to realize".

* Errors of micromamba commands show micromamba's message and the exit
  status.
  0.1.4 ran micromamba with `--quiet`, which hid the message below
  `verbose = "full"`.

* A failed or interrupted `create_env()` no longer deletes the environment
  it replaces: the environment is moved aside first and moved back.
  A failed create of a new environment no longer leaves an empty environment
  behind.

* On Windows, interrupting `create_env()` or `install_packages()` also
  stops the programs that micromamba started, such as pip.

* On Windows, a `run()` that is interrupted or runs out of time no longer
  leaves micromamba's batch files (`mamba_act*.bat`, `mamba_bat_*.bat`) in
  `%TEMP%`: micromamba writes its temporary files to a directory that
  condathis deletes when the call returns.

* `remove_env()` and `create_env()` no longer delete directories outside
  the environments directory (`env_name = ""` deleted every environment,
  and `".."` the whole data directory).
  They delete only a directory that is
  exactly `<root>/envs/<env_name>`: on Windows and macOS, a name that
  differed in case could delete another environment.
  `remove_env()` no longer deletes the leftover directory of a name that
  micromamba does not list.

* The check that an existing environment has the requested packages no
  longer hangs on a `*` after an operator (`"zlib>=1.2.*"`).
  It no longer counts `"zlib=1.3.*.*"`, `"zlib~=1"` or `"zlib>=1.2,"` as
  satisfied by versions that micromamba does not match.
  It no longer treats version numbers above 2147483647 as equal to any other.

* `install_packages()` installs packages for the platform of the
  environment, not for the platform of micromamba.
  An environment created through Rosetta 2, for example, gets `osx-64`
  packages.

* On Apple Silicon, the Rosetta 2 fallback of `create_env()` checks the
  whole request, with its dependencies and `env_file`, and its messages
  follow `verbose`.
  The first install into an environment with only
  `noarch` packages, such as a new `"condathis-env"`, gets the same
  fallback.

* `list_envs()`:
  * lists an environment named `"condathis"` (it was hidden, and
    `create_env()` or `remove_env()` with that name deleted it).
  * no longer fails on a stale entry of `~/.conda/environments.txt`.
  * matches the data directory as a path prefix instead of a regular
    expression.
  * lists an environment reached through a symbolic link once.
  * no longer prints micromamba's JSON with `verbose = "output"`.

* `list_packages()` lists only the pip packages of the environment, not
  those of your user site directory or `PYTHONPATH`.

* `run()` and `run_bin()` write numbers in `...` in full:
  `run("head", "-n", 100000)` passes `"100000"`, not `"1e+05"`.

* On Windows, `run_bin()` finds the programs of an environment in
  `Library/bin`, `Scripts` and the other directories that activation adds
  to `PATH`, with the extensions of `PATHEXT`.
  0.1.4 looked only in `bin`.
  `run_bin()` no longer resolves the symbolic links of a program found on
  `PATH`, which changed `argv[0]` of multicall programs such as busybox.

* `install_micromamba()`:
  * no longer creates `"condathis-env"`.
  * replaces an installed binary only with a download that runs, reports
    its version and matches the checksum, also with `force = TRUE`.
    A bad download, such as an HTML error page or a truncated archive, no
    longer breaks a working installation or reports success.
    The next mirror is tried instead.
  * extracts the archive with R's internal `tar`, so every mirror works
    without a system `tar` and `bzip2`.
  * applies `timeout` also with the curl package.
  * takes `Inf` as no limit (it made every download fail without curl).
  * lowers a limit above 2147483 seconds (about 24.8 days) to that value.
  * no longer tries the micro.mamba.pm mirror, which serves only the latest
    release.
  * on Windows, no longer reports a new binary that antivirus software
    still holds as missing.

* micromamba discovery skips a broken candidate, such as a stale
  `CONDATHIS_MICROMAMBA_PATH`, a directory or a truncated binary, instead
  of failing.

* A local channel in a directory whose path has a space works with
  `create_env()` and `install_packages()` (micromamba failed with "Failed
  to parse URL").

* `run()` and `run_bin()` no longer return an object named `px_res` from
  your workspace when the command cannot start under `error = "continue"`.
  `parse_output()` no longer returns a variable named `raw_text` from your
  workspace.
  With `stream = "both"`, it no longer joins the last line of stdout
  with the first line of stderr.

* condathis works on R 4.3: `%||%` is now imported from rlang.

## condathis 0.1.4

Release Date: 2026-06-19

Development Changelog: [0.1.4](https://github.com/luciorq/condathis/compare/v0.1.3...v0.1.4)

### Added

* New `channel_priority` argument in `create_env()` and `install_packages()`
  to control channel priority strategy.

* Condathis now supports system installed `micromamba` binaries.
  For that we added 1 new option and 1 environment variable to control that behavior.
  `condathis.micromamba_path` and `"CONDATHIS_MICROMAMBA_PATH"` respectively.
  The order of discovery is as follows:
  * User override via `getOption("condathis.micromamba_path")`.
  * User override via `CONDATHIS_MICROMAMBA_PATH` environment variable.
  * condathis internal managed path (`micromamba_bin_path()`).
  * R-in-conda: micromamba adjacent to R's own installation prefix.
  * Active conda environment (`CONDA_PREFIX`).
  * condathis managed micromamba-env fallback.
  * System PATH (`Sys.which("micromamba")`).

### Changed

* Internal `micromamba` version bump to "2.8.1-0".

* `clean_cache()` now also removes any additional cache files created in the
  path reported by `tools::R_user_dir(package = "condathis", which = "cache")`.

* Order of `channels` argument changed to have `"conda-forge"` as the first
  option as for using `channel_priority = "strict"` the order of the channels
  matters.
  Note that relying solely on channel order for priority is not recommended.
  Use explicit syntax like: `bioconda::samtools==X.Y.Z` for better guarantee
  of reproducibility.

* `create_env()` now properly parses MatchSpec version constraints strings to
  define if environment needs to be recreated using new internal functions
  `parse_match_spec()` and `version_spec_contains()` to parse Conda MatchSpec
  and use VersionSpec to compare versions, following CEP29 and CEP33, respectively.

### Fixed

* Fix error in `create_env()` when packages were specified with `"channel::package"` environment was always recreated.

## condathis 0.1.3

Release Date: 2025-11-07

Development Changelog: [0.1.3](https://github.com/luciorq/condathis/compare/v0.1.2...v0.1.3)

### Added

* New `clean_cache()` function to clean the local package cache.

* New `verbose = "spinner"` strategy to show only spinner animation
  in interactive sessions.
  Spinner is always silenced in non-interactive sessions.

### Changed

* Internal `micromamba` version bump to "2.3.3-0".

* Argument `verbose = TRUE` is now converted to `verbose = "output"` by
  default in all exported functions.

* Argument `verbose` in `create_env()`, `run()`, `run_bin()`,
  and `install_micromamba()` are set to `verbose = "output"` by default.
  All internal calls to other functions are kept as `"silent"`, unless when
  calling the user-facing function with `verbose = "full"`.

* Argument `verbose = "silent"` now also silences the spinner animation in
  interactive sessions.

### Fixed

* Ignore `CONDA_ENVS_DIRS` environment variable.

## condathis 0.1.2

Release Date: 2025-06-02

Development Changelog: [0.1.2](https://github.com/luciorq/condathis/compare/v0.1.1...v0.1.2)

### Added

* New `stdin` argument to `run()` and `run_bin()` functions, allowing input to
  be redirected via standard input (`stdin`) via a text file for commands that
  require it.

* Argument `verbose` included in `install_micromamba()` and other auxiliary
  functions, allowing message suppression in all package functions.

### Changed

* Internal `micromamba` version bump to "2.1.1-0".

* `with_sandbox_dir()` now also defines temporary cache directory paths,
  using `R_USER_CACHE_DIR` and `XDG_CACHE_HOME` environment variables.

### Fixed

* Fix parsing of error messages with curly braces in `run()` and `run_bin()`,
  in the rethrown error, when `error = "cancel"`.

## condathis 0.1.1

Release Date: 2025-01-24

Development Changelog: [0.1.1](https://github.com/luciorq/condathis/compare/v0.1.0...v0.1.1)

### Changed

* Internal `micromamba` version bump to "2.0.5-0".

### Fixed

* Fix error in `run_bin()` when `error = "continue"` and `cmd` is not on
  PATH nor in the environment.
  The expected behavior is to not fail (#23).

* Fix error in `create_env()` that would fail if debris from failed installation
  attempts were left in the environment path.

## condathis 0.1.0

Release Date: 2024-12-10

Development Changelog: [0.1.0](https://github.com/luciorq/condathis/compare/v0.0.8...v0.1.0)

### Added

* Initial submission to CRAN.
* New Package Logo.

### Fixed

* `run()` always creates empty base environment if it does not exists yet.

## condathis 0.0.8

### Breaking changes

* `env_exists()` now errors if no argument is supplied.

* The base directory path used for creating the environments is now controlled
  by `tools::R_user_dir()` and accepts `R_USER_DATA_DIR`, and `XDG_DATA_HOME`,
  respectively as environment variables that can control that path.
  On Unix/Linux it should be `"${HOME}/.local/share/R/condathis"`.

* The default `TMPDIR` for all `run()` and `run_bin()` calls is cleaned after
  execution.

* All error messages are resurfaced in the exported function call instead of
  being thrown in the internal `processx` call.

* New classes were added to the error condition in most functions.

### New features

* New `with_sandbox_dir()` allow for isolated tests and examples.

### Minor improvements and fixes

* Improved error message in `list_packages()` when environment doesn't exist (#21).

* Improved message in `install_packages()`.

* Spinner is only active when session is interactive.

## condathis 0.0.7

### New features

* `install_micromamba()` now tries to download an uncompressed version of the
  'micromamba' binary if `untar()` fails because of missing `bzip2` system
  library. (#10 and #14)

* New `parse_output()` parses lines output streams from `run()` results into
  character vectors.

* New `run_bin()` runs binary installed in a Conda environment without wrapping
  in `micromamba run`.

### Minor improvements and fixes

* Internal `micromamba` version bump to "2.0.4-0".

* `create_env()` and `remove_env()` have improved output.

## condathis 0.0.6

### Breaking changes

* `method = "auto"` no longer exists. For backward compatibility will fall back
  to `method = "native"`.
  * All container back-end methods were removed and `method = "native"` is the
    only `method` supported using just this package.
  * A method for supplying additional backends from other packages is planned
    to be implemented.

### Minor improvements and fixes

* Remove dependency on `dockerthis`.

* Fix error in `run()` when `verbose` argument was not supplied.

## condathis 0.0.5

### Breaking changes

* `verbose`, levels `TRUE` and `FALSE` are now soft deprecated.
  For previous functionality `"full"` and `"silent"` should be used respectively.

### New features

* `run()` now has `error` argument.

### Minor improvements and fixes

* `run()` output now has class `"condathis_run_output"` with custom print method.
* `run()` now exposes `stderr`.
* `verbose` now accepts any of `c("silent", "full", "cmd", "output")`.
  `TRUE` and `FALSE` are deprecated but still kept for compatibility.
* Improved error handling in `run()` when invalid arguments are provided.

## condathis 0.0.4

### Breaking changes

* `create_env()` new argument default `overwrite = FALSE`,
  since the previous behavior would allow for the environment to always be overwritten.
  For previous behavior use `overwrite = TRUE`.

* Across the entire package `verbose = FALSE` is default.

### New features

* New `get_env_dir()` retrieves path to environment (v0.0.3.9032).

* `create_env()` now has `overwrite = FALSE` argument (v0.0.3.9030).

* `install_micromamba()` now has `micromamba_version` argument (v0.0.3.9025).

* Add support for internal `micromamba` versions above v2.0 (v0.0.3.9024).

* New `remove_env()` created (v0.0.3.9012 #7).

### Minor improvements and fixes

* `native_cmd()` now uses additional Environmental Variables for removing
  warnings when calling nested `micromamba run` (v0.0.3.9029 #13).

* Standardize argument order passed to `micromamba`, since v2.0, order of some
  arguments starts to conflict (v0.0.3.9027).

* On Windows, the "BAT" file used by `micromamba run` is renamed (v0.0.3.9026 #11).

* Internal `micromamba` version is upgraded to "2.0.2-0", fixes warnings about
  missing prefixes (v0.0.3.9028).

* The internal `micromamba` version is now fixed (currently "v2.0.1-0") (v0.0.3.9025).

* Use GitHub releases as the primary URL for installing `micromamba` (v0.0.3.9025).

* Move `--no-rc` and `--no-env` arguments to `native_cmd()` (v0.0.3.9024).

* Fix path handling in Windows (v0.0.3.9023).

* Add `mode = "wb"` to internal `download.file()` for handling binary downloads
in Windows (v0.0.3.9023).

* `list_envs()` and `list_packages()` use `--no-rc` internally (v0.0.3.9022).

* `create_env_*()`, `packages_search_*()`, and `install_packages()` now uses
  `--no-rc` and `--override-channels` (v0.0.3.9020).

* Remove "defaults" channel (`-c defaults`) from all functions (v0.0.3.9020).

* `create_env_*()`, `packages_search_*()`, and `install_packages()` uses
  `--no-channel-priority` internally (v0.0.3.9019).
