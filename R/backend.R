#' Registry of registered backends
#'
#' A package-level environment (not a list) so `register_backend()` can
#' mutate it in place without `<<-` or a mutable global list.
#'
#' @keywords internal
#' @noRd
backend_registry <- new.env(parent = emptyenv())

#' The generics a backend object must implement
#'
#' @keywords internal
#' @noRd
backend_required_hooks <- c(
  "backend_create_env",
  "backend_install",
  "backend_resolve_run"
)

#' The generics a backend object may implement
#'
#' For each one that a backend object leaves out, or sets to `NULL`, S3
#' dispatch reaches the default method of condathis
#' (`backend_<x>.default`, in `backend-defaults.R`).
#'
#' @keywords internal
#' @noRd
backend_optional_hooks <- c(
  "backend_get_install_dir",
  "backend_get_env_dir",
  "backend_list_envs",
  "backend_env_exists",
  "backend_list_packages",
  "backend_remove_env",
  "backend_available",
  "backend_clean_cache",
  "backend_quiesce",
  "backend_native_platform",
  "backend_can_solve",
  "backend_resolve_run_in_dir",
  "backend_describe_definition",
  "backend_definition_formats"
)

#' Every generic of the backend contract
#'
#' @keywords internal
#' @noRd
backend_contract_names <- c(backend_required_hooks, backend_optional_hooks)

#' The generics that must come with an own `backend_get_install_dir()`
#'
#' Their defaults look in `backend_root_dir(<name>)`, so a backend that
#' keeps its environments in another root must implement them too.
#'
#' @keywords internal
#' @noRd
backend_root_hooks <- c(
  "backend_get_env_dir",
  "backend_list_envs",
  "backend_env_exists"
)

#' The generics that must come with an own `backend_get_env_dir()`
#'
#' Their defaults look for environments in `<backend_root_dir(<name>)>/envs`,
#' so a backend that puts them elsewhere would never find its own
#' environments: `create_env()` succeeded, `list_envs()` was then empty,
#' and a second `create_env()` refused to delete the environment as a
#' directory that is not one.
#'
#' @keywords internal
#' @noRd
backend_env_dir_hooks <- c(
  "backend_list_envs",
  "backend_env_exists"
)

#' The entries directly under the condathis data directory
#'
#' The root of the `"micromamba"` backend is the condathis data directory,
#' and the root of every other backend is the directory of its name inside
#' it (see `backend_root_dir()`). A backend named after one of these
#' entries would get one of micromamba's directories as its root. On
#' Windows, micromamba writes `condabin/` and `Scripts/activate.bat` there.
#'
#' @keywords internal
#' @noRd
condathis_root_entries <- c(
  "envs",
  "pkgs",
  "micromamba",
  "condabin",
  "Scripts",
  "condathis-micromamba.yaml",
  "cache",
  "home",
  "channels",
  "locks"
)

#' Windows device names
#'
#' Windows opens a device, not a file or directory, for each of these
#' names, also with an extension (`nul.txt`), so none can be the directory
#' of a backend's root. Compared case-insensitively.
#'
#' @keywords internal
#' @noRd
windows_device_names <- c(
  "con",
  "prn",
  "aux",
  "nul",
  paste0("com", 0:9),
  paste0("lpt", 0:9)
)

#' Backend names that `register_backend()` refuses
#'
#' `"auto"` and `"native"` are `method` values with their own meaning, and
#' `"micromamba"` is the built-in backend, registered by `.onLoad()`. The
#' entries of the condathis data directory, and generic directory names
#' that micromamba or a later condathis may create there, are reserved
#' too. Compared case-insensitively.
#'
#' @keywords internal
#' @noRd
reserved_backend_names <- unique(c(
  "auto",
  "native",
  "micromamba",
  condathis_root_entries,
  "tmp",
  "bin",
  "lib",
  "etc",
  "conda-meta"
))

#' Classes that a backend object must not have as its first class
#'
#' `register_backend()` registers the backend's functions as S3 methods for
#' its first class. Methods for `"default"` would catch every object, and
#' methods for `"condathis_backend"`, `"list"` or `"data.frame"` would catch
#' every other backend or any plain list passed to a generic.
#'
#' @keywords internal
#' @noRd
shared_backend_first_classes <- c(
  "condathis_backend",
  "default",
  "list",
  "data.frame"
)

#' Register a condathis backend
#'
#' Adds a backend: the engine that creates Conda environments and runs
#' commands in them. `condathis` has one built-in backend, `"micromamba"`.
#' Another package can provide a backend and register it from its
#' `.onLoad()` (see *Registering from a backend package*). The backend's
#' name is then a valid `method` value of every `condathis` function that
#' takes `method`, and `method = "auto"` can select it.
#'
#' `backend` is a list of backend functions, with its own class: the three
#' required functions described below, and any of the optional ones.
#' `condathis` supplies a default for every optional function that the list
#' leaves out. `register_backend()` checks the list, then registers each
#' function as an S3 method of the `condathis` generic of the same name,
#' from inside the `condathis` namespace. The backend package needs no S3
#' registrations in its `NAMESPACE`.
#'
#' @section Lifecycle:
#' This extension API is **experimental**. `condathis` 0.2.0 defines the
#' contract, designed together with a second backend package
#' (`rattlerthis`). The API may still change in breaking ways between
#' `0.x` releases. State the `condathis` version that you developed
#' against, for example as `condathis (>= 0.2.0)` in `Imports`.
#'
#' @section The backend object:
#' Build the backend as:
#'
#' ```r
#' structure(
#'   list(<the functions>),
#'   class = c("condathis_backend_<name>", "condathis_backend")
#' )
#' ```
#'
#' S3 dispatch keys on the first class, so it must be unique to the
#' backend. It must not be `"condathis_backend"`, `"default"`, `"list"` or
#' `"data.frame"`: methods for those classes would also catch objects that
#' are not this backend. The element names are the names of the functions
#' below. The object must have `backend_create_env`, `backend_install` and
#' `backend_resolve_run`. Each other function is optional: an element that
#' is missing or `NULL` gets the default of condathis. Each function must
#' accept every argument of its signature by name, or have a `...`
#' argument. `register_backend()` checks the class and the three required
#' functions. It checks that each other element of the contract is a
#' function or `NULL`. It also checks the rule of the next paragraph and
#' the arguments of the functions that are present. Extra elements are
#' ignored.
#'
#' An object that has its own `backend_get_install_dir()` must also have
#' its own `backend_get_env_dir()`, `backend_list_envs()` and
#' `backend_env_exists()`. An object that has its own
#' `backend_get_env_dir()` must also have its own `backend_list_envs()` and
#' `backend_env_exists()`. Their defaults look for environments in
#' `<backend_root_dir(name)>/envs`, not where the backend keeps them.
#'
#' @section Roots:
#' Each backend has a root, its data directory, which [get_install_dir()]
#' reports. The root of the `"micromamba"` backend is the condathis data
#' directory, `tools::R_user_dir("condathis", "data")`. The root of every
#' other backend is the directory of its name inside it,
#' [backend_root_dir()]: for example `<condathis data directory>/rattler`.
#' So the root of a backend can lie inside the root of micromamba. The
#' names of the entries of the condathis data directory are reserved (see
#' `name`). Each backend has its own environment directory, `<root>/envs`,
#' and its own package caches, and never uses those of another backend.
#' `condathis` owns `<root>/conda-pkgs` in the root of every backend (see
#' *Child processes*), so a backend must not use that name.
#' [with_sandbox_dir()] moves the condathis data directory, and with it
#' every root that [backend_root_dir()] gives.
#'
#' @section What condathis passes:
#' `condathis` passes `backend` first and every other argument by name. It
#' checks every value before it calls a backend function. `verbose` is
#' always one of the five strings, so the defaults of the signatures below
#' are never used. The values are:
#'
#' * `backend`: the registered backend object.
#' * `env_name`: a valid environment name, as described for the `env_name`
#'   argument of [create_env()]. It is a single directory name, never a
#'   path.
#' * `packages`: a character vector of package match specs, such as
#'   `"python>=3.12"`, without `NA` or `""`. `backend_create_env()` gets
#'   `NULL` when the request has no packages: an empty environment, or one
#'   built from `env_file`. `backend_install()` gets `NULL` when it
#'   installs from `env_file`.
#' * `env_file`: `NULL`, or the absolute path of an existing environment
#'   file (or directory) from an [env_definition()]. When it is set,
#'   `packages` is `NULL`.
#' * `definition`: the [env_definition()] object that `env_file` comes
#'   from, a list with `path` (the same path as `env_file`), `format`
#'   (`NULL` or a string) and `options` (a named list). It came after the
#'   first functions of version 2 of this contract, so it is not in the
#'   signatures below, and a function written without it keeps working.
#'   `condathis` passes it only to a function that has a `definition`
#'   argument (or `...`), and only when `env_file` is set. `condathis` never reads `format` or
#'   `options`: the backend does. A backend function without the argument
#'   gets only `env_file`. Then a definition with a `format` or `options`
#'   aborts before any call, with class
#'   `condathis_create_env_unsupported_definition` or
#'   `condathis_install_packages_unsupported_definition` (also
#'   `condathis_backend_unsupported`).
#' * `channels`: a non-empty character vector of channel names or URLs,
#'   without `NA` or `""`, in priority order.
#' * `additional_channels`: `NULL`, or a character vector like `channels`.
#'   These channels come after `channels`.
#' * `channel_priority`: `"strict"`, `"flexible"` or `"disabled"`.
#' * `platform`: `NULL`, or one known conda platform (subdir) name, such as
#'   `"linux-64"` or `"osx-arm64"` (see `platform` in [create_env()]). It
#'   can still be a platform that the backend does not support. `NULL`
#'   means the native platform of the backend.
#' * `overwrite`: `TRUE` or `FALSE`.
#' * `verbose`: one of `"output"` (show the backend's output), `"silent"`
#'   (show nothing), `"cmd"` (show the command line), `"spinner"` (show
#'   only progress) or `"full"` (show everything, also the backend's own
#'   log). It is never a logical or a vector. The probes and listings that
#'   `condathis` uses to choose a backend get `"silent"`. `condathis` prints
#'   its own messages, such as "Environment x successfully created.", so the
#'   backend must not print them again.
#' * `cmd`: a single, non-empty string. `args`: a character vector.
#' * `base_env`: a named character vector, the environment of the command
#'   before activation (see `backend_resolve_run()`).
#' * `env_dir`: the absolute path of an existing directory with a
#'   `conda-meta` directory, in its real form (see
#'   `backend_resolve_run_in_dir()`).
#' * `timeout`: a positive number of seconds. It can also be `Inf` (no
#'   limit) for `backend_resolve_run()` and `backend_resolve_run_in_dir()`.
#'
#' [create_env()], [install_packages()] and [remove_env()] hold the lock of
#' the environment name (see *Other R sessions* in [create_env()]). They
#' hold it while they call `backend_create_env()`, `backend_install()` or
#' `backend_remove_env()`, and during the existence checks before them. So
#' no other R session that uses `condathis` changes the environment
#' meanwhile, with any backend. They also hold the lock of the package
#' caches, shared. [clean_cache()] holds it exclusive while it calls
#' `backend_clean_cache()`. So no create or install of another R session
#' runs while caches are deleted. A backend needs no lock of its own
#' against those sessions.
#'
#' @section Required functions:
#' * `backend_create_env(backend, packages = NULL, env_file = NULL,
#'   env_name = "condathis-env", channels = "conda-forge",
#'   channel_priority = c("strict", "flexible", "disabled"),
#'   additional_channels = NULL, platform = NULL, overwrite = FALSE,
#'   verbose = c("output", "silent", "cmd", "spinner", "full"))` creates
#'   the environment. It can also take the optional argument
#'   `definition = NULL` (see *What condathis passes*). Its directory is
#'   the one that `backend_get_env_dir()` returns, and `condathis` calls it
#'   only when that directory does not exist. That is the case for a new
#'   environment. It is also the case with
#'   `overwrite = TRUE`, after `condathis` moved the existing environment
#'   aside or deleted a directory that was not an environment (one left by
#'   a failed create). When the call fails, `condathis` deletes what it left
#'   and moves the old environment back. A call fails also when it returns a
#'   non-zero `status` or an invalid `link_scripts_skipped` (see *Results*).
#'   So a misspelled spec with `overwrite = TRUE` does not cost the user the
#'   environment. `overwrite` tells the backend which of the two cases
#'   applies. With `env_file`, build the environment from that file (read
#'   `definition` for its `format` and `options`, when the function takes
#'   it). With
#'   `platform`, build it for that platform. The platform can be one that
#'   `condathis` chose because the request does not solve for the native
#'   platform of the backend (see `backend_can_solve()`). After a successful
#'   call, `condathis` writes `<env_dir>/.condathis/backend.json`. It uses
#'   this marker as a cross-check, and the marker records the platform when
#'   one was given or chosen.
#'
#'   `condathis` moves aside or deletes only the directory\cr
#'   `<backend_get_install_dir()>/envs/<env_name>`. For a backend whose
#'   `backend_get_env_dir()` returns another directory, `create_env()`
#'   cannot replace an existing environment, or delete a directory left by
#'   a failed create. It aborts with `condathis_create_env_failed`, whose
#'   parent has the class `condathis_unsafe_env_dir_move` or
#'   `condathis_unsafe_env_dir_delete`.
#'
#'   `condathis` keeps the environment that it replaces in the directory\cr
#'   `<backend_get_install_dir()>/envs/#trash` until the backend succeeded.
#'   No environment can have that name, so `backend_list_envs()` must leave
#'   that directory out.
#' * `backend_install(backend, packages, env_name = "condathis-env",
#'   channels = "conda-forge",
#'   channel_priority = c("strict", "flexible", "disabled"),
#'   additional_channels = NULL, platform = NULL,
#'   verbose = c("output", "silent", "cmd", "spinner", "full"))` installs
#'   `packages` into the existing environment `env_name`, solving for
#'   `platform`. `condathis` passes the platform recorded for the
#'   environment: the one in its marker or its `.mambarc`. On Apple Silicon
#'   and on Windows, `condathis` can choose an emulated platform (see
#'   `backend_can_solve()`). There it also reads the platform of the
#'   package records of an environment without a recorded one. For an
#'   environment without packages of a platform, it passes the platform
#'   that it would choose for a new environment. Otherwise, `platform` is
#'   `NULL`. It must not create a missing environment.
#'
#'   It can also take the optional arguments `env_file = NULL` and
#'   `definition = NULL`. With `env_file`, install the packages that the
#'   file requests, solved
#'   together with the packages of the environment, as `micromamba install
#'   -f` does. [install_packages()] passes a file only when
#'   `backend_describe_definition()` did not say that it is a lock (or that
#'   the backend cannot read it). A function that takes neither argument
#'   cannot install from a file, and
#'   [install_packages()] then aborts before any call with class
#'   `condathis_install_packages_unsupported_definition`. A function that
#'   takes `env_file` but not `definition` gets only the path, as
#'   `backend_create_env()` does.
#' * `backend_resolve_run(backend, cmd, args = character(0L),
#'   env_name = "condathis-env", verbose = "silent", base_env = NULL,
#'   timeout = Inf)` describes, without running `cmd`, how to run `cmd`
#'   with `args` in the activated environment. `base_env` is the
#'   environment that the command gets without activation: the session's
#'   environment with the changes of *Child processes*. Compute the
#'   activation against it, not against the environment of the R session.
#'   `condathis` always passes it. `timeout` is the number of seconds the
#'   function may take: what is left of the `timeout` of [run()],
#'   [run_bin()] or [run_pipeline()], or `Inf`. If the function runs code
#'   to compute the activation, such as the `activate.d` scripts of the
#'   environment, that code can hang. The function should stop it when the
#'   time runs out, and signal an error. When the time ran out,
#'   `condathis` reports a timeout for the call (`timeout = TRUE`, status
#'   `-9`), whatever the function returned or signaled. It does not start
#'   the command. `timeout` is the one argument a function may leave out.
#'   Then `condathis` does not pass it, and can report the timeout only
#'   once the function returned.
#'   The function returns `list(command, args, env, dir)`:
#'   * `command`: a single string, the program to start: an absolute path,
#'     or a bare name. `condathis` starts a bare name the same way for every
#'     backend. On Linux and macOS, it is looked up on the `PATH` of the
#'     command, after `env` is applied. On Windows, [run()] and
#'     [run_pipeline()] look it up in the binary directories of the
#'     environment, with the extensions of `PATHEXT`. Otherwise, they leave
#'     it to `processx`, which searches the working directory and the `PATH`
#'     of the R session for `<name>.com` and `<name>.exe`. [run_bin()]
#'     searches the binary directories of the environment and then the
#'     `PATH` of the command. A bare name that is found nowhere fails to
#'     start.
#'   * `args`: a character vector, or `NULL`. It replaces the user's
#'     arguments, so it must contain them.
#'   * `env`: `NULL`, or a named character vector (not a list) of
#'     activation variables. Each entry replaces the variable of the same
#'     name in the environment of the command, `PATH` included. An `NA`
#'     entry removes the variable, for a variable that the activation
#'     unsets. [run_bin()] also prepends the environment's binary
#'     directories to `PATH`.
#'   * `dir`: `NULL` to keep R's working directory, or the path of an
#'     existing directory to run the command in.
#'
#'   `condathis` calls it only with activation on ([run()], and [run_bin()]
#'   and [run_pipeline()] with `activate = TRUE`). It calls it only for an
#'   environment that this backend reported as existing. It never calls it
#'   for an [env_path()] environment (see `backend_resolve_run_in_dir()`).
#'   A value that breaks these rules aborts with
#'   `condathis_backend_resolve_run_invalid`.
#'
#' @section Optional functions and their defaults:
#' The defaults treat the environments of a backend as conda prefixes in
#' `<backend_root_dir(name)>/envs`. A directory there with
#' `conda-meta/history` is an environment, and the `conda-meta/*.json`
#' files are its package records.
#'
#' * `backend_get_install_dir(backend)` returns the backend's root: the
#'   absolute path of an existing directory, in its real form
#'   (`fs::path_real()`). Paths then compare equal where a temporary
#'   directory is a symbolic link (macOS). Create the directory when it is
#'   missing. Default: [backend_root_dir()], created when missing.
#' * `backend_get_env_dir(backend, env_name = "condathis-env")` returns the
#'   absolute path of the environment directory (its prefix): the directory
#'   that `backend_create_env()` creates. It returns the path also for an
#'   environment that does not exist yet, and it must not create anything.
#'   Default: `<backend_root_dir(name)>/envs/<env_name>`.
#' * `backend_list_envs(backend, verbose = "silent")` returns the names of
#'   this backend's environments: a character vector without `NA` or
#'   duplicates. Names of the vector are dropped. It returns `character(0)`
#'   when there are none, also when the backend's root does not exist yet.
#'   It is read only: it must not create anything, and it should not
#'   install or download anything. Default: the directories in
#'   `<root>/envs` that have `conda-meta/history`, without symbolic links
#'   and without directories whose real path is elsewhere, as
#'   `micromamba env list` reports them.
#' * `backend_env_exists(backend, env_name, verbose = "silent")` returns
#'   `TRUE` or `FALSE`: whether `env_name` is an environment of this
#'   backend. It must agree with `backend_list_envs()`. `condathis` calls it
#'   for every registered backend on every call that names an environment,
#'   whatever `method` is, to find the backend that owns the environment.
#'   So it must be cheap and must not create anything. Avoid processes and
#'   downloads. Report only the environments in this backend's own root:
#'   when two backends report the same name, `condathis` aborts with
#'   `condathis_backend_ambiguous_env` unless `method` names one of them.
#'   Default: `FALSE` when `<root>/envs/<env_name>` is not a directory,
#'   else whether `backend_list_envs()` lists `env_name` (a file system
#'   that ignores case opens the directory for every spelling).
#' * `backend_list_packages(backend, env_name = "condathis-env",
#'   verbose = "silent")` returns a data frame (a tibble is fine) with one
#'   row per installed package and at least these columns: `name`,
#'   `version`, `build_string`, `channel` and `platform` (character), and
#'   `build_number` (integer, or a double with whole numbers).
#'   `platform` is the subdir of the package, such as `"linux-64"` or
#'   `"noarch"`. Extra columns are kept. An empty environment gives zero
#'   rows with the same columns. [create_env()] reads these columns to
#'   decide whether an existing environment already has the requested
#'   packages and was built for the requested platform. Default: the
#'   package records, with the columns of `micromamba list --json`, and the
#'   PyPI packages that pip or uv installed into the environment's python,
#'   as `micromamba list` lists them (channel `pypi`, and as `platform` a
#'   tag such as `linux-x86_64`). See [list_packages()].
#' * `backend_remove_env(backend, env_name = "condathis-env",
#'   verbose = c("output", "silent", "cmd", "spinner", "full"))` removes the
#'   environment and its directory. Default: deletes `conda-meta/history`
#'   first, so the environment leaves every listing at once. Then it moves
#'   the directory into `<root>/envs/#trash` and deletes it there. When a
#'   program uses one of its files (Windows), the directory cannot be
#'   moved. Then it deletes the files one by one, and moves each file in
#'   use into `#trash`, where a later call deletes it. A symbolic link is
#'   deleted, never followed. It does not run pre-unlink scripts, and
#'   reports the packages that have one (see *Results*). Like
#'   `create_env()`, it deletes only the directory
#'   `<backend_get_install_dir()>/envs/<env_name>`. A backend whose
#'   `backend_get_env_dir()` returns another directory needs its own
#'   `backend_remove_env()`. Without it, [remove_env()] aborts with
#'   `condathis_remove_env_failed`, whose parent has the class
#'   `condathis_unsafe_env_dir_delete`.
#' * `backend_available(backend)` returns `TRUE` or `FALSE`: whether the
#'   backend can create environments on this system now. It must be cheap.
#'   It only decides which backend `method = "auto"` picks for a new
#'   environment. `condathis` still lists, finds and uses the existing
#'   environments of an unavailable backend. Default: `TRUE`.
#' * `backend_clean_cache(backend,
#'   verbose = c("output", "silent", "cmd", "spinner", "full"))` deletes
#'   the package caches and the metadata caches of the backend, and nothing
#'   else. It returns `NULL` when there was nothing to clean, or a result
#'   list (see *Results*). [clean_cache()] calls it for every registered
#'   backend, also after the function of another backend failed, and then
#'   deletes `<root>/conda-pkgs` itself. Default: `NULL`.
#' * `backend_quiesce(backend, timeout = 30)` waits until no work of the
#'   backend runs in the R process any more, at most `timeout` seconds, and
#'   returns `TRUE` (invisibly), or `FALSE` with a warning when the time
#'   ran out. `condathis` calls it before [with_sandbox_dir()] and
#'   [clean_cache()] delete directories. An error from it, or a value other
#'   than `TRUE` or `FALSE`, becomes a warning of class
#'   `condathis_backend_quiesce_failed`, and `condathis` goes on. A backend
#'   that only starts processes has nothing to wait for. Default: `TRUE`.
#' * `backend_native_platform(backend)` returns the platform (subdir) that
#'   the backend solves for when it gets no `platform`, such as
#'   `"osx-arm64"`, or `NA` when it cannot tell. Default: `NA`.
#' * `backend_can_solve(backend, packages = NULL, env_file = NULL,
#'   channels = "conda-forge",
#'   channel_priority = c("strict", "flexible", "disabled"),
#'   additional_channels = NULL, platform)` returns `TRUE` when the
#'   request
#'   solves for `platform`, `FALSE` when it does not, and `NA` when it
#'   cannot tell, for example without network access or for a missing
#'   channel. It must not create an environment. `condathis` asks it when
#'   it chooses the platform of a new environment. A request that does not
#'   solve for the native platform uses an emulated one when it solves
#'   there: `"osx-64"` on Apple Silicon with Rosetta 2, and `"win-64"` on
#'   Windows on ARM. An error counts as `NA`. Default: `NA`, so `condathis`
#'   never chooses an emulated platform. `condathis` never asks it about a
#'   lock (see `backend_describe_definition()`). It can also take the
#'   optional argument `definition = NULL`.
#' * `backend_describe_definition(backend, definition, platform = NULL)`
#'   tells `condathis` what the backend makes of an [env_definition()]:
#'   whether it reads it, and whether it is a request or a lock.
#'   `platform` is the `platform` of [create_env()]. [create_env()] calls
#'   it before it locks, moves or creates anything, so it must be cheap:
#'   read the file, but do not download, install or solve anything, and do
#'   not change any environment. It returns a list:
#'   * `supported`: `TRUE` (the backend reads it), `FALSE` (it does not) or
#'     `NA` (it cannot tell). `FALSE` aborts with class
#'     `condathis_create_env_unsupported_definition` (also
#'     `condathis_backend_unsupported`), with `reason` in the message.
#'     Refuse an option of `definition$options` that you do not
#'     understand: never ignore it.
#'   * `format`: `NA`, or the name of the format that the backend detected
#'     or was given, such as `"conda-lock-v1"`.
#'   * `kind`: `"request"` (the backend solves it, as package specs),
#'     `"lock"` (it installs exact packages, without a solve) or `NA`.
#'   * `platforms`: `NULL`, or the platforms that a lock has packages for.
#'   * `reason`: `NA`, or one sentence: why `supported` is `FALSE`.
#'   * `records`: `NULL`, or for a lock a data frame with the character
#'     columns `name`, `version`, `build_string` and `platform` (the
#'     platform the record is for), one row per package that the backend
#'     installs from it.
#'
#'   For a request, `condathis` goes on as for package specs: it asks
#'   `backend_can_solve()` about the platform. For a lock, it picks the
#'   platform from `platforms` and never calls `backend_can_solve()`,
#'   since a dry run says nothing about a lock. It aborts when
#'   `channels`, `additional_channels` or `channel_priority` were given
#'   with an [env_definition()] (the deprecated `env_file` of
#'   [create_env()] passes them on, as in 0.1.4). Records of `noarch`
#'   packages install on any platform: leave `noarch` out of `platforms`.
#'   When `records` has rows for the platform and the new environment has
#'   no package, the create fails with `condathis_create_env_failed`. With
#'   `NA` as `kind`, `condathis` passes the file on and makes no other
#'   check, as for every backend before this function existed. An error
#'   counts as `NA`.
#'
#'   `records` also lets `condathis` compare an existing environment with
#'   a lock: `create_env(overwrite = FALSE)` keeps the environment when
#'   its packages are exactly the records for the platform, and
#'   [validate_env()] gives `TRUE`. Records with `NA` in `name`,
#'   `version` or `build_string` are not compared. [install_packages()]
#'   calls this function too, and installs from a request only.
#'
#'   With `method = "auto"`, a new environment from a definition goes to
#'   the first available backend in `condathis.backend_priority` order
#'   whose `supported` is not `FALSE`.
#'   Default: `NA`, or `FALSE` when the definition has a `format` or
#'   `options` and `backend_create_env()` has no `definition` argument.
#' * `backend_definition_formats(backend)` returns the names of the
#'   formats that the backend reads, as a character vector, such as
#'   `c("environment-yaml", "explicit")`. It is used only in messages: an
#'   error for a definition with a `format` names the registered backends
#'   that list it. `condathis` never decides from it. Default:
#'   `character(0)`.
#' * `backend_resolve_run_in_dir(backend, cmd, args = character(0L),
#'   env_dir, verbose = "silent", base_env = NULL, timeout = Inf)`
#'   describes how to run `cmd` with `args` in the activated environment
#'   whose directory (its prefix) is `env_dir`. This is an environment
#'   given by [env_path()], which `condathis` did not create and which may
#'   belong to no backend, such as one made by conda or mamba elsewhere. It
#'   returns `list(command, args, env, dir)` with the rules of
#'   `backend_resolve_run()` (also for `base_env` and `timeout`).
#'   `condathis` treats the value the same way, also when it breaks them.
#'   It must not change, lock or register the environment. `condathis`
#'   calls it with activation on, after it checked that `env_dir` exists
#'   and has a `conda-meta` directory. It calls it only when the backend
#'   object has this function. For a backend without it, [run()],
#'   [run_bin()] and [run_pipeline()] abort with class
#'   `condathis_env_path_unsupported_method` (also
#'   `condathis_backend_unsupported`) when `method` names that backend.
#'   `method = "auto"` uses the first backend in the order of the option
#'   `condathis.backend_priority` that has it (micromamba by default).
#'   Default: aborts with class `condathis_backend_unsupported`.
#'
#' Every value is checked: a return value that breaks these rules aborts
#' with `condathis_backend_invalid_return` (also
#' `condathis_backend_contract_violation`), naming the backend.
#'
#' @section Results:
#' `backend_create_env()`, `backend_install()`, `backend_remove_env()` and
#' `backend_clean_cache()` may return `NULL` or a list. `condathis` copies
#' the elements `status`, `stdout`, `stderr`, `timeout`, `pid` and `cmd`
#' when present (exact names) and ignores everything else. Any other value
#' counts as an empty list. A non-zero `status` without an error counts as
#' a failure. `cmd` is reported as the command line that ran, so give the
#' exact command line, or leave it out. `condathis` shows the password and
#' the token of a URL in it as `*****`, as micromamba does. Hide them the
#' same way in what the backend prints and in its errors.
#'
#' The element `link_scripts_skipped` of the results of
#' `backend_create_env()`, `backend_install()` and `backend_remove_env()`,
#' when present, is a data frame with the character columns `package` and
#' `script` (`"pre-link"`, `"post-link"` or `"pre-unlink"`). It holds the
#' link scripts of packages that the backend did not run. `condathis` then
#' warns with class `condathis_link_scripts_skipped` after the call
#' succeeded, naming the packages (see [condathis-conditions]). A backend
#' that runs every link script, as micromamba does, leaves the element
#' out. Any other value aborts with `condathis_backend_invalid_return`.
#'
#' @section Missing environments:
#' `condathis` checks with `backend_env_exists()` that an environment
#' exists before it calls `backend_install()`, `backend_remove_env()`,
#' `backend_list_packages()` and `backend_resolve_run()`. A missing
#' environment aborts with class `condathis_env_not_found` before the
#' backend is called. So these functions do not get a missing environment
#' from `condathis`, except when `backend_env_exists()` failed. Then
#' `condathis` calls them anyway, and they must signal an error for a
#' missing environment. Give that error the class
#' `condathis_env_not_found`. `condathis` keeps the `condathis_*` classes
#' of a backend error when it re-raises it, so one handler catches a
#' missing environment on both sides. None of them may create an
#' environment.
#'
#' Only [run()], [run_bin()], [run_pipeline()] and [install_packages()]
#' create a missing environment, and only the default `"condathis-env"`:
#' they call `backend_create_env()` for an empty environment first.
#'
#' For a missing environment, `backend_env_exists()` returns `FALSE`,
#' `backend_list_envs()` leaves the name out, and `backend_get_env_dir()`
#' returns the path anyway. None of them signals an error for it.
#'
#' @section Errors:
#' Signal an error of any class when an operation fails. `condathis`
#' re-raises it with your error as the parent, and with these classes:
#' * `condathis_<function>_failed`, for example
#'   `condathis_create_env_failed`.
#' * `condathis_backend_error`.
#' * Every `condathis_*` class of your error.
#'
#' Handlers still find your own classes with `rlang::cnd_inherits()`.
#'
#' When you cannot honor an argument, such as `env_file` or
#' `channel_priority = "flexible"`, also give your condition the class
#' `condathis_backend_unsupported`.
#'
#' Do not give your own conditions the class `condathis_backend_error`:
#' `condathis` adds it when it re-raises your error. An error that has it
#' anyway is re-raised like any other error.
#'
#' An error from `backend_env_exists()` means "cannot tell", never
#' "absent". A call that would change the environment then aborts with
#' `condathis_backend_probe_failed`. A query warns with
#' `condathis_backend_query_failed` and skips the backend.
#'
#' See [condathis-conditions] for every class.
#'
#' @section Channels:
#' Search only the channels in `channels` and `additional_channels`, in that
#' order, and no default channels. `channel_priority` has its Conda
#' meaning. The `channel` column of `backend_list_packages()` is the
#' channel name, as micromamba reports it (for example `"conda-forge"`), or
#' the channel URL. `condathis` compares `https://conda.anaconda.org/<name>`
#' equal to `<name>`, and drops credentials (`user:password@`,
#' `/t/<token>`) and a platform subdirectory. It compares a `file://`
#' channel by its absolute path.
#'
#' @section Child processes:
#' `condathis` starts `command` with a copy of the session's environment
#' in which the `CONDA_*` and `MAMBA_*` variables listed in
#' [condathis-options] are cleared. It then applies `env`. For commands of
#' every backend other than `"micromamba"`, `CONDA_ENVS_PATH` is the
#' parent directory of the environment directory from
#' `backend_get_env_dir()`, so a Conda tool run in the environment creates
#' named environments next to it. `CONDA_PKGS_DIRS` and `MAMBA_PKGS_DIRS`
#' are `<root>/conda-pkgs` for them when that parent directory is
#' `<root>/envs`, and `""` otherwise. A Conda tool run in the environment
#' keeps its package cache in the backend's root, never in the user's home
#' directory or in the cache of another backend. [clean_cache()] empties
#' it. For an environment given by [env_path()], they have the values of
#' the backend's own environments (those of `"condathis-env"`), not of the
#' directory that holds it. The `"micromamba"` backend sets these
#' variables to the `envs/` and `pkgs/` directories of its own root. A
#' backend whose commands need other values returns them in `env`.
#'
#' @section Registering from a backend package:
#' Put `condathis` in `Imports`, so it is loaded before your package, and
#' register from your package's `.onLoad()`. Also register from a hook on
#' the `condathis` load event. The registry lives in the `condathis`
#' namespace, so a registration is lost when `condathis` is unloaded and
#' loaded again, as during development with `pkgload::load_all()`. The hook
#' registers the backend on every later load of `condathis`. The hook list
#' belongs to base R and outlives your package, so `.onUnload()` must
#' remove the hook. Otherwise, the next load of `condathis` registers the
#' functions of an unloaded namespace.
#'
#' ```r
#' register_mybackend <- function(...) {
#'   condathis::register_backend("mybackend", new_backend_mybackend())
#' }
#'
#' .onLoad <- function(libname, pkgname) {
#'   register_mybackend()
#'   setHook(packageEvent("condathis", "onLoad"), register_mybackend)
#'   invisible(NULL)
#' }
#'
#' .onUnload <- function(libpath) {
#'   hook <- packageEvent("condathis", "onLoad")
#'   setHook(
#'     hook,
#'     Filter(function(h) !identical(h, register_mybackend), getHook(hook)),
#'     action = "replace"
#'   )
#'   if (isNamespaceLoaded("condathis")) {
#'     condathis::unregister_backend("mybackend")
#'   }
#'   invisible(NULL)
#' }
#' ```
#'
#' `register_mybackend()` must be a function at the top level of your
#' package, so that `identical()` finds it. A function created inside
#' `.onLoad()` is a new object every time. Call `condathis` functions with
#' `condathis::` instead of importing them in your `NAMESPACE`. After a
#' reload of `condathis`, imported copies would be the functions of the
#' old namespace.
#'
#' `register_backend()` validates the backend, so after a `condathis`
#' upgrade that changes the contract, the call in `.onLoad()` fails and
#' your package does not load. The error names what to change. R runs the
#' hook under `try()`, so a failing hook only prints its error and
#' `condathis` still loads.
#'
#' `condathis` knows some backend packages by name: `rattlerthis` provides
#' the backend `"rattler"`. `condathis` loads such a package when it is
#' installed and one of these holds:
#'
#' * `method` names its backend.
#' * Its backend has environments (a directory in
#'   `<backend_root_dir(name)>/envs`), so that `method = "auto"` finds them
#'   without a call to `library()`.
#' * The option `condathis.backend_priority` names its backend, and
#'   `method = "auto"` chooses the backend of a new environment.
#'
#' `condathis` does not depend on these packages. When such a package is
#' not installed, or fails to load, a `method` that names its backend
#' aborts with class `condathis_backend_not_installed` or
#' `condathis_backend_load_failed`. A change to one of its environments
#' aborts the same way. The queries skip its environments with a warning of
#' the same class (see [condathis-conditions]). The package must register
#' its backend from its `.onLoad()`. A package that loads without
#' registering it counts as failed.
#'
#' @param name Character string, the backend name that users pass as
#'   `method`. It must start with a letter, contain only letters, digits,
#'   `.`, `_` and `-`, and not end with `.`. It must not be a Windows device
#'   name, such as `"nul"`, `"con"` or `"com1"`, with or without an
#'   extension. Reserved, in any case: `"auto"`, `"native"` and
#'   `"micromamba"`, the names of the entries of the condathis data
#'   directory (`"envs"`, `"pkgs"`, `"micromamba"`, `"condabin"`,
#'   `"Scripts"`, `"condathis-micromamba.yaml"`, `"cache"`, `"home"`,
#'   `"channels"` and `"locks"`), and `"tmp"`, `"bin"`, `"lib"`, `"etc"` and
#'   `"conda-meta"`. `register_backend()` also refuses a name when the
#'   condathis data directory has an entry of that name that is not a
#'   directory. It also refuses a name that differs only in case from a
#'   registered backend name or from the backend name of a package that
#'   `condathis` knows, such as `"rattler"`. On macOS and Windows, both
#'   would have the same root. Registering a name again replaces its
#'   backend.
#' @param backend The backend object: a list of the backend functions,
#'   with its own class. See *The backend object*.
#' @param call The environment reported as the caller in errors, for calls
#'   from another package's `.onLoad()`, as in rlang.
#'
#' @returns `name`, invisibly. Aborts with these classes:
#'   * `condathis_backend_invalid_name`: a name that breaks the rules above.
#'   * `condathis_backend_reserved_name` (also
#'     `condathis_backend_invalid_name`): a reserved name.
#'   * `condathis_backend_root_conflict` (also
#'     `condathis_backend_invalid_name`): a name whose entry in the
#'     condathis data directory is not a directory.
#'   * `condathis_backend_name_conflict` (also
#'     `condathis_backend_invalid_name`): a name that differs only in case
#'     from another backend name.
#'   * `condathis_backend_class_conflict`: another registered name uses the
#'     same first class.
#'   * `condathis_backend_contract_violation`: a backend object that breaks
#'     the contract. The error names the missing functions or arguments.
#'
#'   Every error also has the class `condathis_error`, and the name errors
#'   have `condathis_invalid_arg`.
#'
#' @seealso [condathis-conditions] for the condition classes, and
#'   [condathis-options] for the variables of child processes.
#' @family backends
#'
#' @example man/examples/backend-stub.R
#'
#' @export
register_backend <- function(name, backend, call = rlang::caller_env()) {
  validate_backend_name(name, allow_reserved = FALSE, call = call)
  check_backend_name_case(name, call = call)
  check_backend_root_entry(name, call = call)
  return(register_backend_impl(name, backend, call = call))
}

#' Register a backend without the reserved-name check
#'
#' The body of `register_backend()`. `.onLoad()` calls it to register the
#' built-in `"micromamba"` backend, a name that `register_backend()`
#' refuses.
#'
#' @param name Character string, a well-formed backend name.
#' @param backend The backend object.
#' @param call Environment reported as the caller in errors.
#'
#' @returns `name`, invisibly.
#'
#' @keywords internal
#' @noRd
register_backend_impl <- function(name, backend, call = rlang::caller_env()) {
  validate_backend_name(name, allow_reserved = TRUE, call = call)
  validate_backend_object(name, backend, call = call)

  # S3 methods are keyed on the class, the registry on the name. Two names
  # sharing a class would share one set of methods, and unregistering either
  # one removed the methods the other still needed (registering the built-in
  # micromamba backend under a second name and unregistering it broke the
  # built-in backend for the rest of the session).
  backend_class <- class(backend)[[1L]]
  other_names <- setdiff(registered_names_for_class(backend_class), name)
  if (isTRUE(length(other_names) > 0L)) {
    condathis_abort(
      message = c(
        `x` = "Backend class {.cls {backend_class}} is already registered as {.field {other_names}}.",
        `i` = "Each registered backend needs its own S3 class."
      ),
      class = "condathis_backend_class_conflict",
      call = call
    )
  }
  # Re-registering a name with a different class: drop the old class's
  # methods so they do not linger.
  if (isTRUE(exists(name, envir = backend_registry, inherits = FALSE))) {
    previous_class <- class(get(name, envir = backend_registry))[[1L]]
    if (isFALSE(identical(previous_class, backend_class))) {
      remove_backend_s3_methods(previous_class)
    }
  }
  # Only the functions the object has. The methods of a previous
  # registration of this class go first, so a function the new object no
  # longer has falls back to the default of condathis.
  remove_backend_s3_methods(backend_class)
  for (generic_name in backend_provided_hooks(backend)) {
    base::registerS3method(
      genname = generic_name,
      class = backend_class,
      method = backend_s3_method(backend[[generic_name]], generic_name),
      envir = asNamespace("condathis")
    )
  }

  assign(name, backend, envir = backend_registry)
  return(invisible(name))
}

#' Check the `name` argument of `register_backend()` and
#' `unregister_backend()`
#'
#' A name is a `method` value: it must be a plain identifier, so it cannot
#' be confused with a path, an option or a `method` keyword.
#'
#' @param name The value to check.
#' @param allow_reserved Logical. `TRUE` skips the reserved-name check, for
#'   the built-in backend.
#' @param call Environment reported as the caller in errors.
#'
#' @returns `name`, invisibly. Aborts with
#'   `c("condathis_backend_invalid_name", "condathis_invalid_arg",
#'   "condathis_error")`, or for a reserved name (in any case, see
#'   `reserved_backend_names`) with
#'   `c("condathis_backend_reserved_name", "condathis_backend_invalid_name",
#'   "condathis_invalid_arg", "condathis_error")`. A name that ends with `.`
#'   or is a Windows device name (see `windows_device_names`) is invalid:
#'   Windows opens `<root>/foo.` as `<root>/foo`, and `<root>/nul` as a
#'   device.
#'
#' @keywords internal
#' @noRd
validate_backend_name <- function(
  name,
  allow_reserved = FALSE,
  call = rlang::caller_env()
) {
  if (
    isFALSE(rlang::is_string(name)) ||
      isFALSE(grepl("^[A-Za-z][A-Za-z0-9._-]*$", name))
  ) {
    message <- c(
      `x` = "{.arg name} must be a single string that starts with a letter and contains only letters, digits, {.val .}, {.val _} and {.val -}."
    )
    if (isTRUE(rlang::is_string(name))) {
      message <- c(message, `i` = "It is {.val {name}}.")
    } else {
      message <- c(message, `i` = "It is {.obj_type_friendly {name}}.")
    }
    condathis_abort(
      message = message,
      class = c("condathis_backend_invalid_name", "condathis_invalid_arg"),
      call = call
    )
  }
  # The root of a backend is the directory of its name (see
  # `backend_root_dir()`), and the name must give the same directory on
  # every OS.
  is_device <- tolower(sub("[.].*$", "", name)) %in% windows_device_names
  if (isTRUE(endsWith(name, ".")) || isTRUE(is_device)) {
    condathis_abort(
      message = c(
        `x` = "{.arg name} must not be {.val {name}}.",
        `i` = if (isTRUE(is_device)) {
          "It is the name of a Windows device, so it cannot be the name of a directory."
        } else {
          "Windows drops a final {.val .} from the name of a directory."
        }
      ),
      class = c("condathis_backend_invalid_name", "condathis_invalid_arg"),
      call = call
    )
  }
  if (
    isFALSE(allow_reserved) &&
      isTRUE(tolower(name) %in% tolower(reserved_backend_names))
  ) {
    hint <- if (isTRUE(tolower(name) %in% c("auto", "native", "micromamba"))) {
      "{.val auto} and {.val native} are {.arg method} values, and {.val micromamba} is the built-in backend."
    } else {
      "The root of a backend is the directory of its name in the condathis data directory, so the names of the entries there, such as {.val envs} and {.val pkgs}, are reserved."
    }
    condathis_abort(
      message = c(
        `x` = "{.arg name} must not be {.val {name}}.",
        `i` = hint
      ),
      class = c(
        "condathis_backend_reserved_name",
        "condathis_backend_invalid_name",
        "condathis_invalid_arg"
      ),
      call = call
    )
  }
  return(invisible(name))
}

#' Refuse a backend name that differs only in case from another one
#'
#' The root of a backend is the directory of its name (see
#' `backend_root_dir()`), and the file systems of macOS and Windows ignore
#' case: `"Foo"` and `"foo"` would share one root, so both backends would
#' own every environment in it. The other names are the registered ones
#' and those of `known_backend_packages`, whose package may register later.
#'
#' @param name Character string, a valid backend name.
#' @param call Environment reported as the caller in errors.
#'
#' @returns `name`, invisibly. Aborts with
#'   `c("condathis_backend_name_conflict", "condathis_backend_invalid_name",
#'   "condathis_invalid_arg", "condathis_error")`.
#'
#' @keywords internal
#' @noRd
check_backend_name_case <- function(name, call = rlang::caller_env()) {
  other_names <- unique(c(
    list_registered_backend_names(),
    names(known_backend_packages)
  ))
  taken <- other_names[
    tolower(other_names) == tolower(name) & other_names != name
  ]
  if (isTRUE(length(taken) > 0L)) {
    condathis_abort(
      message = c(
        `x` = "{.arg name} must not be {.val {name}}.",
        `i` = "It differs only in case from the backend name {.val {taken[[1L]]}}, and on macOS and Windows both would have the same root."
      ),
      class = c(
        "condathis_backend_name_conflict",
        "condathis_backend_invalid_name",
        "condathis_invalid_arg"
      ),
      call = call
    )
  }
  return(invisible(name))
}

#' Refuse a backend name whose root path is taken by a file
#'
#' The root of a backend is `<condathis data directory>/<name>` (see
#' `backend_root_dir()`), so an entry of that name that is not a directory,
#' such as a file or a broken symbolic link, would make every default that
#' creates the root fail.
#'
#' @param name Character string, a valid backend name.
#' @param call Environment reported as the caller in errors.
#'
#' @returns `name`, invisibly. Aborts with
#'   `c("condathis_backend_root_conflict", "condathis_backend_invalid_name",
#'   "condathis_invalid_arg", "condathis_error")`.
#'
#' @keywords internal
#' @noRd
check_backend_root_entry <- function(name, call = rlang::caller_env()) {
  root <- backend_root_path(name)
  taken <- (isTRUE(fs::file_exists(root)) || isTRUE(fs::link_exists(root))) &&
    isFALSE(fs::dir_exists(root))
  if (isTRUE(taken)) {
    condathis_abort(
      message = c(
        `x` = "{.arg name} must not be {.val {name}}.",
        `i` = "The root of backend {.field {name}} would be {.path {root}}, which exists and is not a directory."
      ),
      class = c(
        "condathis_backend_root_conflict",
        "condathis_backend_invalid_name",
        "condathis_invalid_arg"
      ),
      call = call
    )
  }
  return(invisible(name))
}

#' The contract functions a backend object provides
#'
#' @param backend A backend object (a list).
#'
#' @returns Character vector, the names in `backend_contract_names` whose
#'   element is not `NULL`, in that order.
#'
#' @keywords internal
#' @noRd
backend_provided_hooks <- function(backend) {
  present <- vapply(
    backend_contract_names,
    function(generic_name) isFALSE(is.null(backend[[generic_name]])),
    logical(1L),
    USE.NAMES = FALSE
  )
  return(backend_contract_names[present])
}

#' Check a backend object against the contract
#'
#' Checks what condathis relies on before it registers any method: the
#' object is a list, its first class is its own and it inherits
#' `"condathis_backend"`, it has the required contract functions
#' (`backend_required_hooks`), every other contract element is a function
#' or `NULL`, an own `backend_get_install_dir()` comes with the functions
#' of `backend_root_hooks`, and each function accepts the arguments of its
#' generic by name (or has `...`). A function with the wrong arguments
#' would otherwise fail only when it is called, with "unused argument".
#'
#' @param name Character string, the backend name, for messages.
#' @param backend The backend object.
#' @param call Environment reported as the caller in errors.
#'
#' @returns `backend`, invisibly. Aborts with
#'   `c("condathis_backend_contract_violation", "condathis_error")`.
#'
#' @keywords internal
#' @noRd
validate_backend_object <- function(name, backend, call = rlang::caller_env()) {
  backend_classes <- class(backend)
  if (
    isFALSE(is.list(backend)) ||
      isFALSE(inherits(backend, "condathis_backend")) ||
      isTRUE(length(backend_classes) < 2L) ||
      isTRUE(backend_classes[[1L]] %in% shared_backend_first_classes)
  ) {
    condathis_abort(
      message = c(
        `x` = "Backend {.field {name}} must be a list with its own first class that inherits {.cls condathis_backend}.",
        `i` = "Its class is {.cls {backend_classes}}.",
        `i` = "Build it with {.code structure(list(...), class = c(\"condathis_backend_<name>\", \"condathis_backend\"))}."
      ),
      class = "condathis_backend_contract_violation",
      call = call
    )
  }

  provided <- backend_provided_hooks(backend)
  missing_generics <- setdiff(backend_required_hooks, provided)
  not_functions <- provided[
    vapply(
      provided,
      function(generic_name) isFALSE(is.function(backend[[generic_name]])),
      logical(1L)
    )
  ]
  if (
    isTRUE(length(missing_generics) > 0L) ||
      isTRUE(length(not_functions) > 0L)
  ) {
    condathis_abort(
      message = c(
        `x` = "Backend {.field {name}} does not implement the backend contract.",
        `i` = if (isTRUE(length(missing_generics) > 0L)) {
          "Missing: {.field {missing_generics}}."
        },
        `i` = if (isTRUE(length(not_functions) > 0L)) {
          "Not a function or {.code NULL}: {.field {not_functions}}."
        },
        `i` = "Required: {.field {backend_required_hooks}}."
      ),
      class = "condathis_backend_contract_violation",
      call = call
    )
  }

  for (own_hook in c("backend_get_install_dir", "backend_get_env_dir")) {
    needed <- if (identical(own_hook, "backend_get_install_dir")) {
      backend_root_hooks
    } else {
      backend_env_dir_hooks
    }
    missing_root_hooks <- setdiff(needed, provided)
    if (
      isTRUE(own_hook %in% provided) &&
        isTRUE(length(missing_root_hooks) > 0L)
    ) {
      condathis_abort(
        message = c(
          `x` = "Backend {.field {name}} has its own {.fn {own_hook}}, but not {.field {missing_root_hooks}}.",
          `i` = "The defaults of these functions look for environments in {.code <backend_root_dir()>/envs}, not where the backend keeps them.",
          `i` = "Implement them too, or leave {.fn {own_hook}} out."
        ),
        class = "condathis_backend_contract_violation",
        call = call
      )
    }
  }

  missing_args <- lapply(provided, function(generic_name) {
    fn_args <- names(formals(args(backend[[generic_name]])))
    if (isTRUE("..." %in% fn_args)) {
      return(character(0L))
    }
    return(setdiff(
      backend_generic_args(generic_name),
      c(fn_args, backend_optional_args[[generic_name]])
    ))
  })
  names(missing_args) <- provided
  missing_args <- Filter(function(x) isTRUE(length(x) > 0L), missing_args)
  if (isTRUE(length(missing_args) > 0L)) {
    bad_generics <- names(missing_args)
    # One bullet per function. The bullets index into `bad_generics` and
    # `missing_args`, so argument names are never parsed as cli markup.
    bullets <- vapply(
      seq_along(bad_generics),
      function(i) {
        paste0(
          "{.fn {bad_generics[[",
          i,
          "]]}} lacks {.arg {missing_args[[",
          i,
          "]]}}."
        )
      },
      character(1L)
    )
    names(bullets) <- rep("*", length(bullets))
    condathis_abort(
      message = c(
        `x` = "Backend {.field {name}} has functions that cannot take the arguments condathis passes.",
        bullets,
        `i` = "Give each function the arguments of its contract signature (see {.code ?condathis::register_backend}), or a {.code ...} argument."
      ),
      class = "condathis_backend_contract_violation",
      call = call
    )
  }
  return(invisible(backend))
}

#' Arguments that a backend function may leave out
#'
#' `timeout` of `backend_resolve_run()` and `backend_resolve_run_in_dir()`,
#' `definition` of `backend_create_env()`, `backend_install()` and
#' `backend_can_solve()`, and `env_file` of `backend_install()`, came after
#' the first functions of version 2 of the contract: condathis passes them
#' only to a function that takes them (see `backend_resolve_args()`).
#'
#' @keywords internal
#' @noRd
backend_optional_args <- list(
  backend_resolve_run = "timeout",
  backend_resolve_run_in_dir = "timeout",
  backend_create_env = "definition",
  backend_install = c("env_file", "definition"),
  backend_can_solve = "definition"
)

#' The optional arguments a backend function takes
#'
#' @param backend A backend object.
#' @param generic_name Character string, the contract function.
#' @param ... Named values of the optional arguments of `generic_name` (see
#'   `backend_optional_args`).
#'
#' @returns A named list: the values of `...` that the backend's function
#'   takes, by name or through `...`.
#'
#' @keywords internal
#' @noRd
backend_resolve_args <- function(backend, generic_name, ...) {
  values <- list(...)
  fn <- backend[[generic_name]]
  if (isFALSE(is.function(fn))) {
    return(values)
  }
  fn_args <- names(formals(args(fn)))
  if (isTRUE("..." %in% fn_args)) {
    return(values)
  }
  return(values[intersect(names(values), fn_args)])
}

#' The S3 method that `register_backend()` registers for a backend function
#'
#' A function with optional arguments that its generic lacks (see
#' `backend_optional_args`), such as `definition`, gets a method with
#' exactly the formals of the generic that calls it: S3 methods must match
#' their generic. `condathis` passes the optional arguments by calling the
#' function itself (see `backend_call()`). Any other function is its own
#' method.
#'
#' @param fn The function of the backend object.
#' @param generic_name Character string, the contract function.
#'
#' @returns A function.
#'
#' @keywords internal
#' @noRd
backend_s3_method <- function(fn, generic_name) {
  generic_formals <- formals(backend_generic_fn(generic_name))
  fn_args <- names(formals(args(fn)))
  extra <- setdiff(fn_args, c(names(generic_formals), "..."))
  if (identical(length(extra), 0L)) {
    return(fn)
  }
  arg_names <- names(generic_formals)
  call_args <- rlang::syms(arg_names)
  names(call_args) <- arg_names
  # The function is a variable of the method's environment, not a value
  # in its body: the S3 checks of R CMD check read the body.
  method_env <- new.env(parent = baseenv())
  method_env$backend_fn <- fn
  method <- function() NULL
  formals(method) <- generic_formals
  body(method) <- rlang::call2("{", rlang::call2("backend_fn", !!!call_args))
  environment(method) <- method_env
  return(method)
}

#' A contract generic of the `condathis` namespace
#'
#' @param generic_name Character string.
#'
#' @returns The function.
#'
#' @keywords internal
#' @noRd
backend_generic_fn <- function(generic_name) {
  return(get(
    generic_name,
    envir = asNamespace("condathis"),
    mode = "function",
    inherits = FALSE
  ))
}

#' Call a contract function, with the optional arguments it takes
#'
#' The generics keep the signatures of version 2 of the contract, so the
#' functions of a backend written for it, such as the rattlerthis backend,
#' still have exactly the formals of the generics. The arguments that came
#' later (see `backend_optional_args`) are passed by calling the backend's
#' own function, and only when that function takes them by name or
#' through `...`. Without such arguments, or for a function that the
#' object leaves out (the defaults of `condathis` take none), the generic
#' is called as usual.
#'
#' @param generic_name Character string, the contract function.
#' @param backend A backend object.
#' @param ... Arguments of the generic, by name.
#' @param .optional Named list of optional arguments.
#'
#' @returns The value of the backend function.
#'
#' @keywords internal
#' @noRd
backend_call <- function(generic_name, backend, ..., .optional = list()) {
  fn <- backend[[generic_name]]
  if (isFALSE(is.function(fn))) {
    # The default of condathis, which takes no optional argument.
    fn <- backend_generic_fn(paste0(generic_name, ".default"))
  }
  fn_args <- names(formals(args(fn)))
  if (isFALSE("..." %in% fn_args)) {
    .optional <- .optional[intersect(names(.optional), fn_args)]
  }
  if (identical(length(.optional), 0L)) {
    return(backend_generic_fn(generic_name)(backend, ...))
  }
  return(rlang::exec(fn, backend, ..., !!!.optional))
}

#' Does a backend function take an argument?
#'
#' @param backend A backend object.
#' @param generic_name Character string, the contract function.
#' @param arg Character string, the argument name.
#'
#' @returns `TRUE` when the backend's function has `arg` or `...` among its
#'   arguments, or when the object leaves the function out: the default of
#'   condathis then takes every argument of the generic. `FALSE`
#'   otherwise.
#'
#' @keywords internal
#' @noRd
backend_fn_takes_arg <- function(backend, generic_name, arg) {
  fn <- backend[[generic_name]]
  if (isFALSE(is.function(fn))) {
    return(TRUE)
  }
  fn_args <- names(formals(args(fn)))
  return(isTRUE("..." %in% fn_args) || isTRUE(arg %in% fn_args))
}

#' Argument names of a contract generic
#'
#' @param generic_name Character string, one of `backend_contract_names`.
#'
#' @returns Character vector, the formals of the generic in the `condathis`
#'   namespace.
#'
#' @keywords internal
#' @noRd
backend_generic_args <- function(generic_name) {
  generic <- get(
    generic_name,
    envir = asNamespace("condathis"),
    mode = "function",
    inherits = FALSE
  )
  return(names(formals(generic)))
}

#' Unregister a condathis backend
#'
#' Removes a backend added with [register_backend()]: the registry entry
#' and the S3 methods registered for its class. Call it from the
#' `.onUnload()` of a backend package (see *Registering from a backend
#' package* in [register_backend()]). Then an unloaded package leaves no
#' registered backend whose functions belong to a missing namespace.
#'
#' Unregistering a name that is not registered does nothing and returns
#' `FALSE`, so an unload hook never fails on cleanup that has nothing left
#' to clean. `unregister_backend()` refuses the reserved names of
#' [register_backend()], because the built-in `"micromamba"` backend is
#' always registered.
#'
#' Part of the **experimental** backend extension API. See the
#' *Lifecycle* section of [register_backend()].
#'
#' @param name Character string with the backend name to unregister.
#' @param call The environment reported as the caller in errors, for calls
#'   from another package's `.onUnload()`, as in rlang.
#'
#' @returns Logical, invisibly: `TRUE` if a backend was unregistered,
#'   `FALSE` if no backend by that name was registered. A malformed name
#'   aborts with class `condathis_backend_invalid_name`, and a reserved one
#'   with `condathis_backend_reserved_name` (also
#'   `condathis_backend_invalid_name`).
#'
#' @family backends
#'
#' @example man/examples/backend-stub.R
#'
#' @export
unregister_backend <- function(name, call = rlang::caller_env()) {
  validate_backend_name(name, allow_reserved = FALSE, call = call)
  if (isFALSE(exists(name, envir = backend_registry, inherits = FALSE))) {
    return(invisible(FALSE))
  }

  backend <- get(name, envir = backend_registry, inherits = FALSE)
  backend_class <- class(backend)[[1L]]

  # Drop the S3 methods `register_backend()` registered for this class. A
  # stale method would hold the last reference to the namespace of the
  # backend package, which may be unloaded. The runtime S3 methods table is
  # not locked (it accepts `registerS3method()` calls after namespace
  # sealing), so `rm()` can remove entries.
  rm(list = name, envir = backend_registry)
  # Only when no other registered name still uses the class (re-registering
  # a name as a fresh class is fine; `register_backend()` refuses two names
  # sharing one class, but guard here as well).
  if (isFALSE(length(registered_names_for_class(backend_class)) > 0L)) {
    remove_backend_s3_methods(backend_class)
  }
  return(invisible(TRUE))
}

#' Names of the registered backends whose first class is `backend_class`
#'
#' @keywords internal
#' @noRd
registered_names_for_class <- function(backend_class) {
  nms <- ls(envir = backend_registry, all.names = TRUE)
  hits <- vapply(
    nms,
    function(nm) {
      identical(class(get(nm, envir = backend_registry))[[1L]], backend_class)
    },
    logical(1L)
  )
  return(nms[hits])
}

#' Remove the backend-contract S3 methods registered for a class
#'
#' @keywords internal
#' @noRd
remove_backend_s3_methods <- function(backend_class) {
  s3_table <- asNamespace("condathis")[[".__S3MethodsTable__."]]
  for (generic_name in backend_contract_names) {
    method_name <- paste0(generic_name, ".", backend_class)
    if (isTRUE(exists(method_name, envir = s3_table, inherits = FALSE))) {
      rm(list = method_name, envir = s3_table)
    }
  }
  return(invisible(NULL))
}

#' Retrieve a registered backend by name
#'
#' @keywords internal
#' @noRd
get_backend <- function(name, call = rlang::caller_env()) {
  if (isFALSE(exists(name, envir = backend_registry, inherits = FALSE))) {
    condathis_abort(
      message = c(
        `x` = "No backend named {.field {name}} is registered.",
        `i` = "Registered backends: {.field {list_registered_backend_names()}}."
      ),
      class = "condathis_backend_not_registered",
      call = call
    )
  }
  return(get(name, envir = backend_registry, inherits = FALSE))
}

#' List the registered backends
#'
#' Returns the names of every backend registered with [register_backend()],
#' available on this system or not. Each one is a valid `method` value of
#' every `condathis` function that takes `method`, besides `"auto"`. The
#' built-in `"micromamba"` backend is always registered.
#'
#' A backend whose package `condathis` knows, such as `"rattler"` of the
#' `rattlerthis` package, is also a valid `method` value when its package
#' is installed but not loaded yet. `condathis` loads the package on first
#' use (see *Registering from a backend package* in [register_backend()]).
#' It is listed here once it is loaded. The error for an invalid `method`
#' value names these backends too.
#'
#' @returns A sorted character vector of registered backend names.
#'
#' @family backends
#'
#' @examples
#' condathis::list_registered_backend_names()
#'
#' @export
list_registered_backend_names <- function() {
  return(sort(ls(envir = backend_registry)))
}

#' Validate a `method` argument against the currently registered backends
#'
#' The shared parser of `method`, so its errors have only the shared
#' classes: `c("condathis_invalid_method", "condathis_invalid_method_arg",
#' "condathis_invalid_arg", "condathis_error")`. `condathis_invalid_method_arg`
#' is the old name, kept until 1.0.
#'
#' A `method` that names a known backend (`known_backend_packages`) that is
#' not registered yet loads its package first, so the backend is a valid
#' value once it registers. When it cannot be loaded, the error also has
#' `condathis_backend_not_installed` or `condathis_backend_load_failed`
#' (see `load_known_backends()`).
#'
#' The 0.1.4 default vector of `create_env()` and `run()`,
#' `c("native", "auto")`, and `c("auto", "native")` give their first
#' element, as `rlang::arg_match()` did in 0.1.4. Any other vector aborts.
#' Callers use the returned value, not `method` itself.
#'
#' @returns A character string: `method`, or the first element of one of
#'   those two vectors. `"native"` is resolved later by
#'   `resolve_method_alias()`.
#'
#' @keywords internal
#' @noRd
validate_method_arg <- function(method, call = rlang::caller_env()) {
  method_class <- c(
    "condathis_invalid_method",
    "condathis_invalid_method_arg",
    "condathis_invalid_arg"
  )
  if (
    isTRUE(is.character(method)) &&
      isTRUE(identical(length(method), 2L)) &&
      isTRUE(setequal(method, c("native", "auto")))
  ) {
    method <- method[[1L]]
  }
  hint <- positional_verbose_hint(method, call = call)
  if (isFALSE(rlang::is_string(method))) {
    condathis_abort(
      message = c(
        `x` = "{.arg method} must be a single, non-missing character string, not {.obj_type_friendly {method}}.",
        hint
      ),
      class = method_class,
      call = call
    )
  }
  # Before the valid values are computed: the backend registers itself
  # while its package loads.
  if (
    isTRUE(method %in% names(known_backend_packages)) &&
      isFALSE(method %in% list_registered_backend_names())
  ) {
    load_known_backends(method = method, call = call)
  }
  valid_values <- c("auto", list_registered_backend_names(), "native")
  if (isFALSE(method %in% valid_values)) {
    on_first_use <- installed_known_backend_names()
    suggestion <- if (is.null(hint)) {
      closest_names(method, c(valid_values, on_first_use))
    }
    condathis_abort(
      message = c(
        `x` = "{.arg method} must be one of {.or {.val {valid_values}}}, not {.val {method}}.",
        if (isTRUE(length(on_first_use) > 0L)) {
          c(
            `i` = "Also installed: {.val {on_first_use}}, loaded on first use."
          )
        },
        if (isTRUE(length(suggestion) > 0L)) {
          c(`i` = "Did you mean {.val {suggestion}}?")
        },
        hint
      ),
      class = method_class,
      call = call
    )
  }
  return(method)
}

#' Hint for a `verbose` value passed by position as `method`
#'
#' Since 0.2.0, `method` comes before `verbose` in `env_exists()`,
#' `list_envs()`, `remove_env()` and `list_packages()`, so a call such as
#' `list_envs("silent")` from 0.1.4 now passes the verbose level as
#' `method`. The hint is given only when the reported caller is such a
#' function. `get_env_dir()` and `get_install_dir()` have no `verbose`, and
#' `run()` or `create_env()` take `method` only by name, so for them the
#' hint would name an argument that cannot be passed that way.
#'
#' @param method The value of `method`.
#' @param call The environment reported as the caller, as in
#'   `validate_method_arg()`.
#'
#' @returns A named character vector with one `i` bullet, or `NULL`.
#'
#' @keywords internal
#' @noRd
positional_verbose_hint <- function(method, call = rlang::caller_env()) {
  is_verbose_value <- (isTRUE(rlang::is_string(method)) &&
    isTRUE(method %in% condathis_verbose_values)) ||
    isTRUE(rlang::is_bool(method))
  if (isFALSE(is_verbose_value)) {
    return(NULL)
  }
  if (isFALSE(takes_method_before_verbose(caller_formal_names(call)))) {
    return(NULL)
  }
  verbose_code <- if (isTRUE(rlang::is_bool(method))) {
    paste0("verbose = ", method)
  } else {
    paste0("verbose = \"", method, "\"")
  }
  return(c(
    `i` = paste0(
      "{.arg method} now comes before {.arg verbose}. Pass {.code ",
      verbose_code,
      "} by name."
    )
  ))
}

#' Can a positional argument meant for `verbose` land in `method`?
#'
#' @param formal_names Character vector, the formals of a function in
#'   order.
#'
#' @returns `TRUE` when the formals have `method` before `...` (or no
#'   `...`) and also have `verbose`. `FALSE` otherwise.
#'
#' @keywords internal
#' @noRd
takes_method_before_verbose <- function(formal_names) {
  method_pos <- match("method", formal_names)
  dots_pos <- match("...", formal_names)
  return(
    isTRUE("verbose" %in% formal_names) &&
      isFALSE(is.na(method_pos)) &&
      (isTRUE(is.na(dots_pos)) || isTRUE(method_pos < dots_pos))
  )
}

#' Formal argument names of the function whose frame is `call`
#'
#' @param call An environment, usually from `rlang::caller_env()`.
#'
#' @returns Character vector. Empty when `call` is not the frame of a
#'   function on the call stack, for example the global environment.
#'
#' @keywords internal
#' @noRd
caller_formal_names <- function(call) {
  if (isFALSE(is.environment(call))) {
    return(character(0L))
  }
  frames <- sys.frames()
  for (i in rev(seq_along(frames))) {
    if (isTRUE(identical(frames[[i]], call))) {
      return(as.character(names(formals(sys.function(i)))))
    }
  }
  return(character(0L))
}

#' Resolve the deprecated `"native"` alias to `"micromamba"`
#'
#' A soft deprecation (see `condathis_deprecate_soft()`): it warns once per
#' session (id `"deprecated_method_native"`, class
#' `condathis_deprecated_method_native`), and only for direct use. The
#' warning counts as given before it is signaled, so under
#' `options(warn = 2)` only the first call errors.
#'
#' @param method Character string, from `validate_method_arg()`.
#' @param user_env The environment the exported function was called from
#'   (`rlang::caller_env()` there), or `NULL` to count the call as direct.
#'
#' @keywords internal
#' @noRd
resolve_method_alias <- function(method, user_env = NULL) {
  if (identical(method, "native")) {
    condathis_deprecate_soft(
      id = "deprecated_method_native",
      message = c(
        `!` = "{.val native} is a deprecated alias for {.val micromamba}.",
        `i` = "Use {.code method = \"micromamba\"} instead."
      ),
      class = "condathis_deprecated_method_native",
      user_env = user_env
    )
    return("micromamba")
  }
  return(method)
}

#' Resolve a backend when no specific environment is involved
#'
#' Used both for `env_name = NULL` callers (e.g. `get_install_dir()`) and
#' for a genuinely new environment (nothing to disambiguate against yet).
#' This is the only place where `backend_available()` matters (rule R6).
#' With `method = "auto"`, a known backend package (see
#' `known_backend_packages`) whose backend the option
#' `condathis.backend_priority` names is loaded first: before, the option
#' took effect only once another call had loaded the package, so the
#' backend of a new environment depended on what ran earlier in the
#' session.
#'
#' With `accept`, `"auto"` also skips an available backend that `accept`
#' refuses, as the routing of an environment given by [env_path()] skips a
#' backend that cannot run it. `create_env()` uses it for an
#' [env_definition()] that a backend says it cannot read. An explicit
#' `method` is never rerouted.
#'
#' @param method Character string, `"auto"` or a registered backend name.
#' @param accept `NULL`, or a function of `backend` and `name` that returns
#'   `TRUE` to accept the backend, or a character string, the reason it
#'   refuses it.
#' @param on_refused A function of a named character vector (the reasons,
#'   named by backend) that aborts. Called when `accept` refused every
#'   available backend.
#' @param call Environment of the function the error is reported for.
#'
#' @keywords internal
#' @noRd
resolve_backend_by_priority <- function(
  method,
  accept = NULL,
  on_refused = NULL,
  call = rlang::caller_env()
) {
  if (isFALSE(identical(method, "auto"))) {
    backend <- get_backend(method, call = call)
    return(list(backend = backend, name = method))
  }
  # A known backend that the priority option names is loaded first, so the
  # option decides, not what an earlier call happened to load.
  load_known_backends(priority = TRUE, call = call)
  candidates <- backend_names_by_priority()
  refused <- character(0L)
  for (candidate in candidates) {
    backend <- get_backend(candidate, call = call)
    available <- validate_backend_return(
      backend_available(backend),
      generic = "backend_available",
      backend_name = candidate,
      call = call
    )
    if (isFALSE(available)) {
      next
    }
    if (is.function(accept)) {
      verdict <- accept(backend, candidate)
      if (isFALSE(isTRUE(verdict))) {
        refused[[candidate]] <- as.character(verdict)
        next
      }
    }
    return(list(backend = backend, name = candidate))
  }
  if (isTRUE(length(refused) > 0L) && is.function(on_refused)) {
    on_refused(refused)
  }
  condathis_abort(
    message = c(`x` = "No registered backend is currently available."),
    class = "condathis_backend_none_available",
    call = call
  )
}

#' Resolve a backend for an environment that already exists under exactly
#' one registered backend
#'
#' @keywords internal
#' @noRd
resolve_backend_existing_env <- function(
  env_name,
  method,
  owner,
  mutating,
  call = rlang::caller_env()
) {
  if (identical(method, "auto") || identical(method, owner)) {
    backend <- get_backend(owner, call = call)
    return(list(backend = backend, name = owner))
  }

  if (isTRUE(mutating)) {
    condathis_abort(
      message = c(
        `x` = "Environment {.field {env_name}} is owned by backend {.field {owner}}, not {.field {method}}.",
        `i` = "Remove it first, or use {.code method = \"{owner}\"}."
      ),
      class = "condathis_backend_mismatch",
      call = call
    )
  }

  condathis_warn(
    message = c(
      `!` = "Environment {.field {env_name}} is owned by backend {.field {owner}}, not {.field {method}}.",
      `i` = "Using {.field {owner}} instead."
    ),
    class = "condathis_backend_mismatch_warning"
  )
  backend <- get_backend(owner, call = call)
  return(list(backend = backend, name = owner))
}

#' Resolve a backend for an environment that exists under more than one
#' registered backend simultaneously
#'
#' @keywords internal
#' @noRd
resolve_backend_ambiguous_env <- function(
  env_name,
  method,
  owners,
  call = rlang::caller_env()
) {
  if (isTRUE(method %in% owners)) {
    backend <- get_backend(method, call = call)
    return(list(backend = backend, name = method))
  }
  condathis_abort(
    message = c(
      `x` = "Environment {.field {env_name}} exists under more than one backend: {.field {owners}}.",
      `i` = "Specify an explicit {.arg method} to disambiguate."
    ),
    class = "condathis_backend_ambiguous_env",
    call = call
  )
}

#' Resolve which backend a call should use
#'
#' The shared dispatch point for every backend-touching public function.
#'
#' @param env_name Character string, or `NULL` when the caller has no
#'   specific environment in mind (e.g. `get_install_dir()`).
#' @param method Character string: `"auto"`, a registered backend name, or
#'   the deprecated `"native"` alias.
#' @param mutating Logical. Whether the caller is about to create/modify/
#'   remove the environment (`TRUE`: a backend/marker mismatch, or a probe
#'   that fails, aborts) or only read from it (`FALSE`: a mismatch warns
#'   and uses the actual owner instead, and a failed probe warns).
#' @param user_env The environment the exported function was called from
#'   (`rlang::caller_env()` there), for the soft deprecation of `"native"`
#'   (see `resolve_method_alias()`). `NULL` counts the call as direct.
#' @param accept,on_refused For an environment that no backend has, with
#'   `method = "auto"`: see `resolve_backend_by_priority()`. An existing
#'   environment always gets its own backend.
#' @param call Calling environment, passed to `condathis_abort()`.
#'
#' @returns A list with `backend` (the resolved backend object) and `name`
#'   (its registered name).
#'
#' @keywords internal
#' @noRd
resolve_backend <- function(
  env_name = NULL,
  method = "auto",
  mutating = FALSE,
  user_env = NULL,
  accept = NULL,
  on_refused = NULL,
  call = rlang::caller_env()
) {
  method <- resolve_method_alias(
    validate_method_arg(method, call = call),
    user_env = user_env
  )
  # A known backend that has environments is loaded first, so an
  # environment of it is found without a `library()` call.
  load_known_backends(call = call)

  if (rlang::is_null(env_name)) {
    return(resolve_backend_by_priority(method, call = call))
  }

  owners <- find_owning_backends(env_name, mutating = mutating, call = call)

  if (identical(length(owners), 0L)) {
    return(resolve_backend_by_priority(
      method,
      accept = accept,
      on_refused = on_refused,
      call = call
    ))
  }
  if (identical(length(owners), 1L)) {
    return(resolve_backend_existing_env(
      env_name = env_name,
      method = method,
      owner = owners[[1L]],
      mutating = mutating,
      call = call
    ))
  }
  return(resolve_backend_ambiguous_env(
    env_name = env_name,
    method = method,
    owners = owners,
    call = call
  ))
}

# --- The backend contract generics ---------------------------------------
# Signatures are the contract documented in ?register_backend. The three of
# `backend_required_hooks` have no default method; the default methods of
# the others are in backend-defaults.R.

#' @keywords internal
#' @noRd
backend_create_env <- function(
  backend,
  packages = NULL,
  env_file = NULL,
  env_name = "condathis-env",
  channels = "conda-forge",
  channel_priority = c("strict", "flexible", "disabled"),
  additional_channels = NULL,
  platform = NULL,
  overwrite = FALSE,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  UseMethod("backend_create_env")
}

#' @keywords internal
#' @noRd
backend_install <- function(
  backend,
  packages,
  env_name = "condathis-env",
  channels = "conda-forge",
  channel_priority = c("strict", "flexible", "disabled"),
  additional_channels = NULL,
  platform = NULL,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  UseMethod("backend_install")
}

#' @keywords internal
#' @noRd
backend_remove_env <- function(
  backend,
  env_name = "condathis-env",
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  UseMethod("backend_remove_env")
}

#' @keywords internal
#' @noRd
backend_list_envs <- function(backend, verbose = "silent") {
  UseMethod("backend_list_envs")
}

#' @keywords internal
#' @noRd
backend_env_exists <- function(backend, env_name, verbose = "silent") {
  UseMethod("backend_env_exists")
}

#' @keywords internal
#' @noRd
backend_list_packages <- function(
  backend,
  env_name = "condathis-env",
  verbose = "silent"
) {
  UseMethod("backend_list_packages")
}

#' @keywords internal
#' @noRd
backend_get_env_dir <- function(backend, env_name = "condathis-env") {
  UseMethod("backend_get_env_dir")
}

#' @keywords internal
#' @noRd
backend_get_install_dir <- function(backend) {
  UseMethod("backend_get_install_dir")
}

#' @keywords internal
#' @noRd
backend_resolve_run <- function(
  backend,
  cmd,
  args = character(0L),
  env_name = "condathis-env",
  verbose = "silent",
  base_env = NULL,
  timeout = Inf
) {
  UseMethod("backend_resolve_run")
}

#' @keywords internal
#' @noRd
backend_resolve_run_in_dir <- function(
  backend,
  cmd,
  args = character(0L),
  env_dir,
  verbose = "silent",
  base_env = NULL,
  timeout = Inf
) {
  UseMethod("backend_resolve_run_in_dir")
}

#' @keywords internal
#' @noRd
backend_available <- function(backend) {
  UseMethod("backend_available")
}

#' @keywords internal
#' @noRd
backend_clean_cache <- function(
  backend,
  verbose = c("output", "silent", "cmd", "spinner", "full")
) {
  UseMethod("backend_clean_cache")
}

#' @keywords internal
#' @noRd
backend_quiesce <- function(backend, timeout = 30) {
  UseMethod("backend_quiesce")
}

#' @keywords internal
#' @noRd
backend_native_platform <- function(backend) {
  UseMethod("backend_native_platform")
}

#' @keywords internal
#' @noRd
backend_can_solve <- function(
  backend,
  packages = NULL,
  env_file = NULL,
  channels = "conda-forge",
  channel_priority = c("strict", "flexible", "disabled"),
  additional_channels = NULL,
  platform
) {
  UseMethod("backend_can_solve")
}

#' @keywords internal
#' @noRd
backend_describe_definition <- function(backend, definition, platform = NULL) {
  UseMethod("backend_describe_definition")
}

#' @keywords internal
#' @noRd
backend_definition_formats <- function(backend) {
  UseMethod("backend_definition_formats")
}

#' Registered backend names, in `condathis.backend_priority` order
#'
#' The default is `"micromamba"` (decision D1): loading a backend package
#' must not change where, or with which solver, a script's new environments
#' are built. Another backend gets new environments only through `method`
#' or this option. A known backend package that the option names is loaded
#' when `method = "auto"` chooses the backend of a new environment (see
#' `resolve_backend_by_priority()`).
#'
#' The option is an ordering hint, not an allowlist: registered backends it
#' does not mention are appended after the prioritized ones. For example,
#' `options(condathis.backend_priority = "rattler")` still resolves to
#' micromamba when only micromamba is registered, instead of aborting with
#' "no backend available".
#'
#' A value that is not a character vector without `NA` warns once per
#' session, with class `c("condathis_invalid_backend_priority_option",
#' "condathis_warning")`, and is ignored: the default applies.
#'
#' @returns Character vector of registered backend names.
#'
#' @keywords internal
#' @noRd
backend_names_by_priority <- function() {
  default_priority <- "micromamba"
  priority <- getOption("condathis.backend_priority", default_priority)
  if (isFALSE(is.character(priority)) || isTRUE(anyNA(priority))) {
    condathis_warn_once(
      id = "invalid_backend_priority_option",
      message = c(
        `!` = "Option {.code condathis.backend_priority} must be a character vector without {.val {NA}}, not {.obj_type_friendly {priority}}.",
        `i` = "The option is ignored, and the default {.val {default_priority}} is used."
      ),
      class = "condathis_invalid_backend_priority_option"
    )
    priority <- default_priority
  }
  registered <- list_registered_backend_names()
  return(unique(c(intersect(priority, registered), registered)))
}
