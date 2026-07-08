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
      `conda-forge::grep` piped into `conda-forge::sed`)
- [x] Run `just lint` and `just test` — all 700 tests pass, 0 failures

## Remaining / Optional

None — implementation is feature complete per PLAN.md.
