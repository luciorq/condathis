# condathis: Run Any CLI Tool in a 'Conda' Environment

Runs command line interface (CLI) tools in isolated and reproducible
'Conda' environments from R. Environments are created and managed with
'micromamba' <https://mamba.readthedocs.io/en/latest/>, which is
downloaded when no usable copy is found. Commands run with their
environment activated, alone or as pipelines connected by pipes, and
other packages can add backends that create and run environments.

## Details

Create an environment with
[`create_env()`](https://luciorq.github.io/condathis/reference/create_env.md).
Run a command line tool in it with
[`run()`](https://luciorq.github.io/condathis/reference/run.md), or run
several tools connected by pipes with
[`run_pipeline()`](https://luciorq.github.io/condathis/reference/run_pipeline.md).
Read the output with
[`parse_output()`](https://luciorq.github.io/condathis/reference/parse_output.md).
Start with
[`vignette("condathis")`](https://luciorq.github.io/condathis/articles/condathis.md).
[condathis-options](https://luciorq.github.io/condathis/reference/condathis-options.md)
lists the options and environment variables that `condathis` reads.
[condathis-conditions](https://luciorq.github.io/condathis/reference/condathis-conditions.md)
lists the classes of its errors and warnings.

## See also

Useful links:

- <https://github.com/luciorq/condathis>

- <https://luciorq.github.io/condathis/>

- Report bugs at <https://github.com/luciorq/condathis/issues>

## Author

**Maintainer**: Lucio Queiroz <luciorqueiroz@gmail.com>
([ORCID](https://orcid.org/0000-0002-6090-1834)) \[copyright holder\]

Authors:

- Lucio Queiroz <luciorqueiroz@gmail.com>
  ([ORCID](https://orcid.org/0000-0002-6090-1834)) \[copyright holder\]

- Claudio Zanettini <claudio.zanettini@gmail.com>
  ([ORCID](https://orcid.org/0000-0001-5043-8033)) \[contributor\]
