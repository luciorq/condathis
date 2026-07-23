# TODO: Exported-function output-type/class contract consistency

See `PLAN.md` for full rationale, the audit findings, and design decisions
behind each item below.

## Done

- [x] Full output-type/class audit of all 17 exported functions —
      identified 5 return-shape families, 2 verified-live type/failure-mode
      bugs (`list_envs()`, `list_packages()`), and several lower-priority
      asymmetries (see PLAN.md's "Secondary findings").
- [x] Fix 1: unify `create_env()`, `install_packages()`, `remove_env()`,
      `clean_cache()` around `condathis_result` (same class `run()`/
      `run_bin()` already use), including `create_env()`'s
      "already satisfied" short-circuit path.
- [x] Update `@returns` docs for all four functions.
- [x] Add `expect_s3_class(..., "condathis_result")` assertions to the
      existing success-path tests in all four test files.
- [x] Add a dedicated new test for `create_env()`'s short-circuit path
      (previously untested for its return shape specifically).
- [x] Re-verify: `test-clean_cache.R` (11/11), `test-remove_env.R`
      (13/13), `test-create_env.R` (37/37), `test-run.R` (34/34),
      `test-run_bin.R` (26/26) — all clean, no regressions from adding
      `pid`/`cmd`/`env_name` to functions that didn't have them before.
- [x] Committed as two commits: `test: extend coverage for public api
      contracts`, `feat: move all public facing internal wrappers output
      to condathis_result instead of bare lists`.

## Next: Fix 2 — `run_pipeline()` per-process entries → real `condathis_result`

- [ ] Change `R/run_pipeline.R`'s `processes[[i]] <- list(...)`
      construction to `new_condathis_result(...)`.
- [ ] Decide and implement the per-process `timeout` field (not currently
      tracked per-stage — see PLAN.md's open question).
- [ ] Confirm `format.condathis_pipeline()`/`print.condathis_pipeline()`
      (`R/pipeline_result.R`) need no changes (they read fields by `$name`,
      which works the same on a classed list) — verify with existing
      "Pipeline format and print methods work" test.
- [ ] Confirm real, non-`NA` `pid` per stage still works (already captured
      via `proc_i$get_pid()`) — existing "Pipeline reports a positive
      integer pid per process" test should keep passing unchanged.
- [ ] Add a test asserting `res$processes[[i]]` has class `condathis_result`
      and that `format()`/`print()` work directly on an individual stage.
- [ ] Re-verify full `test-run_pipeline.R` suite, no regressions.
- [ ] Commit.

## Next: Fix 3 — `list_envs()` always raises on failure

- [ ] Remove the `else { return(px_res$status) }` numeric-fallback branch
      in `R/list_envs.R`; return the parsed character vector unconditionally
      once past `rethrow_error_cmd()`.
- [ ] Update `@returns` doc to drop the "returns the process exit status
      as a numeric value" sentence.
- [ ] New test: mock `native_cmd()` to return a nonzero status without
      throwing; assert `list_envs()` now raises `condathis_cmd_status_error`
      instead of returning an integer.
- [ ] Re-verify `test-list_envs.R` and anything depending on `list_envs()`
      (`test-create_env.R`, `test-clean_cache.R`, `test-create_nested_env.R`,
      `test-env_exists.R`, `test-install_packages.R`).
- [ ] Commit.

## Next: Fix 4 — `list_packages()` raises a proper class instead of a raw `simpleError`

- [ ] Make the failure path in `R/list_packages.R` explicit: either add a
      real `condathis_*`-classed `else` branch, or remove the now-redundant
      post-hoc status check entirely (same reasoning as fix 3 — unreachable
      today given `rethrow_error_cmd()` already aborts on failure first).
- [ ] New test: same mocking approach as fix 3, asserting a
      `condathis_*`-classed error, not `Error: object 'pkgs_df' not found`.
- [ ] Re-verify `test-list_packages.R`.
- [ ] Commit.

## Deferred / not scheduled (see PLAN.md for full reasoning)

- [ ] `install_micromamba()` returning a bare path instead of a
      process-result shape — asymmetric but defensible; revisit only if
      it causes real friction.
- [ ] `get_install_dir()` side-effecting (creates + guarantees existence)
      vs. `get_env_dir()`/`micromamba_bin_path()` being pure/lazy —
      behavioral, not type-level; not scheduled.
- [ ] `env_exists()` silently coercing `NULL`/`NA` to `FALSE` instead of
      validating — interacts with fix 3, but not scheduled on its own.
- [ ] The `test-install_packages.R` cross-platform channel-warning flake
      discovered while verifying fix 1 (likely `"conda-forge/label/main"`
      solver tie-breaking) — user was asked, declined to decide yet.
