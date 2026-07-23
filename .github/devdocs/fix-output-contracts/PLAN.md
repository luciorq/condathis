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

## Secondary findings (lower priority, tracked but not yet scheduled)

- `install_micromamba()` returns a bare path, not a result list — breaks
  the "action function returns a process-result" pattern the other four do
  (now) share. Defensible (it wraps a download+extract, not a single
  `native_cmd()` call), but still a real asymmetry. **Not scheduled** —
  revisit only if it turns out to bite someone in practice.
- `get_install_dir()` side-effects (creates the directory, guarantees
  existence) while `get_env_dir()`/`micromamba_bin_path()` are pure/lazy.
  Not a type issue, a behavioral-predictability asymmetry within what
  looks like one consistent "path getter" family. **Not scheduled.**
- `env_exists()` silently coerces `NULL`/`NA` input to `FALSE` rather than
  validating, while the same argument *omitted* raises an error. Not
  scheduled on its own, but interacts with the `list_envs()` fix below
  (fixing `list_envs()` removes the most dangerous consequence of this).

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
unrelated** intermittent failure — see "Known unrelated flake" below.

## Fix 2 — planned: `run_pipeline()`'s per-process entries become real `condathis_result` objects

**Status: not started.**

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

**Open question**: does each pipeline stage get its own real `pid`? Since
`run_pipeline()` spawns each stage via `processx::process$new()` directly
(not `processx::run()`), `proc_i$get_pid()` **is** available and already
captured (`p_pid <- proc_i$get_pid()`) — so, unlike fix 1's functions,
pipeline stages can get a *real*, non-`NA` `pid`. Confirm this doesn't
change already-tested behavior (existing "Pipeline reports a positive
integer pid per process" test should keep passing unchanged, since it
already expects a real pid).

## Fix 3 — planned: `list_envs()` always raises on failure, never returns a numeric fallback

**Status: not started, design decided.**

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

## Fix 4 — planned: `list_packages()` raises a proper `condathis_*` class instead of leaking an internal variable name

**Status: not started, design decided.**

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

## Known unrelated flake, discovered while verifying fix 1 (not scheduled as one of the four fixes above)

`test-install_packages.R`'s `"install_packages warns when previous
channels are dropped (cross-platform)"` test (added during the earlier
Windows-CI-fix pass, unrelated to this contract-consistency work) failed
intermittently (~2 of 3 runs) at its own `expect_warning()` step, before
any of fix 1's new assertions ever ran — confirmed not caused by fix 1.

Working theory, not yet confirmed: the test creates an env with `channels
= c("conda-forge", "conda-forge/label/main")`, then asserts a warning
fires when a later `install_packages()` call drops
`"conda-forge/label/main"`. If `"conda-forge/label/main"` is effectively
an alias of plain `conda-forge`'s repodata, which channel string actually
gets recorded in `conda-meta/history` for a trivially-available package
like `zlib` may depend on solver tie-breaking — sometimes
`"conda-forge/label/main"` (warning fires, test passes), sometimes plain
`"conda-forge"` (nothing is "missing", no warning, test fails). Not
confirmed against real history file contents yet.

**Not scheduled** — the user was asked whether to fix this alongside fix 1
and declined to decide yet, deferring it. If pursued, the fix would be
swapping `"conda-forge/label/main"` for a channel guaranteed to actually
differ in content (needs a candidate that's real, reachable, and doesn't
reintroduce a Windows/macOS-arm64 platform-support gap the way `bioconda`
did for the original, Linux-only version of this same test).
