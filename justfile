#!/usr/bin/env just
# shellcheck shell=bash

package_name := 'condathis'

github_org := 'luciorq'

@default:
  just --choose

@test:
  #!/usr/bin/env -vS bash -i
  \builtin set -euxo pipefail;
  R -q -e 'devtools::load_all();styler::style_pkg();';
  R -q -e 'devtools::load_all();usethis::use_tidy_description();';
  R -q -e 'devtools::load_all();devtools::document();';
  R -q -e 'devtools::load_all();devtools::run_examples();';
  R -q -e 'devtools::load_all();devtools::test();';
  R -q -e 'devtools::load_all();rmarkdown::render("README.Rmd", encoding = "UTF-8")';

@test-all-examples:
  #!/usr/bin/env -vS bash -i
  \builtin set -euxo pipefail;
  R -q -e 'devtools::load_all();devtools::run_examples(run_dontrun = TRUE, run_donttest = TRUE);';

@check:
  #!/usr/bin/env -vS bash -i
  \builtin set -euxo pipefail;
  R -q -e 'rcmdcheck::rcmdcheck(args="--as-cran");';

# Use R package version on the Description file to tag latest commit of the git repo
@git-tag:
  #!/usr/bin/env -vS bash -i
  \builtin set -euxo pipefail;
  __r_pkg_version="$(R -q --no-echo --silent -e 'suppressMessages({pkgload::load_all()});cat(as.character(utils::packageVersion("{{ package_name }}")));')";
  \builtin echo -ne "Tagging version: ${__r_pkg_version}\n";
  git tag -a "v${__r_pkg_version}" HEAD -m "Version ${__r_pkg_version} released";
  git push --tags;

# Check if package can be installed on a conda environment
@check-install-conda tag_version='main':
  #!/usr/bin/env -vS bash -i
  \builtin set -euxo pipefail;
  conda create -n {{ package_name }}-env -y --override-channels -c bioconda -c conda-forge \
    r-base r-devtools r-rlang r-remotes r-withr r-stringr r-jsonlite r-fs r-cli r-processx r-tibble r-;
  conda run -n {{ package_name }}-env R -q -e 'remotes::install_github("{{ github_org }}/{{ package_name }}@{{ tag_version }}");';
  conda run -n {{ package_name }}-env R -q -e 'utils::packageVersion("{{ package_name }}")';
  conda run -n {{ package_name }}-env R -q -e 'condathis::create_env("r-base", env_name = "condathis-test-env");condathis::run("R","-s", "-q", "--version", env_name = "condathis-test-env");';
