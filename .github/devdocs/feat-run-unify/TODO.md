# TODO: feat-run-unify

Checklist companion to `PLAN.md` in this folder. Item numbers match the
status summary there. Decisions D0 to D22 are in PLAN.md.

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

## Maintainer answers (2026-11-18, D17)

- [x] 25: answer from the maintainer, "Fix this flakiness and think of
      better, more correct ways of testing this. Also double review the
      implementation itself. Remember that `run()` is a function that can
      be called in parallel multiple times."
- [x] 25: review of D16 (concurrency, every OS, tests) with an
      adversarial check: C1, os-1, os-2, os-4, F1 to F5 and C2 confirmed;
      os-3 rejected; C3 handed to `../fix-env-registry/`
- [x] 25: `conda_prefix_env_exists()` lists `<root>/envs` first
      (`read_dir_names()`); a name not listed is `FALSE`; an entry that
      cannot be looked at, or a listing that fails, errors (`NA`); no
      "empty listing means unreadable" rule
- [x] 25: a linked `<root>/envs` (symbolic link, Windows junction):
      `real_envs_dir()` in `conda_prefix_env_exists()` and
      `condathis_env_names()`, the predicate of the deletion guard
      (`is_exact_env_dir()`); `delete_stale_env_dir()` refuses to delete
      a directory that the listing rule counts as an environment
- [x] 25: tests: `read_dir_names()`; rule R5 with the listing replaced
      (`EACCES`, `EPERM`) on every OS for the probe, `env_exists()`,
      `create_env()`, `install_packages()`, `remove_env()` and `run()`;
      an environment removed while the probe reads; real permissions on
      Linux and macOS (four cases, permissions given back in `local()`,
      a skip with a reason for root); a linked `envs` directory with
      micromamba; Windows junctions in `make_existence_layout()`; no
      shell and one `processx` process per warm `run()`; four parallel
      sessions of `run()` on a fresh root
- [x] 25: L1: in a locale that is not UTF-8, the `fs` names made an
      environment with a non-ASCII name missing; the probe reads names
      with `list.files()` and real paths with `normalizePath()`, with a
      C-locale test on Linux and macOS
- [x] 25: the `icacls` variant of the unreadable-directory test, and its
      backup-privilege comment, removed
- [x] 25: `?run`: `run()` does not wait for another session that changes
      the environment (C2), documentation only
- [x] 25: NEWS: one bug-fix bullet for the linked `envs` directory
- [x] 25: Linux: affected test files, the developer suite (9405 pass,
      0 fail, 0 skip), a stress run and the timing (PLAN.md D17)
- [x] 25: omicron: developer suite with zero skips (the permission test
      runs there): 9403 pass (round 7)
- [x] 25: kappa: developer suite with only skips for another OS; check
      that micromamba lists the junctions of `make_existence_layout()`
      and of the linked `envs` test as the file-system rule does (round 7)
- [x] 25: kappa: the sandbox with a dangling junction is deleted
      (`delete_sandbox_links()`), with a test
- [ ] After 0.2.0: `run()` waits for another session that changes the
      environment (C2, `../post-0.2.0/` item 22)

## D18 (2026-11-18): Python state, venv and pixi global activation

- [x] 26: `python_isolation_envvars()` in every child (run family in both
      modes, micromamba's processes)
- [x] 26: venv as a host activation (`undo_host_venv()`, `pyvenv.cfg`)
- [x] 26: pip and uv overrides of `micromamba create`/`install`; `list`
      in its temporary directory with no pip configuration
- [x] 26: `clean_cache()` deletes `<root>/home/.local`
- [x] 26: environment file in a read-only directory: copy, or classed
      abort for relative pip paths
- [x] 26: variables of a pixi global binary that started R removed
      (`read_trampoline_env_vars()`)
- [x] 26: `?condathis-options`, `?condathis-conditions`, `?clean_cache`,
      NEWS
- [ ] 26: verify round on omicron (macOS) and kappa (Windows): the
      `Scripts` rule with a real venv, `PIP_CONFIG_FILE=nul`, the user
      site under `APPDATA`, `file.access()` of a read-only directory, a
      pixi global R on Windows if available
- [ ] After 0.2.0: compiler variables of a `conda activate`d host prefix
      without backups (`../post-0.2.0/` item 23)
- [x] 27: `install_packages()` and `list_packages()` read the probe of
      `resolve_backend()`; `install_packages(packages = NULL)` aborts
      with `condathis_backend_probe_failed` on a failed probe (D19)
- [x] 27: Windows: a command found inside the environment is returned
      with backslashes (`native_command_path()`, D19)
- [ ] 27: verify round on kappa: a command found in
      `Library/bin` starts with the `\` path; the issue #12
      double-quote assertion of `test-create_env.R` is off Windows only
      until R.exe is checked there

## D20 (2026-11-18): jarl with every rule

- [x] 28: `jarl check .` with every rule (`jarl.toml`): 0 findings, from
      650; `just lint` fails on a finding
- [x] 28: the 16 functions above the complexity limit split into helpers
      (`../post-0.2.0/PLAN.md` item 8), with a differential check
- [x] 28: `<<-` and `:::` gone from `R/` and `tests/`; ignore comments
      only for false positives and inputs under test
- [ ] 28: verify round on omicron and kappa: the full suite, in
      particular `test-run_pipeline.R` on kappa (the `reaped` state of
      `pump_pipeline_io()` and `broken_pipe_transition()` run only on
      Windows) and `test-run.R` (the `px` path of processx)

## D21 (2026-11-18): review of round 8

- [x] 29: reticulate's `LD_LIBRARY_PATH` entries removed, and the
      binary directories of its Conda python leave `PATH`
      (`reticulate_host_state()`); checked with a real reticulate binding
      on Linux
- [x] 29: `micromamba_pip_env_file()` probes writability only for a file
      that runs pip
- [x] 29: NEWS pip bullets name `install_packages()`; `?run` and README
      name `export` and `source` (not `cd`, a program on macOS)
- [x] 29: reticulate article output restored (ignore comment); `px`
      found by processx's own lookup, no skip
- [ ] 29: verify round on omicron and kappa: `test-python_isolation.R`
      (the Windows root rule, the link case on macOS)
- [x] 29: kappa's patch of `test-python_isolation.R` (POSIX venv name
      for the `on_windows = FALSE` case, `/` root for the reticulate
      case) applied; passes on Linux (D22 item 3)

## D22 (2026-11-18): verify round of round 8

- [x] 30: `PIP_USER=false`, `PIP_REQUIRE_VIRTUALENV=false`, no
      `PIP_TARGET`/`PIP_PREFIX`/`PIP_ROOT` for every child
      (`python_isolation_envvars()`); `?condathis-options`, NEWS
- [x] 30: `test-list_packages_pypi.R` direct python call isolated from
      the host's Python and pip state
- [x] 30: pixi trampoline as the micromamba path resolved to its `exe`
      in discovery (`resolve_pixi_trampoline()`, 17c)
- [x] 30: `parse_match_spec()` exact names (`../post-0.2.0/` item 26)
- [x] 30: rattlerthis: `configure`/`cleanup` mode 0755; the WebAssembly
      test's child gets its `TMPDIR` in the test's temporary directory
- [x] 30: Linux: developer suite and the hostile-host suite, 0 failures,
      0 errors, 0 skips
- [ ] 30: verify round on omicron and kappa (the trampoline test on
      Windows uses a copy of micromamba; the pip tests on every OS)

## D23 (2026-11-18): review of round 9

- [x] 31: `resolve_pixi_trampoline()` follows only an absolute `exe`
      (`trampoline_config_exe()`); test with a relative `exe`
- [x] 31: `PIP_REQUIRE_VENV` removed for every child; test
- [x] 31: `?condathis-options` and NEWS: `target`, `prefix` and `root`
      in a pip configuration file still apply
- [x] 31: Linux: developer suite and the hostile-host suite (with
      `PIP_REQUIRE_VENV=1`), 0 failures, 0 errors, 0 skips
- [x] 31: verify round on omicron and kappa (round 9): Linux 9798 pass
      plain and under the hostile host, omicron 9796 pass, both 0 skip;
      kappa 9733 pass with 1 test failure, fixed below; R CMD check
      --as-cran --no-manual OK on all three apart from the 404 NOTE of the
      mizu article URL (site not deployed yet)
- [x] 31: kappa: the pip.conf scenario of `test-python_isolation.R`
      set only HOME and APPDATA; pip on Windows finds its user
      configuration through USERPROFILE (`<home>/pip/pip.ini` and the
      roaming folder of the profile). The test now sets USERPROFILE and
      writes both files (158 of 158 pass on kappa)
- [x] 31: `?run` and README: `dir` and `echo` on Windows run when a
      program of that name is on `PATH` (Git for Windows, pixi
      m2-coreutils); the docs say so
- [x] 31: rattlerthis `test-parity-childenv.R` expected the configured
      micromamba path as `MAMBA_EXE`; with a pixi trampoline condathis
      now runs the real binary, so the test compares with
      `get_best_micromamba_path()` (926 of 926 pass with the trampoline
      and with the real binary)
- [x] Before submitting: deploy the pkgdown site so the mizu article URL
      in README resolves, then rerun `R CMD check --as-cran` with remote
      URL checks (2026-11-21: Status OK, with qpdf)
- [x] 32: the vendored `polyglot` build 1 is the file published on
      prefix.dev (SHA256 `e48bcdd9...0b`); the first copy was a local
      build of the same contents with another timestamp

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
- [x] 17c: resolve a pixi trampoline given as the micromamba path to its
      real binary (done in 0.2.0, D22)
- [ ] 17g: `CONDA_DEFAULT_ENV` of the fixed activation for an
      `env_path()` environment (its directory now)
- [ ] 17b follow-up: a public way for a backend to get the child block
      (`base_env` for `backend_create_env()` and `backend_install()`), so
      rattlerthis stops calling `build_child_env()`
