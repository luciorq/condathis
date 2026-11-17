# feat-run-unify: one run path, clean child environments

Written 2026-11-16, after the work landed in the working tree of 0.2.0
(uncommitted on top of `e6672a4`, "docs(devdocs): record 0.2.0 CRAN
preparation and env_definition() decisions"). Sources: the maintainer's
messages of 2026-11-16, an investigation of how `run()`, `run_bin()` and
`run_pipeline()` differed, a written spec, two implementation steps (the
environment layers, then the one run path) and a docs step. File and line
references are to that working tree.

Related folders:

- `../post-0.2.0/` items 1 and 6 (the `run()` convergence and the
  nested-activation artifacts). This folder does both, in 0.2.0.
- `../feat-strict-defaults/PLAN.md`, "North star": the convergence of the
  three run functions. Done here.
- `../feat-backend-abstraction/` (the backend contract). The generics are
  unchanged. Only the prose of `?register_backend` changed (decision D9).
- `../feat-pipeline/` ("Known, intentional divergences"): the activation
  divergence it describes is closed.

## Status summary

| # | Item | State |
|---|------|-------|
| 1 | L1 isolation layer: undo the activation of the R session | done 2026-11-16 |
| 2 | Every child `PATH` composed from the L1 `PATH` | done 2026-11-16 |
| 3 | Fixed activation for `activate = FALSE`, shared by all three | done 2026-11-16 |
| 4 | Activation stacking sanitation (micromamba backend) | done 2026-11-16 |
| 5 | `run()` gains `activate`; one implementation for `run()` and `run_bin()` | done 2026-11-16 |
| 6 | `run_bin()` superseded, a thin wrapper | done 2026-11-16 |
| 7 | One command lookup rule | done 2026-11-16 |
| 8 | Signal status `128 + n` everywhere, broken pipe 141 | done 2026-11-16 |
| 9 | One resolve-failure wording and hint | done 2026-11-16 |
| 10 | Backend contract prose | done 2026-11-16 |
| 11 | Docs: NEWS, help pages, article, devdocs | done 2026-11-16 |
| 12 | Verification on Linux, omicron and kappa | see *Verification* |
| 13 | rattlerthis test updates | done 2026-11-17, in rattlerthis (uncommitted) |
| 14 | Optional backend hook for `activate = FALSE` | follow-up, after 0.2.0 |
| 15 | `R_LIBS*` of a Conda R | done by D15 |
| 16 | Soft-deprecate `run_bin()` | after 0.2.0 (post-0.2.0 21d) |
| 17 | Smaller follow-ups | open (d, e, f done by D11 to D13) |
| 18 | Commit the work | maintainer |
| 19 | One activation level for every command (D11) | done 2026-11-16 |
| 20 | Windows: R's own prefix leaves the command's `PATH` (D12) | done 2026-11-16 |
| 21 | Windows: lookup on the command's `PATH`, as `cmd.exe` (D13) | done 2026-11-16 |
| 22 | Windows: a program of R's own prefix gets its DLL directories (D14) | done 2026-11-17 |
| 23 | Undo R's own startup in every child (D15) | done 2026-11-17 |
| 24 | A warm call starts only the command: one file-system existence check (D16) | done 2026-11-17 |

## Context

Up to this change, 0.2.0 had three run functions with three slightly
different paths:

- `run()` always activated the environment through the backend and had no
  `activate` argument.
- `run_bin()` had `activate = TRUE`. With `activate = FALSE` it set no
  activation variable at all (`CONDA_PREFIX` stayed `""`), only the
  binary directories of the environment in front of the session `PATH`.
  It looked a command up itself, in the binary directories first.
- `run_pipeline(activate = FALSE)` set a small fixed activation
  (`get_activation_envvars()`), with `CONDA_PREFIX` and the binary
  directories in front of the session `PATH`.

In all three, the child started from a copy of the R session's
environment with the `CONDA_*` and `MAMBA_*` variables cleared
(`get_clean_conda_envvars()`). When R itself ran in an activated Conda or
pixi environment, the `PATH` entries and marker variables of that
activation still reached the command.

## Decisions, in order

All on 2026-11-16.

**D0. The maintainer's answer.** The main thread reported the differences
between the three functions (finding 1 below) and proposed one
implementation, with `run_bin()` kept as a superseded wrapper and
`activate = FALSE` working as in `run_pipeline()`. The maintainer answered
(typos fixed):

> Yes, this change should be made now, before 0.2.0 is submitted to CRAN.
>
> The only point of concern I have is that the `activate = FALSE` should
> actually be a behavior more similar to what you described for
> `run_pipeline(activate = FALSE)`. I am not sure what is the current
> state of env vars passed to the underlying commands, but at some point
> we had a clearer distinction of what are the env vars that condathis
> set to make sure that the current environment don't leak things to the
> new run inside processx. And then the layer of activated env vars that
> comes from the environment where the process was run (something that
> the initial implementation handled through `micromamba run`).
>
> Do you get what I mean? activate = FALSE should still try to run the
> command in the cleanest environment possible. So they are not affected
> by R itself be run in a conda environment or deeply nested
> environments.

The design below (D1 to D10) was agreed in the main thread from that
answer.

**D1. Layers of every child environment block.**

- L0: the R session's environment (`Sys.getenv()`), read only.
- L1, isolation: applied to every child in both modes, and to `base_env`,
  the block that a backend computes its activation against. L1a undoes
  the activation of the R session (D2). L1b is the clean overlay that
  existed before (`get_clean_conda_envvars()`: `TMPDIR`, `CONDA_*` and
  `MAMBA_*` reset, the package cache, `R_HOME = ""`).
- L2, activation. `activate = TRUE`: the backend's activation
  (`backend_resolve_run()`, so `activate.d` scripts and `env_vars.d`
  files), computed against the L1 block. `activate = FALSE`: a fixed
  activation that condathis computes without any backend call:
  `CONDA_PREFIX`, `CONDA_DEFAULT_ENV`, `CONDA_SHLVL=1`, `MAMBA_SHLVL=1`,
  the two prompt modifiers (empty since D11), and `PATH` = the binary directories of the
  environment in front of the L1 `PATH`. No `activate.d`, no
  `env_vars.d`.

**D2. L1 undoes the host's activation.** Remove the stacking and marker
variables of conda, micromamba and pixi; restore the values that the
conda-forge backup conventions saved; remove the variables that a host
prefix's `conda-meta/state` or `env_vars.d` set; remove the binary
directories of every host prefix from `PATH`. Keep `PATH` entries that
come from the user's shell configuration (`<root>/condabin`,
`~/.pixi/bin`). Values that host `activate.d` scripts set cannot be
undone reliably: document the limit. Leave `R_LIBS*` alone and ask the
maintainer (item 15; replaced by D15, which removes every `R_*`
variable).

**D3. Every child `PATH` is composed from the L1 `PATH`,** never from the
session `PATH`. The activation cache key must stay correct.

**D4. `run()` gains `activate = TRUE`** (after `linux_pdeathsig`, before
`timeout`, as in `run_bin()`). `run()`, `run_bin()` and `run_pipeline()`
share one implementation of each mode.

**D5. `run_bin()` stays exported, superseded by `run()`.** Plain text, no
lifecycle dependency, no warning in 0.2.0. A thin wrapper with
`fn = "run_bin"`, so its condition classes stay.

**D6. One command lookup rule:** the one `run()` had. On Linux and macOS
a bare name is kept, and `execvp()` searches the child's `PATH`, so the
program gets its bare `argv[0]` and an `activate.d` `PATH` order holds.
On Windows the binary directories of the environment were searched with
`PATHEXT`, else processx's default applied (replaced by D13). With activation, when the
activation `PATH` names none of the environment's binary directories,
condathis puts them in front. A missing environment still aborts and
never falls back to a program on `PATH`. With `activate = FALSE` no
backend code runs, so a failed existence probe (`NA`, rule R5) let the
call go on: `run()`, `run_bin()` and each pipeline command now check
that the environment directory exists, and report a missing one as
`*_env_not_found` (status 127 under `error = "continue"`).

**D7. Exit status.** A command killed by signal `n` has status `128 + n`
off Windows in `run()`, `run_bin()` and every `run_pipeline()` command.
The timeout sentinel stays `-9`. The pipeline broken-pipe rule follows:
`SIGPIPE` on a command that is not the last one, now 141, is not a
failure.

**D8. One resolve-failure wording and the `activate = FALSE` hint** for
all three functions.

**D9. Backend contract unchanged.** The generics keep their formals
(rattlerthis's `test-registration.R` compares them).
`backend_resolve_run()` is still called only with activation. Only the
prose of `?register_backend` changes. An optional hook for
`activate = FALSE` is a follow-up (item 14).

**D10. `env_path()` handling stays as it was.**

**D11 to D13. The maintainer's answers on the open questions.** The main
thread asked about three defaults it had kept: `MAMBA_SHLVL` and the
prompt modifiers of the fixed activation (`"1"` and `"(<env>) "`, while
the real activations left `MAMBA_SHLVL` `"0"` and
`MAMBA_PROMPT_MODIFIER` empty), R's own prefix staying on `PATH` on
Windows, and the Windows lookup of a name the environment lacks on the
`PATH` of the R session. The maintainer answered (typos fixed):

> 1. `MAMBA_SHLVL` and the prompt modifier: this was previously used to
>    make sure that if R is actually running in a conda / mamba nested
>    call, things don't spill into the internal call. So both
>    `MAMBA_SHLVL` and `CONDA_SHLVL` should be set in all calls, right?
>    They should point to the same value, and the prompt modifier should be
>    empty, right? I think this was the original design intention, and
>    things were lost in the different implementations across `run()`,
>    `run_bin()` and `run_pipeline()`. We should always make the internal
>    call run in the most isolated way possible, making sure that other
>    processes running in the parent process do not affect the internal
>    call, and that it is also not affected by how R itself was called.
>
> Are 2 and 3 only relevant on Windows? If yes, remember the goal is
> isolation and least surprises. Think of how `micromamba run` would work
> in a clean environment.

Measured before the change on Linux (micromamba 2.10.0): `micromamba run`
from an empty environment (`env -i`) gives the command `CONDA_SHLVL=1`,
`CONDA_PROMPT_MODIFIER="(<env>) "` and no `MAMBA_SHLVL` or
`MAMBA_PROMPT_MODIFIER`. condathis gave `activate = TRUE` the commands
`CONDA_SHLVL=1`, `MAMBA_SHLVL=0`, `CONDA_PROMPT_MODIFIER="(<env>) "` and
`MAMBA_PROMPT_MODIFIER=""`, and `activate = FALSE` `1`, `1`,
`"(<env>) "`, `"(<env>) "`. Items 2 and 3 were Windows only: on Linux and
macOS, R's prefix already left `PATH`, and `execvp()` searches only the
child's `PATH`.

**D11. One activation level for every command.** Every command of
`run()`, `run_bin()` and `run_pipeline()` gets `CONDA_SHLVL=1`,
`MAMBA_SHLVL=1` and empty `CONDA_PROMPT_MODIFIER` and
`MAMBA_PROMPT_MODIFIER`, in both modes and for every backend, whatever
the activation and the R session set (`child_activation_level_vars()` in
`R/conda_activation.R`, applied last by `compose_child_env()`). The value
is `1`, not `0`: the command runs in exactly one activated environment
(`CONDA_PREFIX` is set), as after one `conda activate` and as
`micromamba run` reports it, so a `conda activate` or `conda deactivate`
inside the command starts from that level. micromamba's own processes
(`native_cmd()`), which run in no environment, keep `0`, `0`, `""`, `""`
from L1b.

**D12. Windows: R's own prefix leaves the command's `PATH`,** as on Linux
and macOS: a command runs as in a shell where that prefix was never
activated. The reason it stayed (no rpath: a Conda R loads its DLLs from
`Library/bin` and the other binary directories) applies only to the
`Rscript` processes that record an activation. They get the binary
directories of R's prefix at the end of their own `PATH`
(`micromamba_run_path()`, for the `micromamba run` dump and the baseline
dump), and those directories are left out of the recorded activation.

**D13. Windows: a bare name is looked up as `cmd.exe` does,** through
which `micromamba run` started commands: the working directory of the
command, then the command's `PATH`, with the command's `PATHEXT`, a name
without an extension only with one of those extensions (so Rtools' `cmd`
shell script never shadows `cmd.exe`). A name found nowhere fails with
status 127 without reaching processx (`abort_command_not_found()`), whose
`CreateProcess()` lookup searched the folder of R's executable and the
`PATH` of the R session. Off Windows the rule is unchanged (D6).

**D14 and D15. The maintainer's answers of 2026-11-17.** The kappa run
with a conda-forge R (see *Verification*) showed that R's own `Rscript`
cannot start as a command under D12, and that the command still gets the
`R_*` variables of the session. Two options were offered for the first:
(A) give a program of R's own prefix that prefix's directories back,
at the end of its `PATH`, or (B) keep the strict `PATH` and change the
tests. The maintainer: "A sounds reasonable. But we need to also find a
solution for the other R_* vars leaking from the parent to the child
process", and, on the proposal below: "Go ahead with all changes."

**D14. Windows: a command that is a program of R's own Conda prefix**
(such as `file.path(R.home("bin"), "Rscript.exe")`, or a program of its
`Library/bin`) gets the binary directories of that prefix at the end of
its `PATH` (`r_prefix_command_env()` in `R/run_internal_backend.R`,
after `resolve_direct_run_command()` in `run_internal_backend()` and in
the spawn step of `run_pipeline()`). It reuses `micromamba_run_path()`.
Every other command keeps the `PATH` of D12, and the directories of the
environment and of the session still come first. Off Windows nothing
changes: a Conda program finds its libraries through its `rpath`.

**D15. Undo R's own startup in every child** (`undo_r_startup_env()` in
`R/host_env.R`, the last step of `isolate_host_env()`, so it applies to
every child block: the run family, micromamba's own processes and the
activation dumps). The rule is the one of `micromamba run` in a clean
shell, and the same as the one for the `env_vars.d` files of a host
prefix: remove a value when it is exactly what the startup set.

1. On Windows, the entries of each `R_RTOOLS<n>_PATH` are removed from
   the front of `PATH`, where the base profile of R put them.
2. `EDITOR`, `PAGER`, `MAKE`, `SED`, `TAR`, `LN_S`, `CURL_CA_BUNDLE` and
   `MSYS2_ENV_CONV_EXCL` are removed when the session has exactly the
   value of R's startup. From `LD_LIBRARY_PATH`,
   `DYLD_FALLBACK_LIBRARY_PATH` and `DYLD_LIBRARY_PATH`, the part that R
   put in front is removed. A value the user set stays.
3. Every variable named `R_*` or `_R_*` is removed, also one the user
   set (`R_LIBS_USER`, `R_PROFILE_USER`, `R_TESTS` of `R CMD check`):
   only R reads them, and an R that the command starts sets its own.
   `get_clean_conda_envvars()` now removes `R_HOME` (`NULL`) instead of
   setting it to `""`.

The values of step 2 depend on the R installation (`etc/ldpaths`,
`etc/Renviron`, `etc/Renviron.site`). `r_startup_env_vars()` measures
them once per R session: R's own `Rscript --no-init-file`, with an empty
`R_ENVIRON_USER`, started from the session's environment without the
activation of the session, the `R_*` variables and the variables of
step 2, records its environment. The answer is kept in
`condathis_rscript_path_cache$r_startup`. It takes about 0.2 s on Linux.
When the start fails, steps 1 and 3 still apply.

Measured on 2026-11-17, what R's startup adds (R started from an empty
environment on Linux and macOS, compared with its parent shell on
Windows):

| R | Variables |
|---|---|
| every R | `R_HOME`, `R_LIBS_USER`, `R_LIBS_SITE`, `R_ARCH` |
| pixi R, rocker R, macOS CRAN R | `R_SHARE_DIR`, `R_DOC_DIR`, `R_INCLUDE_DIR`, `R_PLATFORM`, `R_SESSION_TMPDIR`, `R_PAPERSIZE`, the `R_*CMD` set, `R_STRIP_*`, `EDITOR`, `PAGER`, `MAKE`, `SED`, `TAR`, `LN_S` |
| rocker R 4.6 | `LD_LIBRARY_PATH=<R>/lib:/usr/local/lib:/usr/lib/x86_64-linux-gnu:<java>/lib/server`, `R_LIBS` |
| macOS CRAN R 4.6 | `DYLD_FALLBACK_LIBRARY_PATH=<R>/lib:<java>/lib/server` |
| Windows CRAN R 4.6 | `R_USER`, `R_COMPILED_BY`, `R_RTOOLS45_PATH`, `CURL_CA_BUNDLE=<R>/etc/curl-ca-bundle.crt`, `MSYS2_ENV_CONV_EXCL`, and the Rtools directories in front of `PATH` |
| conda or pixi R | as its OS, with `R_LIBS_SITE` in the environment's `lib/R/site-library` |

Round 4 found that an R installed by rig creates its default user library
at every start: rig adds a block to the base profile of R (it runs also
with `--vanilla`) that calls `dir.create()` on the first entry of
`R_LIBS_USER`. Without an inherited `R_LIBS_USER`, the `Rscript`
processes of condathis itself (activation dumps, the measurement above)
created `~/Library/R/arm64/4.6/library` (macOS) or
`%LOCALAPPDATA%/R/win-library/4.6` (Windows) in the test sandbox. They
now get `R_LIBS_USER = "NULL"` (`internal_rscript_vars()` in
`R/native_cmd.R`, through the `run` overlay of `micromamba_cmd_overlay()`,
the baseline dump and the measurement): R reads `"NULL"` as no user
library, and rig skips it. An R that a user runs as a command still
creates its default user library when its installation does so, as it
would in a clean shell; `test-footprint.R` allows exactly those
directories for its own R commands and checks the internal processes in a
step of their own.

Not changed: variables of the IDE (`RSTUDIO*`, `RS_*`, Positron), which R
does not set, and variables of the user's `.Renviron` other than `R_*`.
Visible change: on Windows a command finds Rtools only when the `PATH`
that R started with has it.

**D16. A warm call starts only the command (2026-11-17).** Measured on
Linux before this change: a warm
`run(cmd, env_name = ..., activate = FALSE)` took about 280 ms,
`processx::run()` of the same program about 16 ms, and `run_bin()` of
0.1.2 about 16 ms. Of the 266 ms of overhead, the existence check in
`resolve_backend()` took 129 ms and a second one in `run_command()`
119 ms. Each check started micromamba twice (`micromamba --version` in
`get_best_micromamba_path()`, then `micromamba env list --json`), and
`Sys.which("micromamba")` started a shell. The rest: `fs::dir_exists()`
34 times per call (1.5 ms each: `fs` reads the whole file information,
with the names of the owner and the group), `Sys.info()` 318 times
through `is_windows()`, `build_child_env()` three times (twice for the
checks), and the `conda-meta` stamp of the activation cache
(`fs::dir_info()`). The main thread proposed three steps, all internal
and without a new session cache, and asked whether to go ahead. The
maintainer answered (typos fixed):

> Fix all open questions.

What changed:

1. `micromamba_backend_env_exists()` reads the file system, with the rule
   of `micromamba env list`: `conda_prefix_env_exists()` in
   `R/backend-defaults.R`, the one-name form of
   `list_conda_prefix_envs()`, the listing that the backend already used
   without a micromamba binary and when micromamba hides the paths. An
   environment exists when `<root>/envs/<name>` has `conda-meta/history`,
   `<root>/envs` has an entry of exactly that name (a file system that
   ignores case also opens `envs/MyEnv` for `myenv`), its real path is a
   direct child of the real `<root>/envs`, and it is not the trash of
   `create_env(overwrite = TRUE)`. This is what condathis read from
   micromamba: `micromamba env list` reports the prefixes with
   `conda-meta/history` in its `envs_dirs` and its registry, and
   `condathis_env_names()` keeps only those whose real parent is
   `<root>/envs`. The registry (in the `home/` of the root, see
   `native_cmd()`) can only add other spellings of the same directories.
   A symbolic link is not listed under its own name. A new test builds
   every case and compares with micromamba 2.10.0 itself. When
   `<root>/envs` cannot be read, the check errors, so
   `backend_probe_env()` gives `NA` (rule R5), as a failed listing did.
   `list_envs()` still asks micromamba.
2. One check per call. `find_owning_backends()` records each probe
   (`probes =`), `resolve_backend()` returns the probe of the backend it
   chose as `env_exists`, and `run_command()` and `precreate_envs()` of
   `run_pipeline()` read it with `resolved_env_exists()`. Without it (a
   `resolve_backend()` replaced in a test, or a backend loaded after the
   owner search), they probe as before. The creation of the default
   `"condathis-env"`, rule R5 and every class and message are unchanged.
   `create_env()`, `install_packages()`, `remove_env()`,
   `list_packages()` and `validate_env()` still check twice; the checks no
   longer start processes.
3. Smaller costs of every call:
   - `is_windows()` reads `.Platform$OS.type`. The choice of a platform
     (`define_platform()`, `has_platform_fallback()` and the emulation
     fallback of `create_env()`) uses `sys_arch_is_windows()`, which reads
     `get_sys_arch()` as the macOS branch next to it does, so the tests
     that set the OS by mocking `get_sys_arch()` still choose the platform
     of that OS. `get_sys_arch()` calls `Sys.info()` once instead of twice.
     `is_windows_arm64()` is unchanged.
   - `dir_exists_quick()` (`base::dir.exists()`, with a leading `~`
     expanded as `fs` does) replaces `fs::dir_exists()` in the install
     directory and its check, `backend_has_env_dirs()`,
     `check_unregistered_known_owners()`, the default
     `backend_env_exists()` and the activation cache.
   - `run()` resolves the micromamba root twice, not three times:
     `child_conda_dirs(root_dir =)` takes it from the environment directory
     just resolved (`micromamba_root_of_env_dir()`). The third one is the
     marker check of `resolve_backend()`.
   - `activation_cache_stamp()` reads `conda-meta` with `list.files()` and
     `file.info()`: the same entries (no hidden ones), the number and the
     latest modification time, as before. Times now follow symbolic links,
     and the size of an `activate.d` file is its target's, as its hash
     already was.

Not done: no new session cache (backend resolution, existence, the
cleaned base environment, host prefixes). A stale entry could run a
removed environment or let the activation of the host leak back.

Results on Linux (R 4.5.3, micromamba 2.10.0, an environment with the
polyglot script; one R process per version, 10 calls of warm-up, then
100 measured calls per case; times in ms). Before is the tree just before
this change, after is the final tree, and the floor is `processx::run()`
of the program's path:

| Call | Before, median | Before, p90 | After, median | After, p90 |
|---|---|---|---|---|
| floor, `processx::run()` | 15.4 | 16.5 | 15.9 | 17.0 |
| `run(activate = FALSE)` | 281.1 | 292.1 | 21.9 | 26.4 |
| `run_bin(activate = FALSE)` | 279.9 | 288.4 | 21.8 | 25.7 |
| `run(activate = TRUE)`, warm | 281.0 | 301.9 | 24.1 | 31.9 |
| `run_pipeline()`, two steps of one environment | 343.7 | 366.1 | 47.3 | 235.9 |

- condathis 0.1.4 on the same machine: `run()` (through `micromamba run`)
  267.4 and 308.2, `run_bin()` 23.2 and 28.1. So `run()` is about ten
  times faster than in 0.1.4, and `run_bin()` as fast as it was. NEWS has
  one bullet in "Other changes".
- A pipeline needs two steps, so it starts two commands. About one call
  in five takes 100 ms to 600 ms longer, before and after the change; that
  is not the existence check, and it is not investigated here.
- A trace of a warm `run(activate = FALSE)`: no process but the command,
  no `fs::dir_exists()`, one `Sys.info()` of condathis
  (`processx_linux_pdeathsig()`).

## Findings (investigation of 2026-11-16)

### 1. How the three functions differed

| Aspect | `run()` | `run_bin()` | `run_pipeline()` |
|---|---|---|---|
| `activate` argument | none (always on) | `TRUE` by default | `TRUE` by default |
| `activate = FALSE` | n/a | no activation variable; env binary directories in front of the session `PATH` | fixed activation (`CONDA_PREFIX`, `CONDA_SHLVL=1`, ...), env binary directories in front of the session `PATH`, and a `TMPDIR` entry |
| Lookup of a bare name | off Windows: kept bare, `execvp()` on the child `PATH`; Windows: env binary directories with `PATHEXT` | its own resolver on every OS: env binary directories first (with an execute check), then `PATH`; a relative name was joined to the env directories; an `<env_dir>/bin/<cmd>` placeholder when found nowhere | `backend_resolve_run()` command, then `resolve_env_bin_path()` as a fallback |
| Signal status off Windows | `128 + n` | `-n` (processx) | `-n`, broken pipe `-13` |
| Resolve-failure text | "Failed to resolve command ..." | "Failed to resolve activation ..." | "Failed to resolve command ..." |
| `activate = FALSE` hint on a failed resolve | no | yes | yes |
| Windows: a command only on the activation `PATH` | not found | found | not checked |

None of these differences was documented as a feature, except the
`run_bin()` lookup.

### 2. What the backends do

- micromamba (built in): `backend_resolve_run()` returns the program and
  the recorded activation; condathis starts the program directly. No
  `micromamba run` wrapper at run time.
- rattlerthis: the same shape. Its activation is computed by
  `rattler_shell` in a shell started with `base_env` as its whole
  environment, and condathis starts the program directly.
- So both can honour `activate = FALSE` with the fixed activation: no
  backend code is needed to run a program of a local prefix.
- A future container or remote backend (`docker run ...`, a remote
  shell) has no local prefix to run from. Without backend code,
  `activate = FALSE` cannot work there. It would need an optional hook to
  describe the command without activation, or to refuse
  `activate = FALSE` with a class. Not needed for the two backends that
  exist; left as a follow-up (item 14).

### 3. Who uses `run_bin()`

From a search of public code on GitHub (2026-11-16):

- slidetool: 1 call.
- wsi-tools: 1 notebook.
- BLASTr: 4 files upstream; a local fork uses it only as a fallback.
- rattlerthis: its tests (the parity tests compare both backends through
  `run()`, `run_bin()` and `run_pipeline()`).

None of them passes `activate = FALSE` (finding 4). So from 0.2.0 on
they get the activation of the environment, which 0.1.4's `run_bin()`
did not set, with or without this change. What this change adds for them
is the lookup rule (D6) and the signal status (D7).

### 4. Who uses `activate = FALSE` and `run()`

- `activate = FALSE` is used nowhere in public code (it is new in 0.2.0
  for `run_bin()` and `run_pipeline()`).
- `run()` is used in about 25 public repositories. The new argument has a
  default that keeps their behaviour.

### 5. The host activation on the developer machine (Linux)

R is the pixi global environment `~/.pixi/envs/r-base` (`R.home()` is
`~/.pixi/envs/r-base/lib/R`, and the prefix has `conda-meta`).

- Started as `~/.pixi/envs/r-base/bin/Rscript`, the session carries a
  foreign activation from the login shell: `CONDA_PREFIX` names another
  pixi global environment (a tool that started the shell), `CONDA_SHLVL=0`,
  and two `~/.pixi/envs/<name>/bin` entries on `PATH`. Only one of them is
  named by a variable: the other environment's `CONDA_PREFIX` was
  overwritten without stacking. The user's shell configuration also puts
  `~/.pixi/bin` and `~/.local/bin` on `PATH`; they must stay.
- Started through the pixi trampoline `~/.pixi/bin/Rscript`, the session
  gets the trampoline's activation: `CONDA_PREFIX=~/.pixi/envs/r-base`,
  `CONDA_SHLVL=1`, its `bin` first on `PATH`, and every value of the
  environment's `activate.d` scripts (`CC`, `CFLAGS`,
  `CMAKE_PREFIX_PATH`, `RSTUDIO_WHICH_R`, `GSETTINGS_SCHEMA_DIR`, ...),
  with no backups except `GSETTINGS_SCHEMA_DIR_CONDA_BACKUP=""`.
- `pixi shell-hook` (pixi 0.84.2) exports `PATH`, `CONDA_SHLVL=1`,
  `CONDA_ENV_SHLVL_1_CONDA_PREFIX=<previous CONDA_PREFIX>`,
  `CONDA_PREFIX`, `CONDA_DEFAULT_ENV`, and the markers
  `PIXI_PROJECT_*`, `PIXI_WORKSPACE_*`, `PIXI_ENVIRONMENT_*`,
  `PIXI_IN_SHELL`, `PIXI_EXE` and `PIXI_PROMPT`. A variable that the
  manifest sets and that existed before gets
  `CONDA_ENV_SHLVL_<n>_<KEY>=<old value>`; a new one gets no backup.
- The developer suite uses a micromamba that is a pixi trampoline. Its
  configuration activates `~/.pixi/envs/micromamba`, so
  `micromamba run` through it, from a clean environment, prints
  `CONDA_SHLVL=2` and `CONDA_PREFIX_1=~/.pixi/envs/micromamba`. Both were
  recorded into every activation on this machine. L1 cannot remove them
  (they happen inside micromamba's process); item 4 does.

### 6. Backup conventions of conda-forge activation scripts

Surveyed across 77 environments under `~/.pixi/envs`:

- `CONDA_BACKUP_<X>` (compilers and binutils, `_tc_activation`):
  activation writes it only when the old `X` was not empty.
  Deactivation: a non-empty backup restores `X`, else `X` is unset; then
  the backup is unset. So a present backup means "restore `X`"; an absent
  one tells nothing.
- `<X>_CONDA_BACKUP` (libglib): activation always writes it, maybe
  empty. Deactivation sets `X` to it, unsets `X` when it is empty, then
  unsets the backup. Its presence proves the activation ran.
- `<X>_PREV` (r-base, `RSTUDIO_WHICH_R_PREV`): not a convention; not
  handled.
- `etc/conda/env_vars.d/*.json` exist (flat `{"NAME": "value"}`
  objects). No pixi environment has a `conda-meta/state` file.

## Design as built

### The layers in code

- `build_child_env()` (`R/child_env.R:57`) applies L1a
  (`isolate_host_env()`, line 64) and then L1b. Every child goes through
  it: `native_cmd()` (micromamba's own processes), the activation
  baseline dump, and the `base_env` of `run()`, `run_bin()` and every
  `run_pipeline()` command.
- `isolated_session_path()` (`R/host_env.R:104`) gives the L1 `PATH` for
  code that composes a `PATH` outside `build_child_env()`.
- `get_activation_envvars(env_name, env_dir, base_path)`
  (`R/conda_activation.R:29`) is the fixed activation (D1). It no longer
  takes `tmp_dir` and no longer sets `TMPDIR` (`base_env` has it).

### L1a: `isolate_host_env()` (`R/host_env.R`)

In this order, on a copy of the snapshot:

0. Host prefixes (`host_env_prefixes()`, line 132), found before
   anything is dropped: `CONDA_PREFIX`, every `CONDA_PREFIX_<n>`, every
   `CONDA_ENV_SHLVL_<n>_CONDA_PREFIX`, and R's own prefix
   (`condathis_r_prefix()`, line 445: one to three parents of `R.home()`,
   the first with `conda-meta`; computed once per session from the
   `R.home()` cached at load, `get_condathis_r_home()`,
   `R/condathis-package.R:95`). A candidate counts only when it is a
   directory with `conda-meta` (`is_conda_prefix()`, line 421), so a
   `CONDA_PREFIX` of `/usr` or a bogus value never removes `/usr/bin`.
1. Restore backups (`restore_host_backups()`, line 244):
   `CONDA_BACKUP_<X>` and `<X>_CONDA_BACKUP` as the deactivation scripts
   do (non-empty sets `X`, empty unsets it), and
   `CONDA_ENV_SHLVL_<n>_<X>` with the smallest `n` (the value before the
   first stacked activation). `PATH` and `CONDA_PREFIX` are never
   restored this way.
2. Drop markers (`drop_host_markers()`, line 302): `CONDA_PREFIX_<n>`,
   `CONDA_ENV_SHLVL_<n>_*`, both backup forms, `CONDA_EXE`,
   `CONDA_PYTHON_EXE`, `_CE_CONDA`, `_CE_M`, `MAMBA_EXE`,
   `PIXI_PROJECT_*`, `PIXI_WORKSPACE_*`, `PIXI_ENVIRONMENT_*`,
   `PIXI_PROMPT`, `PIXI_IN_SHELL`, `PIXI_EXE`. pixi configuration such as
   `PIXI_HOME` stays. `CONDA_PREFIX`, `CONDA_SHLVL` and the other
   `CONDA_*`/`MAMBA_*` variables are left to L1b, which resets them.
3. Unset host env_vars (`drop_host_env_vars()`, line 348): the variables
   of each prefix's `conda-meta/state` and `etc/conda/env_vars.d/*.json`,
   only when the session has exactly that value. Read errors are
   ignored.
4. `PATH` (`strip_host_path()`, line 198): remove every entry that is a
   binary directory (`env_bin_search_dirs()`) of a host prefix, compared
   with `path_entry_key()` (on Windows without case, `/` equal to `\`,
   quotes stripped for the comparison). When nothing is removed, the
   string comes back byte for byte.
5. What R's own startup set (D15, `undo_r_startup_env()`): the Rtools
   entries in front of the Windows `PATH`, R's default values of
   `r_startup_var_names()`, R's part of the library paths, and every
   `R_*` and `_R_*` variable.

Name comparisons are exact off Windows and without case on Windows
(`env_name_key()`; `match_env_name()` gained `on_windows`), so the
Windows rule is unit-tested on Linux.

R's own prefix leaves `PATH` on every OS (D12). Until D12, Windows kept
it: Windows has no rpath, and a Conda R may need its `Library/bin` to
load its DLLs when condathis starts `Rscript`. Only the activation dumps
need that; they get the directories appended (`micromamba_run_path()`,
`R/native_cmd.R`), and `resolve_micromamba_activation_envvars()` leaves
them out of the recorded `PATH`.

Limits (in `?condathis-options`, "The activation of the R session"):

- Values that host `activate.d` scripts set (compiler flags, `JAVA_HOME`,
  `RSTUDIO_WHICH_R`, ...) stay, unless a backup above restores them.
  `PATH` entries that such a script adds, other than the prefix's binary
  directories, stay too.
- The binary directory of an environment that no variable names any more
  stays (finding 5: a pixi global binary that started the shell before
  another one replaced its `CONDA_PREFIX`).
- Variables of the user's `.Renviron` other than `R_*`, and those of an
  IDE (`RSTUDIO*`), stay (D15).

### D3: composition from the L1 `PATH`

- `compose_activation_overlay(resolved, base_path)`: composed against the
  `PATH` of `base_env`, through `base_path_of()`
  (`R/get_micromamba_activation_envvars.R:196`; callers at 142 and 182).
- The `session_parts` step of `resolve_micromamba_activation_envvars()`
  (line 825) and the default of `micromamba_run_path()`
  (`R/native_cmd.R:406`) use `isolated_session_path()`.
- The fixed activation takes the `PATH` of `base_env`.
- Cache key, checked, no change: the cached part is a diff of two dumps
  that both start from L1, and `PATH` is composed at every call. A change
  to the env_vars files of a host prefix is not part of the key; the
  roxygen of `get_micromamba_activation_envvars()` says so.

### Activation stacking sanitation (micromamba backend only)

`drop_activation_stack_vars()`
(`R/get_micromamba_activation_envvars.R:1134`, applied at 797 and 859)
drops `CONDA_PREFIX_<n>` and `CONDA_ENV_SHLVL_<n>_*` from a recorded
activation, and a recorded `CONDA_SHLVL` other than `"1"` becomes `"1"`.
This fixes finding 5's trampoline case. Other backends' `env` is theirs
(D9), so it is not applied to them.

### One run path (D4 to D6, D8)

- `run()` (`R/run.R:168`) and `run_bin()` (`R/run_bin.R:42`) are thin
  wrappers over `run_command(fn, ...)` (`R/run.R:243`). Every validator
  gets `call`, so errors still name the function the user called.
- `run_internal_backend()` (`R/run_internal_backend.R:76`) starts the
  command; it gained `activate`.
- Shared helpers in `R/run_internal_backend.R`, also used by
  `spawn_pipeline_process()` (`R/run_pipeline.R:860`; its own copy of the
  backend dispatch and the `resolve_env_bin_path()` fallback are gone):
  - `resolve_child_invocation()` (line 319): with activation, the
    backend's `backend_resolve_run()` or `backend_resolve_run_in_dir()`;
    without, the fixed activation and no backend call.
  - `compose_child_env()` (line 397): `base_env` plus the activation, and
    with activation the environment's binary directories in front of a
    `PATH` that names none of them.
  - `run_family_resolve_hint()` (line 422).
  - `resolve_direct_run_command()` (line 552): the one lookup rule.
- `resolve_run_bin_command()` is deleted. `run_bin(activate = FALSE)` no
  longer has an execute check, a join of relative names, or the
  `<env_dir>/bin/<cmd>` placeholder.
- `rethrow_error_run()` gained `call = env`.
- Classes: `fn = "run_bin"` keeps `condathis_run_bin_*`, which also carry
  `condathis_run_*`, and the argument-error classes. `NAMESPACE` is
  unchanged.
- Wording: "Failed to resolve command for environment '<label>': ..."
  for all three, and `run()` now also gives the hint
  "`activate = FALSE` runs the command without the activation of the
  backend." `resolve_failure_stderr()` keeps its `what` argument (a test
  calls it with `"activation"`); only `"command"` is documented.

### Exit status (D7)

- `signal_exit_status()` (`R/run_internal_backend.R:600`) maps `-n` to
  `128 + n` off Windows. `run_internal_backend()` applies it for `run()`
  and `run_bin()` (line 270), and `settle_pipeline_stage()`
  (`R/run_pipeline.R:1106`, line 1174) for each pipeline command.
- `broken_pipe_status` is `141L` (`R/run_pipeline.R:1902`), also for the
  Windows emulation of `SIGPIPE`. A command that is not the last one and
  exits with a real 141 counts as a broken pipe, as with bash `pipefail`.
- Timeout `-9`, spawn failure 127 and the activation timeout `-9` are
  unchanged.

### Docs

- `?run`: description, a paragraph on the activation of the R session, a
  paragraph on lookup, the new `@param activate`.
- `?run_bin`: superseded by `run()`; the 0.1.4 note.
- `?run_pipeline`: `@param activate`, statuses (141), *Broken pipes*.
- `?condathis-conditions`: the `status` field (`128 + n`), the
  `activate` class line for both functions.
- `?condathis-options`: the `CONDA_PREFIX` and `PATH` items, the new
  part "The activation of the R session" with its limits, and the
  `activate = TRUE` and `activate = FALSE` sections.
- `?register_backend`: the `base_env`, `command` and `env` bullets, when
  `backend_resolve_run()` is called, and *Child processes*.
- NEWS: the superseded `run_bin()` bullet replaced (Breaking changes),
  `activate` in the new arguments of the run family (New features), the
  broken-pipe status, a bug fix for the activation of the R session, and
  the Windows lookup bullet widened to the three functions.
- `vignettes/articles/python-and-reticulate.qmd`: the `run()` or
  `run_bin()` section no longer says they find `python` differently.
- README, `vignettes/condathis.qmd`, the backends article, `AGENTS.md`,
  `CONTRIBUTING.md` and the pkgdown index needed no change: what they say
  about `run_bin()` stays true. `run_bin()` stays in the "Run command line
  tools" group of the reference index.

## Deviations from the spec

1. `condathis_r_prefix()` has an extra argument,
   `use_cache = missing(r_home)`, so tests can pass an `r_home` without
   touching the session cache.
2. The fake nested host of the end-to-end tests sets the libglib-style
   backup to `user-schema` instead of `""`, because on Windows an empty
   value unsets a variable. The empty-backup case is covered by a unit
   test with a hand-built block.
3. Host markers are checked by value in the end-to-end tests, not by
   name: micromamba's own activation sets `MAMBA_EXE` to its binary,
   which is not a host leak.
4. The wrapper test (a micromamba started through an activating wrapper)
   resolves a pixi trampoline to its real binary through
   `trampoline_configuration/<name>.json`. Otherwise the trampoline's own
   activation hides the wrapper's.
5. A step that removed the stacked prefixes' binary directories from the
   recorded activation `PATH` was tried and removed: micromamba 2.10.0
   already takes them off, and no case showed a difference.
6. `run_internal_backend()` re-signals an error of the `activate = FALSE`
   branch unchanged. No backend code runs there, so it is not wrapped as
   a backend failure.

## Verification

Round 2 (2026-11-16, D0 to D10, each in a copy of the tree with isolated
`HOME`, `XDG_*` and `TMPDIR`):

| Where | Developer suite | `R CMD check --as-cran` |
|---|---|---|
| Linux, R 4.5.3 | 9104 pass, 0 skip; also under a fake nested host | OK with the clock and URL checks off |
| omicron, macOS, R 4.6.1 | 9102 pass, 0 skip | OK; CRAN-mode tests 36 s |
| kappa, Windows 11, R 4.6.1 | 9059 pass, 0 skip | OK |
| Docker | R-devel 9104 pass | OK on R-devel, R 4.6.2, R 4.3.3 and offline |

Round 3 (2026-11-16, after D11 to D13):

| Where | Developer suite | `R CMD check --as-cran` |
|---|---|---|
| Linux | 9142 pass, 0 fail, 0 skip; the same under the fake nested host (which now also sets `MAMBA_SHLVL=2` and `(host) ` prompts) | OK with `_R_CHECK_SYSTEM_CLOCK_=FALSE` and URL checks skipped; with URL checks, 1 NOTE: the two r-universe README URLs return 403. CRAN-mode tests 78 s |
| omicron | 9140 pass, 0 fail, 0 skip | OK, no NOTE; CRAN-mode tests 38 s |
| kappa, R 4.6.1 | first run (old tree): 9094 pass, 3 fail, 0 skip; rerun on 2026-11-17: 9140 pass, 0 fail, 0 skip | OK, no NOTE; CRAN-mode tests 129 s |

- A probe on Linux and omicron, with the R session at `CONDA_SHLVL=2`,
  `MAMBA_SHLVL=2` and `(host) ` prompt modifiers: the command saw `1`,
  `1`, `""`, `""` with `activate = TRUE` and with `activate = FALSE`. A
  missing command gave status 127 in `run()` (both modes) and in its
  `run_pipeline()` step.
- The three kappa failures were the Windows branches of three tests that
  still expected the behavior that D12 and D13 removed
  (`test-child_env.R` nested host `PATH`, `test-run_isolation.R` activation
  `PATH` order, `test-run_bin.R` a command only on the activation `PATH`).
  They now expect the same result as on Linux and macOS.
- On kappa's Rtools45 there is no extensionless `cmd` file, and
  `Sys.which("cmd")` gives `C:\Windows\SYSTEM32\cmd.exe`. The candidate
  rule of D13 is kept for other Rtools layouts.

D12 with a conda-forge R on kappa (2026-11-17; an environment with
`r-base` 4.5.3, the Imports and `r-curl`, condathis installed into it):

- The conda R does not start at all without its activation (exit
  `0xC0000135`, a DLL not found), so it was started with the variables
  of `micromamba run` for its environment.
- `condathis_r_prefix()` found the prefix. The activation dump worked:
  `micromamba_run_path()` appended the 6 directories of R's prefix at the
  end.
- The command's `PATH` named nothing under R's prefix, and the command saw
  `CONDA_SHLVL=1`, `MAMBA_SHLVL=1` and empty prompt modifiers, with
  `activate = TRUE` and `FALSE`.
- `run("cmd", "/c", "echo", "ok")` worked, also with the Rtools
  directories first on the session `PATH`. `run("Rscript.exe")` in an
  environment without R gave 127. `run("Rscript")` and `run("R")` gave
  status 1, because kappa's `PATH` has the rig shim directory
  `C:\Program Files\R\bin`, whose `Rscript.bat` and `R.bat` point to an R
  that is no longer installed (`cmd /c Rscript` fails the same way).
  Without that directory, all six cases gave 127.
- The run-family test files under the conda R: 992 pass, 10 fail, 23
  errors, 0 skip. Every failure and error has one cause: the tests run
  the session's own `Rscript` (`file.path(R.home("bin"), ...)`) as the
  command. D12 takes R's prefix off the command's `PATH`, so that
  `Rscript` cannot load its DLLs and exits with `-1073741515`
  (`0xC0000135`). A user who runs R's own `Rscript` through `run()` from a
  conda R on Windows gets the same exit. `micromamba run` in a clean
  environment behaves the same way. Open question for the maintainer
  (TODO item 12).
- The child also gets `R_ARCH`, `R_COMPILED_BY` and the conda R's
  `R_LIBS_SITE` from the R session (see follow-up 15; removed by D15).

Round 4 (2026-11-17, after D14 and D15):

| Where | Developer suite | `R CMD check --as-cran` |
|---|---|---|
| Linux (pixi R 4.5.3) | 9236 pass, 0 fail, 0 skip; the same under the fake nested host | OK, no NOTE; CRAN-mode tests 78 s |
| omicron (rig CRAN R 4.6.1) | 9226 pass, 8 fail (`test-footprint.R`) | OK, no NOTE |
| kappa (rig CRAN R 4.6.1) | 9182 pass, 7 fail, 1 error | 1 ERROR (two `test-child_env.R` tests) |

- D15 held on every machine: no `R_*` variable in the command's
  environment; `EDITOR` of the user kept; R's `MAKE`, `SED`, `TAR`,
  `LN_S` removed. rocker R 4.6 (Docker): R's part of `LD_LIBRARY_PATH`
  removed, a preset `/user/lib` kept. macOS: the same for
  `DYLD_FALLBACK_LIBRARY_PATH`. Windows: no `CURL_CA_BUNDLE`, no
  `MSYS2_ENV_CONV_EXCL`, no Rtools on the command's `PATH`.
- D14 held on kappa under a conda-forge R 4.5.3: R's own `Rscript` as a
  command exits 0 (round 3: `-1073741515`), with R's prefix only at the
  end of its `PATH`; an ordinary command has none of it.
- Fixed after round 4: `undo_r_startup_env()` used the separator of the
  running OS instead of `on_windows`; two Windows test bugs; the rig
  footprint (see D15, `internal_rscript_vars()`).

Round 5 (2026-11-17, the fixes of round 4):

| Where | Developer suite | `R CMD check --as-cran` |
|---|---|---|
| Linux | 9248 pass, 0 fail, 0 skip; the same under the fake nested host | OK, no NOTE; CRAN-mode tests 79 s |
| omicron | 9246 pass, 0 fail, 0 skip | OK, no NOTE; CRAN-mode tests 38 s |
| kappa | 9201 pass, 0 fail, 0 skip | OK, no NOTE; CRAN-mode tests 128 s |
| kappa, conda-forge R 4.5.3 (5 run-family files) | 1544 pass, 1 fail, 0 skip | - |

- The one failure under the conda-forge R was a test bug: it expected
  `CURL_CA_BUNDLE` from every Windows R, but R's base profile sets it
  only when R ships `etc/curl-ca-bundle.crt`, which conda-forge's R does
  not. The test now follows that file. Not rerun on kappa.
- With a fresh empty home, `r_startup_env_vars()` and the activation
  dumps created nothing under it on omicron and kappa (rig R); R's own
  `Rscript` run as a command still creates its default user library
  there, as rig's profile does in a clean shell.
- Noted on omicron: micromamba 2.10.0 sets `LC_ALL=C.UTF-8` when it
  activates an environment on macOS, so the commands of `run()` with
  activation get it. It is part of the recorded activation (as with
  `micromamba run`), not of condathis. Decision (2026-11-17, with the
  maintainer's "Fix all open questions."): kept. `activate = TRUE`
  promises the variables of the backend's activation, and
  `micromamba run` gives the same value. Not in NEWS: condathis does not
  set it.

Round 6 (2026-11-17, D16, the README links and the conda-R test fix of
round 5; each machine from one source snapshot, in a copy with isolated
`HOME`, `XDG_*` and `TMPDIR`):

| Where | Developer suite | `R CMD check --as-cran` |
|---|---|---|
| Linux, pixi R 4.5.3 | 9314 pass, 0 fail, 0 skip; the same under the fake nested host | OK, no NOTE, with the URL checks on; CRAN-mode tests 76 s |
| omicron, macOS, CRAN R 4.6.1 | 9312 pass, 0 fail, 0 skip | OK, no NOTE (`--no-manual`); CRAN-mode tests 37 s |
| kappa, Windows, CRAN R 4.6.1 | 9257 pass, 0 fail, 1 skip (a POSIX permission test, skipped on Windows) | OK, no NOTE (`--no-manual`); CRAN-mode tests 122 s |
| kappa, conda-forge R 4.5.3 | run-family files: 1545 pass, 0 fail, 0 skip | not run |

- The URL check found no problem: the two r-universe links of the README
  are gone (every r-universe page answers 403 to clients that are not
  browsers, R's own user agent included). The install code still names
  the repository, which is not a checked link.
- The round 5 `CURL_CA_BUNDLE` test passes under conda-forge R, which has
  no `etc/curl-ca-bundle.crt`. R's own `Rscript` as a command exits 0.
- An extra conda-forge R run of more run-family files failed 3 times in
  `test-run_bin.R`: three `PATH` expectations for R's own `Rscript` did
  not allow for the D14 suffix. Test fix: `run_family_rscript_path()` in
  `helper-run-family.R`, as `test-run.R` already did. Rerun on kappa
  under conda-forge R with all 12 run-family files: 2426 pass, 0 fail,
  0 skip.
- Warm call against `processx::run()` of the same program (median, ms):

  | Where | floor | `run(activate = FALSE)` | `run(activate = TRUE)` |
  |---|---|---|---|
  | Linux | 17.4 | 21.0 | 23.5 |
  | omicron | 7.8 | 10.4 | 11.0 |
  | kappa, CRAN R (`.cmd` program) | 25.1 | 41.5 | 58.7 |

- rattlerthis suite against this tree (Linux, with the item 13 and 17b
  changes in rattlerthis): 3742 pass, 2 fail, 2 skip (the `wheels`
  feature is off). Both failures were one stale assertion in
  `test-parity-verbose.R`: `env_exists(verbose = "cmd")` of micromamba
  echoed `micromamba env list`, and since D16 it starts no process. Test
  fixed in rattlerthis.
- Two reviewers read the D16 change against the snapshot before it and
  found no defect. Below their bar: an unreadable `envs` directory gives
  a plain error (no `condathis_*` class) inside the `NA` probe, and
  `dir_exists_quick()` keeps base R's rule for a trailing `/` on Windows
  for an install directory that a third-party backend returns.

Results recorded by the implementation steps (Linux only, in a copy of
the tree with isolated `HOME`, `XDG_*` and `TMPDIR`):

- After the environment layers: developer suite
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 9011 ]`. R started through
  `~/.pixi/bin/Rscript` (a really activated host): R's prefix found,
  `r-base/bin` removed from the child `PATH`, the run-family and
  child-environment test files pass. `test-run_isolation.R` fails as
  expected with the stacking sanitation switched off (`CONDA_SHLVL` 2).
- After the one run path: the 13 run-family test files plus
  `test-polyglot.R` and `test-argument_fidelity.R`: 0 failed, 0 skipped,
  2450 passed.

First kappa run: `test-run_isolation.R` failed 13 times, also in
`R CMD check`. The tests dump the child's environment from `Rscript`.
On Windows, the base Rprofile of R puts the Rtools directories in front
of `PATH` at every start, also with `--vanilla`. So the dumped `PATH`
began with Rtools, not with the expected directory. condathis built the
right `PATH` (a `cmd.exe` child saw it unchanged). The tests now drop
what `Rscript` puts in front, measured once with a marker entry
(`rscript_dumped_path_entries()` in `helper-run-family.R`).

Not run yet: the Windows branches of the new tests (the `Scripts`
directory in the stub-tool tests, status 127 for a command only on the
activation `PATH`, the order test), and rattlerthis (not installed in
the local R library).

## rattlerthis tests that these changes break

Done on 2026-11-17 in rattlerthis (uncommitted there, item 13 and
follow-ups 17a and 17b): the expectations below, the D11 and D15 values,
a new test that no `R_*` variable reaches a command with either backend,
`create_env(env_definition(x))` instead of the deprecated
`env_file =` in its tests, and the `env_exists()` echo of D16.
`rattler_pip_base_env()` now starts from condathis's internal
`build_child_env()`, so pip steps get the L1 isolation and D15. condathis
gives a backend no public way to get that block yet: an optional
`base_env` argument of `backend_create_env()` and `backend_install()`
would let rattlerthis stop calling the internal function (after 0.2.0).

The analysis before that change, from reading
`tests/testthat/test-parity-childenv.R` in rattlerthis:

1. About lines 180 to 195 (`fn = "run_bin_noact"`, environment given by
   name): `CONDA_SHLVL` `"0"` becomes `"1"`, `CONDA_PREFIX` `""` becomes
   `"<ROOT>/envs/<ENV>"`, `CONDA_DEFAULT_ENV` `""` becomes `"<ENV>"`, and
   `MAMBA_SHLVL` `"0"` becomes `"1"`.
2. About lines 413 to 441 (the `env_path()` case of `run_bin_noact`):
   `CONDA_PREFIX` and `CONDA_DEFAULT_ENV` become the target directory, and
   `CONDA_SHLVL` becomes `"1"`.
3. About lines 689 to 738 ("a command killed by a signal"): the expected
   `run_bin_status` `-9L` becomes `137L`, for `res$status` and
   `cnd$status`.

Not broken: about line 826 (`activate = FALSE` still runs no
`activate.d`), the missing-command and lookup parity tests (both backends
go through the same condathis code), the timeout test (`-9`, about line
888), `test-activation-cache.R`, `test-condathis-conformance.R`,
`test-parity-verbose.R` and `test-registration.R` (generic formals
unchanged).

Both backends still agree with each other in the changed cases, so the
fixes are new expected values, not new code.

D11 changes more expected values there: with `activate = TRUE`,
`MAMBA_SHLVL` is now `"1"` (was `"0"`) and `CONDA_PROMPT_MODIFIER` is
now `""` (was `"(<env>) "`) for both backends; with `activate = FALSE`,
both prompt modifiers are now `""`. A parity test that compares the two
backends still passes; one that compares with a written value must take
the new one.

D15 changes more: the base block that a backend gets has no `R_HOME` (it
was `""`) and no other `R_*` variable, and on Windows no Rtools entries
in front of `PATH`. A test that expects `R_HOME` `""` in a child must
expect it unset. rattlerthis's `rattler_pip_base_env()` (follow-up 17b)
builds its own block and does not get D15.

## Follow-ups

14. **Optional backend hook for `activate = FALSE`** (D9). A container
    or remote backend cannot run a program without its own code
    (finding 2). An optional function, with a default that keeps today's
    fixed activation, could let such a backend describe the command
    without activation or refuse `activate = FALSE` with a class. After
    0.2.0.
15. **`R_LIBS`, `R_LIBS_USER`, `R_LIBS_SITE` of a Conda R.** Done by
    D15: every `R_*` variable leaves the child.
16. **Soft-deprecate `run_bin()`** in a later release, with the same
    `condathis_deprecate_soft()` rule as `packages =`. Its users
    (finding 3) can switch to `run()` without other changes.
17. Smaller:
    - a. rattlerthis: update the three expectations above and run its
      suite against this tree. Done 2026-11-17 (round 6).
    - b. rattlerthis's `rattler_pip_base_env()` (`R/rattler-pip.R` in
      rattlerthis) builds its own environment block without the L1
      isolation. Done 2026-11-17: it calls condathis's internal
      `build_child_env()`. Open after 0.2.0: a public way for backends
      to get that block (`base_env` for `backend_create_env()` and
      `backend_install()`).
    - c. A pixi trampoline given as the micromamba path could be resolved
      to its real binary, so its activation never reaches micromamba.
    - d. Windows lookup on the R session's `PATH`: done by D13.
    - e. Windows with R itself in a Conda prefix: done by D12, tested on
      kappa with a conda-forge R (see *Verification*).
    - f. `MAMBA_SHLVL` and the prompt modifiers: done by D11.
    - g. `CONDA_DEFAULT_ENV` of the fixed activation for an `env_path()`
      environment is its directory (as before in `run_pipeline()`), not
      libmamba's name for it.

## Sources

- The maintainer's message of 2026-11-16 (D0).
- `R/host_env.R`, `R/child_env.R`, `R/conda_activation.R`,
  `R/get_micromamba_activation_envvars.R`, `R/native_cmd.R`, `R/run.R`,
  `R/run_bin.R`, `R/run_internal_backend.R`, `R/run_pipeline.R`,
  `R/backend.R`, `R/condathis-options.R`, `R/condathis-conditions.R`.
- Tests: `tests/testthat/test-run_isolation.R` (new),
  `test-child_env.R`, `test-run.R`, `test-run_bin.R`,
  `test-run_pipeline.R`, `test-run_pipeline_api.R`, and the fake nested
  host in `helper-run-family.R`.
- conda-forge activation scripts under `~/.pixi/envs/*/etc/conda`, and
  `pixi shell-hook` of pixi 0.84.2.
- rattlerthis `main`: `R/condathis-backend.R` and
  `tests/testthat/test-parity-childenv.R`.
