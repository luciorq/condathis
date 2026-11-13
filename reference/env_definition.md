# Create an environment from a file

Marks a file as the definition of a Conda environment, such as an
environment YAML file or a lock file. Pass the result in the `...` of
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
in place of package specs:
`create_env(env_definition("environment.yml"), env_name = "tools")`.
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
and
[`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md)
take it too (see *Other functions*).

## Usage

``` r
env_definition(path, format = NULL, ...)
```

## Arguments

- path:

  Character string with the path of the file, absolute or relative to
  the working directory. `env_definition()` expands a leading `~`. A
  backend may also accept a directory. URLs are not supported: download
  the file first. A value that is not a single, non-empty string, or a
  URL, aborts with class `condathis_env_definition_invalid_path` (also
  `condathis_invalid_path`).

- format:

  `NULL` (the default), so that the backend detects the format, or a
  single, non-empty string that names it (see *Formats*). Other values
  abort with class `condathis_env_definition_invalid_format`.

- ...:

  Named options for the backend, such as `categories` for a conda-lock
  file. `condathis` passes them on and never reads them. An unnamed or
  repeated option aborts with class
  `condathis_env_definition_invalid_options`.

## Value

An object of class `condathis_env_definition`: a list with `path` (the
absolute path), `format` (`NULL` or a string) and `options` (a named
list).

## Details

`condathis` does not read the file. The backend reads it and tells
`condathis` two things: which format the file has, and whether it is a
request or a lock.

- A request, such as an environment YAML file or a list of package
  specs, is solved when the environment is created. The result depends
  on the channels and on the day.

- A lock, such as an `@EXPLICIT` file or a conda-lock file, lists exact
  packages. It is installed as it is, without a solve, and only for a
  platform it lists.

`env_definition()` makes `path` absolute against the working directory
at the time of the call, so a later
[`setwd()`](https://rdrr.io/r/base/getwd.html) does not change which
file it refers to. It does not resolve symbolic links, so paths in the
file that are relative to the file, such as `-r requirements.txt` in a
`pip:` section, still resolve.
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
checks that the file exists when it runs.

## Formats

Leave `format` as `NULL` and the backend detects the format. Give it
when the file name does not tell, for example for a lock file named
`ci.lock`. `condathis` passes `format` to the backend and never reads
it. These names are a convention: conda uses them for its `--format`
option. Backends should accept them:

- `"environment-yaml"` (also `"cep-24"`): an environment YAML file, with
  `channels:` and `dependencies:`. A request.

- `"requirements"`: a text file with one package spec per line. A
  request.

- `"explicit"`: an `@EXPLICIT` file, with one package URL per line. A
  lock.

- `"conda-lock-v1"`: a conda-lock file, version 1. A lock.

- `"rattler-lock-v6"` and `"rattler-lock-v7"` (also `"pixi"`): a
  `pixi.lock` file. A lock.

- `"mambajs-lock-v1"`: a lock file of mambajs, in JSON. A lock.

The micromamba backend reads environment YAML, requirements,
`@EXPLICIT`, conda-lock version 1 and mambajs files. It detects the
format from the contents of the file, so the file can have any name,
with one exception: an environment YAML file must have a name that ends
in `.yml` or `.yaml`, and not in `-lock.yml` or `-lock.yaml`. It does
not read `pixi.lock` files or directories. For a conda-lock file, it
accepts one option, `categories`: the package categories to install,
`"main"` by default, as in `categories = c("main", "dev")`. A backend
aborts for an option it does not know.

## Locks

For a lock,
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
picks the platform from the platforms that the file lists: `platform`
when it is given, else the native platform of the backend, else an
emulated one (see `platform` in
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)).
When the file lists none of these,
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
aborts with class `condathis_create_env_platform_not_locked` (also
`condathis_create_env_platform_mismatch`) before anything runs. A lock
of `noarch` packages lists no platform, and installs on any platform.
For an `@EXPLICIT` or mambajs file, micromamba takes the platform of
each package from its subdir, such as `noarch` or `linux-64`, not from
the `platform` header of the file. `channels`, `additional_channels` and
`channel_priority` cannot be given with a lock: a lock names its
packages by URL. They abort with class
`condathis_create_env_conflicting_args`. The deprecated `env_file`
argument of
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
ignores them, as in 0.1.4. A lock that lists packages but gives an empty
environment aborts with class `condathis_create_env_failed`.

When the backend reports the packages of a lock, as micromamba does for
`@EXPLICIT`, conda-lock and mambajs files, an existing environment is
compared with them: the same names, versions and build strings, none
missing and none more, for the platform of the lock. Packages that pip
installed are left out. `create_env(overwrite = FALSE)` then keeps an
environment that has exactly those packages, and
`validate_env(env_definition(<lock>), env_name = ...)` returns `TRUE`.

## Other functions

- [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  installs the packages of a request into an existing environment, as
  `micromamba install -f <file>` does. It aborts for a lock, with class
  `condathis_install_packages_unsupported_definition`: create the
  environment again with `create_env(..., overwrite = TRUE)`.

- [`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md)
  compares an environment with a lock (see *Locks*). It aborts for a
  request, with class `condathis_validate_env_unsupported_definition`: a
  request depends on the channels and on the day.

- With `method = "auto"`,
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  creates a new environment with the first available backend in
  `condathis.backend_priority` order that does not say it cannot read
  the file. An explicit `method`, or an existing environment, keeps its
  backend.

## See also

[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)

Other environments:
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md),
[`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md),
[`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md),
[`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md),
[`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md),
[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md),
[`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md),
[`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md),
[`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md)

## Examples

``` r
condathis::env_definition("environment.yml")
#> <env_definition> /home/runner/work/condathis/condathis/docs/reference/environment.yml
condathis::env_definition("ci.lock", format = "conda-lock-v1")
#> <env_definition> /home/runner/work/condathis/condathis/docs/reference/ci.lock (format: conda-lock-v1)
condathis::env_definition("conda-lock.yml", categories = c("main", "dev"))
#> <env_definition> /home/runner/work/condathis/condathis/docs/reference/conda-lock.yml (options: categories)

if (FALSE) { # \dontrun{
condathis::with_sandbox_dir({
  # An environment YAML file shipped with condathis.
  env_file <- system.file("extdata", "stat-env.yml", package = "condathis")
  condathis::create_env(
    condathis::env_definition(env_file),
    env_name = "stat-env"
  )
})
} # }
```
