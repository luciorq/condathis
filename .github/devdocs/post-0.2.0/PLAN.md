# Post-0.2.0 roadmap: open items across the stacked PRs

Written 2026-09-17, from an audit of every `.github/devdocs/*/TODO.md` and
`PLAN.md` on the stack (`feat-pipeline` -> `feat-backend-abstraction` ->
`feat-strict-defaults`), the in-code `TODO: @luciorq` comments, the
`just lint` (jarl) baseline, and the current state of the sibling
`rattlerthis` checkout (`~/projects/rattlerthis`, `main` at `297c6ba`).

Purpose: one place that lists what is genuinely still open once PRs #34,
#35 and #37 are merged, why each item was deferred, and a concrete
implementation plan for each. Nothing here blocks the v0.2.0 release
(see `feat-strict-defaults/HANDOFF.md` for that sequence). Each item below
says which branch's devdoc it came from so the original reasoning can be
found.

Stale bookkeeping fixed in the same pass: three items in
`feat-backend-abstraction/TODO.md`'s "rattlerthis as a conforming backend"
milestone were still unchecked although the work had landed (the vtable is
populated, `.onLoad()` registration exists in `rattlerthis`, and the
execution path landed in `condathis` on 2026-08-13). They are now ticked
there with a pointer to this file.

## Status summary

| # | Item | Origin | State | Needs a decision? |
|---|------|--------|-------|-------------------|
| 0 | 0.1.4 GitHub release + two uncommitted CRAN tarball edits | CRAN tarball audit | tag exists, release and edits missing | no |
| 1 | `run()` convergence onto resolve-once + direct spawn | feat-pipeline, feat-strict-defaults | designed, not started | yes: hook semantics |
| 2 | `rattlerthis` end-to-end smoke test via `condathis` | feat-backend-abstraction, rattlerthis | partially verified | no |
| 3 | `list_packages()` cross-backend column schema | rattlerthis "flag upward" | decided (minimal subset), unflagged | maybe: coercion |
| 4 | README cross-links between the two packages | both | not started | no |
| 5 | Package-wide supervisor escape hatch | feat-pipeline | not decided | yes: option vs env var |
| 6 | Nested-activation artifacts in `get_micromamba_activation_envvars()` | feat-pipeline | known limitation | no, needs investigation |
| 7 | Windows MinGW runtime pins in tests | HANDOFF | waiting on conda-forge | no |
| 8 | jarl lint baseline (30 findings) | HANDOFF | decided: fix, do not suppress | no |
| 9 | In-code `TODO: @luciorq` comments (3) | code | open | one: env_file + packages mixing |
| 10 | `backend_status()` diagnostics | feat-backend-abstraction "later ideas" | idea | no |
| 11 | Container backend package | feat-backend-abstraction "later ideas" | idea | yes: whether at all |
| 12 | `verbose` on `run_pipeline()` | feat-pipeline "intentional divergences" | explicitly not planned | no |

## 0. Before 0.2.0: the 0.1.4 release was never recorded on GitHub

Found 2026-09-17. The `v0.1.4` git tag exists locally and on `origin`,
annotated "Version 0.1.4 released", pointing at `6074b46` ("chore: prepare
for v1.4.0 release", a typo for 0.1.4), which is also `origin/main`'s
HEAD. What is missing is the GitHub Release object: `gh release list`
stops at `condathis 0.1.3` (2025-11-08). The NEWS.md 0.1.4 section and
its `v0.1.3...v0.1.4` changelog link are already in place.

Comparing the published CRAN tarball (`condathis_0.1.4.tar.gz`,
`Date/Publication: 2026-06-19 22:10:02 UTC`) against the tag shows the
tarball was built from a working tree with two uncommitted edits that
exist in no commit on any branch, and are therefore also missing from
the 0.2.0 stack:

- `R/get_micromamba_version.R`: `parse_output(px_res)` became
  `parse_output(px_res, stream = "both")`. Every branch still has the
  one-argument form. **Not relevant** (checked 2026-09-18): the
  `processx::run()` call discards stderr (`stderr = NULL`, so
  `res$stderr` is `NULL`) and `parse_output()`'s `"both"` branch then
  reduces to stdout alone. No behaviour difference; the current branch
  detects the version correctly and CI is green on all platforms.
- `tests/testthat/test-satisfy_dependencies.R`: the
  "returns correct results" test gained `testthat::skip_if_offline()` and
  `testthat::skip_on_cran()`. It is the only test file on the stack that
  calls `create_env()` without `skip_on_cran()`, so as it stands 0.2.0
  would ship a network-and-conda-dependent test to CRAN that 0.1.4 did
  not.
- `inst/extdata/polyglot.cmd`: a stray, unreferenced Linux/Windows
  polyglot script that was sitting in the working tree and got packaged.
  Not in git, not ignored, referenced by nothing. Harmless, should not be
  re-added.

`CRAN-SUBMISSION` is in `.Rbuildignore` but was never committed, so
there is no recorded SHA for the submission.

**Plan.**

1. (Done 2026-09-18: https://github.com/luciorq/condathis/releases/tag/v0.1.4,
   `created_at` = tag date 2026-06-19, `published_at` = 2026-09-18.)
   Create the missing GitHub Release from the existing tag, without
   moving the tag: `gh release create v0.1.4 --title "condathis 0.1.4"
   --notes-file <(NEWS 0.1.4 section)` or `just release-github` from a
   checkout of `v0.1.4`. `usethis::use_github_release()` reads the version
   from DESCRIPTION, so it must run from the tag checkout, not from the
   0.2.0 dev tree.
2. (Done 2026-09-18, both edits applied to `feat-strict-defaults`, files
   now byte-identical to the tarball; the author chose to port the no-op
   too so sources match CRAN.) Port the `skip_if_offline()` + `skip_on_cran()` edit to
   `test-satisfy_dependencies.R` onto `feat-strict-defaults` (or `main`
   right after the merge). Tests ship in the tarball (`^tests` is not in
   `.Rbuildignore`), `setup.R` has no global CRAN skip, and that test
   creates a `python` + `numpy` environment over the network. The
   `stream = "both"` edit is a no-op and is not worth porting.
3. Add `CRAN-SUBMISSION` handling to the release sequence: commit it (or
   at least note the SHA in the release notes) so the next release leaves
   a record.
4. Fix the `git-tag` recipe's message typo risk: the commit message
   "prepare for v1.4.0" was hand-typed; the recipe itself reads the
   version from DESCRIPTION and is fine.

## 1. Converge `run()` onto the resolve-once + direct-spawn model

**Origin.** `feat-pipeline/PLAN.md` "Known, intentional divergences",
`feat-pipeline/TODO.md` "Remaining / Optional",
`feat-strict-defaults/PLAN.md` "North star", and the roxygen header of
`R/get_micromamba_activation_envvars.R` (lines 33-40).

**Where things stand.** `run_bin()` and `run_pipeline()` both resolve the
environment's activation variables once per `env_name` (cached, invalidated
on `conda-meta` changes) and spawn the binary directly with
`env = c("current", <vars>)`. `run()` still wraps the command in
`micromamba run -n <env> <cmd>`, so it re-runs `activate.d` hooks on every
call, relies on micromamba's activated `PATH` to find the binary, and has
no `activate` argument. Everything else already converged: the
`condathis_result` shape, `error`/`timeout`/`binary`/`stdin`+`input`
semantics, the `-9` timeout sentinel, `build_child_env()`, shared deadline
enforcement and the concurrent stream pump.

**Why it was deferred.** Changing `run()` alters observable hook semantics
(hooks run once at resolve time instead of on every call) and how the
binary is found. It was explicitly scoped out of 0.2.0 twice ("before
trying to modify `run()`" in feat-pipeline; "deferred past 0.2.0 because
it changes observable hook semantics" in feat-strict-defaults).

**Decision needed before starting.**

- Hook semantics: accept that `activate.d` hooks run once per cached
  activation snapshot rather than per call. This is what `run_bin()` and
  `run_pipeline()` already do, so the decision is really "make `run()`
  match" rather than a new behaviour. Recommended: yes, and say so in
  NEWS as a breaking (minor) change.
- Binary resolution: `run()` today finds `cmd` on micromamba's activated
  `PATH`; `run_bin()` uses `resolve_env_bin_path()` with a bare-name
  fallback. Recommended: `run()` adopts `backend_resolve_run()` exactly
  like `run_pipeline()` already does, so all three share one resolver.

**Implementation plan.**

1. Add `activate = TRUE` to `run()`, mirroring `run_bin()`'s signature and
   docs. `activate = FALSE` runs with no activation overlay.
2. Replace the `micromamba run -n` wrapping in `run_internal_native()` with
   a call to `backend_resolve_run()` on the resolved backend, then spawn
   through `execute_command()` with `env = c("current", res$env)`. This is
   the same path `run_internal_backend()` already takes, so the expected
   outcome is that `run_internal_native()` collapses into
   `run_internal_backend()` and the "micromamba" backend stops being a
   special case in `run()`.
3. Keep `verbose = "cmd"` output honest: the echoed command must now show
   the resolved binary path, not a `micromamba run` invocation. Check
   `parse_strategy_verbose()` consumers and the `cmd` field of the result.
4. Audit `run()` callers inside the package (`packages_search_native()`,
   `install_micromamba()` helpers, `check_micromamba_version()`) for any
   that depend on `micromamba run` specifically. Those that call micromamba
   itself should go through `native_cmd()`, not `run()`.
5. Tests: reuse `test-run_bin.R`'s `run_bin(activate = TRUE)` vs `run()`
   equivalence tests and invert them (they become tautological once both
   share a path, so replace with tests that pin the resolved `cmd` path,
   `CONDA_PREFIX`, and `activate = FALSE`). Add a regression test that
   `run()` on a missing env still errors with the existing condition class.
6. NEWS: one "Breaking (minor)" bullet under the next release explaining
   the hook and lookup change, plus the new `activate` argument.
7. Update `R/get_micromamba_activation_envvars.R`'s header (lines 33-40)
   to stop describing itself as "not wired into `run()`".

**Prerequisite.** Item 6 (nested-activation artifacts) should be
understood first, because `run()` is the most-used entry point and the
cached snapshot would expose that limitation to every user running R from
inside a conda or pixi environment.

## 2. `rattlerthis` end-to-end smoke test through `condathis`

**Origin.** `feat-backend-abstraction/TODO.md` milestone "rattlerthis as a
conforming backend"; `rattlerthis/.github/devdocs/feat-rattlerthis-backend/TODO.md`.

**Where things stand.** The condathis side is complete: `register_backend()`
accepts a plain vtable, all 10 generics dispatch, and `run()`/`run_bin()`/
`run_pipeline()` execute through any backend. On the rattlerthis side,
`new_backend_rattler()` now returns the full 10-entry vtable and
`.onLoad()` registers it directly and via `setHook(packageEvent("condathis",
"onLoad"))`, with `.onUnload()` unregistering. `condathis`'s execution
path was verified against a hand-built rattlerthis prefix (activation vars
reach the child, timeout, error modes, writable stdin). What is still
unexercised is the `create_env(method = "rattler")` half: a real solve and
install through condathis's public API, followed by `run()`.

**Implementation plan.**

1. In `rattlerthis/tests/testthat/test-condathis-backend.R`, add one
   `skip_if_not_installed("condathis")` + `skip_on_cran()` +
   `skip_if_offline()` test: `condathis::create_env("python", env_name =
   "rt-smoke", method = "rattler")`, then `condathis::run("python", "-c",
   "import sys; print(sys.prefix)", env_name = "rt-smoke")`, assert the
   printed prefix equals `condathis::get_env_dir("rt-smoke")$path` (or the
   rattler-side equivalent) and that `.condathis/backend.json` in that
   prefix says `"rattler"`. Then `remove_env()` and assert
   `env_exists()` is `FALSE`.
2. Ownership stays in rattlerthis (condathis CI must not need a Rust
   toolchain). condathis's own `test-backend.R` keeps its in-tree fake
   backend.
3. Also exercise the mismatch path once for real: `install_packages(...,
   env_name = "rt-smoke", method = "micromamba")` must abort with
   `condathis_backend_mismatch`.
4. After this passes, mark the milestone done in both packages' devdocs.

## 3. `list_packages()` cross-backend column schema

**Origin.** rattlerthis TODO "Flag the `list_packages()` column-schema
mismatch ... to whoever picks up `condathis`'s `backend_list_packages()`
dispatch".

**Where things stand.** condathis already made the decision on 2026-07-29:
only `name`, `version`, `build_number`, `channel` are guaranteed across
backends, no coercion in the dispatch layer, and the micromamba backend
keeps its full schema. `rattlerthis::backend_list_packages()` is a plain
pass-through to its own `list_packages()`, which uses `build` where
micromamba uses `build_string`. The rattlerthis TODO item is therefore
already answered but nobody told it.

**Implementation plan.**

1. Close the rattlerthis TODO item with a pointer to
   `feat-backend-abstraction/TODO.md`'s "list_packages() schema" note.
2. Optional hardening in condathis: have the public `list_packages()`
   wrapper assert the four guaranteed columns are present after dispatch
   and abort with a `condathis_backend_contract_violation` naming the
   backend if not. Cheap, and turns a silent schema drift into a named
   error the way `validate_resolve_run()` already does for the run
   contract.
3. Open question, low priority: whether to reorder columns so the four
   guaranteed ones always come first. Cosmetic, no decision needed now.

## 4. README cross-links between `condathis` and `rattlerthis`

**Origin.** Both packages' TODOs.

**Where things stand.** `rattlerthis/README.md` already links to condathis
and describes the difference (micromamba binary vs in-process). condathis's
README does not mention rattlerthis, and NEWS only mentions it as a
hypothetical.

**Implementation plan.** After item 2 passes: add a short "Alternative
backends" section to `README.qmd` (rebuilt via `just build-readme`) that
names `rattlerthis`, shows `options(condathis.backend_priority = "rattler")`
and `create_env(..., method = "rattler")`, and links to
`?register_backend` for authors. Keep it explicitly experimental, matching
the `register_backend()` lifecycle text.

## 5. Package-wide supervisor escape hatch

**Origin.** `feat-pipeline/PLAN.md` "Possible follow-up, not yet decided
or implemented"; the only unchecked box in `feat-pipeline/TODO.md`.

**Where things stand.** `supervise` is a per-call argument. Defaults are
`FALSE` on `run()`/`run_bin()` and `TRUE` on `run_pipeline()`, except that
`run_pipeline()` forces it off on Windows (`effective_supervise`, around
`R/run_pipeline.R:213`) because of the antivirus-driven hang. A user who
wants it off everywhere must pass it on every call. Upstream processx's
"Process cleanup" vignette suggests a general escape hatch.

**Decision needed.** Naming and precedence. Recommended:
`getOption("condathis.supervise", default = NULL)`, where `NULL` means "use
each function's own default", `FALSE` forces off, `TRUE` forces on except
on Windows for `run_pipeline()` where the platform gate still wins. An env
var `CONDATHIS_SUPERVISE` is only worth adding if there is a real need to
set this outside R (CI); options are the established pattern in this
package (`condathis.backend_priority`).

**Implementation plan.**

1. One internal helper `resolve_supervise(arg, fn_default)` used by all
   three run functions, so precedence lives in one place: explicit
   argument if the caller supplied it (detect via `missing()`), else the
   option, else the function default, then the Windows pipeline gate.
2. Document the option in each `@param supervise` and in a package-level
   "Options" section of `?condathis`.
3. Tests: option unset, `FALSE`, `TRUE`, explicit argument overriding the
   option, Windows gate still applied (mock `is_windows()`).
4. NEWS bullet under "New features".

## 6. Nested-activation artifacts in `get_micromamba_activation_envvars()`

**Origin.** `feat-pipeline/TODO.md` "Known limitation, not yet resolved".

**Where things stand.** When R itself runs from inside an activated conda
or pixi environment, the diff between the clean baseline and the
`micromamba run` dump can pick up `CONDA_PREFIX_1`, `CONDA_SHLVL > 1` and
similar host-stack artifacts. Today this only affects `run_bin(activate =
TRUE)` and `run_pipeline(activate = TRUE)`. Item 1 would extend it to
`run()`.

**Implementation plan.**

1. Reproduce deliberately: run the test suite from a pixi shell (this
   machine's R is pixi-provided, so this is the natural case) and capture
   the resolved vector for a known env.
2. Decide per variable: `CONDA_SHLVL` should be forced to `"1"`,
   `CONDA_PREFIX_<n>` and `CONDA_DEFAULT_ENV`-style stack entries dropped,
   `PATH` filtered so that only the target prefix's entries are prepended
   to the child's inherited `PATH` (the current behaviour of overlaying the
   full dumped `PATH` is what leaks the host prefix).
3. Add these to the existing noise filter list with a comment per entry,
   and a test that constructs a fake nested baseline and asserts they are
   stripped.
4. Only then proceed with item 1.

## 7. Windows MinGW runtime pins in the test helper

**Origin.** HANDOFF item 2; `tests/testthat/helper-cli-tools.R` lines
12-40.

**Where things stand.** `test_r_base_pkgs()` pins `libgcc=16.1.0=h110b43a_1`
and `libgfortran5=16.1.0=h94075d5_1` on Windows because conda-forge's
`_2`/`_3` rebuilds of 2026-08-19/21 crash every MinGW binary at startup.
No upstream issue was filed.

**Implementation plan.**

1. Check anaconda.org / conda-forge feedstock for a `_4` or newer batch of
   `libgcc`/`libgfortran5`/`libgomp` for win-64.
2. Drop the pins on a throwaway branch and run the Windows CI job. If
   green, remove the pins and the explanatory comment block. If red, keep
   the pins and file the upstream report (draft it from the bisection
   evidence already in the comment).
3. Independent of the pins, `tests/testthat/test-check_micromamba_version.R:48`
   still mocks `"2.8.1"`, which is now equal to the pinned internal
   version rather than "newer". Bump the mocked version when the internal
   binary moves past 2.8.1 (item 9c).

## 8. jarl lint baseline

**Origin.** HANDOFF item 3. Decision already made by the author: fix
genuine findings, do not add `# jarl-ignore` comments without asking.

**Current findings (30, all warnings, `jarl check . --select ALL`).**

Package code (7), all worth fixing for real:

- `R/download_micromamba_file.R:29` unused `dl_success`.
- `R/rethrow_error_cmd.R:40` unused `status_code`.
- `R/parse_match_spec.R:213,219,297` and `R/parse_output.R:78,79`
  `if_not_else`: swap branches and drop the negation.

Test code (23): unused objects in `test-install_micromamba.R` (6),
`test-rethrow_error.R` (8), `test-with_sandbox_dir.R` (3),
`test-create_nested_env.R` (2), `test-compute_sha256.R`, `test-run_bin.R`
(1 each), and two empty trailing arguments in `test-run_output_file.R:41,60`.
Most of the unused objects are results captured and never asserted on, so
the right fix is usually to add the missing assertion, not to delete the
assignment. `test-rethrow_error.R` also carries an in-code "Improve tests"
TODO (item 9b), so do those together.

Not in scope: the 403 `lintr::lint_package()` findings (168 line length,
168 explicit return, 27 commented code, 24 object-usage false positives).
The project does not run lintr in CI or `just lint`; jarl, styler and air
are the gates.

## 9. In-code `TODO: @luciorq` comments

- a. `R/create_env.R:121`: mixing `env_file` and `packages` is allowed
  by conda but condathis's `resolve_create_env_packages_arg()` ignores
  `packages` whenever `env_file` is set. Needs a decision: either pass both
  (`-f file pkg1 pkg2`, which micromamba accepts) and add tests plus docs,
  or abort with a clear message when both are supplied. Recommended: pass
  both, since the comment says this was the intent since 0.1.3-dev.
- b. `tests/testthat/test-rethrow_error.R:68`: "Improve tests". Fold into
  item 8's unused-object cleanup for that file.
- c. `tests/testthat/test-check_micromamba_version.R:48`: bump the mocked
  version above the internal pin whenever `check_micromamba_version()`'s
  `target_version` (currently `"2.8.1"`) changes.

## 10. `backend_status()` diagnostics

**Origin.** `feat-backend-abstraction/TODO.md` "Later ideas".

A user-facing function returning one row per registered backend with
`backend`, `available` (from `backend_available()`), and `install_dir`.
Small and self-contained. Sensible to ship together with item 4 so the
README can show it. `rattlerthis`'s own later-ideas list notes its
`backend_available()` is unconditionally `TRUE`, which is fine for this.

## 11. Container backend package

**Origin.** `feat-backend-abstraction/PLAN.md` decision 9, TODO "Later
ideas".

Design is sketched (image per `env_name`, `backend_get_env_dir()` as a
bind-mount path, `backend_resolve_run()` translating to `docker run` /
`singularity exec`, `backend_available()` probing the daemon). No package
exists and none is planned. Decision needed on whether to pursue it at
all; nothing in condathis needs to change first, which was the point of
the "resolve, don't execute" contract.

## 12. `verbose` on `run_pipeline()`: explicitly not planned

Recorded so nobody reopens it by accident. Interleaving live output from N
concurrent processes is a different problem from `processx::run()`'s
single-process polling and was ruled a structural divergence, not a parity
gap. If it is ever wanted, `pump_pipeline_io()` is now the single place
that already polls every stage, so a `verbose = "output"` that echoes
stdout chunks as they arrive would be the minimal version.

## Suggested ordering after the 0.2.0 release

1. Item 8 + 9b + 9c (lint cleanup, mechanical, low risk) as one small PR.
2. Item 7 (Windows pins) whenever conda-forge ships a fix; independent.
3. Item 2, then 3, then 4 and 10 together (the rattlerthis integration
   becomes real and documented).
4. Item 5 (supervisor option) as its own small PR.
5. Item 6, then item 1 (the `run()` convergence) as the headline of the
   next minor release.
6. Item 9a (env_file + packages) can slot in anywhere; it touches
   `create_env()` docs and tests only.
