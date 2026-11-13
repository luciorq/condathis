# TODO: post-0.2.0

Checklist companion to `PLAN.md` in this folder. Item numbers match.
Nothing here blocks the v0.2.0 release. The release steps themselves
are in `../feat-strict-defaults/TODO.md` ("Release steps").
Updated 2026-11-13.

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

- [ ] 8: fix the 7 jarl findings in `R/` (2 unused objects, 5 `if_not_else`)
- [ ] 8: fix the 23 jarl findings in `tests/` (add missing assertions rather
      than deleting captures; two empty trailing arguments in
      `test-run_output_file.R`)
- [ ] 9b: improve `test-rethrow_error.R` (in-code TODO at line 68)
- [ ] 9c: bump the mocked micromamba version in
      `test-check_micromamba_version.R:48` when the internal pin moves
      past 2.8.1
- [ ] 7: check conda-forge for a fixed win-64 MinGW runtime batch. Drop the
      `libgcc`/`libgfortran5` pins in `helper-cli-tools.R` if Windows CI
      is green without them; otherwise file the upstream report

## rattlerthis integration

- [ ] 18a: build rattlerthis against condathis 0.2.0 (with
      `env_definition()`) and run its tests
- [ ] 18b: in rattlerthis, quiet or migrate the `env_file =` calls of
      `test-parity-envfile.R:98` and `test-parity-linkscripts.R` (about
      line 320), which now see `condathis_deprecated_env_file_arg`
- [ ] 2: end-to-end smoke test in `rattlerthis`'s suite:
      `condathis::create_env(method = "rattler")` -> `condathis::run()` ->
      `remove_env()`, plus one `condathis_backend_mismatch` assertion
- [ ] 3: close the rattlerthis "flag upward" TODO with a pointer to the
      decided minimal `list_packages()` schema
- [ ] 3: (optional) assert the four guaranteed columns after
      `backend_list_packages()` dispatch in condathis
- [ ] 10: `backend_status()` user-facing diagnostics function
- [x] 4: condathis README names rattlerthis, R-universe and the backends
      article (2026-11-13, "How It Works" in `README.qmd`)
- [ ] 4: README cross-link check in rattlerthis
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
      the second unnamed argument, or leave it to NEWS

## run() convergence (next minor release headline)

- [ ] 6: resolve nested-activation artifacts in
      `get_micromamba_activation_envvars()` (reproduce from a pixi shell,
      extend the noise filter, test with a fake nested baseline)
- [ ] 1: add `activate` to `run()`, route it through `backend_resolve_run()`
      + `execute_command()`, collapse `run_internal_native()` into
      `run_internal_backend()`, fix `verbose = "cmd"` echo, audit internal
      callers, rewrite the equivalence tests, NEWS breaking bullet, update
      the header of `R/get_micromamba_activation_envvars.R`

## Found on 2026-11-05

- [ ] 13: close issue #12 (fixed in 0.2.0, see PLAN.md); optionally add
      the issue's `R -e` double-quote example to `test-create_env.R`
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

- [ ] 17b: no `env_name = ` hint when `env_name` is already in the call
      (`given_args` in `collect_package_specs()`)
- [ ] 17c: `create_env(NULL, "env.yml", ...)` hint names the user's file;
      no "after the package specs" for a leading `NULL`
- [ ] 17d: `method = "native"` soft in `env_exists()`, `list_envs()`,
      `get_install_dir()`, `list_packages()`, `get_env_dir()` and
      `run_pipeline()`; then shorten the NEWS bullet and
      `?condathis-conditions`
- [ ] 17e: document that testthat's 3rd edition shows the soft
      deprecations inside `test_that()` (`lifecycle_verbosity`)
- [ ] 17f: `install_packages(packages = NULL)` with a failed (`NA`)
      environment probe goes to the backend instead of returning 0
- [ ] 19: add a license file to the upstream `polyglot` repository
      (maintainer)
- [ ] 20a: Windows backslashes in the relative branch of
      `resolve_env_bin_path()`
- [ ] 20b: show the original URL in the "installed from another
      channel" hint for a URL channel
- [ ] 20c: (optional) narrow the bioconda hint for a missing version
- [ ] 20d: Windows CRAN-mode test time: decide after win-builder
- [ ] 20e: unit test for `sigint_ignored_in_proc()`

## Explicitly not planned

- 12: `verbose` on `run_pipeline()` (structural divergence, documented)
