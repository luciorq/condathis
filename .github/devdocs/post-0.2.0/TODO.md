# TODO: post-0.2.0

Checklist companion to `PLAN.md` in this folder. Item numbers match.
Nothing here blocks the v0.2.0 release. The release steps themselves
are in `../feat-strict-defaults/TODO.md` ("Release steps").
Updated 2026-11-18.

## Before 0.2.0 (release bookkeeping, item 0)

- [x] 0: create the GitHub Release for the existing `v0.1.4` tag (done
      2026-09-18, `created_at` inherited the tag date 2026-06-19)
- [x] 0: both CRAN 0.1.4 tarball edits ported onto `feat-strict-defaults`
      (2026-09-18, uncommitted): `skip_if_offline()` + `skip_on_cran()` in
      `test-satisfy_dependencies.R`, and `stream = "both"` in
      `get_micromamba_version.R` (a no-op, kept so sources match CRAN)
- [x] 0: `CRAN-SUBMISSION`: not committed; `just git-tag` tags the SHA
      it records and checks its version (2026-11-13, `8cffc25`)

## Small, mechanical

- [x] 8: every jarl finding fixed, with every rule selected (650,
      including 16 functions above the complexity limit, split into
      helpers); `jarl.toml`; `just lint` fails on a finding
      (2026-11-18, `../feat-run-unify/` D20). The 7 findings in `R/` and
      the 23 in `tests/` listed before are among them; missing
      assertions added rather than captures deleted
- [x] 26: `parse_match_spec()` writes `license_family` also as `license`
      (exact names and a test, 2026-11-18, `../feat-run-unify/` D22)
- [x] 9b: improve `test-rethrow_error.R` (in-code TODO at line 68):
      explicit frames, assertions on the return value, commented-out
      code and TODO removed (2026-11-18)
- [x] 9c: the mock returns `"2.10.0"`, above the minimum `"2.8.1"`; the
      stale TODO comment replaced (2026-11-18)
- [ ] 7: check conda-forge for a fixed win-64 MinGW runtime batch. Drop the
      `libgcc`/`libgfortran5` pins in `helper-cli-tools.R` if Windows CI
      is green without them; otherwise file the upstream report.
      2026-11-18: 16.1.0 `_2`/`_3` and 16.2.0 `_4` to `_7` exist (`_2` is
      not marked broken); pins kept until a Windows run

## rattlerthis integration

- [x] 18a: build rattlerthis against condathis 0.2.0 (with
      `env_definition()`) and run its tests (round 6 of
      `../feat-run-unify/`, committed in rattlerthis; rerun once after
      the round 8 changes)
- [x] 18b: in rattlerthis, quiet or migrate the `env_file =` calls of
      `test-parity-envfile.R:98` and `test-parity-linkscripts.R` (about
      line 320), which now see `condathis_deprecated_env_file_arg`
      (`lifecycle_verbosity = "quiet"` and `env_definition()`)
- [x] 2: end-to-end smoke test in `rattlerthis`'s suite:
      `condathis::create_env(method = "rattler")` -> `condathis::run()` ->
      `remove_env()`, plus one `condathis_backend_mismatch` assertion
      (`test-condathis-conformance.R`, checked 2026-11-18)
- [x] 3: close the rattlerthis "flag upward" TODO with a pointer to the
      decided minimal `list_packages()` schema (rattlerthis TODO done
      2026-10-22)
- [ ] 3: (optional) assert the four guaranteed columns after
      `backend_list_packages()` dispatch in condathis
- [ ] 10: `backend_status()` user-facing diagnostics function
- [x] 4: condathis README names rattlerthis, R-universe and the backends
      article (2026-11-13, "How It Works" in `README.qmd`)
- [x] 4: README cross-link check in rattlerthis (its README links
      condathis and `method = "rattler"`, checked 2026-11-18)
- [ ] 18c: rattlerthis accepts `definition` and implements
      `backend_describe_definition()`
- [ ] 18d: rattlerthis reads `pixi.lock` through `rattler_lock`

## Needs a decision

- [ ] 5: package-wide supervisor escape hatch. Decide name and precedence
      (recommended `options(condathis.supervise = ...)`), then implement
      `resolve_supervise()` shared by all three run functions
- [x] 9a: `create_env(env_file = , packages = )` mixing. Decided: abort
      (`condathis_create_env_conflicting_args`, `0e60288`, 2026-11-04).
      Superseded 2026-11-13 by `env_definition()`, which aborts the same
      way (see `../feat-env-file/`)
- [ ] 11: container backend package: pursue or drop
- [ ] 17a: `install_packages("pkg", "env", <channels>)`: add a check of
      the second unnamed argument, or leave it to NEWS (it can create a
      missing `"condathis-env"` before the solver fails, see PLAN.md)

## run() convergence (done in 0.2.0)

- [x] 6: resolve nested-activation artifacts in
      `get_micromamba_activation_envvars()` (done in 0.2.0, 2026-11-16,
      see `../feat-run-unify/`)
- [x] 1: add `activate` to `run()` and give the three run functions one
      path (done in 0.2.0, 2026-11-16, see `../feat-run-unify/`)

## Follow-ups of the run-family unification (item 21)

- [ ] 21a: optional backend hook for `activate = FALSE` (container or
      remote backends)
- [x] 21b: `R_LIBS*` of a Conda R in child processes: every `R_*`
      variable leaves the child (feat-run-unify D15)
- [x] 21c: rattlerthis: update `test-parity-childenv.R` (fixed activation
      of `run_bin(activate = FALSE)`, status 137 for a killed command,
      `MAMBA_SHLVL` `"1"` and empty prompt modifiers, `R_HOME` unset, no
      `R_*` variables), run its suite;
      `rattler_pip_base_env()` isolation (done 2026-11-17, uncommitted
      in rattlerthis; feat-run-unify round 6)
- [ ] 21g: a public way for a backend to get the child block (`base_env`
      for `backend_create_env()` and `backend_install()`), so rattlerthis
      stops calling condathis's internal `build_child_env()`
- [ ] 21d: soft-deprecate `run_bin()` in a later release
- [x] 21e: Windows: lookup on the command's `PATH` (done in 0.2.0,
      feat-run-unify D13)
- [x] 21f: pixi trampoline as the micromamba path (`MAMBA_SHLVL` and
      Windows with a Conda R done in 0.2.0, feat-run-unify D11 and D12;
      the trampoline resolved to its `exe` in discovery, 2026-11-18,
      feat-run-unify D22; only an absolute `exe`, D23)

## run() and changes by another session (item 22)

- [ ] 22: decide whether `run()` waits (a shared lock taken and released
      before the probe) for another session that changes its
      environment; test with a callr session that holds the lock

## Compiler variables of an activated host prefix (item 23)

- [ ] 23: undo the compiler activation of a host prefix activated with
      `conda activate` or `micromamba activate` (variables without
      `CONDA_BACKUP_*`), and update the limit in `?condathis-options`

## Found on 2026-11-05

- [ ] 13: close issue #12 (fixed in 0.2.0, see PLAN.md; maintainer)
- [x] 13: the issue's `R -e` double-quote example is in
      `test-create_env.R`, off Windows (2026-11-18)
- [ ] 13: run it on kappa without the `is_windows()` branch; drop the
      branch if R.exe keeps the quotes
- [x] 14: the pip test of `test-list_packages_pypi.R` skips in a
      non-UTF-8 locale; `.github/CONTRIBUTING.md` notes the UTF-8 locale
      and the DNS-based `skip_if_offline()` (2026-11-13, `8cffc25`)
- [x] 15: the backends article and the README install rattlerthis from
      R-universe (2026-11-13). condathis's `DESCRIPTION` does not name
      rattlerthis (decided 2026-11-08, see PLAN.md)
- [ ] 15: install the rattlerthis binary from R-universe in the pkgdown
      workflow instead of building it from source
- [ ] 16: decide whether condathis aborts early, with one class, on
      WebAssembly (webR), where no backend can start a process

## Found on 2026-11-13 (0.2.0 CRAN preparation)

- [x] 17b: no `env_name = ` hint when `env_name` is already in the call
      (`given_args` in `collect_package_specs()`, 2026-11-18)
- [x] 17c: `create_env(NULL, "env.yml", ...)` hint names the user's file;
      no "after the package specs" for a leading `NULL` (2026-11-18)
- [x] 17d: `method = "native"` soft in `env_exists()`, `list_envs()`,
      `get_install_dir()`, `list_packages()`, `get_env_dir()` and
      `run_pipeline()`; then shorten the NEWS bullet and
      `?condathis-conditions` (2026-11-18)
- [x] 17e: document that testthat's 3rd edition shows the soft
      deprecations inside `test_that()` (`lifecycle_verbosity`): for
      calls made inside other packages (2026-11-18)
- [x] 17f: `install_packages(packages = NULL)` with a failed (`NA`)
      environment probe aborts with `condathis_backend_probe_failed`;
      the probe is the one of `resolve_backend()` (2026-11-18,
      feat-run-unify D19)
- [x] 19: add a license file to the upstream `polyglot` repository:
      MIT text in its `LICENSE.txt` (was empty), `license: MIT` in
      `recipe/recipe.yaml`, a License section in its README (2026-11-20;
      the maintainer commits and pushes it)
- [x] 19: the shipped `polyglot-channel` holds build 1 of polyglot
      0.1.0 (`h4616a5c_1`, records `license: MIT`); the tests read its
      file name, build and hashes from `noarch/repodata.json`
      (`polyglot_package()`). The maintainer uploads that same file to
      prefix.dev `universe` (2026-11-21)
- [x] 20a: Windows backslashes in the relative branch of
      `resolve_env_bin_path()` (2026-11-18, feat-run-unify D19; one kappa
      run left)
- [x] 20b: show the original URL in the "installed from another
      channel" hint for a URL channel (only for a URL that is not a
      channel name; no credentials; 2026-11-18)
- [ ] 20c: (optional) narrow the bioconda hint for a missing version
- [ ] 20d: Windows CRAN-mode test time: decide after win-builder
- [x] 20e: unit test for `sigint_ignored_in_proc()` (2026-11-18)

## Found on 2026-11-18 (round 8 surveys)

- [x] `list_packages()` reads the existence probe of `resolve_backend()`
      instead of probing again (feat-run-unify D19); an `NA` probe still
      goes on to the listing
- [x] `tests/testthat/libmamba_wrappers.R` is sourced into the test's
      own environment (`local = TRUE`), not the global environment
- [x] 24: dependency minimums by what the code needs (`rlang >= 1.1.0`,
      `fs >= 1.6.7`, `stringr >= 1.5.0`, `withr >= 3.0.2`, Suggests
      `curl >= 5.0.0`, `testthat >= 3.3.2`); README and cran-comments
      name the source builds of R 4.3 and macOS arm64 R 4.4 (2026-11-18)
- [x] 24: `linux-riscv64` micromamba from 2.9.0 on (2026-11-18)
- [x] 24: roxygen2 8.1.1 (only `Config/roxygen2/version` changed)
- [x] 24: CI jobs for macOS x86_64, Linux arm64 and R 4.4 (2026-11-18)
- [ ] 24: first green run of the three new CI jobs (needs a push)
- [x] 25: docs survey DOC-1 to DOC-4: NEWS sandbox bullet dropped,
      shell builtins per OS, `env_definition()` title, mizu article
      linked; `?install_packages` names the probe abort (2026-11-18)
- [x] 25: DOC-5, `role = "aut"` for Claudio Zanettini (maintainer
      decision 2026-11-20; `man/condathis-package.Rd` regenerated)
- [x] Review of round 8 (feat-run-unify D21): reticulate's
      `LD_LIBRARY_PATH` and Conda `PATH` undone; no write probe for an
      environment file without pip; NEWS, `?run`, README and the
      reticulate article corrected; `px` lookup without a skip
- [x] Push `main` so the pkgdown site has
      `articles/python-and-mizu.html`, then rerun the incoming check with
      `_R_CHECK_CRAN_INCOMING_REMOTE_=true` (2026-11-21: Status OK)
- [ ] Before submitting (maintainer): run the test environments of
      `cran-comments.md` on the final tree and make its results line
      match

## Explicitly not planned

- 12: `verbose` on `run_pipeline()` (structural divergence, documented)
