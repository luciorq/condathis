# TODO: feat-env-file

Checklist companion to `PLAN.md` in this folder. Item numbers match.
Decisions D1 to D5 are in PLAN.md.

## Research and design (2026-11-13)

- [x] Research: conda 26.9.4 + conda-lockfiles 0.2.2, micromamba 2.10.0,
      rattler crates and rattlerthis, pixi 0.84.2, condathis internals
      (PLAN.md "Findings")
- [x] Isolated micromamba runs for every format, name mismatch, mixing,
      dry run, platform and category case (PLAN.md findings 1 to 12)
- [x] Three designs and a judge; name `env_definition()` chosen (PLAN.md
      "Naming")
- [x] Maintainer decision: all of it in 0.2.0, deprecate `env_file =`
      (D3)

## Implemented in 0.2.0 (2026-11-13)

- [x] 1: `env_definition(path, format = NULL, ...)` with `format()` and
      `print()`, absolute path without `path_real()`, URLs abort, checked
      again at use
- [x] 2: no format list in condathis; the backend reports request, lock
      or NA
- [x] 3: optional hooks `backend_describe_definition()` and
      `backend_definition_formats()` with defaults; optional `definition`
      (create, install, can_solve) and `env_file` (install) through
      `backend_call()`; generics keep their 0.2.0 formals;
      `backend_s3_method()` wrappers for R CMD check
- [x] 4: micromamba content sniffing, refusals with reasons (`pixi.lock`,
      other conda-lock versions, other JSON, directories, unknown
      options), staging under a name micromamba reads, YAML rename hint,
      `categories` -> `--category`, lock platforms from package subdirs
- [x] 5: `create_env()` splits definitions out of `...`, describes before
      the environment lock, request path unchanged, lock never sent to
      `backend_can_solve()`
- [x] 6: lock platform: given, native, emulated, else
      `condathis_create_env_platform_not_locked`
- [x] 7: channel arguments abort with an `env_definition()` lock;
      deprecated `env_file =` keeps 0.1.4 behaviour (repair round)
- [x] 8: empty environment from a lock -> `condathis_create_env_failed`,
      old environment restored
- [x] 9: lock comparison in `create_env(overwrite = FALSE)` and
      `validate_env()` (new attribute `unexpected`)
- [x] 10: `install_packages(env_definition(<request>))` through
      `micromamba install -f`; a lock aborts with a `create_env()` hint
- [x] 11: `method = "auto"` skips a backend that refuses the file for a
      new environment; all refused -> one error naming each backend
- [x] 12: `env_file =` soft-deprecated (`condathis_deprecated_env_file_arg`,
      rules of `packages =`); file-name hint widened to
      `.yml/.yaml/.json/.lock` and pointing to `env_definition()`
- [x] 13: new condition classes, all in `?condathis-conditions`
- [x] 14: NEWS, help pages, two vignettes, `inst/extdata/README.md`,
      pkgdown index, WORDLIST
- [x] Review fixes: `env_file =` plus channels with a lock works again;
      `noarch` locks install on any platform; NEWS bug-fix entry narrowed
      to conda-lock (PLAN.md "Deviations" 4 to 6)
- [x] Test fixes: macOS `/private/var` path in `test-env_definition.R`;
      Windows skip removed from the symlink test (zero-skip rule)
- [x] Checks: Linux developer suite 8680 passed, 0 skipped; Docker
      R-devel, R 4.6.2 and R 4.3.3 `--as-cran` OK; Windows
      `--as-cran --no-manual` OK; macOS and Windows end-to-end probes OK
      (PLAN.md "Verification")

## Before submitting 0.2.0

- [x] 15: re-run the developer suite with the two test fixes on omicron
      (macOS) and kappa (Windows): 0 failures, 0 skips (2026-11-13:
      Linux 8680, macOS 8678, Windows 8639 passed; `--as-cran` Status OK
      on macOS and Windows)
- [ ] 16: build rattlerthis on a machine that can, and run its suite
      against this condathis
- [ ] 25: commit (maintainer): `git add` the new files
      `R/env_definition.R`, `R/env_definition_checks.R`,
      `R/backend-micromamba-definition.R`, `man/env_definition.Rd`,
      `tests/testthat/test-env_definition.R` and this folder, plus the
      modified files

## In rattlerthis

Also listed as `../post-0.2.0/` item 18 and
`../feat-backend-abstraction/TODO.md` decision 22.

- [ ] 17: quiet or move the `env_file =` calls in
      `test-parity-envfile.R:98` and `test-parity-linkscripts.R` (about
      line 320), which assert no warnings
- [ ] 18: opt in: `definition` argument, `backend_describe_definition()`
      around `rt_read_env_file()`, `backend_definition_formats()`
- [ ] 19: `pixi.lock` through `rattler_lock` (measure vendor size and
      MSRV first)

## Needs a decision

- [ ] 21: stages after the soft deprecation of `env_file =`, and when to
      remove it; keep the backend-level `env_file` until rattlerthis has
      moved
- [ ] 23: whether to stop passing CLI channels with a request file when
      `channels` was not given (YAML channels now come second)
- [ ] 22: a conda backend: pursue or drop

## Smaller open points (item 24)

- [ ] 24a: native platform for a lock can install micromamba before a
      `platform_not_locked` abort
- [ ] 24b: lock without platform data, or NA native platform: only the
      empty-environment check guards it
- [ ] 24c: reword "does not resolve symbolic links" in `?env_definition`
- [ ] 24d: optional hints (specs plus `env_file`; `create_env_exists` for
      a request file could name `install_packages(env_definition(...))`)
- [ ] 24e: CRAN-mode time, if it becomes a problem: stub matrices of
      `test-env_definition.R` behind `skip_on_cran()`
- [ ] 24f: watch the load-related failure of
      `test-download_micromamba_file.R:223`
- [ ] Not verified yet: raw micromamba with an `@EXPLICIT` file whose
      URLs use another platform's arch subdir; YAML channel order in
      `install_packages()` from a file; conda-lock files with pip items

## Out of scope, by decision

- 20: URLs in `env_definition()` (describe must never download; CRAN
  rules). They abort with a hint to download the file first.
