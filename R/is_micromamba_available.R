#' Check if Micromamba is Available for OS and CPU architecture
is_micromamba_available_for_arch <- function() {
  sys_arch <- get_sys_arch()
  sys_arch_str <- ifelse(
    test = sys_arch == "Linux-x86_64", yes = "linux-64",
    no = ifelse(
      test = sys_arch == "Darwin-x86_64" | sys_arch == "MacOSX-x86_64",
      yes = "osx-64",
      no = ifelse(
        test = sys_arch == "Windows-x86_64",
        yes = "win-64",
        no = ifelse(
          test = sys_arch == "Darwin-arm64" | sys_arch == "MacOSX-arm64",
          yes = "osx-arm64",
          no = ifelse(
            test = sys_arch == "Linux-aarch64",
            yes = "linux-aarch64",
            no = ifelse(
              test = sys_arch == "Linux-ppc64le",
              yes = "linux-ppc64le",
              no = ""
            )
          )
        )
      )
    )
  )
  if (isTRUE(sys_arch_str == "")) {
    cli::cli_abort(c(
      `x` = "{.pkg micromamba} is not available for {.field {sys_arch}} CPU architecture."
    ))
  }
  return(sys_arch_str)
}
