#!/usr/bin/env just
# shellcheck shell=bash

package_name := 'condathis'

github_org := 'luciorq'

@default:
  just --choose

# >>> rstats-package-dev-tasks >>>

# =============================================================================
# General R Package Development Tasks
# =============================================================================

# Update Package Documentation
document:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  R -q -s -e 'devtools::load_all(quiet=TRUE);usethis::use_tidy_description();';
  R -q -s -e 'devtools::load_all(quiet=TRUE);devtools::document(quiet=TRUE);';
  \builtin echo "Documentation updated!";

# Lint R Package Code and Documentation
lint:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # Reformats R/ and tests/ with `air` (configured in `air.toml`), rewrites
  # + `@return` tags and regenerates the documentation. Run it on purpose:
  # + no other recipe depends on it.
  air format ./R/ || true;
  air format ./tests/ || true;
  (jarl check . --select ALL || jarl check . --select ALL --statistics) || true;
  # TODO: @luciorq: This is not capturing lines where `@return` has a line break just after it it.
  find ./R/ -type f -name "*.R" -exec sed -i -e "s|^#' \@return |#' \@returns |g" {} +
  find ./R/ -type f -name "*.R" -exec sed -i -e "s|^#' \@return$|#' \@returns|g" {} +
  just document;
  # Fail on non-ASCII characters (em dashes, curly quotes, ...) in package
  # + sources. Non-ASCII outside comments breaks `R CMD check --as-cran`
  # + ("Portable packages must use only ASCII characters"); banning it
  # + everywhere in these files keeps that check trivially clean and the
  # + failure local instead of a CI round-trip away. README.qmd sets
  # + `cli.unicode = FALSE`, so the rendered README.md is ASCII too, and
  # + both are in the list.
  # + `-I` skips binary files (e.g. man/figures/*.png).
  if \grep -rnI -P '[^\x00-\x7F]' ./R/ ./tests/ ./man/ ./vignettes/ DESCRIPTION NAMESPACE NEWS.md README.md README.qmd; then
    \builtin echo "ERROR: non-ASCII characters found (listed above). Replace them with ASCII equivalents (e.g. '-' instead of em dashes).";
    \builtin exit 1;
  fi
  # Remove duplicate lines from .gitignore and .Rbuildignore without changing their order
  awk '!seen[$0]++' .gitignore > .gitignore.tmp && \mv .gitignore.tmp .gitignore;
  awk '!seen[$0]++' .Rbuildignore > .Rbuildignore.tmp && \mv .Rbuildignore.tmp .Rbuildignore;
  # TODO: @luciorq - Check what is the proper verbosity level for lychee
  lychee . || \builtin echo 'lychee not installed.';
  \builtin echo "Linting done!";

# Run All Unit Tests
test:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  R -q -s -e 'withr::with_envvar(new=list(`TESTTHAT_CPUS`=4),code={devtools::load_all(quiet=TRUE);devtools::run_examples();});';
  R -q -s -e 'withr::with_envvar(new=list(`TESTTHAT_CPUS`=4),code={withr::with_options(list(crayon.enabled=FALSE,cli.unicode=FALSE),code={devtools::load_all(quiet=TRUE);devtools::test(pkg=".");})});';
  \builtin echo "All tests passed!";

# Build and Lint README File
build-readme:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # The README creates environments and installs micromamba. To keep them
  # + out of your own condathis data directory and caches, it is rendered
  # + with HOME and the XDG directories in a temporary directory. The package
  # + is installed into a temporary library on top of your current libraries,
  # + so nothing in them is installed or upgraded. Missing dependencies make
  # + the render fail: install them on purpose with `just install-deps`.
  # Lint markdown files
  [[ -f ./README.Rmd ]] && cat ./README.Rmd | rumdl check --stdin --disable 'MD046' || true;
  [[ -f ./README.qmd ]] && cat ./README.qmd | rumdl check --stdin --disable 'MD046' || true;
  __readme_libs="$(Rscript -e 'cat(.libPaths(), sep = ":")')";
  __readme_tmp="$(\mktemp -d)";
  trap '\rm -rf "${__readme_tmp}"' EXIT;
  \mkdir -p "${__readme_tmp}/lib" "${__readme_tmp}/home" "${__readme_tmp}/xdg/cache" "${__readme_tmp}/xdg/data" "${__readme_tmp}/xdg/config" "${__readme_tmp}/xdg/state";
  R CMD INSTALL --library="${__readme_tmp}/lib" .;
  export R_LIBS="${__readme_tmp}/lib:${__readme_libs}";
  export HOME="${__readme_tmp}/home";
  export XDG_CACHE_HOME="${__readme_tmp}/xdg/cache" XDG_DATA_HOME="${__readme_tmp}/xdg/data";
  export XDG_CONFIG_HOME="${__readme_tmp}/xdg/config" XDG_STATE_HOME="${__readme_tmp}/xdg/state";
  \builtin unset R_USER_DATA_DIR R_USER_CACHE_DIR R_USER_CONFIG_DIR CONDATHIS_MICROMAMBA_PATH;
  [[ -f ./README.Rmd ]] && R -q -s -e 'rmarkdown::render("README.Rmd", encoding="UTF-8");';
  [[ -f ./README.qmd ]] && quarto render README.qmd --to gfm;
  # Lint Final README.md
  sed -i -e 's|[[:blank:]]*$||g' README.md;
  sed -i -e '/./,$!d' README.md;
  sed -i '/<!-- badges: start -->/{n; /^\s*$/d}' README.md;
  rumdl check README.md || true;
  markdownlint README.md || true;
  markdownlint-cli2 --no-globs README.md || true;
  \builtin echo "README built and linted!";

# Run All Examples in the Documentation Including `dontrun`
test-all-examples:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # `devtools::document()` brings man/ up to date first. It does not run
  # + `just document`, which also rewrites DESCRIPTION.
  R -q -s -e 'devtools::load_all(quiet=TRUE);devtools::document(quiet=TRUE);devtools::run_examples(run_dontrun = TRUE, run_donttest = TRUE);';

# Run Tests from a Specific Test File
test-file file_name:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  R -q -s -e 'devtools::load_all(quiet=TRUE);devtools::test_active_file("tests/testthat/test-{{ file_name }}.R")';

# Run R CMD Check on the Package With Cran Like Checks
check: test test-all-examples
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # Runs the tests and all examples (including `dontrun`) first. Lint
  # + (`just lint`) and the README (`just build-readme`) are separate recipes.
  if [[ $(\builtin command -v qpdf) ]]; then 
    R -q -s -e 'withr::with_envvar(new=list(`_R_CHECK_SYSTEM_CLOCK_`="0"),code={rcmdcheck::rcmdcheck(args = c("--as-cran"), repos = c(CRAN = "https://cloud.r-project.org"));});';
  else
    \builtin echo -ne '\n\nNOTE: LaTeX and PDF handling tools missing.\n';
    \builtin echo -ne '  - Skipping Building Manuals\nNOTE: Before submitting to CRAN, check it in a machine that can handle PDF manuals.\n';
    \builtin echo -ne '  - Try installing `R -q -s -e "tinytex::install_tinytex()"`\n';
    \builtin echo -ne '  - Also `pixi global install qpdf ghostscript`\n\n';
    R -q -s -e 'withr::with_envvar(new=list(`_R_CHECK_SYSTEM_CLOCK_`="0"),code={rcmdcheck::rcmdcheck(args = c("--as-cran", "--no-manual"), repos = c(CRAN = "https://cloud.r-project.org"));});';
  fi

# Force GitHub Actions Checks to start for the main branch
check-gha-trigger:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  gh workflow run "r-cmd-check" --ref main;

# Print latest GitHub Actions Checks results for the main branch
monitor-gha:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  gh run list;
  latest_job_id="$(gh run list -w "r-cmd-check" --json databaseId --jq '.[0].databaseId')";
  gh run view "${latest_job_id}";

# Tag the Submitted Commit with Version from the DESCRIPTION File
git-tag:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # Run it after CRAN accepts the release, before `just release-github`
  # + (which removes `CRAN-SUBMISSION`). It tags the commit recorded in the
  # + `SHA:` field of `CRAN-SUBMISSION` (written by `devtools::submit_cran()`),
  # + so commits made after the submission are not part of the tag. Without
  # + that file, it tags HEAD.
  git pull origin --tags || true;
  git pull upstream --tags || true;
  __r_pkg_version="$(R -q --no-echo --silent -e 'cat(read.dcf("DESCRIPTION", fields = "Version")[[1L]]);')";
  __tag_target='HEAD';
  if [[ -f ./CRAN-SUBMISSION ]]; then
    __submitted_version="$(\sed -n -e 's|^Version:[[:blank:]]*||p' ./CRAN-SUBMISSION)";
    __submitted_sha="$(\sed -n -e 's|^SHA:[[:blank:]]*||p' ./CRAN-SUBMISSION)";
    if [[ -z "${__submitted_sha}" ]]; then
      \builtin echo "ERROR: CRAN-SUBMISSION has no SHA field.";
      \builtin exit 1;
    fi
    if [[ "${__submitted_version}" != "${__r_pkg_version}" ]]; then
      \builtin echo "ERROR: CRAN-SUBMISSION is for version ${__submitted_version}, DESCRIPTION has ${__r_pkg_version}.";
      \builtin exit 1;
    fi
    __tag_target="${__submitted_sha}";
  else
    \builtin echo "NOTE: no CRAN-SUBMISSION file; tagging HEAD.";
  fi
  \builtin echo -ne "Tagging version: ${__r_pkg_version} at ${__tag_target}\n";
  git tag -a "v${__r_pkg_version}" "${__tag_target}" -m "Version ${__r_pkg_version} released";
  # git push --tags;
  # git pull upstream --tags;
  # git push upstream --tags;

# Build Vignettes
build-vignettes:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  R -q -s -e 'devtools::load_all(quiet=TRUE);devtools::document(quiet=TRUE);';
  just install-deps;
  just install-local;
  # TODO: `devtools::install()` changed completely its signature by using
  # + `pak::local_install_deps()` for managing dependencies.
  # R -q -s -e 'devtools::install(pkg = ".", build_vignettes = TRUE, dependencies = c("Imports", "Suggests", "Depends"), upgrade = "always");';
  R -q -s -e 'devtools::install(pkg = ".", build_vignettes = TRUE, dependencies = TRUE, upgrade = TRUE);';
  R -q -s -e 'print(vignette(package = "{{ package_name }}"));';

# Install Package Development Dependencies Including Suggests
install-deps:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  R -q -s -e 'if(!requireNamespace("pak", quietly=TRUE)) {install.packages("pak")};';
  R -q -s -e 'pak::local_install_dev_deps(upgrade=TRUE, dependencies=TRUE);';

# Install Local Version of the Package With All Dependencies
install-local:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  R -q -s -e 'if(!requireNamespace("pak", quietly=TRUE)) {install.packages("pak")};';
  R -q -s -e 'pak::local_install(upgrade=TRUE, dependencies=TRUE);';

# Install Dev Environment Dependencies
install-dev-deps: install-deps
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  R -q -s -e 'pak::local_install_dev_deps(dependencies="Config/Needs/dev", upgrade=TRUE)';

# Build the pkgdown Website
build-pkgdown-website: install-deps
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  R -q -s -e 'pak::pak("pkgdown", upgrade=TRUE, dependencies=TRUE);';
  R -q -s -e 'pkgdown::build_favicons(overwrite=FALSE);';
  R -q -s -e 'devtools::document(quiet=TRUE);devtools::load_all(quiet=TRUE);pkgdown::build_site();';
  # Steps for manually deploying the pkgdown website,
  # + not necessary if using GitHub Actions.
  # git add docs/;
  # git add pkgdown/;
  # git add _pkgdown.yml;
  # git commit -m "chore: update pkgdown website";
  # git push;

# Release a New Version on GitHub Releases Using Content From NEWS.md
release-github:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # Using `gh` cli to create a new release.
  # e.g.: `gh release create v0.1.0 --title "v0.1.0" --notes "First Zenodo archiving release"`.
  # Using `usethis` to create a new release.
  # First, change the NEWS.md header temporarily to make usethis happy
  # + Check: <https://github.com/r-lib/pkgdown/issues/2897>
  # + <https://github.com/r-lib/usethis/issues/2130>
  # + <https://github.com/tidyverse/style/issues/245#issuecomment-2959459898>
  # + The trap restores the headings also when the release fails.
  trap 'sed -i -e "s|^# {{ package_name }}|## {{ package_name }}|g" NEWS.md' EXIT;
  sed -i -e "s|^## {{ package_name }}|# {{ package_name }}|g" NEWS.md;
  R -q -e 'devtools::load_all(quiet=TRUE);usethis::use_github_release();';
  \builtin echo "Check the GH Releases!";

# Steps to Run Before Releasing a New Version
pre-release:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # Runs only local checks: nothing is uploaded, submitted or tagged.
  # TODO: Update version on NEWS.md and DESCRIPTION files.
  # git commit -m "chore: prepare for vX.Y.Z release";
  # git push;
  R -q -s -e 'urlchecker::url_check()';
  just build-readme;
  R -q -s -e 'withr::with_options(list(repos = c(CRAN = "https://cloud.r-project.org")), {devtools::check(remote = TRUE, manual = TRUE)})';
  # Upload to win-builder on purpose, after these checks pass:
  # just check-win-devel;
  # just check-win-release;
  # R -q -s -e 'if(!requireNamespace("revdepcheck", quietly=TRUE)) pak::pak("r-lib/revdepcheck");';
  # R -q -s -e 'revdepcheck::revdep_reset();';
  # R -q -s -e 'revdepcheck::revdep_check(num_workers = 4);';
  # TODO: Update CRAN comments with output from `check`.
  # cat ./cran-comments.md;
  # usethis::use_version('patch')
  # devtools::build_rmd("vignettes/my-vignette.Rmd")
  # just build-vignettes;
  # TODO: This step needs to be run manually, from R.
  # + Wait for the win-builder results (sent by email).
  # devtools::submit_cran();
  # TODO: Check your email! Click the link, and check all boxes!
  # TODO: When accepted run:
  # just git-tag;
  # git push --tags;
  # git push upstream --tags;
  # just release-github;
  # TODO: Update Zenodo archive with the new release.
  # + Update the DOI badge in the README file.
  \builtin echo "Pre-release checks done; submit manually.";

# Check the Package on win-builder With R-devel
check-win-devel:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # Uploads the package to win-builder; the results come by email to the
  # + maintainer in DESCRIPTION. Run it on purpose.
  R -q -s -e 'devtools::check_win_devel()';

# Check the Package on win-builder With the Current R Release
check-win-release:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # Uploads the package to win-builder; the results come by email to the
  # + maintainer in DESCRIPTION. Run it on purpose.
  R -q -s -e 'devtools::check_win_release()';

# Link current branch devdocs to project root
link-dev-docs branch_name:
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  # Example usage: `just link-dev-docs feat-new-feature`
  dev_docs_dir='.github/devdocs/{{ branch_name }}';
  if [[ ! -d "${dev_docs_dir}" ]]; then
    \mkdir -p "${dev_docs_dir}";
  fi;
  for file_name in PLAN.md TODO.md; do
    # Check if the file exists in the devdocs directory
    if [[ ! -f ${dev_docs_dir}/${file_name} ]]; then
      \builtin echo -ne "${file_name} does not exist in the devdocs directory for branch: {{ branch_name }}\n";
      \builtin continue;
    fi
    if [[ ! -f "${file_name}" && ! -L "${file_name}" ]]; then
      \builtin echo -ne "${file_name} does not exist in the project root. Creating symlink from ${dev_docs_dir}/${file_name} to project root\n";
      \ln -s "${dev_docs_dir}/${file_name}" ./"${file_name}";
      \builtin continue;
    fi
    # Check if file_name is a symlink but pointing to a different file
    if [[ -L "${file_name}" && "$(readlink "${file_name}")" != "${dev_docs_dir}/${file_name}" ]]; then
      \builtin echo -ne "${file_name} is a symlink but pointing to a different file. Check it's content.\n";
      \builtin continue;
    fi
    diff_res="$(diff "${file_name}" "${dev_docs_dir}/${file_name}")";
    diff_exit_code=${?:-1};
    if [[ ${diff_exit_code} -ne 0 && -n "${diff_res}" && -f "${dev_docs_dir}/${file_name}" ]]; then
      \builtin echo -ne "Differences found in ${file_name} for branch: {{ branch_name }}. Check before continuing.\n";
      \builtin echo -ne "${diff_res}\n";
      \builtin continue;
    fi
    # Check if none of them are symlinks and there is no difference, then create symlinks from devdocs to project root
    if [[ ${diff_exit_code} -eq 0 && -f "${dev_docs_dir}/${file_name}" && ! -L "${file_name}" ]]; then
      \builtin echo -ne "No differences found in ${file_name} for branch: {{ branch_name }}\n";
      \builtin echo -ne "Creating symlink from ${dev_docs_dir}/${file_name} to project root\n";
      \rm -f ./"${file_name}";
      \ln -s "${dev_docs_dir}/${file_name}" ./"${file_name}";
    fi
  done

# <<< rstats-package-dev-tasks <<<

# =============================================================================
# Condathis specific Tasks
# =============================================================================

# Install Package in a New Clean Conda Environment
check-install-conda tag_version='main':
  #!/usr/bin/env bash
  \builtin set -euo pipefail;
  micromamba create -n {{ package_name }}-env -y --override-channels -c conda-forge \
    r-base r-devtools r-remotes r-rlang r-withr r-stringr r-jsonlite r-fs r-cli r-processx r-ps micromamba r-curl curl;
  micromamba run -n {{ package_name }}-env R -q -e 'remotes::install_github("{{ github_org }}/{{ package_name }}@{{ tag_version }}");';
  micromamba run -n {{ package_name }}-env R -q -e 'utils::packageVersion("{{ package_name }}");';
  micromamba run -n {{ package_name }}-env R -q -e 'condathis::create_env("r-base", env_name = "condathis-task-env");message(condathis::run("R","-s", "-q", "--version", env_name = "condathis-task-env"));';
