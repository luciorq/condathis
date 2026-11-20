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

Updated 2026-11-13, after the 0.2.0 CRAN preparation of 2026-11-12 and
2026-11-13 (`feat-strict-defaults/PLAN.md`, "Addendum 2026-11-13") and
the `env_definition()` work (`feat-env-file/PLAN.md`). Items 0, 4, 9a,
14 and 15 are updated in place, each with the date. Items 17 to 20 are
new. Follow-ups of `env_definition()` itself are in
`feat-env-file/TODO.md`; only the ones that live in rattlerthis are
repeated here (item 18).

Updated 2026-11-16, after the run-family unification
(`../feat-run-unify/`), done in 0.2.0 at the maintainer's request. Items
1 and 6 are marked done in place. Item 21 is new: the follow-ups of that
work.

Updated 2026-11-18, after the items survey of round 8 of the run-family
work (each finding checked by a second reviewer). Fixed in 0.2.0: 9b,
9c, 17b to 17f, 20a, 20b and 20e (17f and 20a are decision D19 of
`../feat-run-unify/`). Found done and ticked: 2, 3 (the rattlerthis
side), 4, 18a and 18b. Updated in place: 7, 13 and 17a. The rest stays
deferred: it needs a maintainer decision, a Windows or win-builder run,
or new API.

Stale bookkeeping fixed in the same pass: three items in
`feat-backend-abstraction/TODO.md`'s "rattlerthis as a conforming backend"
milestone were still unchecked although the work had landed (the vtable is
populated, `.onLoad()` registration exists in `rattlerthis`, and the
execution path landed in `condathis` on 2026-08-13). They are now ticked
there with a pointer to this file.

## Status summary

| # | Item | Origin | State | Needs a decision? |
|---|------|--------|-------|-------------------|
| 0 | 0.1.4 GitHub release + two uncommitted CRAN tarball edits | CRAN tarball audit | done; `CRAN-SUBMISSION` handled by `just git-tag` (2026-11-13) | no |
| 1 | `run()` convergence onto resolve-once + direct spawn | feat-pipeline, feat-strict-defaults | done in 0.2.0 (2026-11-16, `../feat-run-unify/`) | no |
| 2 | `rattlerthis` end-to-end smoke test via `condathis` | feat-backend-abstraction, rattlerthis | done: rattlerthis's conformance suite (checked 2026-11-18) | no |
| 3 | `list_packages()` cross-backend column schema | rattlerthis "flag upward" | decided (minimal subset); rattlerthis side closed; condathis assertion optional | maybe: coercion |
| 4 | README cross-links between the two packages | both | done (condathis 2026-11-13, rattlerthis checked 2026-11-18) | no |
| 5 | Package-wide supervisor escape hatch | feat-pipeline | not decided | yes: option vs env var |
| 6 | Nested-activation artifacts in `get_micromamba_activation_envvars()` | feat-pipeline | done in 0.2.0 (2026-11-16, `../feat-run-unify/`) | no |
| 7 | Windows MinGW runtime pins in tests | HANDOFF | pins kept; newer builds exist, untested on Windows | no |
| 8 | jarl lint baseline (650 findings with every rule) | HANDOFF | done in 0.2.0 (2026-11-18): 0 findings, `jarl.toml`, `just lint` gate (`../feat-run-unify/` D20) | no |
| 9 | In-code `TODO: @luciorq` comments (3) | code | 9a decided (abort), superseded by `env_definition()`; 9b, 9c done 2026-11-18 | no |
| 10 | `backend_status()` diagnostics | feat-backend-abstraction "later ideas" | idea | no |
| 11 | Container backend package | feat-backend-abstraction "later ideas" | idea | yes: whether at all |
| 12 | `verbose` on `run_pipeline()` | feat-pipeline "intentional divergences" | explicitly not planned | no |
| 13 | Issue #12 (inner double quotes on Windows) | GitHub issue | fixed in 0.2.0; regression assertion off Windows; issue still open | no |
| 14 | Tests that need a UTF-8 locale or direct DNS | local run 2026-11-05 | done 2026-11-13 | no |
| 15 | r-universe: condathis and rattlerthis | r-universe research 2026-11-05 | article done 2026-11-13; pkgdown workflow open | no |
| 16 | condathis on WebAssembly (webR) | r-universe research 2026-11-05 | idea | yes: whether to abort early |
| 17 | Optional `packages =` compatibility leftovers (6) | `packages =` review 2026-11-13 | b to f done in 0.2.0 (2026-11-18); a open | one: positional `channels` |
| 18 | rattlerthis follow-ups of `env_definition()` | feat-env-file 2026-11-13 | a, b done; c, d open | no |
| 19 | Empty `LICENSE` in the upstream `polyglot` repository | CRAN docs review 2026-11-13 | open, maintainer only | no |
| 20 | Small leftovers of the 2026-11-13 reviews | CRAN preparation reviews | a, b, e done 2026-11-18; c, d open | no |
| 21 | Follow-ups of the run-family unification | feat-run-unify 2026-11-16 | open (e and parts of f done in 0.2.0) | yes: `R_LIBS*` |
| 22 | `run()` waits for a change of its environment by another session | feat-run-unify D17, 2026-11-18 | deferred to after 0.2.0 | yes: whether to wait |
| 24 | Dependency minimums, `linux-riscv64` micromamba, CI platforms | deps survey of round 8, 2026-11-18 | done in 0.2.0 (2026-11-18); CI jobs not run yet | no |
| 25 | User-facing docs against the code of round 8 | docs survey of round 8, 2026-11-18 | done in 0.2.0 (2026-11-18); co-author role left to the maintainer | one: `Authors@R` role |
| 26 | `parse_match_spec()` writes `license_family` also as `license` | jarl stage of round 8, 2026-11-18 | open | yes: fix in 0.2.0 or after |

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
  reduces to stdout alone. No behaviour difference. The current branch
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
   now byte-identical to the tarball. The author chose to port the no-op
   too so sources match CRAN.) Port the `skip_if_offline()` + `skip_on_cran()` edit to
   `test-satisfy_dependencies.R` onto `feat-strict-defaults` (or `main`
   right after the merge). Tests ship in the tarball (`^tests` is not in
   `.Rbuildignore`), `setup.R` has no global CRAN skip, and that test
   creates a `python` + `numpy` environment over the network. The
   `stream = "both"` edit is a no-op and is not worth porting.
3. Add `CRAN-SUBMISSION` handling to the release sequence: commit it (or
   at least note the SHA in the release notes) so the next release leaves
   a record.
   (Done 2026-11-13, in `8cffc25`, without committing the file:
   `just git-tag` now tags the commit named in the `SHA:` field of
   `CRAN-SUBMISSION`, and aborts when its `Version:` differs from
   `DESCRIPTION`. The tag is the record. `just release-github` runs
   `usethis::use_github_release()`, which removes the file, so
   `git-tag` must run first; the recipe comments say so.)
4. Fix the `git-tag` recipe's message typo risk: the commit message
   "prepare for v1.4.0" was hand-typed. The recipe itself reads the
   version from DESCRIPTION and is fine.
   (2026-11-13: the recipe now reads the version with `read.dcf()` from
   `DESCRIPTION` instead of loading the package. Commit messages stay
   hand-typed.)

## 1. Converge `run()` onto the resolve-once + direct-spawn model

**Done in 0.2.0 (2026-11-16), see `../feat-run-unify/`.** The text below
is the plan of 2026-09-17 and is stale. `run()` stopped wrapping the
command in `micromamba run` earlier in the 0.2.0 cycle (NEWS: "`run()`
starts the command itself"). On 2026-11-16 `run()` gained `activate`,
`run()` and `run_bin()` became one implementation, and the three run
functions got one lookup rule, one fixed activation for
`activate = FALSE` and one signal status.

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
  `PATH`. `run_bin()` uses `resolve_env_bin_path()` with a bare-name
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

Verified by hand on 2026-11-05, on Linux with rattlerthis built from
source, by knitting `vignettes/articles/backends.qmd` (PR #38) and in
`with_sandbox_dir()`: `create_env(method = "rattler")` from conda-forge,
`run()` without `method`, a `run_pipeline()` across a rattler and a
micromamba environment, `install_packages(method = "micromamba")` on a
rattler environment aborting with `condathis_backend_mismatch`, a read with
the wrong `method` warning with `condathis_backend_mismatch_warning`,
`create_env()` refusing a name the other backend owns,
`condathis_backend_ambiguous_env` for copies under both backends,
`clean_cache()` emptying rattler's package cache, and `remove_env()`. The
plan below still stands: none of it is a test in either suite yet.

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

**Update 2026-11-18: done.** rattlerthis's
`tests/testthat/test-condathis-conformance.R` covers it: it runs
`condathis::create_env()`, `condathis::run()` and
`condathis::remove_env()` with `method = "rattler"`, reads the
`backend.json` marker, asserts `condathis_backend_mismatch` for
`install_packages(method = "micromamba")`, and has a conda-forge
end-to-end section. "None of it is a test yet" above is out of date.

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

**Update 2026-11-18.** Step 1 is done on the rattlerthis side: its
`feat-rattlerthis-backend/TODO.md` records the six `list_packages()`
columns and `test-condathis-conformance.R` as done (2026-10-22). Step 2,
the assertion in condathis, is new behaviour and stays for after 0.2.0.

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

**Update 2026-11-13.** The condathis side is done, in the docs sweep of
the CRAN preparation. "How It Works" in `README.qmd` says that
`micromamba` is the built-in backend, that other packages add backends
with the experimental `register_backend()`, that `method = "rattler"`
uses the optional rattlerthis, which is not on CRAN but on R-universe,
and links to the backends article. It names
`options(condathis.backend_priority = ...)`. No separate section was
added. Left: the cross-link check in rattlerthis's README.

**Update 2026-11-18: done.** rattlerthis's `README.md` links to
condathis and says to use it with `method = "rattler"`. Linking the
backends article from there is optional.

## 5. Package-wide supervisor escape hatch

**Origin.** `feat-pipeline/PLAN.md` "Possible follow-up, not yet decided
or implemented". It is the only unchecked box in `feat-pipeline/TODO.md`.

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
set this outside R (CI). Options are the established pattern in this
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

**Done in 0.2.0 (2026-11-16), see `../feat-run-unify/`.** Every child now
starts without the activation of the R session (`isolate_host_env()`),
and a recorded micromamba activation drops `CONDA_PREFIX_<n>` and
`CONDA_ENV_SHLVL_<n>_*` and has `CONDA_SHLVL=1`. The cause on the
developer machine was a micromamba started through a pixi trampoline,
not only R itself. The text below is the plan of 2026-09-17.

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

**Update 2026-11-18.** anaconda.org lists newer win-64 builds: `libgcc`
16.1.0 `h110b43a_2` and `_3`, and 16.2.0 `h110b43a_4` to `_7` (the
newest uploaded 2026-09-25), plus 15.3.0 and 14.4.0 rebuilds. The `_2`
build that crashes is not marked broken there. Whether a newer build
fixes the crash needs a Windows run, so the pins stay for now. Step 2
above is unchanged: drop the pins on kappa or a throwaway CI branch,
and keep them if R does not start. Not needed for CRAN: the tests that
use them are `skip_on_cran()`.

## 8. jarl lint baseline

**Origin.** HANDOFF item 3. The first decision was to fix genuine
findings and to add no `# jarl-ignore` comment without asking. On
2026-11-18 the maintainer asked to fix every finding of
`jarl check . --select ALL`, the cyclomatic complexity included.

**Done in 0.2.0 (2026-11-18, `../feat-run-unify/` D20).** jarl 0.7.1
with every rule reported 650 findings: 149 unused objects, 147
`condition_call`, 108 undesirable operators (`<<-` and `:::`), 105
`expect_s3_class`, 33 implicit assignments, 16 cyclomatic complexity,
and 92 of 18 other rules. `jarl check .` now reports 0 with `jarl.toml`
(every rule, `max-complexity = 20`), and `just lint` fails on a finding.
The 30 findings listed here before (unused `dl_success` and
`status_code`, the `if_not_else` of `parse_match_spec()`, the captures of
the tests, the empty trailing arguments of `test-run_output_file.R`) are
among them.

- Safe autofixes (`expect_named()`, `expect_null()`, `expect_type()`,
  `expect_no_match()`, `grep()` for `which(grepl())`, ...) applied and
  reviewed. `expect_identical(class(x), y)` became
  `expect_s3_class(x, y, exact = TRUE)`, the same test.
- Not safe and corrected: the `fixed_regex` autofix of
  `gsub("/", "\\\\", x)` doubled the backslashes (four calls in
  `R/get_micromamba_activation_envvars.R`, four in the tests); and
  `stop(cnd, call. = FALSE)` on a condition object warns.
- Unused objects: a missing assertion added where a capture was never
  read; a dead placeholder or a binding of a setup helper
  (`stub <- local_stub_backend(...)`) removed; a variable read through a
  cli template keeps a `# jarl-ignore unused_object` comment with the
  reason (40 ignore comments in all, every one with a reason).
- `condition_call`: `call. = FALSE` on the `stop()` of mocks and of the
  example backend (`man/examples/backend-stub.R`).

The 16 functions above 20 and their new helpers (same inputs, values,
side effects, condition classes and messages):

| Function (file) | Score | New helpers |
|---|---|---|
| `micromamba_read_definition()` (`backend-micromamba-definition.R`) | 49 | `micromamba_refuse_definition()`, `micromamba_named_definition_format()`, `micromamba_detected_definition_format()`, `micromamba_definition_options()`, `micromamba_definition_stage_name()`; constants `micromamba_lock_formats`, `micromamba_pixi_lock_reason` |
| `validate_backend_return()` (`backend-query.R`) | 42 | `validate_list_envs_return()`, `validate_bool_return()`, `validate_native_platform_return()`, `validate_can_solve_return()`, `validate_definition_formats_return()`, `validate_dir_return()` |
| `validate_definition_description()` (`backend-query.R`) | 22 | `description_na_or_string()`, `normalize_definition_description()` |
| `verify_micromamba_checksum()` (`install_micromamba.R`) | 21 | `verify_micromamba_archive_checksum()` |
| `parse_match_spec()` (`parse_match_spec.R`) | 58 | `ms_apply_bracket_attributes()`, `ms_extra_attribute()` |
| `ms_format_canonical()` (`parse_match_spec.R`) | 36 | `ms_format_channel_prefix()`, `ms_format_version_build()`, `ms_format_extra_brackets()` |
| `ms_normalize_version()` (`parse_match_spec.R`) | 28 | `ms_normalize_single_version()` |
| `parse_output()` (`parse_output.R`) | 28 | `output_binary_streams()`, `output_raw_text()`, `split_output_lines()` |
| `pump_pipeline_io()` (`pump_pipeline_io.R`) | 24 | `pump_pipeline_poll()`, `pump_pipeline_write_input()`, `pump_pipeline_result()` |
| `pump_process_io()` (`pump_process_io.R`) | 38 | `pump_poll_timeout()`, `pump_process_write_input()`; reads with `pump_read_chunk()` |
| `rethrow_error_run()` (`rethrow_error_run.R`) | 25 | `abort_run_failure()`, `run_result_without_process()` |
| `run_internal_backend()` (`run_internal_backend.R`) | 24 | `check_activated_invocation()` |
| `broken_pipe_transition()` (`run_pipeline.R`) | 21 | `broken_pipe_step()`, `broken_pipe_reader_step()`, `broken_pipe_watching_step()` |
| `collect_package_specs()` (`validate_args.R`) | 26 | `abort_unknown_package_arg()`, `collect_unnamed_package_specs()` |
| `validate_env()` (`validate_env.R`) | 24 | `validate_env_installed_packages()`, `abort_validate_env_unsatisfied()` |
| `vs_parse_predicate()` (`version_spec_contains.R`) | 49 | `vs_check_predicate()`, `vs_range_predicate()`, `vs_equality_predicate()`, `vs_bare_predicate()` |

Coverage: the existing tests of each function, run after each split, a
new characterization test of the bracket keys that `parse_match_spec()`
writes (`test-parse_match_spec.R`; `license`, `fn`, `features`, `md5`,
`sha256`, `build_number`, `track_features`, `optional` had no test), and
a differential check of 1,248 inputs against the code before the splits.

Not in scope: the 403 `lintr::lint_package()` findings (168 line length,
168 explicit return, 27 commented code, 24 object-usage false positives).
The project does not run lintr in CI or `just lint`. The gates are jarl
and air.

## 9. In-code `TODO: @luciorq` comments

- a. `R/create_env.R:121`: mixing `env_file` and `packages` is allowed
  by conda but condathis's `resolve_create_env_packages_arg()` ignores
  `packages` whenever `env_file` is set. Needs a decision: either pass both
  (`-f file pkg1 pkg2`, which micromamba accepts) and add tests plus docs,
  or abort with a clear message when both are supplied. Recommended: pass
  both, since the comment says this was the intent since 0.1.3-dev.
  **Decided: abort.** The backend work (`0e60288`, 2026-11-04) removed
  the comment and made `create_env()` abort when package specs and an
  environment file are both given (class
  `condathis_create_env_conflicting_args`, NEWS 0.2.0 "Breaking
  changes"). In 0.1.4 the specs were ignored. **Superseded 2026-11-13**
  by `env_definition()` (`feat-env-file/`): specs together with an
  `env_definition()` abort the same way, and so do `env_definition()`
  together with the deprecated `env_file =`
  (`resolve_create_definition()`, `R/create_env.R`). Passing both to the
  backend stays out of scope.
- b. `tests/testthat/test-rethrow_error.R:68`: "Improve tests". Fold into
  item 8's unused-object cleanup for that file.
- c. `tests/testthat/test-check_micromamba_version.R:48`: bump the mocked
  version above the internal pin whenever `check_micromamba_version()`'s
  `target_version` (currently `"2.8.1"`) changes.

**Update 2026-11-18.** b and c are done. b: the "stdin is a file" test
of `test-rethrow_error.R` passes an explicit frame
(`rlang::env(error, error_var, stdin, cmd)`) instead of reading the
test's own variables, asserts what `rethrow_error_run()` returns for
`NULL`, `"|"` and an existing file, and keeps both class assertions; the
commented-out code and the TODO are gone, and the other tests of the
file that relied on implicit frame variables pass them explicitly too.
c: the mock returns `"2.10.0"`, above `micromamba_minimum_version`
(`"2.8.1"`), and the internal default is `2.10.0-0`, the latest release;
the stale TODO comment is replaced by one that says what to keep.

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
all; nothing in condathis needs to change first. That was the point of
the "resolve, don't execute" contract.

## 12. `verbose` on `run_pipeline()`: explicitly not planned

Recorded so nobody reopens it by accident. Interleaving live output from N
concurrent processes is a different problem from `processx::run()`'s
single-process polling and was ruled a structural divergence, not a parity
gap. If it is ever wanted, `pump_pipeline_io()` is now the single place
that already polls every stage, so a `verbose = "output"` that echoes
stdout chunks as they arrive would be the minimal version.

## 13. Issue #12: inner double quotes in `run()` arguments on Windows

**Origin.** GitHub issue #12 (2024-10-06), the only open issue on
2026-11-05.

**Where things stand.** Fixed in 0.2.0, checked 2026-11-05. Before 0.2.0,
`run()` went through `micromamba run`, which on Windows wraps the command
in a `.bat` script, so `cmd.exe` re-parsed every argument and dropped the
inner `"` of `'print(Sys.getenv("MY_VAR_1"))'`. Since the backend work,
`run()` starts the command itself through processx, and
`R/run_internal_native.R` is gone (NEWS 0.2.0, *Breaking changes*).
`tests/testthat/test-argument_fidelity.R` passes 27 arguments (among them
`a"b`, `"a b"`, `%PATH%`, `^`, `|`, `&`, newlines and Unicode) through
`run()` and `run_bin()` to a C probe that reports each one as hex, read
with `CommandLineToArgvW()` on Windows. It passes on `windows-latest` and
`windows-11-arm` (merge of PR #37, run 41951505379); the failed runs of the
same day list every skipped test, and these were not among them.

**Implementation plan.** Close the issue with a comment that points to the
test (the maintainer posts it). Optional: add the issue's exact example
(R's own `R -e` with double quotes) as a second assertion in the
environment-variable test of `test-create_env.R`, which uses only single
quotes. The probe proves condathis's side; that assertion would also cover
R's launcher on Windows.

**Update 2026-11-18.** The assertion is in `test-create_env.R`, off
Windows only. On Windows, `R.exe` starts `Rterm.exe` through a command
line it builds itself, so whether R receives the inner quotes is up to
R, and it was not run there. On kappa: run it once without the
`is_windows()` branch. If it passes, drop the branch; if R.exe loses the
quotes, keep the branch and say so in the comment (condathis's side is
proven by `test-argument_fidelity.R`). Closing the issue stays a
maintainer action.

## 14. Tests that need a UTF-8 locale or direct DNS

**Origin.** Running the suite in a container on 2026-11-05.

**Where things stand.**

- Under R's `C` locale, the pip test of `test-list_packages_pypi.R` errors
  in `jsonlite::fromJSON()` ("premature EOF") on the output of
  `pip inspect`: a maintainer name of a conda-forge package (with an o-umlaut) is
  not ASCII. `run()` returns the right UTF-8 text; jsonlite cannot read it
  in a non-UTF-8 session. Under `C.UTF-8`, as on CI, all 6 tests of the
  file pass.
- `testthat::skip_if_offline()` checks a direct DNS lookup. Behind an HTTP
  proxy that resolves names itself, it skips the network tests ("offline")
  although downloads work: the two uv/pip parity tests of the same file
  were skipped until the check was stubbed out.

**Implementation plan.** Skip the JSON parse of that test when
`l10n_info()[["UTF-8"]]` is `FALSE` (or read `stdout` with its encoding
marked), and note both in `.github/CONTRIBUTING.md`: run the suite in a
UTF-8 locale, and expect network tests to skip behind a proxy unless the
DNS check works there.

**Done 2026-11-13** (CRAN preparation, `8cffc25`). The pip test of
`test-list_packages_pypi.R` skips with "The R session is not in a UTF-8
locale: run the tests in one." when `l10n_info()[["UTF-8"]]` is not
`TRUE`; it no longer errors. `.github/CONTRIBUTING.md` asks for a UTF-8
locale and explains the DNS check of `skip_if_offline()` behind a proxy,
and `.github/AGENTS.md` ("Testing rules") asks for a UTF-8 locale too.
The skip only
applies to a non-UTF-8 session, so it does not break the zero-skip rule
of developer runs.

## 15. r-universe: condathis and rattlerthis

**Origin.** Research on 2026-11-05 (see rattlerthis's `PLAN.md`,
"r-universe and WebAssembly", for r-universe's build matrix and tooling).

**Where things stand.**

- `luciorq.r-universe.dev` lists condathis and isoformic. It builds
  condathis from the default branch; on 2026-11-05 it still served 0.1.4,
  built 2026-10-17 from the old `main`, and it checks for changes every
  hour. condathis has no compiled code, so it gets one binary per OS
  (also used on Windows on ARM64) and a WebAssembly one.
- rattlerthis is registered (first build 2026-11-05).
  On 2026-11-06 the universe had binaries for Linux, macOS, Windows x64,
  Windows on ARM64 and WebAssembly, so its users do not need Rust.
  Only macOS x86_64 on R 4.6.2 failed (see rattlerthis's `TODO.md`).
- The pkgdown workflow builds rattlerthis from source for the backends
  article (about 2.5 minutes of Rust on the runner, PR #38).
- Decided 2026-11-08: condathis's `DESCRIPTION` does not name
  rattlerthis.
  No `Enhances`, `Suggests` or `Additional_repositories` entry.
  The CRAN release of condathis is independent of rattlerthis.
  CRAN reviewers do not like a CRAN package that points to a package
  outside CRAN.
  This replaces spec decision Q22.
  condathis still finds the package by name at run time
  (`known_backend_packages`).

**Implementation plan.** Install the rattlerthis binary from the
universe in the pkgdown workflow (with `dependencies = FALSE`, so the
local condathis stays).
Show the universe in the article's install section.

**Update 2026-11-13.** The article part is done: the backends article
installs rattlerthis from R-universe and mentions its Linux binary
repository (`vignettes/articles/backends.qmd`), and `README.qmd` points
to R-universe too. `cran-comments.md` explains why help pages mention
rattlerthis although `DESCRIPTION` does not. Still open:
`.github/workflows/pkgdown.yaml` clones rattlerthis and builds it from
source with Rust.

## 16. condathis on WebAssembly (webR)

**Origin.** Research on 2026-11-05.

**Where things stand.** condathis builds for WebAssembly (pure R:
r-universe's 0.1.4 WebAssembly binary built successfully), but webR cannot
start processes, so no backend can create or run an environment there.
What a user gets is whatever error processx or the micromamba download
gives first. rattlerthis already fails gracefully on webR: it installs
without its Rust library and aborts with `rattlerthis_rust_unavailable`
(also `condathis_backend_unsupported`).

**Implementation plan.** Decide whether condathis should say so itself:
`micromamba_backend_available()` returning `FALSE`, and one classed abort
(for example `condathis_platform_unsupported`) from the functions that
start a process, when `R.version$platform` is
`wasm32-unknown-emscripten`. The queries (`list_envs()`, `env_exists()`)
would keep working.

## 17. Optional `packages =` compatibility leftovers

**Origin.** The `packages =` compatibility review of 2026-11-13
(`feat-strict-defaults/PLAN.md`, addendum sections 5 and 6). The
adversarial review re-ran 72 call shapes of 0.1.4 against the final
tree and rated these optional. They were left out of 0.2.0 because each
needed another full check on Linux, macOS and Windows, and none breaks
a 0.1.4 call that works today.

**Items, with the fix the review proposed.**

- a. `install_packages("pkg", "env", <channels>)`, channels as the 0.1.4
  third positional argument. The positional guard looks only at the last
  spec, which is a channel, so the call creates an empty
  `"condathis-env"` and fails in the solver. In 0.1.4 it worked. NEWS
  ("Old positional calls no longer work") describes the outcome.
  Fix: in `install_packages()`, when there are three or more unnamed
  arguments, all strings, also check `dots[[2L]]` (the 0.1.4 `env_name`
  slot) with `abort_on_positional_env_name()` and abort with
  `condathis_install_packages_positional_env_name` before anything is
  created. Test: with `"my-env"` present,
  `install_packages("x", "my-env", "conda-forge")` aborts and
  `"condathis-env"` is not created. Decision needed: worth the extra
  rule, or leave it to NEWS. Checked again 2026-11-18 (from the code,
  not run): with `env_name` missing the target is `"condathis-env"`, so
  when it does not exist, `install_packages()` creates it (decision D3)
  before the solver fails on the packages `"my-env"` and
  `"conda-forge"`. The user gets a solver error and a new empty default
  environment, which stays. Weigh that side effect in the decision.
- b. The hint for `packages =` plus one unnamed string suggests
  `env_name = "<value>"` also when `env_name` is already in the call
  (following it gives "matched by multiple actual arguments"). Fix: give
  `collect_package_specs()` a `given_args` argument and add the hint
  only for an argument that was not given.
- c. `create_env(NULL, "env.yml", env_name = ...)`, 0.1.4's positional
  `env_file`. Since `env_definition()`, the "must be named" hint also
  says to use `env_definition()`, but with the example name
  `"environment.yml"`, not the user's file. The `NULL` abort runs before
  the file-name check. Fix: in the `NULL` branch of
  `collect_package_specs()`, look for a later string that
  `is_env_file_name()` accepts and name it in the hint. Also, for a
  `NULL` in first position, do not say "after the package specs".
- d. `method = "native"` is not a soft deprecation in `env_exists()`,
  `list_envs()`, `get_install_dir()`, `list_packages()`, `get_env_dir()`
  and `run_pipeline()`: they warn also for calls made inside other
  packages. 0.1.4 had `method` only in `create_env()` and `run()`, so no
  0.1.4 call is affected. Fix: pass `user_env = rlang::caller_env()` to
  `resolve_method_alias()` in `R/env_exists.R`, `R/list_envs.R` and
  `R/get_install_dir.R`, to `resolve_backend()` in `R/list_packages.R`
  and `R/get_env_dir.R`, and capture it in `run_pipeline()` for the
  per-step alias. Then shorten the NEWS bullet and the
  `?condathis-conditions` entry, which list the six soft functions.
- e. testthat's 3rd edition sets `lifecycle_verbosity = "warning"` in
  `test_that()` (`local_reproducible_output()`), so other packages'
  tests see `condathis_deprecated_packages_arg` and
  `condathis_deprecated_env_file_arg` even for calls inside their own
  `R/` code. `lifecycle::deprecate_soft()` behaves the same, so the
  behavior is right; the docs do not mention it. Fix: one sentence in
  the `...` docs and in NEWS, with the way out
  (`withr::local_options(lifecycle_verbosity = "quiet")`).
- f. `install_packages(packages = NULL)` returns status 0 also when the
  environment probe failed (`NA`), which skips both the `env_not_found`
  abort and the creation. Rule R5 says a failed probe is not "absent"
  and the backend should report its own error. Found by reading
  `R/install_packages.R`, not reproduced (it needs a backend whose probe
  fails). Fix: return early only when the probe was `TRUE` or the
  default environment was just created; otherwise let the backend run.

**Update 2026-11-18.** b to f are done in 0.2.0:

- b: `collect_package_specs()` has `given_args`; `create_env()`,
  `install_packages()` and `validate_env()` pass the arguments the user
  gave (`env_name`, and `env_file` for `create_env()`), and a hint names
  only an argument that is not in the call.
- c: the `NULL` hint (`positional_null_hint()`) says "Arguments other
  than package specs must be named" for a leading `NULL`, and names the
  first later value that looks like an environment file in the
  `env_definition()` example. Values are interpolated where they are
  (`format_hint()`), with braces escaped.
- d: the six functions pass `rlang::caller_env()`, captured in the
  exported function (`run_pipeline()` passes it to
  `parse_pipeline_steps()`). NEWS and `?condathis-conditions` now say
  that every function with `method` follows the soft rule.
- e: as the verifier corrected it: calls from a package's own `R/` code
  already warn in its own tests (the `TESTTHAT_PKG` rule). What the
  third edition adds is that calls made inside other packages warn in
  `test_that()` too. Documented in `?condathis-conditions` and the `...`
  docs of `create_env()`, `install_packages()` and `validate_env()`, and
  in the NEWS bullet of the deprecation.
- f: not as proposed above. `install_packages()` reads the probe of
  `resolve_backend()` (decision D19 of `../feat-run-unify/`), and with
  no specs a failed probe aborts with `condathis_backend_probe_failed`.
  Letting the backend run an empty install would contradict 0.1.4's
  "nothing to install" result, and nothing else would report the
  failure.

## 18. rattlerthis follow-ups of `env_definition()`

**Origin.** `feat-env-file/` (2026-11-13), items 16 to 19 of its
`PLAN.md`, which has the details. rattlerthis was not changed, built or
run in that work: the build on the Linux host failed (no `pkg-config`;
with a shim, the Rust release build ran out of disk), so compatibility
rests on reading its code, on condathis's stub backend with
rattlerthis's exact arguments, and on a replay of the micromamba half
of its parity fixtures. Listed here because the work happens in
the rattlerthis repository.

- a. **Run rattlerthis's tests against the new condathis** on a machine
  that can build it (feat-env-file item 16), before or soon after the
  CRAN submission. It does not block CRAN: `DESCRIPTION` does not name
  rattlerthis.
- b. **Expected failures** (feat-env-file item 17): rattlerthis's
  `test-parity-envfile.R:98`
  (`expect_identical(seen[[method]]$warnings, list())`) and
  `test-parity-linkscripts.R` (about line 320) assert that `env_file =`
  calls give no warnings. Run first or alone, they now see
  `condathis_deprecated_env_file_arg`: the tests run under
  `TESTTHAT_PKG = "rattlerthis"` and testthat's 3rd edition, which both
  count as direct use (item 17e). Fix in rattlerthis: set
  `lifecycle_verbosity = "quiet"` for those calls, or move them to
  `env_definition()`. condathis does not change.
- c. **Opt in to the new backend contract** (feat-env-file item 18):
  accept the optional `definition` argument and implement
  `backend_describe_definition()` on top of `rt_read_env_file()`, so the
  rattler backend says which files it reads and which are locks. Until
  then condathis passes the plain path, as before.
- d. **pixi.lock** (feat-env-file item 19): rattlerthis cannot read it,
  although the `rattler_lock` crate reads v1 to v7. The micromamba
  backend refuses it with a reason. See also `feat-pixi-backend/PLAN.md`.
- e. Do item 2 (smoke test) and item 3 with the same build.

**Update 2026-11-18.** a and b are done. a: rattlerthis's suite ran
against condathis 0.2.0 in round 6 of `../feat-run-unify/`, and its
fixes are committed there. Run it once more if condathis changes again
before the submission (round 8 changed condathis). b:
`test-parity-envfile.R` sets `lifecycle_verbosity = "quiet"` around
`create_env(env_file = )`, and `test-parity-linkscripts.R` uses
`env_definition()`. c and d are feature work in rattlerthis.

## 19. Empty `LICENSE` in the upstream `polyglot` repository

**Origin.** The docs review of 2026-11-13.
`inst/extdata/README.md` says that the `polyglot` test package
(`inst/extdata/polyglot-channel/`) is the maintainer's own work,
distributed under the MIT license of condathis. Its source repository,
https://github.com/luciorq/polyglot, has an empty `LICENSE` file. The
statement in condathis is correct; the upstream repository should say
the same. Maintainer only: add a license file there. Nothing changes
in condathis.

## 20. Small leftovers of the 2026-11-13 reviews

**Origin.** The reviews of the CRAN preparation rounds. None blocks the
release.

- a. On Windows, the relative branch of `resolve_env_bin_path()` (a
  command found inside the environment) still returns `fs::path()` with
  `/`. Only the absolute branch uses `native_command_path()` since
  2026-11-13. It matters only for a program that reads its own path from
  its command line, as `cmd.exe` does; no Windows test fails.
- b. For a URL channel, the "installed from another channel" hint shows
  the normalized form `host/path` (for example `example.org/chan`),
  which does not work as a value of `channels`. Show the original URL
  instead.
- c. The bioconda default-channel hint also appears when a conda-forge
  package exists but not in the requested version (for example
  `python=1.0`). The text is conditional ("If ... is a bioconda
  package"), so it was kept. A local mirror of bioconda under another
  name also gets the hint.
- d. CRAN-mode test time on Windows is about 120 s on kappa (Linux about
  60 to 70 s, macOS about 35 s), against 76 to 88 s for the whole 0.1.4
  check on CRAN's Windows flavors. Wait for win-builder's figure. If it
  is too slow, the next candidates for `skip_on_cran()` are
  `test-backend-packages.R`, `test-clean_cache.R` and
  `test-with_sandbox_dir.R`.
- e. `helper-env-lock.R`'s `sigint_ignored_in_proc()` has no unit test
  of its own; it was checked by hand with synthetic status files. A test
  in `test-env_lock.R` can use its `status_file` argument.

**Update 2026-11-18.** a, b and e are done. a: decision D19 of
`../feat-run-unify/`; one kappa run left. b: as the verifier corrected
it, only an http(s) channel whose normalized form is not a name is
shown as its URL (`channel_display_name()`: platform directory and
credentials removed, then `hide_secrets()`); names such as `bioconda`
and `pkgs/main`, and local paths, are shown as before, and the
comparison still uses the normalized form. e: a test in
`test-env_lock.R` with six status files. c stays optional; d waits for
win-builder.

## 21. Follow-ups of the run-family unification

**Origin.** `../feat-run-unify/PLAN.md`, "Follow-ups" (items 14 to 17
there). Added 2026-11-16.

- a. An optional backend hook to describe a command without activation,
  or to refuse `activate = FALSE` with a class, for a container or remote
  backend. The default keeps the fixed activation of condathis.
- b. `R_LIBS`, `R_LIBS_USER` and `R_LIBS_SITE` of a Conda R reach the
  commands. Needs a decision: clear, keep, or clear only when they point
  into a host prefix.
- c. rattlerthis: update the expectations of
  `tests/testthat/test-parity-childenv.R` (`run_bin(activate = FALSE)`
  now has the fixed activation; a killed command has status 137), then
  run its suite against condathis 0.2.0. Its `rattler_pip_base_env()`
  builds a block without the isolation of condathis.
- d. Soft-deprecate `run_bin()` in a later release.
- e. Done in 0.2.0 (feat-run-unify D13): on Windows a bare name is
  looked up on the command's `PATH`, as `cmd.exe` does, and a name found
  nowhere fails with status 127.
- f. Smaller: a pixi trampoline given as the micromamba path. Done in
  0.2.0: `MAMBA_SHLVL` and the prompt modifiers (feat-run-unify D11:
  `"1"` and `""` for every command) and Windows with R itself in a Conda
  prefix (D12: R's prefix leaves the command's `PATH`). The rest done in
  0.2.0 (feat-run-unify D22): discovery replaces a trampoline by the
  `exe` of its `trampoline_configuration/<name>.json`, so its
  `CONDA_SHLVL` and `CONDA_PREFIX` never reach micromamba.

## 22. `run()` waits for a change of its environment by another session

**Origin.** `../feat-run-unify/PLAN.md`, D17 (finding C2 of the review of
2026-11-18). Older than 0.2.0: 0.1.4 behaves the same.

`run()` checks that the environment exists and activates it without the
lock of the environment. While another R session runs
`create_env(overwrite = TRUE)` for it, the environment is in `#trash`, so
`run()` says that it does not exist. During `install_packages()` a
command can run in a half-linked environment. Several `run()` calls
among themselves are fine. 0.2.0 documents it in `?run`.

A possible fix: before the probe, when another live session holds the
environment's lock (`lock_held_by_others()`), take it shared and release
it at once. That waits for the change in flight. Release it before
`create_base_env()` (which takes the same lock exclusively; on Windows a
second handle of the same process would deadlock) and before the command
starts (a long command must not block `install_packages()`). It only
narrows the window: a change can start after the check, or while the
command runs. Test: a callr session holds the lock, `run()` in the test
process says that it waits and succeeds after the release, without
sleeps. Needs a decision: whether the narrower window is worth a lock
check in every `run()`.

## 23. Compiler variables of an activated host prefix

**Origin.** `../feat-run-unify/PLAN.md`, D18 item 8 (the docs survey of
round 8, its finding ISO-1). 0.2.0 removes the variables that a pixi
global binary set when it started R, with the exact values that pixi
recorded. Not covered: R started from a shell where `conda activate` or
`micromamba activate` activated a prefix with the compiler packages. The
conda-forge compiler scripts (`_tc_activation` in
`activate-gcc_<platform>.sh`, `activate_clang_<platform>.sh`) save
`CONDA_BACKUP_<X>` only when `<X>` was set before, and their deactivation
unsets `<X>` when there is no backup. `restore_host_backups()` handles
the first case; the second needs the names that the scripts set.

Options: parse the `_tc_activation` arguments of the prefix's
`activate.d` scripts (fragile: a disabled template block names
`QEMU_LD_PREFIX`), or measure once per session what the prefix's
activation sets from a clean environment, as `r_startup_env_vars()` does
for R's startup (runs the host's scripts, about 0.3 s, needs micromamba).
Test first whether an environment with `gcc_linux-64` overrides the
inherited values (the verifier of round 8 could not check it):
`CFLAGS` is appended to (`${CFLAGS:+ }${CFLAGS}`), so an inherited value
leaks into the compiler flags of a command.

## 24. Dependency minimums, platforms and CI

**Origin.** The dependency survey of round 8 (2026-11-18) and its
verifier. Rule (maintainer): a minimum version is what the code
verifiably needs, chosen so that it still has CRAN binaries for every
supported R (R >= 4.3) where possible. The binaries were read from the
per-R-version `PACKAGES.gz` of CRAN for Windows (4.3 to 4.6), macOS arm64
(`big-sur-arm64` 4.3 to 4.5, `sonoma-arm64` 4.6) and macOS x86_64
(`big-sur-x86_64` 4.3 to 4.6) on 2026-11-18.

Decisions (DESCRIPTION):

- `rlang (>= 1.1.0)`, was 1.0.0. From 1.1.0, `try_fetch()` finds a
  condition class across chained errors (the backend errors are parents
  of condathis errors); with 1.0.6 a handler for the parent's class was
  not called (checked by the survey in an isolated session). Binaries
  everywhere (the oldest is 1.1.5, Windows R 4.3). Not 1.3.0: Windows
  R 4.4 has 1.2.0 and macOS arm64 R 4.4 has 1.1.7.
- `fs (>= 1.6.7)`, was unversioned. Before 1.6.7, `fs::dir_exists()`
  returns `FALSE` for a directory reached through a relative symbolic link
  in another directory. Checked with fs 1.6.5 in an isolated session:
  `run("hello", env_name = env_path("<dir>/envs/linked"))`, with
  `envs/linked -> real`, aborted with `condathis_env_path_not_found`;
  with fs 2.1.0 it ran the command. condathis calls `dir_exists()` on
  other paths that users give too (roots, data directories). Cost: Windows R 4.3 (1.6.5) and macOS R 4.3
  (1.6.6) install fs from source, where processx and ps already need a
  compiler (below). Not 1.3.2, the version that has `file_info(follow =)`:
  it keeps this bug.
- `stringr (>= 1.5.0)`, `withr (>= 3.0.2)`: was unversioned. The code
  needs `withr::local_tempdir()` (2.3.0) and the tests
  `local_tempfile(lines =)` (2.5.0); 3.0.2 is what testthat 3.3.2 needs,
  the `withr::defer()` of the package code was only tested with withr 3,
  and it has binaries everywhere. Not 3.0.3 (no binary on Windows or
  macOS arm64 for R 4.4). stringr 1.5.0 made recycling and empty patterns
  errors; no call depends on it, but nothing was tested with 1.4.
- `cli (>= 3.4.0)` kept: `{.obj_type_friendly}` is new in 3.4.0, and
  `{.or}` and `{.obj_type_friendly}` work with cli 3.4.0 (checked).
- `jsonlite` stays unversioned (only `fromJSON()`, `read_json()`,
  `write_json()`).
- `processx (>= 3.9.0)` and `ps (>= 1.9.3)` kept. processx 3.9.0 adds the
  `pipeline` class and the `linux_pdeathsig` argument that condathis uses,
  and it imports ps (>= 1.9.3), so a lower ps is never installed with it.
  The binaries for Windows R 4.3, macOS R 4.3 and macOS arm64 R 4.4 are
  older (processx 3.8.6, ps 1.9.0 or 1.9.1), so those users need Rtools or
  the Xcode Command Line Tools. The README install section and
  cran-comments.md say so.
- Suggests: `curl (>= 5.0.0)` (the code uses curl only from 5.0.0 on and
  falls back to `download.file()` otherwise), `testthat (>= 3.3.2)` (from
  3.3.0, `expect_no_*()` runs the whole block; the suite has about 130 of
  them and was written and run with 3.3.2; the suite was not run with
  3.2.x).
- `Config/roxygen2/version: 8.1.1`: re-documenting with roxygen2 8.1.1
  changed no other file.

Decisions (micromamba):

- `linux-riscv64` is a micromamba platform: R reports `Linux-riscv64`.
  conda-forge has builds from 2.9.0 on, the GitHub releases from 2.10.0-0
  on (checked 2026-11-18). `install_micromamba()` aborts with
  `condathis_micromamba_not_available_for_arch` for an older version on
  that platform, before any download (`micromamba_platform_first_version`
  in `R/is_micromamba_available.R`). 2.9.0 comes from the anaconda.org
  and prefix.dev mirrors, and installs with the warning for a checksum
  that cannot be checked (GitHub has no `.sha256` file for it). Not tested
  on RISC-V hardware.
- The default stays 2.10.0-0, the latest release on GitHub and
  conda-forge on 2026-11-18. The documented "2.8.1 to 2.10.0 checked"
  ranges stay true.

Decisions (CI, `.github/workflows/r-cmd-check.yaml`):

- New jobs: `macos-26-intel` (x86_64 macOS, the newest x64 image),
  `ubuntu-24.04-arm` (Linux arm64, with `cran.r-universe.dev` as an extra
  repository in case the public RSPM lacks an arm64 binary) and
  `ubuntu-latest` with `oldrel-2` (R 4.4). The other jobs are unchanged.
- The actions are already at their latest releases: `actions/checkout@v7`
  (v7.0.1), `r-lib/actions/*@v2` (v2.14.0, no v3),
  `quarto-dev/quarto-actions/setup@v2` (v2.2.0),
  `JamesIves/github-pages-deploy-action@v4.9.0`. actionlint 1.7.12
  reports nothing.
- Not covered by CI: the source builds on Windows and macOS for R 4.3
  (every R 4.3 and 4.4 job runs on Linux).

## 26. `parse_match_spec()` writes `license_family` also as `license`

**Origin.** The jarl stage of round 8 (2026-11-18). `ms_format_canonical()`
read `extra$license` with `$`, which matches names partially: a spec with
`license_family` and no `license` is written with both,
`pkg[license=MIT,license_family=MIT]`. libmamba writes
`pkg[license_family=MIT]`. Only `formatted_spec` is affected; nothing in
condathis compares the license. The split of D20 kept the behaviour
(`extra[[field, exact = FALSE]]`). The fix is `exact = TRUE` and a test
of `pkg[license_family=MIT]`. Done 2026-11-18 (feat-run-unify D22): every
lookup in `extra` is `[[` with an exact name.

## Suggested ordering after the 0.2.0 release

1. Item 8 + 9b + 9c (lint cleanup, mechanical, low risk) as one small PR.
2. Item 7 (Windows pins) whenever conda-forge ships a fix. It is independent.
3. Item 18a/b first (rattlerthis must pass against 0.2.0), then item 2,
   then 3, then 10 and the rattlerthis half of 4, then 18c/d (the
   rattlerthis integration becomes real and documented).
4. Item 5 (supervisor option) as its own small PR.
5. (Done in 0.2.0, 2026-11-16, see `../feat-run-unify/`.) Item 6, then
   item 1 (the `run()` convergence) as the headline of the next minor
   release.
6. Item 17 as one PR (17d and 17e first: they are small and touch only
   docs and argument plumbing), and item 20 alongside.
7. Items 13 and 19 are maintainer actions. Item 15 needs only the
   pkgdown workflow change, item 16 a decision.

## 25. User-facing docs, round 8

**Origin.** The docs survey of round 8 (2026-11-18) and its verifier,
then a review of README, vignettes, help pages, NEWS, CONTRIBUTING and
cran-comments against the code after the isolation, items and
dependency stages of the same round.

Decisions, as built:

- DOC-1: the NEWS bug fix "with_sandbox_dir() deletes a sandbox that
  holds a junction" is gone. 0.1.4 never warned there: the warning and
  the deletion before return are new in 0.2.0, so it fixed unreleased
  code. The existing with_sandbox_dir() bullet now ends "(on Windows,
  also when it holds a junction)". The bullet on a linked `envs`
  directory stays: the verifier checked it against the 0.1.4 code
  (`fs::path_real()` filter in `list_envs()`, `fs::dir_delete()` in
  `create_env()`).
- DOC-2: shell builtins. `echo` is also a program on Linux and macOS
  (`/usr/bin/echo`), so README and `?run` now name `cd` and `export` as
  builtins everywhere, and `dir` and `echo` as builtins on Windows, with
  `run("cmd", "/c", "dir")` for them.
- DOC-3: the help title of `env_definition()` is "Describe an environment
  file" (it was "Create an environment from a file"; it creates nothing),
  and the vignette's Next Steps says that `create_env()` creates the
  environment from the file.
- DOC-4: README "Learn More" and the vignette's Next Steps link the
  mizu article, as `_pkgdown.yml` already lists it.
- DOC-5: not changed. Claudio Zanettini keeps `c("aut", "ctb")`, as in
  the 0.1.4 release; `"aut"` alone is cosmetic and the maintainer's call.
  The maintainer listed twice in `?condathis-package` is how roxygen
  renders it.
- `?install_packages`: `packages = NULL` with a failed environment probe
  aborts with `condathis_backend_probe_failed` (D19 of
  `../feat-run-unify/`); the help said it always returned status 0.
- `inst/WORDLIST` gained CUDA, Xcode, fs, stringr, withr and testthat's,
  which the earlier stages of round 8 added to the docs.

Checked and correct: `tools::checkRd()` on every help page,
`spelling::spell_check_package()`, `pkgdown::check_pkgdown()` (every
exported topic is in the reference index), README.md rendered from
README.qmd with `just build-readme`'s post-processing (only the intended
lines change), and the README and cran-comments claims about CRAN
binaries against the CRAN indexes of 2026-11-18.
