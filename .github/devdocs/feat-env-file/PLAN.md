# feat-env-file: environment files through `env_definition()`

Written 2026-11-13, after the work landed in the working tree of 0.2.0
(uncommitted on top of `8cffc25`, "feat: prepare condathis 0.2.0 for
CRAN"). Sources: the maintainer's messages of 2026-11-13, a research and
design run (four researchers, three designs, one judge), an
implementation run (core, extension, integration, two adversarial
reviews, repair, verification on four hosts), and the current code. Every
claim about behaviour below was checked against the code of the working
tree; file and line references are to that tree.

Related folders:

- `../post-0.2.0/` item 9a (mixing `env_file` with `packages`). This
  folder replaces that item: package specs and a file still abort
  together, and the file now goes through `env_definition()`.
- `../feat-backend-abstraction/` (the backend contract, decision 4). The
  contract additions below are optional and additive. Its decisions 13
  to 18 record them from the backend author's side, and decision 22 is
  the plan for rattlerthis to opt in.
- `../feat-pixi-backend/` (pixi environments through `env_path()`). The
  pixi findings below (pixi never reads a foreign file directly) are
  written up in its "Files and pixi (2026-11-13)" section and feed its
  "What a pixi backend could add" section.
- `../feat-strict-defaults/PLAN.md`, "Addendum 2026-11-13", section 7:
  where this work touches the 0.2.0 release, and the release steps.
- `../post-0.2.0/` item 18: the rattlerthis follow-ups of this folder
  (items 16 to 19 below), repeated there for the post-release plan.

## Status summary

| # | Item | State |
|---|------|-------|
| 1 | `env_definition()` object | done 2026-11-13 |
| 2 | The backend owns format detection | done 2026-11-13 |
| 3 | Backend contract additions | done 2026-11-13 |
| 4 | micromamba backend: sniffing, staging, options | done 2026-11-13 |
| 5 | `create_env()`: request vs lock | done 2026-11-13 |
| 6 | Platform of a lock | done 2026-11-13 |
| 7 | Channel rules | done 2026-11-13 |
| 8 | Empty-environment check after a lock | done 2026-11-13 |
| 9 | `overwrite = FALSE` and `validate_env()` compare a lock | done 2026-11-13 |
| 10 | `install_packages()` from a request file | done 2026-11-13 |
| 11 | `method = "auto"` routing by the backend's answer | done 2026-11-13 |
| 12 | `env_file =` soft deprecation and file-name hints | done 2026-11-13 |
| 13 | Condition classes | done 2026-11-13 |
| 14 | Docs: NEWS, help pages, articles, pkgdown | done 2026-11-13 |
| 15 | Re-run the two test fixes on omicron and kappa | done 2026-11-13 |
| 16 | Run rattlerthis against this condathis | open |
| 17 | rattlerthis tests that assert no warnings | open, in rattlerthis |
| 18 | rattlerthis opts in to `definition` and describe | open, in rattlerthis |
| 19 | `pixi.lock` in rattlerthis through `rattler_lock` | open, in rattlerthis |
| 20 | URLs in `env_definition()` | out of scope, by decision |
| 21 | Stronger deprecation stages, removal of `env_file =` | not decided |
| 22 | A conda backend | idea |
| 23 | CLI channels vs the channels of a YAML file | needs a decision |
| 24 | Smaller open points | open |
| 25 | Commit the work | maintainer |

## Context

Up to 0.2.0, `create_env(env_file = "environment.yml")` was the only way to
create an environment from a file. The argument was documented as "an
environment YAML file", and the micromamba backend passed it on as
`micromamba create -f <path>`. condathis did not look at the file.

0.2.0 already moved the other "what to create" inputs into `...`: package
specs are positional, and `packages =` is soft-deprecated. Environments
given by path got a classed helper, `env_path()` (`R/env_path.R`), passed in
`env_name`. `env_file =` was the last input that was neither.

The maintainer asked whether `env_file =` could follow `env_path()`. The
research for that question found real defects in how 0.2.0 handled files
(see *Findings*), so the change became more than a rename.

## Decisions, in order

All on 2026-11-13.

**D1. The question.** The maintainer asked: "Out of curiosity would it be
hard to deprecate the `env_file = "x.yml"` in favor of an accessory
function like we did for the path environments?"

The first answer: about half a day of work, but a smaller gain than
`env_path()`, because `env_file =` is already a named argument with one
meaning. It sketched a helper called `env_yaml()` and recommended leaving
the change out of 0.2.0.

**D2. No format in the name, and a design open to backends.** The
maintainer: "Newer versions of conda and micromamba accepts other file
formats outside of of the traditional environments.yaml, so env_yaml() is
not a good name. There are the conda lock files, txt, and other proposals,
so we need a generic name that does not depend on the extension.
Additionally, does it make sense for rattler / pixi to accept specs from
files? How they handle that? How would be the overall design pattern that
do not limit the backend extensions?"

This started a research run (conda, micromamba, rattler and pixi,
condathis internals), three independent designs and a judge:

| Design | Correctness | Extensibility | User clarity | Migration cost | Risk |
|---|---|---|---|---|---|
| A: `env_file()`, minimal | 4 | 2 | 3 | 5 | 5 |
| B: `env_spec()`, inspect hook | 4 | 5 | 3 | 3 | 3 |
| C: `env_definition()`, request/lock | 3 | 4 | 4 | 3 | 3 |

(1 to 5, higher is better.) The judge took C's name and its request/lock
split, B's capability hook and staging, and A's release caution. Its
release plan: in 0.2.0 only reword the docs and widen the file-name hint;
export `env_definition()` in 0.3.0; compare locks, install from files and
route `method = "auto"` in 0.4.x.

**D3. Everything in 0.2.0, `env_file =` deprecated.** The maintainer (typos
fixed): "I want all of it implemented now in v0.2, deprecate env_file". So
0.2.0 got the judge's 0.3.0 scope and its "later" scope (items 9, 10 and
11). The maintainer gave no reason. The argument for doing it now that
the first answer (D1) had listed: 0.2.0 already asks users to rewrite
`create_env(packages = ...)` calls, so one release means one rewrite.

**D4. rattlerthis keeps working unchanged.** This was a hard rule of the
implementation brief: the rattlerthis repository was not touched in this
round, so condathis had to accept rattlerthis's backend as it is. The rule
caused three of the deviations in *Deviations from the judge design*. The
deviations were reported to the maintainer with the implementation
summary on 2026-11-13.

**D5. Dev docs, not only notes.** The maintainer: "Don't add decision only
to memory. Update the dev docs at .github/devdocs/ with all new features
and design decisions." and "You can create a separate feat-env-file for
those docs. But also update relevant places in the other directories".
This folder is the result.

## Findings (research of 2026-11-13)

### Formats and tools

"name" means the tool picks the format from the file name, "content" from
the contents. "(u)" marks a cell that was not verified.

| Format | conda 26.9.4 + conda-lockfiles 0.2.2 | micromamba 2.10.0 | rattler crates / rattlerthis | pixi 0.84.2 |
|---|---|---|---|---|
| environment.yml (CEP 24) | yes, built in | yes, by name `.yml`/`.yaml` | crate `EnvironmentYaml`; rattlerthis yes, own parser, by name | import only (`pixi init --import`, `pixi import --format conda-env`) |
| MatchSpec list (CEP 23) | yes (`requirements.txt` format) | yes, any other name without an `@EXPLICIT` line | rattlerthis yes; crate parses MatchSpecs only | no: its `.txt` means pip requirements |
| `@EXPLICIT` (CEP 23) | yes (lockfile category) | yes, by content, inside the text path | crate `ExplicitEnvironmentSpec`; rattlerthis yes, no solve | no import (verified); can export it |
| conda-lock v1 (CEP 37) | yes, through conda-lockfiles | only when named `*-lock.yml`/`.yaml` | crate `rattler_lock` with the `conda-lock` feature (u); rattlerthis yes, by name | no import (u) |
| pixi.lock v6 | yes, through conda-lockfiles (`rattler-lock-v6`, alias `pixi`), "default" environment only | no: read as MatchSpecs | crate yes; rattlerthis no (classed as a spec list) | native, needs its manifest next to it |
| pixi.lock v7 | no: "field 'version' ... less than or equal to 6" | no ("unknown version '7'" or a misread) | crate yes (`FileFormatVersion::V7`); rattlerthis no | native (writes v7), needs its manifest |
| mambajs `.json` lock | no plugin found (u) | yes, by name `.json` | rattlerthis yes, own parser | no (u) |
| pip requirements.txt | not as an environment input (u) | misread as MatchSpecs | YAML `pip:` sections in rattlerthis only | yes (`pixi import --format pypi-txt`) |
| pixi.toml / workspace directory | no | no | crate no | native |

How each tool picks the format:

- **conda.** `-f/--file` of `conda create`, `install` and `update` sends
  the file to an "environment specifier" plugin (hook
  `conda_environment_specifiers`, marked experimental). Without `--format`,
  conda matches the base name against each plugin's `default_filenames`,
  then falls back to content detection (`can_handle()`). More than one
  match is an error. `--format NAME` (new in 26.9) skips detection. Plugins
  are tagged `environment` (solved) or `lockfile` (installed without a
  solve). A file with a custom name was detected from its contents,
  although `--help` says custom names need `--format`. A lockfile plus
  extra package names is refused on a real run, and silently ignored with
  `--dry-run`.
- **micromamba 2.10.0.** Name only, in this order
  (`libmamba/src/api/install.cpp`, `file_specs_hook`;
  `libmamba/src/core/env_lockfile.cpp`): `.json` is a mambajs lock;
  `-lock.yml`/`-lock.yaml` is conda-lock v1; other `.yml`/`.yaml` is an
  environment YAML file; anything else is text. Text is read as
  `@EXPLICIT` when a line starts with `@EXPLICIT`, else as one MatchSpec
  per line. The comparison is case-sensitive: `ENV.YML` is text. Upstream
  `main` had the same code as 2.10.0 on 2026-11-13.
- **rattlerthis.** The same name rules as micromamba
  (`src/rust/src/envfile.rs` in rattlerthis), with its own parsers so that
  it matches micromamba's quirks. Request files are solved; `@EXPLICIT` and
  lock files are installed without a solve. No `pixi.lock`: it is classed
  as a spec list.
- **pixi.** Never installs a foreign file as it is. `pixi import` and
  `pixi init --import` convert a file into pixi's own manifest, trying each
  format in turn. `pixi install --frozen` installs `pixi.lock` without a
  solve, but only with a `pixi.toml` next to it. `pixi exec` and
  `pixi global install` take specs on the command line only.

Answer to the maintainer's question "does it make sense for rattler / pixi
to accept specs from files?": yes. rattlerthis already does, for the same
formats as micromamba. The rattler crates have typed readers for all of
them and for `pixi.lock` v1 to v7 (`rattler_lock::LockFile`). A pixi-style
backend would want a workspace directory, or a `pixi.lock` plus the name of
an environment in it. That is one more reason the helper cannot assume
"one file with a known extension".

### micromamba behaviours found in isolated runs

micromamba 2.10.0 (and 2.8.1 where noted), with `HOME`, the `XDG_*`
variables and `MAMBA_ROOT_PREFIX` in scratch directories, against the
local `polyglot` test channel (`file://`):

1. A conda-lock file not named `*-lock.yml` (for example `mylock.yml`) is
   read as an environment YAML file: "Empty environment created at
   prefix", exit status 0.
2. A well-formed conda-lock v1 file without packages for the target
   platform also gives an empty environment with exit status 0. It only
   warns "Selected packages for category 'main' are empty".
3. `micromamba create --dry-run --json -f <lock>` returns `success: true`
   with no actions without reading the file, also for an invalid lock
   (`libmamba/src/api/create.cpp`, early return with no specs). condathis
   used this dry run in `backend_can_solve()`, so the check answered TRUE
   for any lock. `--dry-run` without `--json`, and `install --dry-run
   --json`, do read it.
4. Package specs on the command line are dropped without a message for an
   `@EXPLICIT` file or a lock (`create -f explicit.txt zlib` installed only
   `polyglot`). For an environment YAML file or a spec list they are merged
   into the request. The old comment in `create_env()` said they were
   always dropped.
5. Several `-f` files: YAML and spec lists are concatenated; with
   `@EXPLICIT` the first explicit file wins; with locks the last one wins;
   mixing kinds aborts with "found multiple spec file types".
6. `pixi.lock` under its own name goes down the text path. Lines such as
   `- url:` become specs, and micromamba fetched from conda.anaconda.org
   despite `--override-channels -c file://...`. Renamed `pixi-lock.yml` it
   fails with "unknown version '7'"; renamed `pixi.lock.yml` it gives an
   empty environment with exit status 0.
7. When name and content disagree, the name wins: YAML in a `.txt` fails
   with 'Error parsing MatchSpec "": Empty package name.'; `@EXPLICIT` in a
   `.yml` fails in yaml-cpp.
8. An `@EXPLICIT` or mambajs file of `noarch` packages installs on any
   platform, whatever its `# platform:` header or `platform` field says
   (re-checked in the repair round).
9. The channels of a YAML file come after the `-c` channels, even with
   `--override-channels`.
10. `update -f <lock>` ignores the lock and runs a normal update against
    the default channels. `install -f` works with YAML, spec lists,
    `@EXPLICIT` and locks (checked on 2.8.1 and 2.10.0 for YAML and spec
    lists, including a YAML with its own channels and a `name:` field).
11. `--category` exists in 2.10.0 and in the 2.8.1 minimum version: no
    flag installs `main`, `--category dev` installs `dev`,
    `--category main dev` installs both.
12. A YAML file and a lock can be given as a URL (anything with `://` is
    downloaded first). A plain text path is not downloaded.

## Naming

**Chosen: `env_definition()`.** It names the role of the file, not its
format, so it covers YAML, spec lists, `@EXPLICIT`, conda-lock, `pixi.lock`
and later a directory. It matches conda's wording: `conda env create -f`
calls its input an "environment definition file".

Rejected, with the reason:

- `env_yaml()`: names one format (the maintainer's objection in D2). The
  same goes for `env_lock()` and `env_txt()`.
- `env_spec()`: conda's own umbrella term, but condathis already calls the
  strings in `...` "package specs", and users would write
  `env_spec("python>=3.12")`.
- `env_file()`: the same name as the argument it replaces, and it does not
  fit a directory.
- `env_input()`: the CEP wording ("input files"), but vague.
- `env_source()`: "source" already means source packages in pixi and
  rattler.

## Design as implemented

### 1. The object

`env_definition(path, format = NULL, ...)` (`R/env_definition.R:134`)
returns a classed list, like `env_path()`:

```r
structure(
  list(path = "<absolute path>", format = NULL, options = list()),
  class = "condathis_env_definition"
)
```

- `path` goes through `fs::path_expand()`, `fs::path_abs()` and
  `fs::path_norm()`, never `fs::path_real()`
  (`normalize_definition_path()`, `R/env_definition.R:237`). Paths in a
  `pip:` section, such as `-r requirements.txt`, are relative to the file
  as the user named it.
- A URL (a scheme followed by `://`, `is_url_path()`,
  `R/env_definition.R:222`) aborts with a hint to download the file first.
  Windows paths such as `C:/x` are not URLs.
- `format` is `NULL` or one non-empty string. condathis never reads it.
- `...` holds named options for the backend, such as `categories`. Unnamed
  or repeated options abort.
- `format()` and `print()` methods print
  `<env_definition> /abs/path (format: ...; options: ...)`.
- The object is checked again where it is used
  (`validate_env_definition_object()`, `R/env_definition.R:325`), because
  it can be built or changed by hand. The file must exist at use time
  (`check_env_definition_exists()`, `R/env_definition.R:398`), with the
  0.1.4 missing-file classes.
- Only unnamed elements of `...` count (`split_env_definitions()`,
  `R/env_definition.R:436`). A named one, such as
  `packages = env_definition(...)`, stays with the package specs and is
  rejected there as "an environment definition from env_definition()"
  (`package_specs_problem()`, `R/validate_args.R:322`).
- condathis 0.1.4 and any code that does not know the class reject a list
  in `...`, so an object passed to an older condathis fails instead of
  being used as a spec.

The recommended `format` names follow conda's `--format` names:
`environment-yaml` (also `cep-24`), `requirements`, `explicit`,
`conda-lock-v1`, `rattler-lock-v6` and `rattler-lock-v7` (also `pixi`), and
`mambajs-lock-v1`. They are a convention in the help page, not a list that
condathis enforces.

### 2. The backend owns the formats

condathis keeps no list of formats. It understands one thing the backend
reports: whether the file is a **request** (solved, like package specs) or
a **lock** (exact packages, installed without a solve, tied to a
platform). Its own rules (items 5 to 11) apply to that kind. A new format,
such as `pixi.lock` v7 or a future CEP, needs a change in the backend only.
This follows conda's environment-specifier plugins.

### 3. Backend contract additions

All optional. A backend written for the 0.2.0 contract registers and works
unchanged.

- **`backend_describe_definition(backend, definition, platform = NULL)`**,
  a new optional hook (`backend_optional_hooks`, `R/backend.R:28-42`;
  contract text `R/backend.R:515-564`). It returns
  `list(supported, format, kind, platforms, reason, records)`:
  `supported` is TRUE, FALSE or NA; `kind` is `"request"`, `"lock"` or NA;
  `platforms` lists the platforms a lock has packages for (without
  `noarch`); `records` is a data frame with `name`, `version`,
  `build_string` and `platform`, one row per package of a lock. It must be
  cheap: read the file, but never download, install, solve or change an
  environment. It must refuse an option it does not understand, never
  ignore it. An error counts as NA
  (`backend_describe_definition_checked()`, `R/backend-query.R:527`). A
  value of the wrong shape aborts with `condathis_backend_invalid_return`
  (`validate_definition_description()`, `R/backend-query.R:433`; test
  `test-env_definition.R:660`).
  Default (`R/backend-defaults.R:313`): NA, or FALSE when the definition
  has a `format` or options and the backend's `backend_create_env()` has
  no `definition` argument. NA means exactly the 0.2.0 behaviour: the path
  goes to the backend and condathis checks nothing else.
- **`backend_definition_formats(backend)`**, a new optional hook. It
  returns format names and is used only in error hints: an error for a
  definition with a `format` names the registered backends that list it
  (`definition_format_hint()`, `R/env_definition_checks.R:110`). Default
  `character(0)` (`R/backend-defaults.R:336`). condathis never decides
  anything from it.
- **New optional arguments**, listed in `backend_optional_args`
  (`R/backend.R:1204-1210`): `definition` for `backend_create_env()`,
  `backend_install()` and `backend_can_solve()`, and `env_file` for
  `backend_install()`. condathis always passes the path as `env_file` to
  `backend_create_env()` and `backend_can_solve()`, as before.
- **How the optional arguments reach a backend.** The generics keep their
  0.2.0 formals. rattlerthis's `tests/testthat/test-registration.R`
  (lines 44 to 50) asserts that its functions have formals `identical()`
  to the generics, so adding `definition` to a generic would break that
  unchanged test.
  - `backend_call()` (`R/backend.R:1311`) calls the backend's own function
    with an optional argument only when that function takes it by name or
    through `...`. Otherwise it calls the generic as before.
  - `backend_s3_method()` (`R/backend.R:1253`): `register_backend()`
    registers a wrapper with exactly the generic's formals for a function
    that has extra optional arguments (the micromamba functions). R CMD
    check flagged S3 methods whose formals differ from the generic, first
    as a WARNING, then as an internal error when the wrapper body embedded
    the closure; the wrapper now keeps the function in its environment. A
    function without extra arguments (rattlerthis's) is registered as
    itself.
  - `backend_resolve_args()` (`R/backend.R:1224`) still serves `timeout`.
- **`backend_install()` and files.** `install_packages()` passes a file
  only to an install function that takes `env_file` or `definition`
  (`definition_formal_problem()`, `R/env_definition_checks.R:36`). One
  that takes neither, such as rattlerthis's, makes `install_packages()`
  abort before any call with "The backend does not install packages from
  a file." One that takes only `env_file` gets the path, and a `format` or
  options then abort.

### 4. The micromamba backend

Code in `R/backend-micromamba-definition.R`. The backend object registers
`micromamba_backend_describe_definition()` and
`micromamba_backend_definition_formats()` (`R/backend-micromamba.R`).

**Content sniffing** (`micromamba_sniff_definition()`, line 299), a text
search without a YAML parser (`yaml` is not in Imports), in this order:

1. JSON (first non-blank character `{`): mambajs when it has a
   `"lockVersion"` field, else refused.
2. An `@EXPLICIT` line: explicit.
3. Top-level `version:` and `environments:`: `pixi.lock`, refused with a
   reason ("micromamba does not read pixi.lock files ...").
4. Top-level `version:` and `package:`: conda-lock; version 1 is read,
   another version is refused.
5. A top-level key of an environment YAML file (`name:`, `channels:`,
   `dependencies:`, `variables:`, `prefix:`), or a name ending in `.yml` or
   `.yaml`: environment YAML.
6. Anything else: a spec list (`requirements`).

A directory is refused. A file that cannot be read gives NA, so the old
path applies. A given `format` is matched in any case against the names and
aliases (`micromamba_format_aliases`, line 37); an unknown name, a
`rattler-lock-*`/`pixi` name, or a lock format that contradicts the
contents gives FALSE with a reason. `backend_definition_formats()` returns
`environment-yaml`, `requirements`, `explicit`, `conda-lock-v1`,
`mambajs-lock-v1` and `cep-24`.

**Staging** (`micromamba_definition_file()`, line 705). When the file name
is not one micromamba reads as the detected format
(`micromamba_name_kind()`, line 351, case-sensitive like micromamba), the
backend passes a copy in a `withr` temporary directory under
`requirements.txt`, `explicit.txt`, `conda-lock.yml` or
`mambajs-lock.json`, deleted when the backend function exits. An
environment YAML file under a wrong name is refused with a rename hint
instead: a copy elsewhere would break `-r` paths in its `pip:` section.

**Options.** Only `categories`, for a conda-lock file, mapped to
`--category` (finding 11). Any other option, or `categories` on another
format, is refused.

**Platforms and records of a lock.**

- `@EXPLICIT` (`micromamba_explicit_info()`, line 421): the platform of
  each record is the subdir of its URL when it is a known platform, else
  the `# platform:` header. `platforms` are the record platforms other
  than `noarch`. A file of only `noarch` packages lists no platform.
- conda-lock (`micromamba_conda_lock_info()`, line 494): the per-package
  `platform:` field, which is what micromamba selects by. Items of another
  manager (pip) are left out of the records. Records are filtered by the
  categories. A line reader for conda-lock's block style
  (`read_conda_lock_items()`); CRLF and a UTF-8 BOM were checked.
- mambajs (`micromamba_mambajs_info()`, line 613): the package `subdir`
  when it is a known platform, else the file's `platform` field.

**Where the file goes.** `micromamba_backend_create_env()` and
`micromamba_backend_can_solve()` take `definition` and use the staged path
plus the extra arguments. `micromamba_backend_install()` takes `env_file`
and `definition`, runs `micromamba install -f`, never `update -f`
(finding 10), and refuses a lock with `condathis_backend_unsupported`.

### 5. `create_env()`: request vs lock

`create_env()` (`R/create_env.R:286`):

1. Splits definitions out of `...` before the package specs are checked.
2. `resolve_create_definition()` (`R/create_env.R:810`) aborts with
   `condathis_create_env_conflicting_args` for two definitions, for a
   definition plus `env_file`, and for package specs plus a file (for every
   kind, because micromamba merges specs for some kinds and drops them for
   others, finding 4). It turns `env_file` into
   `env_definition(env_file)` after the deprecation warning (item 12).
3. Before the environment lock, it resolves the backend once and asks it
   to describe the definition (`describe_create_definition()`,
   `R/create_env.R:964`). FALSE aborts with
   `condathis_create_env_unsupported_definition`. So does a backend
   function that cannot take a `format` or options. Under the lock it
   resolves again, and describes again only if another session created the
   environment with another backend in between. Descriptions are cached
   per backend (`create_definition_routing()`, `R/create_env.R:899`).
4. **Request:** the 0.2.0 path. `definition` reaches `backend_can_solve()`
   through `define_platform()`, so the emulation fallback works as for
   specs.
5. **Lock:** never sent to `backend_can_solve()` (finding 3). The platform
   comes from item 6, the channel rule from item 7, and the empty check
   from item 8.
6. **NA:** exactly the 0.2.0 behaviour.

### 6. Platform of a lock

`choose_lock_platform()` (`R/create_env.R:1042`), before any lock, move or
solve:

- `platform` when given, if the lock lists it;
- else the backend's native platform, if listed;
- else the emulated platform (`osx-64` under Rosetta 2 on Apple Silicon,
  `win-64` on Windows on ARM), if listed;
- else abort with `condathis_create_env_platform_not_locked` (also
  `condathis_create_env_platform_mismatch`).

A lock that lists no platform (only `noarch` packages, or no platform
data), or a backend whose native platform is NA, leaves the choice to the
backend; item 8 is then the only guard.

### 7. Channel rules

- `channels`, `additional_channels` or `channel_priority` given with a
  lock from `env_definition()` abort with
  `condathis_create_env_conflicting_args`: a lock names the channel of
  each package and both backends ignore CLI channels for it. "Given" means
  not `missing()` (`R/create_env.R:305-309`).
- The deprecated `env_file =` keeps 0.1.4 behaviour: the channel arguments
  are passed on and the backend ignores them for a lock
  (`R/create_env.R:362-366`).

### 8. Empty-environment check after a lock

`check_lock_installed()` (`R/create_env.R:1138`) runs inside
`with_env_dir_replacement()`. When the lock has records for the target
platform (or `noarch`, or no platform) and `backend_list_packages()` shows
an empty environment, it aborts. `with_backend_errors()` reports that as
`condathis_create_env_failed`, and an environment replaced with
`overwrite = TRUE` is restored. This closes findings 1, 2 and 6.

### 9. `overwrite = FALSE` and `validate_env()` compare a lock

For a lock whose records name every package (`lock_records_comparable()`,
`R/env_definition_checks.R:349`), an existing environment is compared by
`<name>-<version>-<build>` strings, names in lower case, for the target
platform plus `noarch` and records without a platform. Packages from
channel `pypi` are left out. Without a target platform, any platform of
the lock can match (`compare_lock_records()`, line 413).

- `create_env(overwrite = FALSE)` (`keep_existing_env()`,
  `R/create_env.R:1752`) keeps the platform check first. A matching lock
  returns status 0 without a backend call; a mismatch aborts with
  `condathis_create_env_exists` and names up to five packages per side
  plus "and N more" (`lock_difference_bullets()`). A request, or a lock
  without full records, aborts with `condathis_create_env_exists` as
  before.
- `validate_env(env_definition(<lock>), env_name = ...)`
  (`R/validate_env.R:181`) returns TRUE, or FALSE with reason
  `"unsatisfied"`, the missing records in `unsatisfied` and a new
  attribute `unexpected`. With `error = "cancel"` it aborts with
  `condathis_validate_env_unsatisfied`. A request, an NA description, a
  lock without records, or a `platform` the lock does not list aborts with
  `condathis_validate_env_unsupported_definition`, for either value of
  `error`: a request depends on the channels and the day, so it is never
  compared.

### 10. `install_packages()` from a request file

`install_packages(env_definition("environment.yml"), env_name = ...)`
(`R/install_packages.R:158`) installs the packages a request file asks
for into an existing environment, as `micromamba install -f` does. A lock
aborts with `condathis_install_packages_unsupported_definition` and a hint
to use `create_env(env_definition(...), overwrite = TRUE)`
(`check_install_definition()`, `R/install_packages.R:483`). Two
definitions, or a definition plus specs, abort with
`condathis_install_packages_conflicting_args`. The previous-channels
warning is skipped for a file, which can name its own channels. Finding 10
is why `update -f` is never used.

### 11. `method = "auto"` routing

For a new environment and `method = "auto"`, `resolve_backend()` skips an
available backend whose description says FALSE and takes the next one in
`condathis.backend_priority` order (`resolve_backend_by_priority()`,
`R/backend.R:1724`, arguments `accept` and `on_refused`). NA counts as
"can read". When every available backend refuses, `create_env()` aborts
with `condathis_create_env_unsupported_definition`, naming each backend and
its reason, plus the formats hint
(`abort_no_backend_for_definition()`, `R/env_definition_checks.R:189`).
An explicit `method`, or an environment that already exists, never changes
backend. This mirrors how `env_path()` routing skips a backend without
`backend_resolve_run_in_dir()`.

### 12. `env_file =` soft deprecation and file-name hints

- `create_env(env_file = path)` warns once per session with class
  `condathis_deprecated_env_file_arg`, then behaves as
  `create_env(env_definition(path))` except for item 7
  (`R/create_env.R:858-869`). It uses `condathis_deprecate_soft()`, the
  same rule as `packages =` (`R/conditions.R:220-277`): it warns for calls
  from the global environment and from the tests of the package named in
  `TESTTHAT_PKG`; calls inside another package are silent;
  `lifecycle_verbosity = "quiet"` silences it and `"warning"` or `"error"`
  makes every call direct. An invalid `env_file` aborts before the
  warning.
- A spec that looks like a file name now matches
  `\.(ya?ml|json|lock)$`, case-insensitive (`is_env_file_name()`,
  `R/validate_args.R:308`), so `conda-lock.yml`, `env.json` and
  `pixi.lock` are caught. Every hint now says `env_definition("<file>")`.
- `env_definition()` objects given to functions that take only names
  abort with that function's own invalid-argument class.

### 13. Condition classes

New:

- `condathis_env_definition_invalid_path` (also `condathis_invalid_path`),
  `condathis_env_definition_invalid_format`,
  `condathis_env_definition_invalid_options`: the constructor.
- `condathis_env_definition_invalid`: a malformed object, checked at use.
- `condathis_create_env_unsupported_definition`,
  `condathis_install_packages_unsupported_definition`,
  `condathis_validate_env_unsupported_definition` (with
  `condathis_backend_unsupported` when the backend refused, and
  `condathis_invalid_arg`).
- `condathis_create_env_platform_not_locked` (also
  `condathis_create_env_platform_mismatch`).
- `condathis_install_packages_conflicting_args`,
  `condathis_validate_env_conflicting_args`,
  `condathis_install_packages_missing_env_file`,
  `condathis_validate_env_missing_env_file`.
- `condathis_deprecated_env_file_arg` (warning).

Widened: `condathis_create_env_conflicting_args` (definition plus specs,
two definitions, definition plus `env_file`, channel arguments with a
lock), `condathis_create_env_exists` (a lock that does not match),
`condathis_create_env_failed` (an empty environment from a lock) and
`condathis_validate_env_unsatisfied` (locks, `unexpected`). All are listed
in `?condathis-conditions`.

### 14. Docs

NEWS.md 0.2.0 (the `env_file` deprecation next to `packages =`, the
widened file-name hint, the `overwrite = FALSE` and conflicting-args
bullets, three New features bullets, and a Bug fixes bullet for the empty
environments of findings 1 and 2); `?env_definition` (new, in the
"environments" family and the pkgdown reference index); `?create_env`,
`?install_packages`, `?validate_env`, `?register_backend`,
`?condathis-conditions`, `?get_install_dir`, `?condathis-package`;
`vignettes/condathis.qmd` (Next steps);
`vignettes/articles/python-and-reticulate.qmd` (the YAML example now uses
`env_definition()`); `inst/extdata/README.md`; `inst/WORDLIST` (mambajs).
README.qmd had no `env_file` use and was not changed.

## Deviations from the judge design

1. **Release scope.** The judge planned docs only for 0.2.0, the export
   for 0.3.0 and items 9 to 11 for 0.4.x. Decision D3 put all of it in
   0.2.0.
2. **Generics keep their formals.** The judge added `definition` to the
   generics and listed it in `backend_optional_args`. That passes
   registration but fails rattlerthis's `test-registration.R`, which
   compares formals with `identical()`. Fixed with `backend_call()` and
   `backend_s3_method()` (item 3); the second was needed for R CMD check.
3. **`backend_install()` got an optional `env_file`.** The judge's "pass
   `env_file` only" could not apply: `backend_install()` had no file
   argument.
4. **`env_file =` keeps the 0.1.4 channel behaviour.** The judge said
   `env_file` "becomes `env_definition(path)`, so behaviour is identical".
   The first implementation made `env_file = <lock>` plus `channels` abort.
   Both reviewers found that this breaks rattlerthis's unchanged parity
   tests (`test-parity-envfile.R`, fixtures e6, e7, e9, e10, e11), which
   pass `channels` with `@EXPLICIT` and conda-lock files and expect
   success. The repair restored the 0.1.4 behaviour for `env_file =` only
   (item 7).
5. **Lock platforms from package subdirs.** The judge took the platforms
   of `@EXPLICIT` and mambajs files from the header or `platform` field.
   The reviewers found that a `noarch`-only file with a `linux-64` header
   (rattlerthis fixtures e6 and e10) was refused on macOS and Windows,
   while micromamba installs it there (finding 8). The repair takes each
   record's platform from its subdir (item 4).
6. **NEWS bug-fix wording.** The first text said "a lock file for another
   platform" gave an empty environment. That is false for `@EXPLICIT`
   files (finding 8). Narrowed to conda-lock files, after a raw
   micromamba check with a well-formed conda-lock v1 file (finding 2).
7. **Describe before the lock.** The judge did not say how to get a
   backend before the environment lock. `create_env()` resolves once
   before and once under the lock, with descriptions cached per backend
   (item 5).
8. **Sniffing order.** JSON is checked first, then `@EXPLICIT`, then
   `pixi.lock`, then conda-lock (the judge listed `@EXPLICIT` first).
   Unknown conda-lock versions and other JSON are refused with reasons;
   an unreadable file gives NA.
9. **Code layout.** The micromamba part is in a new file,
   `R/backend-micromamba-definition.R`, and the shared checks and lock
   comparison in `R/env_definition_checks.R`.
10. **Extra condition classes** for `install_packages()` and
    `validate_env()` (item 13), which the judge's 0.3.0 list did not have
    because those functions only rejected the object there.

## Verification (2026-11-13)

Every run used a copy of the tree and isolated `HOME`, `XDG_*` and
`TMPDIR`, with micromamba 2.10.0.

- **Linux (local, R 4.5.3):** developer suite after the repair and again
  after the two test fixes: 68 files, 1152 tests,
  `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 8680 ]` (before this work: 8045
  passed). `R CMD check --as-cran` with the PDF manual: Status OK with
  `_R_CHECK_SYSTEM_CLOCK_=FALSE`; without it, the only NOTE is "unable to
  verify current time", because the time servers could not be reached
  from this host. Examples with `run_dontrun = TRUE`, spelling and
  urlchecker: clean.
- **Docker:** R-devel (2026-11-12 r90880) `--as-cran` with the PDF
  manual, also with `_R_CHECK_DEPENDS_ONLY_=true` and the incoming extras:
  Status OK. R 4.6.2: Status OK. R 4.3.3: Status OK with the clock check
  off. R-devel developer suite: 8680 passed, 0 skipped. Offline
  (`--network none`): 7196 passed, 206 skipped, all "offline".
- **macOS (omicron, R 4.6.1):** one failure, `test-env_definition.R:93`:
  after `setwd()`, `getwd()` gives `/private/var/...` while the test built
  `/var/...` from `withr::local_tempdir()`. A test bug, fixed by comparing
  against `getwd()`. Everything else passed: developer suite 8677 passed,
  CRAN-mode tests 34.1 s. End-to-end probe with the installed tarball: 23
  checks OK, 0 bad (`@EXPLICIT` and conda-lock creates, run, validate TRUE,
  `overwrite = FALSE` keeps, `format` given, a linux-64 lock aborts with
  `platform_not_locked`, channels abort, `validate_env()` on YAML aborts,
  `env_file =` warns and works).
- **Windows (kappa, R 4.6.1):** `R CMD check --as-cran --no-manual`:
  Status OK. Developer suite: 8638 passed, 0 failed, 1 skip:
  `skip_on_os("windows")` in the symlink test of
  `test-env_definition.R`. With that line removed on kappa the test
  passed, so the skip was removed (zero-skip rule). CRAN-mode tests:
  120.4 s, against 115.6 s before. End-to-end: `create_env()` and
  `validate_env()` from a win-64 `@EXPLICIT` file with a backslash path
  and `file:///C:/` URLs worked.
- **After the two test fixes (item 15, done 2026-11-13):**
  - Linux: developer suite 8680 passed, 0 failed, 0 skipped;
    `test-env_definition.R` alone also passes in CRAN mode (287
    expectations).
  - macOS (omicron, default `/var/folders` temporary directory):
    `R CMD check --as-cran --no-manual` Status OK; developer suite 8678
    passed, 0 failed, 0 skipped; CRAN-mode tests 35.2 s, all 333 skips
    "On CRAN", none in `test-env_definition.R`.
  - Windows (kappa): `R CMD check --as-cran --no-manual` Status OK
    (tests 128 s inside the check); developer suite 8639 passed, 0
    failed, 0 skipped. The symlink test now runs there.
- **Adversarial review:** a matrix of every format, conflict, path and
  option case on real micromamba; rule R2 checked by mocking
  `native_cmd()`, `install_micromamba()`, `micromamba_bin_path()` and
  `processx::run()` to fail during describe (0 calls); no staged
  `condathis-definition-*` directories left behind; `options(warn = 2)`
  turns the deprecation into an error before any backend call.
- **CRAN-mode time:** about 6 to 7 s more on Linux, nearly all of it in
  `test-env_definition.R` (no test over 1 s). The host was loaded during
  the final runs; a back-to-back pair with the previous tree put the
  increase near 10 % (estimate).

### Not verified

- **rattlerthis was never built or run against this condathis.** The
  Linux host had no `pkg-config` and too little disk for a Rust build;
  the other hosts were not tried. Compatibility rests on reading its code,
  a stub backend in condathis's tests with rattlerthis's exact formals
  (including an `identical()` formals check), and a replay of the
  micromamba half of its parity tests with its own fixtures against the
  committed tree (HEAD), the first implementation and the repaired tree.
  The repaired tree matched HEAD in every case, apart from the
  deprecation warning. The rattler half was not run.
- What raw micromamba does with an `@EXPLICIT` file whose URLs use the
  arch subdir of another platform. condathis aborts with
  `platform_not_locked` before any work.
- The order of a YAML file's channels against `channels` in
  `install_packages()` from a file.
- conda-lock files with pip items, and lock comparison for pip packages.

## Out of scope and follow-ups

**15. Re-run the two test fixes on omicron and kappa.** Done
2026-11-13: zero failures and zero skips on Linux, macOS and Windows,
and Status OK on macOS and Windows (see *Verification*). Re-run only if
package files change before submitting.

**16. Run rattlerthis against this condathis.** On a machine that can build
it. Expect item 17 and nothing else.

**17. rattlerthis tests that assert no warnings.**
`tests/testthat/test-parity-envfile.R:98`
(`expect_identical(seen[[method]]$warnings, list())`) and
`test-parity-linkscripts.R` (about line 320, `expect_length(out$warnings,
0L)`) fail when run alone or first, because the first `env_file =` call
now warns. In a full serial run the first call is in
`test-condathis-conformance.R` (about line 1031), which then shows one
testthat WARN. Fix in rattlerthis: set `lifecycle_verbosity = "quiet"` for
those calls, or move them to `env_definition()`. This is what a soft
deprecation does, so condathis does not change.

**18. rattlerthis opts in.** Add `definition` to its create, install and
can_solve functions and a `backend_describe_definition()` built on
`rt_read_env_file()`, which already knows request vs lock and the
platforms. Also `backend_definition_formats()`. About a day. Until then,
rattlerthis gets NA (old behaviour) for plain definitions and refuses a
`format` or options.

**19. `pixi.lock` in rattlerthis through `rattler_lock`.**
`LockFile::from_path()` reads v1 to v7, and
`Environment::conda_repodata_records(platform)` feeds the existing
no-solve install path. The cost is new crates (pep440/pep508 and others),
vendor size and MSRV, not measured; estimated two to three days or more.
Source packages and PyPI entries would need a refusal or the pip step.
Selecting an environment would use an option, such as
`env_definition("pixi.lock", environment = "test")`.

**20. URLs in `env_definition()`.** Out of scope by decision: describe must
never download (rule R2), and CRAN has rules about downloads. URLs abort
with `condathis_env_definition_invalid_path` and a hint to download first.
Adding them later needs no rename.

**21. Deprecation stages and removal.** Not decided. The judge suggested:
move to a plain warning in a later release, remove the front-end
`env_file =` no earlier than two releases after that, and keep the
backend-level `env_file` argument until a contract version that
rattlerthis has adopted.

**22. A conda backend.** Idea only. conda 26.9 with conda-lockfiles reads
`pixi.lock` v6 and detects formats by content, so such a backend would
read more formats than micromamba. Nothing is planned.

**23. CLI channels vs the channels of a YAML file.** micromamba (and
rattlerthis) put the `-c` channels before the channels of a YAML file,
even with `--override-channels` (finding 9). condathis always passes
`channels` (default `conda-forge`) with a file, so under strict priority
conda-forge wins over the channels the YAML lists. Passing no CLI channels
for a request file when `channels` was not given would change behaviour,
so it needs its own decision.

**24. Smaller open points.**

- a. For a lock without `platform`, the micromamba native platform comes
  from `micromamba info`, which can install micromamba before a
  `platform_not_locked` abort. Argument checks still never install it.
- b. A lock without platform data, or a backend whose native platform is
  NA, leaves the platform to the backend; only item 8 guards it.
- c. The `?env_definition` sentence "does not resolve symbolic links" is
  only partly true for a relative path: it is made absolute against
  `getwd()`, which on macOS returns the resolved `/private/var` form.
  Possible wording: "It does not resolve symbolic links in `path`
  itself."
- d. Optional hints: specs plus `env_file` gives only "Use either package
  specs in `...` or `env_file`, not both." (`R/create_env.R:854`), and the
  `condathis_create_env_exists` message for a request file could name
  `install_packages(env_definition(...))`.
- e. CRAN-mode time: the stub matrices of `test-env_definition.R` could go
  behind `skip_on_cran()` if CRAN time becomes a problem.
- f. One `R CMD check` run had a failure in the unchanged
  `test-download_micromamba_file.R:223` while the host was loaded; a clean
  rerun passed. Watch for it.

**25. Commit the work.** The maintainer commits. New, untracked files:
`R/env_definition.R`, `R/env_definition_checks.R`,
`R/backend-micromamba-definition.R`, `man/env_definition.Rd`,
`tests/testthat/test-env_definition.R`, plus this folder; the modified
files are in `git status`.

## Sources

**condathis:** the files and lines cited above; `NEWS.md` 0.2.0.

**rattlerthis** (paths in its repository):
`R/condathis-backend.R` (hook formals, can_solve for lock kinds),
`R/rattler-env.R` (`rattler_env_file_request()`),
`src/rust/src/envfile.rs` (name rules, parsers),
`tests/testthat/test-registration.R`, `test-parity-envfile.R`,
`test-parity-linkscripts.R`, `test-parity-lifecycle.R`,
`test-condathis-conformance.R`.

**micromamba 2.10.0** (https://github.com/mamba-org/mamba):
`libmamba/src/api/install.cpp` (`file_specs_hook`),
`libmamba/src/core/env_lockfile.cpp`,
`libmamba/src/core/env_lockfile_conda.cpp`,
`libmamba/src/core/env_lockfile_mambajs.cpp`,
`libmamba/src/api/create.cpp`, `libmamba/src/api/update.cpp`,
`libmamba/src/core/transaction.cpp`, `docs/source/user_guide/mamba.rst`.

**conda 26.9.4 and conda-lockfiles 0.2.2:**
`conda/plugins/hookspec.py`, `conda/plugins/types.py`,
`conda/plugins/manager.py`, `conda/models/environment.py`,
`conda_lockfiles/plugin.py`;
https://docs.conda.io/projects/conda/en/latest/dev-guide/plugins/environment_specifiers.html,
https://docs.conda.io/projects/conda/en/latest/user-guide/tasks/manage-environments.html,
https://conda.github.io/conda-lockfiles/format-aliases/,
https://github.com/conda/conda-lockfiles/issues?q=v7 (issue #178,
PR #143).

**CEPs:** https://github.com/conda/ceps, CEP 23 (text spec input files),
CEP 24 (environment.yml), CEP 37 (conda-lock.yml).

**rattler and pixi:**
https://docs.rs/rattler_lock/latest/rattler_lock/struct.LockFile.html,
https://docs.rs/rattler_lock/latest/rattler_lock/conda_lock/index.html,
https://prefix.dev/blog/lock-file-v7,
https://pixi.prefix.dev/latest/reference/cli/pixi/init/,
https://pixi.prefix.dev/latest/reference/cli/pixi/install/,
https://pixi.prefix.dev/latest/reference/cli/pixi/workspace/export/.
