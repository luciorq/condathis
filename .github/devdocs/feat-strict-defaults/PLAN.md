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
