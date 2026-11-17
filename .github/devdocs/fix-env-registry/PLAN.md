# PLAN: Fewer and cleaner lines in `~/.conda/environments.txt`

## Overview

`~/.conda/environments.txt` (in `%USERPROFILE%` on Windows) is the list of
environments that conda and mamba share. `micromamba create` appends every
environment it creates to it, and no setting stops that
(`register_env()` in libmamba's `environments_manager.cpp`). condathis
0.2.0 runs `micromamba create` with the home `<root>/home`, so the
registry is not touched, except when micromamba needs the real home
(`micromamba_create_keeps_home()`): saved credentials, an environment
file that names the home, and any file with pip packages. `remove_env()`
left the line of the removed environment, because `micromamba env remove`
with the real home rewrites the whole file (it drops every line that is
not an environment at that moment, and sorts the rest).

Found 2026-11-16 while writing the mizu article
(`vignettes/articles/python-and-mizu.qmd`): its two environment files
have `pip:` sections, so every render left two stale lines, on a machine
with no pip, uv or `.netrc` file at all.

## Decisions (2026-11-17)

The user was offered three options: narrow the `pip:` rule; make
`remove_env()` delete exactly its own line; leave it. The user chose both
changes ("Yes for all"), and the removal of the six stale lines that the
tests of 2026-11-16 had left in the user's own registry.

### 1. A `pip:` section keeps the home only when pip or uv needs it

`micromamba_pip_needs_home()` (`R/native_cmd.R`) lists the user files
that depend on the home, from pip 26.2's sources
(`configuration.py`, `utils/appdirs.py`, `network/auth.py`) and uv's
docs (`reference/storage.md`, `concepts/authentication/http.md`):

- pip: `~/.pip/pip.conf` (Windows `~\pip\pip.ini`); Linux
  `$XDG_CONFIG_HOME/pip/pip.conf` else `~/.config/pip/pip.conf`; macOS
  `~/Library/Application Support/pip/pip.conf` if that directory exists,
  else `~/.config/pip/pip.conf` (no XDG there).
- uv: `$XDG_CONFIG_HOME/uv/uv.toml` else `~/.config/uv/uv.toml`; the
  `uv auth` store `$XDG_DATA_HOME/uv/credentials/credentials.toml` else
  under `~/.local/share` (Linux and macOS).
- A `keyring` program on `PATH` (pip's keyring provider).
- `.netrc`/`_netrc` were already checked for every create.
- Windows `%APPDATA%`/`%LOCALAPPDATA%` locations of pip and uv come from
  the Known Folder API, not from `USERPROFILE`, so they need no home.

The check errs on the side of keeping the home (an unreadable file, any
`~/` or home variable still keeps it).

With the moved home on macOS, pip's cache would be
`<root>/home/Library/Caches/pip`, which `clean_cache()` does not delete.
`micromamba_cmd_overlay()` sets `PIP_CACHE_DIR` to the user's
`~/Library/Caches/pip` for `create` (unless the user set it), which keeps
the documented behaviour.

### 2. `remove_env()` deletes exactly its own line

`micromamba_unregister_env()` (`R/micromamba_registry.R`), called by
`micromamba_backend_remove_env()` after the directory is gone:

- Matches lines as libmamba writes them (absolute path, no trailing
  separator, `\r\n` on Windows), with `/` for `\` and without case on
  Windows; the env dir is matched as condathis names it and as its real
  path (taken before the removal).
- Keeps every other line byte for byte, with its own line ending.
- Does not touch the file when no line matches.
- Writes a file in the same directory and renames it over the registry;
  keeps the file mode on Unix. libmamba takes no lock either.
- Best effort: any failure is swallowed, and the removal still succeeds.

`micromamba env remove` still runs with `<root>/home`, so libmamba never
rewrites the user's file.

## Verification

- Linux: `test-native_cmd.R`, `test-footprint.R` pass with no skips; the
  footprint test now expects the line to go on removal (credentials
  case) and keeps the stale line of another tool. End to end on the real
  home: a `pip:` env leaves the registry byte-identical through create
  and remove; a line added by hand is removed and the rest is identical.
- macOS (omicron), Windows (kappa), 2026-11-17: the same two test files
  pass with no skips, and the same end-to-end checks pass; on Windows the
  line is written with backslashes and CRLF and is removed byte-exactly,
  and the rename replaces the file. On macOS, pip's cache stays in
  `~/Library/Caches/pip`, and nothing is created under
  `<root>/home/Library/Caches`.
