#' Run the creation of an environment in a free environment directory
#'
#' The front end of `create_env()` owns the life cycle of the environment
#' directory, for every backend: `backend_create_env()` is called only when
#' the directory from `backend_get_env_dir()` does not exist (see
#' ?register_backend). `create_env()` calls
#' `with_backend_errors(with_env_dir_replacement(backend, env_name,
#' backend_create_env(...)))`, so the classes that reach the user are the
#' ones that micromamba's own replacement code raised.
#'
#' Before `expr` runs:
#' * When the backend does not list `env_name` but its directory exists, as
#'   after a failed create, the directory is deleted
#'   (`delete_stale_env_dir()`). The existence check is the raw
#'   `backend_env_exists()`, with its value checked, as micromamba's own
#'   replacement code called it: its error is never read as "absent", which
#'   would delete a real environment (rule R5), and `with_backend_errors()`
#'   raises it with the classes of a failed create.
#' * An existing environment (`overwrite = TRUE`) is moved into
#'   `env_trash_dir()` (`set_aside_env_dir()`), after
#'   `purge_env_trash_dir()`. When it cannot be moved, nothing runs and the
#'   environment is unchanged.
#'
#' When `expr` fails, what it left is deleted, and the old environment is
#' moved back, before the error leaves this function: the caller's handlers
#' already see the old environment. An environment that cannot be moved
#' back is named in the error (`note_kept_env_dir()`), or, after an
#' interrupt, in a warning (`warn_on_kept_env_dir()`). A new environment
#' that `expr` left half made, also after an interrupt, is deleted
#' (`delete_failed_new_env_dir()`): a backend can write
#' `conda-meta/history` before its downloads, and the identical retry then
#' aborted with `condathis_create_env_exists`. When `expr` succeeds, the
#' old environment is deleted (`discard_set_aside_env_dir()`).
#'
#' For the micromamba backend only: when the micromamba binary in use lives
#' in the environment that is replaced (discovery source 6, or
#' `CONDA_PREFIX`), `expr` runs with the option `condathis.micromamba_path`
#' set to the binary in its new place.
#'
#' The environment directory must be `<root>/envs/<env_name>` of the
#' backend's root: `check_exact_env_dir()` refuses to delete or move
#' anything else.
#'
#' @param backend An already-resolved backend object.
#' @param env_name Character string with the environment name.
#' @param expr The creation, evaluated once the environment directory is
#'   free. It must abort when it fails.
#' @param call Environment of the function that an invalid value of
#'   `backend_env_exists()` is reported for.
#'
#' @returns The value of `expr`.
#'
#' @keywords internal
#' @noRd
with_env_dir_replacement <- function(
  backend,
  env_name,
  expr,
  call = rlang::caller_env()
) {
  env_state <- backend_env_exists_checked(
    backend,
    env_name = env_name,
    call = call
  )
  # A failed create can leave the directory behind, as micromamba does for
  # a non-native platform, and a backend gets only a free directory.
  if (
    isFALSE(env_state) &&
      isTRUE(fs::dir_exists(env_dir_for_backend(backend, env_name)))
  ) {
    delete_stale_env_dir(backend, env_name)
  }

  # `on.exit()` covers an interrupt.
  new_env <- new.env(parent = emptyenv())
  new_env$pending <- isFALSE(env_state)
  if (isTRUE(new_env$pending)) {
    on.exit(delete_failed_new_env_dir(new_env, backend, env_name), add = TRUE)
  }

  # A backend gets only a free directory, and `micromamba create --yes`
  # deleted an existing prefix before it solved, so a failed replacement (a
  # misspelled spec, a download error) lost the environment. `aside$path`
  # is set in the same interrupt-free step as the move, so the environment
  # is never in the trash without a restore.
  aside <- new.env(parent = emptyenv())
  aside$path <- NULL
  if (isTRUE(env_state)) {
    on.exit(
      warn_on_kept_env_dir(
        restore_set_aside_env_dir(aside, backend, env_name),
        backend = backend,
        env_name = env_name
      ),
      add = TRUE
    )
    binary_in_env <- NULL
    if (isTRUE(inherits(backend, "condathis_backend_micromamba"))) {
      binary_in_env <- micromamba_binary_in_env_dir(backend, env_name)
    }
    purge_env_trash_dir(env_trash_dir(backend))
    set_aside_env_dir(aside, backend, env_name)
    if (isFALSE(is.null(binary_in_env))) {
      # The micromamba in use lives in this environment: run it from its
      # new place.
      withr::local_options(
        condathis.micromamba_path = as.character(
          fs::path(aside$path, binary_in_env)
        )
      )
    }
  }

  value <- tryCatch(
    expr,
    error = function(cnd) {
      delete_failed_new_env_dir(new_env, backend, env_name)
      kept <- restore_set_aside_env_dir(aside, backend, env_name)
      # The error reports a copy that could not be moved back, so the
      # `on.exit()` restore must not try again and warn.
      aside$path <- NULL
      stop(note_kept_env_dir(cnd, kept, env_name = env_name))
    }
  )
  new_env$pending <- FALSE
  # Clear `aside$path` first: an interrupt while the old copy is deleted
  # must not make the `on.exit()` restore replace the new environment.
  if (isFALSE(is.null(aside$path))) {
    old_env_dir <- aside$path
    aside$path <- NULL
    discard_set_aside_env_dir(old_env_dir)
  }
  return(value)
}

#' Condition classes of the environment-directory life cycle
#'
#' The micromamba backend kept its environments aside itself, with classes
#' that name it. They stay as extra classes for that backend.
#'
#' @param backend A backend object.
#' @param class Character string, the generic class, such as
#'   `"condathis_env_set_aside_failed"`.
#'
#' @returns `class`, preceded by `condathis_micromamba_<rest>` for the
#'   micromamba backend.
#'
#' @keywords internal
#' @noRd
env_dir_condition_class <- function(backend, class) {
  if (isTRUE(inherits(backend, "condathis_backend_micromamba"))) {
    return(c(sub("^condathis_", "condathis_micromamba_", class), class))
  }
  return(class)
}

#' Delete the stale directory of an environment its backend does not list
#'
#' The callers run it when the backend does not list `env_name` but
#' `<root>/envs/<env_name>` exists. `check_exact_env_dir()` refuses
#' anything else.
#'
#' @keywords internal
#' @noRd
delete_stale_env_dir <- function(backend, env_name) {
  target <- check_exact_env_dir(
    backend,
    env_name = env_name,
    action = "delete",
    class = "condathis_unsafe_env_dir_delete"
  )
  fs::dir_delete(target)
  return(invisible(NULL))
}

#' Delete the directory a failed create of a new environment left
#'
#' Runs once: from the error handler of `with_env_dir_replacement()`, or
#' from its `on.exit()` after an interrupt. A directory that cannot be
#' deleted (on Windows, while a program still uses one of its files) is
#' kept, so the error of the create is the one the caller sees.
#'
#' @param state Environment with `pending`: `TRUE` until the create
#'   succeeds or the directory was deleted.
#'
#' @keywords internal
#' @noRd
delete_failed_new_env_dir <- function(state, backend, env_name) {
  if (isFALSE(isTRUE(state$pending))) {
    return(invisible(NULL))
  }
  state$pending <- FALSE
  if (isTRUE(fs::dir_exists(env_dir_for_backend(backend, env_name)))) {
    try(delete_stale_env_dir(backend, env_name), silent = TRUE)
  }
  return(invisible(NULL))
}

#' Check that a path is exactly the directory of an environment
#'
#' Refuses anything that is not a direct child of `<root>/envs`, so no
#' environment name can turn a deletion or a move into one elsewhere.
#' `validate_env_name()` already rejects such names at every entry point;
#' this is the last line of defense right before the change.
#'
#' It also refuses a directory whose real path is not exactly
#' `<root>/envs/<env_name>`. That path can open the directory of another
#' environment: Windows drops a trailing dot (`myenv.` opens `myenv`) and
#' resolves 8.3 short names (`MYENVI~1`), Windows and macOS compare names
#' case-insensitively (`myenv` opens `MyEnv`), and a symbolic link opens
#' its target. Checking only the lexical path deleted that other
#' environment.
#'
#' @param action Character string, the verb of the error message.
#' @param class Character string, the class of the error.
#'
#' @returns The normalized path `<root>/envs/<env_name>`. Aborts with
#'   `class` otherwise.
#'
#' @keywords internal
#' @noRd
check_exact_env_dir <- function(backend, env_name, action, class) {
  envs_dir <- fs::path_norm(fs::path(install_dir_for_backend(backend), "envs"))
  target <- fs::path_norm(env_dir_for_backend(backend, env_name))
  if (
    isFALSE(is_valid_env_name(env_name)) ||
      isFALSE(identical(
        tolower_on_windows(as.character(fs::path_dir(target))),
        tolower_on_windows(as.character(envs_dir))
      ))
  ) {
    condathis_abort(
      message = c(
        `x` = "Refusing to {action} {.path {target}}.",
        `i` = "It is not an environment directory under {.path {envs_dir}}."
      ),
      class = class
    )
  }
  real_target <- real_path_or_na(target)
  if (
    isFALSE(is_exact_env_dir(
      real_target = real_target,
      real_envs_dir = real_path_or_na(envs_dir),
      env_name = env_name
    ))
  ) {
    condathis_abort(
      message = c(
        `x` = "Refusing to {action} {.path {target}}.",
        `i` = "It is not the directory of environment {.field {env_name}}.",
        `i` = if (isFALSE(is.na(real_target))) {
          "The path opens {.path {real_target}}."
        }
      ),
      class = class
    )
  }
  return(target)
}

#' The directory that holds environments while they are replaced
#'
#' `<root>/envs/#trash`. It is inside `<root>/envs`, so a move into it is a
#' rename on the same file system, also when `<root>/envs` is a link to
#' another disk. No environment can have this name, because
#' `validate_env_name()` rejects `#`. micromamba does not list the
#' environments in it: it only lists the direct children of `<root>/envs`
#' (checked with micromamba 2.9.0 and 2.10.0), and this directory has no
#' `conda-meta/history`. `backend_has_env_dirs()` and the default listing
#' skip it.
#'
#' The directory is never deleted, even when it is empty: another process
#' can move an environment into it at any time.
#'
#' @keywords internal
#' @noRd
env_trash_dir <- function(backend) {
  return(fs::path(install_dir_for_backend(backend), "envs", env_trash_name()))
}

#' @keywords internal
#' @noRd
env_trash_name <- function() {
  return("#trash")
}

#' A new, unused path in `env_trash_dir()`
#'
#' A short name (`#trash/<hex>`), so the paths inside a copy are about as
#' long as in the environment: Windows limits paths to 260 characters by
#' default. `base::tempfile()`, not `fs::file_temp()`, which returns the
#' paths of `fs::file_temp_push()` first, whatever its directory.
#'
#' @keywords internal
#' @noRd
new_trash_path <- function(backend) {
  trash_dir <- env_trash_dir(backend)
  fs::dir_create(trash_dir)
  return(as.character(fs::path(
    trash_dir,
    base::basename(base::tempfile(pattern = "", tmpdir = trash_dir))
  )))
}

#' Move an existing environment aside before it is replaced
#'
#' `with_env_dir_replacement()` moves the environment into
#' `env_trash_dir()` before the backend creates it again, after
#' `purge_env_trash_dir()`. It then deletes it with
#' `discard_set_aside_env_dir()` after a successful create, or moves it
#' back with `restore_set_aside_env_dir()`.
#'
#' The move is one rename, which either moves the whole directory or
#' nothing. On Windows it fails while a program uses a file in the
#' environment; the environment then stays as it was. Only the rename and
#' the assignment of `aside$path` run with interrupts suspended: the checks
#' run before, and the error after, so the caller's handlers can be
#' interrupted.
#'
#' @param aside Environment whose `path` gets the new path of the
#'   environment.
#'
#' @returns `NULL`, invisibly. Aborts with class
#'   `condathis_env_set_aside_failed` when the move fails, preceded by
#'   `condathis_micromamba_env_set_aside_failed` for the micromamba backend.
#'
#' @keywords internal
#' @noRd
set_aside_env_dir <- function(aside, backend, env_name) {
  target <- check_exact_env_dir(
    backend,
    env_name = env_name,
    action = "move",
    class = "condathis_unsafe_env_dir_move"
  )
  new_path <- new_trash_path(backend)
  reason <- suspendInterrupts({
    reason <- rename_path(target, new_path)
    if (is.null(reason)) {
      aside$path <- new_path
    }
    reason
  })
  if (isFALSE(is.null(reason))) {
    condathis_abort(
      message = c(
        `x` = "Could not move environment {.field {env_name}} aside to replace it.",
        `i` = "The environment is unchanged.",
        `i` = "Close the programs that use files in {.path {target}}, and try again.",
        ` ` = if (nzchar(reason)) "{reason}"
      ),
      class = env_dir_condition_class(
        backend,
        "condathis_env_set_aside_failed"
      )
    )
  }
  return(invisible(NULL))
}

#' Move a set-aside environment back after a failed create
#'
#' What the failed create left at the environment path is renamed into the
#' trash with a `.discard` marker, and the old environment is renamed back.
#' Only these renames run with interrupts suspended; the leftover is
#' deleted afterwards, by `purge_env_trash_dir()`, where an interrupt only
#' leaves it for the next purge. It never signals an error or a warning:
#' the caller reports a failure, see `note_kept_env_dir()` and
#' `warn_on_kept_env_dir()`.
#'
#' @param aside Environment from `with_env_dir_replacement()`. Its `path`
#'   is the set-aside environment, or `NULL` when there is nothing to
#'   restore. It is `NULL` afterwards when the environment is back.
#'
#' @returns `NULL` when the environment was moved back or there was nothing
#'   to move. Otherwise a list with `path` (where the old environment is
#'   kept), `target` (the environment directory) and `reason` (a character
#'   string, possibly empty).
#'
#' @keywords internal
#' @noRd
restore_set_aside_env_dir <- function(aside, backend, env_name) {
  set_aside <- aside$path
  if (is.null(set_aside) || isFALSE(fs::dir_exists(set_aside))) {
    aside$path <- NULL
    return(NULL)
  }
  target <- env_dir_for_backend(backend, env_name)
  reason <- tryCatch(
    {
      leftover <- NULL
      if (isTRUE(fs::dir_exists(target)) || isTRUE(fs::link_exists(target))) {
        check_exact_env_dir(
          backend,
          env_name = env_name,
          action = "delete",
          class = "condathis_unsafe_env_dir_delete"
        )
        leftover <- new_trash_path(backend)
      }
      suspendInterrupts({
        reason <- NULL
        if (isFALSE(is.null(leftover))) {
          # The marker comes after the rename (see
          # `delete_env_dir_via_trash()`).
          reason <- rename_path(target, leftover)
          if (is.null(reason)) {
            try(fs::file_create(paste0(leftover, ".discard")), silent = TRUE)
          }
        }
        if (is.null(reason)) {
          reason <- rename_path(set_aside, target)
        }
        if (is.null(reason)) {
          aside$path <- NULL
        }
        reason
      })
    },
    error = function(cnd) conditionMessage(cnd)
  )
  purge_env_trash_dir(env_trash_dir(backend))
  if (is.null(reason)) {
    return(NULL)
  }
  return(list(path = set_aside, target = target, reason = reason))
}

#' The text that says where an environment that was not restored is kept
#'
#' @param kept The value of `restore_set_aside_env_dir()`.
#'
#' @returns A named character vector of message bullets, already formatted.
#'
#' @keywords internal
#' @noRd
kept_env_dir_bullets <- function(kept, env_name) {
  return(c(
    `!` = cli::format_inline(
      "Could not restore environment {.field {env_name}} after the failed create."
    ),
    `i` = paste0("The old environment is kept in ", kept$path, "."),
    `i` = paste0("Move it back to ", kept$target, " to use it again."),
    ` ` = if (nzchar(kept$reason)) kept$reason
  ))
}

#' Add the kept-environment text to the error of a failed create
#'
#' The note goes into the error, not into a warning: a warning signaled
#' while the error is on its way can replace it, for example under
#' `options(warn = 2)`.
#'
#' @param cnd The error of the failed create.
#' @param kept The value of `restore_set_aside_env_dir()`.
#'
#' @returns `cnd`, with the bullets of `kept_env_dir_bullets()` added to its
#'   footer (an rlang error) or its message, the class
#'   `condathis_env_not_restored` and the field `kept_env_dir`. `cnd`
#'   unchanged when `kept` is `NULL`.
#'
#' @keywords internal
#' @noRd
note_kept_env_dir <- function(cnd, kept, env_name) {
  if (is.null(kept)) {
    return(cnd)
  }
  bullets <- kept_env_dir_bullets(kept, env_name = env_name)
  if (inherits(cnd, "rlang_error")) {
    cnd$footer <- c(cnd$footer, bullets)
  } else {
    cnd$message <- paste(c(conditionMessage(cnd), bullets), collapse = "\n")
  }
  cnd$kept_env_dir <- kept$path
  class(cnd) <- unique(c("condathis_env_not_restored", class(cnd)))
  return(cnd)
}

#' Warn that an environment was not restored after an interrupt
#'
#' The `on.exit()` path of `with_env_dir_replacement()`. An error has
#' already been handled by `note_kept_env_dir()`, which clears the
#' set-aside path, so this only runs after an interrupt.
#'
#' @param kept The value of `restore_set_aside_env_dir()`.
#' @param backend The backend object, for the classes.
#'
#' @returns `NULL`, invisibly. Warns with class
#'   `condathis_env_restore_failed`, preceded by
#'   `condathis_micromamba_env_restore_failed` for the micromamba backend.
#'
#' @keywords internal
#' @noRd
warn_on_kept_env_dir <- function(kept, backend, env_name) {
  if (is.null(kept)) {
    return(invisible(NULL))
  }
  bullets <- kept_env_dir_bullets(kept, env_name = env_name)
  # The bullets are already formatted: refer to them, so cli does not read
  # `{` in a path as an expression.
  message <- sprintf("{bullets[[%d]]}", seq_along(bullets))
  names(message) <- names(bullets)
  condathis_warn(
    message = message,
    class = env_dir_condition_class(backend, "condathis_env_restore_failed"),
    kept_env_dir = kept$path
  )
  return(invisible(NULL))
}

#' Delete a set-aside environment after a successful create
#'
#' It first writes `<copy>.discard`, so `purge_env_trash_dir()` knows the
#' copy is not needed. A failed delete is ignored: on Windows a program can
#' still use a file in the old environment. The next replacement deletes
#' what is left.
#'
#' @keywords internal
#' @noRd
discard_set_aside_env_dir <- function(set_aside) {
  marker <- paste0(set_aside, ".discard")
  try(fs::file_create(marker), silent = TRUE)
  deleted <- tryCatch(
    {
      fs::dir_delete(set_aside)
      TRUE
    },
    error = function(cnd) FALSE
  )
  if (isTRUE(deleted)) {
    try(fs::file_delete(marker), silent = TRUE)
  }
  return(invisible(NULL))
}

#' Delete the copies that `discard_set_aside_env_dir()` could not delete
#'
#' Only copies with a `.discard` marker are deleted. A copy without one is
#' either in use by a replacement that is still running (in this or another
#' process) or the only copy of an environment that could not be restored,
#' so it is kept. A link is deleted itself, never its target. Failures are
#' ignored.
#'
#' @keywords internal
#' @noRd
purge_env_trash_dir <- function(trash_dir) {
  markers <- tryCatch(
    fs::dir_ls(trash_dir, all = TRUE, glob = "*.discard", type = "file"),
    error = function(e) character(0L)
  )
  for (marker in markers) {
    entry <- sub("[.]discard$", "", marker)
    deleted <- tryCatch(
      {
        if (isTRUE(fs::link_exists(entry))) {
          fs::link_delete(entry)
        } else if (isTRUE(fs::dir_exists(entry))) {
          fs::dir_delete(entry)
        }
        TRUE
      },
      error = function(cnd) FALSE
    )
    if (isTRUE(deleted)) {
      try(fs::file_delete(marker), silent = TRUE)
    }
  }
  return(invisible(NULL))
}

#' Rename a path
#'
#' A wrapper of `file.rename()`, so tests can make the rename fail.
#' `file.rename()` never copies: across file systems it fails.
#'
#' @returns `NULL` when the rename worked. Otherwise a character string
#'   with the reason, possibly empty.
#'
#' @keywords internal
#' @noRd
rename_path <- function(from, to) {
  reason <- ""
  renamed <- withCallingHandlers(
    file.rename(from, to),
    warning = function(cnd) {
      reason <<- conditionMessage(cnd)
      invokeRestart("muffleWarning")
    }
  )
  if (isTRUE(renamed)) {
    return(NULL)
  }
  return(reason)
}

#' Real path of `path`, or `NA` when it cannot be resolved
#'
#' @param path Character string.
#'
#' @returns Character string.
#'
#' @keywords internal
#' @noRd
real_path_or_na <- function(path) {
  return(tryCatch(
    as.character(fs::path_real(path)),
    error = function(e) NA_character_
  ))
}

#' Is a real path exactly the directory of `env_name` in `<root>/envs`?
#'
#' The last component must be identical to `env_name`, case included: the
#' file system returns the name as stored on disk, so a path that a
#' case-insensitive or a trailing-dot lookup resolved to another directory
#' fails here. The parent must be the real `<root>/envs`, so a symbolic
#' link to a directory with the same name elsewhere fails too.
#'
#' @param real_target Character string, the real path of
#'   `<root>/envs/<env_name>`, or `NA` when it could not be resolved.
#' @param real_envs_dir Character string, the real path of `<root>/envs`,
#'   or `NA`.
#' @param env_name Character string with the environment name.
#'
#' @returns Logical scalar. `FALSE` when either path is `NA`.
#'
#' @keywords internal
#' @noRd
is_exact_env_dir <- function(real_target, real_envs_dir, env_name) {
  if (isTRUE(is.na(real_target)) || isTRUE(is.na(real_envs_dir))) {
    return(FALSE)
  }
  real_target <- to_slash_path(real_target)
  real_envs_dir <- to_slash_path(real_envs_dir)
  return(
    identical(base::basename(real_target), as.character(env_name)) &&
      identical(
        tolower_on_windows(base::dirname(real_target)),
        tolower_on_windows(real_envs_dir)
      )
  )
}
