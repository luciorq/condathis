# TODO: feat-strict-defaults

- [x] Drop bioconda from all default `channels` formals + format_channels_args fallback
- [x] Reorder all `channel_priority` formals to strict-first (9 call sites)
- [x] Update roxygen @param text (defaults + explicit-bioconda guidance)
- [x] Update default-assertion tests (format_channels_args, parse_strategy_channel_priority)
- [x] NEWS.md breaking-change bullets
- [x] Verify bioconda:: spec-prefix behavior empirically (dry-run probe)
- [ ] roxygenize + lint + full test suite
- [ ] CI green on stack layer 3
