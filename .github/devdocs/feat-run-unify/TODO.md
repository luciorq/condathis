# TODO: feat-run-unify

Checklist companion to `PLAN.md` in this folder. Item numbers match the
status summary there. Decisions D0 to D16 are in PLAN.md.

## Investigation and design (2026-11-16)

- [x] Compare `run()`, `run_bin()` and `run_pipeline()`: activation,
      lookup, signal status, wording (PLAN.md finding 1)
- [x] Check what the micromamba and rattler backends return, and what a
      container or remote backend would need (finding 2)
- [x] Public use of `run_bin()`, `activate = FALSE` and `run()`
      (findings 3 and 4)
- [x] The host activation on the developer machine, `pixi shell-hook`,
      and the backup conventions of conda-forge activation scripts
      (findings 5 and 6)
- [x] Maintainer decision: do it in 0.2.0, `activate = FALSE` as the
      fixed activation of `run_pipeline()`, children in the cleanest
      environment possible (D0)

## Implemented in 0.2.0 (2026-11-16)

- [x] 1: `isolate_host_env()` in the new `R/host_env.R`: host prefixes
      (only directories with `conda-meta`), backups restored, markers
      dropped, host env_vars unset on identical value, host binary
      directories removed from `PATH`; `R_LIBS*` untouched (until D15)
- [x] 1: `build_child_env()` applies it before the clean overlay, so
      every child gets it (`native_cmd()`, activation dumps, run family)
- [x] 2: `compose_activation_overlay()`, the `session_parts` step,
      `micromamba_run_path()` and the fixed activation compose from the L1
      `PATH`; activation cache key checked (no change)
- [x] 3: `get_activation_envvars(env_name, env_dir, base_path)`: no
      `tmp_dir`, no `TMPDIR`; used by all three with `activate = FALSE`
- [x] 4: `drop_activation_stack_vars()` and `CONDA_SHLVL` set to `"1"` in
      a recorded micromamba activation
- [x] 5: `run(activate = TRUE)`; `run_command()` behind `run()` and
      `run_bin()`; `resolve_child_invocation()`, `compose_child_env()`
      and `run_family_resolve_hint()` shared with the pipeline
- [x] 6: `run_bin()` is a wrapper with `fn = "run_bin"`; classes kept;
      `resolve_run_bin_command()` deleted; `NAMESPACE` unchanged
- [x] 7: `resolve_direct_run_command()` is the one lookup rule; the
      environment's binary directories go in front of an activation
      `PATH` that names none of them
- [x] 8: `128 + n` for a killed command in all three; `broken_pipe_status`
      141 (also the Windows emulation); timeout stays `-9`
- [x] 9: "Failed to resolve command ..." and the `activate = FALSE` hint
      for all three
- [x] 10: `?register_backend` prose (`base_env`, `command`, `env`, when
      `backend_resolve_run()` runs, *Child processes*); generic formals
      unchanged
- [x] 11: `?run`, `?run_bin`, `?run_pipeline`, `?condathis-conditions`,
      `?condathis-options` (new part "The activation of the R session"),
      internal roxygen; `devtools::document()`
- [x] 11: NEWS: superseded `run_bin()` bullet replaced, `activate` in New
      features, broken pipe 141, bug fix for the activation of the R
      session, Windows lookup bullet for the three functions
- [x] 11: `python-and-reticulate.qmd`: `run()` and `run_bin()` find
      `python` the same way
- [x] 11: devdocs: this folder; `../post-0.2.0/` items 1 and 6;
      `../feat-strict-defaults/` north star; `../feat-backend-abstraction/`;
      `../feat-pipeline/`; `../fix-review-improvements/TODO.md`
- [x] Tests: fake nested host helper; unit tests of `isolate_host_env()`
      (nested host, clean session, Windows rule), `build_child_env()`,
      `condathis_r_prefix()`, `drop_activation_stack_vars()`; new
      `test-run_isolation.R` (stub backend and real micromamba, both
      modes, all three functions, missing command 127, no-`PATH`
      activation, `PATH` order, no backend call without activation,
      activating micromamba wrapper); changed expectations in
      `test-run.R`, `test-run_bin.R`, `test-run_pipeline.R`,
      `test-run_pipeline_api.R`

## Maintainer answers (2026-11-16, D11 to D13)

- [x] 19: `child_activation_level_vars()`: `CONDA_SHLVL` and
      `MAMBA_SHLVL` `"1"`, prompt modifiers `""`, applied last by
      `compose_child_env()` in both modes and for every backend; the
      fixed activation uses it
- [x] 20: Windows: R's own prefix leaves the command's `PATH`
      (`host_env_prefixes()` returns one vector); the activation dumps get
      its binary directories appended (`micromamba_run_path()`, also for
      the baseline dump), left out of the recorded `PATH`
- [x] 21: Windows: `resolve_direct_run_command(command, child_env, wd)`
      searches the working directory and the command's `PATH` with its
      `PATHEXT`; not found is `NULL`, reported as status 127 through
      `abort_command_not_found()` (`rethrow_error_run()`, pipeline stages)
- [x] Docs: `?run`, `?register_backend`, `?condathis-options`, NEWS (the
      Windows bullets replaced, one new bug-fix bullet for the lookup)
- [x] Tests: `compose_child_env()` level test, the lookup unit test
      rewritten for the child's `PATH`, a not-found test for all three
      functions, `micromamba_run_path()` Windows test, the fake nested
      host sets `MAMBA_SHLVL` and both prompt modifiers

## Maintainer answers (2026-11-17, D14 and D15)

- [x] 22: Windows: `r_prefix_command_env()` appends the binary
      directories of R's own prefix to the `PATH` of a command that is a
      program of that prefix (run family and pipeline stages)
- [x] 23: `undo_r_startup_env()` as the last step of `isolate_host_env()`:
      Rtools entries in front of the Windows `PATH`, R's default values
      (measured once per session by `r_startup_env_vars()`), R's part of
      the library paths, every `R_*` and `_R_*` variable;
      `get_clean_conda_envvars()` removes `R_HOME`
- [x] Docs: `?condathis-options` ("The startup of R"), `?run`, NEWS (one
      new bullet), devdocs D14 and D15
- [x] Tests: `r_prefix_command_env()`, `undo_r_startup_env()` on both
      rule sets, `strip_leading_path_entries()`, the measurement and its
      cache, and an end-to-end test of `run()` and `run_bin()` in both
      modes

## Maintainer answers (2026-11-17, D16)

- [x] 24: answer from the maintainer, "Fix all open questions." (the
      open question: go ahead with steps 1 to 3 of the speed fix)
- [x] 24: `micromamba_backend_env_exists()` reads the file system with
      the listing rule of micromamba (`conda_prefix_env_exists()`, the
      one-name form of `list_conda_prefix_envs()`); an unreadable
      `envs` directory errors, so the probe is `NA` (rule R5);
      `list_envs()` still asks micromamba
- [x] 24: one existence check per call: `find_owning_backends(probes =)`,
      `resolve_backend()` returns `env_exists`, read by
      `resolved_env_exists()` in `run_command()` and `precreate_envs()`;
      creation of `"condathis-env"` and every class unchanged
- [x] 24: `is_windows()` from `.Platform`; `sys_arch_is_windows()` for
      the choice of a platform; `get_sys_arch()` calls `Sys.info()` once;
      `dir_exists_quick()` on the path of every call;
      `child_conda_dirs(root_dir =)`; the `conda-meta` stamp with
      `list.files()` and `file.info()`
- [x] No new session cache (backend, existence, base environment, host
      prefixes)
- [x] Tests: the existence rule against `list_conda_prefix_envs()` and
      `micromamba env list`, the `NA` of an unreadable `envs` directory, a
      warm `run()` and `run_bin()` start only the command and check once,
      `run_pipeline()` checks once, `test-get_sys_arch.R`
- [x] Benchmark before and after on Linux (PLAN.md D16): a warm `run()`
      about 22 ms instead of 281 ms, the floor 16 ms
- [x] NEWS: one bullet in "Other changes" (`run()` about ten times faster
      than in 0.1.4)
- [x] Linux developer suite: 9314 pass, 0 fail, 0 skip
- [x] Round 6 on Linux, omicron and kappa after D16, also the rattlerthis
      suite (PLAN.md "Verification")

## Before submitting 0.2.0

- [x] 12: Linux developer suite, the fake nested host, and
      `R CMD check --as-cran` on the final tree (round 3)
- [x] 12: omicron (macOS): developer suite with zero skips,
      `R CMD check --as-cran --no-manual` (round 3)
- [x] 12: kappa (Windows): developer suite with the updated tests and
      `R CMD check --as-cran --no-manual` (round 3, 2026-11-17)
- [x] 12: kappa with a conda-forge R (D12, D14): round 5 passes but for
      one test bug (`CURL_CA_BUNDLE`), fixed and not rerun there
- [x] 12: rounds 4 and 5 on all three machines after D14 and D15
      (PLAN.md "Verification")
- [x] 12: round 6 on all three machines after D16; the conda-forge R
      `CURL_CA_BUNDLE` fix passes on kappa; three `test-run_bin.R`
      expectations fixed for D14 under conda R
- [x] README: the r-universe links that answer 403 removed (URL check
      clean); `inst/WORDLIST` gets the words of the Python articles
- [ ] 18: commit (maintainer): `git add` the new files `R/host_env.R`,
      `tests/testthat/test-run_isolation.R` and this folder, plus the
      modified files

## In rattlerthis

- [x] 13: update `tests/testthat/test-parity-childenv.R`: the
      `run_bin_noact` expectations (about lines 180 to 195 and 413 to
      441) and `run_bin_status` 137 (about lines 689 to 738); then run
      its suite against this condathis (PLAN.md follow-up 17a), and the
      new D11 values (`MAMBA_SHLVL` `"1"`, empty prompt modifiers)
- [x] 17b: `rattler_pip_base_env()` builds its own block without the L1
      isolation (now from condathis's internal `build_child_env()`)
- [x] Suite against this condathis (round 6); the D16 `env_exists()`
      echo assertion of `test-parity-verbose.R` fixed
- [ ] Maintainer: commit the rattlerthis changes

## Decided

- [x] 15: `R_LIBS`, `R_LIBS_USER`, `R_LIBS_SITE` of a Conda R: cleared,
      with every `R_*` variable (D15)
- [x] 16: soft-deprecate `run_bin()` after 0.2.0 (`../post-0.2.0/`
      item 21d)
- [x] `LC_ALL=C.UTF-8` of micromamba's activation on macOS: kept, it is
      the backend's activation (PLAN.md "Verification", round 5)

## After 0.2.0

- [ ] 14: optional backend hook to describe a command without activation
      or refuse `activate = FALSE` (container or remote backends)
- [ ] 17c: resolve a pixi trampoline given as the micromamba path to its
      real binary
- [ ] 17g: `CONDA_DEFAULT_ENV` of the fixed activation for an
      `env_path()` environment (its directory now)
- [ ] 17b follow-up: a public way for a backend to get the child block
      (`base_env` for `backend_create_env()` and `backend_install()`), so
      rattlerthis stops calling `build_child_env()`
