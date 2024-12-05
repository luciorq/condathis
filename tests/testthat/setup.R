withr::local_options(
  .new = list(
    warnPartialMatchArgs = TRUE,
    warnPartialMatchAttr = TRUE,
    warnPartialMatchDollar = TRUE
  ),
  .local_envir = testthat::teardown_env()
)

# fs::path(local_temp_dir, "home")
# fs::path_temp("tmp", "home", "data")

withr::local_envvar(
  .new = list(
    `HOME` = fs::path_temp("tmp", "home"),
    `USERPROFILE` = fs::path_temp("tmp", "home"),
    `LOCALAPPDATA` = fs::path_temp("tmp", "home", "data"),
    `APPDATA` = fs::path_temp("tmp", "home", "data"),
    `R_USER_DATA_DIR` = fs::path_temp("tmp", "home", "data"),
    `XDG_DATA_HOME` = fs::path_temp("tmp", "home", "data")
  )
)
