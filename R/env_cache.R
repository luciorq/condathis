#' Write Environment Method and Command to Cache
write_cache_env_method <- function(env_name,
                                   method_to_use,
                                   cmd = NULL,
                                   overwrite = FALSE) {
  cache_dir <- get_cache_dir()
  env_cache_file <- fs::path(cache_dir, "env_file", ext = "json")
  if (fs::file_exists(env_cache_file)) {
    envs_list <- jsonlite::fromJSON(env_cache_file, simplifyVector = TRUE)
  } else {
    envs_list <- list()
  }
  previous_names <- names(envs_list)
  if (isTRUE(env_name %in% previous_names) | isTRUE(overwrite)) {
    envs_list[[env_name]]$env_name <- env_name
    envs_list[[env_name]]$method <- method_to_use
    envs_list[[env_name]]$cmd <- unique(c(envs_list[[env_name]]$cmd, cmd))
  } else {
    env_to_add <- list()
    env_to_add$env_name <- env_name
    env_to_add$method <- method_to_use
    env_to_add$cmd <- cmd
    env_to_add <- list(
      env_to_add
    )
    names(env_to_add) <- env_name
    envs_list <- base::append(envs_list, env_to_add)
  }
  jsonlite::write_json(
    x = envs_list,
    path = env_cache_file
  )
}

#' Read Environment Details from Cache
read_cache_env_method <- function(env_name, method) {
  cache_dir <- get_cache_dir()
  env_cache_file <- fs::path(cache_dir, "env_file", ext = "json")
  if (fs::file_exists(env_cache_file)) {
    envs_list <- jsonlite::fromJSON(env_cache_file, simplifyVector = TRUE)
  } else {
    envs_list <- list()
  }
  cache_env_names <- names(envs_list)
  if (isTRUE(env_name %in% cache_env_names)) {
    method_to_use <- envs_list[[env_name]]$method
  } else {
    method_to_use <- method
  }
  return(c(method_to_use))
}

#' Find an Environment that the command has already run succesfully
read_cache_cmd <- function(cmd, method, env_name) {
  cache_dir <- get_cache_dir()
  env_cache_file <- fs::path(cache_dir, "env_file", ext = "json")
  if (fs::file_exists(env_cache_file)) {
    envs_list <- jsonlite::fromJSON(env_cache_file, simplifyVector = TRUE)
  } else {
    envs_list <- list()
  }
  to_use <- list()
  if (!is.null(cmd)) {
    for (i in seq_along(envs_list)) {
      if (isTRUE(cmd %in% envs_list[[i]]$cmd)) {
        to_use$method_to_use <- envs_list[[i]]$method
        to_use$env_to_use <- names(envs_list[i])
      }
    }
  }
  if (is.null(to_use$method_to_use)) {
    method_to_use = method
  }
  if (is.null(to_use$env_to_use)) {
    method_to_use = env_name
  }
  return(c(method = method_to_use, env_name = env_to_use))
}
