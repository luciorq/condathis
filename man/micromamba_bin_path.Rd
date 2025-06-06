% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/micromamba_bin_path.R
\name{micromamba_bin_path}
\alias{micromamba_bin_path}
\title{Retrieve Path to the \code{micromamba} Executable}
\usage{
micromamba_bin_path()
}
\value{
A character string representing the full path to the \code{micromamba} executable.
The path differs depending on the operating system:
\describe{
\item{Windows}{\verb{<install_dir>/micromamba/Library/bin/micromamba.exe}}
\item{Other OS (e.g., Linux, macOS)}{\verb{<install_dir>/micromamba/bin/micromamba}}
}
}
\description{
This function returns the file path to the \code{micromamba} executable managed
by the \code{condathis} package. The path is determined based on the system's
operating system and architecture.
}
\examples{
condathis::with_sandbox_dir({
  # Retrieve the path to where micromamba executable is searched
  micromamba_path <- condathis::micromamba_bin_path()
  print(micromamba_path)
})

}
