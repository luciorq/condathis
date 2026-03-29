#' Build Download URLs for Micromamba from Multiple Mirrors
#'
#' Returns a named list of URL vectors for downloading micromamba binaries
#' from multiple mirror sources. The mirrors are tried in order of preference.
#'
#' Mirror sources (in order):
#' - **GitHub Releases**: `https://github.com/mamba-org/micromamba-releases/releases/`
#'   Primary source with both `.tar.bz2` and uncompressed binary formats.
#' - **micro.mamba.pm**: `https://micro.mamba.pm/api/micromamba/`
#'   Official CDN URL. Redirects (307) to `api.anaconda.org`.
#' - **conda-forge via Anaconda**: `https://api.anaconda.org/download/conda-forge/`
#'   Serves the conda package `.tar.bz2`. The binary is at `bin/micromamba`
#'   inside the archive (same structure as GitHub releases).
#' - **conda-forge via prefix.dev**: `https://repo.prefix.dev/conda-forge/`
#'   Alternative mirror for conda-forge packages. Same `.tar.bz2` format.
#'
#' @param sys_arch_str Character string. The platform slug returned by
#'   `is_micromamba_available_for_arch()`, e.g., `"osx-arm64"`, `"linux-64"`.
#' @param micromamba_version Character string. The version to download,
#'   e.g., `"2.5.0-2"`.
#'
#' @returns A named list with:
#'   - `compressed`: Character vector of URLs for `.tar.bz2` archives
#'   - `uncompressed`: Character vector of URLs for raw binary downloads
#'   - `sha256`: Character vector of URLs for SHA256 checksum files
#'   - `check_urls`: Character vector of base URLs to verify connectivity
#'
#' @keywords internal
#' @noRd
get_micromamba_urls <- function(sys_arch_str, micromamba_version) {
  github_base <- "https://github.com/mamba-org/micromamba-releases/releases"

  # Parse version components for conda-forge URL format
  # Version format: "2.5.0-2" -> version "2.5.0", build "2"
  version_parts <- strsplit(micromamba_version, "-", fixed = TRUE)[[1L]]
  version_num <- version_parts[1L]
  build_num <- version_parts[2L]

  # Conda package filename (shared by Anaconda and prefix.dev mirrors)
  conda_pkg_filename <- paste0(
    "micromamba-",
    version_num,
    "-",
    build_num,
    ".tar.bz2"
  )

  # --- Compressed (.tar.bz2) URLs ---

  # 1. GitHub Releases (primary source)
  github_compressed <- paste0(
    github_base,
    "/download/",
    micromamba_version,
    "/micromamba-",
    sys_arch_str,
    ".tar.bz2"
  )

  # 2. micro.mamba.pm (official convenience URL).
  # Redirects (HTTP 307) to api.anaconda.org, serving the same conda-forge
  # .tar.bz2 package. The archive contains bin/micromamba at the top level.
  micromamba_pm_compressed <- paste0(
    "https://micro.mamba.pm/api/micromamba/",
    sys_arch_str,
    "/",
    micromamba_version
  )

  # 3. Anaconda.org conda-forge mirror (direct, no redirect).
  anaconda_compressed <- paste0(
    "https://api.anaconda.org/download/conda-forge/micromamba/",
    version_num,
    "/",
    sys_arch_str,
    "/",
    conda_pkg_filename
  )

  # 4. prefix.dev conda-forge mirror (alternative CDN).
  prefix_dev_compressed <- paste0(
    "https://repo.prefix.dev/conda-forge/",
    sys_arch_str,
    "/",
    conda_pkg_filename
  )

  compressed_urls <- c(
    github_compressed,
    micromamba_pm_compressed,
    anaconda_compressed,
    prefix_dev_compressed
  )

  # --- Uncompressed (raw binary) URLs ---
  # Only available from GitHub releases
  github_uncompressed <- paste0(
    github_base,
    "/download/",
    micromamba_version,
    "/micromamba-",
    sys_arch_str
  )

  uncompressed_urls <- github_uncompressed

  # --- SHA256 checksum URLs ---
  # The .sha256 file from GitHub releases contains the hash of the final
  # standalone binary (not the archive). This allows verification regardless
  # of whether the compressed or uncompressed download was used.
  sha256_url <- paste0(
    github_base,
    "/download/",
    micromamba_version,
    "/micromamba-",
    sys_arch_str,
    ".sha256"
  )

  sha256_urls <- sha256_url

  # --- Connectivity check URLs ---
  check_urls <- c(
    github_base,
    "https://micro.mamba.pm",
    "https://api.anaconda.org",
    "https://repo.prefix.dev"
  )

  return(list(
    compressed = compressed_urls,
    uncompressed = uncompressed_urls,
    sha256 = sha256_urls,
    check_urls = check_urls
  ))
}
