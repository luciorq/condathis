# TODO: Processx 3.9.0 Pipeline Support

## Done

- [x] Write PLAN.md and TODO.md
- [x] Update `DESCRIPTION` — `processx` → `processx (>= 3.9.0)`
- [x] Update `R/native_cmd.R` — add `cleanup_tree`, `encoding`, `linux_pdeathsig`
- [x] Create `R/conda_activation.R` — `get_activation_envvars()`
- [x] Create `R/pipeline_result.R` — S3 `condathis_pipeline` class
- [x] Create `R/run_pipeline.R` — `run_pipeline()` with pipe plumbing
- [x] Update `NAMESPACE` — export `run_pipeline`
- [x] Create `tests/testthat/test-run_pipeline.R`
- [x] Update `NEWS.md` with changelog entry
- [x] Add `linux_pdeathsig = TRUE` to `native_cmd()`
- [x] Add `stdin = "|"` writable stdin support for `run_pipeline()` (new `input` argument)
- [x] Add per-command `stdout`/`stderr` override support in named list spec
- [x] Fix `run_pipeline()` env-existence check running before default-env
      auto-creation (auto-create path was previously unreachable)
- [x] Fix `run_pipeline()` crashing when reading `stdout`/`stderr` for a
      process whose output is redirected to a file or discarded (`NULL`)
- [x] Add more test coverage (stdout NA, 3-command pipe, named list spec,
      pid check, timeout field, stdin/input, per-command overrides,
      auto-create default env)
- [x] Write integration test for mixed environments (two real Conda envs:
      `conda-forge::grep` piped into `conda-forge::sed`; `m2-grep`/`m2-sed`
      on Windows)
- [x] Fix `run_pipeline()` letting a raw, uncaught `processx` error escape
      when a command is not found — now respects `error = "cancel"` /
      `"continue"` via a `spawn_failures` mechanism, consistent with `run()`
- [x] Fix `run_pipeline()` error messages breaking or corrupting when a
      failing command's `stderr` contained curly braces — added
      `escape_cli_braces()`, applied to stderr, `cmd`, and `env_name`
- [x] Fix `run_pipeline()` always throwing on a missing custom `env_name`
      regardless of `error` — `error = "continue"` now reports
      `status = 127` per affected command instead of aborting the pipeline;
      `error = "cancel"` keeps the original fail-fast behavior
- [x] Add regression tests for the three fixes above (command not found ×
      cancel/continue, brace-escaping, missing custom env × cancel/continue)
- [x] Run `just lint` and `just test` — all 712 tests pass, 0 failures

## Reconciliation: feature parity between `run()`, `run_bin()`, and `run_pipeline()`

- [x] Crash safety: add `supervise`, `cleanup_tree`, `linux_pdeathsig`
      arguments to `run()` and `run_bin()` (default `FALSE`, preserving
      existing behavior). Made `run_pipeline()`'s `supervise`/`cleanup_tree`
      (previously hardcoded `TRUE`) and `linux_pdeathsig` (new) overridable
      arguments too, default `TRUE`/`TRUE`/`FALSE`.
- [x] Writable `stdin = "|"` + `input`: add to `run()` and `run_bin()`.
      Since `processx::run()` has no way to write to a `stdin = "|"`
      connection it creates internally (confirmed: `stdin = "|"` alone
      deadlocks the child), added `R/run_process_with_input.R` — a
      `processx::process$new()`-based helper mirroring
      `run_pipeline()`'s own first-process input-writing logic, returning a
      `processx::run()`-shaped list so it slots into the existing
      `rethrow_error_run()` error handling unchanged. `native_cmd()` and
      `run_bin()` now branch to it only when `stdin = "|"`; the common case
      (`stdin = NULL`/file path) is untouched.
      Trade-off (documented in the `input` param docs): no live
      stdout/stderr streaming, spinner, or timeout on this code path.
- [x] Return shape: new `R/run_result.R` — S3 class `condathis_result`
      (`new_condathis_result()`, `format()`, `print()`, `as.list()`),
      returned by `run()` and `run_bin()` instead of a plain
      `processx::run()` list. Remains a plain list under the hood
      (`res$status`/`res$stdout`/etc. unaffected — verified `parse_output()`
      and existing tests that do `res$status` still work unchanged) with
      `pid`, `cmd`, `env_name` fields added, mirroring
      `condathis_pipeline`'s per-process shape.
- [x] Add `condathis_run_invalid_input` validation (mirrors
      `run_pipeline()`'s `condathis_pipeline_invalid_input`): `input`
      requires `stdin = "|"` on both `run()` and `run_bin()`.
- [x] Add test coverage: `condathis_result` class/fields/print, `input` +
      `stdin = "|"` (success and failure, `error = "cancel"`/`"continue"`),
      invalid `input` without `stdin = "|"`, crash-safety params accepted
      on all three functions, `run_pipeline()`'s override params.
- [x] Update README.qmd/README.md "Known Caveats" — no longer claims pipes
      are unsupported or that `stdin` only accepts files.
- [x] Run `just lint` and `just test` — all 735 tests pass, 0 failures.

## Activation-mechanism divergence: exploratory building block

- [x] Add `R/get_micromamba_activation_envvars.R` — `get_micromamba_activation_envvars(env_name)`,
      **not wired into `run_pipeline()`, `run()`, or `run_bin()` yet**.
      Resolves the *real* `micromamba run -n <env>` activation (including
      `activate.d` hook scripts) by spawning `Rscript` through it, dumping
      its environment as JSON, and diffing against a clean baseline —
      verified empirically that activation vars like `CONDA_PREFIX`/`PATH`
      come through correctly. Returns a named character vector in the same
      shape as `get_activation_envvars()`
      (`env = c("current", get_micromamba_activation_envvars(env_name))`),
      so it's a drop-in candidate for `run_pipeline()`'s activation overlay
      once validated further, and — since it resolves activation vars
      independently of wrapping a command in `micromamba run` — a candidate
      building block for consolidating `run()` (currently: wrap `cmd` in
      `micromamba run -n <env> cmd`) with `run_bin()` (currently: run the
      binary directly, no activation) into "resolve activation vars once,
      then execute like `run_bin()` with that overlay."
      Cached per `env_name`, invalidated when the environment's
      `conda-meta` directory changes (package install/remove) via a cheap
      file-count + max-mtime fingerprint (`activation_cache_stamp()`), not
      full content hashing — no new dependency needed for that.
      Known noise sources filtered out (verified against real captured
      output): dump-subprocess artifacts (`R_ENVIRON`, `R_PROFILE`,
      `R_SESSION_TMPDIR`, `PROCESSX_PS2*`), shell-session state
      (`PWD`, `OLDPWD`, `SHLVL`, `PS1`, `_`), and `TMPDIR` (condathis
      manages that separately per-call already).
      Known limitation, not yet resolved: on a machine where R itself runs
      from inside an already-activated environment (e.g. R installed via
      pixi/conda), the diff can still pick up nested-activation artifacts
      (`CONDA_PREFIX_1`, `CONDA_SHLVL` > 1) that reflect the *host's*
      activation stack, not the target env's — needs more investigation
      before this is wired into anything that assumes a from-scratch
      activation.
- [x] Add `tests/testthat/test-get_micromamba_activation_envvars.R` —
      correctness of resolved vars, noise filtering, missing-env error,
      usability as a `process$new(env = ...)` overlay, caching (hit/miss/
      forced-recompute), `reset_micromamba_activation_cache()`, and
      `activation_cache_stamp()` invalidation on `conda-meta` changes.
- [x] Run `just lint` and `just test` — all 753 tests pass, 0 failures.

## Wiring `get_micromamba_activation_envvars()` into `run_bin()` and `run_pipeline()`

- [x] Add `activate = TRUE` argument to `run_bin()`. When `TRUE` (now the
      default — see note below) and `env_name` exists, overlays
      `get_micromamba_activation_envvars(env_name)` as
      `env = c("current", <vars>)` on top of the existing PATH-prefix
      behavior. Silently skipped (falls back to the pre-existing,
      activation-free behavior) when `env_name` does not exist, so
      `run_bin()`'s established "works with a binary outside any managed
      environment" fallback still works unchanged. `cmd` resolution itself
      is unchanged — `run_bin()` still resolves `cmd_path` explicitly
      rather than relying on the activated `PATH`, unlike `run()`.
- [x] Add `activate = TRUE` argument to `run_pipeline()` (single toggle
      for the whole pipeline, not per-command). Replaces the per-process
      `get_activation_envvars()` call with
      `get_micromamba_activation_envvars(env_name_i)` when `TRUE`. Env
      existence is already guaranteed by `precreate_envs()`/
      `missing_envs` by the time this runs, so no extra existence check
      needed there (unlike `run_bin()`).
- [x] **Found and fixed a second instance of the `R_HOME` corruption bug**
      (see the "known noise sources" note above — that was the same root
      cause, first found in isolation). This time it was worse: `run_bin()`
      and `run_pipeline()` *themselves* apply their own
      `get_clean_conda_envvars()` scope (setting `R_HOME = ""`) *before*
      calling `get_micromamba_activation_envvars()`, so the earlier fix
      (resolve `R.home()` before that function's own clean-envvar scope)
      didn't help — `R_HOME` was already corrupted by the caller. Confirmed
      by reproduction: `run_bin(activate = TRUE)` failed with
      `/bin/Rscript: No such file or directory`. Fixed properly this time:
      added `.onLoad()` in `R/condathis-package.R` that resolves and caches
      `R.home("bin")`-derived `Rscript` path once, at package load time —
      before any condathis function has had a chance to touch `R_HOME` —
      via `get_condathis_rscript_path()`. This sidesteps the ordering
      problem entirely rather than requiring every caller in the chain to
      resolve `R.home()` before its own `get_clean_conda_envvars()` call,
      which does not compose when scopes nest.
- [x] Validated `run_bin(activate = TRUE)` against `run()` directly, as
      requested: same `CONDA_PREFIX`, same activated `PATH` (env's `bin/`
      present) — confirmed identical for both `printenv CONDA_PREFIX` and
      `printenv PATH`. `run_bin(activate = FALSE)` confirmed to preserve
      the original no-activation behavior.
- [x] Add test coverage: `run_bin(activate = TRUE)` vs `run()` equivalence
      (`CONDA_PREFIX`, `PATH`), `run_bin(activate = FALSE)` no-activation
      behavior, `run_bin(activate = TRUE)` graceful fallback for a missing
      env, `run_pipeline(activate = TRUE/FALSE)`, and a regression test
      pinning down the `R_HOME`-corruption-via-caller's-own-scope bug.
- [x] Run `just lint` and `just test` — all 767 tests pass, 0 failures.

## Remaining / Optional

Implementation is feature complete per PLAN.md, including the
`run()`/`run_bin()`/`run_pipeline()` reconciliation and the
`get_micromamba_activation_envvars()` wiring above. `run()` itself is not
yet touched — see the user's explicit "before trying to modify `run()`"
scoping for this round of work; consolidating `run()` with
`run_bin(activate = TRUE)` (as sketched in PLAN.md) remains a candidate
follow-up, not yet started.

**Flagging a default-value decision, not just an implementation detail**:
both new `activate` arguments default to `TRUE`, per explicit instruction.
For `run_pipeline()` this is additive (it always activated *something*
before; `TRUE` just makes that more accurate, at the cost of two extra
subprocess spawns per unique `env_name` on first use, mitigated by
caching). For `run_bin()`, though, this is a real change to a previously
zero-activation-by-default, documented "lower-level, no activation"
function — existing callers that relied on `run_bin()` running completely
unactivated (e.g., to avoid inheriting `CONDA_PREFIX`/`PATH` overlay) will
now get activation vars by default unless they pass `activate = FALSE`.
No existing test broke (verified), but this is a behavior change worth the
user's awareness, not merely an implementation footnote.

See PLAN.md's "Known, intentional divergences from `run()` / `run_bin()`"
section for the behavioral differences that remain deliberate design
choices (not open TODOs): no `verbose` support on `run_pipeline()`. The
"environment activation mechanism differs" divergence noted there is now
closed for `run_bin()`/`run_pipeline()` (both can do real `micromamba run`
activation via `activate = TRUE`) — `run()` was intentionally left
untouched this round.

## Additional work landed on this branch (unrelated to the pipeline feature)

Two follow-up requests were done on `feat-pipeline` while it was the active
branch. Neither touches pipeline code; noted here since they shipped as
part of the same branch/PR.

- [x] `install_packages()` channel-mismatch warning: new
      `R/get_env_history_channels.R` (`@noRd`) parses `conda-meta/history`
      to recover the channels packages already in an environment actually
      came from; `install_packages()` warns
      (`condathis_install_missing_previous_channels`) when the current
      call's `channels`/`additional_channels` would drop one of those.
      Install still proceeds — warning only. Tests:
      `test-get_env_history_channels.R` (parser, no network),
      `test-install_packages.R` (real env, network).
- [x] Test-suite Windows portability: `test-run.R`, `test-run_bin.R`,
      `test-run_output_file.R`, and `test-run_pipeline.R` previously called
      bare `echo`/`cat`/`sort`/`sh`/`ls`/`printenv`/`tr`/`uniq`/`rev`/`false`
      against environments that never installed them, relying on the host's
      system `PATH` — not guaranteed on Windows without Git Bash. Added
      `tests/testthat/helper-cli-tools.R` (`test_os_pkg()`, resolving to
      `m2-*` conda-forge packages on Windows) and dedicated per-file test
      environments that install `coreutils`/`bash`/`util-linux` for real;
      `sh` calls switched to `bash -c` (neither `coreutils` nor `bash`
      installs a standalone `sh`). Left untouched: argument-validation tests
      that never spawn a process, the "auto-creates the default
      environment" test (whose point is the empty auto-created env, not
      command output), and `run("R", ...)` calls (R is inherently on `PATH`
      since it's the test runner). Full suite: 773 passed, 0 failed.
