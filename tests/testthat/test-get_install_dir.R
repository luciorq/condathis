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
      rappdirs::user_data_dir(
        appname = "condathis",
        appauthor = "luciorq"
      )
    )
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Darwin-x86_64"),
    expect_equal(get_condathis_path(), rappdirs::user_data_dir(
      appname = "condathis",
      appauthor = "luciorq",
      os = "unix"
    ))
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Darwin-arm64"),
    testthat::expect_equal(
      get_condathis_path(),
      rappdirs::user_data_dir(
        appname = "condathis",
        appauthor = "luciorq",
        os = "unix"
      )
    )
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Unknown-arch"),
    testthat::expect_equal(
      get_condathis_path(),
      rappdirs::user_data_dir(
        appname = "condathis",
        appauthor = "luciorq"
      )
    )
  )
})
