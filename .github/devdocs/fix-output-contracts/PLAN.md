# PLAN: Exported-function output-type/class contract consistency

## Overview

A full function-by-function review of `condathis`'s test coverage (requested
separately, see the coverage-gap work landed on `feat-pipeline` around the
same time) surfaced that the 17 exported functions return values from at
least five structurally different "families" — with no rule for which
family a given function belongs to, and two functions whose own return
*type* varies depending on whether the underlying command succeeded or
failed. This directory tracks fixing that, as a distinct concern from the
pipeline feature work and from the test-coverage-gap work, both tracked
under `feat-pipeline`'s own devdocs.

Goal, in the user's own words: make the public API "the most reliable and
predictable as possible."

## The five return-shape families found

1. **Rich, classed result** — `run()`, `run_bin()`: `condathis_result`
   (`status`/`stdout`/`stderr`/`timeout`/`pid`/`cmd`/`env_name` +
   `format()`/`print()`/`as.list()`).
2. **Rich, classed pipeline** — `run_pipeline()`: `condathis_pipeline`
   (`statuses`/`processes`/`timeout`), where each `processes[[i]]` is a
   **plain, unclassed** list with `cmd`/`env_name`/`status`/`stdout`/
   `stderr`/`pid` (no `timeout`, no methods) — almost but not quite a
   `condathis_result`.
3. **Plain, unclassed result** — `create_env()`, `install_packages()`,
   `remove_env()`, `clean_cache()`: bare
   `list(status, stdout, stderr, timeout)`, no `pid`/`cmd`/`env_name`, no
   print method.
4. **Path string** — `get_env_dir()`, `get_install_dir()`,
   `micromamba_bin_path()`, `install_micromamba()`: `fs_path`/`character`.
5. **Everything else** — `env_exists()` (logical), `get_sys_arch()`
   (character), `list_envs()` (character *or* integer — see below),
   `list_packages()` (tibble), `parse_output()` (character vector),
   `with_sandbox_dir()` (`NULL`).

Families 4 and 5's members are each internally consistent (all
`fs_path`-returning functions agree with each other; `parse_output()` and
`with_sandbox_dir()` have single, well-validated shapes). The problem is
families 2 and 3: four functions doing conceptually the same thing
("run a micromamba command, report what happened") return three
incompatible shapes among themselves and against `run()`/`run_bin()`.

## The two sharpest findings (both verified by direct reproduction, not just read from source)

### `list_envs()` genuinely returns two different types depending on success/failure

Documented in its own `@returns`: *"If the command fails, returns the
process exit status as a numeric value."* Confirmed live:

```r
testthat::local_mocked_bindings(
  native_cmd = function(...) list(status = 1L, stdout = "", stderr = "boom", timeout = FALSE)
)
list_envs(verbose = "silent")
#> [1] 1        <- an integer, not a character vector
```

Today, `rethrow_error_cmd()`'s default `error = "cancel"` behavior means
`native_cmd()` normally *throws* rather than returns a nonzero status, so
this branch is rarely hit in practice — but it's real, reachable code, not
dead code, and its type-punning silently **cascades**: `env_exists()` does
`env_name %in% list_envs()`, so if `list_envs()` ever returns `1L` instead
of a character vector, `env_exists()` doesn't error, it just quietly
returns `FALSE` — which then makes `create_env()`'s "already exists"
check, `install_packages()`'s auto-create check, and
`remove_env()`/`list_packages()`'s existence checks all silently
misbehave instead of surfacing the real underlying failure. Confirmed this
cascade directly with the same mock.

### `list_packages()`'s equivalent failure path is worse in a different way

No `else` branch at all — if its `native_cmd()` call ever returned (rather
than threw) with a nonzero status, it throws a raw, uninformative base-R
error instead of a `condathis_*` class:

```r
testthat::local_mocked_bindings(env_exists = function(...) TRUE, native_cmd = function(...) list(status = 1L, ...))
list_packages(env_name = "condathis-env")
#> Error: object 'pkgs_df' not found
```

So the two "list" functions — same author, same purpose, same shape of
underlying command — fail in two completely different, both-bad ways.

## Secondary findings — all since resolved (see "Fix 5" section below)

- `install_micromamba()` returns a bare path, not a result list — breaks
  the "action function returns a process-result" pattern the other four do
  (now) share. Defensible (it wraps a download+extract, not a single
  `native_cmd()` call), but still a real asymmetry. **Resolved by decision,
  not code change** — see Fix 5.
- `get_install_dir()` side-effects (creates the directory, guarantees
  existence) while `get_env_dir()`/`micromamba_bin_path()` are pure/lazy.
  Not a type issue, a behavioral-predictability asymmetry within what
  looks like one consistent "path getter" family. **Resolved by decision,
  not code change** — see Fix 5.
- `env_exists()` silently coerces `NULL`/`NA` input to `FALSE` rather than
  validating, while the same argument *omitted* raises an error. Fixing
  `list_envs()` (Fix 3) already removed the most dangerous consequence of
  this (the silent cascade), but the coercion itself was still worth
  fixing on its own merits. **Resolved with a real code change** — see
  Fix 5.

## Fix 1 — DONE: unify `create_env()`/`install_packages()`/`remove_env()`/`clean_cache()` around `condathis_result`

**Status: done, committed** (`test: extend coverage for public api
contracts`, `feat: move all public facing internal wrappers output to
condathis_result instead of bare lists`).

All four now return the same `condathis_result` S3 object `run()`/
`run_bin()` already return, with `pid`/`cmd`/`env_name` threaded through:

- `cmd` is a plain, readable summary of the underlying `micromamba`
  invocation, built independently by each function from its own known
  arguments (mirroring how `run()`/`run_bin()` already build their own
  `cmd_string` rather than asking `native_cmd()` to report it) — e.g.
  `"micromamba create -n <env_name> <packages>"` for `create_env()`,
  `"micromamba env remove -n <env_name>"` for `remove_env()`.
- `pid` follows the exact same fallback `run()`/`run_bin()` already use
  (`NA_integer_` when the underlying `processx::run()` result has no
  `$pid`, which is the normal case outside the `stdin = "|"` code path —
  confirmed `processx::run()` genuinely never returns `$pid`, so `run()`/
  `run_bin()`'s own `pid` field is `NA_integer_` in the same common case
  today; this fix does not regress anything, it matches existing
  behavior).
- `clean_cache()` has no associated environment, so its `env_name` is
  honestly `NA_character_` — documented in `@returns`, matching
  `new_condathis_result()`'s own default for a result not tied to an
  environment.
- `create_env()`'s "dependencies already satisfied" short-circuit path
  (previously a hand-built `list(status = 0L, stdout = "", stderr = "",
  timeout = FALSE)`, bypassing `native_cmd()` entirely) now returns the
  same classed object via the same `cmd_string`, built once right after
  `packages_arg` is resolved so both the short-circuit return and the
  final return share it.

Verified: `test-clean_cache.R` (11/11), `test-remove_env.R` (13/13),
`test-create_env.R` (37/37, including a new dedicated test for the
short-circuit path), `test-run.R` (34/34), `test-run_bin.R` (26/26) all
clean. `test-install_packages.R` clean except one **pre-existing,
unrelated** intermittent failure — see "Fix 5" below (now fixed).

## Fix 2 — DONE: `run_pipeline()`'s per-process entries become real `condathis_result` objects

**Status: done, committed** (`feat: individual pipeline output slots are
classed as condathis_result`).

`res$processes[[i]]` currently has the same field names as
`condathis_result` (`cmd`/`env_name`/`status`/`stdout`/`stderr`/`pid`)
minus `timeout`, but as a plain list — so `format()`/`print()` don't work
on an individual pipeline stage even though conceptually "one pipeline
stage" is "one `run()`-shaped call."

Plan: change `R/run_pipeline.R`'s per-process construction
(`processes[[i]] <- list(...)`) to `new_condathis_result(...)` instead,
adding a `timeout` field (the pipeline's own overall `timeout`, or `FALSE`
per-process if per-process timeout isn't tracked — needs a decision, see
Open questions). Update `format.condathis_pipeline()` (`R/pipeline_result.R`)
if it currently relies on `processes[[i]]` being a plain list rather than
a `condathis_result` (it shouldn't need changes — it already reads
`p$status`/`p$stdout`/`p$stderr`/`p$cmd`/`p$env_name` by `$name`, which
works identically on a classed list). Also update
`new_condathis_pipeline()`'s own `stopifnot(is.list(processes))` — a
`condathis_result` still `is.list()`, so no change needed there.

**Open question, resolved**: each pipeline stage does get a real, non-`NA`
`pid` — `run_pipeline()` spawns each stage via `processx::process$new()`
directly (not `processx::run()`), so `proc_i$get_pid()` was already being
captured before this fix and just gets threaded through unchanged. The
existing "Pipeline reports a positive integer pid per process" test kept
passing unchanged, confirming this. `timeout` per stage is `FALSE`
(honest — per-process timeouts aren't tracked, matching the pipeline's own
always-`FALSE` overall `timeout`).

Landed: `processes[[i]] <- list(...)` → `new_condathis_result(...)`;
`format.condathis_pipeline()` needed no changes, as predicted (reads
fields by `$name`); new test confirms `res$processes[[i]]` is
`condathis_result`-classed and that `format()`/`print()` work directly on
an individual stage. `test-run_pipeline.R`: 82 → 88 passing assertions,
0 failures, before and after `air format`.

## Fix 3 — DONE: `list_envs()` always raises on failure, never returns a numeric fallback

**Status: done, committed** (`refactor: standardize list_envs output`).

Drop the `else { return(px_res$status) }` branch entirely (see finding
above — it's real, reachable, dangerous code, not dead code, and
misleadingly documented). Since `native_cmd()`'s default `error = "cancel"`
already makes the underlying `processx::run()` throw before this branch
would ever run in current practice, removing it changes documented
behavior but not real-world behavior for any caller relying on today's
`@returns` promise being kept. Update:

- `R/list_envs.R`: remove the `else` branch and the `if
  (identical(px_res$status, 0L))` guard around it (always true by the time
  execution reaches there, given `rethrow_error_cmd()` already aborted
  otherwise) — return the parsed character vector directly.
- `@returns` doc: drop the "If the command fails, returns ... numeric"
  sentence.
- New test: mock `native_cmd()` to return a nonzero status without
  throwing (exactly the repro above) and assert `list_envs()` now raises
  `condathis_cmd_status_error` (matching `install_packages()`/
  `create_env()`/etc.'s already-established behavior for the same
  underlying failure class) instead of returning an integer.

Landed exactly as planned. Verified the trigger condition (`native_cmd()`
mocked to return, not throw, a non-zero status) live before writing the
test. `test-list_envs.R`: 8/8. Every file that depends on `list_envs()`/
`env_exists()` re-verified clean: `test-create_env.R` (37/37),
`test-clean_cache.R`, `test-create_nested_env.R`, `test-env_exists.R`,
`test-remove_env.R`.

## Fix 4 — DONE: `list_packages()` raises a proper `condathis_*` class instead of leaking an internal variable name

**Status: done, committed** (`fix: error when list_package can't run`).

Currently, if `native_cmd()` ever returned (rather than threw) with a
nonzero status, `pkgs_df` is never assigned, and the function crashes
later with `Error: object 'pkgs_df' not found` — a `simpleError`, no
useful class, exposes an internal variable name to the caller. Plan: make
the `if (identical(px_res$status, 0L))` check in `R/list_packages.R`
explicit and add an `else` that raises a real `condathis_*`-classed error
(new class, e.g. `condathis_list_packages_cmd_failed`, or simply let
`rethrow_error_cmd()`'s own `condathis_cmd_status_error` be the only path
by removing the now-redundant post-hoc status check entirely, matching
fix 3's reasoning: today this branch shouldn't be reachable given
`rethrow_error_cmd()` already aborts on failure — same "defensive dead
code with a bad failure mode" shape as `list_envs()`, same fix shape).
New test: same mocking approach as fix 3's, asserting a
`condathis_*`-classed error rather than a raw `simpleError`.

Landed via the "let `rethrow_error_cmd()`'s own `condathis_cmd_status_error`
be the only path" option — no new error class introduced, matching fix 3's
shape exactly. `test-list_packages.R`: 4/4. `test-create_nested_env.R` and
`test-create_env.R` (both call `list_packages()` for real) re-verified
clean.

### Post-fix cleanup: `roxygenize()`'s unexpected `DESCRIPTION` version bump

Running `roxygen2::roxygenize()` to regenerate `man/*.Rd` for fixes 2 and 3
came with `DESCRIPTION`'s dev version bumping from `0.1.4.9003` to
`0.1.4.9004` as a side effect. Investigated before trusting it: no
`Config/roxygen2`-adjacent version-bump hook found in `DESCRIPTION`, and a
second, isolated `roxygenize()` call did not bump it further — not a
repeatable, intentional behavior tied to this package's build config, and
not something requested as part of any of the four fixes. Reverted once,
but the user committed everything (including that version bump)
themselves, deliberately, before the revert could land — so it stands as
the user's own call, not an artifact of the fix work itself.

## Fix 5 — DONE: the three deferred secondary findings, plus the flaky channel-warning test

**Status: done, not yet committed.**

Requested together in one batch. Each got its own judgment call rather
than a mechanical "make everything consistent" pass — see reasoning below
and in the "Secondary findings" section above.

### `env_exists()`: real fix

Added explicit validation raising `condathis_env_exists_invalid_env_name`
when `env_name` is `NULL`, `NA`, non-character, or not length-1 — instead
of silently returning `FALSE`, indistinguishable from "that environment
genuinely doesn't exist." Confirmed via `grep` that every internal call
site already passes a real character value, so this only changes behavior
for genuinely invalid caller input. Updated `test-env_exists.R`'s existing
test, which had locked in the old silent-`FALSE` behavior as if it were
correct; added a new test covering `NULL`/`NA`/`NA_character_`/
length-2 vector/non-character inputs. Documented as breaking (minor) in
`NEWS.md`.

### `install_micromamba()` and the path-getter asymmetry: decided, documented, not code-changed

Both secondary findings were, on reflection, **not bugs** — re-examined
each rather than mechanically forcing consistency:

- Forcing `install_micromamba()` into `condathis_result` would require
  fabricating a meaningless `status`/`stdout`/`stderr`/`pid` (no real
  `micromamba` subprocess is ever spawned — it downloads and extracts a
  binary directly) while displacing the one genuinely useful piece of
  information it returns (the installed path) out of the top-level return
  value. That's a strictly worse design for no real gain. Documented the
  reasoning directly in `@returns` instead, positioning it with the
  path-getter family it actually belongs to.
- Making `get_env_dir()`/`micromamba_bin_path()` create-and-guarantee
  existence (matching `get_install_dir()`), or making `get_install_dir()`
  lazy (matching them), would each break a real, load-bearing use of the
  other behavior (`get_install_dir()` must exist for everything else to be
  built on; `get_env_dir()`/`micromamba_bin_path()` are used precisely
  *because* they don't check existence, e.g. `install_micromamba()`'s own
  `fs::file_exists(micromamba_bin_path())` check to decide whether to
  install). `get_env_dir()` already documented "returned even if the
  environment has not been created yet"; gave `micromamba_bin_path()` the
  same explicit treatment (it didn't have it before).

### The flaky `test-install_packages.R` cross-platform test: confirmed and fixed

Confirmed the working theory from the Fix 1 write-up: `zlib` (used in the
`create_env()` call) is trivially available on both `"conda-forge"` and
`"conda-forge/label/main"`, so which one a real solve records in
`conda-meta/history` is solver tie-breaking, not something the test
controls — this is why it failed specifically at the `expect_warning()`
step, roughly 1 run in 3.

Fixed by not relying on a real install to populate history at all: create
the env with `channels = "conda-forge"` only (deterministic, no ambiguity
for `zlib`), then `cat()`-append a synthetic
`conda-meta/history` line recording `"conda-forge/label/main"` as a second
previously-used channel directly. `get_env_history_channels()`'s parsing
of exactly this line format is already unit-tested in isolation
(`test-get_env_history_channels.R`), so this doesn't lose any real
coverage — it just removes the dependency on the live solver's channel
choice for a package that exists on both candidate channels.
`"conda-forge/label/main"` still gets used for real in the second,
`expect_no_warning()` half of the test (as an actual `channels=` argument
install_packages() must be able to resolve against, not just parse from
history), so that channel still needs to be real and reachable — it does
not need to actually be the origin of any installed package anymore.
Verified with 2 consecutive clean runs (previously ~2 of 3 failing).
