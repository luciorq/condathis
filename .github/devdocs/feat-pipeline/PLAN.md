# Plan: Processx 3.9.0 Pipeline Support for condathis

## Overview

Add **cross-platform Unix-style pipeline execution** (`cmd1 | cmd2 | cmd3`) to
condathis using the new `processx` 3.9.0 R6 classes and pipe API.

Each command in the pipeline can run in a **different Conda environment**. Data
flows between processes via kernel-level pipes (Unix) or named pipes (Windows) —
no data passes through R for intermediate stages.

## Key Design Decisions

### Per-command environment activation

Since `processx::pipeline$new()` accepts a single `env` for all processes,
per-command environments are handled by creating individual
`processx::process$new()` calls with per-process `env = c("current", ...)`.
The `"current"` sentinel inherits the parent's clean conda env (via
`get_clean_conda_envvars()`), then overlays environment-specific activation
variables (`CONDA_PREFIX`, `CONDA_DEFAULT_ENV`, `CONDA_SHLVL`, `PATH`, etc.)
via `get_activation_envvars()`.

This is a deliberate trade-off: `run_pipeline()` does **not** go through
`micromamba run`, so package-shipped `activate.d` hook scripts (used by some
bioconda packages to set extra env vars) are not executed, unlike `run()`.

### No shell wrappers

The implementation uses `processx::conn_create_pipepair()` to connect processes
directly — no `sh -c` wrappers. This works identically on Linux, macOS, and
Windows.

### S3 return types (`condathis_pipeline` and `condathis_result`)

`run_pipeline()` returns a `condathis_pipeline` S3 object with per-process
status, stdout (only last process), stderr, and PID, nested under
`$processes`.

`run()` and `run_bin()` were later reconciled to match: they now return a
`condathis_result` S3 object (`R/run_result.R`) instead of a plain
(unclassed) `processx::run()` list. `condathis_result` is a plain list under
the hood — `res$status`, `res$stdout`, `res$stderr`, `res$timeout` behave
exactly as before, so this is non-breaking for existing callers (including
`parse_output()`, which only requires list-like `$stdout`/`$stderr` access)
— with `pid`, `cmd`, and `env_name` fields added, plus `format()`/`print()`
methods, mirroring the per-process shape used inside
`condathis_pipeline$processes`.

### Crash safety (`supervise`, `cleanup_tree`, `linux_pdeathsig`)

`run_pipeline()` creates every process with these three arguments, defaulting
to `supervise = TRUE, cleanup_tree = TRUE, linux_pdeathsig = FALSE` — but,
after reconciliation, they are overridable parameters rather than hardcoded.

`run()` and `run_bin()` gained the same three parameters, defaulting to
`FALSE` (preserving prior behavior, and matching `processx`'s own defaults)
so existing callers see no behavior change unless they opt in.

### Writable stdin (`stdin = "|"` + `input`)

A process's stdin can be `"|"` (a pipe) with in-memory data supplied via the
`input` argument, written with `process$write_input()` and then closed.
`input` is rejected unless `stdin = "|"`.

`run_pipeline()` had this from the start (first process only). `run()` and
`run_bin()` gained it during reconciliation — but they can't get it for free,
because `processx::run()` provides no way to reach the `stdin = "|"`
connection it creates internally. Confirmed empirically: calling
`processx::run(stdin = "|")` directly deadlocks (times out) since nothing
ever writes to or closes that pipe. So `R/run_process_with_input.R` adds a
`processx::process$new()`-based helper — spawn, write `input`, close stdin,
`$wait()`, collect `status`/`stdout`/`stderr`/`pid` — used by `native_cmd()`
and `run_bin()` **only** when `stdin = "|"` is requested; the common
`stdin = NULL`/file-path path is untouched and still goes through
`processx::run()` unchanged.

To keep error handling identical either way, the helper returns a
`processx::run()`-shaped list on success, and on non-zero exit (when
`error_on_status = TRUE`) throws a condition with class
`"system_command_status_error"` and `status`/`stderr` fields — the same
minimal contract a real `processx::run()` failure carries (verified
by inspecting a live failure's condition object) — so the existing,
unmodified `rethrow_error_run()` catches and formats it identically,
regardless of which code path actually ran the process. A missing
executable is not special-cased either: `process$new()`'s raw
`rlib_error_3_0`/`c_error` condition is left to propagate, which
`rethrow_error_run()` already catches the same way it does for a normal
`processx::run()` "command not found" failure.

Trade-off, documented in the `input` parameter docs: this path has no live
stdout/stderr streaming, spinner, or timeout — it's a synchronous
write-then-wait, unlike `processx::run()`'s full-featured polling loop.

### Per-command `stdout`/`stderr` overrides

The `cmds` named-list spec accepts per-command `stdout` and `stderr`. `stderr`
may be overridden on any command. `stdout` may only be overridden on the
**last** command — every other command's stdout is a kernel pipe to the next
command and cannot be redirected elsewhere without a `tee`-like mechanism,
which is out of scope.

### Error semantics (`error = "cancel"` / `"continue"`)

All processes that successfully spawn run to completion (or natural SIGPIPE
termination); their exit statuses are then collected. If any exited
non-zero:

- `error = "continue"`: return the `condathis_pipeline` result as-is, with
  per-command `status`/`stderr` reflecting the failure. No error is thrown.
- `error = "cancel"` (default): kill any still-alive processes and throw a
  `condathis_pipeline_status_error` listing every failed command with its
  exit status and (brace-escaped) stderr.

This mirrors `run()`'s `error` contract as closely as the multi-process shape
allows, including for commands that never spawn at all (see below) — the
first implementation only respected `error` for commands that spawned and
then exited non-zero; that gap has since been closed.

### Handling commands that fail to spawn ("spawn failures")

Two situations mean a command in the pipeline never actually starts:

1. **Command not found** (or another `processx` startup failure) —
   `processx::process$new()` throws synchronously.
2. **Target Conda environment does not exist** — detected up front by
   `precreate_envs()`, before any process is spawned.

Both are folded into a single `spawn_failures[[i]]` mechanism inside
`run_pipeline()`:

- Each command slot that fails to spawn gets a synthesized result —
  `status = 127L` plus a descriptive `stderr` message ("System command 'X'
  not found" or "Conda environment 'X' does not exist") — instead of a real
  `processx` process handle.
- These synthesized results flow through the exact same status-collection
  and failure-reporting path as real process exits, so `error = "continue"` /
  `"cancel"` behave consistently regardless of *why* a command failed.
- For a missing **custom** (non-default) Conda environment specifically,
  `error = "cancel"` still fails fast, before spawning anything — matching
  the original, tested behavior — while `error = "continue"` defers the
  failure into the per-command result instead of aborting the whole
  pipeline.
- `processx::process$new()` is wrapped in `tryCatch()` (classes
  `system_command_status_error`, `rlib_error_3_0`, `c_error` — the same set
  `rethrow_error_run()` catches for `run()`) so a raw, uncaught `processx`
  error never escapes `run_pipeline()`, matching `run()`'s behavior for a
  missing executable.

### Safe error-message interpolation

`cli::cli_abort()` treats `{`/`}` in every element of `message` as glue
syntax. Captured stderr, per-command `cmd` strings, and `env_name` values are
arbitrary text and are escaped (`{` → `{{`, `}` → `}}`) via
`escape_cli_braces()` before being embedded in the `condathis_pipeline_status_error`
message — mirroring the escaping `rethrow_error_run()` already does for
`run()`'s error messages.

## Architecture

```
Parent R process
  withr::local_envvar(get_clean_conda_envvars(...))

  precreate_envs()                     # auto-create default env; collect
                                        # missing custom env names (or abort
                                        # immediately if error = "cancel")

  pipe1 <- conn_create_pipepair()      # proc1 → proc2
  pipe2 <- conn_create_pipepair()      # proc2 → proc3 (if applicable)

  for each command i:
    if env_name_i is missing (continue mode):
      spawn_failures[[i]] <- synthesized "env does not exist" result; skip
    else:
      tryCatch(
        procs[[i]] <- process$new(cmd_i,
          stdin   = if first: stdin_src else pipe(i-1)$read,
          stdout  = if last: stdout_target else pipe(i)$write,
          stderr  = stderr_target_i,
          env     = c("current", get_activation_envvars(env_i)),
          supervise = TRUE, cleanup_tree = TRUE),
        <processx startup error classes> = record spawn_failures[[i]]
      )

  # Close parent's pipe-end references (prevent hangs)
  # Write `input` to first process if stdin = "|", then close it
  # Wait for all successfully-spawned processes
  # Collect per-process: status, stdout (last only), stderr, pid —
  #   using spawn_failures[[i]] directly where a command never started
  # error = "cancel" + any failure: kill survivors, throw
  #   condathis_pipeline_status_error (brace-escaped message)
```

## Files

| File                     | Action                                                      |
|--------------------------|-------------------------------------------------------------|
| `DESCRIPTION`            | `processx` → `processx (>= 3.9.0)`                          |
| `R/native_cmd.R`         | Added `cleanup_tree`, `encoding`, `linux_pdeathsig`, `input`, `supervise`; branches to `run_process_with_input()` when `stdin = "|"` |
| `R/conda_activation.R`   | `get_activation_envvars()` helper                           |
| `R/pipeline_result.R`    | S3 `condathis_pipeline` class (`format`/`print`/`as.list`)  |
| `R/run_result.R`         | **New** — S3 `condathis_result` class (`format`/`print`/`as.list`), returned by `run()`/`run_bin()` |
| `R/run_process_with_input.R` | **New** — shared `process$new()`-based helper for `stdin = "|"` + `input`, used by `native_cmd()` and `run_bin()` |
| `R/run_pipeline.R`       | `run_pipeline()` main function + internal helpers: `parse_cmds_spec()`, `check_stdout_overrides()`, `precreate_envs()`, `escape_cli_braces()`, `kill_processes()`; `supervise`/`cleanup_tree`/`linux_pdeathsig` now parameters; new `activate = TRUE` toggles real vs. hand-rolled activation |
| `R/run.R`                | Added `input`, `supervise`, `cleanup_tree`, `linux_pdeathsig`; returns `condathis_result`. **Deliberately not given an `activate` argument this round** |
| `R/run_bin.R`            | Same additions as `R/run.R`; branches to `run_process_with_input()` when `stdin = "|"`; new `activate = TRUE` overlays real `micromamba run` activation (skipped gracefully if `env_name` doesn't exist) — validated to match `run()`'s `CONDA_PREFIX`/`PATH` |
| `R/run_internal_native.R` | Forwards `input`/`supervise`/`cleanup_tree`/`linux_pdeathsig` to `native_cmd()` |
| `R/get_micromamba_activation_envvars.R` | `get_micromamba_activation_envvars()`, real `micromamba run` activation resolution + caching. Now wired into `run_bin()`/`run_pipeline()` via `activate = TRUE` |
| `R/condathis-package.R`  | **New** — `.onLoad()` resolves and caches `R.home("bin")`-derived `Rscript` path at package load time (`get_condathis_rscript_path()`), fixing an `R_HOME`-corruption bug (see below) that only surfaced once `get_micromamba_activation_envvars()` was called from inside a caller's own `get_clean_conda_envvars()` scope |
| `NAMESPACE`              | `export(run_pipeline)`; new S3 methods for `condathis_result`  |
| `tests/testthat/test-native_cmd.R` | Extended for `linux_pdeathsig`                       |
| `tests/testthat/test-run_pipeline.R` | Pipeline tests, incl. spawn-failure, mixed-env, crash-safety-override, and `activate` tests |
| `tests/testthat/test-run.R`, `test-run_bin.R` | `condathis_result` class, `input`/`stdin = "|"`, crash-safety params, `activate` (incl. `run_bin(activate = TRUE)` vs `run()` equivalence) |
| `tests/testthat/test-get_micromamba_activation_envvars.R` | Resolution correctness, noise filtering, caching, cache invalidation, `R_HOME`-corruption-inside-caller's-scope regression test |
| `README.qmd` / `README.md` | "Known Caveats" updated — pipes and writable stdin are now supported |
| `NEWS.md`                | Changelog entries                                            |

## Open Questions (Answered)

1. **Partial failure**: Wait for all spawned processes to finish, then
   collect statuses. If any failed (including commands that never spawned),
   kill all survivors and error (like shell pipeline behavior) — unless
   `error = "continue"`.
2. **`stdin = "|"`**: Yes, supported for the first process, with the `input`
   argument for supplying in-memory data.
3. **Crash safety**: Yes, `supervise = TRUE` + `cleanup_tree = TRUE` on
   every process.
4. **Commands that fail to spawn (missing executable / missing custom
   env)**: Treated as a synthesized `status = 127` result for that command,
   flowing through the normal `error = "cancel"` / `"continue"` handling —
   not a special uncaught error path.

## Known, intentional divergences from `run()` / `run_bin()`

Crash safety, writable `stdin = "|"` + `input`, and return-shape parity have
since been reconciled (see the sections above) — `run()`, `run_bin()`, and
`run_pipeline()` now share the same parameters and the same family of S3
result classes. Two divergences remain, and are structural rather than
parameter gaps, so they are not planned to be reconciled:

- **No `verbose` parameter on `run_pipeline()`.** It always runs silently;
  there is no live command echo or spinner support like `run()`'s
  `verbose = "cmd"/"output"/"full"`. Reconciling this would require
  `run_pipeline()` to poll and interleave output across N concurrently
  running processes rather than one, which is a materially different
  problem from `processx::run()`'s single-process polling loop.
- **Environment activation mechanism — now closable via `activate`,
  `run()` itself intentionally untouched this round.** `run()` still
  always goes through `micromamba run -n <env>` (executes `activate.d`
  hooks). `run_pipeline()`'s per-process activation and `run_bin()`'s
  (previously nonexistent) activation now share a real, `activate.d`
  -inclusive mechanism too: both gained an `activate = TRUE` argument
  that, when the target env exists, overlays
  `get_micromamba_activation_envvars(env_name)` — the same env-var-overlay
  shape `get_activation_envvars()` already used, just resolved via a real
  `micromamba run` instead of a fixed, hand-rolled var list.
  `run_pipeline(activate = FALSE)` and `run_bin(activate = FALSE)` fall
  back to the original mechanisms (hand-rolled overlay, and no activation
  at all, respectively). Validated `run_bin(activate = TRUE)` against
  `run()` directly: identical `CONDA_PREFIX` and activated `PATH` for the
  same `env_name`.
  Costs and caveats carried over from `get_micromamba_activation_envvars()`
  still apply: the nested-activation artifact limitation (documented
  above) is unresolved, and the first pipeline/`run_bin()` call touching a
  given `env_name` with `activate = TRUE` pays for two extra subprocess
  spawns (mitigated by the per-`env_name` cache).
  **A second instance of the `R_HOME`-corruption bug was found while
  wiring this in** (`get_clean_conda_envvars()` sets `R_HOME = ""` via
  `withr::local_envvar()`, corrupting subsequent `R.home()` calls anywhere
  up the call stack for the scope's duration): `run_bin()`/`run_pipeline()`
  apply their *own* clean-envvar scope before calling
  `get_micromamba_activation_envvars()`, so the original fix (resolve
  `R.home()` before *that function's own* clean-envvar scope) wasn't
  sufficient — the caller had already corrupted it first. Fixed properly
  by resolving `R.home("bin")` once at package load time
  (`.onLoad()` in `R/condathis-package.R`, exposed via
  `get_condathis_rscript_path()`), before any condathis function has had a
  chance to touch `R_HOME` — this sidesteps the ordering problem entirely,
  since per-caller ordering fixes don't compose when clean-envvar scopes
  nest.
  `run()` itself was deliberately left unchanged in this round (explicit
  scoping: "before trying to modify `run()`"); consolidating `run()` with
  `run_bin(activate = TRUE)` — resolve activation vars once, then run like
  `run_bin()` with that overlay, instead of wrapping the command in
  `micromamba run` — remains the candidate follow-up sketched in the
  "S3 return types" section above, not yet started.

`run_pipeline()` remains a distinct execution mode (parallel spawn + kernel
pipes) with different constraints than `run()`'s single `micromamba run`
invocation; the `verbose` divergence above follows directly from that, not
from an unaddressed parity gap.

## Additional work landed on this branch (unrelated to the pipeline feature)

Not part of the pipeline design above — recorded here only because both
shipped on `feat-pipeline` as separate follow-up requests, see TODO.md for
the checklist.

### `install_packages()` channel-mismatch warning

`create_env()` and `install_packages()` both accept independent `channels`/
`additional_channels` arguments and always pass `--override-channels`, so
nothing previously connected the channels an environment was originally
built with to the channels used in a later `install_packages()` call —
e.g. `create_env("python", channels = "conda-forge")` followed by
`install_packages("fastqc", channels = "bioconda")` silently drops
`conda-forge` for that install.

Rather than tracking channels in a condathis-side cache (which would drift
from reality if the environment were modified outside condathis), the
channels an environment actually used are recovered from micromamba's own
record: `<env>/conda-meta/history` lists every install transaction as
`+<channel-url>::<pkg>-<version>-<build>` lines. `get_env_history_channels()`
(`R/get_env_history_channels.R`) extracts the channel segment from those
URLs via `stringr::str_match()`, returning `character(0)` when the file
doesn't exist yet (a freshly created, empty environment has none).
`install_packages()` compares that against the current call's
`channels`/`additional_channels` with `setdiff()` and warns
(`condathis_install_missing_previous_channels`) when something would be
dropped — install still proceeds, since dropping a channel isn't
necessarily wrong, just worth surfacing.

### Binary output support (`binary` argument) + two real I/O bugs found and fixed

Also landed on this branch (commit `fa0ea56`, "feat: binary output support"),
prompted by a follow-up article showcasing `run_pipeline()` piping binary
image data (OpenSlide/`libvips` → ImageMagick) between Conda environments —
writing that article surfaced that stdout/stderr were always decoded as
UTF-8 text, corrupting binary payloads captured via `"|"`.

- **New `binary = FALSE` argument on `run()`, `run_bin()`, `run_pipeline()`.**
  When `TRUE`, stdout/stderr are captured as raw vectors instead of decoded
  text. Since `processx` shares one `encoding` between both streams of a
  process, `binary = TRUE` makes *both* streams raw, even if only one
  actually carries binary data — `format()`/`print()`
  (`condathis_result`/`condathis_pipeline`) and `parse_output()` all check
  `is.raw()` on both streams independently rather than assuming only stdout
  can be binary; `parse_output()` aborts with class
  `condathis_parse_output_binary_stream` if asked to parse a raw stream.
  Binary streams are never live-echoed to the console.
- Threaded through: `native_cmd()` already had an unused `encoding`
  parameter (docstring already said `"binary"` for raw output) — `run()` →
  `run_internal_native()` now actually passes it. `run_bin()` threads
  `encoding` to both its `processx::run()` and `run_process_with_input()`
  calls directly (it doesn't go through `native_cmd()`). `run_pipeline()`
  applies it to every process's `encoding` uniformly.
- New `R/read_all_stream_binary.R` (later renamed/expanded, see below)
  because `processx`'s own `read_all_output()`/`read_all_error()`
  accumulate chunks via `paste0(result, self$read_output())` — when
  `encoding = "binary"`, `read_output()` returns a raw vector, and
  `paste0()` coerces `raw` to per-byte hex-string characters (`"68" "65"
  "6c"`) instead of concatenating bytes. Confirmed empirically with a live
  `processx::process`. Fixed by looping `read_output_bytes()`/
  `read_error_bytes()` (which return real raw bytes regardless of the
  process's configured encoding) and `c()`-concatenating instead.

**Two more serious, pre-existing bugs were found while doing this** (not
about `binary` at all — they affect plain text mode too, on any platform,
whenever output is large enough):

1. **Deadlock**: `run_process_with_input()` (used by `run()`/`run_bin()`
   when `stdin = "|"`) and `run_pipeline()` both called `proc$wait()`
   *before* draining any output. Once a process's combined stdout+stderr
   exceeds the OS pipe buffer (64KB on Linux, much smaller on macOS/
   Windows), the child blocks on `write()` to whichever stream isn't being
   read yet, so it never exits, so `wait()` never returns. Confirmed by
   reproducing the hang directly with `processx::process$new()` (200KB on
   each of stdout/stderr, correct shell redirection — an earlier attempt
   with a flawed `1>&2` placement gave a false "still hangs" result, so
   this was re-verified with a corrected command before concluding the fix
   worked). Sequential draining (stdout fully, *then* stderr) has the
   identical failure mode, just with the roles swapped — also reproduced
   and confirmed hanging.
2. **Silent truncation**: `proc$write_input()`'s underlying write is a
   single, non-blocking syscall that can short-write and returns the
   undelivered leftover, which the R wrapper (`write_input()`) discards.
   `run_process_with_input()`/`run_pipeline()` called it once and closed
   the connection immediately — silently truncating any `input` larger
   than the OS pipe buffer, no error. Confirmed on Windows: `input` of
   200,000 bytes delivered only 8,192 to the child, verified independently
   with `wc -c` on the receiving end (isolates the bug to the write side,
   not read-side accounting).

Both fixed by one new shared helper, **`pump_process_io()`**
(`R/read_all_streams.R`, then renamed `R/pump_process_io.R` once its scope
grew past "just draining"): a single loop that polls a process's
stdin/stdout/stderr *together*, retrying the stdin write with whatever
leftover `write_input()` returns, and draining whatever's currently
available on stdout/stderr each iteration — never fully draining one
stream before touching another, and never waiting before reading anything.
Verified empirically (not just reasoned about) against combined
large-input + large-output scenarios in text and binary mode.

- `run_process_with_input()` now calls `pump_process_io(proc, input =
  input, binary = is_binary)` once, replacing the old write→close→wait→read
  sequence entirely.
- `run_pipeline()` calls `pump_process_io()` twice per invocation: once
  up front for the *first* command's `input` (`want_stdout = FALSE`,
  `want_stderr = TRUE` — its stdout is piped straight to the second
  command, never touching R), whose result is cached and reused in the
  main per-process loop instead of re-draining; and once per process inside
  the main extraction loop (`want_stdout = identical(i, n_cmds)`,
  `want_stderr = TRUE`), immediately followed by that process's own
  `wait()` — replacing the old "wait on every process, then read every
  process" two-pass structure. Each process's captured streams are
  independent of every other process's (the inter-process stdout→stdin
  chaining is plain OS-level piping, no R-side buffering), so
  draining/waiting one process at a time is safe.
- New regression tests (`test-run.R`, `test-run_pipeline.R`): round-trip
  200,000-byte payloads through both bugs' exact failure conditions, on
  both `run()`'s `stdin = "|"` path and `run_pipeline()`'s first-command
  `input` and last-command dual-stream cases. Byte-generation initially
  used `yes X | head -c N`, which turned out to be Windows-unreliable (see
  "Open Problem" section below) — replaced with `printf '%*s' N '' | tr '
  ' 'X'`, which terminates deterministically on every platform tested
  (no upstream process to signal-stop).
- Verified cross-platform via SSH against three real machines (`gamma` =
  local Ubuntu/Linux, `omicron` = macOS ARM M2 Pro, `kappa` = Windows 11
  Intel), **using each machine's system R, not a `pixi`-managed R** (an
  earlier pass mistakenly used `pixi`'s `R`/`Rscript` trampolines on
  `omicron`, which the user flagged — re-ran everything against system R
  at `/Library/Frameworks/R.framework/Resources/bin/R` on macOS and
  `C:\Program Files\R\bin\R.bat`/`Rscript.bat` on Windows instead).
  `run()`/`run_bin()` (including the new deadlock/truncation regression
  tests): clean on all three. `run_pipeline()`: clean on Linux and macOS;
  **hangs on Windows** — see below, a separate, pre-existing, unrelated bug
  this investigation surfaced rather than introduced.

## `run_pipeline()` hangs indefinitely on native Windows — fixed

**Status: fixed.** Root cause confirmed and isolated (see below), plus two
independent correctness fixes (`conn_create_proc_pipepair()` +
`poll_connection`, matching `processx::pipeline`'s own reference
implementation). The actual fix landed: `run_pipeline()` now forces
`supervise = FALSE` on Windows specifically (`get_sys_arch()`-gated,
matching the existing `test_os_pkg()` pattern), leaving the `supervise =
TRUE` default untouched on Linux/macOS, where the hang does not occur and
the crash-safety guarantee it exists for is unaffected. Verified with the
full `test-run_pipeline.R` suite (77/77) on all three testbeds after the
fix, including on `kappa` with `NOT_CRAN` correctly propagated (see the
cmd.exe quoting note further down) — genuinely passing, not silently
skipped. Recorded here so the investigation doesn't have to be redone.

### What's confirmed

Any `run_pipeline()` call with **2 or more commands** hangs forever on
native Windows (tested: Windows 11, R 4.6.0, `processx` 3.9.0, system R —
not `pixi`). Confirmed down to the simplest possible case:

```r
run_pipeline(cmds = list(c("echo", "hello"), c("cat")), env_name = "...")
```

This is **not** related to the `binary`/deadlock/truncation work above, and
not caused by anything changed on this branch — `run_pipeline()`'s core
inter-process piping mechanism (`processx::conn_create_pipepair()` +
passing pipe ends to two separately-spawned `process$new()` calls) appears
to have never actually been exercised on real Windows before this
cross-platform verification pass. It is unrelated to the `yes X | head -c
N` shell-command flakiness also found during this session (see below) —
that was a separate, secondary red herring that delayed diagnosis but was
ruled out with a dedicated repro.

### Diagnostic path (three repro scripts, each ruling something out)

1. **`raw_repro.R`** (a scratch script, not part of the package/tests):
   mirrors `run_pipeline()`'s exact internal shape — `conn_create_pipepair()`,
   `process$new()` for command 1 with `stdout = pipe1[[2]]`, `process$new()`
   for command 2 with `stdin = pipe1[[1]]`, close both pipe ends in the
   parent, drain command 1's stderr, `wait()` on command 1, then drain
   command 2's stdout. Result: draining command 1's stderr and waiting on
   it both completed correctly and fast (200,000 bytes, 5 poll iterations).
   **The hang is specifically in reading command 2's (`cat`'s) stdout** —
   `cat` never reaches EOF even though command 1 (its stdin source) already
   exited cleanly (`status = 0`).
2. **`raw_repro2.R`**: same shape, but command 1's command was reduced to
   `echo hi 1>&2; echo hi` — no subprocess pipeline at all. **Same hang**,
   at the same point (draining command 2's stdout). This rules out "an
   extra child process (e.g. from a `yes`/`head`/`tr` subpipeline) leaking
   a duplicate pipe handle" as the cause — there are no extra child
   processes in this version.
3. **`raw_repro3.R`**: same hang reproduced through `run_pipeline()`'s
   actual public API with the trivial 2-command case shown above — confirms
   this isn't specific to the scratch repro's manual pipe handling, and
   isn't specific to any particular command.

### Root cause found: comparison against `processx::pipeline`

The user supplied a working counter-example: `processx::pipeline$new()`
(the CRAN package's own built-in equivalent to `run_pipeline()`) chains
commands correctly on the same Windows machine where `run_pipeline()`
hangs. Diffing its `initialize()` method (`deparse(processx::pipeline$
public_methods$initialize)`) against `run_pipeline()`'s implementation
surfaced three concrete differences, tested one at a time on the Windows
testbed by editing `R/run_pipeline.R`, `scp`-ing it over, and re-running
the minimal `run_pipeline(list(c("echo","hello"), c("cat")))` repro under
an outer `timeout 240` (so a still-hanging attempt self-terminates instead
of blocking indefinitely):

1. **`conn_create_pipepair()` vs `conn_create_proc_pipepair()`.**
   `?processx::processx_connections` documents this explicitly:
   `conn_create_pipepair()`'s ends are **non-blocking**, meant for R-side
   reading/writing (what `pump_process_io()` uses for `stdin = "|"`
   elsewhere in this package); `conn_create_proc_pipepair()`'s ends are
   **synchronous/blocking**, and the docs state this is "required for
   child-process stdin/stdout on Windows". `run_pipeline()` was using the
   wrong one. **Applied. Kept — this is a real correctness bug independent
   of the hang**, matched `conn_create_proc_pipepair()`'s
   write-end-then-read-end element order (opposite of
   `conn_create_pipepair()`'s).
   Tested alone: **did not fix the hang** (`EXIT: 124` under `timeout
   240`).
2. **Closing pipe ends per-iteration vs. deferring all closes until every
   process has spawned.** `pipeline$new()` closes each pipe's write end
   immediately after handing it to its producer, and the previous read end
   immediately after handing it to its consumer — never holding either
   open in the parent longer than necessary. `run_pipeline()` created all
   pipes up front and closed all of them only after the entire spawn loop
   finished. Restructured into a single loop with per-iteration closes,
   matching `pipeline$new()`. **Applied. Kept — also a real hygiene fix.**
   Not tested in isolation (bundled with the same commit as #1); the
   combination of #1+#2 alone still did not fix the hang.
3. **`poll_connection`.** `pipeline$new()` explicitly passes
   `poll_connection = FALSE` for every non-last process, and leaves it at
   the default (`NULL`) only for the last. `run_pipeline()` never set this
   parameter (always the default). Added `poll_connection = if (i <
   n_cmds) FALSE else NULL`. **Applied. Kept — matches the reference
   implementation.**
   Tested with #1+#2+#3 combined: **still did not fix the hang** (`EXIT:
   124`).

None of the above three were the actual cause. The fourth and decisive
difference:

4. **`supervise`.** `processx::process$new()`'s own default is `supervise
   = FALSE`. `pipeline$new()` doesn't expose a `supervise` parameter at
   all, so every process it spawns — including the last one — uses that
   `FALSE` default. `run_pipeline()`, by contrast, **defaults `supervise =
   TRUE`** (intentionally, per its own roxygen docs: "unlike `run()`/
   `run_bin()`... since a pipeline manages multiple concurrently connected
   processes" — i.e. for crash-safety). Isolated by adding an explicit
   `supervise = FALSE` override to the repro call (no source change) and
   re-running on Windows: **completed in 0.66s, no hang.** Confirmed the
   inverse too — re-running the exact same repro with `supervise = TRUE`
   in the same script, right after the `FALSE` case succeeded: **hung
   again**, killed by the same `timeout 240` (`EXIT: 124`), with the
   `FALSE` case's output/timing intact above it in the log. This is about
   as clean an A/B isolation as this kind of bug allows.

   Mechanistically plausible at the time: `supervise = TRUE` spawns an
   extra `supervisor.exe` helper process per child on Windows (confirmed
   via `tasklist` — `supervisor.exe` entries were present, parented under
   the hung `Rscript.exe`, alongside orphaned `cat.exe`). A supervisor that
   inherits its own handle to the piped stdout/stdin would explain exactly
   the observed symptom ("command 2 never sees EOF even though command 1
   already exited cleanly") — the child's own handle closing on exit isn't
   enough if the supervisor watching it still holds a live duplicate.

   **Confirmed by upstream documentation after the fact.** `processx`
   3.9.0's own "Process cleanup" article (`vignette("cleanup",
   package = "processx")`), by the package author, has a "Windows Defender
   caveat" under the supervisor section: *"`supervisor.exe` is a small
   standalone executable bundled with the `processx` package. Windows
   Defender and other antivirus products may flag, quarantine, or block
   it. If `supervise = TRUE` fails on Windows or the supervisor does not
   start, check your antivirus software..."* — and, directly actionable
   for a package author in our exact position: *"If you are a package
   developer using `processx`, consider exposing an option to let users
   disable the supervisor (e.g. via an option or environment variable).
   This gives Windows users a workaround if antivirus software blocks
   `supervisor.exe`."* This doesn't change what was already done (see
   below) but replaces the "plausible hypothesis" framing above with an
   upstream-documented, known Windows failure mode.

**Decision made and applied:** `run_pipeline()` now computes
`effective_supervise <- if (get_sys_arch() matches "^Windows") FALSE else
supervise` and passes that to every `process$new()` call. Chosen over the
alternatives that were on the table:
- Default `supervise` to `FALSE` for every process everywhere (exactly
  matches `processx::pipeline`'s own behavior) — rejected: would silently
  weaken the crash-safety guarantee on Linux/macOS too, where nothing is
  broken.
- Position-based (`supervise = FALSE` for non-last processes only, `TRUE`
  for the last, mirroring the `poll_connection` pattern) — considered but
  never tested (a hand-rolled repro to isolate it hit unrelated script
  bugs and was abandoned once the full-`FALSE`/Windows-only case was
  already conclusively confirmed working). Not pursued further since the
  applied fix already matches upstream's own recommended shape (an
  antivirus-driven, opt-out-by-default-on-Windows workaround), not a
  finer-grained one.

Re-verified with the full `test-run_pipeline.R` suite: 77/77 on Linux,
macOS (`omicron`), and Windows (`kappa`) — the Windows run confirmed
genuinely executing, not silently skipped (see the `NOT_CRAN` cmd.exe
quoting note in TODO.md).

**Possible follow-up, not yet decided or implemented:** upstream's
broader suggestion is a general user-facing escape hatch (option or env
var) to disable the supervisor package-wide, for any `condathis` function,
not just the platform-gated default inside `run_pipeline()`. Worth
considering since `supervise` is currently only a per-call argument — a
user who wants it off everywhere (e.g. to avoid antivirus friction
entirely) has to pass it on every call. Not implemented; would need a
naming/design decision (e.g. `options(condathis.supervise = FALSE)` or
`CONDATHIS_SUPERVISE=false`) and isn't required for the Windows hang,
which is already fixed independent of this.

### Secondary finding along the way: `yes X | head -c N` is unreliable on Windows

While chasing the above, the regression tests' original byte-generation
idiom (`yes X | head -c N`, standard on Linux/macOS) was found to **not
reliably terminate under MSYS2/Windows bash** — `head -c N` closing its
read end doesn't reliably deliver `SIGPIPE` to `yes` the way it does on
real Unix, so `yes` kept writing past `N` bytes (confirmed: a direct shell
test produced 600,618+ bytes for a requested 200,000, still growing when
killed). This is unrelated to the hang above (confirmed by testing both
before and after fixing this) but did cost real debugging time by making
an unrelated test-tooling flakiness look like it might be the same bug.
Replaced with `printf '%*s' N '' | tr ' ' 'X'`, which has no upstream
process to depend on stopping and was verified to produce exactly `N`
bytes on Linux, macOS, and Windows.

### Test-suite Windows portability

Several tests called bare system binaries (`echo`, `cat`, `sort`, `sh`,
`ls`, `printenv`, `tr`, `uniq`, `rev`, `false`) against conda environments
that never installed them, so they only worked by relying on the host's
`PATH` — true on Unix, and on GitHub's `windows-latest` runner only because
Git for Windows happens to be preinstalled and on `PATH`. A plain Windows
machine without Git Bash would fail. This mirrors the design already used
for the mixed-environment pipeline test (`conda-forge::grep`/`sed` on Unix,
`m2-grep`/`m2-sed` on Windows) — extended to every other bare command in
the suite via a new `tests/testthat/helper-cli-tools.R` (`test_os_pkg()`)
and per-file dedicated environments installing `coreutils`/`bash`
(`util-linux` additionally, for `rev`). `sh` calls were changed to
`bash -c`, since neither `coreutils` nor `bash` installs a standalone `sh`
binary. The shared `"condathis-env"` base environment was deliberately
left untouched (not given these packages) since `test-create_base_env.R`
deletes and recreates it empty elsewhere in the suite, and tests run across
parallel worker processes — mutating a widely shared env name risked
flakiness for no benefit; dedicated per-file env names were used instead.

## 2026-07-22: `run_bin()`/`run_pipeline()` binary resolution silently bypasses environment isolation on Windows

**Status: fixed, verified on `kappa`.** Triggered by `r-cmd-check` going
red on `windows-latest` (7 failures) and `macos-latest`/arm64 (1 failure)
on this branch's HEAD. Recorded here in full because two of the seven
Windows failures turned out to share one previously-undiscovered root
cause serious enough to be worth a dedicated write-up — not just a test
fixup — plus a third, unrelated finding about `micromamba run` itself.

### The bug: bare command names never actually go through the target environment on Windows

`run_bin()`'s binary resolution was:

```r
cmd_path <- fs::path(env_dir, "bin", cmd)
if (isFALSE(fs::file_exists(cmd_path)) && isTRUE(fs::file_exists(Sys.which(cmd)))) {
  cmd_path <- normalizePath(Sys.which(cmd), mustWork = FALSE)
}
```

`<env_dir>/bin` is a Linux/macOS-only Conda layout assumption. Confirmed
directly on `kappa`: a Windows environment installing only
`m2-coreutils`/`m2-bash` has **no `bin` directory at all** at its prefix
root — every actual binary (`sort.exe`, `echo.exe`, `cat.exe`, ...) lives
under `Library/usr/bin/` instead (real conda/micromamba activation on
Windows adds `<prefix>`, `Library/mingw-w64/bin`, `Library/usr/bin`,
`Library/bin`, `Scripts`, and `bin`, in that order, to `PATH` — confirmed
against a real captured activated `PATH` string). So `cmd_path` always
failed the existence check, and the code fell through to
`Sys.which(cmd)` — the *ambient* system `PATH`, entirely unrelated to
`env_name`.

Confirmed via direct SSH repro on `kappa` that this isn't hypothetical:

```
> where sort
C:\Windows\SYSTEM32\sort.exe
C:\Users\admin\.pixi\bin\sort.exe
```

`run_bin("sort", stdin = "|", input = "b\na\nc\n", env_name = "...")`
silently resolved to **Windows' own legacy `SYSTEM32\sort.exe`** (the
MS-DOS `SORT` command, not GNU `sort`) instead of the target
environment's coreutils build — which chokes on piped UTF-8 text,
producing literal `???` bytes instead of sorted output (this is
`test-run_bin.R`'s `"supports stdin = '|' with input"` failure). Verified
the fix, not just the symptom, by spawning the *correct* binary's real
path directly via `processx` (bypassing `run_bin()` entirely): produces
correct sorted output every time. This is a real environment-isolation
bypass, not merely a wrong-encoding bug — `run_bin()` was silently
running a different, arbitrary, same-named program instead of the one
belonging to the isolated environment it was asked for.

`run_pipeline()` has the identical root cause via a different code path:
it spawns a bare command name directly —
`processx::process$new(command = cmd_vec[1L], ..., env = c("current",
activation_envvars))` — relying on the OS to locate the executable. But
neither Windows' `CreateProcess` nor POSIX's `execvp()` resolve a bare
command name against the `env =` argument being handed to the *child* —
they resolve it against the *calling* process's own current environment,
before the child's environment block ever takes effect. So the
`activation_envvars`'s correctly-activated `PATH` is never consulted for
the initial spawn at all. Confirmed via `test-run_pipeline.R`'s
`"supports three chained commands"` failure (`echo | tr | rev`, the
`rev` stage returning `NA` stdout) and a direct SSH check on `kappa`:

```
> where rev
INFO: Could not find files for the given pattern(s).
> where tr
C:\Users\admin\.pixi\bin\tr.exe
> where cat
C:\Users\admin\.pixi\bin\cat.exe
```

`rev` isn't reachable anywhere on `kappa`'s ambient `PATH`, so that stage
genuinely failed to spawn — while the *other* stages in the same test
(`echo`, `tr`) only appeared to work by sheer coincidence, because tools
of those names happened to already exist elsewhere on the ambient `PATH`
(Rtools/`pixi`), never actually touching the target `env_name` either.
This means `run_pipeline()`'s Windows binary resolution was silently
broken for *any* pipeline command not coincidentally present elsewhere on
the host's `PATH` — the 2-command tests in the existing suite happened to
only ever use `echo`/`tr`/`cat`/`sort`/`grep`/`sed`, all of which are
common enough to exist on a dev/CI Windows box's `PATH` by accident.

### The fix

New shared helper, `R/resolve_env_bin_path.R`:

- `env_bin_search_dirs(env_dir)`: `<env_dir>/bin` on Linux/macOS; the full
  Windows Conda activation directory list (prefix root,
  `Library/mingw-w64/bin`, `Library/usr/bin`, `Library/bin`, `Scripts`,
  `bin`) on Windows.
- `resolve_env_bin_path(env_dir, cmd)`: searches those directories, trying
  every `PATHEXT` extension on Windows (a bare `fs::file_exists()` check
  does not do the implicit extension search a shell/`CreateProcess`
  would), returning an absolute path or `NULL`. Never falls back to the
  ambient `PATH` itself — that stays the caller's explicit, visible
  decision, not something blurred inside the resolver.

`run_bin()`: `cmd_path` resolution now tries `resolve_env_bin_path()`
first, falling back to `Sys.which()` (unchanged) only when the
environment itself doesn't have the binary — preserving the documented
"falls back to a binary outside any managed environment" behavior for
genuinely-missing commands, while no longer preferring an *ambient*
same-named binary over one that actually exists inside `env_name`. Its
`withr::local_path()` PATH-prefix was also widened from just
`<env_dir>/bin` to every directory in `env_bin_search_dirs()`.

`run_pipeline()`: resolves `cmd_vec[1L]` through
`resolve_env_bin_path(env_dir, cmd_vec[1L]) %||% cmd_vec[1L]` before
spawning — falling back to the bare name, preserving the existing
"command not found" `spawn_failures` behavior unchanged, when the
environment doesn't have it (e.g. the existing
`"this-cmd-does-not-exist-xyz"` test).

Verified on `kappa`: `test-run_bin.R` and `test-run_pipeline.R` both went
from 1 failure each to 0 (only pre-existing, benign `unknown timezone`/
`linux_pdeathsig is ignored` warnings remain). No regressions on Linux
(both files still 0 failures, `pkgload::load_all()` + `test_file()`).

### Unrelated finding along the way: `micromamba run` silently strips `%` characters on Windows

After the fix above, `test-run.R`'s `"does not deadlock when stdout and
stderr are both large"` still failed on `kappa` (`stderr` came back as a
single character instead of 200,000 bytes). Isolated via a sequence of
increasingly narrow repros run directly on `kappa`:

- Spawning `bash` directly (bypassing `run()`'s `native_cmd()` →
  `micromamba run -n <env> -- bash -c "..."` wrapper entirely): the exact
  same command, same `pump_process_io()` drain loop, worked perfectly —
  200,000 bytes on both streams, every time.
- Spawning the same command *through* `micromamba run` (i.e. `micromamba`
  itself as the child, `bash` as its grandchild) reproduced the failure
  reliably, independent of payload size (tried 1,000 through 200,000
  bytes — all truncated to 1 byte).
- Narrowed to the exact trigger with a minimal case: a bare
  `bash -c "echo '100% done'"` run through `micromamba run -n <env> --
  bash -c "..."` comes back as `'100 done'` — the literal `%` character is
  gone. `printf '[%d]' 20` (this test's actual byte-generation idiom,
  `printf '%*s' N ''`, relies on the same mechanism) comes back as
  `'[d]'` — the entire `%d` conversion, argument and all, is silently
  dropped.

This is **a bug in `micromamba run`'s own Windows argument/command-line
handling**, not in `condathis` — confirmed by the fact that spawning
`bash` directly (as `run_pipeline()` already does, never going through
`micromamba run`) preserves `%` correctly, and `run_pipeline()`'s own,
otherwise identical, `printf '%*s'`-based deadlock regression tests
already passed cleanly on `kappa` before and after this investigation.
Not fixed in `condathis` code. Fixed by changing this one test's
byte-generation idiom to `head -c N /dev/zero | tr '\0' 'X'`, which
avoids `%` entirely and was independently verified correct on `kappa`
through the exact same `micromamba run` path. Worth remembering for any
future test — or real user code — that pipes a `%`-containing command
through `run()`/`run_bin()` (both always wrap via `micromamba run`) on
Windows; `run_pipeline()` (spawns directly, no `micromamba run` hop) is
not affected.

### Also touched in the same investigation

- `test-install_packages.R`'s `bioconda::fastqc` test: confirmed against
  bioconda's own repodata (`linux-64`/`osx-64`/`noarch` only, and the
  `noarch` build's own dependencies aren't available for `win-64`/
  `osx-arm64` either) that this is a genuine bioconda platform-support
  gap, not a bug — bioconda has never supported Windows and doesn't ship
  native Apple Silicon builds. Guarded with
  `skip_if_not(system_os() == "linux")`; added a `conda-forge`-only
  cross-platform test exercising the same channel-history-warning logic.
- `test-run_bin.R`'s `"sets an activated PATH like run()"`: not a missing
  feature — Windows has no `<prefix>/bin` at all (see above), and the
  captured `PATH` string is translated differently depending on which
  subprocess reads it (`/cygdrive/c/...` vs `/c/...` vs `fs::path()`'s own
  `C:/...`). Made the assertion OS-aware and drive-letter-agnostic instead
  of skipping it.
- Corrected the `^PROCESSX_PS[0-9]` fix recorded in TODO.md's "caching
  test flaky on `PROCESSX_PS3...`" section: the suffix is a random *hex*
  hash, not a small decimal counter, so `[0-9]` only ever matched by luck.
  Widened to `^PROCESSX_PS`.

### Verification method

All Windows-specific fixes above were verified against the real `kappa`
test-bed (not reasoned about blind) via a fresh, disposable, **non-git**
scratch checkout (`condathis-verify-ci`, populated via `tar`/`scp`),
deliberately not touching the pre-existing git checkout of this repo
already present on `kappa`, which had unrelated uncommitted work in
progress at the time (`git status` showed modified files on `main` before
touching anything). Cleaned up afterward: the scratch directory, plus
orphaned `Rscript.exe`/`bash.exe` processes left behind by one
intentionally-hanging repro script (see the process-hygiene note in
TODO.md — still the right cleanup command:
`taskkill /F /IM <name>.exe /T`).
