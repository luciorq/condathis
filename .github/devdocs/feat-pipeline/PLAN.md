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

### S3 return type

Returns a `condathis_pipeline` S3 object with per-process status, stdout
(only last process), stderr, and PID, nested under `$processes`. This differs
from `run()`/`run_bin()`, which return a plain (unclassed) `processx::run()`
result list — intentional, since a pipeline has multiple per-command results
to carry.

### Crash safety

Each process is created with `supervise = TRUE` and `cleanup_tree = TRUE` for
cross-platform crash safety. This is stronger than `run()`/`run_bin()`, which
don't enable either (not currently exposed as parameters there).

### Writable stdin (`stdin = "|"` + `input`)

The first process's stdin can be `"|"` (a pipe) with in-memory data supplied
via the `input` argument, written with `process$write_input()` and then
closed. `input` is rejected unless `stdin = "|"`. This capability does not
exist on `run()`/`run_bin()`, which only accept a file path or `NULL` for
`stdin`.

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
| `R/native_cmd.R`         | Added `cleanup_tree`, `encoding`, `linux_pdeathsig` params  |
| `R/conda_activation.R`   | `get_activation_envvars()` helper                           |
| `R/pipeline_result.R`    | S3 `condathis_pipeline` class (`format`/`print`/`as.list`)  |
| `R/run_pipeline.R`       | `run_pipeline()` main function + internal helpers: `parse_cmds_spec()`, `check_stdout_overrides()`, `precreate_envs()`, `escape_cli_braces()`, `kill_processes()` |
| `NAMESPACE`              | `export(run_pipeline)`                                      |
| `tests/testthat/test-native_cmd.R` | Extended for `linux_pdeathsig`                       |
| `tests/testthat/test-run_pipeline.R` | Pipeline tests, incl. spawn-failure and mixed-env integration tests |
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

Documented here so they aren't mistaken for bugs later:

- **No `verbose` parameter.** `run_pipeline()` always runs silently; there is
  no live command echo or spinner support like `run()`'s
  `verbose = "cmd"/"output"/"full"`.
- **Environment activation mechanism differs.** `run()` goes through
  `micromamba run -n <env>` (executes `activate.d` hooks). `run_pipeline()`
  sets a fixed handful of env vars directly (see "Per-command environment
  activation" above) and never invokes micromamba.
- **Crash safety is one-directional.** `run_pipeline()` always supervises;
  `run()`/`run_bin()` never do, and don't expose it as a parameter.
- **Writable `stdin = "|"` + `input`** only exists on `run_pipeline()`.
- **Return shape.** Classed `condathis_pipeline` S3 object vs. plain list.

None of these are currently planned to be reconciled; `run_pipeline()` is a
distinct execution mode (parallel spawn + kernel pipes) with different
constraints than `run()`'s single `micromamba run` invocation.
