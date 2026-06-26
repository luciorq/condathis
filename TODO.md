# TODO: Processx 3.9.0 Pipeline Support

## Implementation

- [x] Write PLAN.md and TODO.md
- [ ] Update `DESCRIPTION` — `processx` → `processx (>= 3.9.0)`
- [ ] Update `R/native_cmd.R` — add `cleanup_tree`, `linux_pdeathsig`, `encoding`
- [ ] Create `R/conda_activation.R` — `get_activation_envvars()`
- [ ] Create `R/pipeline_result.R` — S3 `condathis_pipeline` class
- [ ] Create `R/run_pipeline.R` — `run_pipeline()` with pipe plumbing
- [ ] Update `NAMESPACE` — export `run_pipeline`
- [ ] Create `tests/testthat/test-run_pipeline.R`
- [ ] Update `tests/testthat/test-native_cmd.R` for new params
- [ ] Update `NEWS.md` with changelog entry
- [ ] Run `just lint` and verify no new issues
- [ ] Run `just test-file run_pipeline` to verify pipeline tests pass
- [ ] Run `just test-file native_cmd` to verify native_cmd tests pass
