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
| `R/run_pipeline.R`       | `run_pipeline()` main function + internal helpers: `parse_cmds_spec()`, `check_stdout_overrides()`, `precreate_envs()`, `escape_cli_braces()`, `kill_processes()`; `supervise`/`cleanup_tree`/`linux_pdeathsig` now parameters |
| `R/run.R`                | Added `input`, `supervise`, `cleanup_tree`, `linux_pdeathsig`; returns `condathis_result` |
| `R/run_bin.R`            | Same additions as `R/run.R`; branches to `run_process_with_input()` when `stdin = "|"` |
| `R/run_internal_native.R` | Forwards `input`/`supervise`/`cleanup_tree`/`linux_pdeathsig` to `native_cmd()` |
| `R/get_micromamba_activation_envvars.R` | **New** — `get_micromamba_activation_envvars()`, real `micromamba run` activation resolution + caching. Standalone; not wired into anything yet |
| `NAMESPACE`              | `export(run_pipeline)`; new S3 methods for `condathis_result`  |
| `tests/testthat/test-native_cmd.R` | Extended for `linux_pdeathsig`                       |
| `tests/testthat/test-run_pipeline.R` | Pipeline tests, incl. spawn-failure, mixed-env, and crash-safety-override tests |
| `tests/testthat/test-run.R`, `test-run_bin.R` | `condathis_result` class, `input`/`stdin = "|"`, crash-safety params |
| `tests/testthat/test-get_micromamba_activation_envvars.R` | **New** — resolution correctness, noise filtering, caching, cache invalidation |
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
- **Environment activation mechanism differs.** `run()` goes through
  `micromamba run -n <env>` (executes `activate.d` hooks). `run_pipeline()`
  sets a fixed handful of env vars directly (see "Per-command environment
  activation" above) and never invokes micromamba, because
  `processx::pipeline$new()`/`process$new()` takes one `env` per process and
  there is no per-process `micromamba run` wrapper that would still let
  stdout flow directly, kernel-to-kernel, into the next command's stdin.
  `R/get_micromamba_activation_envvars.R` is a first step toward closing
  this specific gap — it resolves the *real* `activate.d`-inclusive
  activation as a plain env-var overlay (same shape as
  `get_activation_envvars()`), decoupled from wrapping the target command
  in `micromamba run`, so it's a candidate replacement for
  `get_activation_envvars()` inside `run_pipeline()`. **Not wired in yet**:
  it has a known limitation (nested-activation artifacts like
  `CONDA_PREFIX_1`/`CONDA_SHLVL` leak through when R itself runs from an
  already-activated environment) and costs two extra subprocess spawns per
  unique `env_name` the first time it's resolved (mitigated by its
  per-`env_name` cache, invalidated on `conda-meta` changes, but not free
  for a pipeline's first run). The same helper is also being considered as
  the mechanism to consolidate `run()` (wraps `cmd` in `micromamba run`)
  with `run_bin()` (no activation at all): resolve activation vars once,
  then run like `run_bin()` with `env = c("current", <vars>)`, rather than
  two separate code paths with different activation semantics.

`run_pipeline()` remains a distinct execution mode (parallel spawn + kernel
pipes) with different constraints than `run()`'s single `micromamba run`
invocation; the two divergences above follow directly from that, not from
an unaddressed parity gap.
