# tests/testthat/test-is_micromamba_available_for_arch.R
testthat::test_that("is_micromamba_available_for_arch handles custom sys_arch input correctly", {
  # Test case for Linux-x86_64
  testthat::expect_equal(
    is_micromamba_available_for_arch("Linux-x86_64"),
    "linux-64"
  )

  # Test case for Darwin-x86_64 or MacOSX-x86_64
  testthat::expect_equal(
    is_micromamba_available_for_arch("Darwin-x86_64"),
    "osx-64"
  )
  testthat::expect_equal(
    is_micromamba_available_for_arch("MacOSX-x86_64"),
    "osx-64"
  )

  # Test case for Windows-x86_64
  testthat::expect_equal(
    is_micromamba_available_for_arch("Windows-x86_64"),
    "win-64"
  )
  # R on Windows reports "x86-64", also for an x64 R on an ARM64 PC.
  testthat::expect_equal(
    is_micromamba_available_for_arch("Windows-x86-64"),
    "win-64"
  )

  # Test case for a native ARM64 R on Windows: R reports "aarch64", and
  # "arm64" is the name Windows uses.
  testthat::expect_equal(
    is_micromamba_available_for_arch("Windows-aarch64"),
    "win-arm64"
  )
  testthat::expect_equal(
    is_micromamba_available_for_arch("Windows-arm64"),
    "win-arm64"
  )

  # Test case for Darwin-arm64 or MacOSX-arm64
  testthat::expect_equal(
    is_micromamba_available_for_arch("Darwin-arm64"),
    "osx-arm64"
  )
  testthat::expect_equal(
    is_micromamba_available_for_arch("MacOSX-arm64"),
    "osx-arm64"
  )

  # Test case for Linux-aarch64
  testthat::expect_equal(
    is_micromamba_available_for_arch("Linux-aarch64"),
    "linux-aarch64"
  )

  # Test case for Linux-ppc64le
  testthat::expect_equal(
    is_micromamba_available_for_arch("Linux-ppc64le"),
    "linux-ppc64le"
  )

  # Test case for Linux-riscv64
  testthat::expect_equal(
    is_micromamba_available_for_arch("Linux-riscv64"),
    "linux-riscv64"
  )

  # Test case for unsupported architecture
  testthat::expect_error(
    is_micromamba_available_for_arch("unsupported-arch"),
    "micromamba is not available for the .*unsupported-arch.* CPU architecture\\."
  )
  testthat::expect_error(
    is_micromamba_available_for_arch("Unknown-arch"),
    class = "condathis_umamba_not_available_for_arch"
  )
})

testthat::test_that("is_micromamba_available_for_arch() has the renamed class and the old one", {
  # Decision D2: condathis_umamba_* became condathis_micromamba_*.
  cnd <- testthat::expect_error(
    is_micromamba_available_for_arch("Unknown-arch"),
    class = "condathis_micromamba_not_available_for_arch"
  )
  testthat::expect_identical(
    class(cnd)[1:3],
    c(
      "condathis_micromamba_not_available_for_arch",
      "condathis_umamba_not_available_for_arch",
      "condathis_error"
    )
  )
})


# Mocking get_sys_arch to return specific values
mock_get_sys_arch <- function(value) {
  function() value
}

testthat::test_that("is_micromamba_available_for_arch returns correct architecture string", {
  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Linux-x86_64"),
    testthat::expect_equal(is_micromamba_available_for_arch(), "linux-64")
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Darwin-x86_64"),
    testthat::expect_equal(is_micromamba_available_for_arch(), "osx-64")
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Windows-x86_64"),
    testthat::expect_equal(is_micromamba_available_for_arch(), "win-64")
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Windows-aarch64"),
    testthat::expect_equal(is_micromamba_available_for_arch(), "win-arm64")
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Darwin-arm64"),
    testthat::expect_equal(is_micromamba_available_for_arch(), "osx-arm64")
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Linux-aarch64"),
    testthat::expect_equal(is_micromamba_available_for_arch(), "linux-aarch64")
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Linux-ppc64le"),
    testthat::expect_equal(is_micromamba_available_for_arch(), "linux-ppc64le")
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Linux-riscv64"),
    testthat::expect_equal(is_micromamba_available_for_arch(), "linux-riscv64")
  )

  with_mocked_bindings(
    get_sys_arch = mock_get_sys_arch("Unknown-arch"),
    testthat::expect_error(
      is_micromamba_available_for_arch(),
      class = "condathis_umamba_not_available_for_arch"
    )
  )
})

testthat::test_that("linux-riscv64 has micromamba builds from 2.9.0 on", {
  # conda-forge has linux-riscv64 builds from 2.9.0 on, and the GitHub
  # releases from 2.10.0-0 on.
  for (version in c("2.9.0", "2.10.0", "2.11.0", "3.0.0")) {
    testthat::expect_identical(
      is_micromamba_available_for_arch(
        "Linux-riscv64",
        micromamba_version = version
      ),
      "linux-riscv64"
    )
  }
  cnd <- testthat::expect_error(
    is_micromamba_available_for_arch(
      "Linux-riscv64",
      micromamba_version = "2.8.1"
    ),
    class = "condathis_micromamba_not_available_for_arch"
  )
  testthat::expect_s3_class(cnd, "condathis_umamba_not_available_for_arch")
  testthat::expect_match(
    conditionMessage(cnd),
    "2.8.1.*is not available for the .*Linux-riscv64.* CPU architecture"
  )
  testthat::expect_match(conditionMessage(cnd), "2.9.0")

  # Every other platform has builds of every supported version.
  for (sys_arch in c("Linux-x86_64", "Linux-aarch64", "Windows-aarch64")) {
    testthat::expect_type(
      is_micromamba_available_for_arch(sys_arch, micromamba_version = "2.8.1"),
      "character"
    )
  }
})

testthat::test_that("install_micromamba() checks the riscv64 version before it downloads", {
  condathis::with_sandbox_dir({
    tracked <- new.env(parent = emptyenv())
    tracked$downloaded <- FALSE
    testthat::local_mocked_bindings(
      get_sys_arch = function() "Linux-riscv64",
      download_compressed_and_extract = function(...) {
        tracked$downloaded <- TRUE
        return(FALSE)
      },
      download_uncompressed_binary = function(...) {
        tracked$downloaded <- TRUE
        return(FALSE)
      }
    )
    testthat::expect_error(
      install_micromamba(
        micromamba_version = "2.8.1-1",
        verbose = "silent",
        force = TRUE
      ),
      class = "condathis_micromamba_not_available_for_arch"
    )
    testthat::expect_false(tracked$downloaded)

    # 2.9.0 gets as far as the download (here a failed one).
    testthat::expect_error(
      install_micromamba(
        micromamba_version = "2.9.0-0",
        verbose = "silent",
        force = TRUE
      ),
      class = "condathis_install_micromamba_download_failed"
    )
    testthat::expect_true(tracked$downloaded)
  })
})
