testthat::test_that("parse_output works", {
  res <- list(
    stdout = "line1\nline2\nline3\n",
    stderr = "error1\nerror2\n",
    both = "this\nis\nrandom\ntext\n",
    status = 1L
  )

  testthat::expect_error(
    parse_output(res, stream = "plain"),
    class = "condathis_parse_output_invalid_res"
  )

  parsed_out <- parse_output(res, stream = "stdout")

  testthat::expect_true(rlang::is_character(parsed_out))

  parsed_err <- parse_output(res, stream = "stderr")
  testthat::expect_true(rlang::is_character(parsed_err))

  parsed_both <- parse_output(res, stream = "both")
  testthat::expect_true(rlang::is_character(parsed_both))

  testthat::expect_equal(
    parsed_out,
    c("line1", "line2", "line3")
  )

  testthat::expect_equal(
    parsed_err,
    c("error1", "error2")
  )

  testthat::expect_equal(
    parsed_both,
    c("line1", "line2", "line3", "error1", "error2")
  )

  testthat::expect_equal(
    parse_output(
      "This is line one.\nThis is line two.\nThis is line three.\n",
      stream = "plain"
    ),
    c("This is line one.", "This is line two.", "This is line three.")
  )

  res_empty <- list(
    stdout = "",
    stderr = ""
  )

  res_empty_parsed <- parse_output(res_empty, stream = "both")
  testthat::expect_identical(res_empty_parsed, character(0L))

  testthat::expect_error(
    parse_output(NULL, stream = "stdout"),
    class = "condathis_parse_output_invalid_res"
  )

  testthat::expect_error(
    parse_output(list(1), stream = "stdout"),
    class = "condathis_parse_output_invalid_res"
  )

  testthat::expect_error(
    parse_output(c("invalid", "input"), stream = "stdout"),
    class = "condathis_parse_output_invalid_res"
  )

  testthat::expect_equal(
    parse_output(c("invalid", "input"), stream = "plain"),
    c("invalid", "input")
  )
})

testthat::test_that("parse_output rejects raw binary streams", {
  res_binary <- list(
    stdout = as.raw(c(0x00, 0x01, 0xFF)),
    stderr = "error1\n"
  )

  testthat::expect_error(
    parse_output(res_binary, stream = "stdout"),
    class = "condathis_parse_output_binary_stream"
  )

  testthat::expect_error(
    parse_output(res_binary, stream = "both"),
    class = "condathis_parse_output_binary_stream"
  )

  # stderr alone is still text, unaffected by a raw stdout
  testthat::expect_equal(
    parse_output(res_binary, stream = "stderr"),
    c("error1")
  )

  res_binary_both <- list(
    stdout = as.raw(1:3),
    stderr = as.raw(4:6)
  )
  testthat::expect_error(
    parse_output(res_binary_both, stream = "stderr"),
    class = "condathis_parse_output_binary_stream"
  )
})

testthat::test_that("parse_output() reads run_pipeline() results", {
  # Regression test: a pipeline result has no top-level `stdout`/`stderr`,
  # so parse_output() rejected it and callers had to dig into
  # `res$processes[[n]]` themselves.
  proc <- function(stdout, stderr) {
    list(
      cmd = "x",
      env_name = "e",
      status = 0L,
      stdout = stdout,
      stderr = stderr,
      pid = 1L,
      timeout = FALSE
    )
  }
  res <- new_condathis_pipeline(
    statuses = c(0L, 0L, 0L),
    processes = list(
      proc(NA_character_, "first warning\n"),
      proc(NA_character_, ""),
      proc("line 1\nline 2\n", "last warning\n")
    )
  )
  testthat::expect_identical(parse_output(res), c("line 1", "line 2"))
  testthat::expect_identical(
    parse_output(res, stream = "stderr"),
    c("first warning", "last warning")
  )
  testthat::expect_identical(
    parse_output(res, stream = "both"),
    c("line 1", "line 2", "first warning", "last warning")
  )

  # The last command's stdout redirected to a file: no stdout stream.
  redirected <- new_condathis_pipeline(
    statuses = c(0L, 0L),
    processes = list(proc(NA_character_, ""), proc(NULL, "only stderr\n"))
  )
  testthat::expect_error(
    parse_output(redirected),
    class = "condathis_parse_output_invalid_res"
  )
  testthat::expect_identical(
    parse_output(redirected, stream = "stderr"),
    "only stderr"
  )

  # Binary pipeline output is reported, not decoded.
  binary <- new_condathis_pipeline(
    statuses = 0L,
    processes = list(proc(as.raw(c(0x89, 0x50)), raw(0L)))
  )
  testthat::expect_error(
    parse_output(binary),
    class = "condathis_parse_output_binary_stream"
  )
})

testthat::test_that("parse_output() never reads raw_text from the caller", {
  # Regression test: `exists("raw_text")` also found a workspace variable
  # of that name and returned its value.
  raw_text <- "LEAKED"
  testthat::expect_error(
    parse_output(list(stdout = "x"), stream = "stderr"),
    class = "condathis_parse_output_invalid_res"
  )
  # A stream that was not captured is NA in a result object.
  testthat::expect_error(
    parse_output(list(stdout = NA_character_, stderr = "e"), stream = "stdout"),
    class = "condathis_parse_output_invalid_res"
  )
})

testthat::test_that("parse_output() keeps the last line of each stream apart", {
  # Regression test: a stream without a trailing newline merged with the
  # next one ("warn" + "err" became "warnerr").
  testthat::expect_identical(
    parse_output(list(stdout = "out", stderr = "err"), stream = "both"),
    c("out", "err")
  )
})

testthat::test_that("parse_output() keeps the text as the command wrote it", {
  stdout_lines <- function(text) parse_output(list(stdout = text))

  # Tab-separated fields: an empty first or last field stays in place.
  testthat::expect_identical(
    stdout_lines("\tchr1\t100\n\tchr2\t200\n"),
    c("\tchr1\t100", "\tchr2\t200")
  )
  testthat::expect_identical(stdout_lines("a\tb\t\n"), "a\tb\t")
  # Indentation is meaningful in YAML.
  testthat::expect_identical(
    stdout_lines("a:\n  b: 1\n"),
    c("a:", "  b: 1")
  )
  # Blank lines stay, wherever they are: `[1]` is the first line.
  testthat::expect_identical(
    stdout_lines("\nheader\n\nbody\n\n"),
    c("", "header", "", "body", "")
  )
  testthat::expect_identical(stdout_lines("  \n"), "  ")
})

testthat::test_that("parse_output() splits lines at \\n, \\r\\n and \\r", {
  stdout_lines <- function(text) parse_output(list(stdout = text))
  read_lines <- function(text) {
    con <- rawConnection(charToRaw(text))
    on.exit(close(con))
    readLines(con, warn = FALSE)
  }
  cases <- c(
    "a\nb\n",
    "a\nb",
    "a\r\nb\r\n",
    "a\rb\r",
    "a\r\n\r\nb",
    "10%\r50%\r100%\ndone\n",
    "\n",
    "\n\n",
    "a\n\n",
    "page1\fpage2\vend\n"
  )
  for (text in cases) {
    testthat::expect_identical(stdout_lines(text), read_lines(text))
  }
  # Empty output has no lines.
  testthat::expect_identical(stdout_lines(""), character(0L))
  testthat::expect_identical(read_lines(""), character(0L))
  # A carriage return, then a Windows line end: two line ends.
  # `readLines()` reads three, as it turns a second "\r" into "\n".
  testthat::expect_identical(stdout_lines("a\r\r\nb"), c("a", "", "b"))
})

testthat::test_that("parse_output(trim = TRUE) trims lines and the output", {
  testthat::expect_identical(
    parse_output(
      list(stdout = "\n  header \t\n\n\tbody\r\n  \n"),
      trim = TRUE
    ),
    c("header", "", "body")
  )
  testthat::expect_identical(
    parse_output(list(stdout = "  \n\n"), trim = TRUE),
    character(0L)
  )
  testthat::expect_identical(
    parse_output(list(stdout = ""), trim = TRUE),
    character(0L)
  )
  testthat::expect_identical(
    parse_output(" 2.9.0 ", stream = "plain", trim = TRUE),
    "2.9.0"
  )
  for (bad in list(NA, "yes", c(TRUE, FALSE), 1L, NULL)) {
    testthat::expect_error(
      parse_output(list(stdout = "x"), trim = bad),
      class = "condathis_parse_output_invalid_trim"
    )
  }
})

testthat::test_that("parse_output() reports streams that were not captured", {
  # Regression test: `"both"` returned "" when neither stream was captured,
  # while `"stdout"` and `"stderr"` errored.
  testthat::expect_error(
    parse_output(
      list(stdout = NA_character_, stderr = NA_character_),
      stream = "both"
    ),
    class = "condathis_parse_output_invalid_res"
  )
  testthat::expect_error(
    parse_output(list(stdout = NA_character_), stream = "both"),
    class = "condathis_parse_output_invalid_res"
  )
  # One captured stream is enough for `"both"`.
  testthat::expect_identical(
    parse_output(list(stdout = NA_character_, stderr = "e\n"), "both"),
    "e"
  )
  testthat::expect_identical(
    parse_output(list(stdout = "o\n", stderr = NA_character_), "both"),
    "o"
  )
  testthat::expect_error(
    parse_output(list(stdout = "o\n", stderr = NA_character_), "stderr"),
    class = "condathis_parse_output_invalid_res"
  )
  # Stream names match exactly: `stdout_file` is not `stdout`.
  testthat::expect_identical(
    parse_output(list(stdout_file = "/tmp/out.txt", stderr = "e\n"), "both"),
    "e"
  )
  # A character vector has no streams.
  testthat::expect_error(
    parse_output("abc", stream = "both"),
    class = "condathis_parse_output_invalid_res"
  )
})

testthat::test_that("parse_output(stream = 'plain') rejects missing values", {
  # Regression test: NA became the string "NA".
  testthat::expect_error(
    parse_output(NA_character_, stream = "plain"),
    class = "condathis_parse_output_invalid_res"
  )
  testthat::expect_error(
    parse_output(c(NA, "x"), stream = "plain"),
    class = "condathis_parse_output_invalid_res"
  )
  testthat::expect_identical(
    parse_output(character(0L), stream = "plain"),
    character(0L)
  )
  # Elements are joined with line ends; each can hold several lines.
  testthat::expect_identical(
    parse_output(c("a\nb", "", "c"), stream = "plain"),
    c("a", "b", "", "c")
  )
  # A list is still not plain text.
  testthat::expect_error(
    parse_output(list(stdout = NA_character_), stream = "plain"),
    class = "condathis_parse_output_invalid_res"
  )
})

testthat::test_that("parse_output() argument errors have the classes of rule R1", {
  # Regression test: an invalid `stream` failed with a plain rlang error,
  # and no error had the shared classes.
  cnd <- testthat::expect_error(
    parse_output(list(stdout = "x"), stream = "bogus"),
    class = "condathis_invalid_stream"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_parse_output_invalid_stream",
      "condathis_invalid_stream",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  testthat::expect_identical(
    rlang::call_name(conditionCall(cnd)),
    "parse_output"
  )
  testthat::expect_error(
    parse_output(list(stdout = "x"), stream = c("stdout", "stderr")),
    class = "condathis_parse_output_invalid_stream"
  )

  cnd <- testthat::expect_error(
    parse_output(list(stdout = "x"), trim = "yes"),
    class = "condathis_parse_output_invalid_trim"
  )
  testthat::expect_identical(
    class(cnd)[1:4],
    c(
      "condathis_parse_output_invalid_trim",
      "condathis_invalid_trim",
      "condathis_invalid_arg",
      "condathis_error"
    )
  )
  testthat::expect_match(conditionMessage(cnd), "must be")

  for (res in list(1, list(status = 0L), NULL)) {
    cnd <- testthat::expect_error(
      parse_output(res),
      class = "condathis_parse_output_invalid_res"
    )
    testthat::expect_identical(
      class(cnd)[1:4],
      c(
        "condathis_parse_output_invalid_res",
        "condathis_invalid_res",
        "condathis_invalid_arg",
        "condathis_error"
      )
    )
  }
  testthat::expect_error(
    parse_output(c("a", NA), stream = "plain"),
    class = "condathis_invalid_res"
  )
  # A character vector read with a stream name gives a hint.
  cnd <- testthat::expect_error(
    parse_output("text"),
    class = "condathis_parse_output_invalid_res"
  )
  testthat::expect_match(
    conditionMessage(cnd),
    "stream = \"plain\"",
    fixed = TRUE
  )

  cnd <- testthat::expect_error(
    parse_output(list(stdout = as.raw(1L))),
    class = "condathis_parse_output_binary_stream"
  )
  testthat::expect_true(
    all(c("condathis_invalid_res", "condathis_error") %in% class(cnd))
  )
})
