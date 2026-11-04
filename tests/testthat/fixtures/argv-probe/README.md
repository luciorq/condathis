# argv-probe

`argv-probe.c` is a small C program for tests that check how arguments and
environment variables reach a command. It has no dependencies and is under
the condathis MIT license.

One source file builds three programs:

- `argv-probe` prints one line per argument: `x`, then the hex of the
  argument's UTF-8 bytes. An empty argument prints `x`.
- `argv-cat` (`-DPROBE_CAT`) copies standard input to standard output.
- `argv-env` (`-DPROBE_ENV`) prints one line per argument, read as the name
  of an environment variable: `x` + the hex of its value, or `-` when it is
  not set.

Hex needs no escaping, so newlines, quotes, `%`, `^` and Unicode come back
exactly. The programs use no C library on Linux (raw system calls) or Windows
(kernel32 and shell32 only), so nothing between condathis and the kernel can
change the arguments. On Windows they get their arguments from
`CommandLineToArgvW()`, which splits the command line by the same rules
processx quotes it for. macOS builds against libSystem, which is part of the
OS.

`helper-argv-probe.R` compiles the programs once per test process, then
packages them as `argv-probe` in a local conda channel for the current
platform. Tests install it with `create_argv_probe_env()` and need no network
once micromamba is installed. The compilers are tried in this order:

1. R's own C compiler (`R CMD config CC`), which on Windows is Rtools.
2. `zig cc`, if `zig` is on `PATH`, with `-target <arch>-windows-gnu` on
   Windows.

Each compiler first builds without the C library and then, if that fails,
with it (`-DPROBE_HOSTED`). A build counts only if the probe returns a few
test arguments exactly. When no compiler works, the tests use Python
commands that print the same format, from a `python` environment downloaded
from conda-forge.

To build by hand:

```sh
# Linux, without libc
cc -O2 -static -nostdlib -ffreestanding -fno-stack-protector -fno-builtin \
  -o argv-probe argv-probe.c
# Any platform, with the C runtime (macOS needs this)
cc -O2 -DPROBE_HOSTED -o argv-probe argv-probe.c
# Windows (Rtools), without the C runtime
gcc -O2 -nostdlib -ffreestanding -fno-stack-protector -fno-builtin \
  -Wl,-e,probe_start -o argv-probe.exe argv-probe.c -lshell32 -lkernel32
```

Add `-DPROBE_CAT` or `-DPROBE_ENV` for the other two programs.
