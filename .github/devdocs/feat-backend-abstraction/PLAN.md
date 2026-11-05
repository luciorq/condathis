# Backend abstraction for `condathis`

## Context

`condathis::create_env()` and `condathis::run()` both carry a `method =
c("native", "auto")` argument today. It is fully vestigial: `rlang::arg_match()`
validates the value and then `if (isTRUE(method %in% c("native", "auto")))`
gates the only code path that exists, so both values do the same thing.
`install_packages()` doesn't even have the argument. Every entry point
ultimately calls `native_cmd()` (`R/native_cmd.R`), which shells out to a
`micromamba` binary managed under `get_install_dir()` via `processx::run()`.
"native" originally meant "run on the host", as opposed to inside a
container — `docker`/`singularity` backends were planned but never built.

That plan is worth reviving now for a different reason: `rattlerthis`
(sibling package, `github.com/luciorq/rattlerthis`) reimplements the same
create/install/run surface without shelling out to `micromamba` at all — it
calls the `rattler` Rust crates in-process via `rextendr`. So `condathis` now
has two real, working "run things on the host" engines, not zero, plus the
still-live idea of container engines. That's exactly the shape a backend
abstraction is for.

## Goals

- Let `condathis` dispatch `create_env()`/`install_packages()`/`run()`/
  `remove_env()`/`list_envs()`/`env_exists()`/`list_packages()`/
  `get_env_dir()`/`get_install_dir()` to a pluggable backend instead of
  hardcoding `native_cmd()`.
- Define the *minimal* contract an external package must implement to add a
  new backend (starting with `rattlerthis`; container backends later).
- Do this without forcing `condathis` itself to depend on Rust, Docker, or
  anything beyond what it needs today (it currently has zero compiled
  dependencies and no `SystemRequirements` — that's worth protecting).
- Preserve `condathis`'s existing user-facing signatures and default
  behavior. Nobody's `create_env(packages = "bioconda::fastqc")` call should
  need to change.

## Non-goals (this round)

- Actually implementing a docker/singularity backend package. This doc only
  defines what such a package *would* need to provide.
- Changing `run()`'s `processx`-level behavior (streaming, spinner, timeout,
  interrupt handling, `supervise`/`cleanup_tree`/`linux_pdeathsig`). That
  logic stays centralized in `condathis` — see decision 4.

## Design decisions

1. **Naming split: "execution strategy" vs "backend engine".**
   The old `method` vocabulary conflated two independent axes: *where* a
   command runs (host vs. container) and *how* the environment is
   managed (shell out to `micromamba` vs. call `rattler` in-process).
   `rattlerthis` and `micromamba` are both "run on the host" engines, so
   calling one of them `"native"` and leaving no name for the other doesn't
   work. Vocabulary: `method = c("auto", "micromamba", "rattler", "docker",
   "singularity")`, with `"native"` kept as a deprecated alias for
   `"micromamba"` (today's actual default behavior) for back-compat, emitting
   `cli::cli_warn(class = "condathis_deprecated_method_native")` once per
   session and mapping internally to `"micromamba"` — never silently.
   Confirmed with the user 2026-07-15: explicit engine names, no generic
   "native".

2. **The registry and generics live in `condathis`, not in a new package or
   in `rattlerthis`.** `condathis` is the user-facing package that already
   owns the `method =` argument and its users; moving the dispatch surface
   elsewhere would just add an extra package to install for no benefit at
   this scale (a handful of generics). Confirmed with the user 2026-07-15.

3. **Dependency direction: backends register themselves *into* `condathis`;
   `condathis` never `Imports`/`Depends` on a backend package.** A backend
   package (e.g. `rattlerthis`) calls
   `condathis::register_backend("rattler", rattlerthis:::as_condathis_backend())`
   from its own `.onLoad()`, guarded by
   `if (requireNamespace("condathis", quietly = TRUE))`. This keeps
   `condathis` installable with zero compiled dependencies exactly as today;
   picking up a Rust-based backend is opt-in by installing `rattlerthis`
   alongside it, not a forced transitive dependency. The same direction
   would apply to a future `condathis.docker`-style package.

4. **The contract: 10 S3 generics, dispatched on a `backend` object.**
   A backend is an S3 object (list) of class `c("condathis_backend_<name>",
   "condathis_backend")`, holding whatever state it needs (paths, config).
   Required generics:

   - `backend_create_env(backend, packages, env_file, env_name, channels, channel_priority, additional_channels, platform, overwrite, verbose)`
   - `backend_install(backend, packages, env_name, channels, channel_priority, additional_channels, verbose)`
   - `backend_remove_env(backend, env_name, verbose)`
   - `backend_list_envs(backend, verbose)`
   - `backend_env_exists(backend, env_name, verbose)`
   - `backend_list_packages(backend, env_name, verbose)`
   - `backend_get_env_dir(backend, env_name)`
   - `backend_get_install_dir(backend)`
   - `backend_resolve_run(backend, cmd, args, env_name, verbose)` — the key
     design choice. Instead of each backend re-implementing process
     execution (streaming, spinner, timeout, interrupt, supervise/
     cleanup_tree/linux_pdeathsig — all the hard-won logic in
     `run_internal_native.R`/`run_process_with_input.R`), a backend only
     *resolves* what to run: it returns
     `list(command = <path/exe>, args = <character vector>, env = <named
     character vector of env vars>, dir = <working dir or NULL>)`.
     `condathis::run()` keeps the single `processx::run()`/
     `run_process_with_input()` call site and applies it uniformly. For
     `micromamba`, resolving means computing the activation env vars for the
     prefix. For `rattler`, it's a direct pass-through of
     `rattlerthis`'s own `rattler_shell::Activator` output (this backend
     already produces exactly this shape internally — see its PLAN.md
     decision 3, "hybrid model"). For a future `docker` backend, `command`
     would be `"docker"` and `args` would be `c("run", "--rm", image, cmd,
     args...)`. **No backend, including future container backends, needs to
     touch `processx` directly.**
   - `backend_available(backend)` — cheap, side-effect-free capability probe
     (is the Rust lib loaded? is a `docker` daemon reachable? is a binary on
     `PATH`?), used to resolve `method = "auto"`.

5. **Per-environment backend persistence, and `method =` becomes explicit on
   every function that touches a backend.** A backend choice is made once,
   at `create_env()` time, and must stick for the life of that environment —
   you can't `install_packages()` into a `micromamba`-created prefix using
   the `rattler` backend's `Installer`, and definitely can't for a
   container-backed "environment" that isn't a local prefix at all. Record
   the owning backend in a marker written by `backend_create_env()`
   (format: decision 5a below), written by `condathis` itself, not by each
   backend, so the format is centralized in one place.

   Confirmed with the user 2026-07-15: rather than only `create_env()`/
   `run()` taking `method =` (as today) and everything else inferring
   silently, **every** backend-touching function gains an explicit
   `method = c("auto", "micromamba", "rattler", "docker", "singularity")`
   argument — `install_packages()`, `remove_env()`, `list_envs()`,
   `env_exists()`, `list_packages()`, `get_env_dir()`, `get_install_dir()`,
   in addition to `create_env()`/`run()`. `resolve_backend(env_name, method,
   mutating)` is the shared internal helper all of them call:

   - `method` explicit and not `"auto"`, env already exists, and it
     disagrees with the stored marker → **mutating** calls
     (`install_packages()`, `remove_env()`, `create_env(overwrite = TRUE)`)
     `cli::cli_abort()`: acting on an environment with the wrong engine can
     corrupt it (e.g. `rattler`'s `Installer` and `micromamba`'s prefix
     layout aren't interchangeable). **Read-only** calls (`list_packages()`,
     `env_exists()`, `get_env_dir()`) instead `cli::cli_warn()` and use the
     *actual stored* backend regardless of what was requested — a query
     should reflect reality, not silently return nothing/wrong data because
     the caller guessed the wrong engine.
   - `method` explicit, env doesn't exist yet → used as-is (this is the
     only case that matters for `create_env()` itself).
   - `method = "auto"`, env exists → read the stored marker, no
     ambiguity.
   - `method = "auto"`, env doesn't exist → priority-list resolution
     (decision 6).

   This removes the need to repeat the *correct* `method =` on every call
   once an environment exists (`"auto"` still works and just reads the
   marker), while making it possible to *notice*, loudly, when a caller's
   explicit assumption about which engine owns an environment was wrong.

   5a. **Marker format: JSON via `jsonlite`.** `condathis` already depends
   on `jsonlite` (used by `list_envs()`/`get_env_history_channels()`
   today), so this adds no new dependency — confirmed with the user
   2026-07-15 as the natural choice over introducing a YAML dependency for
   one small file. Written at `<env_dir>/.condathis/backend.json`, e.g.
   `{"backend": "rattler", "schema_version": 1}`, leaving room for
   backend-specific metadata later (a docker backend would presumably add
   an `"image"` field) without a format migration.

6. **`method = "auto"` resolution order.** Configurable via
   `getOption("condathis.backend_priority", c("rattler", "micromamba"))` —
   first registered *and* `backend_available()` backend wins. Defaulting
   `rattler` first is a bet that most users will eventually prefer the
   in-process engine over shelling out to a managed binary; revisit once
   `rattlerthis` has real-world mileage outside this repo.

7. **Registration-time contract validation.** `register_backend(name,
   backend)` checks that all 10 generics in decision 4 have a method defined
   for `class(backend)[1]` (e.g. via `getS3method(generic, class,
   optional = TRUE)`) and `cli::cli_abort()`s immediately, listing exactly
   which generics are missing, if any aren't. A backend package that forgets
   to implement `backend_list_packages()` should fail loudly at `.onLoad()`
   time (or whenever it registers), not three calls deep in a user's script
   the first time someone calls `list_packages()`.

8. **What `rattlerthis` needs to change to become a conforming backend.**
   Its existing R functions (`create_env()`, `install()`, `run()`,
   `list_envs()`, `env_exists()`, `remove_env()`, `list_packages()`,
   `get_env_dir()`, `get_install_dir()`) already match this contract almost
   1:1 in spirit — `rattlerthis` needs one new small adapter file
   (e.g. `R/condathis-backend.R`) that wraps each existing function as the
   corresponding `backend_*` S3 method plus a constructor and `.onLoad()`
   registration call, guarded by `requireNamespace("condathis", quietly =
   TRUE)`. No changes to `rattlerthis`'s own public API are needed — it
   keeps working standalone for anyone who doesn't use `condathis` at all.

9. **What a future container backend package would need to supply.**
   Concretely, beyond the 10 generics: a way to resolve/pull an image per
   `env_name` (probably its own `create_env()` semantics — "build/pull an
   image with these packages" rather than "populate a directory"),
   `backend_get_env_dir()` returning something meaningful for a bind-mount
   rather than a real prefix path, and `backend_resolve_run()` translating
   `cmd`/`args`/`env_name` into a `docker run`/`singularity exec` invocation
   with the right mounts and env var passthrough. `backend_available()`
   would probe for a reachable daemon (`docker info` exit status). No
   changes to the contract itself should be needed — this was the point of
   designing generic 4 (`backend_resolve_run`) around "resolve, don't
   execute" rather than "each backend runs its own subprocess".

10. **`get_install_dir()`/`list_envs()` return a tibble-classed data frame;
    `env_exists()` stays a logical scalar.** Resolves the previous open
    question. Confirmed with the user 2026-07-15:

    - `get_install_dir(method = "auto")` → one row per registered *and*
      available backend, columns `backend` (chr), `path` (chr). With an
      explicit single `method =`, always still a 1-row tibble of the same
      shape (not a bare string) — the return type never depends on which
      value `method` takes, only the row count does.
    - `list_envs(method = "auto")` → one row per environment across every
      registered + available backend, columns `backend` (chr), `env_name`
      (chr), `path` (chr). Same shape rule: an explicit single `method =`
      still returns this 3-column tibble, just filtered to that backend.
    - `env_exists(env_name, method = "auto")` stays a plain `TRUE`/`FALSE`
      scalar — it's a predicate, not a listing, so "does it exist anywhere"
      is well-defined without a `backend` column. See decision 11 for how
      "anywhere" is actually resolved.

    This is a breaking return-type change for `list_envs()`/
    `get_install_dir()` (today: bare `character`), unavoidable once more
    than one backend can be registered — worth a `NEWS.md` bullet and a
    major/minor version bump, not a patch.

    **No new `tibble` dependency.** Confirmed with the user 2026-07-15:
    reuse the exact pattern `list_packages()` already uses at
    `R/list_packages.R:94-95` —
    ```r
    pkgs_df <- base::unclass(pkgs_df)
    base::attr(pkgs_df, "class") <- c("tbl_df", "tbl", "data.frame")
    ```
    i.e. build a plain `data.frame` (`base::data.frame(backend = ...,
    path = ..., stringsAsFactors = FALSE)`), then hand-stamp the tibble
    class attribute rather than importing `tibble`. Gets tibble-style
    printing when `tibble`/`pillar` happen to be loaded, falls back to
    ordinary `data.frame` printing otherwise, adds zero new dependencies,
    and matches an established in-repo convention instead of introducing a
    second way to build a tibble-classed object.

11. **Internal call sites never pass (or default to) `method = "auto"` —
    they thread down whatever `method` their own caller already resolved.**
    Confirmed with the user 2026-07-15. This is a coding convention enforced
    by review, not runtime call-stack introspection (no `sys.call()`
    trickery to detect "am I top-level") — `method = "auto"` only ever gets
    evaluated at the point a user calls an exported function directly
    without specifying it.

    Auditing today's actual call sites shows two different situations,
    which get fixed differently:

    - **Calls from inside what becomes the `micromamba` backend's own
      implementation** — `R/native_cmd.R:86`, `R/run_internal_native.R:53,72`,
      `R/install_micromamba.R:101`, `R/get_best_micromamba_path.R:74,76`,
      `R/micromamba_bin_path.R:20`, and `R/get_env_dir.R:24`'s
      `get_install_dir()` calls. These aren't "resolve `method`, then call
      the public multi-backend function" at all — once this code moves into
      `backend-micromamba.R` (decision 8), it's *inherently* scoped to the
      one backend it belongs to. It should call a plain internal
      single-backend primitive directly (e.g. `install_dir_for_backend(backend)`
      returning a bare path), never the public tibble-returning
      `get_install_dir()`.
    - **Calls from top-level orchestration functions that themselves will
      gain `method =`** — `R/create_env.R:175,200`, `R/remove_env.R:39,44`,
      `R/list_packages.R:54`, `R/create_base_env.R:11`, `R/run.R:138`,
      `R/run_pipeline.R:454` (all call `env_exists()`), plus
      `R/install_packages.R:67` (calls `list_envs()` + `%in%`, which should
      become an `env_exists()` call instead now that a purpose-built
      predicate exists). Each of these must pass its own already-resolved
      `method` down explicitly instead of omitting the argument.

12. **`env_exists()` needs a dedicated internal single-backend primitive,
    separate from the public function — not just "call it with a resolved
    `method =`".** Confirmed with the user 2026-07-15 as "a true challenge"
    worth scoping out. The reason it's different from decision 11's general
    rule: `resolve_backend()` (decision 5) itself needs to answer "which
    registered backend(s), if any, already have an environment named
    `env_name`" as part of resolving what `method = "auto"` even means for
    an *existing* env — but that answer is circular if it's computed by
    calling the public `env_exists()`, which itself calls `resolve_backend()`.

    Fix: a non-exported primitive, `backend_has_env(backend, env_name,
    verbose)`, that takes an already-resolved backend *object* (not a
    method string) and calls the `backend_env_exists()` S3 generic
    (decision 4) directly — no method resolution, no registry lookup.

    - `resolve_backend(env_name, method = "auto")` for an existing-env
      lookup calls `backend_has_env()` once per *registered* backend (not
      gated on `backend_available()` — an existing env under an
      unavailable/unloaded backend is still a real conflict to report, not
      something to silently skip past): zero matches → treat as a new env,
      fall through to decision 6's priority-list resolution; exactly one
      match → that's the owner; more than one match (the same `env_name`
      genuinely exists under two different backends' roots, since each
      backend has its own namespace) → `cli::cli_abort()` asking the caller
      to disambiguate with an explicit `method =`, rather than guessing.
    - The public `env_exists(env_name, method = "auto")`, called at top
      level, does the same per-backend probe but reduces with `any()`
      instead of erroring on multiple matches — "does it exist anywhere" is
      well-defined even when it exists under two engines at once; only
      *acting* on it (decision 5's mutating-call path) requires
      disambiguation.
    - Every internal call site listed in decision 11's second bullet
      (`create_env.R`, `remove_env.R`, `list_packages.R`,
      `create_base_env.R`, `run.R`, `run_pipeline.R`) calls
      `backend_has_env()` with its own already-resolved backend object, once
      that resolution has happened — never the public `env_exists()`.
    - The marker file from decision 5a ends up *not* load-bearing for this
      discovery step (directory-tree placement under a specific backend's
      root already disambiguates which backend an env belongs to
      structurally); it remains a defense-in-depth consistency check plus a
      home for future backend-specific metadata, not the mechanism
      `resolve_backend()` uses to find an env in the first place.

## Open questions

None remaining. Resolved 2026-07-15: backend name vocabulary (decision 1),
explicit `method =` on every backend-touching function plus mutating/
read-only mismatch handling (decision 5), marker format (decision 5a),
return shape of `get_install_dir()`/`list_envs()`/`env_exists()` under
multiple backends and the hand-stamped-tibble construction (decisions
10–12).

Two more resolved 2026-07-29, during implementation, that this original
design never specified at all (found by reading `rattlerthis`'s actual
already-built adapter, not assumed): the return-shape contract for
`backend_create_env()`/`backend_install()`/`backend_remove_env()`
(resolution: they don't return anything `condathis_result`-shaped — see
`TODO.md`), and `list_packages()`'s cross-backend column schema
(resolution: a documented minimal guaranteed subset, no coercion). See
`TODO.md`'s first milestone for the full writeup, including a mechanical
S3-dispatch correction (`register_backend()` treats its argument as a
plain named-list vtable, not a pre-built S3 object) needed once
`rattlerthis`'s actual adapter code was read directly instead of assumed
from its own plan doc.

## File layout (condathis side implemented 2026-07-29 — see `TODO.md` for
## full detail; `rattlerthis` side still pending, own milestone in `TODO.md`)

```
condathis/
  R/
    backend.R              # register_backend(), get_backend(), resolve_backend(),
                            # backend_* generic definitions, contract validation
    backend-query.R        # internal single-backend primitives: backend_has_env(),
                            # install_dir_for_backend(), env_dir_for_backend() —
                            # decisions 11/12; never call the public multi-backend
                            # functions from here or from inside a backend's own code
    backend-micromamba.R   # wraps existing native_cmd.R path as a conforming backend,
                            # registered in .onLoad(); its internals use
                            # backend-query.R primitives directly, not
                            # get_install_dir()/env_exists(). Contract functions named
                            # micromamba_backend_<verb>(), not a dotted generic.class
                            # name — see TODO.md for why.
  tests/testthat/
    test-backend.R         # register_backend() validation, resolve_backend() logic,
                            # method="auto" priority resolution, multi-backend
                            # env_name collision error (decision 12) — via a lightweight
                            # in-tree fake second backend, not rattlerthis itself

rattlerthis/                # NOT YET DONE — see TODO.md's second milestone
  R/
    condathis-backend.R    # adapter already exists (R/condathis-backend.R,
                            # R/resolve-run.R) but new_backend_rattler() still
                            # returns an empty vtable; needs populating before
                            # condathis::register_backend("rattler", ...) works
  tests/testthat/
    test-condathis-backend.R
```
