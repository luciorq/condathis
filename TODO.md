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

## Remaining / Optional

None — implementation is feature complete per PLAN.md.

See PLAN.md's "Known, intentional divergences from `run()` / `run_bin()`"
section for behavioral differences that are deliberate design choices, not
open TODOs (e.g. no `verbose` support, no `micromamba run` activation hooks,
asymmetric crash-safety defaults, `stdin = "|"` only on `run_pipeline()`).
