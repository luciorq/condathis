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

## Remaining / Optional

Implementation is feature complete per PLAN.md, including the
`run()`/`run_bin()`/`run_pipeline()` reconciliation above.
`get_micromamba_activation_envvars()` exists as a standalone, tested
building block but is intentionally **not wired into anything yet** — see
its known limitation above before doing so.

See PLAN.md's "Known, intentional divergences from `run()` / `run_bin()`"
section for the behavioral differences that remain deliberate design
choices (not open TODOs): no `verbose` support on `run_pipeline()`, and
`run_pipeline()` not going through `micromamba run` (so `activate.d` hook
scripts aren't executed by default) — the environment-activation and
process-topology differences are structural, not something a shared
parameter can reconcile; `get_micromamba_activation_envvars()` is a step
toward closing that gap, once its known limitation is resolved.
