# Backends: micromamba and rattler

## What a Backend Does

Every `condathis` function that touches an environment hands the work to
a *backend*. The backend solves the package specs, downloads and links
the packages, and activates the environment before a command runs.
`condathis` keeps everything else: the arguments, the checks, the
messages, the results and the condition classes.

Two backends exist today:

- **`"micromamba"`** is built in. `condathis` downloads the `micromamba`
  binary the first time it needs it, and runs it as a separate process.
  Every environment uses it unless you ask for another backend.
- **`"rattler"`** comes from the
  [`rattlerthis`](https://github.com/luciorq/rattlerthis) package. It
  uses [`rattler`](https://github.com/conda/rattler), the Rust library
  behind `pixi`, inside the R process. There is no package manager
  binary to download.

Your code stays the same with either backend. The `method` argument of
the environment functions, and of
[`run()`](https://luciorq.github.io/condathis/reference/run.md),
[`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
and
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md),
picks the backend. Its default, `"auto"`, picks it for you.

## Installing rattlerthis

`rattlerthis` is not on CRAN yet. It builds from source, so it needs a
Rust toolchain (`rustc` \>= 1.88.0 and `cargo`, from
<https://rustup.rs>). Linux also needs `pkg-config` and the OpenSSL
headers, and Windows needs Rtools. The [`rattlerthis`
README](https://github.com/luciorq/rattlerthis#installation) lists the
requirements of each platform.

``` r

# install.packages("pak")
pak::pak("luciorq/rattlerthis")
```

You never call
[`library(rattlerthis)`](https://github.com/luciorq/rattlerthis). The
package exports no functions: `condathis` loads it when `method` names
`"rattler"`, and when rattler environments already exist.

## Choosing the Backend of a New Environment

Without `method`, a new environment uses `micromamba`:

``` r

create_env("jq", env_name = "jq-env", verbose = "silent")
```

Pass `method = "rattler"` to create one with `rattler` instead:

``` r

create_env(
  "ripgrep",
  env_name = "rg-env",
  method = "rattler",
  verbose = "silent"
)
```

[`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md)
covers every backend. The `backend` column tells you which one owns each
environment:

``` r

list_envs()[, c("backend", "env_name")]
#> # A tibble: 2 × 2
#>   backend    env_name
#>   <chr>      <chr>   
#> 1 micromamba jq-env  
#> 2 rattler    rg-env
```

## Running Commands

Commands need no `method`. `"auto"` finds the backend that owns the
environment, and that backend activates it:

``` r

res <- run("rg", "--version", env_name = "rg-env", verbose = "silent")
parse_output(res)[1]
#> [1] "ripgrep 15.2.0 (rev 78115297cd)"
```

Environments of different backends work together. In this pipeline,
`ripgrep` from the rattler environment searches a file and prints its
matches as JSON. `jq` from the micromamba environment turns the JSON
into one line per match:

``` r

notes_path <- fs::file_temp(pattern = "notes-", ext = "txt")
writeLines(
  con = notes_path,
  text = c(
    "micromamba is the built-in backend.",
    "Environments live in the condathis data directory.",
    "rattler is the backend of rattlerthis."
  )
)

res <- run_pipeline(
  run_step("rg", "--json", "backend", notes_path, env_name = "rg-env"),
  run_step(
    "jq", "-r",
    paste(
      'select(.type == "match")',
      '"\\(.data.line_number): \\(.data.lines.text | rtrimstr("\\n") | rtrimstr("\\r"))"',
      sep = " | "
    ),
    env_name = "jq-env"
  ),
  verbose = "silent"
)

parse_output(res)
#> [1] "1: micromamba is the built-in backend."   
#> [2] "3: rattler is the backend of rattlerthis."
```

## One Environment, One Backend

The backend that creates an environment owns it for its whole life. A
call that names another backend for it does not move it:

- Functions that change the environment, such as
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  and
  [`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md),
  abort with class `condathis_backend_mismatch`.
- Functions that only read it, such as
  [`run()`](https://luciorq.github.io/condathis/reference/run.md) and
  [`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md),
  warn with class `condathis_backend_mismatch_warning` and use the
  owner.

``` r

install_packages("jq", env_name = "rg-env", method = "micromamba")
#> Error in `install_packages()`:
#> ✖ Environment rg-env is owned by backend rattler, not micromamba.
#> ℹ Remove it first, or use `method = "rattler"`.
```

[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
refuses the name under another backend too, so a name belongs to one
backend at a time. To move an environment to another backend, remove it,
then create it again with that backend. Each backend keeps its
environments in its own directory. If the same name still ends up under
both, for example in a directory copied by hand, `"auto"` cannot choose,
and the call aborts with class `condathis_backend_ambiguous_env` until
`method` names one of them.

## Making rattler the Default

The option `condathis.backend_priority` sets the order that `"auto"`
tries for a *new* environment. Its default is `"micromamba"`, so
installing `rattlerthis` alone changes nothing. To create new
environments with `rattler`, and keep `micromamba` as the fallback, put
this in your `.Rprofile`:

``` r

options(condathis.backend_priority = c("rattler", "micromamba"))
```

With the option set,
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
uses `rattler` without `method`:

``` r

old_options <- options(condathis.backend_priority = c("rattler", "micromamba"))
create_env("jq", env_name = "jq-rattler-env", verbose = "silent")
options(old_options)

list_envs()[, c("backend", "env_name")]
#> # A tibble: 3 × 2
#>   backend    env_name      
#>   <chr>      <chr>         
#> 1 micromamba jq-env        
#> 2 rattler    jq-rattler-env
#> 3 rattler    rg-env
```

Existing environments keep their owner: `jq-env` stays a micromamba
environment.

## Which Backend to Use

Both backends behave the same wherever they can. They activate
environments the same way, cache the activation, install the `pip:`
sections of environment files, and let one R session at a time change an
environment. The differences you are most likely to notice:

- **Link scripts.** `rattler` never runs the `pre-link`, `post-link` and
  `pre-unlink` scripts of packages. `condathis` warns with class
  `condathis_link_scripts_skipped`, and names the packages. `micromamba`
  runs them. Both run the `activate.d` scripts.
- **No binary, no command line.** `rattler` needs no download of a
  package manager, and nothing runs as a separate process to create an
  environment. For the same reason, `verbose = "cmd"` prints a one-line
  description, and the results of
  [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  and
  [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  have `NA` in `cmd` and `pid`.
- **Errors.** The classes are `condathis`’s with both backends. Under a
  `rattler` failure, the parent condition has the classes
  `rattlerthis_rattler_<kind>`, such as `rattlerthis_rattler_solve`,
  instead of `micromamba`’s status classes.
- **Disk.** The package caches are separate, so a package that both
  backends use is downloaded twice.

The [`rattlerthis`
README](https://github.com/luciorq/rattlerthis#differences-from-the-micromamba-backend)
and `?rattlerthis` list every difference. A simple rule: keep
`micromamba` for packages whose link scripts matter. Try `rattler` when
you want no extra binary, or a solver inside R.

## Where the Files Live

[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)
reports the data directory of each backend:

``` r

get_install_dir()
#> # A tibble: 2 × 2
#>   backend    path                                         
#>   <chr>      <chr>                                        
#> 1 micromamba /home/runner/.local/share/R/condathis        
#> 2 rattler    /home/runner/.local/share/R/condathis/rattler
```

The `rattler` backend keeps its environments, its package cache and its
channel metadata in `backend_root_dir("rattler")`, the `rattler`
directory inside the data directory of `condathis`. The functions that
manage files cover every backend:

- [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  deletes the package caches of `micromamba` and of `rattler`.
- [`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)
  redirects the directories of every backend, so code in it leaves
  nothing behind.

## Writing a Backend

The backend system is open: another package can add its own backend with
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md),
and users then select it with `method`. The API is experimental, and it
may still change between `0.x` releases.
[`?register_backend`](https://luciorq.github.io/condathis/reference/register_backend.md)
describes the functions a backend provides, and how to register them
when the package loads.
[`rattlerthis`](https://github.com/luciorq/rattlerthis) is a complete
example.

## Cleaning Up

``` r

remove_env(env_name = "jq-env", verbose = "silent")
if (isTRUE(has_rattler)) {
  remove_env(env_name = "rg-env", verbose = "silent")
  remove_env(env_name = "jq-rattler-env", verbose = "silent")
}
```
