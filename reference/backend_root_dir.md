# Get the root directory of a backend

Returns the root (data directory) that condathis assigns to a backend.
The root of the built-in `"micromamba"` backend is the condathis data
directory (see
[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)).
The root of every other backend is the directory of its name inside it,
for example `<condathis data directory>/rattler`. A backend keeps its
environments in `<root>/envs`, and its caches in other directories of
its root (see *Roots* in
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)).
The default functions of the backend contract use this directory, and a
backend package calls it to find its root.

## Usage

``` r
backend_root_dir(name)
```

## Arguments

- name:

  Character string, a backend name, registered or not. It follows the
  rules of `name` in
  [`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md),
  except that `"micromamba"` is allowed.

## Value

An `fs_path`, the absolute path of the root. When the root exists, its
real path (symbolic links resolved). Otherwise, the real path of its
nearest existing parent directory, followed by the rest of the path. It
creates nothing. Aborts with class `condathis_backend_invalid_name` for
a malformed name, and `condathis_backend_reserved_name` (also
`condathis_backend_invalid_name`) for a reserved name other than
`"micromamba"`.

## Details

`backend_root_dir()` computes the path on every call, so it follows
[`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md).

Part of the **experimental** backend extension API. See the *Lifecycle*
section of
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md).

## See also

[`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)

Other backends:
[`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md),
[`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md),
[`unregister_backend()`](https://luciorq.github.io/condathis/reference/unregister_backend.md)

## Examples

``` r
condathis::with_sandbox_dir({
  condathis::backend_root_dir("rattler")
  #> <data dir>/R/condathis/rattler
})
#> /tmp/Rtmpu60vo2/condathis-sandbox-2b12719a0691/data/R/condathis/rattler
```
