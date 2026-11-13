# TODO: pixi environments

Checklist companion to `PLAN.md` in this folder.

## Done

- [x] Run commands in a pixi environment through `env_path()` with the
      rattler and the micromamba backends (2026-11-11, Linux; see
      PLAN.md "Findings")
- [x] Find out how pixi, conda, micromamba and `rattler_lock` read
      environment files and pixi.lock v6 and v7 (2026-11-13, Linux; see
      PLAN.md "Files and pixi")
- [x] The micromamba backend refuses pixi.lock (by contents or by the
      `format` names `rattler-lock-v6`, `rattler-lock-v7`, `pixi`) and
      directories, with a reason, before anything runs (2026-11-13, in
      the uncommitted `env_definition()` work)

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

### pixi.lock in rattlerthis (PLAN.md "What a pixi-style backend would take")

- [ ] Check which `rattler_lock` release pairs with the
      `rattler_conda_types` version that rattlerthis pins (only 0.34.12
      was checked: it pins `rattler_conda_types =0.58.1`), and measure
      the vendor size and the MSRV it needs (new pep440/pep508 crates)
- [ ] Read pixi.lock in `rattler_backend_describe_definition`:
      `kind = "lock"`, `platforms` of the chosen environment, and
      `records` from `conda_repodata_records(platform)`. Detect it by
      contents, since `classify()` reads `pixi.lock` as a spec list
      today
- [ ] Option `environment` (default `"default"`); refuse an unknown
      environment name with the list of names in the lock
- [ ] Refuse PyPI entries and source packages, or hand PyPI entries to
      the existing pip step; decide which
- [ ] Install through the existing no-solve path (`rt_install_explicit()`
      or rattler's installer on the records)
- [ ] Test v6 and v7 locks made by pixi, and one from an older pixi
      (versions 1 to 5 are listed by the crate but not tested), on Linux,
      omicron and kappa
- [ ] Add `rattler-lock-v6`, `rattler-lock-v7` and `pixi` to its
      `backend_definition_formats`, so the micromamba refusal names
      rattler as a backend that reads the file
- [ ] Depends on rattlerthis opting in to environment definitions:
      `../feat-backend-abstraction/TODO.md`, decision 22

### Docs and watching upstream

- [ ] Document the workaround for micromamba users:
      `pixi workspace export conda-explicit-spec`, then
      `create_env(env_definition(<that file>), ...)`. Decide whether it
      goes in `?env_definition` or in the backends article
- [ ] Decide whether a pixi-binary backend should take a workspace
      directory, as `env_definition("path/to/project", environment = ...)`
      with `pixi install --frozen`. It conflicts with names as identity
      (PLAN.md "What a pixi backend could add")
- [ ] Watch conda-lockfiles for pixi.lock v7 (issue #178, PR #143) and
      mamba releases after 2.10.0 for pixi.lock support; update the
      table in PLAN.md when either changes
- [ ] (Low priority) Check whether the `nodefaults` URL that
      `pixi init --import` wrote is a known pixi bug
