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
