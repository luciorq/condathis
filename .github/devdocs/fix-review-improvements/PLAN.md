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

**Status: investigated, design recommended, NOT implemented — awaiting the
author's policy decision.** Until then the dead code should either be
re-enabled per the above or removed and the non-verification documented as
deliberate, not left as silent dead code.

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

**Status: not started.**

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
  built-in escape. Real feature gap.
- **Uneven input validation.** `install_packages()` and `clean_cache()`
  validate nothing; `install_packages(packages)` with no args gives a bare
  base-R error, not a `condathis_*` class; `get_env_dir()` doesn't validate
  `env_name`. A shared `env_name` validator (the one just added to
  `env_exists()`) could be reused.
- **`install_packages()` existence check reads backwards.**
  `R/install_packages.R:66–69`: `any(list_envs(...) %in% env_name)` — works
  but awkward; `env_exists(env_name)` (or `env_name %in% list_envs()`) is
  clearer and matches every other call site.
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
  delete. **Status: not started** (contingent on the checksum decision).
- **Commented-out code blocks:** ~12 in `install_micromamba.R` (`lintr`
  `commented_code_linter`). Remove or restore. **Status: not started**
  (same contingency).
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

- **Every core-workflow example is `\dontrun{}`** (`run`, `run_bin`,
  `run_pipeline`, `create_env`, `install_packages`, ...). None are exercised
  by `R CMD check`, so they can rot. Understandable (need network +
  micromamba); some could move to `\donttest`.

## What's already solid (for balance)

`parse_match_spec()`/`version_spec_contains()` cross-validated against real
`libmambapy`. The run/pipeline I/O layer is hardened against
empirically-confirmed deadlock/truncation/binary bugs. Tight dependency
footprint (`curl` correctly optional). Error classes well-designed and, post
`fix-output-contracts`, well-tested. `R CMD check` is otherwise clean (no
NOTEs on structure; the only WARNINGs seen were artifacts of a
`--no-build-vignettes` build).

## Open questions (need author input)

1. **Checksum policy** (severity 1): warn-by-default vs fatal on mismatch;
   R floor 4.3-with-fallback vs bump to 4.5. Blocks the checksum item only.
2. **`run()` auto-create** (2b): auto-create `env_name` itself, or only
   check the base env when `env_name` is the default? Determines the 2b fix
   shape.
