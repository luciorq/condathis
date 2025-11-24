test_that("Format Channels args", {
  expect_equal(format_channels_args(), c("-c", "conda-forge", "-c", "bioconda"))
  expect_equal(
    format_channels_args(NULL),
    c("-c", "conda-forge", "-c", "bioconda")
  )
  expect_equal(format_channels_args(NA), c("-c", NA_character_))
  expect_equal(format_channels_args(1), c("-c", "1"))
  expect_equal(format_channels_args("A", "BCD"), c("-c", "A", "-c", "BCD"))
})
