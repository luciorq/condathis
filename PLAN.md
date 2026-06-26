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
variables (`CONDA_PREFIX`, `CONDA_DEFAULT_ENV`, `CONDA_SHLVL`, `PATH`, etc.).

### No shell wrappers

The implementation uses `processx::conn_create_pipepair()` to connect processes
directly — no `sh -c` wrappers. This works identically on Linux, macOS, and
Windows.

### S3 return type

Returns a `condathis_pipeline` S3 object with per-process status, stdout
(only last process), stderr, and PID.

### Crash safety

Each process is created with `supervise = TRUE` and `cleanup_tree = TRUE` for
cross-platform crash safety.

### Error semantics (`error = "cancel"`)

All processes run to completion (or natural SIGPIPE termination), then if any
exited non-zero, all are killed and an error is thrown listing each failed
process with its stderr.

## Architecture

```
Parent R process
  withr::local_envvar(get_clean_conda_envvars(...))

  pipe1 <- conn_create_pipepair()     # proc1 → proc2
  pipe2 <- conn_create_pipepair()     # proc2 → proc3 (if applicable)

  proc1 <- process$new(cmd1,
    stdin   = stdin_src,              # "|", NULL, or file path
    stdout  = pipe1$write,            # kernel pipe to proc2
    stderr  = "|",                    # parent captures per-process
    env     = c("current", get_activation_envvars(env1)),
    supervise = TRUE, cleanup_tree = TRUE)

  proc2 <- process$new(cmd2,
    stdin   = pipe1$read,
    stdout  = if last: "|" else pipe2$write,
    stderr  = "|",
    env     = c("current", get_activation_envvars(env2)),
    supervise = TRUE, cleanup_tree = TRUE)

  # Close parent's pipe-end references (prevent hangs)
  # Write stdin if "|", close it
  # Wait for all processes
  # Collect per-process: status, stdout (last only), stderr, pid
```

## Files

| File                     | Action                                                      |
|--------------------------|-------------------------------------------------------------|
| `DESCRIPTION`            | `processx` → `processx (>= 3.9.0)`                          |
| `R/native_cmd.R`         | Add `cleanup_tree`, `linux_pdeathsig`, `encoding` params    |
| `R/conda_activation.R`   | **New** — `get_activation_envvars()` helper                 |
| `R/pipeline_result.R`    | **New** — S3 `condathis_pipeline` class                     |
| `R/run_pipeline.R`       | **New** — `run_pipeline()` main function                    |
| `NAMESPACE`              | Add `export(run_pipeline)`                                  |
| `tests/testthat/test-native_cmd.R` | Extend for new params                              |
| `tests/testthat/test-run_pipeline.R` | **New** — pipeline tests                            |
| `NEWS.md`                | Changelog entry                                             |

## Open Questions (Answered)

1. **Partial failure**: Wait for all processes to finish, then collect statuses.
   If any failed, kill all and error (like shell pipeline behavior).
2. **stdin = "|"**: Yes, support writable stdin for the first process.
3. **Crash safety**: Yes, use `supervise = TRUE` on each process.
