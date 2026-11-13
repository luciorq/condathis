# Session handoff prompt

Copy the block below into a new Claude Code session to continue this work.
Written 2026-11-13. It replaces the prompt of 2026-09-17, whose first
two steps (mark the stacked PRs ready, merge the stack) are done.
The "re-orient" step exists because this file goes stale.

---

Continue work on the R package `condathis` (~/projects/condathis, branch
`main`).

## Context

condathis 0.2.0 is prepared for CRAN, which has 0.1.4 (2026-06-19).
The stacked PRs #34, #35 and #37 and PR #38 are merged.
The maintainer committed the CRAN preparation as `8cffc25`.
After that, `env_definition()` was added and `env_file =`
soft-deprecated; that work is not committed yet. It includes five
untracked files: `R/env_definition.R`, `R/env_definition_checks.R`,
`R/backend-micromamba-definition.R`, `man/env_definition.Rd` and
`tests/testthat/test-env_definition.R`.

Read first:

- `.github/devdocs/feat-strict-defaults/PLAN.md`, "Addendum 2026-11-13":
  the audit, every fix, the `packages =` compatibility decisions, the
  verification matrix and the release steps.
- `.github/devdocs/feat-env-file/PLAN.md`: `env_definition()`.
- `.github/devdocs/post-0.2.0/PLAN.md`: everything that is open after
  the release.

Done (don't redo): the CRAN audit and its fixes, the docs sweep, the
`packages =` compatibility fixes, `env_definition()`, and
`R CMD check --as-cran` with Status OK on Linux, R-devel, R 4.6.2,
R 4.3.3, offline, macOS (omicron) and Windows (kappa). The NOTE "unable
to verify current time" on some hosts comes from the host (it goes away
with `_R_CHECK_SYSTEM_CLOCK_=0`).

## First: re-orient

Run `git status`, `git log --oneline -5` and `gh run list --limit 5`.
Check whether the `env_definition()` work is committed and whether CI
is green on it, and whether `CRAN-SUBMISSION` exists (then the package
was submitted).

## Pending work, in priority order

1. **v0.2.0 release sequence** (PLAN.md, addendum section 9). The
   maintainer does the outward-facing steps; prepare and verify only.
   1. The `env_definition()` work is committed and CI is green.
   2. Done 2026-11-13: the last re-run passed on Linux, macOS and
      Windows with 0 failures and 0 skips. Re-run only if package
      files change before submitting.
   3. Recommended: rattlerthis built and tested against this tree on a
      machine with a Rust toolchain. Expect `test-parity-envfile.R:98`
      and `test-parity-linkscripts.R` to see the `env_file =`
      deprecation warning; the fix belongs in rattlerthis (post-0.2.0
      item 18).
   4. A license in the upstream `polyglot` repository
      (post-0.2.0 item 19).
   5. `just check-win-devel` and `just check-win-release`, then their
      results in "Test environments" of `cran-comments.md`.
   6. `devtools::submit_cran()` and the confirmation email. CRAN takes
      no submissions from 2026-12-22 to 2027-01-07.
   7. After acceptance: `just git-tag` (tags the SHA in
      `CRAN-SUBMISSION`), push the tags, `just release-github`.
      Optionally add "Release Date:" and the `v0.1.4...v0.2.0`
      changelog link to the 0.2.0 NEWS section once the tag exists
      (before that, `urlchecker::url_check()` reports a 404).
   8. `usethis::use_dev_version()`, push, Zenodo, close issue #12.
2. **After the release**: follow "Suggested ordering" in
   `.github/devdocs/post-0.2.0/PLAN.md`. The Windows MinGW runtime pins
   (item 7), the jarl baseline (item 8, fix findings, do not add
   `# jarl-ignore` without asking) and the `run()` convergence (items 6
   and 1) are still open.

## Conventions

- `just lint` must pass (air + jarl informational + hard-failing
  non-ASCII check over `R/`, `tests/`, `man/`, `vignettes/`,
  `DESCRIPTION`, `NAMESPACE`, `NEWS.md`, `README.md` and `README.qmd`;
  plain `-` only, no em dashes). It reformats files, so run it on
  purpose: no other recipe runs it.
- The `NOT_CRAN=true devtools::test()` full suite is the gate before
  declaring anything done: 0 failures and 0 skips on Linux, macOS and
  Windows, apart from tests for another operating system.
- Run checks and long test runs on a copy of the tree, in the
  background, with R in the foreground of its own shell (an R started
  with `&` ignores SIGINT), in a UTF-8 locale, and with `HOME` and
  `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`
  in temporary directories (`.github/AGENTS.md`, "Testing rules").
- On omicron (macOS), set `CONDATHIS_MICROMAMBA_PATH` to an installed
  micromamba: its firewall holds freshly downloaded binaries. On kappa
  (Windows), put Quarto's pandoc on `PATH` and use an R without rig's
  `R_LIBS_USER` block in `Rprofile`, or the check gets two host NOTEs.
- The user commits and pushes themselves (GPG signing) - prepare changes
  and stop; never commit unless told to.
- Commit style: `type: lowercase description`.
- `NEWS.md` is user facing: replace superseded unreleased lines instead
  of stacking new ones.
- condathis's `DESCRIPTION` never names rattlerthis.
- All fixes must behave identically on Linux/macOS/Windows.
- Test-writing rules learned the hard way:
  - Build PATH fixtures with `.Platform$path.sep`.
  - Never assert a downstream stage's exact exit status after a pipeline kill
    (EOF-exit vs kill is a platform-dependent race).
  - Give pipeline-timeout tests generous budgets
    (the deadline clock starts at run_pipeline() entry, before spawning).
  - Compare paths against `getwd()` after `withr::local_dir()`: on macOS
    `tempdir()` is under `/var`, a symlink to `/private/var`.
  - New tests must not skip on any OS without a reason that holds there.
- micromamba >= 2.9 may answer instead of the pinned internal binary
  (discovery chain).
  Its JSON shapes differ, so both must stay supported.
- Watch local disk space: repeated test-env creation once filled / and
  corrupted test envs (an env dir without conda-meta/ is a corpse from
  that incident - delete it).
