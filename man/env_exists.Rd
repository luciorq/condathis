% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/env_exists.R
\name{env_exists}
\alias{env_exists}
\title{Check If Environment Already exists}
\usage{
env_exists(env_name)
}
\arguments{
\item{env_name}{Character. Name of the Conda environment where the packages
are going to be installed. Defaults to 'condathis-env'.}
}
\value{
Boolean. \code{TRUE} if the environment exists and \code{FALSE} otherwise.
}
\description{
This function checks whether a specified Conda environment already exists
in the available environments. It returns \code{TRUE} if the environment exists
and \code{FALSE} otherwise.
}
\examples{
\dontrun{
condathis::with_sandbox_dir({
  # Create the environment
  condathis::create_env(
    packages = "fastqc",
    env_name = "fastqc-env"
  )

  # Check if the environment exists
  condathis::env_exists("fastqc-env")
  #> [1] TRUE

  # Check for a non-existent environment
  condathis::env_exists("non-existent-env")
  #> [1] FALSE
})
}

}
