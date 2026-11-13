# feat-strict-defaults: align defaults with plain micromamba

Date: 2026-08-26

## Goal

Housekeeping milestone bringing condathis's dependency-resolution defaults
closer to plain `micromamba` behavior, with stricter resolution:

1. Remove `bioconda` from the default `channels` (now `"conda-forge"` only).
2. Make `bioconda` explicit where needed in docs.
3. Make `"strict"` the default `channel_priority` (was `"disabled"`).

## Key facts established before implementing

- A channel-prefixed MatchSpec (`bioconda::samtools`) resolves correctly
  with only `-c conda-forge` under `--override-channels` + strict
  priority: micromamba adds the spec's channel to the solve, including
  for the package's own bioconda dependencies (verified via
  `micromamba create --dry-run --json --platform` probe; `htslib` came
  from bioconda, `libdeflate` from conda-forge). So spec-prefixed doc
  examples keep working with the conda-forge-only default.
- `rlang::arg_match()` takes the first element of the formal default as
  the effective default, so the `channel_priority` change is a reorder of
  the `c(...)` vector at every signature.

## Touched surface

- Formal defaults (`channels`, `channel_priority`): `create_env()`,
  `install_packages()`, `backend_create_env()`/`backend_install()`
  generics (R/backend.R), their micromamba methods
  (R/backend-micromamba.R), `define_platform()`,
  `packages_search_native()`, `parse_strategy_channel_priority()`, and
  `format_channels_args()`'s NULL fallback.
- Docs: `@param channels`/`@param channel_priority` text; guidance on the
  two explicit-bioconda options (spec prefix vs. channels argument).
  Vignette + README already passed `channels` explicitly - unchanged.
- Tests: `test-format_channels_args.R` and
  `test-parse_strategy_channel_priority.R` default assertions.
- NEWS.md: two Breaking (minor) bullets under 0.2.0's Changed section,
  including the migration note about `install_packages()`'s
  channel-history warning firing for pre-change environments.

## Addendum 2026-09-05: deadlock/timeout fix cluster + convergence goal

Fixes from the pre-release /code-review (findings 1, 3, 4):

- New `pump_pipeline_io()` (R/pump_pipeline_io.R): drains every stage's
  R-side streams concurrently in one `processx::poll()` loop, interleaved
  with writing `input` to stage 1. Replaces the sequential per-stage
  `pump_process_io()` calls that deadlocked on cross-stage backpressure
  (reproduced: `seq 1 500000 | cat` hung forever). Also guards the
  stage-1 `write_input()` against broken pipe (child exited early).
- `settle_pipeline_stage()` (was `drain_pipeline_stage()`): no stream
  draining anymore; enforces the shared deadline with a *bounded*
  `wait(timeout = remaining_ms)` so stages invisible to the pump (no
  R-side pipes, e.g. `stderr = NULL`) still honor `timeout`.
- `run_process_with_input()`: same bounded-wait fix for `run()`/
  `run_bin()` with file-redirected streams.
- Platform notes:
  - `processx::poll()` multi-process polling and `wait(timeout=)` are cross-platform.
  - Stages with no R-side connections are excluded from the poll list.
  - `-9` remains condathis's own normalized timeout sentinel on every OS.
  - Tests deliberately do not assert on a downstream stage's exact post-kill status
    (EOF-exit vs kill is a timing race that differs across platforms).

## North star: run()/run_bin()/run_pipeline() convergence

Stated goal (2026-09-05): the three run functions should converge to the
same argument set and the same behavior/failure contract on every major
OS. Progress so far: shared `condathis_result` shape, shared
`error`/`timeout`/`binary`/`stdin`+`input` semantics, shared `-9`
timeout sentinel, shared child-environment construction
(`build_child_env()`), and (this addendum) shared deadline enforcement
and concurrent stream draining.
Known remaining gaps:

- Activation model: `run()` wraps in `micromamba run` (live activation,
  hooks re-run per call, no `activate` argument).
  `run_bin()`/`run_pipeline()` apply the cached activation snapshot with a direct
  spawn.
  Unifying `run()` onto the resolve-once + direct-spawn model is
  the documented final step (see get_micromamba_activation_envvars.R),
  deferred past 0.2.0 because it changes observable hook semantics.
- Binary resolution: micromamba's activated-PATH search (run()) vs
  condathis's `resolve_env_bin_path()` (run_bin()/run_pipeline()).
- Argument set: `activate` missing from `run()`; `run_pipeline()` has
  pipeline-only extras (`cmds` spec, per-command overrides) by nature.

The convergence is still open: `../post-0.2.0/PLAN.md` items 1 and 6.

## Addendum 2026-11-13: 0.2.0 CRAN preparation

Written 2026-11-13. This section records what was decided, found and
built while preparing 0.2.0 for CRAN on 2026-11-12 and 2026-11-13. The
checklist is in `TODO.md` (same section numbers). The short release
prompt is in `HANDOFF.md`. Open items moved to `../post-0.2.0/`.

### Context

- CRAN has condathis 0.1.4 (published 2026-06-19). The stacked PRs #34,
  #35 and #37 and the backends article (PR #38) are merged into `main`.
  `DESCRIPTION` says `Version: 0.2.0` since `f582ba1`.
- The maintainer committed the CRAN preparation as `8cffc25` ("feat:
  prepare condathis 0.2.0 for CRAN"), after the verification of
  section 8 (round 3).
- The `env_definition()` work came after that commit and is not
  committed yet (`git diff HEAD`, plus the untracked
  `R/env_definition.R`, `R/env_definition_checks.R`,
  `R/backend-micromamba-definition.R`, `man/env_definition.Rd` and
  `tests/testthat/test-env_definition.R`). Its design, decisions and
  findings are in `../feat-env-file/`. This section only says where it
  touches the release.

The maintainer's requests, in order (2026-11-12 and 2026-11-13):

1. "Prepare everything in this package for a CRAN submission"
2. After the audit: "Fix everything. Also review all docs and fix
   inconsistencies and missing information and things that are not in
   sync. Do not forget about the README"
3. After the fixes: "Everything sounds right. The only point I would
   make sure to review is allowing the `packages = c()` to coexist with
   `...` on create_env() because that would be one of hardest breaking
   changes from the previous API" (section 5).
4. "I want all if it implemented now in v0. 2 deprecate env_file"
   (section 7 and `../feat-env-file/`), after two questions about
   `env_file =` quoted there (decisions D1 and D2). Between 3 and 4 the
   maintainer also asked about rlang and partial matching (section 5f).
5. "Don't add decision only to memory. Update the dev docs at
   .github/devdocs/ with all new features and design decisions." (this
   addendum).

How the work was done: every check ran on an rsync copy of the tree,
never in the repo, with the `XDG_*` directories (and `HOME`, except on
omicron) pointed to scratch directories (`.github/AGENTS.md`, "Testing
rules"). The verification runs compared the user's `~/.mamba`,
`~/.conda` and condathis data directory before and after. Lesson from
the audit: raw micromamba runs with only the `XDG_*` variables
overridden still appended two lines to the real
`~/.conda/environments.txt` (removed afterwards), so such runs need a
scratch `HOME` too, as `.github/AGENTS.md` now says. Nothing was sent to
win-builder, R-hub or CRAN, and the runs made no commit: those steps
stay with the maintainer (section 9).

### 1. CRAN audit (2026-11-12, tree `f582ba1`)

Nine auditors ran in parallel: local `R CMD check --as-cran` on Linux, a
CRAN-conditions run (fake `HOME`, no network, two cores, traced with
strace), Docker checks (R-devel, R 4.6.2, R 4.5.1, R 4.3.3), macOS on
omicron, Windows on kappa, a read of `R/` against the CRAN Repository
Policy (revision 6985), a review of the help pages, examples, vignette
and README, a review of the release metadata, and the live CRAN pages.

Outcome: 2 blockers, 26 should-fix, 21 nice-to-have and 56 info
findings. No package code broke a CRAN policy.

- 0.1.4 was OK on all 13 CRAN flavors, with no additional issues, no
  deadline, nothing in the incoming queue and no reverse dependencies on
  CRAN or Bioconductor.
- Blocker 1: CRAN's incoming spell check (aspell) flagged "backends" in
  the `Description`, while `cran-comments.md` said "0 notes".
- Blocker 2 (by the audit's own footprint rule; `R CMD check` gave no
  NOTE): in CRAN mode, the test teardown started a detached `Rscript`
  whose temporary directory landed in `/tmp`, outside the check's
  `TMPDIR`.
- Main should-fix items:
  - `NEWS.md` opened with a "development version" section above 0.2.0,
    which `utils::news()` drops.
  - `man/condathis-package.Rd` was stale after `f582ba1`.
  - Tests in CRAN mode took 150 to 268 s (240 to 246 s on Windows),
    against 24 to 88 s for the whole 0.1.4 check on CRAN.
  - Four tests ran a real micromamba when the check machine had one.
  - With `NOT_CRAN=true` and no network, 10 tests errored instead of
    skipping.
  - `testthat (>= 3.0.0)` was lower than what the tests need.
  - The automatic first download of micromamba (an executable of about
    19 MB) printed nothing at the default `verbose`.
  - The checksum check failed open without a warning on that automatic
    path.
  - `?condathis-options` had commented-out code in its examples.
  - The `pre-release` and `check` recipes of the `justfile` rewrote
    sources (hidden `just lint`) and uploaded to win-builder.
- Confirmed clean: writes only under `tools::R_user_dir()` or
  `tempdir()`, and only when the user calls a function; `.onLoad()`
  touches no file; no export removed since 0.1.4, and every signature
  change is in NEWS; CRAN-mode tests, examples and the vignette make no
  network connection; all URLs resolve; the tarball holds only package
  files; `Depends: R (>= 4.3)` holds on R 4.3.3.

The two download findings were first left "for you to decide later",
since both behaved as well as or better than 0.1.4. The maintainer's
"Fix everything" decided them (section 2).

### 2. Code fixes from the audit

a. **Download message.** `install_micromamba_for_command()`
   (`R/native_cmd.R`) says "No usable micromamba binary was found." and
   "Downloading micromamba "2.10.0-0" to '<path>'." with a message of
   class `condathis_micromamba_downloading`, at every `verbose` level
   except `"silent"`. The class is documented in `?condathis-conditions`
   and `?condathis-params`.
b. **Call-level verbose state.** The message follows the `verbose` of
   the exported call, not of the micromamba command that triggered the
   download. Reason: on macOS arm64 and Windows, the first micromamba
   command of `create_env()` is an internal probe that always runs
   silently (the dry-run solves of `define_platform()`, the platform query
   of `micromamba_native_platform()`). A message tied to that command
   never showed there. `parse_verbose_arg()` records the level for the
   length of the call with `local_call_verbose()`, restored when the
   exported function exits, and `call_verbose()` reads it
   (`R/parse_strategy_verbose.R`).
c. **Checksum warning.** When the `.sha256` file cannot be fetched or no
   SHA256 tool exists, `install_micromamba()` warns with class
   `condathis_install_micromamba_checksum_unavailable` at every level
   except `"silent"`, and still installs: mirrors without a checksum file
   and hosts that block GitHub must keep working. A checksum that does
   not match still refuses the binary.
d. **certutil fallback on Windows.** `compute_sha256()` tries
   `tools::sha256sum()` (R >= 4.5), then `digest` (Suggests), then
   `sha256sum`, `shasum` and, on Windows only, `certutil`. Each command
   must pass a known-answer test (`sha256_command_is_trustworthy()`).
   `certutil` is taken from `%SystemRoot%\System32` first
   (`sha256_command_path()`), and `parse_certutil_sha256()` reads its
   output. Reason: on R 4.3 and 4.4 on Windows without `digest`, no tool
   was found and the check was skipped. Confirmed on kappa.
e. **`micromamba_default_version`** (`R/install_micromamba.R`,
   `"2.10.0-0"`): the version the message names. It is a separate
   constant because the default of `install_micromamba(micromamba_version
   = )` stays a literal, so the usage in `?install_micromamba` shows it.
   A test checks that the two agree.
f. **Windows `PATH` de-duplication.** `run_bin()` put each directory of
   the environment twice on the command's `PATH` on Windows: micromamba's
   activation spells it with `\`, `env_bin_search_dirs()` with `/`.
   `prepend_path_dirs()` and `path_entry_key()` (`R/child_env.R`) compare
   entries as Windows does: without case, `/` equal to `\`, and (round 3)
   without a trailing separator, except at a drive root (`C:\` is not
   `C:`). Used by `build_child_env()` and `run_internal_backend.R`. No
   NEWS bullet: 0.1.4 ran `run_bin()` without activation, so the bug never
   shipped. For the same reason the old "development version" NEWS bullet
   about Windows `PATH` was dropped instead of moved.
g. **libmamba `~/.mamba/pkgs` workaround removed** from
   `R/backend-micromamba.R`, with its test file
   `tests/testthat/test-ensure_libmamba_pkgs_dir_workaround.R`. It
   created `~/.mamba/pkgs` in the user's home for libmamba 2.0.0 to 2.0.2
   (issue #13). The minimum micromamba is now 2.8.1
   (`micromamba_minimum_version`, `R/check_micromamba_version.R`), so it
   was dead code, and the policy audit flagged the home write.
h. **`stats::setNames()` -> `rlang::set_names()`**
   (`R/backend-defaults.R`): `stats` is not in Imports. `R CMD check`
   does not flag it, the policy audit did.

### 3. Tests in CRAN mode

- `skip_on_cran()` on slow multi-session and child-process tests, and on
  the four tests that ran a real micromamba. Ten network tests now skip
  offline instead of erroring. Eight fast pure-logic tests that the fixer
  had skipped beyond the brief were put back (they cost about 4 s). No
  test was weakened, and every exported function is still tested on
  CRAN.
- The detached sandbox deleter of `tests/testthat/setup.R` starts only
  off CRAN (`on_cran`), and on CRAN the sandboxes live in `tempdir()`
  (blocker 2).
- The Windows-only `PATHEXT` test was the single developer-run skip on
  Linux and macOS. It now runs on every OS, with `PATHEXT` set by the
  test. A duplicated test name in `test-run.R` was renamed.
- `Suggests: testthat (>= 3.2.1)`. The review of round 1 found that 3.2.0
  is one patch too low: `test-run.R:1199` mocks `processx::process` (a
  list, not a function) with `local_mocked_bindings()`, which 3.2.0
  rejects and 3.2.1 allows (testthat NEWS, #1896). Checked by running
  `test-run.R` under both versions. `skip_if_offline()` also needs
  testthat >= 3.1.2.
- Developer-run fixes (CRAN unaffected):
  - `lock_session_ignores_interrupt()` (`tests/testthat/helper-env-lock.R`)
    works off Linux, so the interrupt test of `test-env_lock.R` skips
    cleanly on macOS when R was started with `&`. In round 3,
    `sigint_ignored_in_proc()` reads `SigIgn` from `/proc/self/status`
    and answers `TRUE`, `FALSE` or `NA`; the callr probe runs only for
    `NA`.
  - No empty `/tmp/Rtmp*` from `test-backend.R` and no `uv-*.lock` in
    `%TEMP%` from the uv test.
  - The `native_cmd` test no longer starts an abort probe on macOS (it
    left a crash report).
  - The pip test of `test-list_packages_pypi.R` skips when
    `l10n_info()[["UTF-8"]]` is not `TRUE` (`../post-0.2.0/` item 14).

CRAN-mode timings (`NOT_CRAN=false`, run alone, no micromamba on
`PATH`):

| Tree | Linux | macOS (omicron) | Windows (kappa) |
|---|---|---|---|
| Audit, `f582ba1` | 150 to 268 s | not measured | 240 to 246 s |
| Round 3, `packages =` fixes | 64.5 s (R-devel: 59.2 s) | 31.1 s | 117 s in the check |
| With `env_definition()` | about 70 s (estimate, loaded host) | 34 to 35 s | 120.4 s (round 4); 128 s in the round 5 check |

The whole 0.1.4 check took 76 to 88 s on CRAN's Windows flavors. If
win-builder shows Windows too slow, the next candidates for
`skip_on_cran()` are `test-backend-packages.R`, `test-clean_cache.R` and
`test-with_sandbox_dir.R`.

### 4. Metadata, tooling and docs

- **`DESCRIPTION`.** The `Description` no longer contains "backend" or
  "back ends" (aspell flags both forms of the word). It now ends "Other
  packages can provide other tools to create and run environments." The
  help pages and articles keep "backend". `DESCRIPTION` never names
  rattlerthis (decided 2026-11-08, `../post-0.2.0/` item 15).
  `Config/Needs/dev` gained `urlchecker`.
- **`NEWS.md`** starts at `## condathis 0.2.0`. Superseded unreleased
  lines were replaced, not stacked. The 0.2.0 section has no
  "Release Date:" or "Development Changelog:" line yet: the
  `v0.1.4...v0.2.0` compare link returns 404 until the tag exists, and
  `urlchecker::url_check()` would flag it (section 9).
- **`inst/extdata/README.md`** (new, shipped): where each example file
  comes from, where it is used and under which terms. `example.bam`
  comes from the ENCODE UW Repli-seq K562 data (its `@PG` lines name the
  source file). The FASTQ files are simulated reads. `stat-env.yml` and
  `polyglot-channel/` are the maintainer's own work under the package's
  MIT license. Open: the upstream `polyglot` repository has an empty
  `LICENSE` file (`../post-0.2.0/` item 19).
- **`justfile`.**
  - `test`, `build-readme` and `check` no longer run `just lint`
    behind the caller's back.
  - The non-ASCII check covers `README.md` and `README.qmd`.
  - `build-readme` renders with `HOME` and the `XDG_*` directories in a
    temporary directory and installs the package in a temporary library.
  - `git-tag` tags the commit in the `SHA:` field of `CRAN-SUBMISSION`
    and checks its version against `DESCRIPTION`.
  - `release-github` restores the NEWS headings with a `trap`, also when
    it fails.
  - `pre-release` runs only local checks.
  - New `check-win-devel` and `check-win-release` upload to win-builder
    on purpose.
- **CI.** `r-cmd-check.yaml` has an `ubuntu-latest` job on R `'4.3'`,
  the oldest R that `Depends` allows.
- **Docs sweep (round 2).** Five reviewers (README, vignette and
  articles, help pages, NEWS and meta files, cross-cutting terms and
  versions), each followed by a skeptic who tried to refute every
  finding: 77 findings, 9 refuted, 2 already covered by section 2.
  - `README.qmd`: new "Output and Errors" section, Windows notes in
    "Known Caveats", a pointer to "Removing everything" in
    `?clean_cache`, rattlerthis from R-universe, "Learn More" links and
    an upgrade note. `README.md` re-rendered in a sandbox, in ASCII
    (`cli.unicode = FALSE`).
  - Vignette: the samtools example uses bioconda, which has no Windows
    builds; it says so and points to WSL.
  - Backends article: install rattlerthis from R-universe (binaries, no
    Rust toolchain).
  - Roxygen in 14 files. `?condathis-conditions` re-laid out: the PDF
    manual had 370 overfull boxes from long class names, now none wider
    than 72 pt.
  - Runnable examples for `env_exists()`, `list_envs()` and
    `validate_env()`; a "Removing everything" section in `?clean_cache`;
    the commented-out example code of `?condathis-options` moved to
    prose; `[c()]` links to `c.condathis_run_step`.
  - `.github/AGENTS.md` (testthat version, `packages =` usage, `run()`
    arguments) and `.github/CONTRIBUTING.md` (UTF-8 locale, the DNS check
    of `skip_if_offline()`, R in the foreground).
- **`cran-comments.md`** was rewritten from the verified results: the
  breaking changes, the test environments, the `\dontrun{}` rationale
  (examples download and run micromamba; `--as-cran` runs `\donttest{}`),
  the micromamba download and checksum behavior, and why rattlerthis is
  mentioned although no field of `DESCRIPTION` names it.

### 5. `packages =` next to `...` (the maintainer's priority)

0.2.0 takes package specs in `...` and every other argument by name
(decision D6 in the comments of `collect_package_specs()`,
`R/validate_args.R`). In 0.1.4, `packages` was the first formal. The
maintainer asked that `packages = c()` keep working next to `...`.

**How it was reviewed (2026-11-13).** Three probes and a synthesis:

- A call-shape matrix of 72 rows, run against 0.1.4 (installed from the
  `v0.1.4` tag) and against the current tree, on the offline polyglot
  channel: `packages =` as a string, a vector, `NULL`, `character(0)`, a
  named vector, through wrappers, `do.call()`, `rlang::exec()` and `!!!`,
  with every other 0.1.4 argument and value, and under
  `options(warn = 2)`.
- A code review of the alias, the positional-`env_name` guard and the
  0.1.4 prefixes that R matched to `packages` (`pack =`, `p =`).
- A survey of real callers: GitHub code search plus the maintainer's
  local projects. 75 call sites in 14 repositories outside condathis,
  all `create_env()` except one `install_packages()` line. About half
  pass `packages =`, among them isoformic, BLASTr and slidetool. The
  other repositories are not named here; several are private. condathis
  has no reverse dependencies on CRAN or Bioconductor, and on r-universe
  only rattlerthis needs it (it already uses the 0.2.0 style).

**Verdict.** `packages =` works next to `...` in `create_env()`,
`install_packages()` and `validate_env()`, for every shape above, with
the same result as 0.1.4 plus one deprecation warning.

**Decisions and fixes (round 3, 2026-11-13).**

a. **Positional `env_name` guard.** Bug found by all three probes:
   `create_env(packages = c("python", "samtools"))` aborted when an
   environment named `samtools` existed, although nothing was
   positional. Rule now: the guard runs only when `env_name` is missing
   and there are two or more unnamed `...` arguments, the last one a
   single string (`positional_env_name_possible()`,
   `R/backend-query.R`). It never runs for `packages =`, a named list in
   `do.call()`, `rlang::exec()`, `!!!` or one vector. It still catches
   `create_env("x", "<existing env>")`, with class
   `condathis_<fn>_positional_env_name` and the hint
   `env_name = "<name>"` (`abort_on_positional_env_name()`).
b. **Soft deprecation.** Proposed by the review, and applied because the
   maintainer did not ask to keep the plain warning. Base R, no new
   Imports (`R/conditions.R`):
   - `is_direct_use(user_env)` follows `lifecycle::deprecate_soft()`.
     Direct: a call whose `topenv()` is the global environment (console,
     script, vignette), or the namespace named by `TESTTHAT_PKG` (the
     tests of the calling package, so its maintainer sees it).
     Indirect: a call made in any other namespace, including base
     functionals such as `Map()`.
   - `options(lifecycle_verbosity = "warning")` or `"error"` makes every
     call direct, `"quiet"` none. The condition stays a warning.
   - `condathis_deprecate_soft()` warns once per session and id
     (`condathis_warn_once()`). An indirect call neither warns nor uses
     up the id. The id is recorded before the warning is signaled, so
     under `options(warn = 2)` only the first direct call errors.
   - Each exported function captures `user_env <- rlang::caller_env()`
     itself, never in a helper.
   - Reasons: the alias costs nothing to keep; about half of the real
     calls are inside packages whose users cannot change the code; under
     `options(warn = 2)` an always-on warning would make the first such
     call fail. Planned path: soft in 0.2.0, then warn every caller once
     after the known users moved, no removal before 1.0.
   - Classes unchanged: `condathis_deprecated_packages_arg`, ids
     `deprecated_packages_arg_<fn>`.
c. **`install_packages(packages = NULL)`** and `packages =
   character(0)` return status 0 and run nothing, as in 0.1.4
   (`R/install_packages.R`). A missing non-default environment still
   aborts with `env_not_found`; a missing `"condathis-env"` is created
   empty first, as documented. No specs at all still abort with
   `condathis_install_packages_missing_packages`.
d. **`method = c("native", "auto")`**, the 0.1.4 default vector of
   `create_env()` and `run()`, and `c("auto", "native")` give their first
   element, as `rlang::arg_match()` did (`validate_method_arg()`,
   `R/backend.R`). Any other vector aborts. This keeps wrappers that
   copied the 0.1.4 signature working.
e. **`method = "native"`** goes through `resolve_method_alias()` with
   the same soft rule and warn-once id (`deprecated_method_native`,
   class `condathis_deprecated_method_native`). The old
   `condathis_native_warned` flag is gone. Soft only in `create_env()`,
   `install_packages()`, `validate_env()`, `remove_env()`, `run()` and
   `run_bin()`; see section 6.
f. **Hints for 0.1.4 shapes** (classes unchanged):
   - `install_packages(packages = "x", "my-env")` suggests
     `env_name = "my-env"`. In `create_env()`, a file name such as
     `"env.yml"` gets a hint to use `env_definition()` instead.
   - A `NULL` among unnamed values that is not last says the arguments
     after the specs must be named (0.1.4's positional
     `create_env("pkg", NULL, "env")`), and, where the function takes a
     file, how to pass it with `env_definition()`.
   - Abbreviations that 0.1.4 matched to `packages` (`package =`,
     `pack =`, `p =`) abort and say so. They are not accepted silently.
     `p =` in `create_env()` also matches `platform`, so its hint names
     both.

   Answer recorded for the maintainer's question "Does rlang provides
   any way of defending against partial matching of function
   arguments?": no switch exists. Base R matches names before rlang
   runs, and formals after `...` already need exact names, which 0.2.0
   uses. rlang can only check `...` (`check_dots_empty()`,
   `check_dots_unnamed()`, `check_dots_used()`);
   `collect_package_specs()` does that job and names the closest
   formal. Base options `warnPartialMatchArgs`, `warnPartialMatchDollar`
   and `warnPartialMatchAttr` only warn.

**Breakages that real callers hit, unrelated to `packages =`**, fixed
in the same round:

g. **bioconda hint.** About 20 calls in 9 repositories relied on
   bioconda being a default channel in 0.1.4. When `channels` was not
   given, `"bioconda"` is not among the channels, and the backend error
   names a requested spec without a channel ("does not exist" from
   micromamba 2, "No candidates were found" from rattler), the error
   gets a bullet that bioconda is no longer a default channel and names
   `"bioconda::<spec>"` (`with_default_channels_hint()`,
   `default_channels_hint()`, `R/create_env.R`). It can also appear when
   a conda-forge package lacks the requested version; the text is
   conditional, so it stays.
h. **Virtual package specs.** Specs whose name starts with `__`
   (`__cuda`, `__unix`, `__glibc`) are left out of the satisfaction
   check (`is_virtual_package_spec()` in `check_env_request()`), so a
   re-run of `create_env(overwrite = FALSE)` no longer always aborts.
   They still go to the backend.
i. **"installed from another channel".** An environment built from
   bioconda by 0.1.4 does not satisfy `"samtools"` with the default
   `channels`, because the channel is part of the request (unchanged
   decision). The error now names the channel of the installed package
   and how to add it, and drops the `overwrite = TRUE` hint when the
   channel explains every unsatisfied spec
   (`specs_from_other_channels()`, `unsatisfied_only_by_channel()`).
j. **pypi exclusion.** Found by the round 3 review: pip packages are
   listed with channel `pypi`, so the hint above told users to add
   "pypi" to `channels`. `specs_from_other_channels()` now skips `pypi`
   rows, with a test.

**Small fixes of the same round:**

k. **Windows absolute command path.** `run_bin("C:\\...\\cmd.exe", ...)`
   failed: `resolve_env_bin_path()` returned `fs::path()` with `/`, and
   `cmd.exe` reads its own path from the command line.
   `native_command_path()` (`R/resolve_env_bin_path.R`) now returns `\`
   on Windows for absolute paths. 0.1.4 used
   `normalizePath(Sys.which())`, so the bug never shipped and NEWS has no
   line. The relative branch still returns `/` (`../post-0.2.0/` item
   20).
l. **`path_entry_key()` trailing separator**: see section 2f.
m. **SIGINT probe** and **UTF-8 pip test guard**: see section 3.
n. Wording of `?condathis` (it keeps the micromamba it downloads, and
   uses one found elsewhere where it is) and an own `@param verbose` for
   `?install_micromamba`.

The final adversarial review re-ran the 72-row matrix. One 0.1.4 shape
still fails: `install_packages("pkg", "env", <channels>)`, channels as
the third positional argument. NEWS ("Old positional calls no longer
work") describes the outcome.

### 6. Compatibility items left out on purpose

Each would have needed another full check on all three machines, and
none affects a 0.1.4 call that the matrix found working. Plans are in
`../post-0.2.0/PLAN.md` item 17.

- `install_packages("pkg", "env", <channels>)`: the guard sees a
  channel as the last spec, so the call creates `"condathis-env"` and
  fails in the solver.
- The `packages =` plus one unnamed string hint suggests
  `env_name = "<value>"` also when `env_name` is in the call.
- `create_env(NULL, "env.yml", ...)` gets the generic "must be named"
  hint. Since `env_definition()` it also says to use
  `env_definition()`, but with an example file name, not the user's.
- `method = "native"` is not soft in `env_exists()`, `list_envs()`,
  `get_install_dir()` (no `user_env` to `resolve_method_alias()`),
  `list_packages()`, `get_env_dir()` (no `user_env` to
  `resolve_backend()`) and `run_pipeline()` (per-step alias). 0.1.4 had
  `method` only in `create_env()` and `run()`, so no 0.1.4 call is
  affected. NEWS and `?condathis-conditions` name the six soft functions.
- testthat's 3rd edition sets `lifecycle_verbosity = "warning"` inside
  `test_that()` (`local_reproducible_output()`), so the tests of other
  packages see the warning even for calls made in their own `R/` code.
  `lifecycle::deprecate_soft()` does the same. The docs do not say so.
- `install_packages(packages = NULL)` returns status 0 also when the
  environment probe failed (`NA`), against rule R5. Found by reading the
  code; it needs a backend whose probe fails.

### 7. `env_definition()` and the `env_file =` deprecation

Implemented on 2026-11-13 at the maintainer's request (quote 4 above),
after `8cffc25`. Everything about it is in `../feat-env-file/PLAN.md`.
For the release it means:

- New export `env_definition()`, and `env_file =` soft-deprecated with
  the same `condathis_deprecate_soft()` rule as `packages =` (class
  `condathis_deprecated_env_file_arg`).
- It reuses section 5's helpers, and the 0.1.4 positional hints now
  point to `env_definition()`.
- Five new untracked files must be committed (Context above).
- It was verified with the same matrix (section 8, rounds 4 and 5).
- rattlerthis was not built or run against it (section 9).

### 8. Verification matrix

Five verification rounds ran: 1 after the test and metadata fixes, 2
after the code fixes of section 2 and the docs sweep, 3 after the
`packages =` fixes of section 5, 4 after `env_definition()`, and 5 after
the two test fixes of round 4. Each round checked the whole working
tree, identified by the `HEAD` sha plus the sha256 of `git diff HEAD`,
recomputed at the end to show the tree did not change during the run.
The table has the results of rounds 3 to 5.

| Where | R | `R CMD check --as-cran` | Developer suite (`NOT_CRAN=true`) |
|---|---|---|---|
| Linux, Ubuntu 24.04 x86_64 | 4.5.3 | OK (round 3), OK* (round 4); PDF manual, remote incoming, also `_R_CHECK_DEPENDS_ONLY_=true` | round 3: 8045 pass; round 5: 8680 pass |
| Docker, Ubuntu 26.04 | R-devel 2026-11-12 r90880 | OK; PDF manual, depends-only, incoming extras with aspell | round 3: 8045 pass; round 4: 8680 pass |
| Docker | 4.6.2 | OK; PDF and HTML manual | not run |
| Docker, Ubuntu 22.04 | 4.3.3 (tarball built in 4.3.3) | OK*; `--no-manual` | audit only: 7668 pass, 1 skip (the Windows-only test, since fixed) |
| Docker, `--network none` | 4.6.2 | OK*; `--no-manual`, `_R_CHECK_CRAN_INCOMING_=false` | round 3: 6615 pass, 200 skips; round 4: 7196 pass, 206 skips; all skips "offline" |
| omicron, macOS 26.4.1 arm64 | 4.6.1 (CRAN build) | OK (rounds 3 and 5); offline OK* (round 3); `--no-manual` | round 3: 8043 pass; round 5: 8678 pass |
| kappa, Windows 11 x64 | 4.6.1 ucrt | OK (rounds 3 to 5); `--no-manual` | round 3: 8004 pass; round 4: 8638 pass, 1 skip; round 5: 8639 pass |

Every developer run listed had 0 failures, 0 warnings and 0 skips,
except where a skip count is given. Round 4 found two problems, both
in `tests/testthat/test-env_definition.R` only:

- On macOS a test compared against the unresolved `tempdir()` path
  (`/var/...`), while `getwd()` returns `/private/var/...`. It now
  compares against `getwd()`.
- On Windows a symlink test was skipped with `skip_on_os("windows")`.
  It passed with the skip removed, so the skip is gone.

Round 5 re-ran them (2026-11-13): 0 failures and 0 skips on Linux (8680
pass), macOS (8678 pass) and Windows (8639 pass), and `R CMD check
--as-cran --no-manual` Status OK on macOS and Windows.

Inside every round 4 check, the CRAN-mode tests gave
`[ FAIL 0 | WARN 0 | SKIP 333 | PASS 5973 ]`, all skips "On CRAN".
Examples, including `\dontrun{}`, all ran
(`devtools::run_examples(run_dontrun = TRUE)`), with no micromamba on
`PATH` and `HOME`, `XDG_*` and `TMPDIR` in scratch. `urlchecker` found no
problem and `spelling` no misspelled word. No run wrote to `~/.mamba`,
`~/.conda`, `~/.cache/conda` or the condathis data directory (compared
before and after).

\* The NOTE "unable to verify current time" (R 4.3.3, the offline runs,
and Linux in round 4). How it was shown to come from the host: R asks
worldtimeapi.org and worldclockapi.com for the time, and curl from the
host got "Connection reset by peer" and a timeout from those URLs; the
same check with `_R_CHECK_SYSTEM_CLOCK_=0`, and nothing else changed,
gives `Status: OK`.

Other host causes, removed for the record runs and not package
problems:

- kappa: rig's patched `Rprofile` creates a `'NULL'` directory (a NOTE),
  and pandoc is not on `PATH` (a NOTE on top-level files). The checks
  ran with Quarto's pandoc on `PATH` and an R copy without rig's
  `R_LIBS_USER` block.
- omicron: the LuLu firewall holds connections from every freshly
  downloaded micromamba, so the developer suite stalls. It runs with
  `CONDATHIS_MICROMAMBA_PATH` set to an installed micromamba.
- No LaTeX on omicron and kappa, so their checks use `--no-manual`. The
  PDF manual is checked on Linux and in Docker.
- To show aspell really runs in the R-devel check, a copy of
  `DESCRIPTION` with a planted typo was reported ("pipelnies"), while
  the real file reports nothing.

### 9. Release steps left to the maintainer

None of these were done here. `HANDOFF.md` has the same list as a
prompt.

1. Review and commit the `env_definition()` work, including the five
   untracked files and the untracked `.github/devdocs/feat-env-file/`
   folder, and push. Wait for GitHub Actions (R-devel, release,
   oldrel-1 and 4.3 on Linux, plus macOS and Windows).
2. (Done 2026-11-13: round 5 passed on Windows with 0 failures and
   0 skips.) Re-run the round 5 checks only if the package files change
   again before submitting.
3. Recommended, not blocking CRAN: build rattlerthis against this tree
   on a machine with a Rust toolchain and run its tests. Expected
   failures: `test-parity-envfile.R:98` and `test-parity-linkscripts.R`
   (about line 320) assert no warnings for `env_file =` calls, and now
   see the deprecation warning when run first or alone. The fix belongs
   in rattlerthis (`../post-0.2.0/` item 18,
   `../feat-env-file/PLAN.md` item 17).
4. Add a license to the upstream `polyglot` repository, since
   `inst/extdata/README.md` says it is MIT (`../post-0.2.0/` item 19).
5. `just check-win-devel` and `just check-win-release`
   (`devtools::check_win_devel()`, `check_win_release()`). Add their R
   versions and results to "Test environments" in `cran-comments.md`,
   and check that the other lines still match section 8.
   `just pre-release` runs only local checks now, so it is safe to run.
6. `devtools::submit_cran()` and confirm the email. CRAN's submission
   break runs from 2026-12-22 to 2027-01-07.
7. After acceptance: `just git-tag` (tags the SHA in `CRAN-SUBMISSION`),
   push the tags, then `just release-github` (it removes
   `CRAN-SUBMISSION`). Optionally add "Release Date:" and
   "Development Changelog: [0.2.0](.../compare/v0.1.4...v0.2.0)" to the
   0.2.0 NEWS section, now that the tag exists.
8. `usethis::use_dev_version()`, push, and let pkgdown and r-universe
   rebuild. Update the Zenodo archive and badge (`pre-release` recipe
   note). Close issue #12 (`../post-0.2.0/` item 13).
