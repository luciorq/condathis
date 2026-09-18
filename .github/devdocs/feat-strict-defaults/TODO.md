# TODO: feat-strict-defaults

- [x] Drop bioconda from all default `channels` formals + format_channels_args fallback
- [x] Reorder all `channel_priority` formals to strict-first (9 call sites)
- [x] Update roxygen @param text (defaults + explicit-bioconda guidance)
- [x] Update default-assertion tests (format_channels_args, parse_strategy_channel_priority)
- [x] NEWS.md breaking-change bullets
- [x] Verify bioconda:: spec-prefix behavior empirically (dry-run probe)
- [x] roxygenize + lint + full test suite (verified 2026-09-17: roxygenise
      produces no diff, `just lint` passes, full suite runs in CI on all 5
      platforms at 6c57846)
- [x] CI green on stack layer 3 (r-cmd-check + pkgdown, 6c57846, 2026-09-07)

Open items deferred past 0.2.0 are collected in `../post-0.2.0/`.
