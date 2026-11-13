# Package index

## Run command line tools

Run a command, or a pipeline of commands, in a Conda environment.

- [`run()`](https://luciorq.github.io/condathis/reference/run.md) : Run
  a command in a Conda environment
- [`run_bin()`](https://luciorq.github.io/condathis/reference/run_bin.md)
  : Run a binary from a Conda environment
- [`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md)
  : Run a pipeline of commands connected with pipes
- [`run_step()`](https://luciorq.github.io/condathis/reference/run_step.md)
  : Describe one command of a pipeline
- [`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md)
  : Split the output of a command into lines

## Manage environments

Create, change, check, list and remove Conda environments.

- [`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md)
  : Create a Conda environment
- [`install_packages()`](https://luciorq.github.io/condathis/reference/install_packages.md)
  : Install packages in a Conda environment
- [`remove_env()`](https://luciorq.github.io/condathis/reference/remove_env.md)
  : Remove a Conda environment
- [`validate_env()`](https://luciorq.github.io/condathis/reference/validate_env.md)
  : Check that an environment has the requested packages
- [`env_exists()`](https://luciorq.github.io/condathis/reference/env_exists.md)
  : Check whether a Conda environment exists
- [`list_envs()`](https://luciorq.github.io/condathis/reference/list_envs.md)
  : List Conda environments managed by condathis
- [`list_packages()`](https://luciorq.github.io/condathis/reference/list_packages.md)
  : List packages in a Conda environment
- [`get_env_dir()`](https://luciorq.github.io/condathis/reference/get_env_dir.md)
  : Get an environment directory path
- [`env_path()`](https://luciorq.github.io/condathis/reference/env_path.md)
  : Refer to an environment by its path

## Setup: micromamba, data directories and caches

Install and locate the micromamba binary that condathis uses, find the
data directory of each backend, clean the package caches, run code with
temporary home and data directories, and report the operating system and
CPU architecture.

- [`install_micromamba()`](https://luciorq.github.io/condathis/reference/install_micromamba.md)
  : Install micromamba
- [`micromamba_bin_path()`](https://luciorq.github.io/condathis/reference/micromamba_bin_path.md)
  : Get the path of the managed micromamba binary
- [`get_install_dir()`](https://luciorq.github.io/condathis/reference/get_install_dir.md)
  : Get the data directories of the backends
- [`clean_cache()`](https://luciorq.github.io/condathis/reference/clean_cache.md)
  : Clean the package caches of condathis
- [`with_sandbox_dir()`](https://luciorq.github.io/condathis/reference/with_sandbox_dir.md)
  : Run code with temporary home and data directories
- [`get_sys_arch()`](https://luciorq.github.io/condathis/reference/get_sys_arch.md)
  : Get operating system and CPU architecture

## Backends

Add, remove and inspect backends that create and run environments.

- [`register_backend()`](https://luciorq.github.io/condathis/reference/register_backend.md)
  : Register a condathis backend
- [`unregister_backend()`](https://luciorq.github.io/condathis/reference/unregister_backend.md)
  : Unregister a condathis backend
- [`list_registered_backend_names()`](https://luciorq.github.io/condathis/reference/list_registered_backend_names.md)
  : List the registered backends
- [`backend_root_dir()`](https://luciorq.github.io/condathis/reference/backend_root_dir.md)
  : Get the root directory of a backend

## Options and conditions

The options and environment variables that condathis reads or sets, and
the classes of the conditions it signals.

- [`condathis-options`](https://luciorq.github.io/condathis/reference/condathis-options.md)
  [`condathis_options`](https://luciorq.github.io/condathis/reference/condathis-options.md)
  : Options and environment variables used by condathis
- [`condathis-conditions`](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
  [`condathis_conditions`](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
  : Condition classes of condathis
