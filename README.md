
# condathis <img src="man/figures/logo.png" align="right" height="138" alt="" />

<!-- badges: start -->

[![r-cmd-check](https://github.com/luciorq/condathis/actions/workflows/r-cmd-check.yaml/badge.svg)](https://github.com/luciorq/condathis/actions/workflows/r-cmd-check.yaml)
[![CRAN
status](https://www.r-pkg.org/badges/version/condathis)](https://CRAN.R-project.org/package=condathis)
<!-- badges: end -->

> Run command-line tools in a **reproducible** and **isolated** way,
> right from R.

Tired of `system()` calls that work on your machine but break everywhere
else? `condathis` is here to help! It lets you create self-contained
environments for your command-line tools, so your R code runs reliably
for you, your colleagues, and your future self.

## A Quick Example

Let’s have some fun with `cowpy`. With just two commands, we can install
and run it in its own isolated environment:

``` r
# 1. Install 'cowpy' into an environment named 'cowpy-env'
condathis::create_env(packages = "cowpy", env_name = "cowpy-env", verbose = "output")
#> ! Environment cowpy-env already exists.

# 2. Run it!
# Not working without stdin redirection - need to use a file as input
temp_file <- tempfile()
writeLines("{condathis} is awesome!", temp_file)
condathis::run("cowpy", stdin = temp_file, env_name = "cowpy-env", verbose = "output")
#>  _________________________
#> < {condathis} is awesome! >
#>  -------------------------
#>      \   ^__^
#>       \  (oo)\_______
#>          (__)\       )\/\
#>            ||----w |
#>            ||     ||
```

Maybe you want to try something fancier, like `rich-cli` for formatting
messages?

``` r
condathis::create_env(packages = "rich-cli", env_name = "rich-cli-env", verbose = "output")
#> ! Environment rich-cli-env already exists.

condathis::run(
  "rich", "[b]Condathis[/b] is awesome!", "-p", "-a", "heavy",
  env_name = "rich-cli-env",
  verbose = "output"
)
#> ┏━━━━━━━━━━━━━━━━━━━━━━━┓
#> ┃ Condathis is awesome! ┃
#> ┗━━━━━━━━━━━━━━━━━━━━━━━┛
```

That’s it! You can now package any command-line tool with your R script,
ensuring it works everywhere, every time.

## Get Started

Install the release version of the package from
[CRAN](https://cran.r-project.org/package=condathis):

``` r
install.packages("condathis")
```

Or get the development version from
[R-Universe](https://luciorq.r-universe.dev/condathis):

``` r
install.packages("condathis", repos = c("https://luciorq.r-universe.dev", getOption("repos")))
```

## Why `condathis`?

R’s `system()` and `system2()` are powerful, but they depend on tools
being installed on the host system. This creates a few problems:

- **Reproducibility:** Will your script from last year still work? Will
  your collaborator be able to run your code if they have a different
  version of a tool?
- **Conflicts:** What if two different tools need two different versions
  of the same dependency?

`{condathis}` solves these issues by creating isolated environments for
each tool.

### Reproducibility: An Example

Let’s say you’re using `fastqc` for quality control in a bioinformatics
pipeline. Different versions of `fastqc` can produce slightly different
results.

With `{condathis}`, you can lock in a specific version:

``` r
fastq_file <- system.file("extdata", "sample1_L001_R1_001.fastq.gz", package = "condathis")
temp_out_dir <- file.path(tempdir(), "output")
fs::dir_create(temp_out_dir)

# Always use fastqc version 0.12.1
condathis::create_env(packages = "fastqc==0.12.1", env_name = "fastqc-0.12.1")
condathis::run("fastqc", fastq_file, "-o", temp_out_dir, env_name = "fastqc-0.12.1")
```

Now your analysis will produce the same output files, regardless of
where or when it’s run.

### Isolation: An Example

Need to use a specific version of a tool like `curl` that’s different
from your system’s version? No problem.

Your system’s `curl`:

``` r
libcurlVersion()
#> [1] "8.7.1"
#> attr(,"ssl_version")
#> [1] "SecureTransport (LibreSSL/3.3.6)"
#> attr(,"libssh_version")
#> [1] ""
#> attr(,"protocols")
#>  [1] "dict"    "file"    "ftp"     "ftps"    "gopher"  "gophers" "http"
#>  [8] "https"   "imap"    "imaps"   "ldap"    "ldaps"   "mqtt"    "pop3"
#> [15] "pop3s"   "rtsp"    "smb"     "smbs"    "smtp"    "smtps"   "telnet"
#> [22] "tftp"
```

A specific `curl` version, isolated with `condathis`:

``` r
condathis::create_env(
  packages = "curl==8.10.1",
  env_name = "curl-env",
  verbose = "output"
)
#> ! Environment curl-env already exists.

out <- condathis::run(
  "curl", "--version",
  env_name = "curl-env"
)

message(out$stdout)
#> curl 8.10.1 (aarch64-apple-darwin20.0.0) libcurl/8.10.1 OpenSSL/3.5.4 (SecureTransport) zlib/1.3.1 zstd/1.5.7 libssh2/1.11.1 nghttp2/1.67.0
#> Release-Date: 2024-09-18
#> Protocols: dict file ftp ftps gopher gophers http https imap imaps ipfs ipns mqtt pop3 pop3s rtsp scp sftp smb smbs smtp smtps telnet tftp ws wss
#> Features: alt-svc AsynchDNS GSS-API HSTS HTTP2 HTTPS-proxy IPv6 Kerberos Largefile libz MultiSSL NTLM SPNEGO SSL threadsafe TLS-SRP UnixSockets zstd
```

This allows you to run tools with conflicting dependencies side-by-side
without any issues.

## How It Works

The package `{condathis}` relies on
[**`micromamba`**](https://mamba.readthedocs.io/en/latest/user_guide/micromamba.html)
to bring **reproducibility and isolation**. `micromamba` is a
lightweight, fast, and efficient package manager that “does not need a
base environment and does not come with a default version of Python”.

The integration of `micromamba` into `R` is handled using the `processx`
and `withr` packages.

## Known Caveats

Special characters in CLI commands are interpreted as literals and not
expanded.

- It is not supported the use of output redirections in commands,
  e.g. “\|” or “\>”.
  - Instead of redirects (e.g. “\>”), use the argument
    `stdout = "<FILENAME>.txt"`. Instead of Pipes (“\|”), simple run
    multiple calls to `condathis::run()`, using `stdout` argument to
    control the output and `stdin` to control the input of each command.
    P.S. The current implementation only supports files as the “STDIN”.
- File paths should not use special characters for relative paths,
  e.g. “~”, “.”, “..”.
  - Expand file paths directly in R, using `base` functions or functions
    from the `fs` package.
