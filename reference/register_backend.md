# Register a condathis backend implementation

The extension point for packages that provide an alternative execution
engine for `condathis` (e.g. an in-process `rattler`-based solver, or a
container-based engine). Once registered, the backend becomes selectable
through the `method` argument of every environment-management function
([`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
...), and participates in `method = "auto"` resolution.

## Usage

``` r
register_backend(name, backend, call = rlang::caller_env())
```

## Arguments

- name:

  Character string identifying this backend (e.g. `"micromamba"`,
  `"rattler"`). This is the value users pass as `method =`.
  Re-registering an existing name overwrites it.

- backend:

  A classed, named list of the 10 contract functions - see *The backend
  contract* below.

- call:

  Calling environment reported in error conditions. Defaults to the
  caller's environment.

## Value

`name`, invisibly. Signals a condition of class
`condathis_backend_contract_violation` (naming exactly which contract
functions are missing) if the vtable is incomplete.

## Details

`backend` is a classed, named list (a "vtable"), not an S3 object with
methods already attached: its element names must be exactly the 10
contract function names listed below, each a function implementing that
part of the contract. `register_backend()` validates the vtable is
complete, then registers each entry for S3 dispatch from inside
`condathis`'s own namespace - the backend package does not need to
`Imports`/`Depends` on `condathis` or register anything in its own
`NAMESPACE`.

## Lifecycle

This extension API is **experimental**. The backend contract (the
required functions, their signatures, and their return-value
expectations) has not yet been validated by a second, real backend
package shipping against it, and may change in breaking ways between
`0.x` releases as the first external backends are wired in. Backend
authors should declare the specific `condathis` version they were
developed against and expect to track contract changes until this notice
is removed.

## The backend contract

`backend` must be built as
`structure(list(<the 10 functions>), class = c("condathis_backend_<name>", "condathis_backend"))`

- the first class is what S3 dispatch keys on, so it must be unique to
  this backend. The 10 required element names are:

&nbsp;

- `backend_create_env(backend, packages, env_file, env_name, channels, channel_priority, additional_channels, platform, overwrite, verbose)`

- `backend_install(backend, packages, env_name, channels, channel_priority, additional_channels, verbose)`

- `backend_remove_env(backend, env_name, verbose)`

- `backend_list_envs(backend, verbose)` - returns a bare character
  vector of environment names.

- `backend_env_exists(backend, env_name, verbose)` - returns a single
  logical.

- `backend_list_packages(backend, env_name, verbose)` - returns a data
  frame with at least `name`, `version`, `build_number`, and `channel`
  columns; extra backend-specific columns are allowed.

- `backend_get_env_dir(backend, env_name)` - returns the environment's
  directory path.

- `backend_get_install_dir(backend)` - returns the backend's own install
  root. Each backend must use its own separate root: directory placement
  under that root is how `condathis` determines which backend owns an
  existing environment.

- `backend_resolve_run(backend, cmd, args, env_name, verbose)` - returns
  `list(command, args, env, dir)` describing how to execute `cmd` inside
  `env_name`.

- `backend_available(backend)` - returns a single logical; gates
  `method = "auto"` selection for *new* environments.

Creation/installation/removal functions signal an error condition on
failure; their return values are not otherwise inspected. `condathis`
builds its own user-facing result objects.

## Registering from a backend package

Register from your package's `.onLoad()`, and *also* hook `condathis`'s
own load event: the registry lives inside `condathis`'s namespace, so if
`condathis` is ever unloaded and reloaded after your package registered,
the registration would silently be lost without the hook. The combined
pattern covers both load orders:

    .onLoad <- function(libname, pkgname) {
      register_self <- function(...) {
        condathis::register_backend("mybackend", new_backend_mybackend())
      }
      if (requireNamespace("condathis", quietly = TRUE)) {
        register_self()
      }
      setHook(packageEvent("condathis", "onLoad"), register_self)
      invisible(NULL)
    }

    .onUnload <- function(libpath) {
      if (isNamespaceLoaded("condathis")) {
        condathis::unregister_backend("mybackend")
      }
    }

## See also

[`unregister_backend()`](https://luciorq.github.io/condathis/reference/unregister_backend.md),
[`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# Inside a backend package's .onLoad() (see the registration section
# for the full, load-order-safe pattern):
condathis::register_backend("mybackend", new_backend_mybackend())
} # }
```
