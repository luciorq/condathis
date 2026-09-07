# feat-strict-defaults: align defaults with plain micromamba

Date: 2026-08-26

## Goal

Housekeeping milestone bringing condathis's dependency-resolution defaults
closer to plain `micromamba` behavior, with stricter resolution:

1. Remove `bioconda` from the default `channels` (now `"conda-forge"` only).
2. Make `bioconda` explicit where needed in docs.
3. Make `"strict"` the default `channel_priority` (was `"disabled"`).

## Key facts established before implementing

- A channel-prefixed MatchSpec (`bioconda::samtools`) resolves correctly
  with only `-c conda-forge` under `--override-channels` + strict
  priority: micromamba adds the spec's channel to the solve, including
  for the package's own bioconda dependencies (verified via
  `micromamba create --dry-run --json --platform` probe; `htslib` came
  from bioconda, `libdeflate` from conda-forge). So spec-prefixed doc
  examples keep working with the conda-forge-only default.
- `rlang::arg_match()` takes the first element of the formal default as
  the effective default, so the `channel_priority` change is a reorder of
  the `c(...)` vector at every signature.

## Touched surface

- Formal defaults (`channels`, `channel_priority`): `create_env()`,
  `install_packages()`, `backend_create_env()`/`backend_install()`
  generics (R/backend.R), their micromamba methods
  (R/backend-micromamba.R), `define_platform()`,
  `packages_search_native()`, `parse_strategy_channel_priority()`, and
  `format_channels_args()`'s NULL fallback.
- Docs: `@param channels`/`@param channel_priority` text; guidance on the
  two explicit-bioconda options (spec prefix vs. channels argument).
  Vignette + README already passed `channels` explicitly - unchanged.
- Tests: `test-format_channels_args.R` and
  `test-parse_strategy_channel_priority.R` default assertions.
- NEWS.md: two Breaking (minor) bullets under 0.2.0's Changed section,
  including the migration note about `install_packages()`'s
  channel-history warning firing for pre-change environments.

## Addendum 2026-09-05: deadlock/timeout fix cluster + convergence goal

Fixes from the pre-release /code-review (findings 1, 3, 4):

- New `pump_pipeline_io()` (R/pump_pipeline_io.R): drains every stage's
  R-side streams concurrently in one `processx::poll()` loop, interleaved
  with writing `input` to stage 1. Replaces the sequential per-stage
  `pump_process_io()` calls that deadlocked on cross-stage backpressure
  (reproduced: `seq 1 500000 | cat` hung forever). Also guards the
  stage-1 `write_input()` against broken pipe (child exited early).
- `settle_pipeline_stage()` (was `drain_pipeline_stage()`): no stream
  draining anymore; enforces the shared deadline with a *bounded*
  `wait(timeout = remaining_ms)` so stages invisible to the pump (no
  R-side pipes, e.g. `stderr = NULL`) still honor `timeout`.
- `run_process_with_input()`: same bounded-wait fix for `run()`/
  `run_bin()` with file-redirected streams.
- Platform notes: `processx::poll()` multi-process polling and
  `wait(timeout=)` are cross-platform; stages with no R-side connections
  are excluded from the poll list; `-9` remains condathis's own
  normalized timeout sentinel on every OS; tests deliberately do not
  assert on a downstream stage's exact post-kill status (EOF-exit vs
  kill is a timing race that differs across platforms).

## North star: run()/run_bin()/run_pipeline() convergence

Stated goal (2026-09-05): the three run functions should converge to the
same argument set and the same behavior/failure contract on every major
OS. Progress so far: shared `condathis_result` shape, shared
`error`/`timeout`/`binary`/`stdin`+`input` semantics, shared `-9`
timeout sentinel, shared child-environment construction
(`build_child_env()`), and (this addendum) shared deadline enforcement
and concurrent stream draining. Known remaining gaps:

- Activation model: `run()` wraps in `micromamba run` (live activation,
  hooks re-run per call, no `activate` argument); `run_bin()`/
  `run_pipeline()` apply the cached activation snapshot with a direct
  spawn. Unifying `run()` onto the resolve-once + direct-spawn model is
  the documented final step (see get_micromamba_activation_envvars.R),
  deferred past 0.2.0 because it changes observable hook semantics.
- Binary resolution: micromamba's activated-PATH search (run()) vs
  condathis's `resolve_env_bin_path()` (run_bin()/run_pipeline()).
- Argument set: `activate` missing from `run()`; `run_pipeline()` has
  pipeline-only extras (`cmds` spec, per-command overrides) by nature.
