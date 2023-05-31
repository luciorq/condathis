test_that("Micromamba availability for different architectures", {
  # Test case for Linux-x86_64
  expect_equal(is_micromamba_available_for_arch("Linux-x86_64"), "linux-64")

  # Test case for Darwin-x86_64 or MacOSX-x86_64
  expect_equal(is_micromamba_available_for_arch("Darwin-x86_64"), "osx-64")
  expect_equal(is_micromamba_available_for_arch("MacOSX-x86_64"), "osx-64")

  # Test case for Windows-x86_64
  expect_equal(is_micromamba_available_for_arch("Windows-x86_64"), "win-64")

  # Test case for Darwin-arm64 or MacOSX-arm64
  expect_equal(is_micromamba_available_for_arch("Darwin-arm64"), "osx-arm64")
  expect_equal(is_micromamba_available_for_arch("MacOSX-arm64"), "osx-arm64")

  # Test case for Linux-aarch64
  expect_equal(is_micromamba_available_for_arch("Linux-aarch64"), "linux-aarch64")

  # Test case for Linux-ppc64le
  expect_equal(is_micromamba_available_for_arch("Linux-ppc64le"), "linux-ppc64le")

  # Test case for unsupported architecture
  expect_error(is_micromamba_available_for_arch("unsupported-arch"), 
               "micromamba is not available for unsupported-arch CPU architecture.")
})
