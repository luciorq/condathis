#!/usr/bin/env just
# shellcheck shell=bash

package_name := 'condathis'

github_org := 'luciorq'

@default:
  just --choose

@test:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  R -q -e 'devtools::load_all();';
  R -q -e 'devtools::document();';
  R -q -e 'devtools::test();';

@check:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  R -q -e 'rcmdcheck::rcmdcheck();';

# Use R package version on the Description file to tag latest commit of the git repo
@git-tag:
  #!/usr/bin/env bash
  \builtin set -euxo pipefail;
  __r_pkg_version="$(R -q --no-echo --silent -e 'suppressMessages({pkgload::load_all()});cat(as.character(utils::packageVersion("{{ package_name }}")));')";
  \builtin echo -ne "Tagging version: ${__r_pkg_version}\n";
  git tag -a "v${__package_version}" HEAD -m "Version ${_r_pkg_version} released";
  git push --tags;
