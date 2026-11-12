# TODO: pixi environments

Checklist companion to `PLAN.md` in this folder.

## Done

- [x] Run commands in a pixi environment through `env_path()` with the
      rattler and the micromamba backends (2026-11-11, Linux; see
      PLAN.md "Findings")

## Open

- [ ] Repeat the check on omicron (macOS arm64) and kappa (Windows 11)
      with an environment made by pixi, not a plain Conda prefix
- [ ] Decide whether to document pixi environments in the `env_path()`
      help page or in the backends article
- [ ] Decide whether condathis needs a pixi helper or backend (PLAN.md
      "What a pixi backend could add")
- [ ] If pixi activation is wanted: decide between `pixi shell-hook` and
      reading `pixi.toml`, and how to handle the `CONDA_DEFAULT_ENV`
      difference (PLAN.md limit 3)
