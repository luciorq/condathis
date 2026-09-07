## condathis 0.2.0 (Development Version)

Development Changelog: [dev](https://github.com/luciorq/condathis/compare/v0.1.4...HEAD)

This release is being tracked as a minor version bump instead of a patch
(`0.1.5`) because its centerpiece - the pluggable backend system - is a
structural, package-wide refactor: every environment-management function
now dispatches through a backend registry instead of hardcoding the managed
`micromamba` installation, laying the foundation for future backends (e.g.
an in-process `rattler` engine) to plug in without further changes to the
public API. It also carries several other breaking (though narrow) changes
alongside it - see below.

### Backend System

* `condathis` now has a pluggable backend system. Internally, every
  environment-management operation (`create_env()`, `install_packages()`,
  `remove_env()`, `list_envs()`, `env_exists()`, `list_packages()`,
  `get_env_dir()`, `get_install_dir()`, and, for the environments it can
  already execute through, `run()`, `run_bin()`, `run_pipeline()`) now
  dispatches to a registered *backend* instead of hardcoding the managed
  `micromamba` installation. `"micromamba"` is the built-in default and,
  today, the only registered backend - this is the foundation for future
  backends (e.g. an in-process `rattler` engine, or container-based
  engines) to plug in later without changing any of the functions above.
  All of these functions gain a new `method` argument: `"auto"` (the
  default) resolves automatically - an existing environment's own owning
  backend, or `getOption("condathis.backend_priority")` order for a new
  one; `"micromamba"` selects it explicitly. `"native"` (the old default)
  is now a deprecated alias for `"micromamba"` and warns once per session,
  but keeps working exactly the same. If you never pass `method`, nothing
  about your existing code changes.

* New exported extension API for backend authors: `register_backend()`
  (the extension point itself - its documentation specifies the full
  10-function backend contract, the class convention, and the
  load-order-safe `.onLoad()`/`setHook()` registration pattern),
  `unregister_backend()` (for a backend package's `.onUnload()`), and
  `list_registered_backend_names()` (introspection: what's currently
  plugged in). These are aimed at packages providing alternative
  execution engines, not at end users - regular `condathis` usage never
  needs them. This extension API is **experimental**: the backend
  contract may change in breaking ways between `0.x` releases as the
  first external backends are wired in (see `register_backend()`'s
  *Lifecycle* section).

* **Breaking (minor):** `get_install_dir()` and `list_envs()` now return a
  tibble-classed data frame instead of a bare character vector/string, so
  they can report results across more than one backend. `get_install_dir()`
  gains `backend`/`path` columns; `list_envs()` gains `backend`/`env_name`/
  `path` columns. With a single registered backend (today's default),
  this is always one row per environment (or one row total for
  `get_install_dir()`), just no longer a bare vector - code checking
  `is.character(get_install_dir())` or iterating `for (e in list_envs())`
  needs to switch to `get_install_dir()$path` / `list_envs()$env_name`.
  `env_exists()` is unaffected - it still returns a plain `TRUE`/`FALSE`.

* `list_packages()`'s columns are now documented as backend-dependent:
  only `name`, `version`, `build_number`, and `channel` are guaranteed
  present across every backend. The `"micromamba"` backend's other
  columns (`base_url`, `build_string`, `dist_name`, `platform`, `md5`,
  `sha256`, `url`) are unchanged, just no longer part of the documented
  cross-backend guarantee.

### Added

* New `run_pipeline()` function for Unix-style pipeline execution
  (`cmd1 | cmd2 | cmd3`) based on `processx` 3.9.0 kernel-level pipes.
  Each command in the pipeline can run in a different Conda environment.
  Returns an S3 `condathis_pipeline` object with per-process status, stdout
  (last process only), stderr, and PID.
  Supports `stdin` file redirection, writable `stdin = "|"` with an `input`
  value written to the first command, per-command `stdout`/`stderr`
  overrides in the `cmds` named list spec (`stdout` only on the last
  command), `error = "cancel"` / `"continue"`, and automatic crash cleanup
  via `supervise = TRUE`.

* New arguments that exists in both `run()`, `run_bin()`, `run_pipeline()`:
  * New `supervise`, `cleanup_tree`, and `linux_pdeathsig` arguments for
    crash-safe process cleanup
    . Default to `FALSE`, preserving existing behavior.
  * New `input` argument: writable `stdin = "|"` support, writing
    character/raw data directly to the process's standard input - matching
    `run_pipeline()`'s `input` argument. Previously `stdin` only accepted
    `NULL` or a file path.
  * Both now return a `condathis_result` S3 object instead of a plain
    `processx::run()` list. It remains fully usable as a list (`res$status`,
    `res$stdout`, etc. are unchanged) and adds `pid`, `cmd`, and `env_name`
    fields plus `print()`/`format()` methods, mirroring `condathis_pipeline`.

* `run_pipeline()`'s `supervise`, `cleanup_tree` (previously always `TRUE`),
  and `linux_pdeathsig` (new) are now overridable arguments instead of
  hardcoded, for full parity with `run()`/`run_bin()`.

* New `binary` argument (defaults to `FALSE`) on `run()`, `run_bin()`, and
  `run_pipeline()`: captures stdout/stderr as raw vectors instead of
  decoding them as UTF-8 text, so binary output (images, compressed data,
  etc.) round-trips correctly. Since a process's stdout and stderr share one
  encoding, both streams come back raw when `TRUE` - check with `is.raw()`
  before treating either as text. `format()`/`print()` on the resulting
  `condathis_result`/`condathis_pipeline` objects, and `parse_output()`, all
  handle raw streams safely (`parse_output()` errors with class
  `condathis_parse_output_binary_stream` if asked to parse one). Binary
  streams are never live-echoed to the console.

* New `timeout` argument on `run()`, `run_bin()`, and `run_pipeline()`:
  maximum number of seconds to let a command (or, for `run_pipeline()`, the
  whole pipeline) run before it's killed. Defaults to `Inf` (no limit, the
  previous behavior). On expiry, the process is killed (`status = -9`) and
  `timeout` is `TRUE` in the returned result; `error = "cancel"` (the
  default) aborts with a dedicated class (`condathis_run_timeout_error` /
  `condathis_pipeline_timeout_error`) instead of the regular
  status-error class, so you can tell a timeout apart from an ordinary
  failed command; `error = "continue"` returns the result normally instead
  of aborting. For `run_pipeline()`, `timeout` applies to the pipeline as a
  whole (one shared deadline across every command, not per-command); any
  output a killed stage had already produced is preserved.

* `install_micromamba()` now verifies the downloaded `micromamba` binary
  against its official checksum. If it doesn't match - or the check can't
  be run at all, for any reason - you'll see a warning, but the install
  still completes; this never blocks you. On R 4.5 and newer this needs no
  extra software at all; on older R it prefers the optional `digest`
  package if you have it installed, and only as a last resort falls back
  to a `sha256sum`/`shasum` program on your system, which is verified to
  actually work correctly before being trusted.

### Changed

* `condathis` no longer temporarily mutates the calling R session's
  environment variables while running commands. Previously, every
  execution path applied its conda-isolation overrides (`R_HOME = ""`,
  `TMPDIR`, `CONDA_*`/`MAMBA_*`, and for `run_bin()` also `PATH`) to the
  *session* for the duration of the child process, and any R code that
  happened to run during that window - console callbacks, condition
  handlers, code in an interrupt path - observed the corrupted values
  (most visibly `R.home()` returning nonsense while `R_HOME` was
  blanked). Child processes now receive an explicitly constructed
  environment block instead, and the session is never touched. Behavior
  of the child processes themselves is unchanged.

* **Breaking (minor):** the default `channels` for `create_env()` and
  `install_packages()` is now just `"conda-forge"` - `"bioconda"` is no
  longer included implicitly. Aligns `condathis` with plain `micromamba`
  behavior and avoids solving against a channel most environments never
  use. Code that installs bioconda packages needs the channel stated
  explicitly, in either of two ways: a channel-prefixed package spec -
  `create_env(packages = "bioconda::samtools")` pulls the package *and*
  its bioconda dependencies with no other change - or the channel
  argument, e.g. `channels = c("conda-forge", "bioconda")`. Calls that
  already passed `channels` explicitly are unaffected.

* **Breaking (minor):** the default `channel_priority` for `create_env()`
  and `install_packages()` is now `"strict"` (previously `"disabled"`),
  matching `micromamba`'s own recommended default: when multiple channels
  provide the same package name, only the highest-priority channel's
  builds are considered, which keeps resolution reproducible and prevents
  accidental cross-channel mixing. Pass
  `channel_priority = "disabled"` (or `"flexible"`) to restore the
  previous behavior for a specific call. Note for existing environments:
  `install_packages()`'s channel-history warning may now fire for
  environments created before this change with the old implicit
  `"bioconda"` default - add the channel it names to `channels` or
  `additional_channels` to silence it.

* `run()` and `run_bin()` gain feature parity with `run_pipeline()`:
  * New `supervise`, `cleanup_tree`, and `linux_pdeathsig` arguments for
    crash-safe process cleanup (previously only available, and always on,
    in `run_pipeline()`). Default to `FALSE`, preserving existing behavior.
  * New `input` argument: writable `stdin = "|"` support, writing
    character/raw data directly to the process's standard input - matching
    `run_pipeline()`'s `input` argument. Previously `stdin` only accepted
    `NULL` or a file path.
  * Both now return a `condathis_result` S3 object instead of a plain
    `processx::run()` list. It remains fully usable as a list (`res$status`,
    `res$stdout`, etc. are unchanged) and adds `pid`, `cmd`, and `env_name`
    fields plus `print()`/`format()` methods, mirroring `condathis_pipeline`.

* `run_pipeline()`'s `supervise`, `cleanup_tree` (previously always `TRUE`),
  and `linux_pdeathsig` (new) are now overridable arguments instead of
  hardcoded, for full parity with `run()`/`run_bin()`.

* **Breaking (minor):** `create_env()`, `install_packages()`, `remove_env()`,
  and `clean_cache()` now return the same kind of result object as `run()`/
  `run_bin()` (a `condathis_result`), instead of a plain, unlabeled list.
  If your code only reads `res$status`, `res$stdout`, or `res$stderr`,
  nothing changes - that keeps working exactly as before. What's new: every
  result now also includes `res$pid`, `res$cmd`, and `res$env_name`, and
  simply printing a result (e.g. typing it at the console, or letting it
  auto-print) now shows a short, readable summary instead of a raw list
  dump. The one thing that *can* break: code that checks the exact class
  of the result (for example `is.list(res) && !inherits(res, "condathis_result")`,
  or anything comparing `class(res)` to `"list"`). If you need a plain list
  back, `as.list(res)` gives you one.

* **Breaking (minor):** in `run_pipeline()`'s result, each step in
  `res$processes` (e.g. `res$processes[[1]]`) is now that same kind of
  result object too, not a plain list. You can now `print()` or `format()`
  a single step on its own, not just the whole pipeline result. Each step
  also gains a `timeout` field, `TRUE` for whichever step(s) were still
  running when `run_pipeline()`'s own `timeout` expired. As above,
  `res$status`/`res$stdout`/`res$stderr`/`res$cmd`/`res$env_name`/`res$pid`
  all still work the same way; only code checking the exact class of an
  individual step is affected.

* `install_packages()` now validates its arguments upfront instead of
  letting bad input reach `micromamba` (or a plain base-R error): calling
  it without `packages` (or with `packages = NULL`) now gives a clear,
  classed error (`condathis_install_packages_missing_packages`) instead of
  a generic "argument is missing" error; an invalid `env_name` (not a
  single, non-missing character string) now errors the same way
  `env_exists()` and `get_env_dir()` do. Its check for whether the target
  environment already exists now uses `env_exists()` internally (same
  result, clearer code) instead of `list_envs()` plus a manual `%in%`
  check.

* `get_env_dir()` now validates `env_name` (a single, non-missing character
  string) instead of silently building a nonsensical path - for example, a
  multi-element `env_name` used to silently return a vector of paths.

* `install_packages()` now warns when the target environment was previously
  installed using a channel that is not included in the current call (e.g.
  creating an environment with `channels = "conda-forge"` and later calling
  `install_packages()` with `channels = "bioconda"` only). The channel used
  is recorded per package in the environment's `conda-meta/history` file;
  dropping a previously-used channel can change how dependencies resolve.
  The install still proceeds - this is a warning, not an error.

* **Breaking (minor):** `env_exists()` now raises a clear error if
  `env_name` isn't a single, real environment name (for example `NULL`,
  `NA`, a number, or a vector of more than one name). Previously, these
  invalid inputs silently returned `FALSE`, which looked exactly the same
  as "that environment doesn't exist" - an easy way to hide a mistake in
  your own code. If you were deliberately relying on `env_exists(NULL)` or
  `env_exists(NA)` returning `FALSE`, that call now errors instead;
  everything else (checking a real environment name) is unaffected.

* **Breaking (minor):** `run()` no longer creates any environment when the
  one you asked for (`env_name`) doesn't exist - it errors instead,
  telling you to create it first. Previously, if you gave a custom
  `env_name` that didn't exist, `run()` would silently create an unrelated,
  empty `"condathis-env"` as a side effect (left over from a workaround for
  an old `micromamba` limitation that no longer applies) and then still
  fail anyway, just with a more confusing error. The one thing that keeps
  working exactly as before: calling `run()` without specifying `env_name`
  at all still auto-creates the default `"condathis-env"` for you, since
  that's a deliberate convenience, not the bug being fixed here. With
  `error = "continue"`, a missing custom environment now gives you back a
  result with `status = 127` instead of erroring.

### Fixed

* Fix `run_pipeline(stderr = "some-file")` losing every command's stderr
  except the last one to open the file: each command's process opened
  (and truncated) the shared path independently, clobbering what earlier
  commands had written - worst exactly when a middle command failed and
  its stderr was what the file was meant to keep. Each command now writes
  to its own temporary file and the requested file is assembled once, in
  command order, after the pipeline finishes (including when it aborts
  under `error = "cancel"`).

* Fix a low-level "broken pipe" error escaping when a command exits
  before consuming its `input` (e.g. a large `input` written to a command
  that fails immediately): in `run()`/`run_bin()` it was misreported as a
  status-127 "command not found", masking the real exit status, and in
  `run_pipeline()` it escaped even under `error = "continue"`. The
  undeliverable input is now simply abandoned and the command's own exit
  status is reported, on every platform.

* Fix a single stale environment entry (e.g. in
  `~/.conda/environments.txt`, or an environment removed by another
  process mid-call) breaking every environment at once: realizing the
  listed paths errored on the first one that no longer existed, which
  aborted `list_envs()` entirely and made `env_exists()` report
  *existing* environments as absent. Vanished paths are now dropped
  individually and never affect the others.

* Fix `run()` and `run_pipeline()` refusing to execute ("environment
  does not exist") when the environment existence check itself failed
  (transient lock, corrupt listing metadata, and similar): a failed check
  is no longer treated as "absent" - execution proceeds, and a genuinely
  missing environment still fails with the backend's own clear error.

* Fix an unreadable low-level JSON error when resolving activation for an
  environment whose `activate.d` hook scripts print to stdout (e.g. a
  package that echoes a banner on activation): the activation dump is now
  fenced with markers so hook output cannot corrupt it, and a genuinely
  broken dump reports a clear, classed error naming the environment.

* Fix `run_pipeline(activate = FALSE)` still performing the full
  activation resolution it was asked to skip (two extra subprocess spawns
  per environment on a cache miss) and still inheriting activation's
  failure modes - a failing `activate.d` hook aborted the whole pipeline
  even under `error = "continue"`. The activation-free path now resolves
  the executable directly and never touches activation.

* Fix `install_micromamba(force = TRUE)` destroying a working
  `micromamba` installation when the download failed: the standalone-
  binary download strategy wrote directly onto the live binary path, and
  its per-mirror cleanup deleted that path after every failed mirror - so
  a forced reinstall on a machine with unreachable mirrors (e.g.
  offline) deleted the existing binary and then aborted, leaving nothing.
  Downloads now go to a temporary path and only replace the existing
  binary once a complete new one exists; a failed install still aborts
  (the requested version was not installed), but the previous working
  binary survives.

* Fix `run_pipeline()` deadlocking permanently once the data flowing
  between commands exceeded the OS pipe buffers (~64KB): stages' captured
  streams were drained one stage at a time, leaving the last command's
  output pipe unread while earlier stages were waited on, and the
  resulting backpressure froze every process in the pipeline - reproduced
  with `seq 1 500000 | cat`. All stages' captured streams are now drained
  concurrently in a single poll loop, on every platform.

* Fix `timeout` being silently unenforced in `run()`/`run_bin()` when
  both `stdout` and `stderr` are redirected to files (or the child closes
  its streams but keeps running), and in `run_pipeline()` for commands
  with no captured streams (e.g. `stderr = NULL`): the final wait on the
  child was unbounded, so a 2-second timeout could wait out a
  100-second command. The remaining time budget is now always enforced
  with a bounded wait, and expiry reports the same `status = -9` /
  `timeout = TRUE` result as any other timeout.

* Fix `run_pipeline(activate = FALSE)` building a corrupted `PATH` for
  its child processes on Windows: the hand-rolled activation used the
  POSIX `":"` separator and a POSIX-only `bin/` layout. It now uses the
  platform's real separator and the same Windows-aware environment
  layout (`Scripts/`, `Library/bin/`, ...) the rest of the package uses.

* Fix the cached `micromamba` activation variables freezing the session
  `PATH` of whichever call first resolved an environment into every later
  call for it: directories removed from the session `PATH` afterwards
  were resurrected in child processes, later additions were missing, and
  one caller's transient `PATH` prefix could leak into unrelated calls.
  The cache now stores only the directories activation *adds*, and the
  final `PATH` is composed against the live session `PATH` on every use.

* Fix `install_micromamba()` always creating the default `"condathis-env"`
  as an undocumented side effect of installing the binary, even when
  triggered incidentally by an unrelated, read-only call (for example
  `env_exists()`) that happened to need a first-time install because no
  `micromamba` binary was available anywhere yet. `install_micromamba()`
  is documented to install the binary only; this leftover, no-longer-needed
  workaround (the same kind `run()`'s own auto-create logic already dropped)
  made a fresh install root end up with an unwanted default environment
  the caller never asked for. `run()`, `run_pipeline()`, and
  `list_packages()` each already auto-create `"condathis-env"` themselves,
  correctly scoped to only when it's actually the target - that behavior
  is unaffected.

* Fix `run_pipeline()` checking that Conda environments exist before
  attempting to auto-create the missing default environment, which made the
  auto-create path unreachable.

* Fix `run_pipeline()` crashing when reading `stdout`/`stderr` for a process
  whose output was redirected to a file or discarded (`NULL`) instead of
  captured with `"|"`.

* Fix `run_pipeline()` letting a raw `processx` error escape uncaught when a
  command is not found, ignoring the `error` argument entirely. It now
  matches `run()`: `error = "continue"` reports `status = 127` for that
  command and keeps running the rest of the pipeline; `error = "cancel"`
  throws a `condathis_pipeline_status_error` instead of a low-level error.

* Fix `run_pipeline()` error messages breaking (or silently corrupting) when
  a failing command's `stderr` contained curly braces, since
  `cli::cli_abort()` interprets `{`/`}` as glue syntax. Captured stderr,
  command strings, and environment names are now escaped before being
  embedded in the error message.

* Fix `run_pipeline()` always throwing on a missing custom environment
  regardless of `error`. `error = "continue"` now reports `status = 127` for
  commands targeting that environment instead of aborting the whole
  pipeline; `error = "cancel"` keeps the previous fail-fast behavior.

* Fix `run_pipeline()` hanging indefinitely on native Windows for any
  pipeline of 2 or more commands. Caused by three compounding issues in how
  inter-process pipes were created and managed: using the non-blocking,
  R-facing `processx::conn_create_pipepair()` instead of
  `conn_create_proc_pipepair()` (documented as required for correct
  child-to-child stdin/stdout behavior on Windows); deferring the parent's
  own copies of pipe handles from closing until every process in the
  pipeline had spawned, instead of closing each one immediately after use;
  and defaulting every process to `supervise = TRUE`, which spawns an extra
  Windows helper process per stage that can itself hold the piped stdout
  open, preventing the next stage from ever seeing EOF. `run_pipeline()`
  now forces `supervise = FALSE` on Windows regardless of the `supervise`
  argument (unaffected on Linux/macOS, where the hang does not occur).

* Fix `run()`/`run_bin()`'s `stdin = "|"` silently truncating `input`
  larger than the OS pipe buffer (confirmed: only 8192 of 200000 bytes
  delivered on macOS, no error) - a single non-blocking `write_input()`
  call can short-write and discard the undelivered remainder. Also fixes a
  related deadlock in `run()`, `run_bin()`, and `run_pipeline()`: reading
  `stdout` and `stderr` sequentially (or calling `wait()` before draining
  either) can hang once combined output exceeds the OS pipe buffer, because
  the child blocks writing to whichever stream isn't being read yet. Both
  fixed by a shared internal helper that writes/polls/drains all of a
  process's streams concurrently instead of one at a time.

* Fix `install_micromamba()` intermittently reporting a freshly
  downloaded/extracted `micromamba` binary as missing on Windows.
  Antivirus real-time scanning can briefly hold its own handle on a
  just-written executable, making a `file.exists()` check performed
  immediately afterward return `FALSE` even though the file is present -
  confirmed directly (a `force = TRUE` reinstall failed once, then
  succeeded on an immediate retry with no code change). The existence
  check now polls briefly before giving up.

* Fix `get_micromamba_activation_envvars()`'s noise-filtering only
  stripping `processx`'s `PROCESSX_PS2...` tracking variable and not the
  similarly PID/hash-suffixed `PROCESSX_PS3...` (and potentially further
  numbered variants), letting it leak into the returned environment
  variables and making two otherwise-identical resolutions of the same
  Conda environment compare as different on every call.

* Fix `list_envs()` occasionally returning a plain number instead of a
  character vector of environment names, in the rare case where the
  underlying command failed in an unusual way. It now always reports that
  kind of failure as a proper error, so code calling `list_envs()` can
  rely on always getting back either a vector of names or an informative
  error - never a bare number.

* Fix `list_packages()` crashing with a confusing, low-level R error
  (`object 'pkgs_df' not found`) in that same kind of rare failure case.
  It now reports a clear, consistent error instead.

* Fix `list_envs()` matching environment paths against the install
  directory as a pattern instead of literal text, which could in rare
  cases match a directory that only looked similar (for example, one
  differing by a single character where the install path happens to
  contain a `.`). It now compares the literal path.

* Removed the `micro.mamba.pm` mirror from `install_micromamba()`'s
  download attempts. It no longer serves specific, pinned versions (only
  the latest release), and `condathis` always requests a pinned version,
  so every attempt against it was guaranteed to fail before falling
  through to a working mirror. Removing it makes installs slightly faster
  when the first mirror is unavailable, with no change in which version
  gets installed.

## condathis 0.1.4

Release Date: 2026-06-19

Development Changelog: [0.1.4](https://github.com/luciorq/condathis/compare/v0.1.3...v0.1.4)

### Added

* New `channel_priority` argument in `create_env()` and `install_packages()`
  to control channel priority strategy.

* Condathis now support system installed `micromamba` binaries.
  For that we added 1 new option and 1 environment variable to control that behavior.
  `condathis_micromamba_path` and `"CONDATHIS_MICROMAMBA_PATH"` respectively.
  The order of discovey is as follows:
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
  define if environment need to be recreated using new internal functions
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

* Argument `verbose = "silent"` now also silence the spinner animation in
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

* `env_exists()` now error if no argument is supplied.

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

* New `get_env_dir()` retrieves path to environment v(0.0.3.9032).

* `create_env()` now has `overwrite = FALSE` argument v(0.0.3.9030).

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

* `list_envs()` and `list_packages()` uses `--no-rc` internally (v.0.0.3.9022).

* `create_env_*()`, `packages_search_*()`, and `install_packages()` now uses
  `--no-rc` and `--override-channels` (v0.0.3.9020).

* Remove "defaults" channel (`-c defaults`) from all functions (v0.0.3.9020).

* `create_env_*()`, `packages_search_*()`, and `install_packages()` uses
  `--no-channel-priority` internally (v0.0.3.9019).
