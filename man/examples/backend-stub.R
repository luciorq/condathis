# A minimal backend: the three required functions, which this example
# does not implement. It reports that it is unavailable, so
# `method = "auto"` never selects it. condathis supplies the other
# functions: they look for environments in
# `backend_root_dir("mybackend")/envs`. A backend package builds this
# object in its own constructor, for example `new_backend_mybackend()` in
# *Registering from a backend package* of `?register_backend`.
not_implemented <- function(...) {
  stop("Not implemented by this example backend.")
}
mybackend <- structure(
  list(
    backend_create_env = not_implemented,
    backend_install = not_implemented,
    backend_resolve_run = not_implemented,
    backend_available = function(backend) FALSE
  ),
  class = c("condathis_backend_mybackend", "condathis_backend")
)

condathis::register_backend("mybackend", mybackend)
condathis::list_registered_backend_names()

condathis::unregister_backend("mybackend")
condathis::list_registered_backend_names()
