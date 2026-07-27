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

## Blocked on author decision (see PLAN.md "Open questions")

- [ ] Checksum verification re-enable — design ready, needs policy call
      (warn-vs-fatal on mismatch; R floor 4.3-fallback vs 4.5).
- [ ] `run()` auto-create-wrong-env (2b) — needs a call on intended
      behavior before fixing.

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

- [ ] 4: remove or re-wire dead `check_connection()` +
      `get_micromamba_urls()$check_urls`; clean commented-out blocks in
      `install_micromamba.R` (contingent on the checksum decision, since
      some of that dead code is the checksum path).
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
