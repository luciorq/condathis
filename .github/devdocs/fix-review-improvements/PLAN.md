# PLAN: package-wide review improvements

An extensive, evidence-based review of the whole package (not just a diff),
requested after the output-contract-consistency work
(`.github/devdocs/fix-output-contracts/`) wrapped up. Findings are ordered
by severity; each has a `file:line` anchor and was confirmed by reading the
code / running probes, not from memory.

This is a distinct concern from `fix-output-contracts` (return-type/class
consistency) and `feat-pipeline` (the pipeline feature + Windows CI). It
covers correctness bugs, dead code, API asymmetries, a security gap, and
maintainability.

## Severity 1 — security / integrity

### Checksum verification of the downloaded `micromamba` binary is disabled

`R/install_micromamba.R` downloads an executable from one of four mirrors
and runs it with no integrity check. The verification machinery exists but
is dead: `verify_micromamba_checksum()` (line ~269), `compute_sha256()`
(line ~367), `get_micromamba_urls()$sha256`, but the call site is commented
out (lines ~216–221). Transport is HTTPS, so this is defense-in-depth, not
a trivially-exploitable hole — but there is zero protection against a
corrupted download or a compromised mirror, and the `.sha256` files are
already being fetched-for and discarded.

**Important maintainer context (from the author):** the code was commented
out on purpose. Initial testing found hashes appearing to differ across
OSes, mirrors, and the compressed-vs-uncompressed download strategies; plus
it adds a system dependency (a `sha256sum`/`shasum` tool) and a big
maintenance burden if hashes can't be retrieved automatically during
development. So this must be "highly reviewed for consistency" before any
re-enable — a naive re-enable would reintroduce the exact failures that got
it disabled.

**Empirical investigation done (2026-07-24), version 2.8.1-0 (current
default), all real downloads + hashes:**

| platform | GitHub standalone vs its `.sha256` | conda-forge (prefix.dev) compressed → extracted `bin/micromamba` vs same `.sha256` |
|---|---|---|
| linux-64 | MATCH | MATCH |
| linux-aarch64 | MATCH | MATCH |
| osx-64 | MATCH | MATCH |
| osx-arm64 | MATCH | MATCH |
| win-64 | MATCH | MATCH |

Also cross-checked linux-64 against the GitHub-compressed and
anaconda.org-compressed archives: both extract to the identical binary too.

**Conclusions from the data:**
1. The GitHub-published `.sha256` is a **universal, correct target for the
   final binary** — same value whether the binary came standalone or was
   extracted from any conda-forge mirror, on every platform, for this
   version. This exactly matches the (correct) intent already written in
   the `install_micromamba.R:236–244` comment.
2. The "inconsistency across mirrors/strategies" is almost certainly from
   hashing the **archive** (which legitimately differs per mirror/packaging)
   instead of the **extracted binary**. Verify the final binary, never the
   archive.
3. **No hardcoded hashes, no per-version maintenance:** the `.sha256` is
   fetched dynamically per version+platform from the matching GitHub
   release. The existing dead code already does this. The author's
   maintenance-burden concern is largely unfounded *if* verification targets
   the dynamically-fetched `.sha256`.
4. **The system-dependency concern is now mostly solved:**
   `tools::sha256sum()` exists in base R (and `tools` is already an
   `Imports`), added in **R 4.5.0**. The package requires only R >= 4.3, so
   on R >= 4.5 verification needs **zero new dependencies and no system
   tool**; on R 4.3/4.4 a graceful fallback (system `sha256sum`/`shasum`,
   else skip-with-message) covers the rest.
5. **Separate real bug found while probing:** the `micro.mamba.pm` mirror
   (compressed URL #2) is **broken** for the pinned version —
   `https://micro.mamba.pm/api/micromamba/linux-64/2.8.1-0` returns
   `{"detail":"No version found for linux-64/2.8.1-0"}` (50 bytes of JSON,
   not a binary). It doesn't bite today only because GitHub is mirror #1 and
   succeeds first. See severity-3 item below.

**Recommended design (feasible, low-risk):**
- Verify the **final installed binary** (post-extract / post-download)
  against the dynamically-fetched GitHub `.sha256` for the exact
  version+platform. Never hash the archive.
- Compute the hash with `tools::sha256sum()` when available (R >= 4.5);
  fall back to system `sha256sum`/`shasum` on older R; if neither is
  available, **skip with a message**, never error.
- Make a mismatch **non-fatal by default** (warn loudly, don't block the
  install) — this is the key reliability guard: even if some future
  edge case diverges, it can never break an install, only surface a
  warning. A stricter opt-in mode (e.g. `verify = "strict"`) can gate the
  install for users who want it.
- Drop the dead `micro.mamba.pm` entry (or make the download robust to a
  mirror returning JSON — see severity 3).

**Open policy decisions for the author (do not implement without a call):**
- Mismatch handling: warn-by-default (recommended) vs. fatal.
- R floor: keep `>= 4.3` with a fallback, or bump to `>= 4.5` for the clean
  base-R-only path (drops R 4.3/4.4; affects the CI oldrel job).

**Status: DONE.** Author decided: warn-and-continue on mismatch *or* on the
hashing tool failing; R floor stays >= 4.3 with a fallback (not bumped to
4.5); keep `digest` as `Suggests`; make the system-CLI fallback provably
robust (not just exit-status checking). Implemented exactly that — see
`TODO.md` for the full detail, including the known-answer self-test added
for the system-CLI fallback and the 13 new tests. `verify_micromamba_checksum()`
already warned rather than aborted on mismatch, so its re-enable needed no
behavior change, only re-enabling the call site and fixing
`compute_sha256()`.

## Severity 2 — correctness (latent bugs)

### 2a. `list_envs()` uses a filesystem path as a regex

`R/list_envs.R:68`:
`envs_str <- envs_str[stringr::str_detect(c(envs_str), env_root_dir)]`.
`env_root_dir` (from `get_install_dir()`, e.g. `~/.local/share/R/condathis`)
is used as a **regex pattern**. The `.` in `.local` matches any character,
so `/home/user/Xlocal/share/R/condathis/...` would also match. It finds the
right envs in practice but is a false-positive risk and fragile. Fix:
`stringr::str_detect(envs_str, stringr::fixed(env_root_dir))`, or a proper
path-prefix test (`fs::path_has_parent()` / `startsWith()`).

**Status: DONE — see `TODO.md` for implementation detail.**

### 2b. `run()` auto-creates the *wrong* environment

`R/run.R:152–160` hardcodes `env_exists("condathis-env")` regardless of the
`env_name` argument. So `run("samtools", env_name = "samtools-env")` when
`samtools-env` doesn't exist (a) creates an empty `condathis-env` the caller
never asked for, then (b) fails with "environment samtools-env not found" —
the auto-create didn't help the real target. The doc claim ("If the
*default* environment does not exist, it is created") is technically true,
but the behavior is surprising and the wasted side-effect env is confusing.
Options: auto-create `env_name` itself, or only run the base-env check when
`env_name` is the default. Needs a small design decision (which behavior is
intended) — see Open questions.

**Status: DONE.** Author decided: neither option above — `run()` should
never create the *target* environment when missing, only error (matching
`run_pipeline()`'s existing behavior for the same situation). The
hardcoded `"condathis-env"` check existed as a workaround for an old
`micromamba` requirement (the root prefix needed *some* environment before
`micromamba run` worked at all); confirmed empirically (fresh sandbox,
only a custom env ever created, `"condathis-env"` never touched) that this
no longer reproduces with the current pinned `micromamba`. See `TODO.md`
for the full implementation detail.

## Severity 3 — API design & consistency

- **`run()` vs `run_bin()` auto-create asymmetry.** `run()` auto-creates the
  base env; `run_bin()` creates nothing. Odd remaining asymmetry after the
  recent parity work. (`R/run.R` vs `R/run_bin.R`.)
- **`method` argument is dead API surface.** `R/run.R`, `R/create_env.R`:
  soft-deprecated, documented as no-op, still `arg_match(c("native",
  "auto"))`d, both branches identical. Either fully deprecate via
  `lifecycle` or drop it — it clutters the two most-used signatures.
- **No `timeout` argument** on `run()`/`run_bin()`/`run_pipeline()` despite
  `processx` supporting it. A hung CLI tool hangs the R session with no
  built-in escape. Real feature gap. **Status: DONE.**

  New `timeout = Inf` argument on `run()`, `run_bin()`, and `run_pipeline()`.
  Threaded through both `processx` execution paths in the codebase:
  - `processx::run()` (used directly by `native_cmd()`'s non-stdin branch
    and `run_bin()`'s non-stdin branch): `timeout` passed straight through;
    `processx`'s own native timeout support does the rest. Confirmed
    empirically before writing any code: on expiry `processx::run()` kills
    the process (`status = -9`, `timeout = TRUE` in its result) and, with
    `error_on_status = TRUE`, throws a distinct condition class
    `system_command_timeout_error` (inherits `system_command_error`,
    `rlib_error_3_0`, `rlib_error`, `error`, `condition`) instead of the
    regular `system_command_status_error` — with `error_on_status = FALSE`
    it returns normally, no error.
  - `run_process_with_input()` (the hand-rolled `processx::process$new()` +
    `pump_process_io()` path used whenever `stdin = "|"`, which
    `processx::run()` itself doesn't support): `pump_process_io()`
    (`R/pump_process_io.R`) gained a `deadline` parameter (an absolute
    `proc.time()[["elapsed"]]` timestamp, default `Inf`) checked each loop
    iteration; on expiry it stops draining, reports `timeout = TRUE`, and
    the caller kills the process. Confirmed empirically that manually
    killing a `process$new()` object (`proc$kill(); proc$wait()`) produces
    the identical `status = -9` convention `processx::run()` uses natively,
    so both paths report timeouts identically regardless of which one ran
    the command. `run_process_with_input()` then throws the same
    `system_command_timeout_error` class (hand-rolled via `rlang::abort()`,
    since it doesn't inherit `rlib_error_3_0` automatically the way
    `processx`'s own condition does — added explicitly to
    `rethrow_error_run()`'s caught classes to compensate), gated by
    `error_on_status` exactly like a normal failure — **not** unconditional
    (an earlier design draft got this wrong and was self-corrected before
    writing code: a timeout must respect `error = "continue"` the same way
    a regular failure does).

  Found and fixed a real pre-existing bug in `rethrow_error_run()` along the
  way: its "continue mode" synthesized-result branch hardcoded
  `timeout = FALSE` unconditionally, which would have silently misreported
  a genuine timeout as a normal failure once this feature existed. Also
  added a distinct abort class per surface for the cancel-mode case
  (`condathis_run_timeout_error` for `run()`/`run_bin()`,
  `condathis_pipeline_timeout_error` for `run_pipeline()`) instead of
  reusing the regular status-error class, so callers can `tryCatch()`
  a timeout specifically.

  `run_pipeline()` needed its own design since it manages multiple
  `processx::process$new()` stages directly with real inter-process pipes:
  `timeout` is a single shared deadline for the *whole* pipeline (not
  per-command), computed once and passed to every stage's
  `pump_process_io()` call. A subtlety found only by testing against a real
  multi-stage pipeline, not by reasoning: `kill()` on a `processx` process
  immediately invalidates its own connection object, discarding anything
  still unread — confirmed empirically (`p$kill(); p$wait(); p$read_output(-1)`
  errors with "Invalid (uninitialized or closed?) connection object", even
  for output already sitting in the OS pipe buffer). An early draft handled
  the shared deadline by killing every process as soon as the first stage
  timed out, which lost real output later stages had already produced but
  not yet drained. Fixed two ways: (1) `pump_process_io()` always attempts
  one last non-blocking (`poll_io(0)`) drain in the same iteration the
  deadline is hit, instead of bailing out before reading anything, so
  already-buffered data is never lost; (2) `run_pipeline()` kills only the
  one stage whose own drain call reported the timeout (after having drained
  it), not every process up front — killing that stage closes its stdout
  pipe, so the next stage sees EOF and finishes draining normally on its
  own. Verified live: a 2-stage pipeline (`sh -c "echo hello; sleep 5" |
  cat`) with `timeout = 1` correctly preserves `"hello\n"` in the final
  result even though both processes end up killed.
- **Uneven input validation.** `install_packages()` and `clean_cache()`
  validate nothing; `install_packages(packages)` with no args gives a bare
  base-R error, not a `condathis_*` class; `get_env_dir()` doesn't validate
  `env_name`. A shared `env_name` validator (the one just added to
  `env_exists()`) could be reused. **Status: DONE** (except `clean_cache()`
  — see note below).

  New internal `validate_env_name(env_name, class, call)` helper
  (`R/validate_env_name.R`): the exact type-check `env_exists()` already
  had (single, non-missing, non-`NA` character string), extracted so every
  call site can reuse it while keeping its own distinct, already-documented
  error class via the `class` argument. `env_exists()` itself now calls it
  instead of inlining the check. `get_env_dir()` now calls it too (class
  `condathis_get_env_dir_invalid_env_name`) — previously a bad `env_name`
  (e.g. a length-2 vector) silently produced a nonsensical vector of paths
  via `fs::path()`'s vectorization instead of erroring. `install_packages()`
  now calls it as well (class
  `condathis_install_packages_invalid_env_name`), and separately gained a
  proper `condathis_install_packages_missing_packages`-classed abort for a
  missing or `NULL` `packages` argument (previously a bare base-R "argument
  is missing" error, or — for explicit `NULL` — no error at all until
  `native_cmd()` failed confusingly downstream).

  Deliberately did **not** touch `clean_cache()`: it has no `env_name`
  argument at all (cache cleanup isn't tied to a specific environment), so
  there's nothing for the shared validator to attach to — the original
  finding's phrasing was imprecise on this point.
- **`install_packages()` existence check reads backwards.**
  `R/install_packages.R:66–69`: `any(list_envs(...) %in% env_name)` — works
  but awkward; `env_exists(env_name)` (or `env_name %in% list_envs()`) is
  clearer and matches every other call site. **Status: DONE** — switched to
  `env_exists(env_name, verbose = verbose_list$internal_verbose)` directly.
  Deliberately *not* used inside `get_env_dir()` itself: `env_exists()`
  calls `list_envs()`, a real `micromamba` invocation, which would make a
  pure path-builder function do heavy I/O and require `micromamba` to
  already be installed — `get_env_dir()` only needs the lightweight type
  check, which is exactly why the validator was extracted as its own
  function separate from `env_exists()`.
- **`micro.mamba.pm` dead mirror** (see severity-1 probe). **Status: DONE**
  — dropped from `get_micromamba_urls()`'s `compressed` and `check_urls`
  lists. The "harden `try_download_from_mirrors()`" half of the original
  finding was corrected, not implemented: verified live that both
  `curl::curl_download()` and `utils::download.file()` already correctly
  error/warn on this mirror's HTTP 404, and `download_micromamba_file()`
  already converts that into `FALSE` — there was never a corrupt-file/
  silent-success gap to harden against. See `TODO.md` for the verification
  detail.

## Severity 4 — dead code & maintainability

- **Unreachable functions:** `check_connection()` (`R/check_connection.R`,
  only referenced in commented-out code at `install_micromamba.R:97`; has a
  live test hitting github.com), `get_micromamba_urls()$check_urls` (built,
  never consumed), plus the checksum trio if not re-enabled. Wire back in or
  delete. **Status: DONE** — author decision: delete. Reasoning that led to
  the recommendation: `try_download_from_mirrors()`/`install_micromamba()`
  already fail cleanly with a clear, classed error
  (`condathis_install_error_missing_bzip2`, message mentions "network
  issues") when no mirror is reachable — a connectivity pre-check would
  only add redundant network round-trips before every real attempt and
  avoid creating two (harmless, now-empty) directories a little earlier.
  Same shape of finding as the `micro.mamba.pm` mirror-hardening item
  above: the original review flagged a gap that, on closer inspection, the
  existing error path already covers.

  Deleted `R/check_connection.R` and its test
  (`tests/testthat/test-check_connection.R`), the commented-out call site
  in `install_micromamba.R`, and `get_micromamba_urls()`'s `check_urls`
  element (`R/micromamba_download_urls.R`) plus its doc line. Updated
  `test-install_micromamba.R`'s structure test (expected names, no more
  `check_urls`) and removed its own commented-out
  `"Connection not available"` test (mocked the now-deleted function).
  `lintr::lint("R/install_micromamba.R", linters = commented_code_linter())`
  confirmed clean afterward. Full regression:
  `test-install_micromamba.R` 24/24 (real network installs, not skipped).
- **Commented-out code blocks:** ~12 in `install_micromamba.R` (`lintr`
  `commented_code_linter`). Remove or restore. **Status: DONE** — the
  connectivity pre-check block above was the only one; removed as part of
  the same change.
- **Three different "is Windows?" idioms, no shared helper.** **Status:
  DONE** — added internal `is_windows()`/`is_macos()` (`R/get_sys_arch.R`)
  and replaced every genuinely-redundant call site; deliberately left
  `condathis-package.R:38`'s `.Platform$OS.type` check alone (runs inside
  `.onLoad()`, most dependency-free option at the earliest point in the
  package lifecycle — see `TODO.md` for the reasoning). See `TODO.md` for
  the full list of call sites touched.
- **High cyclomatic complexity:** `parse_match_spec()` 77, `pump_process_io()`
  49, `parse_match_spec` sub-fns 48/37, `install_micromamba()` 30,
  `create_env()` 29 (`lintr` limit 25). Parsers are well-tested so risk is
  contained; `install_micromamba()`/`create_env()` are the ones worth
  splitting since they mix I/O with control flow and are less exhaustively
  tested. Lower priority — refactor only with care and full test cover.

## Severity 5 — testing & docs

### Every core-workflow example is `\dontrun{}` — policy decided, not yet implemented

**Status: policy decided (2026-07-27), implementation not started.**

12 of the 17 exported functions wrap their entire `@examples` block in
`\dontrun{}`: `clean_cache`, `create_env`, `env_exists`, `install_micromamba`,
`install_packages`, `list_envs`, `list_packages`, `remove_env`, `run_bin`,
`run_pipeline`, `run`, `with_sandbox_dir`. None of these are exercised by
`R CMD check`, so they can silently rot. The remaining 5
(`get_env_dir`, `get_install_dir`, `get_sys_arch`, `micromamba_bin_path`,
`parse_output`) already have runnable examples and need no change — they
don't touch the network or `micromamba` at all.

**Verified CRAN semantics before deciding anything** (R's own bundled
"Writing R Extensions" manual, `R RHOME`/doc/manual/R-exts.html, the
`\examples{}` section):

- `\dontrun{}`: verbatim text, never executed by `example()` or
  `R CMD check`, ever. Reserved for things that are illustrative only.
- `\donttest{}`: **must be correct, runnable R code** (unlike `\dontrun{}`).
  Executed by `example()`. **Not** executed by a plain `R CMD check`
  unless `--run-donttest` is passed, and confirmed (via the user, who has
  directly observed CRAN's own process) that `R CMD check --as-cran` —
  CRAN's own submission/incoming check — does **not** run `\donttest{}`
  examples either. However, CRAN maintainers are known to periodically run
  *all* examples (including `\donttest{}`) by hand on their own machines,
  which may have no internet access — so `\donttest{}` code must survive
  that gracefully, not error. This exactly matches the manual's own
  guidance for `\donttest{}`: *"Use e.g. `capabilities()` or
  `nzchar(Sys.which("someprogram"))` to test for features needed in the
  examples wherever possible, and you can also use `try()` or
  `tryCatch()`."*

**Decision:** switch the 12 `\dontrun{}` examples to `\donttest{}`, each
wrapped in a `tryCatch()` (or equivalent) so a missing network connection
or a failed `micromamba` download/install is swallowed silently rather
than erroring — satisfying both CRAN's occasional manual, potentially
airgapped re-run *and* giving real end-users a working, live demonstration
when they call `example("create_env")` themselves with network access,
which `\dontrun{}` can never provide.

**Recommendation on *how* to guard them, since this was asked for
explicitly:** wrap the whole example body in a broad
`tryCatch({...}, error = function(e) invisible(NULL))` rather than a
narrower upfront connectivity check (e.g. `condathis:::check_connection()`
before attempting anything). Reasoning: the broad `tryCatch` catches
*every* failure mode a network-restricted or otherwise atypical machine
could hit — DNS failure, a specific mirror being blocked while others
aren't, disk-permission issues in the check sandbox, a slow timeout — not
just "no internet at all." A narrow precondition check only guards against
the one failure mode it explicitly tests for and could still let the
example error on a different one. This is the same "many failure modes,
one broad catch" reasoning already applied elsewhere in this codebase
(e.g. `download_micromamba_file()`'s own `tryCatch`/`warning` handling).

**Two functions need something extra, found while auditing all 12, not
just a markup change:**

- **`with_sandbox_dir()`'s example doesn't need network or `micromamba` at
  all** — it just prints paths inside a sandboxed environment
  (`print(fs::path_home())`, `print(tools::R_user_dir("condathis"))`).
  It's miscategorized: this one should just become a plain, always-run
  example, not `\donttest{}` at all — the *only* one of the 12 in that
  situation.
- **`run_bin()`'s current example is already broken as written**,
  independent of the `\dontrun{}`/`\donttest{}` question: it says
  `# Example assumes that 'my-env' exists and contains 'python'` but never
  creates `my-env` — it would fail immediately if actually run, `\donttest{}`
  or not. Needs an actual `create_env()` setup step added (matching every
  other example's pattern) before it can be meaningfully switched, not just
  a tag swap.

**Not started** — this is documented policy, ready to implement, but no
`.R`/`.Rd` files have been touched for this yet.

## What's already solid (for balance)

`parse_match_spec()`/`version_spec_contains()` cross-validated against real
`libmambapy`. The run/pipeline I/O layer is hardened against
empirically-confirmed deadlock/truncation/binary bugs. Tight dependency
footprint (`curl` correctly optional). Error classes well-designed and, post
`fix-output-contracts`, well-tested. `R CMD check` is otherwise clean (no
NOTEs on structure; the only WARNINGs seen were artifacts of a
`--no-build-vignettes` build).

## Open questions — both answered and implemented

1. **Checksum policy** (severity 1): warn-by-default (chosen), not fatal.
   R floor stays 4.3-with-fallback (chosen), not bumped to 4.5. See
   severity-1 section and `TODO.md` for the implementation.
2. **`run()` auto-create** (2b): neither of the two options sketched above
   — the target environment is never auto-created, only the default env
   (existing convenience, kept), and a missing custom `env_name` now
   errors. See the 2b section and `TODO.md` for the implementation.
