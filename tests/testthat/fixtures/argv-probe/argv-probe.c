/* SPDX-License-Identifier: MIT
 * Part of the condathis test suite, under the condathis license.
 *
 * argv-probe.c: prints each argument on its own line as "x" + the hex of
 * its UTF-8 bytes, so every byte can be compared exactly. An empty argument
 * prints just "x".
 *
 * Variants, selected at compile time:
 *   default        argv-probe: one line per argument.
 *   -DPROBE_CAT    argv-cat: copies standard input to standard output.
 *   -DPROBE_ENV    argv-env: one line per argument, read as the name of an
 *                  environment variable: "x" + the hex of its value, or "-"
 *                  when it is not set.
 *
 * Builds without libc on Linux (x86_64, aarch64) and Windows, where only
 * kernel32 and shell32 are used. Builds against libSystem on macOS, or with
 * the toolchain's C runtime anywhere when PROBE_HOSTED is defined.
 *
 * Freestanding flags, Linux:   -static -nostdlib -ffreestanding
 *                              -fno-stack-protector -fno-builtin
 * Freestanding flags, Windows: -nostdlib -ffreestanding -fno-stack-protector
 *                              -fno-builtin -Wl,-e,probe_start
 *                              -lshell32 -lkernel32 */

static const char probe_hex[] = "0123456789abcdef";

/* Not every variant uses every helper. */
#define PROBE_MAYBE_UNUSED __attribute__((unused))

#if defined(_WIN32)
#include <windows.h>
#include <shellapi.h>

static HANDLE probe_out;

static void probe_exit(int code) { ExitProcess((UINT)code); }

static void probe_write(const char *buf, unsigned long len) {
  DWORD written;
  while (len > 0) {
    if (!WriteFile(probe_out, buf, (DWORD)len, &written, NULL) || written == 0)
      probe_exit(2);
    buf += written;
    len -= written;
  }
}

PROBE_MAYBE_UNUSED static long probe_read(char *buf, unsigned long len) {
  DWORD got;
  if (!ReadFile(GetStdHandle(STD_INPUT_HANDLE), buf, (DWORD)len, &got, NULL))
    return GetLastError() == ERROR_BROKEN_PIPE ? 0 : -1;
  return (long)got;
}

#elif defined(__linux__) && !defined(PROBE_HOSTED)
#if defined(__x86_64__)
#define PROBE_SYS_READ 0
#define PROBE_SYS_WRITE 1
#define PROBE_SYS_EXIT_GROUP 231
#elif defined(__aarch64__)
#define PROBE_SYS_READ 63
#define PROBE_SYS_WRITE 64
#define PROBE_SYS_EXIT_GROUP 94
#else
#error "No freestanding build for this CPU; compile with -DPROBE_HOSTED"
#endif

#define PROBE_EINTR 4

static long probe_syscall3(long n, long a1, long a2, long a3) {
#if defined(__x86_64__)
  long ret;
  __asm__ volatile("syscall"
                   : "=a"(ret)
                   : "a"(n), "D"(a1), "S"(a2), "d"(a3)
                   : "rcx", "r11", "memory");
  return ret;
#else
  register long x8 __asm__("x8") = n;
  register long x0 __asm__("x0") = a1;
  register long x1 __asm__("x1") = a2;
  register long x2 __asm__("x2") = a3;
  __asm__ volatile("svc 0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2) : "memory");
  return x0;
#endif
}

static void probe_exit(int code) {
  for (;;)
    probe_syscall3(PROBE_SYS_EXIT_GROUP, code, 0, 0);
}

static void probe_write(const char *buf, unsigned long len) {
  while (len > 0) {
    long ret = probe_syscall3(PROBE_SYS_WRITE, 1, (long)buf, (long)len);
    if (ret == -PROBE_EINTR)
      continue;
    if (ret <= 0)
      probe_exit(2);
    buf += ret;
    len -= (unsigned long)ret;
  }
}

PROBE_MAYBE_UNUSED static long probe_read(char *buf, unsigned long len) {
  for (;;) {
    long ret = probe_syscall3(PROBE_SYS_READ, 0, (long)buf, (long)len);
    if (ret != -PROBE_EINTR)
      return ret;
  }
}

#else
#include <errno.h>
#include <stdlib.h>
#include <unistd.h>

static void probe_exit(int code) { _exit(code); }

static void probe_write(const char *buf, unsigned long len) {
  while (len > 0) {
    ssize_t ret = write(1, buf, len);
    if (ret < 0 && errno == EINTR)
      continue;
    if (ret <= 0)
      probe_exit(2);
    buf += ret;
    len -= (unsigned long)ret;
  }
}

PROBE_MAYBE_UNUSED static long probe_read(char *buf, unsigned long len) {
  for (;;) {
    ssize_t ret = read(0, buf, len);
    if (ret >= 0 || errno != EINTR)
      return (long)ret;
  }
}
#endif

/* Buffered output, shared by every platform. */
static char probe_buf[4096];
static unsigned long probe_len;

static void probe_flush(void) {
  probe_write(probe_buf, probe_len);
  probe_len = 0;
}

static void probe_put(char c) {
  if (probe_len == sizeof(probe_buf))
    probe_flush();
  probe_buf[probe_len++] = c;
}

/* One line: "x" + hex of `len` bytes. */
PROBE_MAYBE_UNUSED static void probe_emit(const unsigned char *bytes, unsigned long len) {
  unsigned long i;
  probe_put('x');
  for (i = 0; i < len; i++) {
    probe_put(probe_hex[bytes[i] >> 4]);
    probe_put(probe_hex[bytes[i] & 15]);
  }
  probe_put('\n');
}

#if defined(PROBE_ENV)
static void probe_emit_unset(void) {
  probe_put('-');
  probe_put('\n');
}
#endif

#if defined(PROBE_CAT)
static void probe_cat(void) {
  for (;;) {
    long got = probe_read(probe_buf, sizeof(probe_buf));
    if (got == 0)
      return;
    if (got < 0)
      probe_exit(3);
    probe_write(probe_buf, (unsigned long)got);
  }
}
#endif

#if defined(_WIN32)

static char *probe_utf8(const wchar_t *wide, int wide_len, int *out_len) {
  int len;
  char *out;
  if (wide_len == 0) {
    *out_len = 0;
    return NULL;
  }
  len = WideCharToMultiByte(CP_UTF8, 0, wide, wide_len, NULL, 0, NULL, NULL);
  if (len <= 0)
    probe_exit(4);
  out = (char *)HeapAlloc(GetProcessHeap(), 0, (SIZE_T)len);
  if (out == NULL)
    probe_exit(4);
  WideCharToMultiByte(CP_UTF8, 0, wide, wide_len, out, len, NULL, NULL);
  *out_len = len;
  return out;
}

PROBE_MAYBE_UNUSED static void probe_emit_wide(const wchar_t *wide, int wide_len) {
  int len;
  char *utf8 = probe_utf8(wide, wide_len, &len);
  probe_emit((const unsigned char *)utf8, (unsigned long)len);
  if (utf8 != NULL)
    HeapFree(GetProcessHeap(), 0, utf8);
}

PROBE_MAYBE_UNUSED static int probe_wlen(const wchar_t *s) {
  int n = 0;
  while (s[n] != 0)
    n++;
  return n;
}

#if defined(PROBE_ENV)
/* Variable names are case-insensitive on Windows. */
static wchar_t probe_wupper(wchar_t c) {
  return (c >= L'a' && c <= L'z') ? (wchar_t)(c - L'a' + L'A') : c;
}

/* Scans the environment block, so variables set to "" are found too. */
static void probe_emit_env(const wchar_t *block, const wchar_t *name) {
  const wchar_t *entry = block;
  while (*entry != 0) {
    int len = probe_wlen(entry);
    int i = 0;
    /* Skip the leading "=" of hidden entries such as "=C:=C:\\". */
    if (entry[0] != L'=') {
      while (name[i] != 0 && probe_wupper(entry[i]) == probe_wupper(name[i]))
        i++;
      if (name[i] == 0 && entry[i] == L'=') {
        probe_emit_wide(entry + i + 1, len - i - 1);
        return;
      }
    }
    entry += len + 1;
  }
  probe_emit_unset();
}
#endif

void probe_start(void) {
  int argc = 0;
  wchar_t **argv;
  probe_out = GetStdHandle(STD_OUTPUT_HANDLE);
  argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv == NULL)
    probe_exit(4);
#if defined(PROBE_CAT)
  probe_cat();
#elif defined(PROBE_ENV)
  {
    wchar_t *block = GetEnvironmentStringsW();
    int i;
    for (i = 1; i < argc; i++)
      probe_emit_env(block, argv[i]);
  }
#else
  {
    int i;
    for (i = 1; i < argc; i++)
      probe_emit_wide(argv[i], probe_wlen(argv[i]));
  }
#endif
  probe_flush();
  probe_exit(0);
}

#if defined(PROBE_HOSTED)
/* Toolchains whose startup code cannot be dropped, such as `zig cc`. */
int main(void) {
  probe_start();
  return 0;
}
#endif

#else

PROBE_MAYBE_UNUSED static unsigned long probe_strlen(const char *s) {
  unsigned long n = 0;
  while (s[n] != 0)
    n++;
  return n;
}

#if defined(PROBE_ENV)
static void probe_emit_env(char **envp, const char *name) {
  for (; *envp != 0; envp++) {
    const char *entry = *envp;
    unsigned long i = 0;
    while (name[i] != 0 && entry[i] == name[i])
      i++;
    if (name[i] == 0 && entry[i] == '=') {
      probe_emit((const unsigned char *)entry + i + 1,
                 probe_strlen(entry + i + 1));
      return;
    }
  }
  probe_emit_unset();
}
#endif

static int probe_main(int argc, char **argv, char **envp) {
#if defined(PROBE_CAT)
  (void)argc;
  (void)argv;
  (void)envp;
  probe_cat();
#elif defined(PROBE_ENV)
  int i;
  for (i = 1; i < argc; i++)
    probe_emit_env(envp, argv[i]);
#else
  int i;
  (void)envp;
  for (i = 1; i < argc; i++)
    probe_emit((const unsigned char *)argv[i], probe_strlen(argv[i]));
#endif
  probe_flush();
  return 0;
}

#if defined(__linux__) && !defined(PROBE_HOSTED)
/* The kernel starts the program at `_start` with the stack holding argc,
 * then argv and envp, each ending in a null pointer. */
__attribute__((used)) void probe_start_c(long *sp) {
  int argc = (int)sp[0];
  char **argv = (char **)(sp + 1);
  probe_exit(probe_main(argc, argv, argv + argc + 1));
}

#if defined(__x86_64__)
__asm__(".text\n"
        ".global _start\n"
        "_start:\n"
        "  xor %rbp, %rbp\n"
        "  mov %rsp, %rdi\n"
        "  and $-16, %rsp\n"
        "  call probe_start_c\n"
        "  hlt\n");
#else
__asm__(".text\n"
        ".global _start\n"
        "_start:\n"
        "  mov x29, #0\n"
        "  mov x30, #0\n"
        "  mov x0, sp\n"
        "  bl probe_start_c\n"
        "  brk #0\n");
#endif

#else
extern char **environ;

int main(int argc, char **argv) {
  probe_main(argc, argv, environ);
  probe_exit(0);
  return 0;
}
#endif
#endif
