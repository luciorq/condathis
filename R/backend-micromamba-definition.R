# Environment definitions (`env_definition()`) for the micromamba backend.
#
# micromamba 2.10.0 picks the reader of `micromamba create -f <file>` by
# the file name (`libmamba/src/api/install.cpp`):
# * a name that ends in `-lock.yml` or `-lock.yaml`: a conda-lock file,
#   version 1;
# * another name that ends in `.yml` or `.yaml`: an environment YAML file;
# * a name that ends in `.json`: a mambajs lock file;
# * any other name: a text file, read as an `@EXPLICIT` file when it has an
#   `@EXPLICIT` line, else as one package spec per line.
# The comparison is case-sensitive: `ENV.YML` is a text file. A conda-lock
# file under another name gives an empty environment with exit status 0,
# and a pixi.lock file is read as a list of specs. So the backend reads the
# contents itself, without a YAML parser, and gives micromamba a copy under
# a name it reads correctly.

#' The formats that the micromamba backend reads
#'
#' @keywords internal
#' @noRd
micromamba_definition_formats <- c(
  "environment-yaml",
  "requirements",
  "explicit",
  "conda-lock-v1",
  "mambajs-lock-v1"
)

#' The `format` names that the micromamba backend accepts
#'
#' Names are compared in lower case. The values are the formats of
#' `micromamba_definition_formats`, or `"rattler-lock"` for a pixi.lock
#' file, which micromamba does not read.
#'
#' @keywords internal
#' @noRd
micromamba_format_aliases <- c(
  `environment-yaml` = "environment-yaml",
  `cep-24` = "environment-yaml",
  `requirements` = "requirements",
  `explicit` = "explicit",
  `conda-lock-v1` = "conda-lock-v1",
  `conda-lock` = "conda-lock-v1",
  `mambajs-lock-v1` = "mambajs-lock-v1",
  `mambajs` = "mambajs-lock-v1",
  `rattler-lock-v6` = "rattler-lock",
  `rattler-lock-v7` = "rattler-lock",
  `pixi` = "rattler-lock"
)

#' The `backend_definition_formats()` function of the micromamba backend
#'
#' @keywords internal
#' @noRd
micromamba_backend_definition_formats <- function(backend) {
  return(c(micromamba_definition_formats, "cep-24"))
}

#' The `backend_describe_definition()` function of the micromamba backend
#'
#' Reads the file, starts no process. See `micromamba_read_definition()`.
#'
#' @param backend The micromamba backend object.
#' @param definition A `condathis_env_definition` object.
#' @param platform Not used: the platforms of a lock come from the file.
#'
#' @returns A list, as `definition_description()`.
#'
#' @keywords internal
#' @noRd
micromamba_backend_describe_definition <- function(
  backend,
  definition,
  platform = NULL
) {
  return(micromamba_read_definition(definition)$description)
}

#' What micromamba makes of an environment definition
#'
#' The format comes from `definition$format` when it is given, else from
#' the contents of the file (see `micromamba_sniff_definition()`). A lock
#' format given by name must match the contents. Then the name of the file
#' must be one that micromamba reads as that format (see
#' `micromamba_name_kind()`). When it is not, a list of specs, an
#' `@EXPLICIT` file, a conda-lock file and a mambajs file are copied under
#' another name (`stage_name`). An environment YAML file is refused
#' instead: a `pip:` section can name files relative to the file, as in
#' `-r requirements.txt`, and a copy elsewhere would break them.
#'
#' The only option is `categories`, for a conda-lock file: the
#' `--category` of `micromamba create`. micromamba installs the `main`
#' category by default.
#'
#' @param definition A `condathis_env_definition` object.
#'
#' @returns A list:
#'   * `description`: as `definition_description()`. `supported` is `NA`
#'     when the file cannot be read.
#'   * `stage_name`: `NULL`, or the file name of the copy to pass.
#'   * `extra_args`: character vector of arguments for `micromamba create`,
#'     such as `c("--category", "main", "dev")`.
#'
#' @keywords internal
#' @noRd
micromamba_read_definition <- function(definition) {
  path <- definition[["path"]]
  format_arg <- definition[["format"]]
  options <- definition[["options"]]
  refuse <- function(reason, format = NA_character_) {
    return(list(
      description = definition_description(
        supported = FALSE,
        format = format,
        reason = reason
      ),
      stage_name = NULL,
      extra_args = character(0L)
    ))
  }
  pixi_reason <- "micromamba does not read pixi.lock files. Use a backend that reads them, or export the environment to an @EXPLICIT or conda-lock file."
  if (isTRUE(fs::dir_exists(path))) {
    return(refuse("micromamba reads an environment file, not a directory."))
  }
  lines <- tryCatch(
    suppressWarnings(readLines(path, warn = FALSE, encoding = "UTF-8")),
    error = function(e) NULL
  )
  if (is.null(lines)) {
    return(list(
      description = definition_description(),
      stage_name = NULL,
      extra_args = character(0L)
    ))
  }
  detected <- micromamba_sniff_definition(lines, path)
  lock_formats <- c("explicit", "conda-lock-v1", "mambajs-lock-v1")
  if (isFALSE(is.null(format_arg))) {
    format <- unname(micromamba_format_aliases[tolower(format_arg)])
    if (isTRUE(is.na(format))) {
      return(refuse(
        paste0(
          "micromamba does not read format '",
          format_arg,
          "'. It reads: ",
          paste(micromamba_definition_formats, collapse = ", "),
          "."
        ),
        format = format_arg
      ))
    }
    if (identical(format, "rattler-lock")) {
      return(refuse(pixi_reason, format = format_arg))
    }
    content_is_lock <- isTRUE(
      detected %in% c(lock_formats, "conda-lock-other", "rattler-lock")
    )
    if (
      (isTRUE(format %in% lock_formats) && isFALSE(identical(detected, format))) ||
        (isFALSE(format %in% lock_formats) && isTRUE(content_is_lock)) ||
        identical(detected, "json-other")
    ) {
      return(refuse(
        paste0(
          "The file does not have the contents of format '",
          format_arg,
          "': it reads as '",
          detected,
          "'."
        ),
        format = format_arg
      ))
    }
  } else {
    format <- detected
    if (identical(format, "rattler-lock")) {
      return(refuse(pixi_reason, format = "rattler-lock"))
    }
    if (identical(format, "conda-lock-other")) {
      return(refuse(
        "micromamba reads only version 1 of conda-lock files.",
        format = "conda-lock"
      ))
    }
    if (identical(format, "json-other")) {
      return(refuse(
        "micromamba reads a JSON file only as a mambajs lock file, which has a 'lockVersion' field."
      ))
    }
  }

  extra_args <- character(0L)
  option_names <- rlang::names2(options)
  unknown <- setdiff(option_names, "categories")
  if (isTRUE(length(unknown) > 0L)) {
    return(refuse(
      paste0(
        "micromamba does not understand the option",
        if (isTRUE(length(unknown) > 1L)) "s" else "",
        " ",
        paste0("'", unknown, "'", collapse = ", "),
        ". It takes only 'categories', for a conda-lock file."
      ),
      format = format
    ))
  }
  categories <- "main"
  if (isTRUE("categories" %in% option_names)) {
    if (isFALSE(identical(format, "conda-lock-v1"))) {
      return(refuse(
        "The option 'categories' applies only to conda-lock files.",
        format = format
      ))
    }
    categories <- options[["categories"]]
    if (
      isFALSE(is.character(categories)) ||
        identical(length(categories), 0L) ||
        isTRUE(anyNA(categories)) ||
        isFALSE(all(nzchar(categories)))
    ) {
      return(refuse(
        "The option 'categories' must be a character vector of category names, such as c(\"main\", \"dev\").",
        format = format
      ))
    }
    categories <- unique(categories)
    extra_args <- c("--category", categories)
  }

  needed_kind <- switch(
    format,
    `environment-yaml` = "yaml",
    `requirements` = "text",
    `explicit` = "text",
    `conda-lock-v1` = "conda-lock",
    `mambajs-lock-v1` = "mambajs"
  )
  stage_name <- NULL
  if (isFALSE(identical(micromamba_name_kind(path), needed_kind))) {
    if (identical(format, "environment-yaml")) {
      return(refuse(
        "micromamba reads an environment YAML file only when its name ends in '.yml' or '.yaml', and not in '-lock.yml' or '-lock.yaml'. Rename the file, for example to 'environment.yml'. condathis does not pass a copy: the 'pip:' section can name files relative to the file.",
        format = format
      ))
    }
    stage_name <- switch(
      format,
      `requirements` = "requirements.txt",
      `explicit` = "explicit.txt",
      `conda-lock-v1` = "conda-lock.yml",
      `mambajs-lock-v1` = "mambajs-lock.json"
    )
  }

  kind <- if (isTRUE(format %in% lock_formats)) "lock" else "request"
  lock_info <- switch(
    format,
    `explicit` = micromamba_explicit_info(lines),
    `conda-lock-v1` = micromamba_conda_lock_info(lines, categories = categories),
    `mambajs-lock-v1` = micromamba_mambajs_info(path),
    list(platforms = NULL, records = NULL)
  )
  return(list(
    description = definition_description(
      supported = TRUE,
      format = format,
      kind = kind,
      platforms = lock_info$platforms,
      records = lock_info$records
    ),
    stage_name = stage_name,
    extra_args = extra_args
  ))
}

#' The format of an environment file, from its contents
#'
#' A text search, without a YAML parser, in this order:
#' 1. JSON (the first character that is not a space is `{`): a mambajs
#'    lock file when it has a `"lockVersion"` field, else `"json-other"`.
#' 2. An `@EXPLICIT` line: `"explicit"`.
#' 3. A top-level `version:` and `environments:`: a pixi.lock file,
#'    `"rattler-lock"`.
#' 4. A top-level `version:` and `package:`: a conda-lock file,
#'    `"conda-lock-v1"` for version 1, else `"conda-lock-other"`.
#' 5. A top-level key of an environment YAML file (`name:`, `channels:`,
#'    `dependencies:`, `variables:`, `prefix:`), or a name that ends in
#'    `.yml` or `.yaml`: `"environment-yaml"`.
#' 6. Anything else: a list of specs, `"requirements"`.
#'
#' @param lines Character vector, the lines of the file.
#' @param path Character string, the path of the file.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
micromamba_sniff_definition <- function(lines, path) {
  text_lines <- lines[nzchar(trimws(lines))]
  if (
    isTRUE(length(text_lines) > 0L) &&
      isTRUE(startsWith(trimws(text_lines[[1L]]), "{"))
  ) {
    if (isTRUE(any(grepl("\"lockVersion\"[[:space:]]*:", lines, useBytes = TRUE)))) {
      return("mambajs-lock-v1")
    }
    return("json-other")
  }
  if (isTRUE(any(grepl("^[[:space:]]*@EXPLICIT[[:space:]]*$", lines, useBytes = TRUE)))) {
    return("explicit")
  }
  version_line <- grep("^version:", lines, value = TRUE, useBytes = TRUE)
  if (isTRUE(length(version_line) > 0L)) {
    if (isTRUE(any(grepl("^environments:", lines, useBytes = TRUE)))) {
      return("rattler-lock")
    }
    if (isTRUE(any(grepl("^package:", lines, useBytes = TRUE)))) {
      version <- trimws(gsub(
        "[\"']",
        "",
        sub("^version:([^#]*).*$", "\\1", version_line[[1L]])
      ))
      if (identical(version, "1")) {
        return("conda-lock-v1")
      }
      return("conda-lock-other")
    }
  }
  yaml_keys <- "^(name|channels|dependencies|variables|prefix)[[:space:]]*:"
  if (
    isTRUE(any(grepl(yaml_keys, lines, useBytes = TRUE))) ||
      isTRUE(grepl("\\.ya?ml$", path, ignore.case = TRUE))
  ) {
    return("environment-yaml")
  }
  return("requirements")
}

#' How micromamba reads a file, by its name
#'
#' The rules of `micromamba create -f` in micromamba 2.10.0 (see the top of
#' this file). Case-sensitive, as micromamba.
#'
#' @param path Character string.
#'
#' @returns `"conda-lock"`, `"yaml"`, `"mambajs"` or `"text"`.
#'
#' @keywords internal
#' @noRd
micromamba_name_kind <- function(path) {
  name <- basename(as.character(path))
  if (isTRUE(endsWith(name, "-lock.yml")) || isTRUE(endsWith(name, "-lock.yaml"))) {
    return("conda-lock")
  }
  if (isTRUE(endsWith(name, ".yml")) || isTRUE(endsWith(name, ".yaml"))) {
    return("yaml")
  }
  if (isTRUE(endsWith(name, ".json"))) {
    return("mambajs")
  }
  return("text")
}

#' An empty records data frame
#'
#' @keywords internal
#' @noRd
empty_definition_records <- function() {
  return(data.frame(
    name = character(0L),
    version = character(0L),
    build_string = character(0L),
    platform = character(0L),
    stringsAsFactors = FALSE
  ))
}

#' Read a package file name as name, version and build
#'
#' @param file_names Character vector of package file names or URLs, such
#'   as `"polyglot-0.1.0-h4616a5c_0.conda"`.
#'
#' @returns A data frame with the character columns `name`, `version` and
#'   `build_string`, `NA` where a name does not have three parts.
#'
#' @keywords internal
#' @noRd
split_package_file_names <- function(file_names) {
  base <- sub("[#?].*$", "", basename(as.character(file_names)))
  base <- sub("\\.(conda|tar\\.bz2)$", "", base)
  pattern <- "^(.+)-([^-]+)-([^-]+)$"
  matched <- grepl(pattern, base)
  return(data.frame(
    name = ifelse(matched, sub(pattern, "\\1", base), NA_character_),
    version = ifelse(matched, sub(pattern, "\\2", base), NA_character_),
    build_string = ifelse(matched, sub(pattern, "\\3", base), NA_character_),
    stringsAsFactors = FALSE
  ))
}

#' Platforms and records of an `@EXPLICIT` file
#'
#' Each line after `@EXPLICIT` that is not a comment is the URL of a
#' package file. The platform of a record is the subdir of its URL, such as
#' `noarch` or `linux-64`. micromamba installs every URL, whatever the
#' `# platform: <subdir>` header that conda, micromamba and pixi write says,
#' so a file of `noarch` packages installs on any platform. The header
#' counts only for a URL without a known subdir, and for a file without
#' URLs.
#'
#' @param lines Character vector, the lines of the file.
#'
#' @returns A list with `platforms` (the subdirs of the URLs other than
#'   `noarch`, else the header platforms; `NULL` when there are none) and
#'   `records` (a data frame; `platform` is the subdir of the URL, else the
#'   header platform, or `NA`).
#'
#' @keywords internal
#' @noRd
micromamba_explicit_info <- function(lines) {
  header <- grep(
    "^#[[:space:]]*platform:[[:space:]]*[^[:space:]]+",
    lines,
    value = TRUE,
    useBytes = TRUE
  )
  platforms <- NULL
  if (isTRUE(length(header) > 0L)) {
    platforms <- unique(trimws(sub(
      "^#[[:space:]]*platform:[[:space:]]*([^[:space:]]+).*$",
      "\\1",
      header
    )))
  }
  marker <- which(grepl("^[[:space:]]*@EXPLICIT[[:space:]]*$", lines, useBytes = TRUE))
  urls <- character(0L)
  if (isTRUE(length(marker) > 0L) && isTRUE(marker[[1L]] < length(lines))) {
    urls <- trimws(lines[seq(marker[[1L]] + 1L, length(lines))])
    urls <- urls[nzchar(urls) & !startsWith(urls, "#")]
  }
  records <- empty_definition_records()
  if (isTRUE(length(urls) > 0L)) {
    records <- split_package_file_names(urls)
    header_platform <- if (identical(length(platforms), 1L)) {
      platforms
    } else {
      NA_character_
    }
    subdirs <- basename(dirname(sub("[#?].*$", "", urls)))
    known <- subdirs %in% known_platforms
    records$platform <- ifelse(known, subdirs, header_platform)
    if (isTRUE(any(known))) {
      platforms <- lock_record_platforms(records)
    }
  }
  return(list(platforms = platforms, records = records))
}

#' The platforms of the records of a lock, other than `noarch`
#'
#' @param records A records data frame.
#'
#' @returns `NULL`, or the platforms of the records other than `noarch`
#'   and `NA`.
#'
#' @keywords internal
#' @noRd
lock_record_platforms <- function(records) {
  platform <- as.character(records[["platform"]])
  listed <- unique(setdiff(platform[!is.na(platform)], "noarch"))
  if (identical(length(listed), 0L)) {
    return(NULL)
  }
  return(listed)
}

#' Platforms and records of a conda-lock file, version 1
#'
#' Reads the items of the top-level `package:` list line by line: the
#' scalar keys `name`, `version`, `manager`, `platform`, `url` and
#' `category` of each item. Items of another manager than `conda` (pip)
#' are left out of the records.
#'
#' @param lines Character vector, the lines of the file.
#' @param categories Character vector, the categories that micromamba
#'   installs: `"main"` unless the option `categories` is given.
#'
#' @returns A list with `platforms` (the platforms of every conda item, or
#'   `NULL`) and `records` (the conda items of `categories`).
#'
#' @keywords internal
#' @noRd
micromamba_conda_lock_info <- function(lines, categories = "main") {
  items <- read_conda_lock_items(lines)
  if (identical(length(items), 0L)) {
    return(list(platforms = NULL, records = empty_definition_records()))
  }
  field <- function(key) {
    return(vapply(
      items,
      function(item) item[[key]] %||% NA_character_,
      character(1L)
    ))
  }
  manager <- field("manager")
  is_conda <- is.na(manager) | manager == "conda"
  platform <- field("platform")
  category <- field("category")
  category[is.na(category)] <- "main"
  url <- field("url")
  platforms <- unique(platform[is_conda & !is.na(platform)])
  keep <- is_conda & category %in% categories
  builds <- split_package_file_names(ifelse(is.na(url), "", url))$build_string
  records <- data.frame(
    name = field("name")[keep],
    version = field("version")[keep],
    build_string = builds[keep],
    platform = platform[keep],
    stringsAsFactors = FALSE
  )
  return(list(
    platforms = if (isTRUE(length(platforms) > 0L)) platforms,
    records = records
  ))
}

#' The items of the `package:` list of a conda-lock file
#'
#' A line reader for the block style that conda-lock writes: `package:` at
#' the top level, then items that start with `- ` at one indentation, with
#' their keys two columns further in. The first key can be on the `- `
#' line. Only scalar values of keys at that level are read; nested keys
#' (`hash:`, `dependencies:`) are skipped.
#'
#' @param lines Character vector, the lines of the file.
#'
#' @returns A list with one named list of strings per item.
#'
#' @keywords internal
#' @noRd
read_conda_lock_items <- function(lines) {
  start <- which(grepl("^package:[[:space:]]*$", lines, useBytes = TRUE))
  if (identical(length(start), 0L) || isTRUE(start[[1L]] >= length(lines))) {
    return(list())
  }
  body <- lines[seq(start[[1L]] + 1L, length(lines))]
  # The block ends at the next top-level key.
  block_end <- which(grepl("^[^[:space:]#-]", body, useBytes = TRUE))
  if (isTRUE(length(block_end) > 0L)) {
    body <- body[seq_len(block_end[[1L]] - 1L)]
  }
  dash_lines <- grep("^[[:space:]]*- ", body, useBytes = TRUE)
  if (identical(length(dash_lines), 0L)) {
    return(list())
  }
  item_indent <- min(nchar(sub("^([[:space:]]*)- .*$", "\\1", body[dash_lines])))
  item_pattern <- paste0("^[[:space:]]{", item_indent, "}- ")
  key_indent <- item_indent + 2L
  key_pattern <- paste0(
    "^[[:space:]]{",
    key_indent,
    "}([A-Za-z_][A-Za-z0-9_-]*):[[:space:]]*(.*)$"
  )
  wanted <- c("name", "version", "manager", "platform", "url", "category")
  items <- list()
  current <- NULL
  for (line in body) {
    if (isTRUE(grepl(item_pattern, line, useBytes = TRUE))) {
      if (isFALSE(is.null(current))) {
        items[[length(items) + 1L]] <- current
      }
      current <- list()
      # The first key on the `- ` line, as if it were on its own line.
      line <- paste0(
        strrep(" ", key_indent),
        sub(item_pattern, "", line, useBytes = TRUE)
      )
    }
    if (is.null(current) || isFALSE(grepl(key_pattern, line, useBytes = TRUE))) {
      next
    }
    key <- sub(key_pattern, "\\1", line, useBytes = TRUE)
    value <- trimws(sub(key_pattern, "\\2", line, useBytes = TRUE))
    if (isFALSE(key %in% wanted) || isFALSE(nzchar(value))) {
      next
    }
    value <- sub("^([\"'])(.*)\\1$", "\\2", value)
    current[[key]] <- value
  }
  if (isFALSE(is.null(current))) {
    items[[length(items) + 1L]] <- current
  }
  return(items)
}

#' Platforms and records of a mambajs lock file
#'
#' The platform of a record is its `subdir` field, such as `noarch`, else
#' the `platform` field of the file. micromamba installs every package,
#' whatever the `platform` field says, so a file of `noarch` packages
#' installs on any platform.
#'
#' @param path Character string, the path of the JSON file.
#'
#' @returns A list with `platforms` (the platforms of the records other
#'   than `noarch`, `NULL` when there are none; the `platform` field for a
#'   file without packages) and `records` (one row per element of `packages`; `NULL` when the
#'   file cannot be read as JSON).
#'
#' @keywords internal
#' @noRd
micromamba_mambajs_info <- function(path) {
  lock <- tryCatch(
    jsonlite::read_json(path, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (isFALSE(is.list(lock))) {
    return(list(platforms = NULL, records = NULL))
  }
  platform <- lock[["platform"]]
  platforms <- if (isTRUE(rlang::is_string(platform))) platform
  packages <- lock[["packages"]]
  records <- empty_definition_records()
  if (isTRUE(is.list(packages)) && isTRUE(length(packages) > 0L)) {
    get_text <- function(pkg, key) {
      value <- pkg[[key]]
      if (isTRUE(rlang::is_string(value))) {
        return(value)
      }
      return(NA_character_)
    }
    from_names <- split_package_file_names(rlang::names2(packages))
    records <- data.frame(
      name = vapply(
        packages,
        get_text,
        character(1L),
        key = "name",
        USE.NAMES = FALSE
      ),
      version = vapply(
        packages,
        get_text,
        character(1L),
        key = "version",
        USE.NAMES = FALSE
      ),
      build_string = vapply(
        packages,
        get_text,
        character(1L),
        key = "build",
        USE.NAMES = FALSE
      ),
      platform = vapply(
        packages,
        function(pkg) {
          subdir <- pkg[["subdir"]]
          if (
            isTRUE(rlang::is_string(subdir)) &&
              isTRUE(subdir %in% known_platforms)
          ) {
            return(subdir)
          }
          return(platforms %||% NA_character_)
        },
        character(1L),
        USE.NAMES = FALSE
      ),
      stringsAsFactors = FALSE
    )
    for (column in c("name", "version", "build_string")) {
      missing_value <- is.na(records[[column]])
      records[[column]][missing_value] <- from_names[[column]][missing_value]
    }
    rownames(records) <- NULL
    platforms <- lock_record_platforms(records)
  }
  return(list(platforms = platforms, records = records))
}

#' The file that `micromamba create -f` gets for an environment definition
#'
#' The path of the definition, or a copy of it under a name that micromamba
#' reads as its format (see `micromamba_read_definition()`). The copy is in
#' a temporary directory that is deleted when `envir` exits.
#'
#' @param definition `NULL` or a `condathis_env_definition` object.
#' @param env_file `NULL` or the path that condathis passed as `env_file`.
#' @param kinds Character vector, the kinds (`"request"`, `"lock"`) that
#'   the caller takes. `micromamba install` takes only a request.
#' @param envir The frame whose exit deletes the copy.
#' @param call Environment of the function the error is reported for.
#'
#' @returns A list with `path` (`NULL` or the path to pass) and
#'   `extra_args` (character vector). Aborts with class
#'   `condathis_backend_unsupported` for a definition that micromamba does
#'   not read, or whose kind is not in `kinds`: `create_env()` and
#'   `install_packages()` refuse it first, so this catches only a direct
#'   call.
#'
#' @keywords internal
#' @noRd
micromamba_definition_file <- function(
  definition,
  env_file,
  kinds = c("request", "lock"),
  envir = parent.frame(),
  call = rlang::caller_env()
) {
  if (is.null(definition)) {
    return(list(path = env_file, extra_args = character(0L)))
  }
  read <- micromamba_read_definition(definition)
  reason <- read$description$reason
  if (
    isTRUE(read$description$supported) &&
      isFALSE(read$description$kind %in% kinds)
  ) {
    reason <- paste0(
      "micromamba does not take a ",
      read$description$kind,
      " here."
    )
  }
  if (isFALSE(read$description$supported) || isFALSE(is.na(reason))) {
    condathis_abort(
      message = c(
        `x` = "micromamba cannot read environment definition {.path {definition$path}}.",
        `i` = "{reason}"
      ),
      class = "condathis_backend_unsupported",
      call = call
    )
  }
  path <- definition$path
  if (isFALSE(is.null(read$stage_name))) {
    stage_dir <- withr::local_tempdir(
      pattern = "condathis-definition-",
      .local_envir = envir
    )
    staged <- fs::path(stage_dir, read$stage_name)
    fs::file_copy(path, staged)
    path <- as.character(staged)
  }
  return(list(path = path, extra_args = read$extra_args))
}
