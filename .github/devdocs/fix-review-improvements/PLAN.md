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
  **Status: not dead — redirected, not a review fix.** Author correction
  (2026-07-27): `method` is **not** to be deprecated or dropped. It's the
  reserved argument for a pluggable-backend feature (`"native"`/`"auto"`
  today, eventually `"micromamba"`/`"rattler"`/`"docker"`/`"singularity"`),
  already fully scoped in its own design doc:
  `.github/devdocs/feat-backend-abstraction/PLAN.md` +
  `TODO.md` (11 confirmed design decisions, ready for implementation, none
  of it built yet). That milestone is large enough to need its own
  session — out of scope for this review pass. Removed from this file's
  scope entirely; tracked exclusively under `feat-backend-abstraction/`
  from now on, not duplicated here.
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
  `create_env()` 29 (against `lintr::cyclocomp_linter()`'s actual default
  limit of 15 — no `.lintr` config exists in the repo, so "limit 25" in the
  original finding was unverified; corrected here). Parsers left alone
  (well-tested, `pump_match_spec()`/`pump_process_io()` out of scope —
  same reasoning as before). **Status: DONE for `install_micromamba()`/
  `create_env()`** — the two the finding itself called out as "worth
  splitting since they mix I/O with control flow and are less exhaustively
  tested."

  Both were already naturally segmented — `install_micromamba()` by its own
  section comments (`# --- Strategy 1 ---` etc.), `create_env()` less so,
  needed the boundaries chosen. Pure structural extraction, zero intended
  behavior change, one helper extracted and test-verified at a time (not
  batched):

  - `install_micromamba()` (30 → under 15): extracted
    `download_compressed_and_extract()` (the `.tar.bz2` download + extract
    + cleanup strategy, ~50 lines, previously the single biggest
    contributor — nested `if`s plus a two-handler `tryCatch()`) and
    `download_uncompressed_binary()` (the raw-binary fallback strategy).
    Both return a plain logical (`extraction_succeeded`); the parent
    function's own two-strategy sequencing collapses to two function
    calls. Also merged the two near-duplicate "already installed, not
    forcing" `if` checks into one guard clause with a nested message-only
    `if`, removing one duplicate condition (identical observable
    behavior — message only under `!dl_quiet_flag`, same as before).
  - `create_env()` (29 → 0 lints): extracted
    `ensure_libmamba_pkgs_dir_workaround()` (the `~/.mamba/pkgs`
    workaround + `withr::defer()` cleanup — see the scoping note below),
    `resolve_create_env_packages_arg()` (the `packages`/`env_file`
    resolution, including the `condathis_create_missing_env_file` abort),
    `resolve_create_env_platform_args()` (the `--platform` resolution),
    and `env_already_satisfies_request()` (the deepest block — the
    already-exists-and-satisfies-deps early return, now a single
    `if (!is.null(early_result)) return(early_result)` at the call site).
    Incidentally dropped one stray commented-out line
    (`# verbose = verbose_list$internal_verbose`) that was directly inside
    the code being moved and already flagged by `commented_code_linter`;
    left every other comment/`TODO` untouched.

  **The one real hazard, caught before it shipped, not after:**
  extracting the `withr::defer()` cleanup into
  `ensure_libmamba_pkgs_dir_workaround()` is exactly the
  `withr::local_tempfile()`-style scoping trap already hit twice elsewhere
  in this codebase — `withr::defer()`'s own default `envir` is *its
  immediate caller* (the new helper's frame), so a naive extraction would
  make the cleanup fire the instant the helper returns, not when
  `create_env()` itself exits. Fixed by giving the helper its own
  `envir = parent.frame()` parameter (same mechanism already used this
  session for `validate_env_name()`'s `call` and `rethrow_error_run()`'s
  `env`) and threading it into `withr::defer(..., envir = envir)`, called
  with no arguments from `create_env()`. Verified empirically, not just
  reasoned about — confirmed the cleanup now fires on the *caller's* exit
  via a minimal repro, then confirmed both real code paths against a fake
  `HOME`: a freshly-created `~/.mamba/pkgs` is removed again once the
  caller returns; a pre-existing one is left alone. (First verification
  attempt gave a false positive — used `withr::local_tempdir()` for the
  fake `HOME` itself, whose *own* teardown deletes the whole tree
  including `.mamba` regardless of this function's logic, momentarily
  looking like a bug in the extraction; re-tested with a plain
  `tempfile()`/`Sys.setenv()` fake `HOME` with no competing auto-cleanup
  to confirm the real behavior.)

  New function names (`ensure_libmamba_pkgs_dir_workaround`,
  `download_compressed_and_extract`, `resolve_create_env_packages_arg`,
  `resolve_create_env_platform_args`) exceed `object_length_linter`'s
  30-character default — checked against the rest of the package first:
  7 existing internal helpers already do too (e.g.
  `get_micromamba_activation_envvars`), and no `.lintr` config enforces
  the limit, so this matches established style rather than violating it.

  Full regression: `test-install_micromamba.R` (24/24),
  `test-create_env.R` (36/36), `test-create_nested_env.R` (5/5),
  `test-install_packages.R` (14/14), `test-run.R` (49/49),
  `test-list_envs.R` (11/11) — all clean, real network installs not
  skipped. `lintr::cyclocomp_linter(complexity_limit = 15L)`: both
  functions no longer flagged (only the two pre-existing, out-of-scope
  checksum helpers — `verify_micromamba_checksum()` 16,
  `compute_sha256()` 18, added after the original review pass — remain
  over the default limit; not part of this item's scope).

## Severity 5 — testing & docs

### Every core-workflow example is `\dontrun{}` — reconsidered and reversed

**Status: DONE.** Decided 2026-07-27, reversed 2026-07-28 after the author
pushed back with a fact that changed the risk calculus, verified directly
against R's own `tools::check.R` source rather than just the "Writing R
Extensions" manual prose. **Net effect: keep `\dontrun{}` for all 12
functions — no markup change.** The `run_bin()` example bug found during
the original audit was still real and independent of the markup question;
fixed separately (see below).

12 of the 17 exported functions wrap their entire `@examples` block in
`\dontrun{}`: `clean_cache`, `create_env`, `env_exists`, `install_micromamba`,
`install_packages`, `list_envs`, `list_packages`, `remove_env`, `run_bin`,
`run_pipeline`, `run`, `with_sandbox_dir`. The remaining 5 (`get_env_dir`,
`get_install_dir`, `get_sys_arch`, `micromamba_bin_path`, `parse_output`)
already have runnable examples and need no change — they don't touch the
network or `micromamba` at all.

**Original reasoning (2026-07-27), from the R-exts manual alone:**
`\dontrun{}` is verbatim text, never executed by `example()`/`R CMD check`
by default; `\donttest{}` must be real runnable code, executed by
`example()`, not executed by a plain `R CMD check` unless `--run-donttest`
is passed. Believed (based on the manual's prose plus the author's own
recollection of CRAN's process) that `R CMD check --as-cran` doesn't run
`\donttest{}` either, and that CRAN maintainers only *occasionally* run
everything by hand, sometimes airgapped. Concluded `\donttest{}` was
strictly better: real checkable code, a working `example()` demo for
users, `\dontrun{}` "silently rots" since nothing ever exercises it.
Decision at the time: switch all 12 to `\donttest{}`, each wrapped in a
broad `tryCatch({...}, error = function(e) invisible(NULL))`.

**What actually reversed it (2026-07-28):** the author's own local check
task is `R -q -s -e 'devtools::load_all(quiet=TRUE);
devtools::document(quiet=TRUE); devtools::run_examples(run_dontrun = TRUE,
run_donttest = TRUE);'` — which *already* exercises `\dontrun{}` examples
locally every time it's run (`devtools::run_examples()` calls
`tools::Rd2ex()` with `commentDontrun = !run_dontrun`, so `run_dontrun =
TRUE` un-comments and sources them). So the "silently rots" argument,
while true of CRAN's own view of the package and of any contributor not
running this exact command, does **not** apply to the author's actual
workflow — `\dontrun{}` rot gets caught locally regardless of markup.

That alone would only make the two options a wash, not reverse the
decision — the real reversal came from re-checking the *other* premise
directly against R's source instead of the manual's prose. Read
`tools::check.R` (R 4.6.1) around its example-checking logic:

```r
# ~line 4734
test_donttest <- !run_donttest &&
    (if (x == "NA") as_cran else config_val_to_logical(x))
if (test_donttest) {
    checkingLog(Log, "examples with --run-donttest")
    ... # re-runs Rd2ex() with commentDonttest = FALSE and executes it
```

`--as-cran` sets `as_cran <- TRUE`; when `_R_CHECK_DONTTEST_EXAMPLES_`
isn't explicitly overridden (the default, `"NA"`), `test_donttest` becomes
`TRUE` automatically. So `R CMD check --as-cran` runs the example suite
**twice**: once with both `\dontrun{}` and `\donttest{}` commented out,
then a **second, fully automatic pass** — labeled "examples with
--run-donttest" in the check log, and visible as its own section on every
package's public CRAN check-results page — that executes every
`\donttest{}` block for real. This is standard, routine CRAN submission
behavior, not an occasional manual maintainer action as originally
believed — that earlier belief was the actual error, not just an
optimistic framing of the same fact.

`\dontrun{}` has no equivalent secondary pass anywhere in that logic. It
only ever runs via an explicit `--run-dontrun` (or `run.dontrun = TRUE` to
`example()`/`devtools::run_examples()`) — a deliberate, developer-only
action CRAN's own infrastructure never takes on its own.

**Corrected risk comparison, specifically for examples needing internet
*and* downloading/executing an external `micromamba` binary:**

- `\donttest{}`: genuinely, routinely executed by CRAN's own submission
  check. A CRAN build machine with restricted/no internet for that step,
  or a slow/failed `micromamba` download, becomes a real, automatic CRAN
  check failure attributed to the package — not hypothetical.
- `\dontrun{}`: never executed by any part of CRAN's automated pipeline,
  under any flag combination. Zero risk of ever failing there.

**Decision (reversed): keep `\dontrun{}` for all 12 functions.** The
`tryCatch()`-wrapping recommendation is no longer a CRAN-compliance
necessity (there's nothing CRAN-side for it to protect against once
`\dontrun{}` is confirmed to never execute under CRAN's own tooling) —
left as an optional, author's-discretion nicety for their own local
`run_dontrun = TRUE` runs, not implemented.

**Still real and fixed, independent of the markup question:**
`run_bin()`'s example said `# Example assumes that 'my-env' exists and
contains 'python'` but never created it — would fail if actually run,
regardless of `\dontrun{}`/`\donttest{}`. Fixed by adding a real
`create_env()` setup step, matching every other example's pattern (see
`R/run_bin.R`).

`with_sandbox_dir()`'s example was correctly identified during the
original audit as not needing `\dontrun{}` at all — it only prints paths
inside a sandboxed environment, no network/`micromamba` involved, so
`\dontrun{}` there isn't buying any CRAN-safety (nothing to protect
against) and just needlessly hides a fast, safe example from ever
running. **Status: DONE** (2026-07-28) — moved out of `\dontrun{}` into a
plain, always-run example (`R/with_sandbox_dir.R`); no other change
needed since it never touched the network.

### Example portability audit — some examples couldn't run on Windows at all

**Status: DONE (2026-07-28, corrected 2026-07-28).** Separate from the
`\dontrun{}`/`\donttest{}` question: audited every `@examples` block across
all 18 exported functions for whether the demonstrated packages actually
have Windows builds, after the `run_bin()` fix above accidentally
introduced exactly this class of bug (`conda-forge::coreutils`, which has
no `win-64` build). Author's guidance: prefer genuinely portable
single-package solutions over OS-conditional branching wherever the
illustrative point allows it.

**A methodology mistake in the first pass, caught and corrected by the
author:** the first pass checked each package's availability by reading
`channeldata.json`'s `subdirs` field directly and concluded `bioconda::
fastqc` had no Windows support (`subdirs: linux-64, noarch, osx-64` —
no `win-64` listed) — leading to an unnecessary swap of `bioconda::fastqc`
→ `conda-forge::ripgrep` across six examples. **That inference doesn't
hold for `noarch` packages.** `fastqc` is `noarch` (a Java wrapper script,
not a compiled binary), and `noarch` packages install from any platform's
package pool as long as their dependencies resolve for that platform — the
`subdirs` list only reflects which platform-specific artifacts a channel
has *actually built and uploaded*, not which platforms can *use* a
`noarch` package. Verified directly rather than re-assumed: a real
`micromamba create --dry-run --platform win-64 -c conda-forge -c bioconda
fastqc` solve succeeds, pulling in `openjdk` (Java) and the Windows
runtime libraries (`ucrt`, `vc`, `vc14_runtime`, `vcomp14`) automatically
from conda-forge — exactly the two channels `create_env()` already
defaults to. **Net effect: the `fastqc`→`ripgrep` swap in the six generic
examples was reverted; those examples are back to `bioconda::fastqc`,
which was already Windows-compatible all along** (with default
`channels = c("conda-forge", "bioconda")`).

**What genuinely doesn't work on Windows, confirmed two ways — checked
each channel's `channeldata.json` *and* distinguished `noarch` from
platform-specific packages, not `subdirs` alone:**

| package | channel | noarch? | Windows? |
|---|---|---|---|
| `ripgrep` | conda-forge | no (native builds per platform) | yes — has a real `win-64`/`win-arm64` build |
| `fastqc` | bioconda | **yes** | yes — solves via `noarch` + conda-forge's `openjdk`, confirmed with a live `--platform win-64` dry-run solve |
| `coreutils` | conda-forge | no | no — only the separate, Windows-only `m2-coreutils` (MSYS2) package provides this on Windows |
| `grep` | conda-forge | no | no — same MSYS2 (`m2-grep`) situation as `coreutils` |
| `samtools` | bioconda | no (compiled htslib-based binary) | no — no Windows build under any name, on any channel |

The generalizable distinction: a `noarch` bioconda/conda-forge package
(interpreted/wrapper-script, e.g. Java- or Python-based tools) is
platform-agnostic and works everywhere its dependencies do; a compiled,
platform-specific package (`coreutils`, `grep`, `samtools`) only works on
the platforms it's actually been built for, and bioconda has never built
for Windows at all. "Is this from bioconda" is not itself the deciding
factor — "is this `noarch`" is.

**What actually changed, after the correction:**

- **Reverted (no longer needed):** `list_envs()`, `remove_env()`,
  `create_env()` (version-pin demo back to `fastqc==0.12.1`),
  `list_packages()`, `env_exists()`, `install_packages()` — all back to
  `bioconda::fastqc`, `env_name = "fastqc-env"`. `list_packages()`'s
  `dim(dat)` comment corrected to a value verified from a real install,
  `[1] 66 11` — the pre-existing `[1] 34 8` in the docs before any of this
  was already stale/wrong regardless of package choice (a real `ripgrep`
  install returned `[1] 4 11`, an 11-column schema either way; the `34`
  row count didn't match a real `fastqc` install either, which returns 66).
- **Still fixed (genuinely necessary, unaffected by the correction —
  `coreutils`/`grep` are compiled, not `noarch`):** `run_bin()`'s
  `conda-forge::coreutils`/`"ls"` → `conda-forge::ripgrep`/`"rg"`;
  `run_pipeline()`'s `get_sys_arch()`-based `grep`/`m2-grep` conditional
  simplified to `ripgrep`/`rg`.
- **Still left as Linux/macOS-only, with an explicit comment (unaffected —
  `samtools` is compiled, not `noarch`, and has no Windows build under any
  name):** `run()`'s and `run_pipeline()`'s use of `bioconda::samtools` to
  demonstrate operating on the packaged `inst/extdata/example.bam` file.

**Verified live, not just parsed, both before and after the correction** —
every rewritten/reverted example run end-to-end via `tools::Rd2ex()` +
`source()` (the same mechanism `devtools::run_examples()` uses) against
real network installs: `with_sandbox_dir`, `list_envs`, `remove_env`,
`create_env`, `list_packages`, `env_exists`, `install_packages`, `run_bin`,
`run`, `run_pipeline` — all complete with no errors.
`roxygen2::roxygenize()` regenerated all affected `.Rd` files;
`DESCRIPTION` version unchanged.

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
