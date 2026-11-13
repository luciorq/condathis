# TODO: feat-strict-defaults

- [x] Drop bioconda from all default `channels` formals + format_channels_args fallback
- [x] Reorder all `channel_priority` formals to strict-first (9 call sites)
- [x] Update roxygen @param text (defaults + explicit-bioconda guidance)
- [x] Update default-assertion tests (format_channels_args, parse_strategy_channel_priority)
- [x] NEWS.md breaking-change bullets
- [x] Verify bioconda:: spec-prefix behavior empirically (dry-run probe)
- [x] roxygenize + lint + full test suite (verified 2026-09-17: roxygenise
      produces no diff, `just lint` passes, full suite runs in CI on all 5
      platforms at 6c57846)
- [x] CI green on stack layer 3 (r-cmd-check + pkgdown, 6c57846, 2026-09-07)
- [x] Stack merged into `main` (PRs #34, #35, #37, then #38)

Open items deferred past 0.2.0 are collected in `../post-0.2.0/`.

## 0.2.0 CRAN preparation (2026-11-12 and 2026-11-13)

Section numbers match "Addendum 2026-11-13" in `PLAN.md`.

- [x] 1: CRAN audit of `f582ba1` (9 auditors, 2 blockers, 26 should-fix)
- [x] 2a/2b: download message (`condathis_micromamba_downloading`) with
      the call-level verbose state (`local_call_verbose()`)
- [x] 2c: checksum-unavailable warning at every level but `"silent"`
- [x] 2d: `certutil` SHA256 fallback on Windows (checked on kappa)
- [x] 2e: `micromamba_default_version` constant, tested against the
      `install_micromamba()` default
- [x] 2f: Windows `PATH` de-duplication (`prepend_path_dirs()`,
      `path_entry_key()`), checked on kappa
- [x] 2g: libmamba `~/.mamba/pkgs` workaround and its test file removed
- [x] 2h: `stats::setNames()` -> `rlang::set_names()`
- [x] 3: CRAN-mode skips, offline skips, setup deleter off CRAN,
      `PATHEXT` test on every OS, `testthat (>= 3.2.1)`
- [x] 3: developer-run fixes (SIGINT probe, `/tmp/Rtmp*`, `uv-*.lock`,
      macOS crash report, UTF-8 pip guard)
- [x] 4: `DESCRIPTION` wording without "backend", `NEWS.md` starts at
      0.2.0, `inst/extdata/README.md`, `justfile` recipes, CI R 4.3 job
- [x] 4: docs sweep (77 findings, 9 refuted), README re-rendered,
      `man/` regenerated, `cran-comments.md` rewritten
- [x] 5a: positional `env_name` guard only for two or more unnamed
      arguments (`positional_env_name_possible()`)
- [x] 5b: soft deprecation (`is_direct_use()`,
      `condathis_deprecate_soft()`)
- [x] 5c: `install_packages(packages = NULL)` is a no-op with status 0
- [x] 5d: `method = c("native", "auto")` accepted
- [x] 5e: `method = "native"` soft and warn-once in the six functions
      that take `user_env`
- [x] 5f: hints for 0.1.4 shapes (abbreviations of `packages` abort)
- [x] 5g: bioconda default-channel hint
- [x] 5h: `__` virtual specs skipped in the satisfaction check
- [x] 5i/5j: "installed from another channel" message, `pypi` rows
      excluded
- [x] 5k: Windows absolute command path with backslashes
- [ ] 6: optional compatibility items, moved to `../post-0.2.0/` item 17
- [x] 7: `env_definition()` implemented (see `../feat-env-file/`)
- [x] 8: rounds 3 and 4 on Linux, Docker (R-devel, 4.6.2, 4.3.3,
      offline), macOS and Windows
- [x] 8: round 5 (the two `test-env_definition.R` fixes) on Linux,
      macOS and Windows: 0 failures, 0 skips

### Release steps (maintainer, PLAN.md section 9)

- [ ] 9.1: commit the `env_definition()` work (five untracked files,
      plus `.github/devdocs/feat-env-file/`), push, wait for GitHub
      Actions
- [x] 9.2: Windows result of `test-env_definition.R` confirmed (round 5,
      2026-11-13)
- [ ] 9.3: (recommended) build and test rattlerthis against this tree
- [ ] 9.4: add a license to the upstream `polyglot` repository
- [ ] 9.5: `just check-win-devel` and `just check-win-release`; update
      "Test environments" in `cran-comments.md`
- [ ] 9.6: `devtools::submit_cran()` and confirm the email, before
      2026-12-22 (CRAN break until 2027-01-07)
- [ ] 9.7: after acceptance, `just git-tag`, push tags,
      `just release-github`; optional NEWS release date and changelog
      link
- [ ] 9.8: `usethis::use_dev_version()`, push, Zenodo, close issue #12
