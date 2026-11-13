# Backend abstraction for `condathis`

Decisions 1 to 12 are the design of 2026-07-15. Later changes to the
contract are at the end of this file: "Where the contract stands on
2026-11-13", "Environment definitions in the contract (2026-11-13)"
(decisions 13 to 18) and "Contract changes in the 0.2.0 CRAN
preparation" (decisions 19 to 21) and "rattlerthis opting in to
environment definitions" (decision 22, planned). `?register_backend` is
the reference for the current contract.

## Context

`condathis::create_env()` and `condathis::run()` both carry a `method =
c("native", "auto")` argument today. It is fully vestigial: `rlang::arg_match()`
validates the value and then `if (isTRUE(method %in% c("native", "auto")))`
gates the only code path that exists, so both values do the same thing.
`install_packages()` doesn't even have the argument. Every entry point
ultimately calls `native_cmd()` (`R/native_cmd.R`), which shells out to a
`micromamba` binary managed under `get_install_dir()` via `processx::run()`.
"native" originally meant "run on the host", as opposed to inside a
container.
The `docker`/`singularity` backends were planned but never built.

That plan is worth reviving now for a different reason: `rattlerthis`
(sibling package, `github.com/luciorq/rattlerthis`) reimplements the same
create/install/run surface without shelling out to `micromamba` at all.
It calls the `rattler` Rust crates in-process via `rextendr`. So `condathis` now
has two real, working "run things on the host" engines, not zero, plus the
still-live idea of container engines. That's exactly the shape a backend
abstraction is for.

## Goals

- Let `condathis` dispatch `create_env()`/`install_packages()`/`run()`/
  `remove_env()`/`list_envs()`/`env_exists()`/`list_packages()`/
  `get_env_dir()`/`get_install_dir()` to a pluggable backend instead of
  hardcoding `native_cmd()`.
- Define the *minimal* contract an external package must implement to add a
  new backend (starting with `rattlerthis`, container backends later).
- Do this without forcing `condathis` itself to depend on Rust, Docker, or
  anything beyond what it needs today (it currently has zero compiled
  dependencies and no `SystemRequirements`).
  Protect that.
- Preserve `condathis`'s existing user-facing signatures and default
  behavior. Nobody's `create_env(packages = "bioconda::fastqc")` call should
  need to change.

## Non-goals (this round)

- Actually implementing a docker/singularity backend package. This doc only
  defines what such a package *would* need to provide.
- Changing `run()`'s `processx`-level behavior (streaming, spinner, timeout,
  interrupt handling, `supervise`/`cleanup_tree`/`linux_pdeathsig`). That
  logic stays centralized in `condathis` (see decision 4).

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
   session and mapping internally to `"micromamba"`, never silently.
   Confirmed with the user 2026-07-15: explicit engine names, no generic
   "native".

2. **The registry and generics live in `condathis`, not in a new package or
   in `rattlerthis`.** `condathis` is the user-facing package that already
   owns the `method =` argument and its users.
   Moving the dispatch surface
   elsewhere would just add an extra package to install for no benefit at
   this scale (a handful of generics). Confirmed with the user 2026-07-15.

3. **Dependency direction: backends register themselves *into* `condathis`,
   `condathis` never `Imports`/`Depends` on a backend package.** A backend
   package (e.g. `rattlerthis`) calls
   `condathis::register_backend("rattler", rattlerthis:::as_condathis_backend())`
   from its own `.onLoad()`, guarded by
   `if (requireNamespace("condathis", quietly = TRUE))`. This keeps
   `condathis` installable with zero compiled dependencies exactly as today.
   Picking up a Rust-based backend is opt-in by installing `rattlerthis`
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
   - `backend_resolve_run(backend, cmd, args, env_name, verbose)`: the key
     design choice. Instead of each backend re-implementing process
     execution (streaming, spinner, timeout, interrupt, supervise/
     cleanup_tree/linux_pdeathsig, all the hard-won logic in
     `run_internal_native.R`/`run_process_with_input.R`), a backend only
     *resolves* what to run: it returns
     `list(command = <path/exe>, args = <character vector>, env = <named
     character vector of env vars>, dir = <working dir or NULL>)`.
     `condathis::run()` keeps the single `processx::run()`/
     `run_process_with_input()` call site and applies it uniformly. For
     `micromamba`, resolving means computing the activation env vars for the
     prefix. For `rattler`, it's a direct pass-through of
     `rattlerthis`'s own `rattler_shell::Activator` output (this backend
     already produces exactly this shape internally: see its PLAN.md
     decision 3, "hybrid model"). For a future `docker` backend, `command`
     would be `"docker"` and `args` would be `c("run", "--rm", image, cmd,
     args...)`. **No backend, including future container backends, needs to
     touch `processx` directly.**
   - `backend_available(backend)`: cheap, side-effect-free capability probe
     (is the Rust lib loaded? is a `docker` daemon reachable? is a binary on
     `PATH`?).
     It resolves `method = "auto"`.

5. **Per-environment backend persistence, and `method =` becomes explicit on
   every function that touches a backend.** A backend choice is made once,
   at `create_env()` time, and must stick for the life of that environment:
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
   argument: `install_packages()`, `remove_env()`, `list_envs()`,
   `env_exists()`, `list_packages()`, `get_env_dir()`, `get_install_dir()`,
   in addition to `create_env()`/`run()`. `resolve_backend(env_name, method,
   mutating)` is the shared internal helper all of them call:

   - `method` explicit and not `"auto"`, env already exists, and it
     disagrees with the stored marker -> **mutating** calls
     (`install_packages()`, `remove_env()`, `create_env(overwrite = TRUE)`)
     `cli::cli_abort()`: acting on an environment with the wrong engine can
     corrupt it (e.g. `rattler`'s `Installer` and `micromamba`'s prefix
     layout aren't interchangeable). **Read-only** calls (`list_packages()`,
     `env_exists()`, `get_env_dir()`) instead `cli::cli_warn()` and use the
     *actual stored* backend regardless of what was requested.
     A query should reflect reality, not silently return nothing/wrong data because
     the caller guessed the wrong engine.
   - `method` explicit, env doesn't exist yet -> used as-is (this is the
     only case that matters for `create_env()` itself).
   - `method = "auto"`, env exists -> read the stored marker, no
     ambiguity.
   - `method = "auto"`, env doesn't exist -> priority-list resolution
     (decision 6).

   This removes the need to repeat the *correct* `method =` on every call
   once an environment exists (`"auto"` still works and just reads the
   marker), while making it possible to *notice*, loudly, when a caller's
   explicit assumption about which engine owns an environment was wrong.

   5a. **Marker format: JSON via `jsonlite`.** `condathis` already depends
   on `jsonlite` (used by `list_envs()`/`get_env_history_channels()`
   today), so this adds no new dependency (confirmed with the user
   2026-07-15 as the natural choice over introducing a YAML dependency for
   one small file).
   Written at `<env_dir>/.condathis/backend.json`, e.g.
   `{"backend": "rattler", "schema_version": 1}`, leaving room for
   backend-specific metadata later (a docker backend would presumably add
   an `"image"` field) without a format migration.

6. **`method = "auto"` resolution order.** Configurable via
   `getOption("condathis.backend_priority", c("rattler", "micromamba"))`:
   first registered *and* `backend_available()` backend wins. Defaulting
   `rattler` first is a bet that most users will eventually prefer the
   in-process engine over shelling out to a managed binary.
   Revisit once
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
   1:1 in spirit: `rattlerthis` needs one new small adapter file
   (e.g. `R/condathis-backend.R`) that wraps each existing function as the
   corresponding `backend_*` S3 method plus a constructor and `.onLoad()`
   registration call, guarded by `requireNamespace("condathis", quietly =
   TRUE)`. No changes to `rattlerthis`'s own public API are needed.
   It keeps working standalone for anyone who doesn't use `condathis` at all.

9. **What a future container backend package would need to supply.**
   Concretely, beyond the 10 generics: a way to resolve/pull an image per
   `env_name` (probably its own `create_env()` semantics: "build/pull an
   image with these packages" rather than "populate a directory"),
   `backend_get_env_dir()` returning something meaningful for a bind-mount
   rather than a real prefix path, and `backend_resolve_run()` translating
   `cmd`/`args`/`env_name` into a `docker run`/`singularity exec` invocation
   with the right mounts and env var passthrough. `backend_available()`
   would probe for a reachable daemon (`docker info` exit status). No
   changes to the contract itself should be needed.
   This was the point of
   designing generic 4 (`backend_resolve_run`) around "resolve, don't
   execute" rather than "each backend runs its own subprocess".

10. **`get_install_dir()`/`list_envs()` return a tibble-classed data frame,
    `env_exists()` stays a logical scalar.** Resolves the previous open
    question. Confirmed with the user 2026-07-15:

    - `get_install_dir(method = "auto")` -> one row per registered *and*
      available backend, columns `backend` (chr), `path` (chr). With an
      explicit single `method =`, always still a 1-row tibble of the same
      shape (not a bare string).
      The return type never depends on which
      value `method` takes, only the row count does.
    - `list_envs(method = "auto")` -> one row per environment across every
      registered + available backend, columns `backend` (chr), `env_name`
      (chr), `path` (chr). Same shape rule: an explicit single `method =`
      still returns this 3-column tibble, just filtered to that backend.
    - `env_exists(env_name, method = "auto")` stays a plain `TRUE`/`FALSE`
      scalar.
      It's a predicate, not a listing, so "does it exist anywhere"
      is well-defined without a `backend` column. See decision 11 for how
      "anywhere" is actually resolved.

    This is a breaking return-type change for `list_envs()`/
    `get_install_dir()` (today: bare `character`), unavoidable once more
    than one backend can be registered.
    This is worth a `NEWS.md` bullet and a
    major/minor version bump, not a patch.

    **No new `tibble` dependency.** Confirmed with the user 2026-07-15:
    reuse the exact pattern `list_packages()` already uses at
    `R/list_packages.R:94-95`:
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

11. **Internal call sites never pass (or default to) `method = "auto"`:
    they thread down whatever `method` their own caller already resolved.**
    Confirmed with the user 2026-07-15. This is a coding convention enforced
    by review, not runtime call-stack introspection (no `sys.call()`
    trickery to detect "am I top-level").
    `method = "auto"` only ever gets
    evaluated at the point a user calls an exported function directly
    without specifying it.

    Auditing today's actual call sites shows two different situations,
    which get fixed differently:

    - **Calls from inside what becomes the `micromamba` backend's own
      implementation**: `R/native_cmd.R:86`, `R/run_internal_native.R:53,72`,
      `R/install_micromamba.R:101`, `R/get_best_micromamba_path.R:74,76`,
      `R/micromamba_bin_path.R:20`, and `R/get_env_dir.R:24`'s
      `get_install_dir()` calls. These aren't "resolve `method`, then call
      the public multi-backend function" at all.
      Once this code moves into
      `backend-micromamba.R` (decision 8), it's *inherently* scoped to the
      one backend it belongs to. It should call a plain internal
      single-backend primitive directly (e.g. `install_dir_for_backend(backend)`
      returning a bare path), never the public tibble-returning
      `get_install_dir()`.
    - **Calls from top-level orchestration functions that themselves will
      gain `method =`**: `R/create_env.R:175,200`, `R/remove_env.R:39,44`,
      `R/list_packages.R:54`, `R/create_base_env.R:11`, `R/run.R:138`,
      `R/run_pipeline.R:454` (all call `env_exists()`), plus
      `R/install_packages.R:67` (calls `list_envs()` + `%in%`, which should
      become an `env_exists()` call instead now that a purpose-built
      predicate exists). Each of these must pass its own already-resolved
      `method` down explicitly instead of omitting the argument.

12. **`env_exists()` needs a dedicated internal single-backend primitive,
    separate from the public function, not just "call it with a resolved
    `method =`".** Confirmed with the user 2026-07-15 as "a true challenge"
    worth scoping out. The reason it's different from decision 11's general
    rule: `resolve_backend()` (decision 5) itself needs to answer "which
    registered backend(s), if any, already have an environment named
    `env_name`" as part of resolving what `method = "auto"` even means for
    an *existing* env.
    But that answer is circular if it's computed by
    calling the public `env_exists()`, which itself calls `resolve_backend()`.

    Fix: a non-exported primitive, `backend_has_env(backend, env_name,
    verbose)`, that takes an already-resolved backend *object* (not a
    method string) and calls the `backend_env_exists()` S3 generic
    (decision 4) directly.
    There is no method resolution and no registry lookup.

    - `resolve_backend(env_name, method = "auto")` for an existing-env
      lookup calls `backend_has_env()` once per *registered* backend (not
      gated on `backend_available()`: an existing env under an
      unavailable/unloaded backend is still a real conflict to report, not
      something to silently skip past): zero matches -> treat as a new env,
      fall through to decision 6's priority-list resolution.
      Exactly one
      match -> that's the owner; more than one match (the same `env_name`
      genuinely exists under two different backends' roots, since each
      backend has its own namespace) -> `cli::cli_abort()` asking the caller
      to disambiguate with an explicit `method =`, rather than guessing.
    - The public `env_exists(env_name, method = "auto")`, called at top
      level, does the same per-backend probe but reduces with `any()`
      instead of erroring on multiple matches.
      "Does it exist anywhere" is
      well-defined even when it exists under two engines at once.
      Only
      *acting* on it (decision 5's mutating-call path) requires
      disambiguation.
    - Every internal call site listed in decision 11's second bullet
      (`create_env.R`, `remove_env.R`, `list_packages.R`,
      `create_base_env.R`, `run.R`, `run_pipeline.R`) calls
      `backend_has_env()` with its own already-resolved backend object, once
      that resolution has happened, never the public `env_exists()`.
    - The marker file from decision 5a ends up *not* load-bearing for this
      discovery step (directory-tree placement under a specific backend's
      root already disambiguates which backend an env belongs to
      structurally).
      It remains a defense-in-depth consistency check plus a
      home for future backend-specific metadata, not the mechanism
      `resolve_backend()` uses to find an env in the first place.

## Open questions

None remaining. Resolved 2026-07-15: backend name vocabulary (decision 1),
explicit `method =` on every backend-touching function plus mutating/
read-only mismatch handling (decision 5), marker format (decision 5a),
return shape of `get_install_dir()`/`list_envs()`/`env_exists()` under
multiple backends and the hand-stamped-tibble construction (decisions
10 to 12).

Two more resolved 2026-07-29, during implementation, that this original
design never specified at all (found by reading `rattlerthis`'s actual
already-built adapter, not assumed): the return-shape contract for
`backend_create_env()`/`backend_install()`/`backend_remove_env()`
(resolution: they don't return anything `condathis_result`-shaped: see
`TODO.md`), and `list_packages()`'s cross-backend column schema
(resolution: a documented minimal guaranteed subset, no coercion). See
`TODO.md`'s first milestone for the full writeup, including a mechanical
S3-dispatch correction (`register_backend()` treats its argument as a
plain named-list vtable, not a pre-built S3 object) needed once
`rattlerthis`'s actual adapter code was read directly instead of assumed
from its own plan doc.

## File layout (condathis side implemented 2026-07-29, see `TODO.md` for
## full detail, `rattlerthis` side still pending, own milestone in `TODO.md`)

```
condathis/
  R/
    backend.R              # register_backend(), get_backend(), resolve_backend(),
                            # backend_* generic definitions, contract validation
    backend-query.R        # internal single-backend primitives: backend_has_env(),
                            # install_dir_for_backend(), env_dir_for_backend() -
                            # decisions 11/12; never call the public multi-backend
                            # functions from here or from inside a backend's own code
    backend-micromamba.R   # wraps existing native_cmd.R path as a conforming backend,
                            # registered in .onLoad(); its internals use
                            # backend-query.R primitives directly, not
                            # get_install_dir()/env_exists(). Contract functions named
                            # micromamba_backend_<verb>(), not a dotted generic.class
                            # name - see TODO.md for why.
  tests/testthat/
    test-backend.R         # register_backend() validation, resolve_backend() logic,
                            # method="auto" priority resolution, multi-backend
                            # env_name collision error (decision 12) - via a lightweight
                            # in-tree fake second backend, not rattlerthis itself

rattlerthis/                # NOT YET DONE - see TODO.md's second milestone
  R/
    condathis-backend.R    # adapter already exists (R/condathis-backend.R,
                            # R/resolve-run.R) but new_backend_rattler() still
                            # returns an empty vtable; needs populating before
                            # condathis::register_backend("rattler", ...) works
  tests/testthat/
    test-condathis-backend.R
```

## Where the contract stands on 2026-11-13

The code moved on after decisions 1 to 12. These parts of this file no
longer match it:

- Decisions 4 and 7: there are no longer 10 required generics. The
  current contract, called "version 2" in the code comments, has three
  required functions, `backend_create_env`, `backend_install` and
  `backend_resolve_run` (`backend_required_hooks`, `R/backend.R:14-18`),
  and optional ones (`backend_optional_hooks`, `R/backend.R:28-43`). For
  an optional function that a backend object leaves out, S3 dispatch
  reaches the default of condathis (`backend_<x>.default` in
  `R/backend-defaults.R`).
- Decision 6: the default of `condathis.backend_priority` is
  `"micromamba"` alone, not `c("rattler", "micromamba")`. Loading a
  backend package does not change where new environments go
  (`backend_names_by_priority()`, `R/backend.R:2068-2107`).
- `TODO.md`, first milestone: the `condathis_native_warned` flag is
  gone (decision 20).

## Environment definitions in the contract (2026-11-13)

On 2026-11-13 the maintainer asked whether `create_env(env_file = )`
could be deprecated "in favor of an accessory function like we did for
the path environments". The maintainer then asked for "a generic name
that does not depend on the extension", whether rattler and pixi should
read files, and: "How would be the overall design pattern that do not
limit the backend extensions?". A design run compared three designs and
recommended `env_definition()` for 0.3.0, with the contract changes
below. The maintainer decided (verbatim):
"I want all if it implemented now in v0. 2 deprecate env_file". So all
of it, the "later" items of the design included, is in 0.2.0. On
2026-11-13 it is in the working tree, not committed.

The user-facing side (the `env_definition()` object, the formats, the
lock rules, how the micromamba backend reads files, the deprecation of
`env_file =`) is in `../feat-env-file/PLAN.md`. This section records
only the backend contract. The pixi findings of the same research are in
`../feat-pixi-backend/PLAN.md`.

13. **Additive only. condathis owns a neutral object, the backend owns
    the formats.** An `env_definition()` is a list with `path`, `format`
    (`NULL` or a string) and `options` (a named list). condathis never
    reads `format` or `options`. It understands one thing that the
    backend reports: the kind, `"request"` (solved) or `"lock"`
    (installed as it is, without a solve). The model is conda's
    "environment specifier" plugins, which split `requested_packages`
    from `explicit_packages`. A new format, such as pixi.lock v7, is then
    a change in a backend only, and condathis keeps no list of formats.
    Every addition below is optional: a backend written for version 2
    works unchanged (decision 18).

14. **Optional arguments `definition` and `env_file`.**
    - `backend_create_env()` and `backend_can_solve()` can take
      `definition = NULL`. condathis still passes
      `env_file = definition$path`. It passes `definition` only when
      `env_file` is set and the function takes `definition` by name or
      has `...`.
    - `backend_install()` can take `env_file = NULL` and
      `definition = NULL`. `install_packages(env_definition(<request>))`
      passes `packages = NULL` and the file. An install function that
      takes neither cannot install from a file: `install_packages()`
      aborts before any call, with class
      `condathis_install_packages_unsupported_definition` and the reason
      "The backend does not install packages from a file."
      (`definition_formal_problem()`, `R/env_definition_checks.R:36-51`).
      One that takes only `env_file` gets the path.
    - A function without `definition` cannot honor a `format` or
      options. A definition with either aborts before any call, with
      class `condathis_<fn>_unsupported_definition` (also
      `condathis_backend_unsupported` and `condathis_invalid_arg`).
    - These arguments are listed in `backend_optional_args`
      (`R/backend.R:1204-1210`), next to the older `timeout` of
      `backend_resolve_run()` and `backend_resolve_run_in_dir()`.
      `register_backend()` does not report them as missing formals
      (`validate_backend_object()`, `R/backend.R:1150-1159`).

    Deviation from the design: it added only `definition`, to create and
    can_solve. `env_file` on install came with the implementation of
    `install_packages(env_definition())`: `backend_install()` had no file
    argument at all, so "pass the path only" had nothing to pass it to.

15. **New optional function
    `backend_describe_definition(backend, definition, platform = NULL)`.**
    It tells condathis what the backend makes of a definition. The full
    text is in `?register_backend` (`R/backend.R:515-563`). It returns a
    list:

    | Element | Value |
    |---|---|
    | `supported` | `TRUE` (reads it), `FALSE` (does not) or `NA` (cannot tell) |
    | `format` | `NA`, or the format name it detected or was given |
    | `kind` | `"request"`, `"lock"` or `NA` |
    | `platforms` | `NULL`, or the platforms a lock has packages for (`noarch` left out) |
    | `reason` | `NA`, or one sentence: why `supported` is `FALSE` |
    | `records` | `NULL`, or for a lock a data frame with the character columns `name`, `version`, `build_string`, `platform` |

    Rules for the backend:
    - Cheap: read the file, but do not download, install or solve
      anything, and do not change any environment. `create_env()` calls
      it before it locks, moves or creates anything (rule R2,
      `R/create_env.R:381-404`).
    - Refuse an option of `definition$options` that you do not
      understand. Never ignore it. The micromamba backend refuses every
      option but `categories`.
    - An error counts as `NA` (`probe_or_na()` in
      `backend_describe_definition_checked()`,
      `R/backend-query.R:527-551`). A value that breaks the shape aborts
      with class `condathis_backend_invalid_return` (also
      `condathis_backend_contract_violation`), see
      `validate_definition_description()` (`R/backend-query.R:433-510`).
      Missing elements get their defaults, so a backend may return only
      `supported` and `kind`.
    - Default (`R/backend-defaults.R:313-331`): all `NA`, which is the
      behavior from before the function existed. It is `FALSE`, with a
      reason, when the definition has a `format` or options and the
      backend's `backend_create_env()` has no `definition` argument.

    What condathis does with the answer:
    - `FALSE`: aborts with `condathis_<fn>_unsupported_definition`, with
      the reason in the message.
    - `"request"`: goes on as for package specs. `backend_can_solve()`
      gets the file (and `definition`, when it takes it) for the
      emulated-platform fallback.
    - `"lock"`: never calls `backend_can_solve()`, since micromamba's
      `create --dry-run --json -f <lock>` returned success for every lock,
      an invalid one too. Picks the platform from `platforms`. Aborts for
      `channels`, `additional_channels` or `channel_priority` given with
      an `env_definition()`. An empty environment from a lock that has
      records for the platform fails with `condathis_create_env_failed`.
      With `records`, `create_env(overwrite = FALSE)` keeps an
      environment with exactly those packages, and `validate_env()`
      compares.
    - `NA`: passes the file on with no other check, as before.
    - `install_packages()` and `validate_env()` call it too
      (`check_install_definition()`, `R/install_packages.R:483-518`;
      `validate_env_lock_records()`, `R/validate_env.R:395`).
      `install_packages()` takes a request only, `validate_env()` a lock
      with records only.
    - `method = "auto"` for a new environment: `resolve_backend()` and
      `resolve_backend_by_priority()` gained the arguments `accept` and
      `on_refused` (`R/backend.R:1724-1767`, `1858-1904`).
      `create_definition_routing()` (`R/create_env.R:899-936`) asks each
      available backend once (the answer is cached for the second
      resolve under the lock) and skips a backend whose `supported` is
      `FALSE`. `NA` counts as "can read". When every available backend
      refuses, `abort_no_backend_for_definition()` lists each backend
      with its reason. An explicit `method`, or an existing environment,
      is never rerouted. This is the routing that `env_path()` objects
      already had.

16. **New optional function `backend_definition_formats(backend)`.** A
    character vector of the format names the backend reads. It is used
    in messages only: `definition_format_hint()`
    (`R/env_definition_checks.R:110-130`) names the other registered
    backends that list the `format` of a refused definition. condathis
    never decides from it. Default: `character(0)`
    (`R/backend-defaults.R:336-338`). A function that fails or returns
    an invalid value is left out (`registered_definition_formats()`,
    `R/backend-query.R:564-580`). The micromamba backend lists
    `environment-yaml`, `requirements`, `explicit`, `conda-lock-v1`,
    `mambajs-lock-v1` and `cep-24`.

17. **The generics keep their version 2 formals.** This deviates from
    the design, which added `definition` to the formals of the generics.
    The first implementation round did that. The second round, on
    2026-11-13, put the generics back after reading rattlerthis's
    `tests/testthat/test-registration.R`. For each backend function it
    asserts that `formals()` is identical to the formals of the condathis
    generic, and that `utils::getS3method(<generic>,
    "condathis_backend_rattler")` is the backend's own function. A new
    formal in a generic fails that unchanged test. The mechanism instead:
    - `backend_call(generic_name, backend, ..., .optional)`
      (`R/backend.R:1311-1325`): when the backend's own function takes an
      optional argument (by name or through `...`), condathis calls that
      function directly, with it. Otherwise, and for a function the
      object leaves out (the defaults of condathis take none), it calls
      the generic as before. `create_env()`, `install_packages()` and
      `backend_can_solve_checked()` use it.
    - `backend_s3_method(fn, generic_name)` (`R/backend.R:1253-1272`),
      called by `register_backend_impl()` (`R/backend.R:861-866`): a
      function with arguments that its generic lacks is registered
      through a wrapper with exactly the formals of the generic. Any
      other function is its own method. Reason: R CMD check compares an
      S3 method with its generic. It gave a WARNING for the micromamba
      functions with `definition`, then an internal error while the
      wrapper had the function inside its body. The wrapper now keeps
      the function in its environment.
    - `backend_fn_takes_arg()` (`R/backend.R:1340-1347`) answers whether
      a backend function can get an argument.

    Rule for backend authors: add the optional arguments to your own
    functions. Do not expect them in the generics.
    Tests: `test-env_definition.R:528` (a backend with the rattlerthis
    formals keeps working) and `test-env_definition.R:1570` (registered
    methods match the generics, a function without optional arguments
    is its own method, and the wrapper forwards every argument, a
    missing one too).

18. **rattlerthis keeps working unchanged.** The reasons, from reading
    rattlerthis `main` on 2026-11-13 (`R/condathis-backend.R:269`, `357`
    and `766`):
    - Its `backend_create_env`, `backend_install` and `backend_can_solve`
      have exactly the version 2 formals, without `definition` and
      without `...`. They are registered as themselves, so its
      `test-registration.R` still holds.
    - It has no describe function. The default gives `NA` for a
      definition without `format` or options, so condathis passes the
      path as `env_file`, as in 0.1.4, and applies no lock rule.
      rattlerthis reads the file with its own `rt_read_env_file()`.
    - A definition with a `format` or options aborts before any rattler
      call. `install_packages(env_definition(...), method = "rattler")`
      aborts, since its install takes no file. `validate_env()` with a
      definition aborts, since it reports no records.
    - `create_env(env_file = )` warns with
      `condathis_deprecated_env_file_arg` once per session in
      rattlerthis's own tests, which run with `TESTTHAT_PKG=rattlerthis`
      (`is_direct_use()`, `R/conditions.R:220`). A call from rattlerthis
      code does not warn.
    - The deprecated `env_file =` route ignores `channels`,
      `additional_channels` and `channel_priority` for a lock, as 0.1.4
      did. The first implementation aborted there. The review found
      that this broke rattlerthis's micromamba-side parity fixtures
      (`test-parity-envfile.R`, fixtures e6, e7, e9, e10 and e11), and
      the repair round restored the 0.1.4 behavior.

    How this was checked: rattlerthis is not installed in the local R
    library, and a build on the Linux host failed (no `pkg-config`; with
    a shim, the Rust release build ran out of disk), so it was not run.
    condathis's tests
    use a stub backend with the rattlerthis formals. The repair round
    replayed rattlerthis's parity fixtures with its own helper scripts
    against the patched condathis, on the micromamba side only. A real
    rattlerthis test run is open in `TODO.md`.

## Contract changes in the 0.2.0 CRAN preparation

From commit `8cffc25` ("feat: prepare condathis 0.2.0 for CRAN",
2026-11-13), after the review of how 0.1.4 callers use the API.

19. **`validate_method_arg()` accepts the 0.1.4 default vector.**
    `create_env()` and `run()` had `method = c("native", "auto")` in
    0.1.4, and `rlang::arg_match()` took the first element. A wrapper
    that copied that signature passes the whole vector, which aborted in
    the 0.2.0 draft. Now `c("native", "auto")` and `c("auto", "native")`
    give their first element, and any other vector still aborts
    (`R/backend.R:1523-1579`). Every caller uses the returned value.
    Test: `test-backend.R:1263-1265`.

20. **The `"native"` deprecation is soft, with `user_env`.**
    `resolve_method_alias(method, user_env = NULL)` and
    `resolve_backend(..., user_env = NULL)` take the environment the
    exported function was called from: `rlang::caller_env()`, evaluated
    in the exported function, never in a helper. The warning
    `condathis_deprecated_method_native` goes through
    `condathis_deprecate_soft()` (`R/conditions.R:261`). It warns once
    per session, and only for direct use: from the global environment,
    or from the tests of the package under test (`TESTTHAT_PKG`).
    `lifecycle_verbosity` is respected. This is the rule of
    `lifecycle::deprecate_soft()`, in base R. A call from inside a
    package namespace, such as a backend package, does not warn and does
    not use up the warning. It replaced the `condathis_native_warned`
    flag. Test: `test-backend.R:1198` ("method = 'native' is a soft
    deprecation").

21. **`register_backend()` is experimental.** Its help page has a
    *Lifecycle* section (`R/backend.R:174`): the API may change in
    breaking ways between `0.x` releases, and a backend package should
    state the condathis version it was developed against, for example
    `condathis (>= 0.2.0)` in `Imports`. README, NEWS and the backends
    article say the same.

## rattlerthis opting in to environment definitions (planned)

22. **Not started. Each step works on its own.** rattlerthis already
    reads files: `rt_read_env_file()` (Rust, `src/rust/src/envfile.rs`)
    reads environment YAML, plain spec lists, `@EXPLICIT`, conda-lock v1
    and mambajs files. Like micromamba, it picks the reader by file name
    (`classify()`, `envfile.rs:202-213`). YAML and plain files are solved
    with `rt_install()`. The others are installed without a solve by
    `rt_install_explicit()`. To opt in, in rattlerthis:
    - `backend_describe_definition`: wrap `rt_read_env_file()`. Report
      `kind` (YAML and plain: `"request"`; explicit, conda-lock and
      mambajs: `"lock"`), `platforms` (the `platforms` field it already
      parses, `envfile.rs:174-175`) and `records`. Then condathis applies
      the lock rules and the lock comparison to rattler environments
      too. It also stops asking rattlerthis's `backend_can_solve()` about
      locks: that function returns `TRUE` for every lock, also one
      without packages for the platform (`R/condathis-backend.R:786-790`),
      which gives an empty environment.
    - `definition` on its `backend_create_env()` (and
      `backend_can_solve()`), to honor `format` and options. A `format`
      that disagrees with the file name needs a reader chosen by format,
      not by name. Refuse unknown options.
    - `env_file` and `definition` on its `backend_install()`, so that
      `install_packages(env_definition(<request>), method = "rattler")`
      works. Refuse a lock.
    - `backend_definition_formats`.
    - `tests/testthat/test-registration.R`: add the new hooks to
      `hook_generics`. For a function with optional arguments, compare
      its formals without the names in `condathis:::backend_optional_args`,
      and expect the registered S3 method to be a wrapper with the
      formals of the generic, not the function itself (decision 17).
    - Its tests that call `create_env(env_file = )`: move most to
      `env_definition()`. Keep a few for the deprecated path.
    - Later: pixi.lock through the `rattler_lock` crate, see
      `../feat-pixi-backend/PLAN.md`.

    The design estimated about one day for the opt-in, and two to three
    days or more for pixi.lock (vendor size and MSRV not measured).

## Files added or changed for decisions 13 to 21

```
R/backend.R                        generics, backend_optional_args,
                                   backend_call(), backend_s3_method(),
                                   resolve_backend(accept, on_refused,
                                   user_env), validate_method_arg()
R/backend-defaults.R               default describe and formats functions
R/backend-query.R                  backend_describe_definition_checked(),
                                   validate_definition_description(),
                                   registered_definition_formats()
R/backend-micromamba.R             vtable entries; `definition` on create,
                                   `env_file` and `definition` on install
R/backend-micromamba-definition.R  (new) how micromamba reads a definition
R/env_definition.R                 (new) env_definition()
R/env_definition_checks.R          (new) formal checks, refusal errors,
                                   lock record comparison
```
