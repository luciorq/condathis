# TODO: package-wide review improvements

See `PLAN.md` for full findings, severities, the checksum empirical data,
and design decisions.

## Done

- [x] Full package review (52 R files, ~7.4k LOC): security, correctness,
      API consistency, dead code, complexity, testing/docs. Findings +
      severities recorded in `PLAN.md`.
- [x] Empirical checksum investigation: downloaded + hashed the micromamba
      binary from every mirror × strategy × 5 platforms for v2.8.1-0.
      Result: GitHub `.sha256` is a universal, correct target for the final
      binary everywhere; `tools::sha256sum()` (base R, already imported,
      R >= 4.5) removes the system-dependency concern; `micro.mamba.pm`
      mirror found broken. Recommended design written up.

## Author decisions — both received and implemented

**Decision 1 (checksum policy):** warn-and-continue on mismatch *or* on the
hashing tool itself failing (never block an install either way). Implement
`tools::sha256sum()` gated on R >= 4.5 *and* the function actually existing
in the `tools` namespace; fall back through other implementations; keep
`digest` as a `Suggests` dependency; make the system-CLI fallback provably
robust, not just "exit status 0" — verify it actually produces the expected
output across OSes.

- [x] Rewrote `compute_sha256()` (`R/install_micromamba.R`) with the full
      priority chain: `tools::sha256sum()` (new `has_tools_sha256sum()`
      gate: R >= 4.5 *and* namespace presence) → `digest::digest()`
      (`Suggests`, added to `DESCRIPTION`) → a system `sha256sum`/`shasum`,
      **only trusted after passing a known-answer test** (new
      `sha256_command_is_trustworthy()`): runs the candidate command
      against the standard SHA-256 test vector for `"abc"`
      (`ba7816bf8f01cfea...`, cross-checked live against
      `tools::sha256sum()`, `digest::digest()`, `openssl::sha256()`, and
      Python's `hashlib` — all agree — before hardcoding it). New
      `run_sha256_command()` additionally rejects any output that isn't
      exactly 64 hex characters, regardless of exit status. Every step
      wrapped so a failure anywhere falls through to the next; returns
      `NA_character_` (never errors) if nothing works.
- [x] Re-enabled the `verify_micromamba_checksum()` call site (previously
      commented out) — its mismatch handling already warned rather than
      aborted, matching the chosen policy exactly, so no change was needed
      there. Verified live end-to-end: a real install produces no warning
      (hash matches); feeding an unrelated file as `bin_path` produces a
      clear mismatch warning with expected/actual hashes, without erroring.
- [x] R floor left at `>= 4.3` (not bumped to 4.5) — `has_tools_sha256sum()`
      gates the base-R path and everything falls back correctly on older R.
- [x] New `tests/testthat/test-compute_sha256.R` (13 tests): the R-version
      gate, the system-tool self-test (accepts a real tool, rejects a
      nonexistent one, rejects a mocked "liar" that reports the wrong
      hash), malformed-output rejection, the full priority chain forced
      through each fallback level via mocking, the "nothing available"
      path never erroring, and a live network test confirming
      `verify_micromamba_checksum()` warns-not-aborts on a real mismatch.
      Caught and fixed a real scoping bug in my own first draft of the test
      helper along the way (`withr::local_tempfile()`'s default
      `.local_envir` deleted the file before `compute_sha256()` ever read
      it — same class of gotcha as `with_sandbox_dir()`'s documented
      behavior from the previous review pass).
- [x] Full regression: `test-compute_sha256.R` (13/13),
      `test-install_micromamba.R` (26/26, real network installs),
      `test-check_connection.R`, `test-check_micromamba_version.R`,
      `test-run.R` all clean.

**Decision 2 (`run()` auto-create):** `run()` should never create the
*target* environment when it's missing — only error. The existing
auto-create-`"condathis-env"`-regardless-of-`env_name`, was a workaround
for an old `micromamba` requirement (root prefix needed *some* environment
to exist before `micromamba run` worked at all), status in the current
pinned version unconfirmed by the author.

- [x] Confirmed empirically before changing anything: a fresh sandboxed
      install root, with only a custom-named environment ever created
      (`"condathis-env"` never touched), runs commands in that custom
      environment correctly with the current pinned `micromamba`
      (`2.8.1-0`) — the old requirement does not reproduce. The
      auto-create-as-workaround is confirmed unnecessary today.
- [x] Rewrote `R/run.R`'s environment-existence handling: still
      auto-creates `"condathis-env"` when it's missing *and* is the actual
      target (the deliberate, documented default-env convenience — kept
      unchanged) but no longer touches it as a side effect when targeting
      a different, missing environment. A missing custom `env_name` now:
      aborts with new class `condathis_run_env_not_found` under
      `error = "cancel"` (default); returns a `status = 127` result under
      `error = "continue"`, without creating anything — mirrors
      `run_pipeline()`'s existing `condathis_pipeline_env_not_found`
      behavior for the identical situation, for consistency.
      `run_bin()` was already correct here (already falls back to running
      outside any managed environment, already tested) and needed no
      change.
- [x] New tests in `test-run.R`: missing custom env × `error = "continue"`
      (returns 127, doesn't create anything), × `error = "cancel"` (aborts
      with the new class), and an explicit check that
      `"condathis-env"` is never created as a side effect of targeting an
      unrelated missing environment — the exact bug being fixed. Updated
      `@param env_name`/`@param error` docs (and regenerated `man/run.Rd`).
- [x] Full regression: `test-run.R` (44/44), plus every file that calls
      `run()` (`test-create_nested_env.R`, `test-list_envs.R`,
      `test-run_output_file.R`, `test-create_env.R`, `test-rethrow_error.R`,
      `test-run_verbose_levels.R`) — all clean, confirming no existing test
      relied on the old side-effect-creation behavior.

## Clear-cut — implemented, not yet committed

- [x] 2a: `list_envs()` regex-injection. Extracted the filtering into a new
      pure helper `condathis_env_names(envs_str, env_root_dir)`
      (`R/list_envs.R`) matching the root via `stringr::fixed()` instead of
      treating it as a regex. Proved the bug was real first (simulated the
      old behavior: a decoy path with a `.`-adjacent character wrongly
      matched); new test confirms it's gone
      (`test-list_envs.R`: "condathis_env_names matches the install root
      literally, not as a regex"). `test-list_envs.R`: 11/11.
- [x] 4: added internal `is_windows()`/`is_macos()` helpers to
      `R/get_sys_arch.R` (single source of truth built on `get_sys_arch()`,
      consistent with the existing `with_mocked_bindings(get_sys_arch=...)`
      test pattern). Replaced all genuinely-redundant call sites:
      `resolve_env_bin_path.R` (both — one had a local variable literally
      named `is_windows`, renamed to `on_windows` to avoid shadowing the new
      function), `micromamba_bin_path.R`, `create_env.R`, `run_pipeline.R`,
      `run_internal_native.R` (was the odd one out, using
      `identical(Sys.info()["sysname"], c(sysname = "Windows"))`), and
      `get_condathis_path.R`'s Darwin check → `is_macos()`.
      **Deliberately left unchanged:** `condathis-package.R:38`'s
      `identical(.Platform$OS.type, "windows")` inside `.onLoad()` — it's
      the most dependency-free check available (no `Sys.info()`/`stringr`
      needed) at the earliest, most fragile point in the package lifecycle;
      unifying it would trade robustness for consistency with no real
      benefit. New test: `test-get_sys_arch.R` (added to the existing file
      rather than a new one, proportional to the size of what's tested) —
      9/9. Full regression: `test-create_env.R`, `test-run_pipeline.R`,
      `test-get_install_dir.R`, `test-micromamba_bin_path.R`, `test-run.R`
      all clean.
- [x] 3 (narrowed after investigation): dropped the dead `micro.mamba.pm`
      mirror from `get_micromamba_urls()`'s `compressed` and `check_urls`
      lists. The "harden `try_download_from_mirrors()`" half of this item
      turned out to be unnecessary — verified empirically that **both**
      `curl::curl_download()` and `utils::download.file()` already
      correctly error/warn on `micro.mamba.pm`'s HTTP 404 (confirmed live:
      `curl_download()` throws `"HTTP response code said error"`;
      `download.file()` warns `"HTTP status was '404 Not Found'"`), and
      `download_micromamba_file()`'s existing `tryCatch` already converts
      both into `FALSE` — so the mirror loop already correctly skips to the
      next candidate today. No corrupt-file/silent-success gap actually
      exists; that part of the original finding was an unverified
      assumption, corrected here rather than "fixed" with redundant code.
      Updated the one test that hardcoded the old 4-mirror structure
      (`test-install_micromamba.R`). `test-install_micromamba.R`: 26/26
      (real network install, not skipped).

## Remaining — needs a decision or is lower priority

- [ ] 4: remove or re-wire the dead connectivity pre-check in
      `install_micromamba.R` (`check_connection()` +
      `get_micromamba_urls()$check_urls`, lines ~94–110) — a *separate*
      commented-out block from the checksum path, unaffected by the
      checksum decision above and still pending its own call: wire it back
      in (fail fast before creating any directories if no mirror is
      reachable) or delete `check_connection()` and `check_urls` entirely.
      `lintr`'s `commented_code_linter` still flags 5 lines here.
- [ ] 3: add a `timeout` argument to `run()`/`run_bin()`/`run_pipeline()`
      (thread through to `processx`), default `Inf`/`NULL` preserving
      current behavior.
- [ ] 3: reuse the `env_exists()` `env_name` validator across
      `install_packages()`/`clean_cache()`/`get_env_dir()`; give
      `install_packages(packages)` a `condathis_*`-classed missing-arg
      error. Switch `install_packages()`'s existence check to `env_exists()`.
- [ ] 3/5: `method` argument — decide `lifecycle::deprecate_soft()` vs
      drop; likely a follow-up, low urgency.

## Lower priority / follow-up

- [ ] 4: split `install_micromamba()` / `create_env()` to reduce cyclomatic
      complexity — only with full test cover; not urgent.
- [ ] 5: consider `\donttest` for a couple of core examples so they get
      some check-time exercise.
