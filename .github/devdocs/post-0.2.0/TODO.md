# TODO: post-0.2.0

Checklist companion to `PLAN.md` in this folder. Item numbers match.
Nothing here blocks the v0.2.0 release.

## Before 0.2.0 (release bookkeeping, item 0)

- [x] 0: create the GitHub Release for the existing `v0.1.4` tag (done
      2026-09-18, `created_at` inherited the tag date 2026-06-19)
- [x] 0: both CRAN 0.1.4 tarball edits ported onto `feat-strict-defaults`
      (2026-09-18, uncommitted): `skip_if_offline()` + `skip_on_cran()` in
      `test-satisfy_dependencies.R`, and `stream = "both"` in
      `get_micromamba_version.R` (a no-op, kept so sources match CRAN)
- [ ] 0: decide whether to commit `CRAN-SUBMISSION` going forward

## Small, mechanical

- [ ] 8: fix the 7 jarl findings in `R/` (2 unused objects, 5 `if_not_else`)
- [ ] 8: fix the 23 jarl findings in `tests/` (add missing assertions rather
      than deleting captures; two empty trailing arguments in
      `test-run_output_file.R`)
- [ ] 9b: improve `test-rethrow_error.R` (in-code TODO at line 68)
- [ ] 9c: bump the mocked micromamba version in
      `test-check_micromamba_version.R:48` when the internal pin moves
      past 2.8.1
- [ ] 7: check conda-forge for a fixed win-64 MinGW runtime batch; drop the
      `libgcc`/`libgfortran5` pins in `helper-cli-tools.R` if Windows CI
      is green without them; otherwise file the upstream report

## rattlerthis integration

- [ ] 2: end-to-end smoke test in `rattlerthis`'s suite:
      `condathis::create_env(method = "rattler")` -> `condathis::run()` ->
      `remove_env()`, plus one `condathis_backend_mismatch` assertion
- [ ] 3: close the rattlerthis "flag upward" TODO with a pointer to the
      decided minimal `list_packages()` schema
- [ ] 3: (optional) assert the four guaranteed columns after
      `backend_list_packages()` dispatch in condathis
- [ ] 10: `backend_status()` user-facing diagnostics function
- [ ] 4: README "Alternative backends" section in condathis; README
      cross-link check in rattlerthis

## Needs a decision

- [ ] 5: package-wide supervisor escape hatch. Decide name and precedence
      (recommended `options(condathis.supervise = ...)`), then implement
      `resolve_supervise()` shared by all three run functions
- [ ] 9a: `create_env(env_file = , packages = )` mixing. Decide pass-both
      vs abort, then tests and docs
- [ ] 11: container backend package: pursue or drop

## run() convergence (next minor release headline)

- [ ] 6: resolve nested-activation artifacts in
      `get_micromamba_activation_envvars()` (reproduce from a pixi shell,
      extend the noise filter, test with a fake nested baseline)
- [ ] 1: add `activate` to `run()`, route it through `backend_resolve_run()`
      + `execute_command()`, collapse `run_internal_native()` into
      `run_internal_backend()`, fix `verbose = "cmd"` echo, audit internal
      callers, rewrite the equivalence tests, NEWS breaking bullet, update
      the header of `R/get_micromamba_activation_envvars.R`

## Explicitly not planned

- 12: `verbose` on `run_pipeline()` (structural divergence, documented)
