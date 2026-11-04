# Session handoff prompt

Copy the block below into a new Claude Code session to continue this work.
Written 2026-09-17.
The "re-orient" step exists because this file goes stale.

---

Continue work on the R package `condathis` (~/projects/condathis, branch
`feat-strict-defaults`).

## Context

Three-layer GitHub stacked PR (Stack #36, via `gh stack`): PR #34
(`feat-pipeline` -> `main`), PR #35 (`feat-backend-abstraction` ->
`feat-pipeline`), PR #37 (`feat-strict-defaults` ->
`feat-backend-abstraction`).
All layers were CI-green on all 5 platforms as of the last push.
Version in DESCRIPTION is a 0.2.0.90xx dev version.
The goal is a v0.2.0 CRAN release.

Completed on this stack (don't redo):

- Pluggable backend system + exported experimental extension API
  (`register_backend()` etc.).
- Strict defaults (conda-forge-only channels, `channel_priority = "strict"`).
- Explicit child-env construction (`build_child_env()`, no session mutation).
- Concurrent pipeline stream pump (`pump_pipeline_io()`, fixed a real
  deadlock).
- All 18 findings from a /code-review remediated with regression tests.
- micromamba 2.9 `list --json` format compat (`{log_history,
  packages}` vs bare array).
- Windows finalized-handle race tolerance
  (`wait_process_safely()`/`exit_status_safely()`, commit 6c57846).

NEWS.md documents all of it under 0.2.0.

## First: re-orient

Run `git log --oneline -10`, `gh stack view`, `gh run list --limit 5` and
confirm the stack and CI state before doing anything - commits may have
landed since this prompt was written.

## Pending work, in priority order

1. **v0.2.0 release sequence** (the main goal):
   1. Mark PRs #34/#35/#37 ready-for-review.
   2. Merge the stack (merging #37 lands all layers, or bottom-up with
      retarget).
   3. On `main`: DESCRIPTION -> 0.2.0, NEWS.md header -> release + changelog
      link (v0.1.4...v0.2.0).
   4. Tag BEFORE `urlchecker::url_check()` (the justfile pre-release recipe
      documents this ordering trap).
   5. Run `devtools::check(remote = TRUE, manual = TRUE)` +
      `check_win_devel()`.
   6. Update cran-comments.md (mention the \dontrun{} rationale: examples need
      network + conda installs).
   7. Run `devtools::submit_cran()`.
   8. On acceptance, run `just release-github`.
2. **Windows runtime pins**: `tests/testthat/helper-cli-tools.R`
   `test_r_base_pkgs()` pins `libgcc=16.1.0=h110b43a_1` +
   `libgfortran5=16.1.0=h94075d5_1` on Windows because conda-forge's
   win-64 MinGW runtime rebuilds of 2026-08-19/21 (`_2`/`_3` builds) crash
   all MinGW binaries at startup ("stack smashing detected", 0xC0000409).
   Check anaconda.org for a newer fixed batch and remove the pins if safe.
   The upstream conda-forge report was never filed - offer to draft it.
3. **jarl lint baseline**: `just lint` shows ~30 pre-existing findings from
   a jarl upgrade.
   The user explicitly decided NOT to add `# jarl-ignore`
   comments yet.
   Genuine style findings (if_not_else in
   parse_match_spec.R/parse_output.R, unused `dl_success` in
   download_micromamba_file.R, condition_call) can be fixed for real.
   Ask before any suppression comments.
4. **Deferred post-0.2.0** (documented in
   .github/devdocs/feat-strict-defaults/PLAN.md): converge
   run()/run_bin()/run_pipeline() to one argument set and activation model
   (run() onto resolve-once + direct spawn); rattlerthis backend wiring.

## Conventions

- `just lint` must pass (styler + air + jarl informational + hard-failing
  non-ASCII check - plain `-` only, no em dashes).
- The `NOT_CRAN=true devtools::test()` full suite is the gate before declaring
  anything done.
- Run long test runs in the background.
- The user commits and pushes themselves (GPG signing) - prepare changes
  and stop; never commit unless told to.
- Commit style: `type: lowercase description`.
- All fixes must behave identically on Linux/macOS/Windows.
- Test-writing rules learned the hard way:
  - Build PATH fixtures with `.Platform$path.sep`.
  - Never assert a downstream stage's exact exit status after a pipeline kill
    (EOF-exit vs kill is a platform-dependent race).
  - Give pipeline-timeout tests generous budgets
    (the deadline clock starts at run_pipeline() entry, before spawning).
- micromamba >= 2.9 may answer instead of the pinned internal binary
  (discovery chain).
  Its JSON shapes differ, so both must stay supported.
- Watch local disk space: repeated test-env creation once filled / and
  corrupted test envs (an env dir without conda-meta/ is a corpse from
  that incident - delete it).
