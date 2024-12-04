# Mocking get_sys_arch to return specific values
mock_get_sys_arch <- function(value) {
  function() value
}

# get_condathis_path()
testthat::test_that("get_sys_arch returns correct path for each os", {
  testthat::skip_on_os("windows")

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Linux-x86_64"),
    expect_equal(
      get_condathis_path(),
      tools::R_user_dir("condathis", which = "data")
    )
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Darwin-x86_64"),
    testthat::expect_equal(
      get_condathis_path(),
      withr::with_envvar(
        new = list(
          `XDG_DATA_HOME` = fs::path_home(".local", "share")
        ),
        code = {
          tools::R_user_dir("condathis", which = "data")
        }
      )
    )
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Darwin-arm64"),
    testthat::expect_equal(
      get_condathis_path(),
      withr::with_envvar(
        new = list(
          `XDG_DATA_HOME` = fs::path_home(".local", "share")
        ),
        code = {
          tools::R_user_dir("condathis", which = "data")
        }
      )
    )
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Unknown-arch"),
    testthat::expect_equal(
      get_condathis_path(),
      tools::R_user_dir("condathis", which = "data")
    )
  )
})
