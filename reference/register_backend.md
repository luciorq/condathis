# Register a condathis backend

Adds a backend: the engine that creates Conda environments and runs
commands in them. `condathis` has one built-in backend, `"micromamba"`.
Another package can provide a backend and register it from its
`.onLoad()` (see *Registering from a backend package*). The backend's
name is then a valid `method` value of every `condathis` function that
takes `method`, and `method = "auto"` can select it.

## Usage

``` r
register_backend(name, backend, call = rlang::caller_env())
```

## Arguments

- name:

  Character string, the backend name that users pass as `method`. It
  must start with a letter, contain only letters, digits, `.`, `_` and
  `-`, and not end with `.`. It must not be a Windows device name, such
  as `"nul"`, `"con"` or `"com1"`, with or without an extension.
  Reserved, in any case: `"auto"`, `"native"` and `"micromamba"`, the
  names of the entries of the condathis data directory (`"envs"`,
  `"pkgs"`, `"micromamba"`, `"condabin"`, `"Scripts"`,
  `"condathis-micromamba.yaml"`, `"cache"`, `"home"`, `"channels"` and
  `"locks"`), and `"tmp"`, `"bin"`, `"lib"`, `"etc"` and `"conda-meta"`.
  `register_backend()` also refuses a name when the condathis data
  directory has an entry of that name that is not a directory. It also
  refuses a name that differs only in case from a registered backend
  name or from the backend name of a package that `condathis` knows,
  such as `"rattler"`. On macOS and Windows, both would have the same
  root. Registering a name again replaces its backend.

- backend:

  The backend object: a list of the backend functions, with its own
  class. See *The backend object*.

- call:

  The environment reported as the caller in errors, for calls from
  another package's `.onLoad()`, as in rlang.

## Value

`name`, invisibly. Aborts with these classes:

- `condathis_backend_invalid_name`: a name that breaks the rules above.

- `condathis_backend_reserved_name` (also
  `condathis_backend_invalid_name`): a reserved name.

- `condathis_backend_root_conflict` (also
  `condathis_backend_invalid_name`): a name whose entry in the condathis
  data directory is not a directory.

- `condathis_backend_name_conflict` (also
  `condathis_backend_invalid_name`): a name that differs only in case
  from another backend name.

- `condathis_backend_class_conflict`: another registered name uses the
  same first class.

- `condathis_backend_contract_violation`: a backend object that breaks
  the contract. The error names the missing functions or arguments.

Every error also has the class `condathis_error`, and the name errors
have `condathis_invalid_arg`.

## Details

`backend` is a list of backend functions, with its own class: the three
required functions described below, and any of the optional ones.
`condathis` supplies a default for every optional function that the list
leaves out. `register_backend()` checks the list, then registers each
function as an S3 method of the `condathis` generic of the same name,
from inside the `condathis` namespace. The backend package needs no S3
registrations in its `NAMESPACE`.

## Lifecycle

This extension API is **experimental**. `condathis` 0.2.0 defines the
contract, designed together with a second backend package
(`rattlerthis`). The API may still change in breaking ways between `0.x`
releases. State the `condathis` version that you developed against, for
example as `condathis (>= 0.2.0)` in `Imports`.

## The backend object

Build the backend as:

    structure(
      list(<the functions>),
      class = c("condathis_backend_<name>", "condathis_backend")
    )

S3 dispatch keys on the first class, so it must be unique to the
backend. It must not be `"condathis_backend"`, `"default"`, `"list"` or
`"data.frame"`: methods for those classes would also catch objects that
are not this backend. The element names are the names of the functions
below. The object must have `backend_create_env`, `backend_install` and
`backend_resolve_run`. Each other function is optional: an element that
is missing or `NULL` gets the default of condathis. Each function must
accept every argument of its signature by name, or have a `...`
argument. `register_backend()` checks the class and the three required
functions. It checks that each other element of the contract is a
function or `NULL`. It also checks the rule of the next paragraph and
the arguments of the functions that are present. Extra elements are
ignored.

An object that has its own `backend_get_install_dir()` must also have
its own `backend_get_env_dir()`, `backend_list_envs()` and
`backend_env_exists()`. An object that has its own
`backend_get_env_dir()` must also have its own `backend_list_envs()` and
`backend_env_exists()`. Their defaults look for environments in
`<backend_root_dir(name)>/envs`, not where the backend keeps them.

## Roots

Each backend has a root, its data directory, which
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)
reports. The root of the `"micromamba"` backend is the condathis data
directory, `tools::R_user_dir("condathis", "data")`. The root of every
other backend is the directory of its name inside it,
[`backend_root_dir()`](https://luciorq.github.io/condathis/reference/backend_root_dir.md):
for example `<condathis data directory>/rattler`. So the root of a
backend can lie inside the root of micromamba. The names of the entries
of the condathis data directory are reserved (see `name`). Each backend
has its own environment directory, `<root>/envs`, and its own package
caches, and never uses those of another backend. `condathis` owns
`<root>/conda-pkgs` in the root of every backend (see *Child
processes*), so a backend must not use that name.
[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)
moves the condathis data directory, and with it every root that
[`backend_root_dir()`](https://luciorq.github.io/condathis/reference/backend_root_dir.md)
gives.

## What condathis passes

`condathis` passes `backend` first and every other argument by name. It
checks every value before it calls a backend function. `verbose` is
always one of the five strings, so the defaults of the signatures below
are never used. The values are:

- `backend`: the registered backend object.

- `env_name`: a valid environment name, as described for the `env_name`
  argument of
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).
  It is a single directory name, never a path.

- `packages`: a character vector of package match specs, such as
  `"python>=3.12"`, without `NA` or `""`. `backend_create_env()` gets
  `NULL` when the request has no packages: an empty environment, or one
  built from `env_file`. `backend_install()` gets `NULL` when it
  installs from `env_file`.

- `env_file`: `NULL`, or the absolute path of an existing environment
  file (or directory) from an
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md).
  When it is set, `packages` is `NULL`.

- `definition`: the
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md)
  object that `env_file` comes from, a list with `path` (the same path
  as `env_file`), `format` (`NULL` or a string) and `options` (a named
  list). It came after the first functions of version 2 of this
  contract, so it is not in the signatures below, and a function written
  without it keeps working. `condathis` passes it only to a function
  that has a `definition` argument (or `...`), and only when `env_file`
  is set. `condathis` never reads `format` or `options`: the backend
  does. A backend function without the argument gets only `env_file`.
  Then a definition with a `format` or `options` aborts before any call,
  with class `condathis_create_env_unsupported_definition` or
  `condathis_install_packages_unsupported_definition` (also
  `condathis_backend_unsupported`).

- `channels`: a non-empty character vector of channel names or URLs,
  without `NA` or `""`, in priority order.

- `additional_channels`: `NULL`, or a character vector like `channels`.
  These channels come after `channels`.

- `channel_priority`: `"strict"`, `"flexible"` or `"disabled"`.

- `platform`: `NULL`, or one known conda platform (subdir) name, such as
  `"linux-64"` or `"osx-arm64"` (see `platform` in
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)).
  It can still be a platform that the backend does not support. `NULL`
  means the native platform of the backend.

- `overwrite`: `TRUE` or `FALSE`.

- `verbose`: one of `"output"` (show the backend's output), `"silent"`
  (show nothing), `"cmd"` (show the command line), `"spinner"` (show
  only progress) or `"full"` (show everything, also the backend's own
  log). It is never a logical or a vector. The probes and listings that
  `condathis` uses to choose a backend get `"silent"`. `condathis`
  prints its own messages, such as "Environment x successfully
  created.", so the backend must not print them again.

- `cmd`: a single, non-empty string. `args`: a character vector.

- `base_env`: a named character vector, the environment of the command
  before activation (see `backend_resolve_run()`).

- `env_dir`: the absolute path of an existing directory with a
  `conda-meta` directory, in its real form (see
  `backend_resolve_run_in_dir()`).

- `timeout`: a positive number of seconds. It can also be `Inf` (no
  limit) for `backend_resolve_run()` and `backend_resolve_run_in_dir()`.

[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
and
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)
hold the lock of the environment name (see *Other R sessions* in
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)).
They hold it while they call `backend_create_env()`, `backend_install()`
or `backend_remove_env()`, and during the existence checks before them.
So no other R session that uses `condathis` changes the environment
meanwhile, with any backend. They also hold the lock of the package
caches, shared.
[`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
holds it exclusive while it calls `backend_clean_cache()`. So no create
or install of another R session runs while caches are deleted. A backend
needs no lock of its own against those sessions.

## Required functions

- `backend_create_env(backend, packages = NULL, env_file = NULL, env_name = "condathis-env", channels = "conda-forge", channel_priority = c("strict", "flexible", "disabled"), additional_channels = NULL, platform = NULL, overwrite = FALSE, verbose = c("output", "silent", "cmd", "spinner", "full"))`
  creates the environment. It can also take the optional argument
  `definition = NULL` (see *What condathis passes*). Its directory is
  the one that `backend_get_env_dir()` returns, and `condathis` calls it
  only when that directory does not exist. That is the case for a new
  environment. It is also the case with `overwrite = TRUE`, after
  `condathis` moved the existing environment aside or deleted a
  directory that was not an environment (one left by a failed create).
  When the call fails, `condathis` deletes what it left and moves the
  old environment back. A call fails also when it returns a non-zero
  `status` or an invalid `link_scripts_skipped` (see *Results*). So a
  misspelled spec with `overwrite = TRUE` does not cost the user the
  environment. `overwrite` tells the backend which of the two cases
  applies. With `env_file`, build the environment from that file (read
  `definition` for its `format` and `options`, when the function takes
  it). With `platform`, build it for that platform. The platform can be
  one that `condathis` chose because the request does not solve for the
  native platform of the backend (see `backend_can_solve()`). After a
  successful call, `condathis` writes
  `<env_dir>/.condathis/backend.json`. It uses this marker as a
  cross-check, and the marker records the platform when one was given or
  chosen.

  `condathis` moves aside or deletes only the directory  
  `<backend_get_install_dir()>/envs/<env_name>`. For a backend whose
  `backend_get_env_dir()` returns another directory,
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  cannot replace an existing environment, or delete a directory left by
  a failed create. It aborts with `condathis_create_env_failed`, whose
  parent has the class `condathis_unsafe_env_dir_move` or
  `condathis_unsafe_env_dir_delete`.

  `condathis` keeps the environment that it replaces in the directory  
  `<backend_get_install_dir()>/envs/#trash` until the backend succeeded.
  No environment can have that name, so `backend_list_envs()` must leave
  that directory out.

- `backend_install(backend, packages, env_name = "condathis-env", channels = "conda-forge", channel_priority = c("strict", "flexible", "disabled"), additional_channels = NULL, platform = NULL, verbose = c("output", "silent", "cmd", "spinner", "full"))`
  installs `packages` into the existing environment `env_name`, solving
  for `platform`. `condathis` passes the platform recorded for the
  environment: the one in its marker or its `.mambarc`. On Apple Silicon
  and on Windows, `condathis` can choose an emulated platform (see
  `backend_can_solve()`). There it also reads the platform of the
  package records of an environment without a recorded one. For an
  environment without packages of a platform, it passes the platform
  that it would choose for a new environment. Otherwise, `platform` is
  `NULL`. It must not create a missing environment.

  It can also take the optional arguments `env_file = NULL` and
  `definition = NULL`. With `env_file`, install the packages that the
  file requests, solved together with the packages of the environment,
  as `micromamba install -f` does.
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  passes a file only when `backend_describe_definition()` did not say
  that it is a lock (or that the backend cannot read it). A function
  that takes neither argument cannot install from a file, and
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  then aborts before any call with class
  `condathis_install_packages_unsupported_definition`. A function that
  takes `env_file` but not `definition` gets only the path, as
  `backend_create_env()` does.

- `backend_resolve_run(backend, cmd, args = character(0L), env_name = "condathis-env", verbose = "silent", base_env = NULL, timeout = Inf)`
  describes, without running `cmd`, how to run `cmd` with `args` in the
  activated environment. `base_env` is the environment that the command
  gets without activation: the session's environment with the changes of
  *Child processes*. Compute the activation against it, not against the
  environment of the R session. `condathis` always passes it. `timeout`
  is the number of seconds the function may take: what is left of the
  `timeout` of
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  or
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
  or `Inf`. If the function runs code to compute the activation, such as
  the `activate.d` scripts of the environment, that code can hang. The
  function should stop it when the time runs out, and signal an error.
  When the time ran out, `condathis` reports a timeout for the call
  (`timeout = TRUE`, status `-9`), whatever the function returned or
  signaled. It does not start the command. `timeout` is the one argument
  a function may leave out. Then `condathis` does not pass it, and can
  report the timeout only once the function returned. The function
  returns `list(command, args, env, dir)`:

  - `command`: a single string, the program to start: an absolute path,
    or a bare name. `condathis` starts a bare name the same way for
    every backend. On Linux and macOS, it is looked up on the `PATH` of
    the command, after `env` is applied. On Windows,
    [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
    [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
    look it up in the binary directories of the environment, with the
    extensions of `PATHEXT`. Otherwise, they leave it to `processx`,
    which searches the working directory and the `PATH` of the R session
    for `<name>.com` and `<name>.exe`.
    [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
    searches the binary directories of the environment and then the
    `PATH` of the command. A bare name that is found nowhere fails to
    start.

  - `args`: a character vector, or `NULL`. It replaces the user's
    arguments, so it must contain them.

  - `env`: `NULL`, or a named character vector (not a list) of
    activation variables. Each entry replaces the variable of the same
    name in the environment of the command, `PATH` included. An `NA`
    entry removes the variable, for a variable that the activation
    unsets.
    [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
    also prepends the environment's binary directories to `PATH`.

  - `dir`: `NULL` to keep R's working directory, or the path of an
    existing directory to run the command in.

  `condathis` calls it only with activation on
  ([`run()`](https://luciorq.github.io/condathis/reference/run.md), and
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  and
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  with `activate = TRUE`). It calls it only for an environment that this
  backend reported as existing. It never calls it for an
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  environment (see `backend_resolve_run_in_dir()`). A value that breaks
  these rules aborts with `condathis_backend_resolve_run_invalid`.

## Optional functions and their defaults

The defaults treat the environments of a backend as conda prefixes in
`<backend_root_dir(name)>/envs`. A directory there with
`conda-meta/history` is an environment, and the `conda-meta/*.json`
files are its package records.

- `backend_get_install_dir(backend)` returns the backend's root: the
  absolute path of an existing directory, in its real form
  ([`fs::path_real()`](https://fs.r-lib.org/reference/path_math.html)).
  Paths then compare equal where a temporary directory is a symbolic
  link (macOS). Create the directory when it is missing. Default:
  [`backend_root_dir()`](https://luciorq.github.io/condathis/reference/backend_root_dir.md),
  created when missing.

- `backend_get_env_dir(backend, env_name = "condathis-env")` returns the
  absolute path of the environment directory (its prefix): the directory
  that `backend_create_env()` creates. It returns the path also for an
  environment that does not exist yet, and it must not create anything.
  Default: `<backend_root_dir(name)>/envs/<env_name>`.

- `backend_list_envs(backend, verbose = "silent")` returns the names of
  this backend's environments: a character vector without `NA` or
  duplicates. Names of the vector are dropped. It returns `character(0)`
  when there are none, also when the backend's root does not exist yet.
  It is read only: it must not create anything, and it should not
  install or download anything. Default: the directories in
  `<root>/envs` that have `conda-meta/history`, without symbolic links
  and without directories whose real path is elsewhere, as
  `micromamba env list` reports them.

- `backend_env_exists(backend, env_name, verbose = "silent")` returns
  `TRUE` or `FALSE`: whether `env_name` is an environment of this
  backend. It must agree with `backend_list_envs()`. `condathis` calls
  it for every registered backend on every call that names an
  environment, whatever `method` is, to find the backend that owns the
  environment. So it must be cheap and must not create anything. Avoid
  processes and downloads. Report only the environments in this
  backend's own root: when two backends report the same name,
  `condathis` aborts with `condathis_backend_ambiguous_env` unless
  `method` names one of them. Default: `FALSE` when
  `<root>/envs/<env_name>` is not a directory, else whether
  `backend_list_envs()` lists `env_name` (a file system that ignores
  case opens the directory for every spelling).

- `backend_list_packages(backend, env_name = "condathis-env", verbose = "silent")`
  returns a data frame (a tibble is fine) with one row per installed
  package and at least these columns: `name`, `version`, `build_string`,
  `channel` and `platform` (character), and `build_number` (integer, or
  a double with whole numbers). `platform` is the subdir of the package,
  such as `"linux-64"` or `"noarch"`. Extra columns are kept. An empty
  environment gives zero rows with the same columns.
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  reads these columns to decide whether an existing environment already
  has the requested packages and was built for the requested platform.
  Default: the package records, with the columns of
  `micromamba list --json`, and the PyPI packages that pip or uv
  installed into the environment's python, as `micromamba list` lists
  them (channel `pypi`, and as `platform` a tag such as `linux-x86_64`).
  See
  [`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md).

- `backend_remove_env(backend, env_name = "condathis-env", verbose = c("output", "silent", "cmd", "spinner", "full"))`
  removes the environment and its directory. Default: deletes
  `conda-meta/history` first, so the environment leaves every listing at
  once. Then it moves the directory into `<root>/envs/#trash` and
  deletes it there. When a program uses one of its files (Windows), the
  directory cannot be moved. Then it deletes the files one by one, and
  moves each file in use into `#trash`, where a later call deletes it. A
  symbolic link is deleted, never followed. It does not run pre-unlink
  scripts, and reports the packages that have one (see *Results*). Like
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
  it deletes only the directory
  `<backend_get_install_dir()>/envs/<env_name>`. A backend whose
  `backend_get_env_dir()` returns another directory needs its own
  `backend_remove_env()`. Without it,
  [`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)
  aborts with `condathis_remove_env_failed`, whose parent has the class
  `condathis_unsafe_env_dir_delete`.

- `backend_available(backend)` returns `TRUE` or `FALSE`: whether the
  backend can create environments on this system now. It must be cheap.
  It only decides which backend `method = "auto"` picks for a new
  environment. `condathis` still lists, finds and uses the existing
  environments of an unavailable backend. Default: `TRUE`.

- `backend_clean_cache(backend, verbose = c("output", "silent", "cmd", "spinner", "full"))`
  deletes the package caches and the metadata caches of the backend, and
  nothing else. It returns `NULL` when there was nothing to clean, or a
  result list (see *Results*).
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  calls it for every registered backend, also after the function of
  another backend failed, and then deletes `<root>/conda-pkgs` itself.
  Default: `NULL`.

- `backend_quiesce(backend, timeout = 30)` waits until no work of the
  backend runs in the R process any more, at most `timeout` seconds, and
  returns `TRUE` (invisibly), or `FALSE` with a warning when the time
  ran out. `condathis` calls it before
  [`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)
  and
  [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  delete directories. An error from it, or a value other than `TRUE` or
  `FALSE`, becomes a warning of class
  `condathis_backend_quiesce_failed`, and `condathis` goes on. A backend
  that only starts processes has nothing to wait for. Default: `TRUE`.

- `backend_native_platform(backend)` returns the platform (subdir) that
  the backend solves for when it gets no `platform`, such as
  `"osx-arm64"`, or `NA` when it cannot tell. Default: `NA`.

- `backend_can_solve(backend, packages = NULL, env_file = NULL, channels = "conda-forge", channel_priority = c("strict", "flexible", "disabled"), additional_channels = NULL, platform)`
  returns `TRUE` when the request solves for `platform`, `FALSE` when it
  does not, and `NA` when it cannot tell, for example without network
  access or for a missing channel. It must not create an environment.
  `condathis` asks it when it chooses the platform of a new environment.
  A request that does not solve for the native platform uses an emulated
  one when it solves there: `"osx-64"` on Apple Silicon with Rosetta 2,
  and `"win-64"` on Windows on ARM. An error counts as `NA`. Default:
  `NA`, so `condathis` never chooses an emulated platform. `condathis`
  never asks it about a lock (see `backend_describe_definition()`). It
  can also take the optional argument `definition = NULL`.

- `backend_describe_definition(backend, definition, platform = NULL)`
  tells `condathis` what the backend makes of an
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md):
  whether it reads it, and whether it is a request or a lock. `platform`
  is the `platform` of
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  calls it before it locks, moves or creates anything, so it must be
  cheap: read the file, but do not download, install or solve anything,
  and do not change any environment. It returns a list:

  - `supported`: `TRUE` (the backend reads it), `FALSE` (it does not) or
    `NA` (it cannot tell). `FALSE` aborts with class
    `condathis_create_env_unsupported_definition` (also
    `condathis_backend_unsupported`), with `reason` in the message.
    Refuse an option of `definition$options` that you do not understand:
    never ignore it.

  - `format`: `NA`, or the name of the format that the backend detected
    or was given, such as `"conda-lock-v1"`.

  - `kind`: `"request"` (the backend solves it, as package specs),
    `"lock"` (it installs exact packages, without a solve) or `NA`.

  - `platforms`: `NULL`, or the platforms that a lock has packages for.

  - `reason`: `NA`, or one sentence: why `supported` is `FALSE`.

  - `records`: `NULL`, or for a lock a data frame with the character
    columns `name`, `version`, `build_string` and `platform` (the
    platform the record is for), one row per package that the backend
    installs from it.

  For a request, `condathis` goes on as for package specs: it asks
  `backend_can_solve()` about the platform. For a lock, it picks the
  platform from `platforms` and never calls `backend_can_solve()`, since
  a dry run says nothing about a lock. It aborts when `channels`,
  `additional_channels` or `channel_priority` were given with an
  [`env_definition()`](https://luciorq.github.io/condathis/reference/env_definition.md)
  (the deprecated `env_file` of
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  passes them on, as in 0.1.4). Records of `noarch` packages install on
  any platform: leave `noarch` out of `platforms`. When `records` has
  rows for the platform and the new environment has no package, the
  create fails with `condathis_create_env_failed`. With `NA` as `kind`,
  `condathis` passes the file on and makes no other check, as for every
  backend before this function existed. An error counts as `NA`.

  `records` also lets `condathis` compare an existing environment with a
  lock: `create_env(overwrite = FALSE)` keeps the environment when its
  packages are exactly the records for the platform, and
  [`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md)
  gives `TRUE`. Records with `NA` in `name`, `version` or `build_string`
  are not compared.
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  calls this function too, and installs from a request only.

  With `method = "auto"`, a new environment from a definition goes to
  the first available backend in `condathis.backend_priority` order
  whose `supported` is not `FALSE`. Default: `NA`, or `FALSE` when the
  definition has a `format` or `options` and `backend_create_env()` has
  no `definition` argument.

- `backend_definition_formats(backend)` returns the names of the formats
  that the backend reads, as a character vector, such as
  `c("environment-yaml", "explicit")`. It is used only in messages: an
  error for a definition with a `format` names the registered backends
  that list it. `condathis` never decides from it. Default:
  `character(0)`.

- `backend_resolve_run_in_dir(backend, cmd, args = character(0L), env_dir, verbose = "silent", base_env = NULL, timeout = Inf)`
  describes how to run `cmd` with `args` in the activated environment
  whose directory (its prefix) is `env_dir`. This is an environment
  given by
  [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
  which `condathis` did not create and which may belong to no backend,
  such as one made by conda or mamba elsewhere. It returns
  `list(command, args, env, dir)` with the rules of
  `backend_resolve_run()` (also for `base_env` and `timeout`).
  `condathis` treats the value the same way, also when it breaks them.
  It must not change, lock or register the environment. `condathis`
  calls it with activation on, after it checked that `env_dir` exists
  and has a `conda-meta` directory. It calls it only when the backend
  object has this function. For a backend without it,
  [`run()`](https://luciorq.github.io/condathis/reference/run.md),
  [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  and
  [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  abort with class `condathis_env_path_unsupported_method` (also
  `condathis_backend_unsupported`) when `method` names that backend.
  `method = "auto"` uses the first backend in the order of the option
  `condathis.backend_priority` that has it (micromamba by default).
  Default: aborts with class `condathis_backend_unsupported`.

Every value is checked: a return value that breaks these rules aborts
with `condathis_backend_invalid_return` (also
`condathis_backend_contract_violation`), naming the backend.

## Results

`backend_create_env()`, `backend_install()`, `backend_remove_env()` and
`backend_clean_cache()` may return `NULL` or a list. `condathis` copies
the elements `status`, `stdout`, `stderr`, `timeout`, `pid` and `cmd`
when present (exact names) and ignores everything else. Any other value
counts as an empty list. A non-zero `status` without an error counts as
a failure. `cmd` is reported as the command line that ran, so give the
exact command line, or leave it out. `condathis` shows the password and
the token of a URL in it as `*****`, as micromamba does. Hide them the
same way in what the backend prints and in its errors.

The element `link_scripts_skipped` of the results of
`backend_create_env()`, `backend_install()` and `backend_remove_env()`,
when present, is a data frame with the character columns `package` and
`script` (`"pre-link"`, `"post-link"` or `"pre-unlink"`). It holds the
link scripts of packages that the backend did not run. `condathis` then
warns with class `condathis_link_scripts_skipped` after the call
succeeded, naming the packages (see
[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)).
A backend that runs every link script, as micromamba does, leaves the
element out. Any other value aborts with
`condathis_backend_invalid_return`.

## Missing environments

`condathis` checks with `backend_env_exists()` that an environment
exists before it calls `backend_install()`, `backend_remove_env()`,
`backend_list_packages()` and `backend_resolve_run()`. A missing
environment aborts with class `condathis_env_not_found` before the
backend is called. So these functions do not get a missing environment
from `condathis`, except when `backend_env_exists()` failed. Then
`condathis` calls them anyway, and they must signal an error for a
missing environment. Give that error the class
`condathis_env_not_found`. `condathis` keeps the `condathis_*` classes
of a backend error when it re-raises it, so one handler catches a
missing environment on both sides. None of them may create an
environment.

Only [`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md),
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
and
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
create a missing environment, and only the default `"condathis-env"`:
they call `backend_create_env()` for an empty environment first.

For a missing environment, `backend_env_exists()` returns `FALSE`,
`backend_list_envs()` leaves the name out, and `backend_get_env_dir()`
returns the path anyway. None of them signals an error for it.

## Errors

Signal an error of any class when an operation fails. `condathis`
re-raises it with your error as the parent, and with these classes:

- `condathis_<function>_failed`, for example
  `condathis_create_env_failed`.

- `condathis_backend_error`.

- Every `condathis_*` class of your error.

Handlers still find your own classes with
[`rlang::cnd_inherits()`](https://rlang.r-lib.org/reference/cnd_inherits.html).

When you cannot honor an argument, such as `env_file` or
`channel_priority = "flexible"`, also give your condition the class
`condathis_backend_unsupported`.

Do not give your own conditions the class `condathis_backend_error`:
`condathis` adds it when it re-raises your error. An error that has it
anyway is re-raised like any other error.

An error from `backend_env_exists()` means "cannot tell", never
"absent". A call that would change the environment then aborts with
`condathis_backend_probe_failed`. A query warns with
`condathis_backend_query_failed` and skips the backend.

See
[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for every class.

## Channels

Search only the channels in `channels` and `additional_channels`, in
that order, and no default channels. `channel_priority` has its Conda
meaning. The `channel` column of `backend_list_packages()` is the
channel name, as micromamba reports it (for example `"conda-forge"`), or
the channel URL. `condathis` compares
`https://conda.anaconda.org/<name>` equal to `<name>`, and drops
credentials (`user:password@`, `/t/<token>`) and a platform
subdirectory. It compares a `file://` channel by its absolute path.

## Child processes

`condathis` starts `command` with a copy of the session's environment in
which the `CONDA_*` and `MAMBA_*` variables listed in
[condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)
are cleared. It then applies `env`. For commands of every backend other
than `"micromamba"`, `CONDA_ENVS_PATH` is the parent directory of the
environment directory from `backend_get_env_dir()`, so a Conda tool run
in the environment creates named environments next to it.
`CONDA_PKGS_DIRS` and `MAMBA_PKGS_DIRS` are `<root>/conda-pkgs` for them
when that parent directory is `<root>/envs`, and `""` otherwise. A Conda
tool run in the environment keeps its package cache in the backend's
root, never in the user's home directory or in the cache of another
backend.
[`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
empties it. For an environment given by
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
they have the values of the backend's own environments (those of
`"condathis-env"`), not of the directory that holds it. The
`"micromamba"` backend sets these variables to the `envs/` and `pkgs/`
directories of its own root. A backend whose commands need other values
returns them in `env`.

## Registering from a backend package

Put `condathis` in `Imports`, so it is loaded before your package, and
register from your package's `.onLoad()`. Also register from a hook on
the `condathis` load event. The registry lives in the `condathis`
namespace, so a registration is lost when `condathis` is unloaded and
loaded again, as during development with
[`pkgload::load_all()`](https://pkgload.r-lib.org/reference/load_all.html).
The hook registers the backend on every later load of `condathis`. The
hook list belongs to base R and outlives your package, so `.onUnload()`
must remove the hook. Otherwise, the next load of `condathis` registers
the functions of an unloaded namespace.

    register_mybackend <- function(...) {
      condathis::register_backend("mybackend", new_backend_mybackend())
    }

    .onLoad <- function(libname, pkgname) {
      register_mybackend()
      setHook(packageEvent("condathis", "onLoad"), register_mybackend)
      invisible(NULL)
    }

    .onUnload <- function(libpath) {
      hook <- packageEvent("condathis", "onLoad")
      setHook(
        hook,
        Filter(function(h) !identical(h, register_mybackend), getHook(hook)),
        action = "replace"
      )
      if (isNamespaceLoaded("condathis")) {
        condathis::unregister_backend("mybackend")
      }
      invisible(NULL)
    }

`register_mybackend()` must be a function at the top level of your
package, so that [`identical()`](https://rdrr.io/r/base/identical.html)
finds it. A function created inside `.onLoad()` is a new object every
time. Call `condathis` functions with `condathis::` instead of importing
them in your `NAMESPACE`. After a reload of `condathis`, imported copies
would be the functions of the old namespace.

`register_backend()` validates the backend, so after a `condathis`
upgrade that changes the contract, the call in `.onLoad()` fails and
your package does not load. The error names what to change. R runs the
hook under [`try()`](https://rdrr.io/r/base/try.html), so a failing hook
only prints its error and `condathis` still loads.

`condathis` knows some backend packages by name: `rattlerthis` provides
the backend `"rattler"`. `condathis` loads such a package when it is
installed and one of these holds:

- `method` names its backend.

- Its backend has environments (a directory in
  `<backend_root_dir(name)>/envs`), so that `method = "auto"` finds them
  without a call to [`library()`](https://rdrr.io/r/base/library.html).

- The option `condathis.backend_priority` names its backend, and
  `method = "auto"` chooses the backend of a new environment.

`condathis` does not depend on these packages. When such a package is
not installed, or fails to load, a `method` that names its backend
aborts with class `condathis_backend_not_installed` or
`condathis_backend_load_failed`. A change to one of its environments
aborts the same way. The queries skip its environments with a warning of
the same class (see
[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)).
The package must register its backend from its `.onLoad()`. A package
that loads without registering it counts as failed.

## See also

[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
for the condition classes, and
[condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)
for the variables of child processes.

Other backends:
[`backend_root_dir()`](https://luciorq.github.io/condathis/reference/backend_root_dir.md),
[`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md),
[`unregister_backend()`](https://luciorq.github.io/condathis/reference/unregister_backend.md)

## Examples

``` r
# A minimal backend: the three required functions, which this example
# does not implement. It reports that it is unavailable, so
# `method = "auto"` never selects it. condathis supplies the other
# functions: they look for environments in
# `backend_root_dir("mybackend")/envs`. A backend package builds this
# object in its own constructor, for example `new_backend_mybackend()` in
# *Registering from a backend package* of `?register_backend`.
not_implemented <- function(...) {
  stop("Not implemented by this example backend.")
}
mybackend <- structure(
  list(
    backend_create_env = not_implemented,
    backend_install = not_implemented,
    backend_resolve_run = not_implemented,
    backend_available = function(backend) FALSE
  ),
  class = c("condathis_backend_mybackend", "condathis_backend")
)

condathis::register_backend("mybackend", mybackend)
condathis::list_registered_backend_names()
#> [1] "micromamba" "mybackend" 

condathis::unregister_backend("mybackend")
condathis::list_registered_backend_names()
#> [1] "micromamba"
```
