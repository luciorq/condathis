# TODO

Status and roadmap for the backend-abstraction work. See `PLAN.md` for the
design behind these decisions.

Resolved 2026-07-15 (see PLAN.md decisions 1, 5, 10–12): explicit backend
vocabulary (`"micromamba"`/`"rattler"`/`"docker"`/`"singularity"`, `"native"`
deprecated), every backend-touching function gets an explicit `method =`
argument with mutating-calls-error/read-only-calls-warn on marker mismatch,
the marker is JSON via the already-present `jsonlite` dependency,
`get_install_dir()`/`list_envs()` become tibble-returning (`backend`/`path`/
`env_name` columns, hand-stamped via the existing `R/list_packages.R`
`unclass()` + `attr(x, "class") <- c("tbl_df", "tbl", "data.frame")`
pattern — no new `tibble` dependency) while `env_exists()` stays a logical
scalar resolved via a dedicated internal `backend_has_env()` primitive, and
internal call sites must thread an already-resolved `method` down rather
than defaulting to `"auto"`.

## Milestone: backend contract in `condathis` (DONE — 2026-07-29)

Goal: registry + generics + `"micromamba"` wrapped as the first conforming
backend, every backend-touching function dispatching through it, zero
behavior change for today's single-backend users. Implemented in one pass
(not split into the originally-sketched phase 1/phase 2), verified against
the full existing test suite plus a new `test-backend.R`.

Before implementing, the plan itself was revisited against the *current*
codebase (this doc was written 2026-07-15, before a `timeout` argument was
added to `run()`/`run_bin()`/`run_pipeline()`, `install_micromamba.R`/
`create_env.R` were refactored for cyclomatic complexity, and
`validate_env_name()` was introduced) and two contract-shape gaps the
original design never specified were resolved with the author:

- **Result-shape reconciliation**: `backend_create_env()`/`backend_install()`/
  `backend_remove_env()` do **not** need to return anything
  `condathis_result`-shaped. They signal success (return value ignored) or
  throw a condition on failure; the public `create_env()`/`install_packages()`/
  `remove_env()` wrappers build the actual `condathis_result` themselves
  afterward, since they already have `env_name`/`cmd` in scope. Confirmed
  necessary by reading `rattlerthis`'s actual (already-built)
  `R/condathis-backend.R`: its `create_env()`/`install()`/`remove_env()`
  return a completely different `rattlerthis_result` object
  (`status, env_name, prefix, packages, duration`), not `condathis_result`.
- **`list_packages()` schema**: documented a minimal guaranteed-columns
  subset across backends — `name`, `version`, `build_number`, `channel`
  (the true intersection; `rattlerthis::list_packages()` uses `build` where
  the `"micromamba"` backend uses `build_string` — each backend-specific,
  not guaranteed). No schema coercion in the dispatch layer.

Also found and fixed one mechanical gap in the contract's own dispatch
plumbing, not a design change: `rattlerthis`'s already-built adapter
(`new_backend_rattler()`) returns an **empty** `structure(list(), class =
c("condathis_backend_rattler", "condathis_backend"))` — the 10 `backend_*`
functions are separate top-level functions in that file, never attached to
the object, and plain `UseMethod()` dispatch would never find them without
`registerS3method()` calls that would need to live in `rattlerthis`'s own
namespace. Fixed entirely on the `condathis` side instead:
`register_backend(name, backend)` treats `backend` as a plain named list
(a "vtable") and calls `base::registerS3method()` for each of the 10
entries itself, from inside `condathis`'s own namespace — so a future
backend package only needs to hand over a named list of functions, never
touch its own `NAMESPACE`. (`rattlerthis` will need to populate that list
with its already-written functions before it can actually be wired in —
tracked in the next milestone below, not done here.)

- [x] `R/backend.R`: `backend_registry` (a package-level `new.env()`),
      `backend_contract_names` (the 10 required names), `register_backend()`
      (validates the vtable is complete — `condathis_backend_contract_violation`
      if not — then `registerS3method()`s all 10 and stores the vtable),
      `get_backend()` (`condathis_backend_not_registered` if unknown),
      `list_registered_backend_names()`, `validate_method_arg()` (valid
      values computed dynamically: `"auto"`, every registered name, plus
      the deprecated `"native"`), `resolve_method_alias()` (`"native"` →
      `"micromamba"`, `cli::cli_warn(class = "condathis_deprecated_method_native")`
      exactly once per session via a small internal flag environment), the
      10 `backend_*` generic stubs (plain `UseMethod()` dispatchers,
      signatures matching `rattlerthis`'s already-built adapter exactly),
      and `resolve_backend(env_name, method, mutating, call)` — the shared
      dispatch point every backend-touching function calls, implementing
      decision 5's four cases (`env_name = NULL` / new env / single owner
      with match-or-abort-or-warn / multi-owner collision).
- [x] `R/backend-query.R`: `backend_has_env()` (calls the
      `backend_env_exists()` generic directly on an *already-resolved*
      backend — no registry lookup — this is what avoids decision 12's
      circularity), `find_owning_backends()` (iterates every *registered*
      backend, not gated on `backend_available()`, per decision 12),
      `install_dir_for_backend()`/`env_dir_for_backend()` (trivial
      pass-throughs used by internal, already-resolved call sites instead
      of the public multi-backend functions), `read_backend_marker()`/
      `write_backend_marker()` (`jsonlite::fromJSON()`/`write_json()` on
      `<env_dir>/.condathis/backend.json` — no new dependency).
- [x] `R/backend-micromamba.R`: `new_backend_micromamba()` + a cached
      `micromamba_backend()` singleton, and the 10 contract functions
      (named `micromamba_backend_create_env()`, `micromamba_backend_install()`,
      etc. — **not** dotted `generic.class` names: `roxygen2::roxygenize()`
      flags any `generic.class`-shaped name as an S3 method needing
      `@export`/`@exportS3Method` regardless of `@noRd`, and since dispatch
      here is wired dynamically via `registerS3method()` in `register_backend()`
      rather than a `NAMESPACE` `S3method()` entry, the dotted name bought
      nothing but a spurious warning on every future `roxygenize()` call —
      confirmed `registerS3method()` doesn't care what the underlying
      function is named, only that it's registered against the right
      `generic`/`class` pair). Each is today's existing function body
      relocated, with `get_install_dir()`/`get_env_dir()`/`env_exists()`
      calls swapped for the `backend-query.R` primitives:
      `micromamba_backend_create_env()` (absorbs `ensure_libmamba_pkgs_dir_workaround()`,
      `resolve_create_env_packages_arg()`, `resolve_create_env_platform_args()`,
      and the stale-directory workaround, relocated here from `create_env.R`;
      returns the raw `native_cmd()`/`rethrow_error_cmd()` result or throws —
      no `condathis_result` construction), `micromamba_backend_install()`,
      `micromamba_backend_remove_env()` (absorbs the existence-check +
      stray-directory-cleanup + abort logic relocated from `remove_env()`),
      `micromamba_backend_list_envs()` (absorbs `condathis_env_names()`,
      relocated from `list_envs.R`, unchanged), `micromamba_backend_env_exists()`,
      `micromamba_backend_list_packages()` (keeps its full native ~11-column
      schema — no shrinking to the cross-backend minimal subset here, see
      above), `micromamba_backend_get_env_dir()`, `micromamba_backend_get_install_dir()`
      (today's `get_install_dir()` body verbatim), `micromamba_backend_resolve_run()`
      (**new** — resolves `cmd`'s path via `resolve_env_bin_path()` +
      `get_micromamba_activation_envvars()`; not called by anything in this
      milestone, see the execution-path note below), `micromamba_backend_available()`
      (unconditionally `TRUE` — micromamba self-installs on first use).
      `native_cmd()`/`run_internal_native()`/`get_best_micromamba_path()`/
      `micromamba_bin_path()`/`install_micromamba.R`'s own `get_install_dir()`
      call sites were redirected to `install_dir_for_backend(micromamba_backend())`
      in place (not physically relocated into this file — they're
      plumbing `native_cmd()` itself depends on, callable from anywhere in
      the package regardless of which file defines them; only the call
      site mattered, not physical file position, for the "no calling the
      public multi-backend function from micromamba-internal code" goal).
- [x] `.onLoad()` (`R/condathis-package.R`): `register_backend("micromamba",
      new_backend_micromamba())`.
- [x] Per-environment backend marker `<env_dir>/.condathis/backend.json`:
      written by the public `create_env()` wrapper right after a
      successful `backend_create_env()` call (never inside a backend's own
      method — the format stays centralized, per decision 5a). Verified
      live: `create_env(env_name = "marker-env")` produces
      `.../marker-env/.condathis/backend.json` containing
      `{"backend":"micromamba","schema_version":1}`.
- [x] `method = "auto"` priority resolution via
      `getOption("condathis.backend_priority", c("rattler", "micromamba"))`,
      inside `resolve_backend()`'s no-`env_name`/new-env cases.
- [x] Added explicit `method =` to **every** backend-touching function:
      `create_env()`/`run()` already had it (rewired onto `resolve_backend()`);
      `install_packages()`, `remove_env()`, `list_envs()`, `env_exists()`,
      `list_packages()`, `get_env_dir()`, `get_install_dir()` are all new.
      **Also added to `run_bin()` and per-command (list-spec `method =`
      field) to `run_pipeline()`** — both were mysteriously absent from
      this doc's original "add `method =` everywhere" list, discovered
      only by reading the current signatures directly (only `run()`/
      `create_env()` had `method` at all before this milestone). `run_bin()`
      needed it because it resolves a backend's `env_dir/bin` layout
      directly — without `method`, it would silently resolve under the
      wrong root once a second backend exists. `run_pipeline()`'s
      per-command `method` mirrors its existing per-command `env_name`
      override mechanism exactly (same `parse_cmds_spec()`/`precreate_envs()`
      extension point).
- [x] `get_install_dir()`/`list_envs()` return a tibble always (`backend`/
      `path` and `backend`/`env_name`/`path` respectively) — verified live:
      `list_envs()` and `get_install_dir()` both print as
      `tbl_df`/`tbl`/`data.frame`-classed 1-row-per-backend tables with a
      single registered backend today.
- [x] Rewired all 9 functions to call `resolve_backend()` + the relevant
      `backend_*()` generic instead of `native_cmd()`/`get_install_dir()`/
      `get_env_dir()`/`env_exists()` directly. `env_exists()` is the one
      deliberate exception (decision 12): it never calls `resolve_backend()`
      at all, since resolving a backend for an *existing* environment is
      itself implemented in terms of this exact per-backend probe — it
      does its own candidate-name enumeration (`"auto"` → every registered
      name; explicit → just that one) and reduces with `any()`.
- [x] `resolve_backend(env_name, method, mutating, call)`: implements all
      four cases from decision 5/12 — `env_name = NULL` and "new
      environment" both resolve via `getOption("condathis.backend_priority")`
      order (nothing to disambiguate against yet); a single existing owner
      resolves directly, or — if the caller's explicit `method` disagrees
      with it — `cli::cli_abort(class = "condathis_backend_mismatch")` for
      `mutating = TRUE` callers (`create_env()`, `install_packages()`,
      `remove_env()`) vs. `cli::cli_warn(class = "condathis_backend_mismatch_warning")`
      **and use the actual owner anyway** for `mutating = FALSE` callers
      (`list_packages()`, `get_env_dir()`, `run()`, `run_bin()`, each
      `run_pipeline()` command); a genuine multi-backend collision
      disambiguates via a matching explicit `method`, or
      `cli::cli_abort(class = "condathis_backend_ambiguous_env")` listing
      every owner, for *every* caller regardless of `mutating` (there's no
      well-defined single answer to silently pick). All four paths
      exercised live via `test-backend.R`'s fake second backend, not just
      reasoned about.
- [x] `"native"` deprecation: `resolve_method_alias()` maps it to
      `"micromamba"` and warns exactly once per session
      (`condathis_deprecated_method_native`) — verified live: two
      successive `method = "native"` calls in the same session produce
      exactly one warning, not two.
- [x] Audited and fixed every internal call site this doc originally
      listed, using **current** line numbers (several had drifted since
      2026-07-15 — see `PLAN.md`'s "What's confirmed still accurate vs.
      what's corrected" for the full stale-reference list) — plus two real
      gaps the original audit missed entirely: `env_already_satisfies_request()`
      (a `create_env()` helper extracted this session, after this doc was
      written) called the *public* `list_packages()`, not a
      backend-resolved one — fixed by giving `satisfies_dependencies()` an
      optional `backend` parameter (`NULL` default preserves its own
      standalone public-`list_packages()`-calling behavior for direct
      callers/tests); and `run_pipeline()`'s main spawn loop's own
      `get_env_dir()` call (line ~249, inside the per-command loop, not
      inside `precreate_envs()`) — fixed by threading each command's
      already-resolved backend through from `precreate_envs()`'s new
      `resolved_backends` return value instead.
- [x] New `tests/testthat/test-backend.R`: registry contract validation
      (incomplete vtable rejected, complete vtable + re-registration both
      succeed), `resolve_backend()` precedence (explicit > stored owner >
      `"auto"` priority, each via a lightweight in-tree fake second
      backend — directory-existence-as-database, zero subprocess, *not* a
      `rattlerthis` reimplementation), mismatch handling (mutating aborts,
      read-only warns-and-uses-actual-owner — verified the *returned*
      backend name, not just that a warning fired), collision handling
      (two fake backends independently claiming the same `env_name`;
      `resolve_backend()` aborts under `"auto"` and disambiguates under an
      explicit match; `env_exists()` on the same setup returns `TRUE` via
      `any()`, no error), `"native"` deprecation (warns exactly once,
      resets/restores the session flag so this test doesn't depend on
      execution order relative to other files that also use
      `method = "native"`, e.g. `test-create_env.R`), and tibble shape
      (`get_install_dir()`/`list_envs()` with 1 vs. 2+ registered
      backends). Tests that touch a real `env_name` carry
      `skip_if_offline()`/`skip_on_cran()`, since `resolve_backend()`'s
      `find_owning_backends()` always probes *every* registered backend
      including the real `"micromamba"` one, which needs a live
      installation the first time.
- [x] Full existing test suite: zero intended behavior change for
      single-backend usage, with the two deliberate, documented exceptions
      (`get_install_dir()`/`list_envs()`'s tibble return, and
      `list_packages()`'s narrowed *documented* column guarantee — no
      actual columns removed). Test files updated for the tibble change:
      `test-list_envs.R`, `test-get_env_dir.R`, `test-create_base_env.R`,
      `test-install_micromamba.R`, `test-create_nested_env.R`,
      `test-clean_cache.R`, `test-create_env.R` (all switched
      `list_envs()`/`get_install_dir()` call sites from bare-vector
      indexing to `$env_name`/`$path`). `NEWS.md` updated with the breaking
      change.

**Deliberately not done in this milestone** (matches PLAN.md's "Non-goals"
and this doc's own scoping):

- ~~`run()`/`run_bin()`/`run_pipeline()`'s actual **execution path**~~ —
  **done 2026-08-13**, see "Backend execution path" below. All three now
  execute through any registered backend, and the
  `condathis_run_backend_unsupported`/`condathis_run_bin_backend_unsupported`/
  `condathis_pipeline_backend_unsupported` conditions no longer exist.
- `clean_cache()` and internal `packages_search_native()`/`define_platform()`
  stay micromamba-only, no generic added — `clean_cache()`'s `env_name` is
  always `NA` (a whole-root operation, not tied to any specific
  environment) and no other backend implements cache cleaning yet
  (`rattlerthis`'s own `TODO.md` lists this as an unscheduled "later
  idea"); Apple-Silicon/Rosetta solver fallback via `packages_search_native()`
  is a micromamba-solver-specific detail (`rattlerthis`'s own `TODO.md`
  lists cross-platform solving as an explicit known gap on its side too).
- `install_packages()`'s channel-history-mismatch warning
  (`get_env_history_channels()`, reads `conda-meta/history`) stays gated
  on `resolved$name == "micromamba"` — a micromamba/conda prefix-layout
  detail, not part of the generic contract.

## Milestone: backend execution path (done, 2026-08-13)

Goal: `run()`, `run_bin()` and `run_pipeline()` execute through any
registered backend, not just `"micromamba"`, reusing the same
`timeout`/`supervise`/`cleanup_tree`/`pump_process_io()` plumbing rather
than growing a parallel one (PLAN.md decision 4).

- [x] `R/execute_command.R`: the single place a child process is spawned.
      Picks `run_process_with_input()` (writable stdin) or
      `processx::run()`, and is now the only caller of either. Both
      `native_cmd()` and the new backend path go through it, so streaming,
      spinner, timeout, encoding and the crash-safety flags cannot drift
      apart between backends.
- [x] `R/run_internal_backend.R`: the `backend_resolve_run()`-based
      counterpart to `run_internal_native()`. Applies the backend's `env`
      as `c("current", env)` — `processx`'s "inherit, then override" idiom,
      the same shape `run_bin()` already used for micromamba — so a backend
      returning `NULL` means "inherit unchanged", not "run with an empty
      environment".
- [x] `validate_resolve_run()`: validates a backend's `backend_resolve_run()`
      return *before* spawning. Backends are third-party code, and a
      malformed return would otherwise surface as an opaque `processx`
      assertion naming no backend at all. Caught a real bug immediately:
      `rattlerthis` returned `env` as a named **list** (its own `run()` uses
      `withr::local_envvar()`, which accepts one), which `processx` rejects
      with `is_env_vector(env) is not TRUE`. Fixed on `rattlerthis`'s side;
      the validator now names that specific mistake.
- [x] `native_cmd()` refactored onto `execute_command()` — a pure
      extraction, no behaviour change (full suite green, including the
      network/micromamba tests).
- [x] `run()`: rejection branch replaced with `run_internal_backend()`.
- [x] `run_bin()`: resolves `cmd_path`/activation via the backend when it
      isn't `"micromamba"`. `activate = FALSE` stays honoured for every
      backend — it is the documented way to run a binary *without*
      activation variables.
- [x] `run_pipeline()`: `spawn_pipeline_process()` now takes both the
      executable path and the activation variables from
      `backend_resolve_run()` for *every* backend, including
      `"micromamba"` — `micromamba_backend_resolve_run()` computes exactly
      what that function used to inline (`resolve_env_bin_path()` with a
      bare-name fallback, plus `get_micromamba_activation_envvars()`), so
      this unified the two paths instead of adding a second one.
      `activate = FALSE` keeps the hand-rolled, backend-independent
      `get_activation_envvars()`.
- [x] `run_process_with_input()` gained `wd`, so the contract's `dir` field
      is honoured on both spawn paths.
- [x] Tests updated for the new behaviour: the two that asserted
      `run_pipeline()` *rejects* non-micromamba backends now assert it
      executes through them, plus a new test that a genuinely missing
      environment is still reported as missing (the half of the old test
      that still matters).

Verified end-to-end against a real `rattlerthis`-backed environment:
`run()` and `run_bin()` execute with the backend's activation variables
reaching the child (`CONDA_PREFIX` set), `run_bin(activate = FALSE)`
correctly omits them, `timeout` kills and reports `status = -9` with
`timeout = TRUE`, non-zero exits raise `condathis_run_status_error` under
`error = "cancel"` and report `status` under `"continue"`, and the
writable-stdin path round-trips input.

## Milestone: `rattlerthis` as a conforming backend (not started, depends on above)

- [ ] `rattlerthis::R/condathis-backend.R`'s `new_backend_rattler()` needs
      to actually populate its vtable with its own 10 already-written
      adapter functions (today it returns `structure(list(), class = ...)`
      — an **empty** list) so `condathis::register_backend("rattler", ...)`
      has something to validate and register. This is now the concrete,
      mechanical shape of that change (see the "one mechanical gap" note
      above) — not a rewrite of the adapter functions themselves, which
      are already correct.
- [ ] `.onLoad()` registration guarded by
      `requireNamespace("condathis", quietly = TRUE)` — confirmed this
      doesn't exist yet; `rattlerthis/R/rattlerthis-package.R` is still the
      bare roxygen template with no `.onLoad()` at all.
- [ ] The `backend_resolve_run()`-based execution branch in `run()`/
      `run_bin()`/`run_pipeline()` (see "deliberately not done" above) —
      needed before `method = "rattler"` can actually run anything, not
      just create/list/remove environments.
- [ ] `condathis::create_env(..., method = "rattler")` end-to-end smoke
      test exercising a real `rattlerthis`-backed environment through
      `condathis`'s own `run()` (proves `backend_resolve_run()` correctly
      hands off to `rattlerthis`'s own activation env vars). Reasonable to
      keep this in `rattlerthis`'s own test suite rather than `condathis`'s
      (cleaner ownership — `condathis`'s own CI shouldn't need a Rust
      toolchain), `skip_if_not_installed("rattlerthis")`-gated either way.
- [ ] Document in both packages' READMEs how the two relate now.

## Later ideas (not scheduled)

- Container backend package (`docker`/`singularity`) implementing the same
  10 generics — PLAN.md decision 9 sketches what it would need, but no
  package exists yet and none is planned as part of this milestone.
- `backend_available()`-driven diagnostics, e.g. a
  `condathis::backend_status()` user-facing function listing every
  registered backend and whether it's currently usable.
