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

- [x] 3: added a `timeout = Inf` argument to `run()`, `run_bin()`, and
      `run_pipeline()`, threaded through to `processx` (default preserves
      current no-limit behavior exactly). Both `processx` execution paths
      covered: `processx::run()`'s native `timeout` support (verified
      empirically: kills the process, `status = -9`, and — gated by
      `error_on_status` — throws a distinct `system_command_timeout_error`
      instead of the regular status-error class) and the hand-rolled
      `run_process_with_input()`/`pump_process_io()` path used whenever
      `stdin = "|"` (new `deadline` parameter on `pump_process_io()`,
      checked each poll iteration; manually killing a `process$new()`
      object confirmed to produce the identical `status = -9` convention).
      Fixed a real pre-existing bug found along the way:
      `rethrow_error_run()`'s continue-mode synthesized result hardcoded
      `timeout = FALSE` unconditionally. New dedicated abort classes
      (`condathis_run_timeout_error`, `condathis_pipeline_timeout_error`)
      distinguish a timeout from a regular failure under
      `error = "cancel"`. `run_pipeline()` uses one shared deadline across
      the whole pipeline; found (by testing a real multi-stage pipeline,
      not by reasoning) that `processx` invalidates a process's own
      connection immediately on `kill()`, discarding any unread output —
      fixed by having `pump_process_io()` always attempt one last
      non-blocking drain in the same iteration the deadline is hit, and by
      killing only the one stage that actually timed out (after draining
      it), not every process up front. Verified live end-to-end for all
      three functions, both `error` modes, plus the specific
      output-preservation case for `run_pipeline()`. See `PLAN.md` for the
      full empirical detail. Full regression clean (see below).
- [x] 3: reused the `env_exists()` `env_name` validator across
      `install_packages()`/`get_env_dir()` (not `clean_cache()` — it has no
      `env_name` argument at all, so there's nothing to attach a validator
      to; the original finding was imprecise on this point). Extracted the
      exact type-check `env_exists()` already had into a new internal
      `validate_env_name(env_name, class, call)` (`R/validate_env_name.R`),
      parameterized by error `class` so each call site keeps its own
      already-documented class. `install_packages(packages)` now aborts
      with class `condathis_install_packages_missing_packages` for a
      missing/`NULL` `packages` argument (previously a bare base-R error,
      or no error at all until a confusing downstream failure), and with
      `condathis_install_packages_invalid_env_name` for a bad `env_name`.
      `get_env_dir()` now aborts with `condathis_get_env_dir_invalid_env_name`
      instead of silently building a nonsensical vector-of-paths for a
      multi-element `env_name`. Switched `install_packages()`'s existence
      check from `any(list_envs(...) %in% env_name)` to
      `env_exists(env_name, ...)` directly, matching every other call site.
      New man page for `validate_env_name` skipped (`@keywords internal`
      `@noRd`, matches every other internal helper in the package).

- [x] 4: removed the dead connectivity pre-check in `install_micromamba.R`
      (`check_connection()` + `get_micromamba_urls()$check_urls`). Author
      decision: delete rather than wire back in — the download path
      (`try_download_from_mirrors()`/`install_micromamba()`) already fails
      cleanly with a clear, classed error when no mirror is reachable, so
      the pre-check would only add redundant network round-trips. Deleted
      `R/check_connection.R`, its test
      (`tests/testthat/test-check_connection.R`), the commented-out call
      site, `check_urls` from `get_micromamba_urls()`
      (`R/micromamba_download_urls.R`), and the matching pieces of
      `test-install_micromamba.R` (structure-test expectation, the
      commented-out `"Connection not available"` mock test).
      `lintr`'s `commented_code_linter` confirmed clean on
      `install_micromamba.R` afterward. `test-install_micromamba.R`: 24/24
      (real network installs, not skipped).

- [x] 3/5: `method` argument — resolved by author correction, not by a fix
      in this file: it is **not** dead API surface to deprecate or drop.
      It's reserved for a pluggable-backend feature, already scoped in
      full in `.github/devdocs/feat-backend-abstraction/PLAN.md` + its
      `TODO.md` — a separate, large milestone (11 confirmed design
      decisions, own file layout, own test plan) to be implemented in a
      future session, not part of this review. No code changed here;
      removed from this checklist so it isn't tracked in two places.

## Remaining — needs a decision or is lower priority

Nothing left needing a decision. See "Lower priority / follow-up" below for
what's left in this file; the next *milestone*-sized piece of work is
`.github/devdocs/feat-backend-abstraction/` (separate session).

## Lower priority / follow-up

- [x] 4: split `install_micromamba()` / `create_env()` to reduce cyclomatic
      complexity. `install_micromamba()` 30 → under 15: extracted
      `download_compressed_and_extract()` and
      `download_uncompressed_binary()` (its two download strategies),
      merged two duplicate "already installed" checks into one guard.
      `create_env()` 29 → 0 lints: extracted
      `ensure_libmamba_pkgs_dir_workaround()`,
      `resolve_create_env_packages_arg()`,
      `resolve_create_env_platform_args()`, and
      `env_already_satisfies_request()`. Pure structural refactor, no
      intended behavior change, one extraction verified at a time.
      Caught and fixed the one real hazard *before* it shipped:
      extracting the `~/.mamba/pkgs` workaround's `withr::defer()` cleanup
      needed an explicit `envir = parent.frame()` parameter threaded into
      `withr::defer(..., envir = envir)`, otherwise the cleanup would fire
      when the new helper returns instead of when `create_env()` itself
      exits — the same scoping trap as `withr::local_tempfile()`'s
      `.local_envir` default, hit twice before elsewhere in this
      codebase. Verified empirically against a fake `HOME` (fresh
      `.mamba/pkgs` removed on caller exit; pre-existing one preserved) —
      first verification attempt gave a false-positive "bug" caused by
      `withr::local_tempdir()`'s own teardown deleting the whole fake
      `HOME` tree, re-tested with a non-auto-cleaned fake `HOME` to get
      the real answer. See `PLAN.md` for full detail. Full regression:
      `test-install_micromamba.R` (24/24), `test-create_env.R` (36/36),
      `test-create_nested_env.R` (5/5), `test-install_packages.R`
      (14/14), `test-run.R` (49/49), `test-list_envs.R` (11/11) — all
      clean. `lintr::cyclocomp_linter(complexity_limit = 15L)`: neither
      function flagged anymore.
- [ ] 5: `\dontrun{}` → `\donttest{}` policy decided (see `PLAN.md`,
      "Every core-workflow example is `\dontrun{}`"), not yet implemented.
      - [ ] Switch all 12 affected functions' `@examples` from `\dontrun{}`
            to `\donttest{}`, each wrapped in
            `tryCatch({...}, error = function(e) invisible(NULL))`:
            `clean_cache`, `create_env`, `env_exists`, `install_micromamba`,
            `install_packages`, `list_envs`, `list_packages`, `remove_env`,
            `run_bin`, `run_pipeline`, `run`.
      - [ ] `with_sandbox_dir()`: move to a plain, always-run example
            instead (no network dependency, doesn't need `\donttest{}` at
            all — the one exception among the 12).
      - [ ] `run_bin()`: fix the example content first (it currently
            references a `my-env` that's never created, so it would fail
            even under `\donttest{}` as currently written) — add a real
            `create_env()` setup step, matching the other examples.
      - [ ] Regenerate `man/*.Rd` (`roxygen2::roxygenize()`) after editing.
      - [ ] Spot-check at least one converted example actually runs clean
            with `R CMD check --run-donttest` (or `tools::Rd2ex()` +
            `source()`) before considering this done, not just that it
            parses.
