% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/get_install_dir.R
\name{get_install_dir}
\alias{get_install_dir}
\title{Retrieve and Create the \code{condathis} Data Directory}
\usage{
get_install_dir()
}
\value{
A character string representing the normalized, real path to the \code{condathis} data directory.
}
\description{
Retrieves the installation directory for the \code{condathis} package, creating it if it does not exist.
This function ensures that the package data directory complies with the \href{https://specifications.freedesktop.org/basedir-spec/latest/}{freedesktop's XDG Base Directory Specification}.
The base path can be controlled by the \code{XDG_DATA_HOME} environment variable.
Additionally, on Windows, \verb{\%LOCALAPPDATA\%} is also accepted as the base installation directory.
}
\details{
If the directory does not exist, it will be created. On macOS,
special handling is applied to avoid spaces in the path,
as \verb{micromamba run} fails if there are spaces in the path (e.g., in \verb{~/Library/Application Support/condathis}).
Therefore, Unix-style paths are used on macOS.
}
\examples{
if (interactive()) {
  condathis::with_sandbox_dir({
    message("The installation directory for condathis is:")
    print(condathis::get_install_dir())
    #> /home/username/.local/share/condathis
  })
}
}
