# TODO: Processx 3.9.0 Pipeline Support

## Done

- [x] Write PLAN.md and TODO.md
- [x] Update `DESCRIPTION` — `processx` → `processx (>= 3.9.0)`
- [x] Update `R/native_cmd.R` — add `cleanup_tree`, `encoding`, `linux_pdeathsig`
- [x] Create `R/conda_activation.R` — `get_activation_envvars()`
- [x] Create `R/pipeline_result.R` — S3 `condathis_pipeline` class
- [x] Create `R/run_pipeline.R` — `run_pipeline()` with pipe plumbing
- [x] Update `NAMESPACE` — export `run_pipeline`
- [x] Create `tests/testthat/test-run_pipeline.R`
- [x] Update `NEWS.md` with changelog entry
- [x] Add `linux_pdeathsig = TRUE` to `native_cmd()`
- [x] Add `stdin = "|"` writable stdin support for `run_pipeline()` (new `input` argument)
- [x] Add per-command `stdout`/`stderr` override support in named list spec
- [x] Fix `run_pipeline()` env-existence check running before default-env
      auto-creation (auto-create path was previously unreachable)
- [x] Fix `run_pipeline()` crashing when reading `stdout`/`stderr` for a
      process whose output is redirected to a file or discarded (`NULL`)
- [x] Add more test coverage (stdout NA, 3-command pipe, named list spec,
      pid check, timeout field, stdin/input, per-command overrides,
      auto-create default env)
- [x] Write integration test for mixed environments (two real Conda envs:
      `conda-forge::grep` piped into `conda-forge::sed`; `m2-grep`/`m2-sed`
      on Windows)
- [x] Fix `run_pipeline()` letting a raw, uncaught `processx` error escape
      when a command is not found — now respects `error = "cancel"` /
      `"continue"` via a `spawn_failures` mechanism, consistent with `run()`
- [x] Fix `run_pipeline()` error messages breaking or corrupting when a
      failing command's `stderr` contained curly braces — added
      `escape_cli_braces()`, applied to stderr, `cmd`, and `env_name`
- [x] Fix `run_pipeline()` always throwing on a missing custom `env_name`
      regardless of `error` — `error = "continue"` now reports
      `status = 127` per affected command instead of aborting the pipeline;
      `error = "cancel"` keeps the original fail-fast behavior
- [x] Add regression tests for the three fixes above (command not found ×
      cancel/continue, brace-escaping, missing custom env × cancel/continue)
- [x] Run `just lint` and `just test` — all 712 tests pass, 0 failures

## Reconciliation: feature parity between `run()`, `run_bin()`, and `run_pipeline()`

- [x] Crash safety: add `supervise`, `cleanup_tree`, `linux_pdeathsig`
      arguments to `run()` and `run_bin()` (default `FALSE`, preserving
      existing behavior). Made `run_pipeline()`'s `supervise`/`cleanup_tree`
      (previously hardcoded `TRUE`) and `linux_pdeathsig` (new) overridable
      arguments too, default `TRUE`/`TRUE`/`FALSE`.
- [x] Writable `stdin = "|"` + `input`: add to `run()` and `run_bin()`.
      Since `processx::run()` has no way to write to a `stdin = "|"`
      connection it creates internally (confirmed: `stdin = "|"` alone
      deadlocks the child), added `R/run_process_with_input.R` — a
      `processx::process$new()`-based helper mirroring
      `run_pipeline()`'s own first-process input-writing logic, returning a
      `processx::run()`-shaped list so it slots into the existing
      `rethrow_error_run()` error handling unchanged. `native_cmd()` and
      `run_bin()` now branch to it only when `stdin = "|"`; the common case
      (`stdin = NULL`/file path) is untouched.
      Trade-off (documented in the `input` param docs): no live
      stdout/stderr streaming, spinner, or timeout on this code path.
- [x] Return shape: new `R/run_result.R` — S3 class `condathis_result`
      (`new_condathis_result()`, `format()`, `print()`, `as.list()`),
      returned by `run()` and `run_bin()` instead of a plain
      `processx::run()` list. Remains a plain list under the hood
      (`res$status`/`res$stdout`/etc. unaffected — verified `parse_output()`
      and existing tests that do `res$status` still work unchanged) with
      `pid`, `cmd`, `env_name` fields added, mirroring
      `condathis_pipeline`'s per-process shape.
- [x] Add `condathis_run_invalid_input` validation (mirrors
      `run_pipeline()`'s `condathis_pipeline_invalid_input`): `input`
      requires `stdin = "|"` on both `run()` and `run_bin()`.
- [x] Add test coverage: `condathis_result` class/fields/print, `input` +
      `stdin = "|"` (success and failure, `error = "cancel"`/`"continue"`),
      invalid `input` without `stdin = "|"`, crash-safety params accepted
      on all three functions, `run_pipeline()`'s override params.
- [x] Update README.qmd/README.md "Known Caveats" — no longer claims pipes
      are unsupported or that `stdin` only accepts files.
- [x] Run `just lint` and `just test` — all 735 tests pass, 0 failures.

## Activation-mechanism divergence: exploratory building block

- [x] Add `R/get_micromamba_activation_envvars.R` — `get_micromamba_activation_envvars(env_name)`,
      **not wired into `run_pipeline()`, `run()`, or `run_bin()` yet**.
      Resolves the *real* `micromamba run -n <env>` activation (including
      `activate.d` hook scripts) by spawning `Rscript` through it, dumping
      its environment as JSON, and diffing against a clean baseline —
      verified empirically that activation vars like `CONDA_PREFIX`/`PATH`
      come through correctly. Returns a named character vector in the same
      shape as `get_activation_envvars()`
      (`env = c("current", get_micromamba_activation_envvars(env_name))`),
      so it's a drop-in candidate for `run_pipeline()`'s activation overlay
      once validated further, and — since it resolves activation vars
      independently of wrapping a command in `micromamba run` — a candidate
      building block for consolidating `run()` (currently: wrap `cmd` in
      `micromamba run -n <env> cmd`) with `run_bin()` (currently: run the
      binary directly, no activation) into "resolve activation vars once,
      then execute like `run_bin()` with that overlay."
      Cached per `env_name`, invalidated when the environment's
      `conda-meta` directory changes (package install/remove) via a cheap
      file-count + max-mtime fingerprint (`activation_cache_stamp()`), not
      full content hashing — no new dependency needed for that.
      Known noise sources filtered out (verified against real captured
      output): dump-subprocess artifacts (`R_ENVIRON`, `R_PROFILE`,
      `R_SESSION_TMPDIR`, `PROCESSX_PS2*`), shell-session state
      (`PWD`, `OLDPWD`, `SHLVL`, `PS1`, `_`), and `TMPDIR` (condathis
      manages that separately per-call already).
      Known limitation, not yet resolved: on a machine where R itself runs
      from inside an already-activated environment (e.g. R installed via
      pixi/conda), the diff can still pick up nested-activation artifacts
      (`CONDA_PREFIX_1`, `CONDA_SHLVL` > 1) that reflect the *host's*
      activation stack, not the target env's — needs more investigation
      before this is wired into anything that assumes a from-scratch
      activation.
- [x] Add `tests/testthat/test-get_micromamba_activation_envvars.R` —
      correctness of resolved vars, noise filtering, missing-env error,
      usability as a `process$new(env = ...)` overlay, caching (hit/miss/
      forced-recompute), `reset_micromamba_activation_cache()`, and
      `activation_cache_stamp()` invalidation on `conda-meta` changes.
- [x] Run `just lint` and `just test` — all 753 tests pass, 0 failures.

## Wiring `get_micromamba_activation_envvars()` into `run_bin()` and `run_pipeline()`

- [x] Add `activate = TRUE` argument to `run_bin()`. When `TRUE` (now the
      default — see note below) and `env_name` exists, overlays
      `get_micromamba_activation_envvars(env_name)` as
      `env = c("current", <vars>)` on top of the existing PATH-prefix
      behavior. Silently skipped (falls back to the pre-existing,
      activation-free behavior) when `env_name` does not exist, so
      `run_bin()`'s established "works with a binary outside any managed
      environment" fallback still works unchanged. `cmd` resolution itself
      is unchanged — `run_bin()` still resolves `cmd_path` explicitly
      rather than relying on the activated `PATH`, unlike `run()`.
- [x] Add `activate = TRUE` argument to `run_pipeline()` (single toggle
      for the whole pipeline, not per-command). Replaces the per-process
      `get_activation_envvars()` call with
      `get_micromamba_activation_envvars(env_name_i)` when `TRUE`. Env
      existence is already guaranteed by `precreate_envs()`/
      `missing_envs` by the time this runs, so no extra existence check
      needed there (unlike `run_bin()`).
- [x] **Found and fixed a second instance of the `R_HOME` corruption bug**
      (see the "known noise sources" note above — that was the same root
      cause, first found in isolation). This time it was worse: `run_bin()`
      and `run_pipeline()` *themselves* apply their own
      `get_clean_conda_envvars()` scope (setting `R_HOME = ""`) *before*
      calling `get_micromamba_activation_envvars()`, so the earlier fix
      (resolve `R.home()` before that function's own clean-envvar scope)
      didn't help — `R_HOME` was already corrupted by the caller. Confirmed
      by reproduction: `run_bin(activate = TRUE)` failed with
      `/bin/Rscript: No such file or directory`. Fixed properly this time:
      added `.onLoad()` in `R/condathis-package.R` that resolves and caches
      `R.home("bin")`-derived `Rscript` path once, at package load time —
      before any condathis function has had a chance to touch `R_HOME` —
      via `get_condathis_rscript_path()`. This sidesteps the ordering
      problem entirely rather than requiring every caller in the chain to
      resolve `R.home()` before its own `get_clean_conda_envvars()` call,
      which does not compose when scopes nest.
- [x] Validated `run_bin(activate = TRUE)` against `run()` directly, as
      requested: same `CONDA_PREFIX`, same activated `PATH` (env's `bin/`
      present) — confirmed identical for both `printenv CONDA_PREFIX` and
      `printenv PATH`. `run_bin(activate = FALSE)` confirmed to preserve
      the original no-activation behavior.
- [x] Add test coverage: `run_bin(activate = TRUE)` vs `run()` equivalence
      (`CONDA_PREFIX`, `PATH`), `run_bin(activate = FALSE)` no-activation
      behavior, `run_bin(activate = TRUE)` graceful fallback for a missing
      env, `run_pipeline(activate = TRUE/FALSE)`, and a regression test
      pinning down the `R_HOME`-corruption-via-caller's-own-scope bug.
- [x] Run `just lint` and `just test` — all 767 tests pass, 0 failures.

## Remaining / Optional

Implementation is feature complete per PLAN.md, including the
`run()`/`run_bin()`/`run_pipeline()` reconciliation and the
`get_micromamba_activation_envvars()` wiring above. `run()` itself is not
yet touched — see the user's explicit "before trying to modify `run()`"
scoping for this round of work; consolidating `run()` with
`run_bin(activate = TRUE)` (as sketched in PLAN.md) remains a candidate
follow-up, not yet started.

**Flagging a default-value decision, not just an implementation detail**:
both new `activate` arguments default to `TRUE`, per explicit instruction.
For `run_pipeline()` this is additive (it always activated *something*
before; `TRUE` just makes that more accurate, at the cost of two extra
subprocess spawns per unique `env_name` on first use, mitigated by
caching). For `run_bin()`, though, this is a real change to a previously
zero-activation-by-default, documented "lower-level, no activation"
function — existing callers that relied on `run_bin()` running completely
unactivated (e.g., to avoid inheriting `CONDA_PREFIX`/`PATH` overlay) will
now get activation vars by default unless they pass `activate = FALSE`.
No existing test broke (verified), but this is a behavior change worth the
user's awareness, not merely an implementation footnote.

See PLAN.md's "Known, intentional divergences from `run()` / `run_bin()`"
section for the behavioral differences that remain deliberate design
choices (not open TODOs): no `verbose` support on `run_pipeline()`. The
"environment activation mechanism differs" divergence noted there is now
closed for `run_bin()`/`run_pipeline()` (both can do real `micromamba run`
activation via `activate = TRUE`) — `run()` was intentionally left
untouched this round.

## Binary output support (`binary` argument) + two real I/O bugs found and fixed

Prompted by writing an article showcasing `run_pipeline()` piping binary
image data between Conda environments (OpenSlide/`libvips` → ImageMagick),
which surfaced that stdout/stderr were always decoded as UTF-8 text,
corrupting binary payloads. See PLAN.md for full design/rationale.

- [x] Add `binary = FALSE` argument to `run()`, `run_bin()`, `run_pipeline()`
      — captures stdout/stderr as raw vectors instead of UTF-8 text when
      `TRUE`. Both streams become raw together (one shared `processx`
      encoding per process), not just stdout.
- [x] Update `format.condathis_result()`, `format.condathis_pipeline()`, and
      `parse_output()` to check `is.raw()` on **both** stdout and stderr
      independently before running character-only operations
      (`nzchar()`/`strsplit()`/etc.) — `parse_output()` aborts with class
      `condathis_parse_output_binary_stream` naming exactly which stream(s)
      are binary, rather than crashing inside `stringr` calls.
- [x] Fix real bug: `processx`'s `read_all_output()`/`read_all_error()`
      mangle raw bytes into hex-string characters when `encoding =
      "binary"` (they `paste0()`-concatenate chunks, which coerces `raw` to
      per-byte hex text) — confirmed empirically. Fixed by reading via
      `read_output_bytes()`/`read_error_bytes()` in a loop instead.
- [x] **Fix real bug (deadlock, any platform, plain text too)**:
      `run_process_with_input()` and `run_pipeline()` both called
      `proc$wait()` before draining any output — deadlocks once combined
      stdout+stderr exceeds the OS pipe buffer (64KB on Linux, smaller on
      macOS/Windows), since the child blocks writing to whichever stream
      isn't being read, so it never exits. Confirmed by reproducing the
      hang directly with `processx::process$new()`.
- [x] **Fix real bug (silent truncation, any platform)**:
      `proc$write_input()` is a single non-blocking write that can
      short-write and returns the undelivered leftover, which the R
      wrapper discards — writing once and closing immediately silently
      truncated `input` larger than the OS pipe buffer, no error. Confirmed
      on Windows: 200,000-byte `input` delivered only 8,192 bytes,
      independently verified with `wc -c` on the receiving end.
- [x] New shared helper `pump_process_io()` (`R/pump_process_io.R`, née
      `R/read_all_stream_binary.R`/`R/read_all_streams.R` as its scope
      grew) fixing both bugs at once: one loop that polls a process's
      stdin/stdout/stderr together, retrying the stdin write with
      `write_input()`'s returned leftover, and draining whatever's
      currently available on stdout/stderr each iteration. Wired into
      `run_process_with_input()` (replaces the old write→close→wait→read
      sequence) and `run_pipeline()` (replaces the old "wait on every
      process, then read every process" two-pass structure with
      drain-then-wait per process, reusing the first command's
      already-fully-drained stderr from its own input-writing phase instead
      of draining it twice).
- [x] Add regression tests (`test-run.R`, `test-run_pipeline.R`):
      200,000-byte round-trips through both bugs' exact failure conditions.
      Byte generation via `printf '%*s' N '' | tr ' ' 'X'`, not
      `yes X | head -c N` — the latter doesn't reliably terminate under
      MSYS2/Windows bash (see PLAN.md's "Open Problem" section).
- [x] Verify cross-platform via SSH against `gamma` (local Ubuntu), and
      `omicron`/`kappa` (macOS ARM / Windows 11 test-bed machines), **using
      each machine's system R, not `pixi`'s R** (corrected after an initial
      pass mistakenly used `pixi`'s trampoline `R`/`Rscript` on `omicron`).
      `run()`/`run_bin()`: clean on all three, including the new regression
      tests. `run_pipeline()`: clean on Linux/macOS; **hangs on Windows for
      any 2+ command pipeline — see next section, a separate pre-existing
      bug this surfaced, not caused by this work.**

## `run_pipeline()` hangs indefinitely on native Windows — fixed

**Fixed.** Two real, permanent correctness fixes applied
(`conn_create_proc_pipepair()`, per-iteration pipe closes, `poll_connection`)
— none of which alone or combined fixed the hang. The actual cause
(`supervise = TRUE`) was isolated and A/B-confirmed, then fixed by forcing
`supervise = FALSE` on Windows only (`get_sys_arch()`-gated), leaving the
`TRUE` default and its crash-safety guarantee untouched on Linux/macOS.
Full write-up in PLAN.md's corresponding section — summary here:

- [x] Confirm the hang is real and reproducible — simplest case,
      `run_pipeline(cmds = list(c("echo", "hello"), c("cat")))`.
- [x] Rule out: this session's `binary`/deadlock/truncation changes,
      extra child processes from a `yes`/`head`/`tr` subpipeline, `pixi`'s
      R specifically (all previously ruled out, see PLAN.md).
- [x] Isolate the hang point: second command's stdout never sees EOF even
      after the first command exits cleanly.
- [x] Diff against `processx::pipeline$new()` (a working reference on the
      same Windows box, supplied by the user as a live counter-example)
      and test each difference in isolation on Windows:
  - [x] `conn_create_pipepair()` → `conn_create_proc_pipepair()` (the
        latter is documented as required — synchronous/blocking — for
        Windows child stdin/stdout). **Applied, kept. Tested alone: did
        not fix the hang.**
  - [x] Close each pipe end immediately per-iteration instead of
        deferring all closes until the whole pipeline has spawned.
        **Applied, kept. Bundled with the above, still did not fix the
        hang.**
  - [x] `poll_connection = FALSE` for every non-last process (matches
        `pipeline$new()` exactly). **Applied, kept. Combined with both
        above: still did not fix the hang.**
  - [x] `supervise`: `pipeline$new()` never enables it (every process gets
        `process$new()`'s own `FALSE` default); `run_pipeline()` defaults
        it to `TRUE`. Tested by overriding to `FALSE` in the repro call
        (no source change): **hang gone, 0.66s.** Confirmed the inverse
        immediately after in the same script/session: `TRUE` **hung
        again**. This is the cause.
- [x] Mechanism recorded, then confirmed by upstream: `supervise = TRUE`
      spawns a `supervisor.exe` helper per child on Windows (confirmed via
      `tasklist`). `processx` 3.9.0's own "Process cleanup" vignette
      independently documents this exact failure mode under a "Windows
      Defender caveat" — antivirus may flag/quarantine/block
      `supervisor.exe` — and explicitly recommends package authors expose
      a way to disable the supervisor as a Windows workaround. See
      PLAN.md for the full quote.
- [x] Fix implemented: `run_pipeline()` computes `effective_supervise <-
      if (get_sys_arch() matches "^Windows") FALSE else supervise` and
      passes that to every `process$new()` call instead of the raw
      `supervise` argument. Chosen over "default `FALSE` everywhere"
      (would silently weaken crash-safety on Linux/macOS, where nothing is
      broken) and the untested per-position variant (no evidence it was
      needed once the real cause was found).
- [x] Re-verified with the full `test-run_pipeline.R` suite: 77/77 on
      Linux, macOS (`omicron`), and Windows (`kappa`) — the Windows run
      confirmed genuinely executing (not silently skipped; see the
      `NOT_CRAN` quoting note below) with 0 errors, only the pre-existing
      benign tzdata warnings.
- [x] `testthat::skip_on_os("windows")` was never added, so there's
      nothing to revisit — the multi-command pipeline tests always ran
      unconditionally on Windows; they just weren't failing loudly because
      of the `NOT_CRAN` issue below, not because they were skipped by OS.
- [ ] **Open, not decided or implemented**: upstream's "Process cleanup"
      vignette recommends a *general* user-facing escape hatch (option or
      env var) to disable the supervisor package-wide, not just the
      Windows-gated default inside `run_pipeline()` that's already applied.
      Would need a naming/design decision (e.g. `options(condathis.supervise
      = FALSE)` or `CONDATHIS_SUPERVISE=false`) — not required for the
      Windows hang itself, which is already fixed independent of this.

### Unrelated finding along the way: `NOT_CRAN` silently not propagating via `ssh kappa "... set NOT_CRAN=true && ..."`

`cmd.exe`'s `set VAR=value && next_command` includes the trailing space
before `&&` in the value — `Sys.getenv("NOT_CRAN")` came back as `"true "`
(trailing space), which `testthat::skip_on_cran()` correctly treats as not
set (it requires an exact `"true"` match), silently skipping every
`skip_on_cran()`-gated test instead of running them. This made several
earlier "N/N pass" results in this investigation actually mean "N/N
*skipped*, 0 run" — not caught until a differently-shaped failure (a real,
separate bug — see below) surfaced once tests were actually executing.
Fixed for future remote Windows test invocations by quoting the
assignment: `set "NOT_CRAN=true" && ...`.

## Fixed: `install_micromamba()` intermittently reports a fresh binary as missing on Windows

Surfaced only once `NOT_CRAN` was actually propagating (see above) and
real tests started running: `install_micromamba(force = TRUE)` failed
once with `condathis_install_error_missing_bzip2` ("was not downloaded or
extracted successfully"), then succeeded immediately on manual retry with
no code change in between. Consistent with a Windows antivirus real-time
scan briefly holding its own handle on the just-extracted/just-downloaded
`micromamba.exe`, making `fs::file_exists()` return `FALSE` for a moment
even though the file is actually present. Fixed by wrapping both
post-extraction and final existence checks in a small
`file_exists_retry()` helper (5 attempts, 0.2s apart) in
`R/install_micromamba.R`. Re-verified: 3 consecutive full `test-
install_micromamba.R` runs (25/25 each) and an 8-attempt manual stress
test (5× `force = TRUE` reinstall via the compressed/`tar`+`bzip2` path, 3×
via the raw-binary fallback path with `PATH` restricted like the test
does) all clean on `kappa` after the fix.

## Fixed: `get_micromamba_activation_envvars()` caching test flaky on `PROCESSX_PS3...`

The noise-filter regex only matched `^PROCESSX_PS2`, but `processx` also
sets a `PROCESSX_PS3...` tracking variable (both PID/hash-suffixed, fresh
on every subprocess spawn) that leaked through unfiltered — making the
"caches per `env_name`" test's `identical(envvars_first, envvars_forced)`
check fail nondeterministically (it forces a second, fresh resolution via
`use_cache = FALSE`, which necessarily spawns a new subprocess with a new
`PROCESSX_PS3...` value). Broadened to `^PROCESSX_PS[0-9]` in
`R/get_micromamba_activation_envvars.R`; matching test assertion in
`test-get_micromamba_activation_envvars.R` broadened the same way.
Re-verified: 5 consecutive clean runs on Linux, 3 on macOS, 3 on Windows.

**Correction (2026-07-22): the `[0-9]` fix above was still wrong.** CI
failed again on `windows-latest` with the exact same "caches per
`env_name`" test. Root cause was never "PS2 vs PS3" — the suffix is a
random *hex* hash (confirmed directly: `PROCESSX_PSc84243e8843f4_...` on
Linux, `PROCESSX_PSf046e9e523d_...` on Windows), not a small decimal
counter, so `[0-9]` only ever matched by luck (~64% of the time, confirmed
by a 2000-sample local simulation) whenever the hash happened to start
with a digit — deterministically failing whenever it starts with a
letter, which is what happened on that Windows run. Since the whole
`PROCESSX_PS*` namespace belongs to `processx`, widened the pattern to
just `^PROCESSX_PS` (in both the source and the matching test assertion).
See the 2026-07-22 section below for the rest of what shipped alongside
this.

**Process hygiene note for future remote Windows testing:** killing the
local `ssh`/`timeout` wrapper does **not** kill the remote process tree —
each hung repro attempt left orphaned `Rscript.exe`/`cat.exe`/
`supervisor.exe` processes running on `kappa` indefinitely (visible via
`tasklist`), which then blocked subsequent `scp` uploads of the same
filename (`Failure` writing to a file still open on the remote side).
Clean up with `taskkill /F /IM <name>.exe /T` for each relevant process
name before re-running a repro that previously hung.

## Additional work landed on this branch (unrelated to the pipeline feature)

Two follow-up requests were done on `feat-pipeline` while it was the active
branch. Neither touches pipeline code; noted here since they shipped as
part of the same branch/PR.

- [x] `install_packages()` channel-mismatch warning: new
      `R/get_env_history_channels.R` (`@noRd`) parses `conda-meta/history`
      to recover the channels packages already in an environment actually
      came from; `install_packages()` warns
      (`condathis_install_missing_previous_channels`) when the current
      call's `channels`/`additional_channels` would drop one of those.
      Install still proceeds — warning only. Tests:
      `test-get_env_history_channels.R` (parser, no network),
      `test-install_packages.R` (real env, network).
- [x] Test-suite Windows portability: `test-run.R`, `test-run_bin.R`,
      `test-run_output_file.R`, and `test-run_pipeline.R` previously called
      bare `echo`/`cat`/`sort`/`sh`/`ls`/`printenv`/`tr`/`uniq`/`rev`/`false`
      against environments that never installed them, relying on the host's
      system `PATH` — not guaranteed on Windows without Git Bash. Added
      `tests/testthat/helper-cli-tools.R` (`test_os_pkg()`, resolving to
      `m2-*` conda-forge packages on Windows) and dedicated per-file test
      environments that install `coreutils`/`bash`/`util-linux` for real;
      `sh` calls switched to `bash -c` (neither `coreutils` nor `bash`
      installs a standalone `sh`). Left untouched: argument-validation tests
      that never spawn a process, the "auto-creates the default
      environment" test (whose point is the empty auto-created env, not
      command output), and `run("R", ...)` calls (R is inherently on `PATH`
      since it's the test runner). Full suite: 773 passed, 0 failed.

## 2026-07-22: CI red on Windows/macOS — one platform-support gap, four real bugs

`r-cmd-check` was failing on `windows-latest` (7 failures) and
`macos-latest`/arm64 (1 failure) on this branch's HEAD. Investigated each
failure individually rather than blanket-skipping — only one turned out to
be an actual "not supported outside Linux" case; the rest were real,
previously-undiscovered bugs, two of them significant (silent
environment-isolation bypass on Windows). All five fixes verified on real
Windows (`kappa`) via SSH per the process established above; the sixth
(macOS/bioconda) doesn't need Windows and was verified against bioconda's
own repodata instead.

- [x] **Platform-support gap, not a bug**: `test-install_packages.R`
      installs `bioconda::fastqc`. Confirmed against bioconda's repodata:
      published for `linux-64`/`osx-64`/`noarch` only — no `win-64` build
      at all, and the `noarch` build's own dependencies (`openjdk`,
      `font-ttf-dejavu-sans-mono`) are themselves unavailable for
      `win-64`/`osx-arm64`. bioconda has never supported Windows and does
      not ship native Apple Silicon builds — this is unsolvable on
      `windows-latest` and modern (`arm64`) `macos-latest` runners
      regardless of anything `condathis` does. Added
      `testthat::skip_if_not(testthat:::system_os() == "linux", ...)` to
      that test, and a new
      `"install_packages warns when previous channels are dropped
      (cross-platform)"` test exercising the identical
      channel-history-diff warning logic with `conda-forge`-only packages
      (`zlib`/`xz`), which resolves identically on all four platforms.
- [x] **Real bug, significant**: `run_bin()` only ever checked
      `<env_dir>/bin/<cmd>` for the target binary (a Linux/macOS-only
      Conda layout) — Windows environments spread binaries across
      `Library/mingw-w64/bin`, `Library/usr/bin`, `Library/bin`, `Scripts`,
      and the prefix root instead, so that check always failed there. The
      existing fallback then silently tried `Sys.which(cmd)` — the
      *ambient* system `PATH`, completely unrelated to `env_name` — which
      resolved `sort` to Windows' own `C:\Windows\System32\sort.exe`
      (confirmed via `where sort` on `kappa`) instead of the environment's
      own coreutils build, silently defeating environment isolation.
      Confirmed as the cause of `test-run_bin.R`'s `"supports stdin = '|'
      with input"` failure (`sort` output came back as literal `???`
      bytes, i.e. `System32\sort.exe` choking on piped UTF-8 input it
      doesn't expect) via a minimal repro on `kappa`: same command spawned
      directly through `processx` with the coreutils `sort.exe`'s real
      path worked correctly; through `run_bin()`'s resolution, it silently
      picked the wrong binary.
- [x] **Real bug, same root cause, different symptom**: `run_pipeline()`
      passes a bare command name (`cmd_vec[1L]`) straight to
      `processx::process$new(command = ...)`, relying on the OS to locate
      it — but the OS resolves a bare command name against the *calling*
      R process's own ambient `PATH` (Windows `CreateProcess`, like POSIX
      `execvp()`, locates the executable image before the child's `env =`
      override ever takes effect), not against the environment activation
      vars passed via `env =`. Confirmed the cause of
      `test-run_pipeline.R`'s `"supports three chained commands"` failure
      (the `rev` stage returned `NA` stdout): `where rev`/`where rev.exe`
      on `kappa` found nothing anywhere on the ambient `PATH` at all, even
      though the target environment's own `Library/usr/bin/rev.exe`
      exists and is genuinely on the *activated* `PATH` — it's just never
      consulted for the initial spawn. The other pipeline stages in that
      same test (`echo`, `tr`) only "worked" by pure coincidence, because
      tools of those names happened to already exist elsewhere on
      `kappa`'s ambient `PATH` (Rtools/`pixi`), completely bypassing
      `env_name` — not a real pass.
- [x] Fix for both of the above: new shared `R/resolve_env_bin_path.R`
      (`env_bin_search_dirs()`, `resolve_env_bin_path()`) searching every
      real Windows Conda-env binary directory, trying every `PATHEXT`
      extension, before ever falling back to the ambient `PATH`.
      `run_bin()`'s `cmd_path` resolution and its `withr::local_path()`
      prefix now both use it; `run_pipeline()` resolves `cmd_vec[1L]`
      through it before spawning, falling back to the bare name (existing
      "command not found" behavior, unchanged) only when the environment
      itself doesn't have it. Verified clean on `kappa`: `test-run_bin.R`
      (was 1 failure, now 0) and `test-run_pipeline.R` (was 1 failure, now
      0), no regressions on Linux (`test-run_bin.R`/`test-run_pipeline.R`
      both still 0 failures).
- [x] **Real bug, but not `condathis`'s**: `test-run.R`'s `"does not
      deadlock when stdout and stderr are both large"` still failed on
      `kappa` after the fix above (`stderr` came back as a single
      character instead of 200,000). Isolated via a sequence of minimal
      repros on `kappa`: bypassing `run()`'s `micromamba run` wrapper
      (spawning `bash` directly) made the failure disappear entirely,
      pointing at `micromamba run` itself. Confirmed directly: a bare
      `bash -c "echo '100% done'"` run through `micromamba run -n <env> --
      bash -c "..."` comes back as `'100 done'` — **`micromamba run`
      silently strips literal `%` characters somewhere in its own Windows
      argument handling**, corrupting this test's `printf '%*s' N ''`
      byte-generation idiom's format string (and any other command
      containing a bare `%`). `run_pipeline()` spawns commands directly
      (no `micromamba run` hop — see above), so its own, otherwise
      identical, `printf '%*s'`-based deadlock regression tests are
      unaffected; this is specific to arguments crossing the
      `native_cmd()`/`micromamba run` wrapper that `run()`/`run_bin()`
      always use. Not a `condathis` bug and not fixed in `condathis` code;
      fixed by changing the test's own byte-generation idiom to `head -c N
      /dev/zero | tr '\0' 'X'`, which avoids `%` entirely and was
      independently verified correct on `kappa` through the exact same
      `micromamba run` path. Worth remembering for any future test (or
      real usage) that pipes a `%`-containing command through `run()`/
      `run_bin()` on Windows.
- [x] Also fixed, smaller: `test-run_bin.R`'s `"sets an activated PATH
      like run()"` wasn't testing a missing feature — Windows Conda envs
      have no `bin` subdirectory at all (binaries sit at the prefix root,
      per the `resolve_env_bin_path()` finding above), and the PATH string
      the test captured is translated differently depending on which
      subprocess reads it (`/cygdrive/c/...` via Rtools' own `bash`,
      `/c/...` via a directly-spawned native exe) — neither matches the
      `C:/...` form `fs::path()` produces. Made the assertion check the
      OS-appropriate directory (prefix root on Windows, `<prefix>/bin`
      elsewhere) and drop the drive-letter prefix before matching, so one
      test works on every platform instead of needing a skip.
- [x] Corrected the `PROCESSX_PS[0-9]` fix from the section above (see the
      correction note there) — same "caches per `env_name`" test, same
      noise-filter mechanism, still flaky on Windows because the fix
      applied there didn't actually match the variable's real (hex, not
      decimal) format.
- [x] All fixes verified against real `kappa` (Windows 11) via SSH, using
      a fresh, disposable, non-git scratch checkout (`condathis-verify-ci`,
      populated via `tar`/`scp`, never touching the pre-existing git
      checkout on `kappa` that had unrelated uncommitted work in
      progress) — cleaned up afterward, including orphaned
      `Rscript.exe`/`bash.exe` processes left by an intentionally-hanging
      repro (see the process-hygiene note above; still applies).
      `test-get_micromamba_activation_envvars.R`,
      `test-run_bin.R`, `test-run_pipeline.R`, `test-run.R`: 0 failures
      each on `kappa` after all fixes (only pre-existing, benign
      `unknown timezone`/`linux_pdeathsig is ignored` warnings remain).
      `test-install_packages.R`'s new cross-platform test and all other
      touched files verified separately on Linux (773+ assertions, 0
      failures, 0 warnings).
- [x] Not committed yet — left as working-tree changes for review:
      `R/get_micromamba_activation_envvars.R`, `R/resolve_env_bin_path.R`
      (new), `R/run_bin.R`, `R/run_pipeline.R`,
      `tests/testthat/test-get_micromamba_activation_envvars.R`,
      `tests/testthat/test-install_packages.R`,
      `tests/testthat/test-run_bin.R`, `tests/testthat/test-run.R`.
