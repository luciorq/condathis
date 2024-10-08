% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/install_packages.R
\name{install_packages}
\alias{install_packages}
\title{Install Packages in a Existing Conda Environment}
\usage{
install_packages(
  packages,
  env_name = "condathis-env",
  channels = c("bioconda", "conda-forge"),
  additional_channels = NULL,
  verbose = FALSE
)
}
\arguments{
\item{packages}{Character vector with the names of the packages and
version strings if necessary.}

\item{env_name}{Name of the Conda environment where the packages are
going to be installed. Defaults to 'condathis-env'.}

\item{channels}{Character vector. Names of the channels to be included.
By default 'c("bioconda", "conda-forge")' are used for solving
dependencies.}

\item{additional_channels}{Character. Additional Channels to be added to the
default ones.}

\item{verbose}{Logical. Should command and messages be print to
the console.
Defaults to \code{TRUE}.}
}
\description{
Install Packages in a Existing Conda Environment
}
