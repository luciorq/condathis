# A `polyglot` environment built at `prefix`, a directory outside the
# condathis root, from the local channel. It simulates an environment that
# another conda client created: condathis does not know it by name, and
# only reaches it through `env_path(prefix)`.
#
# `micromamba create -p` runs offline: the channel is a local directory.
# Returns the `native_cmd()` result invisibly, as `create_polyglot_env()`
# returns the `create_env()` result.
create_prefix_env <- function(prefix, channel = polyglot_channel()) {
  res <- native_cmd(
    conda_cmd = "create",
    conda_args = c(
      "-y",
      "-p",
      prefix,
      "-c",
      channel,
      "--override-channels",
      "--offline",
      "polyglot"
    ),
    verbose = "silent"
  )
  return(invisible(res))
}
