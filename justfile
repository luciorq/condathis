#!/usr/bin/env just
# shellcheck shell=bash

package_name := 'condathis'

github_org := 'luciorq'

@default:
  just --choose

# =============================================================================
# General R Package Development Tasks
# =============================================================================
@lint:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  R -q -e 'devtools::load_all();styler::style_pkg();';
  air format ./R/ || true;
  air format ./tests/ || true;
  R -q -e 'devtools::load_all();usethis::use_tidy_description();';
  R -q -e 'devtools::load_all();devtools::document();';
  \builtin echo "Linting done!";

@test: lint
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  R -q -e 'devtools::load_all();devtools::run_examples();';
  R -q -e 'devtools::load_all();devtools::test();';
  \builtin echo "All tests passed!";

@build-readme:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  # Lint markdown files
  [[ -f ./README.Rmd ]] && cat ./README.Rmd | rumdl check --stdin || true;
  [[ -f ./README.qmd ]] && cat ./README.qmd | rumdl check --stdin || true;
  [[ -f ./README.Rmd ]] && R -q -e 'devtools::load_all();if(file.exists("README.Rmd"))rmarkdown::render("README.Rmd", encoding = "UTF-8")' || true;
  [[ -f ./README.qmd ]] && quarto render README.qmd --to gfm || true;
  # Lint Final README.md
  rumdl check README.md || true;
  markdownlint README.md || true;
  \builtin echo "README built and linted!";

@test-all-examples:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  R -q -e 'devtools::load_all();devtools::document();devtools::run_examples(run_dontrun = TRUE, run_donttest = TRUE);';

@check: test
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  R -q -e 'rcmdcheck::rcmdcheck(args = c("--as-cran"), repos = c(CRAN = "https://cloud.r-project.org"));';

# Force GitHub Actions Checks to start for the main branch
@check-gha-trigger:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  gh workflow run "r-cmd-check" --ref main;

# Print latest GitHub Actions Checks results for the main branch
@monitor-gha:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  gh run list;
  latest_job_id="$(gh run list -w "r-cmd-check" --json databaseId --jq '.[0].databaseId')";
  gh run view "${latest_job_id}";

# Use R package version on the DESCRIPTION file to tag latest commit of the git repo
@git-tag:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  __r_pkg_version="$(R -q --no-echo --silent -e 'suppressMessages({pkgload::load_all()});cat(as.character(utils::packageVersion("{{ package_name }}")));')";
  \builtin echo -ne "Tagging version: ${__r_pkg_version}\n";
  git tag -a "v${__r_pkg_version}" HEAD -m "Version ${__r_pkg_version} released";
  git push --tags;

# Things to run before releasing a new version
@pre-release:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  R -q -e 'urlchecker::url_check()';
  R -q -e 'devtools::build_readme()';
  R -q -e 'withr::with_options(list(repos = c(CRAN = "https://cloud.r-project.org")), {devtools::check(remote = TRUE, manual = TRUE)})';
  R -q -e 'devtools::check_win_devel()';
  # revdepcheck::revdep_check(num_workers = 4)
  # Update CRAN comments
  # usethis::use_version('patch')
  # devtools::build_rmd("vignettes/my-vignette.Rmd")
  # devtools::submit_cran()
  \builtin echo "Pre-release checks done!";

@build-vignettes:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  R -q -e 'devtools::load_all();devtools::document();';
  R -q -e 'devtools::install(pkg = ".", build_vignettes = TRUE, dependencies = c("Imports", "Suggests", "Depends"), upgrade = "always");';
  R -q -e 'print(vignette(package = "{{ package_name }}"));';

@build-pkgdown-website:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  R -q -e 'devtools::load_all();devtools::document();pkgdown::build_site();';
  # git add docs/;
  # git commit -m "chore: update pkgdown website";
  # git push;

@release-github:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  # gh release create v0.1.0 --title "v0.1.0" --notes "First Zenodo archiving release"
  \builtin echo "Not implemented yet";

# =============================================================================
# Condathis specifc Tasks
# =============================================================================

# Check if package can be installed on a conda environment
@check-install-conda tag_version='main':
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  conda create -n {{ package_name }}-env -y --override-channels -c conda-forge \
    r-base r-devtools r-remotes r-rlang r-withr r-stringr r-jsonlite r-fs r-cli r-processx r-ps r-tibble;
  conda run -n {{ package_name }}-env R -q -e 'remotes::install_github("{{ github_org }}/{{ package_name }}@{{ tag_version }}");';
  conda run -n {{ package_name }}-env R -q -e 'utils::packageVersion("{{ package_name }}");';
  conda run -n {{ package_name }}-env R -q -e 'condathis::create_env("r-base", env_name = "condathis-test-env");message(condathis::run("R","-s", "-q", "--version", env_name = "condathis-test-env"));';
