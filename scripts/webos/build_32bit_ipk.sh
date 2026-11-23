#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK_DIR="${WORK_DIR:-$(cd "$REPO_ROOT/.." && pwd)}"
WEBOS_SDK_DIR="${WEBOS_SDK_DIR:-/usr/local/starfish-sdk-x86_64}"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/dist}"

SQLITE_AMALG_URL="${SQLITE_AMALG_URL:-https://sqlite.org/2025/sqlite-amalgamation-3500200.zip}"
SQLITE_AMALG_SHA256="${SQLITE_AMALG_SHA256:-387991de2834b5da2894119ff4173a9ea0779ea55ebcf53d9a40b24d1dc2484e}"
SQLITE_AMALG_ZIP="${SQLITE_AMALG_ZIP:-$WORK_DIR/sqlite-amalgamation-3500200.zip}"

if [ -f "$REPO_ROOT/scripts/webos/env.sh" ]; then
  source "$REPO_ROOT/scripts/webos/env.sh"
fi

APP_ID="${APP_ID:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$REPO_ROOT/webos/meta/appinfo.json" 2>/dev/null || true)}"
APP_ID="${APP_ID:-com.mcphailmonator.plezy}"
APP_VER="${APP_VER:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$REPO_ROOT/webos/meta/appinfo.json" 2>/dev/null || grep -E '^version:' "$REPO_ROOT/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d'+' -f1)}"
APP_VER="${APP_VER:-2.26.1}"

mkdir -p "$OUT_DIR"

ORIG_IPK="${ORIG_IPK:-$(find "$REPO_ROOT/build" -name "${APP_ID}_*.ipk" 2>/dev/null | grep -v -E "(-32bit|_webos6-24|_webos25-26)\.ipk" | head -n 1 || true)}"
if [ -z "$ORIG_IPK" ] || [ ! -f "$ORIG_IPK" ]; then
  ORIG_IPK="${ORIG_IPK:-$(find "$REPO_ROOT/build" -name "*.ipk" 2>/dev/null | grep -v -E "(-32bit|_webos6-24|_webos25-26)\.ipk" | head -n 1 || true)}"
fi
if [ -z "$ORIG_IPK" ] || [ ! -f "$ORIG_IPK" ]; then
  ORIG_IPK="$OUT_DIR/${APP_ID}_${APP_VER}_arm_webos25-26.ipk"
fi

if [ ! -f "$ORIG_IPK" ]; then
  echo "ERROR: Basis-IPK nicht gefunden. Bitte zuerst 'flutter-webos build webos --release' ausfuehren."
  exit 1
fi

MODERN_IPK_PATH="$OUT_DIR/${APP_ID}_${APP_VER}_arm_webos25-26.ipk"
if [ "$(realpath "$ORIG_IPK")" != "$(realpath "$MODERN_IPK_PATH" 2>/dev/null || echo "")" ]; then
  cp -f "$ORIG_IPK" "$MODERN_IPK_PATH"
fi

NDK_NATIVE_BIN="${WEBOS_SDK_DIR}/sysroots/x86_64-starfishsdk-linux/usr/bin"
NDK_TARGET_SYSROOT="${WEBOS_SDK_DIR}/sysroots/ca9v1-webosmllib32-linux-gnueabi"
CLANG_BIN="${NDK_NATIVE_BIN}/clang"
if [ ! -x "$CLANG_BIN" ]; then
  CLANG_BIN="$(find "${WEBOS_SDK_DIR}" -name "clang" -type f 2>/dev/null | head -n 1)"
fi
if [ ! -x "$CLANG_BIN" ] || [ ! -d "$NDK_TARGET_SYSROOT" ]; then
  echo "ERROR: Starfish NDK clang/sysroot nicht gefunden unter $WEBOS_SDK_DIR"
  exit 1
fi

export PATH="${NDK_NATIVE_BIN}:${NDK_NATIVE_BIN}/arm-webosmllib32-linux-gnueabi:${PATH}"

echo "=== [1/7] Entpacke Basis-IPK: $(basename "$ORIG_IPK") ==="
STAGE_DIR="/tmp/plezy_32bit_stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/ipk_extract" "$STAGE_DIR/data_extract"

cd "$STAGE_DIR/ipk_extract"
ar x "$ORIG_IPK"
cd "$STAGE_DIR/data_extract"
tar -xzf "$STAGE_DIR/ipk_extract/data.tar.gz"

APP_DIR="$(dirname "$(find "$STAGE_DIR/data_extract" -name "plezy" -type f | head -n 1)")"
echo "App-Ordner: $APP_DIR"

echo "=== [2/7] Kompiliere libsqlite3_dart.so (SQLite 3.50.2) + NativeAssetsManifest.json ==="
if [ ! -f "$SQLITE_AMALG_ZIP" ] || ! echo "$SQLITE_AMALG_SHA256  $SQLITE_AMALG_ZIP" | sha256sum -c --status -; then
  mkdir -p "$(dirname "$SQLITE_AMALG_ZIP")"
  tmp_sqlite="$(mktemp)"
  curl -fsSL -o "$tmp_sqlite" "$SQLITE_AMALG_URL"
  echo "$SQLITE_AMALG_SHA256  $tmp_sqlite" | sha256sum -c -
  mv -f "$tmp_sqlite" "$SQLITE_AMALG_ZIP"
fi

python3 - "$REPO_ROOT" "$APP_DIR" "$STAGE_DIR" "$SQLITE_AMALG_ZIP" "$CLANG_BIN" "$NDK_TARGET_SYSROOT" << 'PYEOF'
import json
import subprocess
import sys
import zipfile
from pathlib import Path

repo_root = Path(sys.argv[1])
app_dir = Path(sys.argv[2])
stage_dir = Path(sys.argv[3])
sqlite_zip = Path(sys.argv[4])
clang_bin = sys.argv[5]
target_sysroot = sys.argv[6]

FALLBACK_USED_SQLITE_SYMBOLS = [
    "sqlite3_aggregate_context",
    "sqlite3_auto_extension",
    "sqlite3_backup_finish",
    "sqlite3_backup_init",
    "sqlite3_backup_pagecount",
    "sqlite3_backup_remaining",
    "sqlite3_backup_step",
    "sqlite3_bind_blob64",
    "sqlite3_bind_double",
    "sqlite3_bind_int64",
    "sqlite3_bind_null",
    "sqlite3_bind_parameter_count",
    "sqlite3_bind_parameter_index",
    "sqlite3_bind_text",
    "sqlite3_busy_handler",
    "sqlite3_changes",
    "sqlite3_close_v2",
    "sqlite3_column_blob",
    "sqlite3_column_bytes",
    "sqlite3_column_count",
    "sqlite3_column_double",
    "sqlite3_column_int64",
    "sqlite3_column_name",
    "sqlite3_column_table_name",
    "sqlite3_column_text",
    "sqlite3_column_type",
    "sqlite3_commit_hook",
    "sqlite3_compileoption_get",
    "sqlite3_compileoption_used",
    "sqlite3_create_collation_v2",
    "sqlite3_create_function_v2",
    "sqlite3_create_window_function",
    "sqlite3_db_config",
    "sqlite3_db_filename",
    "sqlite3_errmsg",
    "sqlite3_error_offset",
    "sqlite3_errstr",
    "sqlite3_exec",
    "sqlite3_extended_errcode",
    "sqlite3_extended_result_codes",
    "sqlite3_finalize",
    "sqlite3_free",
    "sqlite3_get_autocommit",
    "sqlite3_initialize",
    "sqlite3_last_insert_rowid",
    "sqlite3_libversion",
    "sqlite3_libversion_number",
    "sqlite3_open_v2",
    "sqlite3_prepare_v2",
    "sqlite3_prepare_v3",
    "sqlite3_reset",
    "sqlite3_result_blob64",
    "sqlite3_result_double",
    "sqlite3_result_error",
    "sqlite3_result_int64",
    "sqlite3_result_null",
    "sqlite3_result_subtype",
    "sqlite3_result_text",
    "sqlite3_rollback_hook",
    "sqlite3_sourceid",
    "sqlite3_step",
    "sqlite3_stmt_isexplain",
    "sqlite3_stmt_readonly",
    "sqlite3_temp_directory",
    "sqlite3_update_hook",
    "sqlite3_user_data",
    "sqlite3_value_blob",
    "sqlite3_value_bytes",
    "sqlite3_value_double",
    "sqlite3_value_int64",
    "sqlite3_value_subtype",
    "sqlite3_value_text",
    "sqlite3_value_type",
    "sqlite3_vfs_register",
    "sqlite3_vfs_unregister",
    "sqlite3changeset_apply",
    "sqlite3changeset_finalize",
    "sqlite3changeset_invert",
    "sqlite3changeset_new",
    "sqlite3changeset_next",
    "sqlite3changeset_old",
    "sqlite3changeset_op",
    "sqlite3changeset_start",
    "sqlite3session_attach",
    "sqlite3session_changeset",
    "sqlite3session_create",
    "sqlite3session_delete",
    "sqlite3session_diff",
    "sqlite3session_enable",
    "sqlite3session_indirect",
    "sqlite3session_isempty",
    "sqlite3session_patchset",
]

used_symbols = list(FALLBACK_USED_SQLITE_SYMBOLS)
pkg_cfg = repo_root / ".dart_tool" / "package_config.json"
if pkg_cfg.is_file():
    cfg_data = json.loads(pkg_cfg.read_text())
    for pkg in cfg_data.get("packages", []):
        if pkg.get("name") == "sqlite3":
            root_uri = pkg.get("rootUri", "")
            pkg_root = Path(root_uri.removeprefix("file://")) if root_uri.startswith("file://") else (pkg_cfg.parent / root_uri).resolve()
            used_file = pkg_root / "lib" / "src" / "hook" / "compile" / "used_symbols.dart"
            if used_file.is_file():
                parsed = [
                    line.strip().split("'")[1]
                    for line in used_file.read_text().splitlines()
                    if line.strip().startswith("'sqlite3")
                ]
                if parsed:
                    used_symbols = parsed
            break

sqlite_src_dir = stage_dir / "sqlite_src"
sqlite_src_dir.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(sqlite_zip) as zf:
    zf.extractall(sqlite_src_dir)
c_file = next(sqlite_src_dir.rglob("sqlite3.c"))

version_script = stage_dir / "sqlite3_dart.ver"
version_script.write_text(
    "{\n  global:\n"
    + "\n".join(f"    {sym};" for sym in used_symbols)
    + "\n  local:\n    *;\n};\n"
)

defines = [
    "SQLITE_ENABLE_DBSTAT_VTAB",
    "SQLITE_ENABLE_FTS5",
    "SQLITE_ENABLE_RTREE",
    "SQLITE_ENABLE_MATH_FUNCTIONS",
    "SQLITE_DQS=0",
    "SQLITE_DEFAULT_MEMSTATUS=0",
    "SQLITE_TEMP_STORE=2",
    "SQLITE_MAX_EXPR_DEPTH=0",
    "SQLITE_STRICT_SUBTYPE=1",
    "SQLITE_OMIT_AUTHORIZATION",
    "SQLITE_OMIT_DECLTYPE",
    "SQLITE_OMIT_DEPRECATED",
    "SQLITE_OMIT_PROGRESS_CALLBACK",
    "SQLITE_OMIT_SHARED_CACHE",
    "SQLITE_OMIT_TCL_VARIABLE",
    "SQLITE_OMIT_TRACE",
    "SQLITE_USE_ALLOCA",
    "SQLITE_ENABLE_SESSION",
    "SQLITE_ENABLE_PREUPDATE_HOOK",
    "SQLITE_UNTESTABLE",
    "SQLITE_HAVE_ISNAN",
    "SQLITE_HAVE_LOCALTIME_R",
    "SQLITE_HAVE_LOCALTIME_S",
    "SQLITE_HAVE_MALLOC_USABLE_SIZE",
    "SQLITE_HAVE_STRCHRNUL",
    "SQLITE_ENABLE_BATCH_ATOMIC_WRITE",
    "SQLITE_THREADSAFE=1",
    "_FILE_OFFSET_BITS=64",
]

out_sqlite_so = app_dir / "lib" / "libsqlite3_dart.so"
cmd = [
    clang_bin,
    "--target=arm-webosmllib32-linux-gnueabi",
    "-mthumb",
    "-mfpu=neon",
    "-mfloat-abi=softfp",
    "-mcpu=cortex-a9",
    "-mlittle-endian",
    f"--sysroot={target_sysroot}",
    "-shared",
    "-fPIC",
    "-O2",
    "-ffunction-sections",
    "-fdata-sections",
    "-Wl,-O1",
    "-Wl,--hash-style=gnu",
    "-Wl,-Bsymbolic",
    f"-Wl,--version-script={version_script}",
    "-Wl,--gc-sections",
    "-Wl,-soname,libsqlite3_dart.so",
    f"-I{c_file.parent}",
    *[f"-D{d}" for d in defines],
    str(c_file),
    "-lm",
    "-ldl",
    "-lpthread",
    "-o",
    str(out_sqlite_so),
]
subprocess.check_call(cmd)
out_sqlite_so.chmod(0o755)

assets_dir = app_dir / "data" / "flutter_assets"
assets_dir.mkdir(parents=True, exist_ok=True)
manifest_path = assets_dir / "NativeAssetsManifest.json"
manifest_data = {
    "format-version": [1, 0, 0],
    "native-assets": {
        "linux_arm": {
            "package:sqlite3/src/ffi/libsqlite3.g.dart": [
                "system",
                "libsqlite3_dart.so",
            ]
        }
    },
}
manifest_path.write_text(json.dumps(manifest_data, indent=2) + "\n")
print(f"  -> libsqlite3_dart.so gebaut ({out_sqlite_so.stat().st_size} Bytes, {len(used_symbols)} Symbole) & NativeAssetsManifest.json geschrieben!")
PYEOF

echo "=== [3/7] Bundle NDK libstdc++.so.6 (6.0.32 / GLIBCXX_3.4.32) ==="
NDK_LIBSTDCPP="$NDK_TARGET_SYSROOT/usr/lib/libstdc++.so.6"
if [ ! -e "$NDK_LIBSTDCPP" ]; then
  echo "ERROR: libstdc++.so.6 nicht im NDK-Sysroot gefunden: $NDK_LIBSTDCPP"
  exit 1
fi
cp -L "$NDK_LIBSTDCPP" "$APP_DIR/lib/libstdc++.so.6"
chmod 0755 "$APP_DIR/lib/libstdc++.so.6"
echo "  -> libstdc++.so.6 gebundelt: $(basename "$(realpath "$NDK_LIBSTDCPP")")"

echo "=== [4/7] Baue libwebos_compat32.so (webOS 6-25 Shims + glibc 2.28-2.38 Bridges) ==="
python3 - "$APP_DIR" "$STAGE_DIR/webos_compat32.c" << 'PYEOF'
import subprocess
import sys
from pathlib import Path

app_dir = Path(sys.argv[1])
c_out = Path(sys.argv[2])

binaries = [str(app_dir / "plezy")] + [
    str(p)
    for p in sorted((app_dir / "lib").glob("*.so*"))
    if p.name not in ("libwebos_compat32.so", "libapp.so")
]

out = subprocess.check_output(["readelf", "-Ws"] + binaries, text=True, errors="ignore")

und_ndl = set()
for line in out.splitlines():
    if "UND" not in line:
        continue
    parts = line.split()
    if not parts:
        continue
    tok = parts[-2] if parts[-1].startswith("(") else parts[-1]
    sym = tok.split("@")[0]
    if sym.startswith("NDL_"):
        und_ndl.add(sym)

qned_native_ndl = {
    "NDL_MediaGetCurrentPosition",
    "NDL_Media_DL_IsInitialized",
    "NDL_MediaGetError",
    "NDL_MediaSetPlayer",
    "NDL_Media_DL_Initialize",
    "NDL_MediaInit",
    "NDL_MediaLoad",
    "NDL_MediaLoadWithOption",
    "NDL_MediaPreload",
    "NDL_MediaPause",
    "NDL_MediaPlay",
    "NDL_MediaQuit",
    "NDL_Media_DL_Finalize",
    "NDL_MediaSeekTo",
    "NDL_MediaSelectTrack",
    "NDL_MediaSetDisplayWindow",
    "NDL_MediaMuteDisplay",
    "NDL_MediaSetPlaybackRate",
    "NDL_MediaSetSubtitleColor",
    "NDL_MediaSetSubtitleEnable",
    "NDL_MediaSetSubtitleEncoding",
    "NDL_MediaSetSubtitleFontSize",
    "NDL_MediaSetSubtitlePosition",
    "NDL_MediaSetSubtitleSource",
    "NDL_MediaSetSubtitleSync",
    "NDL_MediaSubscribeEvents",
    "NDL_MediaUnload",
    "NDL_MediaDRMInit",
    "NDL_MediaDRMQuit",
    "NDL_MediaDRMGetError",
    "NDL_MediaDRMIsLoaded",
    "NDL_MediaDRMLoad",
    "NDL_MediaDRMUnload",
    "NDL_MediaDRMSendMessage",
    "NDL_MediaDRMSendMessageAsync",
    "NDL_MediaDRMGetRightsError",
}

c_code = """#include <stdarg.h>
typedef __UINT32_TYPE__ uint32_t;
typedef __INT32_TYPE__  int32_t;
typedef __UINT16_TYPE__ uint16_t;
typedef __UINTPTR_TYPE__ uintptr_t;

#define EXPORT __attribute__((used, visibility("default")))
#define RTLD_NEXT ((void *)-1L)
#define RTLD_LAZY 0x00001
#define _STAT_VER_LINUX 3
#define WL_MARSHAL_FLAG_DESTROY 1
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 1
#define EINVAL 22
#define ENOENT 2

#define COMPAT_O_RDONLY  0
#define COMPAT_O_WRONLY  1
#define COMPAT_O_CREAT   64
#define COMPAT_O_TRUNC   512
#define COMPAT_O_APPEND  1024
#define COMPAT_O_CLOEXEC 524288

#define COMPAT_SIGILL    4
#define COMPAT_SIGABRT   6
#define COMPAT_SIGBUS    7
#define COMPAT_SIGFPE    8
#define COMPAT_SIGSEGV   11

#define COMPAT_SA_SIGINFO   4
#define COMPAT_SA_RESETHAND 0x80000000U

#define PMLOG_LEVEL_ERROR 3
#define PMLOG_LEVEL_INFO  6

typedef struct _IO_FILE FILE;
typedef void *locale_t;

struct compat_timespec {
    long tv_sec;
    long tv_nsec;
};

struct compat_sigaction {
    void (*sa_sigaction)(int, void *, void *);
    uint32_t sa_mask[32];
    int sa_flags;
    void (*sa_restorer)(void);
};

extern void *dlsym(void *handle, const char *symbol);
extern void *dlvsym(void *handle, const char *symbol, const char *version);
extern void *dlopen(const char *filename, int flags);
extern int strcmp(const char *s1, const char *s2);
extern int strncmp(const char *s1, const char *s2, unsigned int n);
extern int mkdir(const char *pathname, unsigned int mode);
extern int chmod(const char *pathname, unsigned int mode);
extern int access(const char *pathname, int mode);
extern int open(const char *pathname, int flags, ...);
extern int read(int fd, void *buf, unsigned int count);
extern int write(int fd, const void *buf, unsigned int count);
extern int close(int fd);
extern int readlink(const char *pathname, char *buf, unsigned int bufsiz);
extern int unlink(const char *pathname);

extern int clock_gettime(int clk_id, struct compat_timespec *tp);
extern int pthread_cond_timedwait(void *cond, void *mutex, const struct compat_timespec *abstime);

extern long strtol(const char *nptr, char **endptr, int base);
extern unsigned long strtoul(const char *nptr, char **endptr, int base);
extern long long strtoll(const char *nptr, char **endptr, int base);
extern unsigned long long strtoull(const char *nptr, char **endptr, int base);
extern long strtol_l(const char *nptr, char **endptr, int base, locale_t loc);
extern unsigned long strtoul_l(const char *nptr, char **endptr, int base, locale_t loc);
extern long long strtoll_l(const char *nptr, char **endptr, int base, locale_t loc);
extern unsigned long long strtoull_l(const char *nptr, char **endptr, int base, locale_t loc);

extern int vsscanf(const char *str, const char *format, va_list ap);
extern int vfscanf(FILE *stream, const char *format, va_list ap);
extern int vscanf(const char *format, va_list ap);

extern long wcstol(const int *nptr, int **endptr, int base);
extern unsigned long wcstoul(const int *nptr, int **endptr, int base);
extern long long wcstoll(const int *nptr, int **endptr, int base);
extern unsigned long long wcstoull(const int *nptr, int **endptr, int base);

typedef struct {
    uint32_t dlpi_addr;
    const char *dlpi_name;
    const void *dlpi_phdr;
    uint16_t dlpi_phnum;
} compat_dl_phdr_info_t;

typedef struct {
    uint32_t p_type;
    uint32_t p_offset;
    uint32_t p_vaddr;
    uint32_t p_paddr;
    uint32_t p_filesz;
    uint32_t p_memsz;
    uint32_t p_flags;
    uint32_t p_align;
} compat_elf32_phdr_t;

typedef struct {
    int32_t d_tag;
    uint32_t d_val;
} compat_elf32_dyn_t;

extern int dl_iterate_phdr(int (*callback)(compat_dl_phdr_info_t *info, unsigned int size, void *data), void *data);

static void copy_str(char *dst, const char *src, unsigned int max_len) {
    if (!dst || max_len == 0) return;
    unsigned int i = 0;
    if (src) {
        while (src[i] && i + 1 < max_len) {
            dst[i] = src[i];
            ++i;
        }
    }
    dst[i] = '\\0';
}

static unsigned int c_strlen(const char *s) {
    unsigned int n = 0;
    if (!s) return 0;
    while (s[n]) ++n;
    return n;
}

static void c_memzero(void *dst, unsigned int len) {
    unsigned char *p = (unsigned char *)dst;
    for (unsigned int i = 0; i < len; ++i) p[i] = 0;
}

static void c_memcpy(void *dst, const void *src, unsigned int len) {
    unsigned char *d = (unsigned char *)dst;
    const unsigned char *s = (const unsigned char *)src;
    for (unsigned int i = 0; i < len; ++i) d[i] = s[i];
}

static const char *c_strstr(const char *hay, const char *needle) {
    if (!hay || !needle) return 0;
    if (!needle[0]) return hay;
    for (unsigned int i = 0; hay[i]; ++i) {
        unsigned int j = 0;
        while (needle[j] && hay[i + j] == needle[j]) ++j;
        if (!needle[j]) return hay + i;
    }
    return 0;
}

static void *resolve_libc_sym(const char *name) {
    static void *libc_handle = 0;
    void *fn = dlsym(RTLD_NEXT, name);
    if (fn) return fn;
    if (!libc_handle) {
        libc_handle = dlopen("libc.so.6", RTLD_LAZY);
        if (!libc_handle) libc_handle = dlopen("/lib/libc.so.6", RTLD_LAZY);
    }
    if (libc_handle) {
        fn = dlsym(libc_handle, name);
    }
    return fn;
}

static void *resolve_pthread_sym(const char *name) {
    static void *pt_handle = 0;
    void *fn = dlsym(RTLD_NEXT, name);
    if (fn) return fn;
    if (!pt_handle) {
        pt_handle = dlopen("libpthread.so.0", RTLD_LAZY);
        if (!pt_handle) pt_handle = dlopen("/lib/libpthread.so.0", RTLD_LAZY);
    }
    if (pt_handle) {
        fn = dlsym(pt_handle, name);
        if (fn) return fn;
    }
    return resolve_libc_sym(name);
}

/* ============================================================================
 * Async-Signal-Safe State, Boot Tracer, Crash Handlers & Fatal Function Hooks
 * ============================================================================ */
typedef int (*fn_open_t)(const char *, int, ...);
typedef int (*fn_read_t)(int, void *, unsigned int);
typedef int (*fn_write_t)(int, const void *, unsigned int);
typedef int (*fn_close_t)(int);
typedef int (*fn_readlink_t)(const char *, char *, unsigned int);
typedef int (*fn_getpid_t)(void);
typedef unsigned int (*fn_getuid_t)(void);
typedef int (*fn_sigaction_t)(int, const struct compat_sigaction *, struct compat_sigaction *);
typedef void (*fn_abort_t)(void);
typedef void (*fn_assert_fail_t)(const char *, const char *, unsigned int, const char *);
typedef void (*fn_exit_t)(int);
typedef FILE *(*fn_fopen_t)(const char *, const char *);
typedef int *(*fn_errno_loc_t)(void);
typedef int (*fn_pmlog_getctx_t)(const char *, const void **);
typedef int (*fn_pmlog_str_t)(const void *, int, const char *, const char *, const char *);
typedef int (*fn_setenv_t)(const char *, const char *, int);
typedef char *(*fn_getenv_t)(const char *);

static fn_open_t        g_real_open        = 0;
static fn_read_t        g_real_read        = 0;
static fn_write_t       g_real_write       = 0;
static fn_close_t       g_real_close       = 0;
static fn_readlink_t    g_real_readlink    = 0;
static fn_getpid_t      g_real_getpid      = 0;
static fn_getuid_t      g_real_getuid      = 0;
static fn_sigaction_t   g_real_sigaction   = 0;
static fn_abort_t       g_real_abort       = 0;
static fn_assert_fail_t g_real_assert_fail = 0;
static fn_exit_t        g_real_exit        = 0;
static fn_fopen_t       g_real_fopen       = 0;
static fn_fopen_t       g_real_fopen64     = 0;
static fn_errno_loc_t   g_real_errno_loc   = 0;
static fn_setenv_t      g_real_setenv      = 0;
static fn_getenv_t      g_real_getenv      = 0;
static fn_pmlog_str_t   g_pmlog_str        = 0;
static const void      *g_pmlog_ctx        = 0;

#ifndef COMPAT32_APP_ID
#define COMPAT32_APP_ID "com.mcphailmonator.plezy"
#endif

static char g_exe_dir[512]       = "";
static char g_appdata_dir[512]   = "/tmp/plezy_appdata";
static char g_cache_dir[512]     = "/tmp/plezy_appdata/.cache";
static char g_download_dir[512]  = "/tmp/plezy_appdata/.download";
static char g_log_dir[512]       = "/tmp/plezy_appdata/log";
static char g_boot_log_path[512] = "/tmp/plezy_boot.log";
static int  g_main_pid           = -1;
static volatile int g_crash_lock = 0;

EXPORT void abort(void);
EXPORT void exit(int status);
EXPORT void __assert_fail(const char *assertion, const char *file, unsigned int line, const char *function);
EXPORT FILE *fopen(const char *pathname, const char *mode);
EXPORT FILE *fopen64(const char *pathname, const char *mode);
EXPORT int setenv(const char *name, const char *value, int overwrite);
EXPORT char *getenv(const char *name);
static void ensure_compat_init(void);

static void cache_libc_ptrs(void) {
    static int done = 0;
    if (done) return;
    done = 1;
    void *p;
    g_real_open     = (fn_open_t)resolve_libc_sym("open");
    g_real_read     = (fn_read_t)resolve_libc_sym("read");
    g_real_write    = (fn_write_t)resolve_libc_sym("write");
    g_real_close    = (fn_close_t)resolve_libc_sym("close");
    g_real_readlink = (fn_readlink_t)resolve_libc_sym("readlink");
    g_real_getpid   = (fn_getpid_t)resolve_libc_sym("getpid");
    g_real_getuid   = (fn_getuid_t)resolve_libc_sym("getuid");
    g_real_sigaction = (fn_sigaction_t)resolve_libc_sym("sigaction");
    g_real_errno_loc = (fn_errno_loc_t)resolve_libc_sym("__errno_location");

    p = resolve_libc_sym("abort");
    if (p && p != (void *)abort) g_real_abort = (fn_abort_t)p;
    p = resolve_libc_sym("__assert_fail");
    if (p && p != (void *)__assert_fail) g_real_assert_fail = (fn_assert_fail_t)p;
    p = resolve_libc_sym("exit");
    if (p && p != (void *)exit) g_real_exit = (fn_exit_t)p;
    p = resolve_libc_sym("fopen");
    if (p && p != (void *)fopen) g_real_fopen = (fn_fopen_t)p;
    p = resolve_libc_sym("fopen64");
    if (p && p != (void *)fopen64) g_real_fopen64 = (fn_fopen_t)p;
    if (!g_real_fopen64) g_real_fopen64 = g_real_fopen;
    p = resolve_libc_sym("setenv");
    if (p && p != (void *)setenv) g_real_setenv = (fn_setenv_t)p;
    p = resolve_libc_sym("getenv");
    if (p && p != (void *)getenv) g_real_getenv = (fn_getenv_t)p;
}

static void init_pmlog(void) {
    static int tried = 0;
    if (tried) return;
    tried = 1;
    void *h = dlopen("libPmLogLib.so.3", RTLD_LAZY);
    if (!h) h = dlopen("/usr/lib/libPmLogLib.so.3", RTLD_LAZY);
    if (!h) return;
    fn_pmlog_getctx_t getctx = (fn_pmlog_getctx_t)dlsym(h, "PmLogGetContext");
    g_pmlog_str = (fn_pmlog_str_t)dlsym(h, "PmLogString_");
    if (getctx) {
        if (getctx("plezy.compat32", &g_pmlog_ctx) != 0) {
            g_pmlog_ctx = 0;
        }
    }
}

struct log_buf {
    char data[768];
    unsigned int len;
};

static void lbuf_init(struct log_buf *b) {
    b->len = 0;
    b->data[0] = '\\0';
}

static void lbuf_str(struct log_buf *b, const char *s) {
    if (!s) s = "(null)";
    for (unsigned int i = 0; s[i] && b->len + 2 < sizeof(b->data); ++i) {
        b->data[b->len++] = s[i];
    }
    b->data[b->len] = '\\0';
}

static void lbuf_str_trunc(struct log_buf *b, const char *s, unsigned int maxc) {
    if (!s) s = "(null)";
    for (unsigned int i = 0; s[i] && i < maxc && b->len + 2 < sizeof(b->data); ++i) {
        char ch = s[i];
        if (ch == '\\n' || ch == '\\r') ch = ' ';
        b->data[b->len++] = ch;
    }
    b->data[b->len] = '\\0';
}

static void lbuf_hex32(struct log_buf *b, uint32_t v) {
    const char *hex = "0123456789abcdef";
    lbuf_str(b, "0x");
    for (int shift = 28; shift >= 0 && b->len + 2 < sizeof(b->data); shift -= 4) {
        b->data[b->len++] = hex[(v >> shift) & 0xfU];
    }
    b->data[b->len] = '\\0';
}

static void lbuf_u32(struct log_buf *b, uint32_t v) {
    static const uint32_t pow10[10] = {
        1000000000U, 100000000U, 10000000U, 1000000U, 100000U,
        10000U, 1000U, 100U, 10U, 1U
    };
    int started = 0;
    for (int i = 0; i < 10; ++i) {
        uint32_t p = pow10[i];
        uint32_t d = 0;
        while (v >= p) {
            v -= p;
            ++d;
        }
        if (d > 0 || started || i == 9) {
            started = 1;
            if (b->len + 2 < sizeof(b->data)) {
                b->data[b->len++] = (char)('0' + d);
            }
        }
    }
    b->data[b->len] = '\\0';
}

static void lbuf_i32(struct log_buf *b, int32_t v) {
    if (v < 0) {
        lbuf_str(b, "-");
        lbuf_u32(b, (uint32_t)(-(v + 1)) + 1U);
    } else {
        lbuf_u32(b, (uint32_t)v);
    }
}

static void write_file_line_raw(const char *path, const char *line, unsigned int len) {
    fn_open_t fn_open = g_real_open ? g_real_open : open;
    fn_write_t fn_write = g_real_write ? g_real_write : write;
    fn_close_t fn_close = g_real_close ? g_real_close : close;
    if (!path || !path[0] || !line || len == 0) return;
    int fd = fn_open(path, COMPAT_O_CREAT | COMPAT_O_WRONLY | COMPAT_O_APPEND | COMPAT_O_CLOEXEC, 0666);
    if (fd >= 0) {
        (void)fn_write(fd, line, len);
        (void)fn_write(fd, "\\n", 1);
        fn_close(fd);
    }
}

static void log_raw_line(int pmlog_level, const struct log_buf *b, int allow_pmlog) {
    write_file_line_raw(g_boot_log_path, b->data, b->len);
    if (strcmp(g_boot_log_path, "/tmp/plezy_boot.log") != 0) {
        write_file_line_raw("/tmp/plezy_boot.log", b->data, b->len);
    }
    if (allow_pmlog && g_pmlog_str) {
        g_pmlog_str(g_pmlog_ctx, pmlog_level, "COMPAT32", "{}", b->data);
    }
}

static void log_text(int pmlog_level, const char *msg) {
    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "[compat32 pid=");
    lbuf_i32(&b, g_real_getpid ? g_real_getpid() : 0);
    lbuf_str(&b, "] ");
    lbuf_str_trunc(&b, msg, 680);
    log_raw_line(pmlog_level, &b, 1);
}

static int parse_hex_range_u32(const char *s, uint32_t *out_val, const char **next_p) {
    uint32_t v = 0;
    int digits = 0;
    while (*s) {
        char c = *s;
        uint32_t d;
        if (c >= '0' && c <= '9') d = (uint32_t)(c - '0');
        else if (c >= 'a' && c <= 'f') d = (uint32_t)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') d = (uint32_t)(c - 'A' + 10);
        else break;
        v = (v << 4) | d;
        ++digits;
        ++s;
    }
    if (digits == 0) return 0;
    *out_val = v;
    *next_p = s;
    return 1;
}

static void log_addr_in_maps_raw(const char *tag, uint32_t addr, int allow_pmlog) {
    fn_open_t fn_open = g_real_open ? g_real_open : open;
    fn_read_t fn_read = g_real_read ? g_real_read : read;
    fn_close_t fn_close = g_real_close ? g_real_close : close;
    if (!addr) return;
    int fd = fn_open("/proc/self/maps", COMPAT_O_RDONLY | COMPAT_O_CLOEXEC);
    if (fd < 0) return;

    char chunk[512];
    char line[384];
    unsigned int line_len = 0;
    int matched = 0;
    for (;;) {
        int n = fn_read(fd, chunk, sizeof(chunk));
        if (n <= 0) break;
        for (int i = 0; i < n; ++i) {
            char ch = chunk[i];
            if (ch == '\\n') {
                line[line_len] = '\\0';
                uint32_t start_va = 0, end_va = 0;
                const char *p1 = 0, *p2 = 0;
                if (parse_hex_range_u32(line, &start_va, &p1) && p1 && *p1 == '-' &&
                    parse_hex_range_u32(p1 + 1, &end_va, &p2)) {
                    if (addr >= start_va && addr < end_va) {
                        struct log_buf b;
                        lbuf_init(&b);
                        lbuf_str(&b, "  ");
                        lbuf_str(&b, tag);
                        lbuf_str(&b, "=");
                        lbuf_hex32(&b, addr);
                        lbuf_str(&b, " (+");
                        lbuf_hex32(&b, addr - start_va);
                        lbuf_str(&b, ") in ");
                        lbuf_str_trunc(&b, line, 240);
                        log_raw_line(PMLOG_LEVEL_ERROR, &b, allow_pmlog);
                        matched = 1;
                    }
                }
                line_len = 0;
            } else if (line_len + 1 < sizeof(line)) {
                line[line_len++] = ch;
            }
        }
        if (matched) break;
    }
    fn_close(fd);
}

static void compat_crash_handler(int signo, void *siginfo_ptr, void *ucontext_ptr) {
    if (__atomic_test_and_set(&g_crash_lock, __ATOMIC_ACQUIRE)) {
        return;
    }
    uint32_t si_code = 0, si_addr = 0;
    uint32_t r0 = 0, sp_reg = 0, lr_reg = 0, pc_reg = 0, cpsr = 0, fault = 0;
    if (siginfo_ptr) {
        const char *si = (const char *)siginfo_ptr;
        si_code = *(const uint32_t *)(si + 8);
        si_addr = *(const uint32_t *)(si + 12);
    }
    if (ucontext_ptr) {
        const char *uc = (const char *)ucontext_ptr;
        r0     = *(const uint32_t *)(uc + 32);
        sp_reg = *(const uint32_t *)(uc + 84);
        lr_reg = *(const uint32_t *)(uc + 88);
        pc_reg = *(const uint32_t *)(uc + 92);
        cpsr   = *(const uint32_t *)(uc + 96);
        fault  = *(const uint32_t *)(uc + 100);
    }

    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "FATAL SIGNAL=");
    lbuf_i32(&b, signo);
    lbuf_str(&b, " code=");
    lbuf_hex32(&b, si_code);
    lbuf_str(&b, " si_addr=");
    lbuf_hex32(&b, si_addr);
    lbuf_str(&b, " pc=");
    lbuf_hex32(&b, pc_reg);
    lbuf_str(&b, " lr=");
    lbuf_hex32(&b, lr_reg);
    lbuf_str(&b, " sp=");
    lbuf_hex32(&b, sp_reg);
    lbuf_str(&b, " r0=");
    lbuf_hex32(&b, r0);
    lbuf_str(&b, " cpsr=");
    lbuf_hex32(&b, cpsr);
    lbuf_str(&b, " fault=");
    lbuf_hex32(&b, fault);
    log_raw_line(PMLOG_LEVEL_ERROR, &b, 0);

    log_addr_in_maps_raw("pc", pc_reg, 0);
    log_addr_in_maps_raw("lr", lr_reg, 0);
    log_addr_in_maps_raw("si_addr", si_addr, 0);
}

static void install_crash_handlers(void) {
    static int installed = 0;
    if (installed) return;
    installed = 1;
    fn_sigaction_t fn_sig = g_real_sigaction ? g_real_sigaction : (fn_sigaction_t)resolve_libc_sym("sigaction");
    if (!fn_sig) return;

    struct compat_sigaction sa;
    c_memzero(&sa, sizeof(sa));
    sa.sa_sigaction = compat_crash_handler;
    sa.sa_flags = COMPAT_SA_SIGINFO | (int)COMPAT_SA_RESETHAND;

    const int sigs[5] = {COMPAT_SIGABRT, COMPAT_SIGSEGV, COMPAT_SIGBUS, COMPAT_SIGILL, COMPAT_SIGFPE};
    for (int i = 0; i < 5; ++i) {
        fn_sig(sigs[i], &sa, 0);
    }
}

EXPORT void abort(void) {
    cache_libc_ptrs();
    uint32_t caller = (uint32_t)(uintptr_t)__builtin_return_address(0);
    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "HOOK abort() caller=");
    lbuf_hex32(&b, caller);
    log_raw_line(PMLOG_LEVEL_ERROR, &b, 1);
    log_addr_in_maps_raw("abort_caller", caller, 1);

    if (g_real_abort) g_real_abort();
    for (;;) { *(volatile int *)0 = 1; }
}

EXPORT void __assert_fail(const char *assertion, const char *file, unsigned int line, const char *function) {
    cache_libc_ptrs();
    uint32_t caller = (uint32_t)(uintptr_t)__builtin_return_address(0);
    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "HOOK __assert_fail caller=");
    lbuf_hex32(&b, caller);
    lbuf_str(&b, " file=");
    lbuf_str_trunc(&b, file, 140);
    lbuf_str(&b, ":");
    lbuf_u32(&b, line);
    lbuf_str(&b, " fn=");
    lbuf_str_trunc(&b, function, 120);
    lbuf_str(&b, " cond=");
    lbuf_str_trunc(&b, assertion, 120);
    log_raw_line(PMLOG_LEVEL_ERROR, &b, 1);
    log_addr_in_maps_raw("assert_caller", caller, 1);

    if (g_real_assert_fail) {
        g_real_assert_fail(assertion, file, line, function);
    }
    abort();
}

EXPORT void _ZSt9terminatev(void) {
    cache_libc_ptrs();
    uint32_t caller = (uint32_t)(uintptr_t)__builtin_return_address(0);
    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "HOOK std::terminate() caller=");
    lbuf_hex32(&b, caller);
    log_raw_line(PMLOG_LEVEL_ERROR, &b, 1);
    log_addr_in_maps_raw("terminate_caller", caller, 1);

    typedef void (*term_fn_t)(void);
    term_fn_t real_term = (term_fn_t)dlsym(RTLD_NEXT, "_ZSt9terminatev");
    if (!real_term || real_term == _ZSt9terminatev) {
        void *h = dlopen("libstdc++.so.6", RTLD_LAZY);
        if (h) {
            void *p = dlsym(h, "_ZSt9terminatev");
            if (p && p != (void *)_ZSt9terminatev) real_term = (term_fn_t)p;
        }
    }
    if (real_term && real_term != _ZSt9terminatev) {
        real_term();
    }
    abort();
}

EXPORT void exit(int status) {
    cache_libc_ptrs();
    int cur_pid = g_real_getpid ? g_real_getpid() : -1;
    if (g_main_pid < 0 || cur_pid == g_main_pid) {
        uint32_t caller = (uint32_t)(uintptr_t)__builtin_return_address(0);
        struct log_buf b;
        lbuf_init(&b);
        lbuf_str(&b, "HOOK exit(status=");
        lbuf_i32(&b, status);
        lbuf_str(&b, ") caller=");
        lbuf_hex32(&b, caller);
        log_raw_line(status ? PMLOG_LEVEL_ERROR : PMLOG_LEVEL_INFO, &b, 1);
        if (status != 0) log_addr_in_maps_raw("exit_caller", caller, 1);
    }
    if (g_real_exit) g_real_exit(status);
    for (;;) { *(volatile int *)0 = 1; }
}

/* ============================================================================
 * /var/luna/preferences/localeInfo Schema Validation Guard
 * ============================================================================ */
static const char *skip_ws(const char *p, const char *end) {
    while (p < end && (*p == ' ' || *p == '\\t' || *p == '\\n' || *p == '\\r')) ++p;
    return p;
}

static int json_match_quoted_key(const char *p, const char *end, const char *key, const char **after_quote) {
    unsigned int klen = c_strlen(key);
    if (p + 1U + klen + 1U > end || *p != '"') return 0;
    if (strncmp(p + 1, key, klen) != 0) return 0;
    if (p[1U + klen] != '"') return 0;
    *after_quote = p + 1U + klen + 1U;
    return 1;
}

static int validate_locale_info_file(void) {
    static int logged_ok = 0;
    fn_open_t fn_open = g_real_open ? g_real_open : open;
    fn_read_t fn_read = g_real_read ? g_real_read : read;
    fn_close_t fn_close = g_real_close ? g_real_close : close;
    int fd = fn_open("/var/luna/preferences/localeInfo", COMPAT_O_RDONLY | COMPAT_O_CLOEXEC);
    if (fd < 0) {
        log_text(PMLOG_LEVEL_INFO, "localeInfo open failed -> returning NULL for safe fallback");
        return 0;
    }
    char buf[8192];
    int total = 0;
    while (total < (int)sizeof(buf) - 1) {
        int n = fn_read(fd, buf + total, (unsigned int)((int)sizeof(buf) - 1 - total));
        if (n <= 0) break;
        total += n;
    }
    fn_close(fd);
    buf[total] = '\\0';
    const char *end = buf + total;
    const char *p = skip_ws(buf, end);
    if (p >= end || *p != '{') {
        log_text(PMLOG_LEVEL_ERROR, "localeInfo not JSON object -> forcing NULL fallback");
        return 0;
    }

    int depth = 0;
    int stage = 0; /* 0=seek localeInfo@d1, 1=seek locales@d2, 2=seek UI@d3 */
    int target_depth = 1;
    int in_str = 0;
    int esc = 0;
    while (p < end) {
        char c = *p;
        if (in_str) {
            if (esc) {
                esc = 0;
            } else if (c == '\\\\') {
                esc = 1;
            } else if (c == '"') {
                in_str = 0;
            }
            ++p;
            continue;
        }
        if (c == '"') {
            const char *after = 0;
            if (stage == 0 && depth == 1 && json_match_quoted_key(p, end, "localeInfo", &after)) {
                const char *col = skip_ws(after, end);
                if (col < end && *col == ':') {
                    const char *obj = skip_ws(col + 1, end);
                    if (obj < end && *obj == '{') {
                        stage = 1;
                        target_depth = 2;
                        depth = 2;
                        p = obj + 1;
                        continue;
                    }
                }
            } else if (stage == 1 && depth == 2 && json_match_quoted_key(p, end, "locales", &after)) {
                const char *col = skip_ws(after, end);
                if (col < end && *col == ':') {
                    const char *obj = skip_ws(col + 1, end);
                    if (obj < end && *obj == '{') {
                        stage = 2;
                        target_depth = 3;
                        depth = 3;
                        p = obj + 1;
                        continue;
                    }
                }
            } else if (stage == 2 && depth == 3 && json_match_quoted_key(p, end, "UI", &after)) {
                const char *col = skip_ws(after, end);
                if (col < end && *col == ':') {
                    const char *val = skip_ws(col + 1, end);
                    if (val + 1 < end && *val == '"' && val[1] != '"') {
                        if (!logged_ok) {
                            logged_ok = 1;
                            log_text(PMLOG_LEVEL_INFO, "localeInfo schema validated OK");
                        }
                        return 1;
                    }
                    log_text(PMLOG_LEVEL_ERROR, "localeInfo UI invalid/empty -> forcing NULL fallback");
                    return 0;
                }
            }
            in_str = 1;
            ++p;
            continue;
        }
        if (c == '{') {
            ++depth;
        } else if (c == '}') {
            --depth;
            if (stage > 0 && depth < target_depth) break;
        }
        ++p;
    }

    log_text(PMLOG_LEVEL_ERROR, "localeInfo missing localeInfo.locales.UI -> forcing NULL fallback");
    return 0;
}

EXPORT FILE *fopen64(const char *pathname, const char *mode) {
    cache_libc_ptrs();
    if (pathname && strcmp(pathname, "/var/luna/preferences/localeInfo") == 0) {
        if (!validate_locale_info_file()) {
            if (g_real_errno_loc) *g_real_errno_loc() = ENOENT;
            return 0;
        }
    }
    if (g_real_fopen64) return g_real_fopen64(pathname, mode);
    if (g_real_fopen) return g_real_fopen(pathname, mode);
    return 0;
}

EXPORT FILE *fopen(const char *pathname, const char *mode) {
    cache_libc_ptrs();
    if (pathname && strcmp(pathname, "/var/luna/preferences/localeInfo") == 0) {
        if (!validate_locale_info_file()) {
            if (g_real_errno_loc) *g_real_errno_loc() = ENOENT;
            return 0;
        }
    }
    if (g_real_fopen) return g_real_fopen(pathname, mode);
    if (g_real_fopen64) return g_real_fopen64(pathname, mode);
    return 0;
}

/* ============================================================================
 * glibc >= 2.32/2.33/2.34/2.36 Runtime Compatibility Shims (webOS 6 / glibc 2.28+)
 * ============================================================================ */
EXPORT char __libc_single_threaded = 0;

struct compat_main_fini_state {
    void (*fini_fn)(void);
    uint32_t *fini_array;
    uint32_t fini_arraysz;
};

static struct compat_main_fini_state g_main_fini = {0, 0, 0};

struct compat_main_init_scan {
    int found;
    uint32_t dlpi_addr;
    uint32_t min_vaddr;
    uint32_t max_vaddr;
    const compat_elf32_dyn_t *dyn;
};

static int find_main_exe_cb(compat_dl_phdr_info_t *info, unsigned int size, void *data) {
    (void)size;
    struct compat_main_init_scan *out = (struct compat_main_init_scan *)data;
    if (info->dlpi_name && info->dlpi_name[0] != '\\0') {
        return 0;
    }
    const compat_elf32_phdr_t *phdr = (const compat_elf32_phdr_t *)info->dlpi_phdr;
    uint32_t min_v = 0xffffffffU;
    uint32_t max_v = 0U;
    const compat_elf32_dyn_t *dyn = 0;
    for (uint16_t i = 0; i < info->dlpi_phnum; ++i) {
        if (phdr[i].p_type == 1U) { /* PT_LOAD */
            if (phdr[i].p_vaddr < min_v) min_v = phdr[i].p_vaddr;
            if (phdr[i].p_vaddr + phdr[i].p_memsz > max_v) {
                max_v = phdr[i].p_vaddr + phdr[i].p_memsz;
            }
        } else if (phdr[i].p_type == 2U) { /* PT_DYNAMIC */
            dyn = (const compat_elf32_dyn_t *)(info->dlpi_addr + phdr[i].p_vaddr);
        }
    }
    if (dyn) {
        out->found = 1;
        out->dlpi_addr = info->dlpi_addr;
        out->min_vaddr = (min_v == 0xffffffffU) ? 0U : min_v;
        out->max_vaddr = max_v;
        out->dyn = dyn;
        return 1;
    }
    return 0;
}

static uint32_t resolve_dyn_ptr(const struct compat_main_init_scan *scan, uint32_t val) {
    if (!val) return 0;
    if (scan->dlpi_addr != 0 && val >= scan->min_vaddr && val < scan->max_vaddr && val < scan->dlpi_addr + scan->min_vaddr) {
        return scan->dlpi_addr + val;
    }
    return val;
}

static void compat_exe_fini(void) {
    static int ran_fini = 0;
    if (ran_fini) return;
    ran_fini = 1;
    if (g_main_fini.fini_array && g_main_fini.fini_arraysz >= 4U) {
        uint32_t count = g_main_fini.fini_arraysz / 4U;
        for (uint32_t i = count; i > 0; --i) {
            uint32_t entry = g_main_fini.fini_array[i - 1U];
            if (entry != 0U && entry != 0xffffffffU) {
                ((void (*)(void))entry)();
            }
        }
    }
    if (g_main_fini.fini_fn) {
        g_main_fini.fini_fn();
    }
}

static void compat_exe_init(int argc, char **argv, char **envp) {
    static int ran_init = 0;
    if (ran_init) return;
    ran_init = 1;

    struct compat_main_init_scan scan;
    scan.found = 0;
    scan.dlpi_addr = 0;
    scan.min_vaddr = 0;
    scan.max_vaddr = 0;
    scan.dyn = 0;
    dl_iterate_phdr(find_main_exe_cb, &scan);
    if (!scan.found || !scan.dyn) return;

    uint32_t init_ptr = 0;
    uint32_t fini_ptr = 0;
    uint32_t init_arr_ptr = 0;
    uint32_t fini_arr_ptr = 0;
    uint32_t init_arr_sz = 0;
    uint32_t fini_arr_sz = 0;

    for (const compat_elf32_dyn_t *d = scan.dyn; d->d_tag != 0; ++d) {
        switch (d->d_tag) {
            case 12: init_ptr = resolve_dyn_ptr(&scan, d->d_val); break;      /* DT_INIT */
            case 13: fini_ptr = resolve_dyn_ptr(&scan, d->d_val); break;      /* DT_FINI */
            case 25: init_arr_ptr = resolve_dyn_ptr(&scan, d->d_val); break;  /* DT_INIT_ARRAY */
            case 26: fini_arr_ptr = resolve_dyn_ptr(&scan, d->d_val); break;  /* DT_FINI_ARRAY */
            case 27: init_arr_sz = d->d_val; break;                           /* DT_INIT_ARRAYSZ */
            case 28: fini_arr_sz = d->d_val; break;                           /* DT_FINI_ARRAYSZ */
            default: break;
        }
    }

    g_main_fini.fini_fn = (void (*)(void))fini_ptr;
    g_main_fini.fini_array = (uint32_t *)fini_arr_ptr;
    g_main_fini.fini_arraysz = fini_arr_sz;

    if (init_ptr) {
        ((void (*)(void))init_ptr)();
    }
    if (init_arr_ptr && init_arr_sz >= 4U) {
        uint32_t *arr = (uint32_t *)init_arr_ptr;
        uint32_t count = init_arr_sz / 4U;
        for (uint32_t i = 0; i < count; ++i) {
            uint32_t entry = arr[i];
            if (entry != 0U && entry != 0xffffffffU) {
                ((void (*)(int, char **, char **))entry)(argc, argv, envp);
            }
        }
    }
}

static char g_patched_argv_buf[8192];

static void patch_missing_appdesc_folder_path(int argc, char **ubp_av) {
    if (!ubp_av || argc <= 1 || !g_exe_dir[0]) return;
    unsigned int exe_len = c_strlen(g_exe_dir);
    for (int i = 1; i < argc; ++i) {
        const char *arg = ubp_av[i];
        if (!arg || arg[0] != '{') continue;
        const char *ad = c_strstr(arg, "\\"appDesc\\"");
        if (!ad) continue;
        if (c_strstr(arg, "\\"folderPath\\"")) continue;

        const char *p = ad + 9;
        while (*p == ' ' || *p == '\\t' || *p == '\\n' || *p == '\\r') ++p;
        if (*p != ':') continue;
        ++p;
        while (*p == ' ' || *p == '\\t' || *p == '\\n' || *p == '\\r') ++p;

        unsigned int arg_len = c_strlen(arg);
        if (*p == '{') {
            const char *insert_at = p + 1;
            const char *q = insert_at;
            while (*q == ' ' || *q == '\\t' || *q == '\\n' || *q == '\\r') ++q;
            int need_comma = (*q != '}');
            const char *prefix = "\\"folderPath\\":\\"";
            const char *suffix = need_comma ? "\\"," : "\\"";
            unsigned int add_len = c_strlen(prefix) + exe_len + c_strlen(suffix);
            if (arg_len + add_len + 1U <= sizeof(g_patched_argv_buf)) {
                unsigned int head = (unsigned int)(insert_at - arg);
                c_memcpy(g_patched_argv_buf, arg, head);
                unsigned int pos = head;
                c_memcpy(g_patched_argv_buf + pos, prefix, c_strlen(prefix)); pos += c_strlen(prefix);
                c_memcpy(g_patched_argv_buf + pos, g_exe_dir, exe_len); pos += exe_len;
                c_memcpy(g_patched_argv_buf + pos, suffix, c_strlen(suffix)); pos += c_strlen(suffix);
                c_memcpy(g_patched_argv_buf + pos, insert_at, arg_len - head + 1U);
                ubp_av[i] = g_patched_argv_buf;
                log_text(PMLOG_LEVEL_INFO, "injected missing folderPath into argv appDesc object");
            }
            break;
        } else if (*p == '"' && p[1] == '{') {
            const char *insert_at = p + 2;
            int need_comma = (*insert_at != '}');
            const char *prefix = "\\\\\\"folderPath\\\\\\":\\\\\\"";
            const char *suffix = need_comma ? "\\\\\\"," : "\\\\\\"";
            unsigned int add_len = c_strlen(prefix) + exe_len + c_strlen(suffix);
            if (arg_len + add_len + 1U <= sizeof(g_patched_argv_buf)) {
                unsigned int head = (unsigned int)(insert_at - arg);
                c_memcpy(g_patched_argv_buf, arg, head);
                unsigned int pos = head;
                c_memcpy(g_patched_argv_buf + pos, prefix, c_strlen(prefix)); pos += c_strlen(prefix);
                c_memcpy(g_patched_argv_buf + pos, g_exe_dir, exe_len); pos += exe_len;
                c_memcpy(g_patched_argv_buf + pos, suffix, c_strlen(suffix)); pos += c_strlen(suffix);
                c_memcpy(g_patched_argv_buf + pos, insert_at, arg_len - head + 1U);
                ubp_av[i] = g_patched_argv_buf;
                log_text(PMLOG_LEVEL_INFO, "injected missing folderPath into stringified appDesc");
            }
            break;
        }
    }
}

static void log_launch_diag(int argc, char **ubp_av) {
    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "__libc_start_main argc=");
    lbuf_i32(&b, argc);
    lbuf_str(&b, " exe_dir=");
    lbuf_str_trunc(&b, g_exe_dir, 140);
    lbuf_str(&b, " appdata=");
    lbuf_str_trunc(&b, g_appdata_dir, 140);
    log_raw_line(PMLOG_LEVEL_INFO, &b, 1);

    int max_a = argc < 4 ? argc : 4;
    for (int i = 0; i < max_a; ++i) {
        lbuf_init(&b);
        lbuf_str(&b, "  argv[");
        lbuf_i32(&b, i);
        lbuf_str(&b, "]=");
        lbuf_str_trunc(&b, (ubp_av && ubp_av[i]) ? ubp_av[i] : "(null)", 520);
        log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
    }

    const char *env_names[4] = {"APP_ID", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY", "LD_LIBRARY_PATH"};
    lbuf_init(&b);
    lbuf_str(&b, "  env:");
    for (int i = 0; i < 4; ++i) {
        const char *v = g_real_getenv ? g_real_getenv(env_names[i]) : 0;
        lbuf_str(&b, " ");
        lbuf_str(&b, env_names[i]);
        lbuf_str(&b, "=");
        lbuf_str_trunc(&b, v ? v : "<unset>", 96);
    }
    log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
}

EXPORT int __libc_start_main(
    int (*main_fn)(int, char **, char **),
    int argc,
    char **ubp_av,
    void (*init)(int, char **, char **),
    void (*fini)(void),
    void (*rtld_fini)(void),
    void *stack_end
) {
    typedef int (*lsm_fn_t)(
        int (*)(int, char **, char **),
        int, char **,
        void (*)(int, char **, char **),
        void (*)(void), void (*)(void), void *
    );

    ensure_compat_init();
    if (g_real_getpid) g_main_pid = g_real_getpid();
    log_launch_diag(argc, ubp_av);
    patch_missing_appdesc_folder_path(argc, ubp_av);

    lsm_fn_t real_234 = (lsm_fn_t)dlvsym(RTLD_NEXT, "__libc_start_main", "GLIBC_2.34");
    if (real_234) {
        return real_234(main_fn, argc, ubp_av, init, fini, rtld_fini, stack_end);
    }

    lsm_fn_t real_204 = (lsm_fn_t)dlvsym(RTLD_NEXT, "__libc_start_main", "GLIBC_2.4");
    if (!real_204) {
        void *fallback = dlsym(RTLD_NEXT, "__libc_start_main");
        if (fallback && fallback != (void *)__libc_start_main) {
            real_204 = (lsm_fn_t)fallback;
        }
    }
    if (!real_204) {
        log_text(PMLOG_LEVEL_ERROR, "__libc_start_main real_204 resolve FAILED");
        return 127;
    }
    return real_204(
        main_fn,
        argc,
        ubp_av,
        init ? init : compat_exe_init,
        fini ? fini : compat_exe_fini,
        rtld_fini,
        stack_end
    );
}

EXPORT int stat64(const char *path, void *buf) {
    typedef int (*stat64_fn_t)(const char *, void *);
    typedef int (*xstat64_fn_t)(int, const char *, void *);
    stat64_fn_t real_fn = (stat64_fn_t)dlsym(RTLD_NEXT, "stat64");
    if (real_fn && real_fn != stat64) return real_fn(path, buf);
    xstat64_fn_t xfn = (xstat64_fn_t)resolve_libc_sym("__xstat64");
    if (xfn) return xfn(_STAT_VER_LINUX, path, buf);
    return -1;
}

EXPORT int fstat64(int fd, void *buf) {
    typedef int (*fstat64_fn_t)(int, void *);
    typedef int (*fxstat64_fn_t)(int, int, void *);
    fstat64_fn_t real_fn = (fstat64_fn_t)dlsym(RTLD_NEXT, "fstat64");
    if (real_fn && real_fn != fstat64) return real_fn(fd, buf);
    fxstat64_fn_t xfn = (fxstat64_fn_t)resolve_libc_sym("__fxstat64");
    if (xfn) return xfn(_STAT_VER_LINUX, fd, buf);
    return -1;
}

EXPORT int lstat64(const char *path, void *buf) {
    typedef int (*lstat64_fn_t)(const char *, void *);
    typedef int (*lxstat64_fn_t)(int, const char *, void *);
    lstat64_fn_t real_fn = (lstat64_fn_t)dlsym(RTLD_NEXT, "lstat64");
    if (real_fn && real_fn != lstat64) return real_fn(path, buf);
    lxstat64_fn_t xfn = (lxstat64_fn_t)resolve_libc_sym("__lxstat64");
    if (xfn) return xfn(_STAT_VER_LINUX, path, buf);
    return -1;
}

EXPORT int fstatat64(int dirfd, const char *path, void *buf, int flags) {
    typedef int (*fstatat64_fn_t)(int, const char *, void *, int);
    typedef int (*fxstatat64_fn_t)(int, int, const char *, void *, int);
    fstatat64_fn_t real_fn = (fstatat64_fn_t)dlsym(RTLD_NEXT, "fstatat64");
    if (real_fn && real_fn != fstatat64) return real_fn(dirfd, path, buf, flags);
    fxstatat64_fn_t xfn = (fxstatat64_fn_t)resolve_libc_sym("__fxstatat64");
    if (xfn) return xfn(_STAT_VER_LINUX, dirfd, path, buf, flags);
    return -1;
}

EXPORT int pthread_cond_clockwait(void *cond, void *mutex, int clock_id, const struct compat_timespec *abstime) {
    typedef int (*clockwait_fn_t)(void *, void *, int, const struct compat_timespec *);
    clockwait_fn_t real_fn = (clockwait_fn_t)resolve_pthread_sym("pthread_cond_clockwait");
    if (real_fn && real_fn != pthread_cond_clockwait) {
        return real_fn(cond, mutex, clock_id, abstime);
    }

    if (!abstime || abstime->tv_nsec < 0 || abstime->tv_nsec >= 1000000000L) {
        return EINVAL;
    }
    if (clock_id != CLOCK_REALTIME && clock_id != CLOCK_MONOTONIC) {
        return EINVAL;
    }

    /* pthread_cond_t::__data.__wrefs sits at byte offset 0x24 (word index 9); bit 0x2 = CLOCK_MONOTONIC */
    unsigned int wrefs = ((const unsigned int *)cond)[9];
    int cond_clock = (wrefs & 2U) ? CLOCK_MONOTONIC : CLOCK_REALTIME;
    if (clock_id == cond_clock) {
        return pthread_cond_timedwait(cond, mutex, abstime);
    }

    struct compat_timespec now_req;
    struct compat_timespec now_cond;
    if (clock_gettime(clock_id, &now_req) != 0 || clock_gettime(cond_clock, &now_cond) != 0) {
        return EINVAL;
    }

    struct compat_timespec target;
    if (abstime->tv_sec < now_req.tv_sec ||
        (abstime->tv_sec == now_req.tv_sec && abstime->tv_nsec <= now_req.tv_nsec)) {
        target.tv_sec = 0;
        target.tv_nsec = 0;
    } else {
        long sec_diff = abstime->tv_sec - now_req.tv_sec;
        long nsec_diff = abstime->tv_nsec - now_req.tv_nsec;
        if (nsec_diff < 0) {
            sec_diff -= 1;
            nsec_diff += 1000000000L;
        }
        if (sec_diff > 0x7fffffffL - now_cond.tv_sec) {
            target.tv_sec = 0x7fffffffL;
            target.tv_nsec = 999999999L;
        } else {
            target.tv_sec = now_cond.tv_sec + sec_diff;
            target.tv_nsec = now_cond.tv_nsec + nsec_diff;
            if (target.tv_nsec >= 1000000000L) {
                target.tv_nsec -= 1000000000L;
                if (target.tv_sec < 0x7fffffffL) {
                    target.tv_sec += 1;
                } else {
                    target.tv_nsec = 999999999L;
                }
            }
        }
    }
    return pthread_cond_timedwait(cond, mutex, &target);
}

EXPORT uint32_t arc4random(void) {
    typedef uint32_t (*arc4_fn_t)(void);
    typedef int (*getentropy_fn_t)(void *, unsigned int);
    arc4_fn_t real_fn = (arc4_fn_t)dlsym(RTLD_NEXT, "arc4random");
    if (real_fn && real_fn != arc4random) {
        return real_fn();
    }
    uint32_t val = 0;
    getentropy_fn_t ge_fn = (getentropy_fn_t)resolve_libc_sym("getentropy");
    if (ge_fn && ge_fn(&val, sizeof(val)) == 0) {
        return val;
    }
    int fd = open("/dev/urandom", 0);
    if (fd >= 0) {
        int n = read(fd, &val, sizeof(val));
        close(fd);
        if (n == (int)sizeof(val)) return val;
    }
    return val;
}

/* ============================================================================
 * Writable FLUTTER_* & XDG_* Redirector for webOS (prisoner user)
 * ============================================================================ */
static void make_dir_writable(const char *p) {
    mkdir(p, 0777);
    chmod(p, 0777);
}

static void join_path(char *dst, unsigned int dst_sz, const char *base, const char *sub) {
    unsigned int b_len = c_strlen(base);
    if (b_len + 1U >= dst_sz) {
        copy_str(dst, base, dst_sz);
        return;
    }
    c_memcpy(dst, base, b_len);
    if (sub && sub[0]) {
        if (b_len > 0 && dst[b_len - 1] != '/') {
            dst[b_len++] = '/';
        }
        copy_str(dst + b_len, sub, dst_sz - b_len);
    } else {
        dst[b_len] = '\\0';
    }
}

static void populate_exe_dir(void) {
    if (g_exe_dir[0]) return;
    fn_readlink_t fn_rl = g_real_readlink ? g_real_readlink : readlink;
    char exe_buf[512];
    int n = fn_rl("/proc/self/exe", exe_buf, sizeof(exe_buf) - 1);
    if (n > 0) {
        exe_buf[n] = '\\0';
        int last_slash = -1;
        for (int i = 0; i < n; ++i) {
            if (exe_buf[i] == '/') last_slash = i;
        }
        if (last_slash > 0) {
            exe_buf[last_slash] = '\\0';
            copy_str(g_exe_dir, exe_buf, sizeof(g_exe_dir));
        }
    }
}

static int probe_writable_dir(const char *cand) {
    fn_open_t fn_open = g_real_open ? g_real_open : open;
    fn_write_t fn_write = g_real_write ? g_real_write : write;
    fn_close_t fn_close = g_real_close ? g_real_close : close;
    if (!cand || !cand[0]) return 0;

    make_dir_writable(cand);
    char log_sub[512], probe_path[512];
    join_path(log_sub, sizeof(log_sub), cand, "log");
    make_dir_writable(log_sub);
    join_path(probe_path, sizeof(probe_path), log_sub, ".probe");

    int fd = fn_open(probe_path, COMPAT_O_CREAT | COMPAT_O_WRONLY | COMPAT_O_TRUNC | COMPAT_O_CLOEXEC, 0666);
    if (fd < 0) return 0;
    int nw = fn_write(fd, "1", 1);
    fn_close(fd);
    unlink(probe_path);
    if (nw != 1) return 0;

    char sub[512];
    const char *subdirs[7] = {
        COMPAT32_APP_ID,
        ".cache", ".cache/" COMPAT32_APP_ID,
        ".data", ".data/" COMPAT32_APP_ID,
        ".download", ".download/" COMPAT32_APP_ID
    };
    for (int i = 0; i < 7; ++i) {
        join_path(sub, sizeof(sub), cand, subdirs[i]);
        make_dir_writable(sub);
    }

    copy_str(g_appdata_dir, cand, sizeof(g_appdata_dir));
    join_path(g_cache_dir, sizeof(g_cache_dir), cand, ".cache");
    join_path(g_download_dir, sizeof(g_download_dir), cand, ".download");
    join_path(g_log_dir, sizeof(g_log_dir), cand, "log");
    join_path(g_boot_log_path, sizeof(g_boot_log_path), g_log_dir, "boot.log");
    return 1;
}

static const char *get_writable_appdata_dir(void) {
    static int probed = 0;
    if (probed) return g_appdata_dir;
    probed = 1;

    cache_libc_ptrs();
    populate_exe_dir();
    make_dir_writable("/media/developer/temp");

    if (probe_writable_dir("/media/developer/temp/plezy_appdata")) return g_appdata_dir;
    if (probe_writable_dir("/tmp/plezy_appdata")) return g_appdata_dir;
    if (g_exe_dir[0]) {
        char exe_app[512];
        join_path(exe_app, sizeof(exe_app), g_exe_dir, "appdata");
        if (probe_writable_dir(exe_app)) return g_appdata_dir;
    }
    if (probe_writable_dir("/var/tmp/plezy_appdata")) return g_appdata_dir;
    return g_appdata_dir;
}

static const char *get_writable_cache_dir(void) {
    (void)get_writable_appdata_dir();
    return g_cache_dir;
}

static const char *get_writable_download_dir(void) {
    (void)get_writable_appdata_dir();
    return g_download_dir;
}

static const char *get_writable_log_dir(void) {
    (void)get_writable_appdata_dir();
    return g_log_dir;
}

static const char *map_env_var(const char *name) {
    if (!name) return 0;
    if (strcmp(name, "FLUTTER_HOME") == 0 ||
        strcmp(name, "FLUTTER_APPDATA_HOME") == 0 ||
        strcmp(name, "FLUTTER_EXT_STORAGE_PATH") == 0 ||
        strcmp(name, "XDG_DATA_HOME") == 0 ||
        strcmp(name, "XDG_CONFIG_HOME") == 0) {
        return get_writable_appdata_dir();
    }
    if (strcmp(name, "FLUTTER_TEMP_HOME") == 0 ||
        strcmp(name, "XDG_CACHE_HOME") == 0) {
        return get_writable_cache_dir();
    }
    if (strcmp(name, "FLUTTER_DOWNLOAD_HOME") == 0) {
        return get_writable_download_dir();
    }
    if (strcmp(name, "FLUTTER_APP_LOG_PATH") == 0) {
        return get_writable_log_dir();
    }
    return 0;
}

EXPORT int setenv(const char *name, const char *value, int overwrite) {
    cache_libc_ptrs();
    if (!g_real_setenv) return -1;

    const char *mapped = map_env_var(name);
    if (mapped) {
        return g_real_setenv(name, mapped, 1);
    }
    return g_real_setenv(name, value, overwrite);
}

EXPORT char *getenv(const char *name) {
    cache_libc_ptrs();
    if (name) {
        const char *mapped = map_env_var(name);
        if (mapped) {
            return (char *)mapped;
        }
        if (strcmp(name, "APP_ID") == 0 || strcmp(name, "FLUTTER_APP_ID") == 0) {
            char *val = g_real_getenv ? g_real_getenv(name) : 0;
            if (!val || !val[0]) return COMPAT32_APP_ID;
            return val;
        }
    }
    return g_real_getenv ? g_real_getenv(name) : 0;
}

static void ensure_compat_init(void) {
    static int init_done = 0;
    if (init_done) return;
    init_done = 1;

    cache_libc_ptrs();
    if (g_real_getpid && g_main_pid < 0) g_main_pid = g_real_getpid();
    populate_exe_dir();
    const char *dir = get_writable_appdata_dir();
    const char *cache_dir = get_writable_cache_dir();
    const char *dl_dir = get_writable_download_dir();
    const char *log_dir = get_writable_log_dir();

    init_pmlog();
    install_crash_handlers();

    if (g_real_setenv && dir) {
        g_real_setenv("APP_ID", COMPAT32_APP_ID, 0);
        g_real_setenv("FLUTTER_APP_ID", COMPAT32_APP_ID, 0);
        g_real_setenv("FLUTTER_HOME", dir, 1);
        g_real_setenv("FLUTTER_APPDATA_HOME", dir, 1);
        g_real_setenv("FLUTTER_TEMP_HOME", cache_dir, 1);
        g_real_setenv("FLUTTER_DOWNLOAD_HOME", dl_dir, 1);
        g_real_setenv("FLUTTER_EXT_STORAGE_PATH", dir, 1);
        g_real_setenv("FLUTTER_APP_LOG_PATH", log_dir, 1);
        g_real_setenv("XDG_DATA_HOME", dir, 1);
        g_real_setenv("XDG_CONFIG_HOME", dir, 1);
        g_real_setenv("XDG_CACHE_HOME", cache_dir, 1);
    }

    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "=== compat32 ctor init pid=");
    lbuf_i32(&b, g_real_getpid ? g_real_getpid() : 0);
    lbuf_str(&b, " uid=");
    lbuf_u32(&b, g_real_getuid ? g_real_getuid() : 0U);
    lbuf_str(&b, " exe_dir=");
    lbuf_str_trunc(&b, g_exe_dir, 140);
    lbuf_str(&b, " appdata=");
    lbuf_str_trunc(&b, g_appdata_dir, 140);
    lbuf_str(&b, " ===");
    log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
}

__attribute__((constructor))
static void init_webos_compat32(void) {
    ensure_compat_init();
}

/* ============================================================================
 * Wayland Protocol Version Clamp (wl_webos_* v2 -> v1) & wl_proxy_marshal_flags Fallback (webOS 6-23)
 * ============================================================================ */
struct wl_interface {
    const char *name;
    int version;
};

static void *resolve_wl_sym(const char *name) {
    static void *wl_handle = 0;
    void *fn = dlsym(RTLD_NEXT, name);
    if (fn) return fn;
    if (!wl_handle) {
        wl_handle = dlopen("libwayland-client.so.0", RTLD_LAZY);
        if (!wl_handle) wl_handle = dlopen("/usr/lib/libwayland-client.so.0", RTLD_LAZY);
    }
    if (wl_handle) {
        fn = dlsym(wl_handle, name);
    }
    return fn;
}

static uint32_t clamp_webos_wayland_version(const struct wl_interface *interface, uint32_t version) {
    if (interface && interface->name) {
        if (strncmp(interface->name, "wl_webos_", 9) == 0 && version > 1) {
            return 1;
        }
    }
    return version;
}

static int is_wl_registry_proxy(void *proxy) {
    typedef const char *(*get_class_fn_t)(void *);
    if (!proxy) return 0;
    get_class_fn_t get_cls = (get_class_fn_t)resolve_wl_sym("wl_proxy_get_class");
    if (!get_cls) return 0;
    const char *cls = get_cls(proxy);
    return cls && strcmp(cls, "wl_registry") == 0;
}

EXPORT void *wl_proxy_marshal_constructor_versioned(
    void *proxy,
    uint32_t opcode,
    const struct wl_interface *interface,
    uint32_t version,
    ...
) {
    typedef void *(*fn_var_t)(void *, uint32_t, const struct wl_interface *, uint32_t, ...);
    uint32_t safe_ver = clamp_webos_wayland_version(interface, version);

    va_list ap;
    va_start(ap, version);
    uint32_t a0  = va_arg(ap, uint32_t);
    uint32_t a1  = va_arg(ap, uint32_t);
    uint32_t a2  = va_arg(ap, uint32_t);
    uint32_t a3  = va_arg(ap, uint32_t);
    uint32_t a4  = va_arg(ap, uint32_t);
    uint32_t a5  = va_arg(ap, uint32_t);
    uint32_t a6  = va_arg(ap, uint32_t);
    uint32_t a7  = va_arg(ap, uint32_t);
    uint32_t a8  = va_arg(ap, uint32_t);
    uint32_t a9  = va_arg(ap, uint32_t);
    uint32_t a10 = va_arg(ap, uint32_t);
    uint32_t a11 = va_arg(ap, uint32_t);
    uint32_t a12 = va_arg(ap, uint32_t);
    uint32_t a13 = va_arg(ap, uint32_t);
    uint32_t a14 = va_arg(ap, uint32_t);
    uint32_t a15 = va_arg(ap, uint32_t);
    uint32_t a16 = va_arg(ap, uint32_t);
    uint32_t a17 = va_arg(ap, uint32_t);
    uint32_t a18 = va_arg(ap, uint32_t);
    uint32_t a19 = va_arg(ap, uint32_t);
    va_end(ap);

    if (opcode == 0 && safe_ver != version && is_wl_registry_proxy(proxy)) {
        a2 = safe_ver;
    }

    fn_var_t real_fn = (fn_var_t)resolve_wl_sym("wl_proxy_marshal_constructor_versioned");
    if (real_fn && real_fn != wl_proxy_marshal_constructor_versioned) {
        return real_fn(
            proxy, opcode, interface, safe_ver,
            a0, a1, a2, a3, a4, a5, a6, a7, a8, a9,
            a10, a11, a12, a13, a14, a15, a16, a17, a18, a19
        );
    }
    return 0;
}

EXPORT void *wl_proxy_marshal_flags(
    void *proxy,
    uint32_t opcode,
    const struct wl_interface *interface,
    uint32_t version,
    uint32_t flags,
    ...
) {
    typedef void *(*fn_flags_t)(void *, uint32_t, const struct wl_interface *, uint32_t, uint32_t, ...);
    typedef void *(*fn_mcv_t)(void *, uint32_t, const struct wl_interface *, uint32_t, ...);
    typedef void (*fn_marshal_t)(void *, uint32_t, ...);
    typedef void (*fn_destroy_t)(void *);

    uint32_t safe_ver = clamp_webos_wayland_version(interface, version);

    va_list ap;
    va_start(ap, flags);
    uint32_t a0  = va_arg(ap, uint32_t);
    uint32_t a1  = va_arg(ap, uint32_t);
    uint32_t a2  = va_arg(ap, uint32_t);
    uint32_t a3  = va_arg(ap, uint32_t);
    uint32_t a4  = va_arg(ap, uint32_t);
    uint32_t a5  = va_arg(ap, uint32_t);
    uint32_t a6  = va_arg(ap, uint32_t);
    uint32_t a7  = va_arg(ap, uint32_t);
    uint32_t a8  = va_arg(ap, uint32_t);
    uint32_t a9  = va_arg(ap, uint32_t);
    uint32_t a10 = va_arg(ap, uint32_t);
    uint32_t a11 = va_arg(ap, uint32_t);
    uint32_t a12 = va_arg(ap, uint32_t);
    uint32_t a13 = va_arg(ap, uint32_t);
    uint32_t a14 = va_arg(ap, uint32_t);
    uint32_t a15 = va_arg(ap, uint32_t);
    uint32_t a16 = va_arg(ap, uint32_t);
    uint32_t a17 = va_arg(ap, uint32_t);
    uint32_t a18 = va_arg(ap, uint32_t);
    uint32_t a19 = va_arg(ap, uint32_t);
    va_end(ap);

    if (opcode == 0 && safe_ver != version && is_wl_registry_proxy(proxy)) {
        a2 = safe_ver;
    }

    fn_flags_t real_fn = (fn_flags_t)resolve_wl_sym("wl_proxy_marshal_flags");
    if (real_fn && real_fn != wl_proxy_marshal_flags) {
        return real_fn(
            proxy, opcode, interface, safe_ver, flags,
            a0, a1, a2, a3, a4, a5, a6, a7, a8, a9,
            a10, a11, a12, a13, a14, a15, a16, a17, a18, a19
        );
    }

    void *res = 0;
    if (interface) {
        fn_mcv_t mcv_fn = (fn_mcv_t)resolve_wl_sym("wl_proxy_marshal_constructor_versioned");
        if (mcv_fn && mcv_fn != wl_proxy_marshal_constructor_versioned) {
            res = mcv_fn(
                proxy, opcode, interface, safe_ver,
                a0, a1, a2, a3, a4, a5, a6, a7, a8, a9,
                a10, a11, a12, a13, a14, a15, a16, a17, a18, a19
            );
        }
    } else {
        fn_marshal_t marshal_fn = (fn_marshal_t)resolve_wl_sym("wl_proxy_marshal");
        if (marshal_fn) {
            marshal_fn(
                proxy, opcode,
                a0, a1, a2, a3, a4, a5, a6, a7, a8, a9,
                a10, a11, a12, a13, a14, a15, a16, a17, a18, a19
            );
        }
    }

    if ((flags & WL_MARSHAL_FLAG_DESTROY) && proxy) {
        fn_destroy_t destroy_fn = (fn_destroy_t)resolve_wl_sym("wl_proxy_destroy");
        if (destroy_fn) destroy_fn(proxy);
    }
    return res;
}

EXPORT void *wl_display_connect(const char *name) {
    typedef void *(*fn_wl_conn_t)(const char *);
    static int logged_ok = 0;
    ensure_compat_init();

    fn_wl_conn_t real_fn = (fn_wl_conn_t)resolve_wl_sym("wl_display_connect");
    if (!real_fn || real_fn == wl_display_connect) {
        log_text(PMLOG_LEVEL_ERROR, "wl_display_connect resolve FAILED");
        return 0;
    }

    void *dpy = real_fn(name);
    if (dpy) {
        if (!logged_ok) {
            logged_ok = 1;
            struct log_buf b;
            lbuf_init(&b);
            lbuf_str(&b, "wl_display_connect ok name=");
            lbuf_str_trunc(&b, name ? name : "(null)", 80);
            lbuf_str(&b, " XDG_RUNTIME_DIR=");
            const char *xdg = g_real_getenv ? g_real_getenv("XDG_RUNTIME_DIR") : 0;
            lbuf_str_trunc(&b, xdg ? xdg : "<unset>", 96);
            lbuf_str(&b, " WAYLAND_DISPLAY=");
            const char *wd = g_real_getenv ? g_real_getenv("WAYLAND_DISPLAY") : 0;
            lbuf_str_trunc(&b, wd ? wd : "<unset>", 64);
            log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
        }
        return dpy;
    }

    const char *cur_xdg = g_real_getenv ? g_real_getenv("XDG_RUNTIME_DIR") : 0;
    const char *cur_wd  = g_real_getenv ? g_real_getenv("WAYLAND_DISPLAY") : 0;
    char orig_xdg[256], orig_wd[128];
    copy_str(orig_xdg, cur_xdg ? cur_xdg : "", sizeof(orig_xdg));
    copy_str(orig_wd, cur_wd ? cur_wd : "", sizeof(orig_wd));

    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "wl_display_connect FAILED name=");
    lbuf_str_trunc(&b, name ? name : "(null)", 80);
    lbuf_str(&b, " XDG_RUNTIME_DIR=");
    lbuf_str_trunc(&b, orig_xdg[0] ? orig_xdg : "<unset>", 96);
    lbuf_str(&b, " WAYLAND_DISPLAY=");
    lbuf_str_trunc(&b, orig_wd[0] ? orig_wd : "<unset>", 64);
    log_raw_line(PMLOG_LEVEL_ERROR, &b, 1);

    const char *cand_dirs[6] = {
        orig_xdg[0] ? orig_xdg : 0,
        "/tmp/xdg",
        "/run/user/0",
        "/run",
        "/var/run",
        "/tmp"
    };
    const char *cand_socks[3] = {
        (name && name[0]) ? name : (orig_wd[0] ? orig_wd : 0),
        "wayland-0",
        "wayland-1"
    };

    for (int di = 0; di < 6; ++di) {
        const char *dir = cand_dirs[di];
        if (!dir || !dir[0]) continue;
        for (int si = 0; si < 3; ++si) {
            const char *sock = cand_socks[si];
            if (!sock || !sock[0] || sock[0] == '/') continue;
            char full[384];
            join_path(full, sizeof(full), dir, sock);
            if (access(full, 0) != 0) continue;

            if (g_real_setenv) {
                g_real_setenv("XDG_RUNTIME_DIR", dir, 1);
                if (!name) g_real_setenv("WAYLAND_DISPLAY", sock, 1);
            }
            if (!name || name[0] != '/') {
                dpy = real_fn(name);
            }
            if (!dpy) {
                dpy = real_fn(full);
            }
            if (dpy) {
                lbuf_init(&b);
                lbuf_str(&b, "wl_display_connect RECOVERED socket=");
                lbuf_str_trunc(&b, full, 160);
                log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
                return dpy;
            }
        }
    }

    if (g_real_setenv && orig_xdg[0]) g_real_setenv("XDG_RUNTIME_DIR", orig_xdg, 1);
    if (g_real_setenv && orig_wd[0])  g_real_setenv("WAYLAND_DISPLAY", orig_wd, 1);
    log_text(PMLOG_LEVEL_ERROR, "wl_display_connect ALL FALLBACK PROBES FAILED");
    return 0;
}

/* ============================================================================
 * Wayland Seat / Pointer Diagnostics Interceptor
 * ============================================================================ */
struct compat_wl_seat_listener_t {
    void (*capabilities)(void *data, void *seat, uint32_t caps);
    void (*name)(void *data, void *seat, const char *name);
};

struct compat_seat_slot {
    void *seat;
    void (*orig_caps)(void *data, void *seat, uint32_t caps);
    void (*orig_name)(void *data, void *seat, const char *name);
};

#define COMPAT_MAX_SEATS 8
static struct compat_seat_slot g_compat_seats[COMPAT_MAX_SEATS];
static uint32_t g_seat_event_logs = 0;
static uint32_t g_ptr_listener_logs = 0;

static void compat_wl_seat_capabilities(void *data, void *seat, uint32_t caps) {
    if (__atomic_fetch_add(&g_seat_event_logs, 1U, __ATOMIC_RELAXED) < 24U) {
        struct log_buf b;
        lbuf_init(&b);
        lbuf_str(&b, "wl_seat.capabilities seat=");
        lbuf_hex32(&b, (uint32_t)(uintptr_t)seat);
        lbuf_str(&b, " caps=");
        lbuf_hex32(&b, caps);
        if (caps & 1U) lbuf_str(&b, " POINTER");
        if (caps & 2U) lbuf_str(&b, " KEYBOARD");
        if (caps & 4U) lbuf_str(&b, " TOUCH");
        log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
    }
    for (unsigned int i = 0; i < COMPAT_MAX_SEATS; ++i) {
        if (g_compat_seats[i].seat == seat && g_compat_seats[i].orig_caps) {
            g_compat_seats[i].orig_caps(data, seat, caps);
            return;
        }
    }
}

static void compat_wl_seat_name(void *data, void *seat, const char *name) {
    if (__atomic_fetch_add(&g_seat_event_logs, 1U, __ATOMIC_RELAXED) < 24U) {
        struct log_buf b;
        lbuf_init(&b);
        lbuf_str(&b, "wl_seat.name seat=");
        lbuf_hex32(&b, (uint32_t)(uintptr_t)seat);
        lbuf_str(&b, " name=");
        lbuf_str_trunc(&b, name ? name : "(null)", 64);
        log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
    }
    for (unsigned int i = 0; i < COMPAT_MAX_SEATS; ++i) {
        if (g_compat_seats[i].seat == seat && g_compat_seats[i].orig_name) {
            g_compat_seats[i].orig_name(data, seat, name);
            return;
        }
    }
}

static const struct compat_wl_seat_listener_t g_compat_seat_listener_impl = {
    compat_wl_seat_capabilities,
    compat_wl_seat_name,
};

EXPORT int wl_proxy_add_listener(void *proxy, void (**implementation)(void), void *data) {
    typedef int (*fn_t)(void *, void (**)(void), void *);
    typedef const char *(*get_class_fn_t)(void *);

    fn_t real_fn = (fn_t)resolve_wl_sym("wl_proxy_add_listener");
    if (!real_fn || real_fn == wl_proxy_add_listener) {
        return -1;
    }

    get_class_fn_t get_cls = (get_class_fn_t)resolve_wl_sym("wl_proxy_get_class");
    const char *cls = (proxy && get_cls) ? get_cls(proxy) : 0;

    if (cls && strcmp(cls, "wl_seat") == 0 && implementation) {
        const struct compat_wl_seat_listener_t *orig =
            (const struct compat_wl_seat_listener_t *)implementation;
        int slot_idx = -1;
        for (int i = 0; i < COMPAT_MAX_SEATS; ++i) {
            if (g_compat_seats[i].seat == proxy || g_compat_seats[i].seat == 0) {
                slot_idx = i;
                break;
            }
        }
        if (slot_idx >= 0) {
            g_compat_seats[slot_idx].orig_caps = orig->capabilities;
            g_compat_seats[slot_idx].orig_name = orig->name;
            __atomic_store_n(&g_compat_seats[slot_idx].seat, proxy, __ATOMIC_RELEASE);
            return real_fn(proxy, (void (**)(void))&g_compat_seat_listener_impl, data);
        }
    } else if (cls && strcmp(cls, "wl_pointer") == 0) {
        if (__atomic_fetch_add(&g_ptr_listener_logs, 1U, __ATOMIC_RELAXED) < 12U) {
            struct log_buf b;
            lbuf_init(&b);
            lbuf_str(&b, "wl_pointer_add_listener ptr=");
            lbuf_hex32(&b, (uint32_t)(uintptr_t)proxy);
            lbuf_str(&b, " data=");
            lbuf_hex32(&b, (uint32_t)(uintptr_t)data);
            log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
        }
    }

    return real_fn(proxy, implementation, data);
}

/* ============================================================================
 * Wayland-EGL Dynamic Bridge (libwayland-egl.so.1 -> libwayland-egl.so.0 / Mali)
 * ============================================================================ */
#define COMPAT_WL_EGL_CAND_COUNT 10

static void *resolve_wl_egl_sym(const char *name, void *self_fn, const char **out_src) {
    static const char *const cands[COMPAT_WL_EGL_CAND_COUNT] = {
        "libwayland-egl.so.1",
        "/usr/lib/libwayland-egl.so.1",
        "libwayland-egl.so.0",
        "/usr/lib/libwayland-egl.so.0",
        "libwayland-egl.so",
        "/usr/lib/libwayland-egl.so",
        "libEGL.so.1",
        "/usr/lib/libEGL.so.1",
        "libmali.so.0",
        "/usr/lib/libmali.so.0",
    };
    static void *handles[COMPAT_WL_EGL_CAND_COUNT] = {0};
    static volatile int handle_state[COMPAT_WL_EGL_CAND_COUNT] = {0}; /* 0=init, 1=opening, 2=done */

    void *fn = dlsym(RTLD_NEXT, name);
    if (fn && fn != self_fn) {
        if (out_src) *out_src = "RTLD_NEXT";
        return fn;
    }

    for (unsigned int i = 0; i < COMPAT_WL_EGL_CAND_COUNT; ++i) {
        int st = __atomic_load_n(&handle_state[i], __ATOMIC_ACQUIRE);
        if (st == 0) {
            int expected = 0;
            if (__atomic_compare_exchange_n(&handle_state[i], &expected, 1, 0, __ATOMIC_ACQ_REL, __ATOMIC_ACQUIRE)) {
                void *h = dlopen(cands[i], RTLD_LAZY);
                __atomic_store_n(&handles[i], h, __ATOMIC_RELEASE);
                __atomic_store_n(&handle_state[i], 2, __ATOMIC_RELEASE);
            } else {
                while (__atomic_load_n(&handle_state[i], __ATOMIC_ACQUIRE) == 1) {}
            }
        } else {
            while (__atomic_load_n(&handle_state[i], __ATOMIC_ACQUIRE) == 1) {}
        }
        void *h = __atomic_load_n(&handles[i], __ATOMIC_ACQUIRE);
        if (h) {
            fn = dlsym(h, name);
            if (fn && fn != self_fn) {
                if (out_src) *out_src = cands[i];
                return fn;
            }
        }
    }
    if (out_src) *out_src = 0;
    return 0;
}

EXPORT void *wl_egl_window_create(void *surface, int width, int height) {
    typedef void *(*fn_t)(void *, int, int);
    static void *cached_fn = 0;
    static int logged_ok = 0;
    static int logged_fail = 0;
    const char *src = 0;

    fn_t real_fn = (fn_t)__atomic_load_n(&cached_fn, __ATOMIC_ACQUIRE);
    if (!real_fn) {
        real_fn = (fn_t)resolve_wl_egl_sym("wl_egl_window_create", (void *)wl_egl_window_create, &src);
        if (real_fn) {
            __atomic_store_n(&cached_fn, (void *)real_fn, __ATOMIC_RELEASE);
        }
    }
    if (!real_fn) {
        if (!__atomic_exchange_n(&logged_fail, 1, __ATOMIC_ACQ_REL)) {
            log_text(PMLOG_LEVEL_ERROR, "wl_egl_window_create resolve FAILED");
        }
        return 0;
    }

    void *win = real_fn(surface, width, height);
    if (!win) {
        struct log_buf b;
        lbuf_init(&b);
        lbuf_str(&b, "wl_egl_window_create returned NULL src=");
        lbuf_str_trunc(&b, src ? src : "cached", 64);
        lbuf_str(&b, " w=");
        lbuf_i32(&b, width);
        lbuf_str(&b, " h=");
        lbuf_i32(&b, height);
        log_raw_line(PMLOG_LEVEL_ERROR, &b, 1);
    } else if (!__atomic_exchange_n(&logged_ok, 1, __ATOMIC_ACQ_REL)) {
        struct log_buf b;
        lbuf_init(&b);
        lbuf_str(&b, "wl_egl_window_create ok src=");
        lbuf_str_trunc(&b, src ? src : "cached", 64);
        lbuf_str(&b, " w=");
        lbuf_i32(&b, width);
        lbuf_str(&b, " h=");
        lbuf_i32(&b, height);
        log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
    }
    return win;
}

EXPORT void wl_egl_window_destroy(void *egl_window) {
    typedef void (*fn_t)(void *);
    static void *cached_fn = 0;
    static int logged_fail = 0;

    fn_t real_fn = (fn_t)__atomic_load_n(&cached_fn, __ATOMIC_ACQUIRE);
    if (!real_fn) {
        real_fn = (fn_t)resolve_wl_egl_sym("wl_egl_window_destroy", (void *)wl_egl_window_destroy, 0);
        if (real_fn) {
            __atomic_store_n(&cached_fn, (void *)real_fn, __ATOMIC_RELEASE);
        }
    }
    if (!real_fn) {
        if (!__atomic_exchange_n(&logged_fail, 1, __ATOMIC_ACQ_REL)) {
            log_text(PMLOG_LEVEL_ERROR, "wl_egl_window_destroy resolve FAILED");
        }
        return;
    }
    real_fn(egl_window);
}

EXPORT void wl_egl_window_resize(void *egl_window, int width, int height, int dx, int dy) {
    typedef void (*fn_t)(void *, int, int, int, int);
    static void *cached_fn = 0;
    static int logged_fail = 0;

    fn_t real_fn = (fn_t)__atomic_load_n(&cached_fn, __ATOMIC_ACQUIRE);
    if (!real_fn) {
        real_fn = (fn_t)resolve_wl_egl_sym("wl_egl_window_resize", (void *)wl_egl_window_resize, 0);
        if (real_fn) {
            __atomic_store_n(&cached_fn, (void *)real_fn, __ATOMIC_RELEASE);
        }
    }
    if (!real_fn) {
        if (!__atomic_exchange_n(&logged_fail, 1, __ATOMIC_ACQ_REL)) {
            log_text(PMLOG_LEVEL_ERROR, "wl_egl_window_resize resolve FAILED");
        }
        return;
    }
    real_fn(egl_window, width, height, dx, dy);
}

EXPORT void wl_egl_window_get_attached_size(void *egl_window, int *width, int *height) {
    typedef void (*fn_t)(void *, int *, int *);
    static void *cached_fn = 0;
    static int logged_fail = 0;

    fn_t real_fn = (fn_t)__atomic_load_n(&cached_fn, __ATOMIC_ACQUIRE);
    if (!real_fn) {
        real_fn = (fn_t)resolve_wl_egl_sym("wl_egl_window_get_attached_size", (void *)wl_egl_window_get_attached_size, 0);
        if (real_fn) {
            __atomic_store_n(&cached_fn, (void *)real_fn, __ATOMIC_RELEASE);
        }
    }
    if (!real_fn) {
        if (!__atomic_exchange_n(&logged_fail, 1, __ATOMIC_ACQ_REL)) {
            log_text(PMLOG_LEVEL_ERROR, "wl_egl_window_get_attached_size resolve FAILED");
        }
        if (width) *width = 0;
        if (height) *height = 0;
        return;
    }
    real_fn(egl_window, width, height);
}

/* ============================================================================
 * EGL Config/Context/Surface Resilience & Diagnostics (Mali / webOS 6)
 * ============================================================================ */
#define COMPAT_EGL_ALPHA_SIZE            0x3021
#define COMPAT_EGL_BLUE_SIZE             0x3022
#define COMPAT_EGL_GREEN_SIZE            0x3023
#define COMPAT_EGL_RED_SIZE              0x3024
#define COMPAT_EGL_DEPTH_SIZE            0x3025
#define COMPAT_EGL_STENCIL_SIZE          0x3026
#define COMPAT_EGL_SAMPLES               0x3031
#define COMPAT_EGL_SAMPLE_BUFFERS        0x3032
#define COMPAT_EGL_SURFACE_TYPE          0x3033
#define COMPAT_EGL_WINDOW_BIT            0x0004
#define COMPAT_EGL_NONE                  0x3038
#define COMPAT_EGL_RENDERABLE_TYPE       0x3040
#define COMPAT_EGL_OPENGL_ES2_BIT        0x0004
#define COMPAT_EGL_CONTEXT_CLIENT_VERSION 0x3098

static void *resolve_egl_sym(const char *name, void *self_fn) {
    static void *egl_h = 0;
    static void *mali_h = 0;
    void *fn = dlsym(RTLD_NEXT, name);
    if (fn && fn != self_fn) return fn;
    if (!egl_h) {
        egl_h = dlopen("libEGL.so.1", RTLD_LAZY);
        if (!egl_h) egl_h = dlopen("/usr/lib/libEGL.so.1", RTLD_LAZY);
    }
    if (egl_h) {
        fn = dlsym(egl_h, name);
        if (fn && fn != self_fn) return fn;
    }
    if (!mali_h) {
        mali_h = dlopen("libmali.so.0", RTLD_LAZY);
        if (!mali_h) mali_h = dlopen("/usr/lib/libmali.so.0", RTLD_LAZY);
    }
    if (mali_h) {
        fn = dlsym(mali_h, name);
        if (fn && fn != self_fn) return fn;
    }
    return 0;
}

static int32_t compat_egl_get_error(void) {
    typedef int32_t (*fn_err_t)(void);
    fn_err_t fn = (fn_err_t)resolve_egl_sym("eglGetError", 0);
    return fn ? fn() : -1;
}

static void log_egl_attribs(const char *prefix, const int32_t *attrib_list, int32_t egl_err) {
    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, prefix);
    lbuf_str(&b, " eglGetError=");
    lbuf_hex32(&b, (uint32_t)egl_err);
    lbuf_str(&b, " attrs:");
    if (!attrib_list) {
        lbuf_str(&b, " (null)");
    } else {
        for (int i = 0; i < 32; i += 2) {
            int32_t k = attrib_list[i];
            if (k == COMPAT_EGL_NONE) {
                lbuf_str(&b, " NONE");
                break;
            }
            int32_t v = attrib_list[i + 1];
            lbuf_str(&b, " ");
            lbuf_hex32(&b, (uint32_t)k);
            lbuf_str(&b, "=");
            lbuf_i32(&b, v);
        }
    }
    log_raw_line(PMLOG_LEVEL_ERROR, &b, 1);
}

EXPORT unsigned int eglChooseConfig(
    void *dpy,
    const int32_t *attrib_list,
    void **configs,
    int32_t config_size,
    int32_t *num_config
) {
    typedef unsigned int (*fn_cc_t)(void *, const int32_t *, void **, int32_t, int32_t *);
    static int logged_ok = 0;
    fn_cc_t real_fn = (fn_cc_t)resolve_egl_sym("eglChooseConfig", (void *)eglChooseConfig);
    if (!real_fn) {
        log_text(PMLOG_LEVEL_ERROR, "eglChooseConfig resolve FAILED");
        return 0;
    }

    int32_t local_num = 0;
    int32_t *cnt_ptr = num_config ? num_config : &local_num;
    unsigned int ret = real_fn(dpy, attrib_list, configs, config_size, cnt_ptr);
    if (ret == 1U && *cnt_ptr > 0) {
        if (!logged_ok) {
            logged_ok = 1;
            log_text(PMLOG_LEVEL_INFO, "eglChooseConfig strict succeeded");
        }
        return ret;
    }

    log_egl_attribs("eglChooseConfig strict FAILED", attrib_list, compat_egl_get_error());

    /* Pass 1: strip MSAA/depth/stencil and normalize EGL_SURFACE_TYPE -> EGL_WINDOW_BIT */
    if (attrib_list) {
        int32_t relaxed[64];
        int out_i = 0;
        for (int i = 0; i + 1 < 62 && out_i + 3 < 64; i += 2) {
            int32_t k = attrib_list[i];
            if (k == COMPAT_EGL_NONE) break;
            int32_t v = attrib_list[i + 1];
            if (k == COMPAT_EGL_SAMPLE_BUFFERS || k == COMPAT_EGL_SAMPLES ||
                k == COMPAT_EGL_DEPTH_SIZE || k == COMPAT_EGL_STENCIL_SIZE) {
                continue;
            }
            if (k == COMPAT_EGL_SURFACE_TYPE) {
                v = COMPAT_EGL_WINDOW_BIT;
            }
            relaxed[out_i++] = k;
            relaxed[out_i++] = v;
        }
        relaxed[out_i] = COMPAT_EGL_NONE;
        *cnt_ptr = 0;
        ret = real_fn(dpy, relaxed, configs, config_size, cnt_ptr);
        if (ret == 1U && *cnt_ptr > 0) {
            log_text(PMLOG_LEVEL_INFO, "eglChooseConfig RECOVERED via Pass 1 (filtered caller attribs)");
            return ret;
        }
    }

    /* Pass 2: ES2 RGBA8888 window */
    static const int32_t pass2_rgba[] = {
        COMPAT_EGL_RENDERABLE_TYPE, COMPAT_EGL_OPENGL_ES2_BIT,
        COMPAT_EGL_SURFACE_TYPE, COMPAT_EGL_WINDOW_BIT,
        COMPAT_EGL_RED_SIZE, 8,
        COMPAT_EGL_GREEN_SIZE, 8,
        COMPAT_EGL_BLUE_SIZE, 8,
        COMPAT_EGL_ALPHA_SIZE, 8,
        COMPAT_EGL_NONE
    };
    *cnt_ptr = 0;
    ret = real_fn(dpy, pass2_rgba, configs, config_size, cnt_ptr);
    if (ret == 1U && *cnt_ptr > 0) {
        log_text(PMLOG_LEVEL_INFO, "eglChooseConfig RECOVERED via Pass 2 (ES2 RGBA8888)");
        return ret;
    }

    /* Pass 3: ES2 RGB888 window */
    static const int32_t pass3_rgb[] = {
        COMPAT_EGL_RENDERABLE_TYPE, COMPAT_EGL_OPENGL_ES2_BIT,
        COMPAT_EGL_SURFACE_TYPE, COMPAT_EGL_WINDOW_BIT,
        COMPAT_EGL_RED_SIZE, 8,
        COMPAT_EGL_GREEN_SIZE, 8,
        COMPAT_EGL_BLUE_SIZE, 8,
        COMPAT_EGL_NONE
    };
    *cnt_ptr = 0;
    ret = real_fn(dpy, pass3_rgb, configs, config_size, cnt_ptr);
    if (ret == 1U && *cnt_ptr > 0) {
        log_text(PMLOG_LEVEL_INFO, "eglChooseConfig RECOVERED via Pass 3 (ES2 RGB888)");
        return ret;
    }

    /* Pass 4: minimal ES2 & unfiltered wildcard */
    static const int32_t pass4_min[] = {
        COMPAT_EGL_RENDERABLE_TYPE, COMPAT_EGL_OPENGL_ES2_BIT,
        COMPAT_EGL_NONE
    };
    *cnt_ptr = 0;
    ret = real_fn(dpy, pass4_min, configs, config_size, cnt_ptr);
    if (ret == 1U && *cnt_ptr > 0) {
        log_text(PMLOG_LEVEL_INFO, "eglChooseConfig RECOVERED via Pass 4 (minimal ES2)");
        return ret;
    }

    static const int32_t pass5_any[] = { COMPAT_EGL_NONE };
    *cnt_ptr = 0;
    ret = real_fn(dpy, pass5_any, configs, config_size, cnt_ptr);
    if (ret == 1U && *cnt_ptr > 0) {
        log_text(PMLOG_LEVEL_INFO, "eglChooseConfig RECOVERED via Pass 5 (EGL_NONE wildcard)");
        return ret;
    }

    log_egl_attribs("eglChooseConfig ALL PASSES FAILED", 0, compat_egl_get_error());
    return ret;
}

EXPORT void *eglCreateContext(
    void *dpy,
    void *config,
    void *share_context,
    const int32_t *attrib_list
) {
    typedef void *(*fn_ctx_t)(void *, void *, void *, const int32_t *);
    static int logged_ok = 0;
    fn_ctx_t real_fn = (fn_ctx_t)resolve_egl_sym("eglCreateContext", (void *)eglCreateContext);
    if (!real_fn) {
        log_text(PMLOG_LEVEL_ERROR, "eglCreateContext resolve FAILED");
        return 0;
    }

    void *ctx = real_fn(dpy, config, share_context, attrib_list);
    if (ctx) {
        if (!logged_ok) {
            logged_ok = 1;
            log_text(PMLOG_LEVEL_INFO, "eglCreateContext succeeded");
        }
        return ctx;
    }

    log_egl_attribs("eglCreateContext FAILED", attrib_list, compat_egl_get_error());

    /* Fallback if GLES 3 context requested on an ES2-only config */
    if (attrib_list) {
        int want_es3 = 0;
        for (int i = 0; i < 16 && attrib_list[i] != COMPAT_EGL_NONE; i += 2) {
            if (attrib_list[i] == COMPAT_EGL_CONTEXT_CLIENT_VERSION && attrib_list[i + 1] > 2) {
                want_es3 = 1;
                break;
            }
        }
        if (want_es3) {
            static const int32_t es2_attrs[] = { COMPAT_EGL_CONTEXT_CLIENT_VERSION, 2, COMPAT_EGL_NONE };
            ctx = real_fn(dpy, config, share_context, es2_attrs);
            if (ctx) {
                log_text(PMLOG_LEVEL_INFO, "eglCreateContext RECOVERED via ES2 fallback");
                return ctx;
            }
        }
    }
    return 0;
}

EXPORT void *eglCreateWindowSurface(
    void *dpy,
    void *config,
    uintptr_t win,
    const int32_t *attrib_list
) {
    typedef void *(*fn_ws_t)(void *, void *, uintptr_t, const int32_t *);
    static int logged_ok = 0;
    fn_ws_t real_fn = (fn_ws_t)resolve_egl_sym("eglCreateWindowSurface", (void *)eglCreateWindowSurface);
    if (!real_fn) {
        log_text(PMLOG_LEVEL_ERROR, "eglCreateWindowSurface resolve FAILED");
        return 0;
    }

    void *surf = real_fn(dpy, config, win, attrib_list);
    if (surf) {
        if (!logged_ok) {
            logged_ok = 1;
            log_text(PMLOG_LEVEL_INFO, "eglCreateWindowSurface succeeded");
        }
        return surf;
    }

    log_egl_attribs("eglCreateWindowSurface FAILED", attrib_list, compat_egl_get_error());
    if (attrib_list && attrib_list[0] != COMPAT_EGL_NONE) {
        static const int32_t empty_attrs[] = { COMPAT_EGL_NONE };
        surf = real_fn(dpy, config, win, empty_attrs);
        if (surf) {
            log_text(PMLOG_LEVEL_INFO, "eglCreateWindowSurface RECOVERED with empty attribs");
            return surf;
        }
    }
    return 0;
}

/* ============================================================================
 * Luna Service 2 (LS*) Resilience & Internal RapidJSON Guard (webOS 6 ACG)
 * ============================================================================ */
typedef int (*compat_ls_cb_t)(void *sh, void *msg, void *ctx);

#define COMPAT_LS_FAKE_COUNT 64
#define COMPAT_LS_SLOT_COUNT 256

static char g_fake_ls_handles[COMPAT_LS_FAKE_COUNT];
static uint32_t g_fake_ls_next = 0;

struct compat_ls_slot {
    int used;
    int one_shot;
    int is_internal;
    void *sh;
    uint32_t token;
    uint32_t seq;
    compat_ls_cb_t orig_cb;
    void *orig_ctx;
    char uri[128];
};

static struct compat_ls_slot g_ls_slots[COMPAT_LS_SLOT_COUNT];
static volatile int g_ls_lock = 0;
static uint32_t g_ls_seq = 0;
static uint32_t g_ls_call_logs = 0;
static uint32_t g_ls_reply_logs = 0;

static void compat_ls_acquire(void) {
    while (__atomic_test_and_set(&g_ls_lock, __ATOMIC_ACQUIRE)) {}
}

static void compat_ls_release(void) {
    __atomic_clear(&g_ls_lock, __ATOMIC_RELEASE);
}

static int is_fake_ls_handle(const void *sh) {
    return sh >= (const void *)g_fake_ls_handles &&
           sh < (const void *)(g_fake_ls_handles + COMPAT_LS_FAKE_COUNT);
}

static void *alloc_fake_ls_handle(void) {
    uint32_t idx = __atomic_fetch_add(&g_fake_ls_next, 1U, __ATOMIC_RELAXED) % COMPAT_LS_FAKE_COUNT;
    return (void *)&g_fake_ls_handles[idx];
}

static void *resolve_ls_sym(const char *name, void *self_fn) {
    static void *ls_h = 0;
    void *fn = dlsym(RTLD_NEXT, name);
    if (fn && fn != self_fn) return fn;
    if (!ls_h) {
        ls_h = dlopen("libluna-service2.so.3", RTLD_LAZY);
        if (!ls_h) ls_h = dlopen("/usr/lib/libluna-service2.so.3", RTLD_LAZY);
    }
    if (ls_h) {
        fn = dlsym(ls_h, name);
        if (fn && fn != self_fn) return fn;
    }
    return 0;
}

static void safe_clear_lserror(void *err) {
    if (!err) return;
    typedef void (*fn_ls_err_t)(void *);
    fn_ls_err_t fn_free = (fn_ls_err_t)resolve_ls_sym("LSErrorFree", 0);
    fn_ls_err_t fn_init = (fn_ls_err_t)resolve_ls_sym("LSErrorInit", 0);
    if (fn_free) fn_free(err);
    if (fn_init) fn_init(err);
}

static void log_ls_error(const char *op, const char *detail, void *err) {
    typedef int (*fn_isset_t)(const void *);
    const char *msg = 0;
    if (err) {
        fn_isset_t fn_isset = (fn_isset_t)resolve_ls_sym("LSErrorIsSet", 0);
        if (!fn_isset || fn_isset(err)) {
            /* LSError layout: int error_code; char *message; ... */
            msg = ((const char * const *)err)[1];
        }
    }
    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "LS2 ");
    lbuf_str(&b, op);
    lbuf_str(&b, " FAILED");
    if (detail && detail[0]) {
        lbuf_str(&b, " [");
        lbuf_str_trunc(&b, detail, 140);
        lbuf_str(&b, "]");
    }
    if (msg && msg[0]) {
        lbuf_str(&b, " err=");
        lbuf_str_trunc(&b, msg, 180);
    }
    log_raw_line(PMLOG_LEVEL_ERROR, &b, 1);
}

static int is_internal_embedder_ls_call(const char *uri, const char *payload) {
    if (!uri) return 0;
    if (c_strstr(uri, "registerServerStatus")) return 1;
    if (c_strstr(uri, "com.webos.service.applicationmanager/registerApp") ||
        c_strstr(uri, "com.webos.service.applicationmanager/registerNativeApp")) {
        return 1;
    }
    if (c_strstr(uri, "com.webos.service.tvpower")) return 1;
    if (c_strstr(uri, "screensaver") || c_strstr(uri, "service.sm")) return 1;
    if (c_strstr(uri, "com.webos.settingsservice") && payload &&
        (c_strstr(payload, "localeInfo") || c_strstr(payload, "audioGuidance") || c_strstr(payload, "highContrast"))) {
        return 1;
    }
    return 0;
}

static int ls_payload_unsafe_for_internal(const char *uri, const char *payload) {
    if (!payload || !payload[0]) return 1;
    const char *p = payload;
    while (*p == ' ' || *p == '\\t' || *p == '\\n' || *p == '\\r') ++p;
    if (*p != '{') return 1;
    if (c_strstr(payload, "\\"errorCode\\"")) return 1;
    if (c_strstr(payload, "\\"returnValue\\":false") || c_strstr(payload, "\\"returnValue\\": false")) {
        return 1;
    }
    if (c_strstr(uri, "registerServerStatus")) {
        if (!c_strstr(payload, "\\"serviceName\\"") || !c_strstr(payload, "\\"connected\\"")) {
            return 1;
        }
    }
    if (c_strstr(uri, "com.webos.settingsservice")) {
        if (!c_strstr(payload, "\\"settings\\"") && !c_strstr(payload, "\\"method\\"")) {
            return 1;
        }
    }
    return 0;
}

static int compat_ls_reply_filter(void *sh, void *msg, void *slot_ctx) {
    typedef const char *(*fn_get_payload_t)(void *);
    compat_ls_cb_t orig_cb = 0;
    void *orig_ctx = 0;
    int is_internal = 0;
    int one_shot = 0;
    uint32_t seq = 0;
    char uri_copy[128];
    uri_copy[0] = '\\0';

    struct compat_ls_slot *slot = (struct compat_ls_slot *)slot_ctx;
    int valid_slot = (slot >= &g_ls_slots[0] && slot < &g_ls_slots[COMPAT_LS_SLOT_COUNT]);

    if (valid_slot) {
        compat_ls_acquire();
        if (slot->used) {
            orig_cb = slot->orig_cb;
            orig_ctx = slot->orig_ctx;
            is_internal = slot->is_internal;
            one_shot = slot->one_shot;
            seq = slot->seq;
            copy_str(uri_copy, slot->uri, sizeof(uri_copy));
        }
        compat_ls_release();
    }

    fn_get_payload_t fn_payload = (fn_get_payload_t)resolve_ls_sym("LSMessageGetPayload", 0);
    const char *payload = (fn_payload && msg) ? fn_payload(msg) : 0;

    if (g_ls_reply_logs < 100U) {
        ++g_ls_reply_logs;
        struct log_buf b;
        lbuf_init(&b);
        lbuf_str(&b, "LS2 reply uri=");
        lbuf_str_trunc(&b, uri_copy[0] ? uri_copy : "(unknown)", 96);
        lbuf_str(&b, " payload=");
        lbuf_str_trunc(&b, payload ? payload : "(null)", 180);
        log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
    }

    if (is_internal && ls_payload_unsafe_for_internal(uri_copy, payload)) {
        struct log_buf b;
        lbuf_init(&b);
        lbuf_str(&b, "LS2 SUPPRESSED internal unsafe reply uri=");
        lbuf_str_trunc(&b, uri_copy, 96);
        lbuf_str(&b, " payload=");
        lbuf_str_trunc(&b, payload ? payload : "(null)", 180);
        log_raw_line(PMLOG_LEVEL_ERROR, &b, 1);
        if (one_shot && valid_slot) {
            compat_ls_acquire();
            if (slot->used && slot->seq == seq) slot->used = 0;
            compat_ls_release();
        }
        return 1;
    }

    int ret = 1;
    if (orig_cb) {
        ret = orig_cb(sh, msg, orig_ctx);
    }

    if (one_shot && valid_slot) {
        compat_ls_acquire();
        if (slot->used && slot->seq == seq) slot->used = 0;
        compat_ls_release();
    }
    return ret;
}

static struct compat_ls_slot *alloc_ls_slot(
    void *sh,
    const char *uri,
    const char *payload,
    compat_ls_cb_t cb,
    void *ctx,
    int one_shot,
    uint32_t *out_seq
) {
    compat_ls_acquire();
    struct compat_ls_slot *found = 0;
    for (int i = 0; i < COMPAT_LS_SLOT_COUNT; ++i) {
        if (!g_ls_slots[i].used) {
            found = &g_ls_slots[i];
            break;
        }
    }
    if (found) {
        uint32_t seq = ++g_ls_seq;
        if (seq == 0) seq = ++g_ls_seq;
        found->used = 1;
        found->one_shot = one_shot;
        found->is_internal = is_internal_embedder_ls_call(uri, payload);
        found->sh = sh;
        found->token = 0;
        found->seq = seq;
        found->orig_cb = cb;
        found->orig_ctx = ctx;
        copy_str(found->uri, uri ? uri : "", sizeof(found->uri));
        if (out_seq) *out_seq = seq;
    }
    compat_ls_release();
    return found;
}

static void finish_ls_slot(struct compat_ls_slot *slot, uint32_t seq, void *sh, int ok, const uint32_t *ret_token) {
    if (!slot) return;
    compat_ls_acquire();
    if (slot->used && slot->seq == seq) {
        if (ok && ret_token && *ret_token != 0) {
            slot->sh = sh;
            slot->token = *ret_token;
        } else if (!ok) {
            slot->used = 0;
        }
    }
    compat_ls_release();
}

static void clear_ls_slots_for_token(void *sh, uint32_t token) {
    if (!sh || token == 0U) return;
    compat_ls_acquire();
    for (int i = 0; i < COMPAT_LS_SLOT_COUNT; ++i) {
        if (g_ls_slots[i].used && g_ls_slots[i].sh == sh && g_ls_slots[i].token == token) {
            g_ls_slots[i].used = 0;
        }
    }
    compat_ls_release();
}

static void clear_ls_slots_for_handle(void *sh) {
    compat_ls_acquire();
    for (int i = 0; i < COMPAT_LS_SLOT_COUNT; ++i) {
        if (g_ls_slots[i].used && g_ls_slots[i].sh == sh) {
            g_ls_slots[i].used = 0;
        }
    }
    compat_ls_release();
}

EXPORT int LSRegister(const char *name, void **sh, void *err) {
    typedef int (*fn_t)(const char *, void **, void *);
    fn_t real_fn = (fn_t)resolve_ls_sym("LSRegister", (void *)LSRegister);
    if (real_fn) {
        if (real_fn(name, sh, err) && sh && *sh) {
            log_text(PMLOG_LEVEL_INFO, name ? "LSRegister(named) ok" : "LSRegister(anon) ok");
            return 1;
        }
        log_ls_error("LSRegister", name ? name : "(null)", err);
        safe_clear_lserror(err);
        if (name) {
            if (real_fn(0, sh, err) && sh && *sh) {
                log_text(PMLOG_LEVEL_INFO, "LSRegister RECOVERED via anonymous NULL");
                return 1;
            }
            log_ls_error("LSRegister(anon_fallback)", "(null)", err);
            safe_clear_lserror(err);
        }
    }
    if (sh) *sh = alloc_fake_ls_handle();
    log_text(PMLOG_LEVEL_ERROR, "LSRegister returning sentinel fake handle");
    return 1;
}

EXPORT int LSRegisterApplicationService(const char *name, const char *app_id, void **sh, void *err) {
    typedef int (*fn_app_t)(const char *, const char *, void **, void *);
    typedef int (*fn_reg_t)(const char *, void **, void *);
    fn_app_t real_app = (fn_app_t)resolve_ls_sym("LSRegisterApplicationService", (void *)LSRegisterApplicationService);
    fn_reg_t real_reg = (fn_reg_t)resolve_ls_sym("LSRegister", (void *)LSRegister);

    if (real_app) {
        if (real_app(name, app_id, sh, err) && sh && *sh) {
            log_text(PMLOG_LEVEL_INFO, "LSRegisterApplicationService ok");
            return 1;
        }
        log_ls_error("LSRegisterApplicationService", name ? name : (app_id ? app_id : "(null)"), err);
        safe_clear_lserror(err);
    }
    if (real_reg) {
        if (app_id && real_reg(app_id, sh, err) && sh && *sh) {
            log_text(PMLOG_LEVEL_INFO, "LSRegisterApplicationService RECOVERED via LSRegister(app_id)");
            return 1;
        }
        safe_clear_lserror(err);
        if (real_reg(0, sh, err) && sh && *sh) {
            log_text(PMLOG_LEVEL_INFO, "LSRegisterApplicationService RECOVERED via anonymous LSRegister(NULL)");
            return 1;
        }
        log_ls_error("LSRegisterApplicationService(anon_fallback)", "(null)", err);
        safe_clear_lserror(err);
    }
    if (sh) *sh = alloc_fake_ls_handle();
    log_text(PMLOG_LEVEL_ERROR, "LSRegisterApplicationService returning sentinel fake handle");
    return 1;
}

EXPORT int LSRegisterPubPriv(const char *name, void **sh, int public_bus, void *err) {
    typedef int (*fn_pp_t)(const char *, void **, int, void *);
    fn_pp_t real_pp = (fn_pp_t)resolve_ls_sym("LSRegisterPubPriv", (void *)LSRegisterPubPriv);
    if (real_pp) {
        if (real_pp(name, sh, public_bus, err) && sh && *sh) {
            return 1;
        }
        log_ls_error("LSRegisterPubPriv", name ? name : "(null)", err);
        safe_clear_lserror(err);
    }
    return LSRegister(name, sh, err);
}

EXPORT int LSUnregister(void *sh, void *err) {
    typedef int (*fn_t)(void *, void *);
    clear_ls_slots_for_handle(sh);
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 1;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSUnregister", (void *)LSUnregister);
    if (real_fn) {
        if (real_fn(sh, err)) return 1;
        log_ls_error("LSUnregister", "", err);
        safe_clear_lserror(err);
    }
    return 1;
}

EXPORT int LSGmainAttach(void *sh, void *main_loop, void *err) {
    typedef int (*fn_t)(void *, void *, void *);
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 1;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSGmainAttach", (void *)LSGmainAttach);
    if (real_fn) {
        if (real_fn(sh, main_loop, err)) return 1;
        log_ls_error("LSGmainAttach", "", err);
        safe_clear_lserror(err);
    }
    return 1;
}

EXPORT int LSGmainContextAttach(void *sh, void *gmain_ctx, void *err) {
    typedef int (*fn_t)(void *, void *, void *);
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 1;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSGmainContextAttach", (void *)LSGmainContextAttach);
    if (real_fn) {
        if (real_fn(sh, gmain_ctx, err)) return 1;
        log_ls_error("LSGmainContextAttach", "", err);
        safe_clear_lserror(err);
    }
    return 1;
}

EXPORT int LSRegisterCategory(
    void *sh,
    const char *category,
    void *methods,
    void *signals,
    void *properties,
    void *err
) {
    typedef int (*fn_t)(void *, const char *, void *, void *, void *, void *);
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 1;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSRegisterCategory", (void *)LSRegisterCategory);
    if (real_fn) {
        if (real_fn(sh, category, methods, signals, properties, err)) return 1;
        log_ls_error("LSRegisterCategory", category ? category : "", err);
        safe_clear_lserror(err);
    }
    return 1;
}

EXPORT int LSCategorySetData(void *sh, const char *category, void *user_data, void *err) {
    typedef int (*fn_t)(void *, const char *, void *, void *);
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 1;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSCategorySetData", (void *)LSCategorySetData);
    if (real_fn) {
        if (real_fn(sh, category, user_data, err)) return 1;
        log_ls_error("LSCategorySetData", category ? category : "", err);
        safe_clear_lserror(err);
    }
    return 1;
}

EXPORT int LSMessageRespond(void *msg, const char *reply_payload, void *err) {
    typedef int (*fn_t)(void *, const char *, void *);
    if (!msg) {
        safe_clear_lserror(err);
        return 1;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSMessageRespond", (void *)LSMessageRespond);
    if (real_fn) {
        if (real_fn(msg, reply_payload, err)) return 1;
        log_ls_error("LSMessageRespond", "", err);
        safe_clear_lserror(err);
    }
    return 1;
}

EXPORT int LSCallCancel(void *sh, uint32_t token, void *err) {
    typedef int (*fn_t)(void *, uint32_t, void *);
    static uint32_t zero_logs = 0;
    if (!sh || is_fake_ls_handle(sh) || token == 0U) {
        if (sh && !is_fake_ls_handle(sh) && token == 0U &&
            __atomic_fetch_add(&zero_logs, 1U, __ATOMIC_RELAXED) < 5U) {
            log_text(PMLOG_LEVEL_INFO, "LS2 LSCallCancel(token=0) ignored");
        }
        safe_clear_lserror(err);
        return 1;
    }
    clear_ls_slots_for_token(sh, token);
    fn_t real_fn = (fn_t)resolve_ls_sym("LSCallCancel", (void *)LSCallCancel);
    if (real_fn) {
        if (real_fn(sh, token, err)) return 1;
        log_ls_error("LSCallCancel", "", err);
        safe_clear_lserror(err);
    }
    return 1;
}

EXPORT int LSCallCancelNotificationAdd(void *sh, void *cb, void *ctx, void *err) {
    typedef int (*fn_t)(void *, void *, void *, void *);
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 1;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSCallCancelNotificationAdd", (void *)LSCallCancelNotificationAdd);
    if (real_fn) {
        if (real_fn(sh, cb, ctx, err)) return 1;
        log_ls_error("LSCallCancelNotificationAdd", "", err);
        safe_clear_lserror(err);
    }
    return 1;
}

EXPORT int LSCallCancelNotificationRemove(void *sh, void *cb, void *ctx, void *err) {
    typedef int (*fn_t)(void *, void *, void *, void *);
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 1;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSCallCancelNotificationRemove", (void *)LSCallCancelNotificationRemove);
    if (real_fn) {
        if (real_fn(sh, cb, ctx, err)) return 1;
        log_ls_error("LSCallCancelNotificationRemove", "", err);
        safe_clear_lserror(err);
    }
    return 1;
}

static void log_ls_call_start(const char *fn_name, const char *uri, const char *payload) {
    if (g_ls_call_logs >= 200U) return;
    ++g_ls_call_logs;
    struct log_buf b;
    lbuf_init(&b);
    lbuf_str(&b, "LS2 ");
    lbuf_str(&b, fn_name);
    lbuf_str(&b, " uri=");
    lbuf_str_trunc(&b, uri ? uri : "(null)", 120);
    lbuf_str(&b, " payload=");
    lbuf_str_trunc(&b, payload ? payload : "(null)", 120);
    log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
}

EXPORT int LSCallFromApplication(
    void *sh,
    const char *uri,
    const char *payload,
    const char *app_id,
    compat_ls_cb_t cb,
    void *ctx,
    uint32_t *ret_token,
    void *err
) {
    typedef int (*fn_t)(void *, const char *, const char *, const char *, compat_ls_cb_t, void *, uint32_t *, void *);
    log_ls_call_start("LSCallFromApplication", uri, payload);
    if (ret_token) *ret_token = 0U;
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 0;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSCallFromApplication", (void *)LSCallFromApplication);
    if (!real_fn) {
        safe_clear_lserror(err);
        return 0;
    }
    int wrap = (cb != 0 && is_internal_embedder_ls_call(uri, payload));
    uint32_t seq = 0;
    struct compat_ls_slot *slot = wrap ? alloc_ls_slot(sh, uri, payload, cb, ctx, 0, &seq) : 0;
    int ok = real_fn(
        sh, uri, payload, app_id,
        slot ? compat_ls_reply_filter : cb,
        slot ? (void *)slot : ctx,
        ret_token, err
    );
    if (slot) finish_ls_slot(slot, seq, sh, ok, ret_token);
    if (!ok) log_ls_error("LSCallFromApplication", uri, err);
    return ok;
}

EXPORT int LSCall(
    void *sh,
    const char *uri,
    const char *payload,
    compat_ls_cb_t cb,
    void *ctx,
    uint32_t *ret_token,
    void *err
) {
    typedef int (*fn_t)(void *, const char *, const char *, compat_ls_cb_t, void *, uint32_t *, void *);
    log_ls_call_start("LSCall", uri, payload);
    if (ret_token) *ret_token = 0U;
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 0;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSCall", (void *)LSCall);
    if (!real_fn) {
        safe_clear_lserror(err);
        return 0;
    }
    int wrap = (cb != 0 && is_internal_embedder_ls_call(uri, payload));
    uint32_t seq = 0;
    struct compat_ls_slot *slot = wrap ? alloc_ls_slot(sh, uri, payload, cb, ctx, 0, &seq) : 0;
    int ok = real_fn(
        sh, uri, payload,
        slot ? compat_ls_reply_filter : cb,
        slot ? (void *)slot : ctx,
        ret_token, err
    );
    if (slot) finish_ls_slot(slot, seq, sh, ok, ret_token);
    if (!ok) log_ls_error("LSCall", uri, err);
    return ok;
}

EXPORT int LSCallOneReply(
    void *sh,
    const char *uri,
    const char *payload,
    compat_ls_cb_t cb,
    void *ctx,
    uint32_t *ret_token,
    void *err
) {
    typedef int (*fn_t)(void *, const char *, const char *, compat_ls_cb_t, void *, uint32_t *, void *);
    log_ls_call_start("LSCallOneReply", uri, payload);
    if (ret_token) *ret_token = 0U;
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 0;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSCallOneReply", (void *)LSCallOneReply);
    if (!real_fn) {
        safe_clear_lserror(err);
        return 0;
    }
    int wrap = (cb != 0 && is_internal_embedder_ls_call(uri, payload));
    uint32_t seq = 0;
    struct compat_ls_slot *slot = wrap ? alloc_ls_slot(sh, uri, payload, cb, ctx, 1, &seq) : 0;
    int ok = real_fn(
        sh, uri, payload,
        slot ? compat_ls_reply_filter : cb,
        slot ? (void *)slot : ctx,
        ret_token, err
    );
    if (slot) finish_ls_slot(slot, seq, sh, ok, ret_token);
    if (!ok) log_ls_error("LSCallOneReply", uri, err);
    return ok;
}

EXPORT int LSCallFromApplicationOneReply(
    void *sh,
    const char *uri,
    const char *payload,
    const char *app_id,
    compat_ls_cb_t cb,
    void *ctx,
    uint32_t *ret_token,
    void *err
) {
    typedef int (*fn_t)(void *, const char *, const char *, const char *, compat_ls_cb_t, void *, uint32_t *, void *);
    log_ls_call_start("LSCallFromApplicationOneReply", uri, payload);
    if (ret_token) *ret_token = 0U;
    if (!sh || is_fake_ls_handle(sh)) {
        safe_clear_lserror(err);
        return 0;
    }
    fn_t real_fn = (fn_t)resolve_ls_sym("LSCallFromApplicationOneReply", (void *)LSCallFromApplicationOneReply);
    if (!real_fn) {
        safe_clear_lserror(err);
        return 0;
    }
    int wrap = (cb != 0 && is_internal_embedder_ls_call(uri, payload));
    uint32_t seq = 0;
    struct compat_ls_slot *slot = wrap ? alloc_ls_slot(sh, uri, payload, cb, ctx, 1, &seq) : 0;
    int ok = real_fn(
        sh, uri, payload, app_id,
        slot ? compat_ls_reply_filter : cb,
        slot ? (void *)slot : ctx,
        ret_token, err
    );
    if (slot) finish_ls_slot(slot, seq, sh, ok, ret_token);
    if (!ok) log_ls_error("LSCallFromApplicationOneReply", uri, err);
    return ok;
}

/* ============================================================================
 * NDL_Media* & SDL_webOS* Compatibility Shims for webOS 6-25
 * ============================================================================ */
static char g_last_window_id[256] = "_Window_Id_1";

static void *resolve_ndl_sym(const char *name) {
    static void *ndl_handle = 0;
    void *fn = dlsym(RTLD_NEXT, name);
    if (fn) return fn;
    if (!ndl_handle) {
        ndl_handle = dlopen("libNDL_media.so.1", RTLD_LAZY);
        if (!ndl_handle) ndl_handle = dlopen("/usr/lib/libNDL_media.so.1", RTLD_LAZY);
    }
    if (ndl_handle) {
        fn = dlsym(ndl_handle, name);
    }
    return fn;
}

EXPORT char *HApp_GetCurrentAppID(char *buf, unsigned int size) {
    if (buf && size > 0) {
        copy_str(buf, COMPAT32_APP_ID, size);
        return buf;
    }
    return COMPAT32_APP_ID;
}

EXPORT const char *SDL_webOSCreateExportedWindow(unsigned int exportedType) {
    static uint32_t create_logs = 0;
    if (__atomic_fetch_add(&create_logs, 1U, __ATOMIC_RELAXED) < 6U) {
        struct log_buf b;
        lbuf_init(&b);
        lbuf_str(&b, "SDL_webOSCreateExportedWindow type=");
        lbuf_u32(&b, exportedType);
        lbuf_str(&b, " -> ");
        lbuf_str_trunc(&b, g_last_window_id, 64);
        log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
    }
    return g_last_window_id;
}

EXPORT int SDL_webOSSetExportedWindow(const char *windowID, const void *srcRegion, const void *dstRegion) {
    (void)windowID;
    (void)srcRegion;
    (void)dstRegion;
    return 1;
}

EXPORT int SDL_webOSExportedSetCropRegion(const char *windowID, const void *orgRegion, const void *srcRegion, const void *dstRegion) {
    (void)windowID;
    (void)orgRegion;
    (void)srcRegion;
    (void)dstRegion;
    return 1;
}

EXPORT int SDL_webOSExportedSetProperty(const char *windowID, const char *name, const char *value) {
    static uint32_t prop_logs = 0;
    if (__atomic_fetch_add(&prop_logs, 1U, __ATOMIC_RELAXED) < 6U) {
        struct log_buf b;
        lbuf_init(&b);
        lbuf_str(&b, "SDL_webOSExportedSetProperty id=");
        lbuf_str_trunc(&b, windowID ? windowID : "(null)", 48);
        lbuf_str(&b, " ");
        lbuf_str_trunc(&b, name ? name : "(null)", 48);
        lbuf_str(&b, "=");
        lbuf_str_trunc(&b, value ? value : "(null)", 48);
        log_raw_line(PMLOG_LEVEL_INFO, &b, 1);
    }
    return 1;
}

EXPORT void SDL_webOSDestroyExportedWindow(const char *windowID) {
    (void)windowID;
}

EXPORT void *SDL_GL_GetCurrentWindow(void) {
    return (void *)1;
}

EXPORT void *SDL_GetWindowFromID(unsigned int id) {
    (void)id;
    return (void *)1;
}

EXPORT void SDL_GetWindowSize(void *window, int *w, int *h) {
    (void)window;
    if (w) *w = 1920;
    if (h) *h = 1080;
}

EXPORT int NDL_MediaInitWithWindowId(void *arg, const char *windowId) {
    typedef int (*fn2_t)(void *, const char *);
    typedef int (*fn1_t)(void *);
    static uint32_t init_logs = 0;
    if (windowId && windowId[0]) {
        copy_str(g_last_window_id, windowId, sizeof(g_last_window_id));
    }
    fn2_t f2 = (fn2_t)resolve_ndl_sym("NDL_MediaInitWithWindowId");
    if (f2) {
        int rc = f2(arg, windowId);
        if (__atomic_fetch_add(&init_logs, 1U, __ATOMIC_RELAXED) < 6U) {
            struct log_buf b;
            lbuf_init(&b);
            lbuf_str(&b, "NDL_MediaInitWithWindowId(native) id=");
            lbuf_str_trunc(&b, windowId ? windowId : "(null)", 64);
            lbuf_str(&b, " rc=");
            lbuf_i32(&b, rc);
            log_raw_line(rc == 0 ? PMLOG_LEVEL_INFO : PMLOG_LEVEL_ERROR, &b, 1);
        }
        return rc;
    }
    fn1_t f1 = (fn1_t)resolve_ndl_sym("NDL_MediaInit");
    if (f1) {
        int rc = f1(arg);
        if (__atomic_fetch_add(&init_logs, 1U, __ATOMIC_RELAXED) < 6U) {
            struct log_buf b;
            lbuf_init(&b);
            lbuf_str(&b, "NDL_MediaInitWithWindowId(fallback) id=");
            lbuf_str_trunc(&b, windowId ? windowId : "(null)", 64);
            lbuf_str(&b, " rc=");
            lbuf_i32(&b, rc);
            log_raw_line(rc == 0 ? PMLOG_LEVEL_INFO : PMLOG_LEVEL_ERROR, &b, 1);
        }
        return rc;
    }
    return 0;
}

EXPORT int NDL_MediaUnsubscribeEvents(void) {
    typedef int (*fn_t)(void);
    fn_t f = (fn_t)resolve_ndl_sym("NDL_MediaUnsubscribeEvents");
    if (f) return f();
    return 0;
}

EXPORT int NDL_MediaSelectAudioTrack(int trackIndex) {
    typedef int (*fn1_t)(int);
    typedef int (*fn2_t)(const char *, int);
    fn1_t f1 = (fn1_t)resolve_ndl_sym("NDL_MediaSelectAudioTrack");
    if (f1) return f1(trackIndex);
    fn2_t f2 = (fn2_t)resolve_ndl_sym("NDL_MediaSelectTrack");
    if (f2) return f2("audio", trackIndex);
    return 0;
}

EXPORT int NDL_MediaSetPlayRate(double rate) {
    typedef int (*fn_t)(double);
    fn_t f1 = (fn_t)resolve_ndl_sym("NDL_MediaSetPlayRate");
    if (f1) return f1(rate);
    fn_t f2 = (fn_t)resolve_ndl_sym("NDL_MediaSetPlaybackRate");
    if (f2) return f2(rate);
    return 0;
}

/* ============================================================================
 * GLIBC_2.38 C23 Symbol Family
 * ============================================================================ */
EXPORT long __isoc23_strtol(const char *nptr, char **endptr, int base) { return strtol(nptr, endptr, base); }
EXPORT unsigned long __isoc23_strtoul(const char *nptr, char **endptr, int base) { return strtoul(nptr, endptr, base); }
EXPORT long long __isoc23_strtoll(const char *nptr, char **endptr, int base) { return strtoll(nptr, endptr, base); }
EXPORT unsigned long long __isoc23_strtoull(const char *nptr, char **endptr, int base) { return strtoull(nptr, endptr, base); }
EXPORT long long __isoc23_strtoimax(const char *nptr, char **endptr, int base) { return strtoll(nptr, endptr, base); }
EXPORT unsigned long long __isoc23_strtoumax(const char *nptr, char **endptr, int base) { return strtoull(nptr, endptr, base); }

EXPORT long __isoc23_strtol_l(const char *nptr, char **endptr, int base, locale_t loc) { return strtol_l(nptr, endptr, base, loc); }
EXPORT unsigned long __isoc23_strtoul_l(const char *nptr, char **endptr, int base, locale_t loc) { return strtoul_l(nptr, endptr, base, loc); }
EXPORT long long __isoc23_strtoll_l(const char *nptr, char **endptr, int base, locale_t loc) { return strtoll_l(nptr, endptr, base, loc); }
EXPORT unsigned long long __isoc23_strtoull_l(const char *nptr, char **endptr, int base, locale_t loc) { return strtoull_l(nptr, endptr, base, loc); }

EXPORT int __isoc23_sscanf(const char *str, const char *format, ...) {
    va_list ap; va_start(ap, format); int ret = vsscanf(str, format, ap); va_end(ap); return ret;
}
EXPORT int __isoc23_vsscanf(const char *str, const char *format, va_list ap) { return vsscanf(str, format, ap); }

EXPORT int __isoc23_fscanf(FILE *stream, const char *format, ...) {
    va_list ap; va_start(ap, format); int ret = vfscanf(stream, format, ap); va_end(ap); return ret;
}
EXPORT int __isoc23_vfscanf(FILE *stream, const char *format, va_list ap) { return vfscanf(stream, format, ap); }

EXPORT int __isoc23_scanf(const char *format, ...) {
    va_list ap; va_start(ap, format); int ret = vscanf(format, ap); va_end(ap); return ret;
}
EXPORT int __isoc23_vscanf(const char *format, va_list ap) { return vscanf(format, ap); }

EXPORT long __isoc23_wcstol(const int *nptr, int **endptr, int base) { return wcstol(nptr, endptr, base); }
EXPORT unsigned long __isoc23_wcstoul(const int *nptr, int **endptr, int base) { return wcstoul(nptr, endptr, base); }
EXPORT long long __isoc23_wcstoll(const int *nptr, int **endptr, int base) { return wcstoll(nptr, endptr, base); }
EXPORT unsigned long long __isoc23_wcstoull(const int *nptr, int **endptr, int base) { return wcstoull(nptr, endptr, base); }
"""

already_defined = {
    "NDL_MediaInitWithWindowId",
    "NDL_MediaUnsubscribeEvents",
    "NDL_MediaSelectAudioTrack",
    "NDL_MediaSetPlayRate",
}

for sym in sorted(und_ndl):
    if sym in qned_native_ndl or sym in already_defined:
        continue
    c_code += f"""
EXPORT int {sym}(int a, int b, int c, int d, int e, int f) {{
    typedef int (*fn_t)(int, int, int, int, int, int);
    fn_t fn = (fn_t)resolve_ndl_sym("{sym}");
    if (fn) return fn(a, b, c, d, e, f);
    return 0;
}}
"""

c_out.write_text(c_code)
PYEOF

"$CLANG_BIN" -target armv7a-linux-gnueabi -mfloat-abi=softfp -march=armv7-a \
  -Wall -Wextra -Werror=implicit-function-declaration -Werror=return-type -Wno-unused-parameter \
  "-DCOMPAT32_APP_ID=\"${APP_ID}\"" \
  -fuse-ld=lld -shared -fPIC -O2 -nostdlib -fno-stack-protector \
  -Wl,-soname,libwebos_compat32.so \
  "$STAGE_DIR/webos_compat32.c" \
  -o "$APP_DIR/lib/libwebos_compat32.so"
chmod 0755 "$APP_DIR/lib/libwebos_compat32.so"
patchelf --set-rpath '$ORIGIN' --force-rpath "$APP_DIR/lib/libwebos_compat32.so"
patchelf --add-needed libc.so.6 "$APP_DIR/lib/libwebos_compat32.so"
patchelf --add-needed librt.so.1 "$APP_DIR/lib/libwebos_compat32.so"
patchelf --add-needed libpthread.so.0 "$APP_DIR/lib/libwebos_compat32.so"
patchelf --add-needed libdl.so.2 "$APP_DIR/lib/libwebos_compat32.so"

echo "  -> libwebos_compat32.so mit clang -nostdlib gebaut!"

echo "=== [5/7] Setze Interpreter (/lib/ld-linux.so.3), RPATH & DT_NEEDED ==="
patchelf --set-interpreter /lib/ld-linux.so.3 "$APP_DIR/plezy"
patchelf --set-rpath '$ORIGIN/lib:$ORIGIN' --force-rpath "$APP_DIR/plezy"

prepend_compat_libs() {
  local target="$1"
  local existing
  existing="$(patchelf --print-needed "$target" 2>/dev/null || true)"
  for lib in $existing; do
    patchelf --remove-needed "$lib" "$target" 2>/dev/null || true
  done
  # patchelf --add-needed prepends to the front of DT_NEEDED, so insert in reverse
  # to yield: libwebos_compat32.so, libdl.so.2, libpthread.so.0, librt.so.1, <existing...>
  # Also strip libwayland-egl.so.1 so webOS 6 (which only ships libwayland-egl.so.0)
  # resolves wl_egl_window_* dynamically via libwebos_compat32.so.
  local filtered
  filtered="$(printf '%s\n' $existing | grep -v -E '^(libwebos_compat32\.so|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|libwayland-egl\.so\.1)$' || true)"
  local rev_existing
  rev_existing="$(printf '%s\n' $filtered | tac)"
  for lib in $rev_existing; do
    [ -n "$lib" ] && patchelf --add-needed "$lib" "$target"
  done
  for compat in librt.so.1 libpthread.so.0 libdl.so.2 libwebos_compat32.so; do
    patchelf --add-needed "$compat" "$target"
  done
}

prepend_compat_libs "$APP_DIR/plezy"
for sofile in "$APP_DIR/lib/"*.so*; do
  if [ -f "$sofile" ] && [ ! -L "$sofile" ]; then
    base_name="$(basename "$sofile")"
    if [ "$base_name" = "libwebos_compat32.so" ] || [ "$base_name" = "libapp.so" ]; then
      patchelf --set-rpath '$ORIGIN' --force-rpath "$sofile" 2>/dev/null || true
      continue
    fi
    patchelf --set-rpath '$ORIGIN' --force-rpath "$sofile"
    prepend_compat_libs "$sofile"
  fi
done

echo "=== [6/7] Patche WebOSSurface wl_webos_shell v2->v1, Verneed-Symbole & Kernel-ABI-Tag ==="
python3 - "$APP_DIR" << 'PYEOF'
import struct
import sys
from pathlib import Path

app_dir = Path(sys.argv[1])

media_so = app_dir / "lib" / "libflutter_webos_media.so"
if not media_so.is_file():
    raise RuntimeError(f"Expected {media_so} to exist")

mdata = bytearray(media_so.read_bytes())
sig_v2 = bytes.fromhex("136800270226cde9007102a9c8c100210223")
sig_v1 = bytes.fromhex("136800270126cde9007102a9c8c100210123")
cnt_v2 = mdata.count(sig_v2)
cnt_v1 = mdata.count(sig_v1)
if cnt_v2 == 1:
    idx = mdata.find(sig_v2)
    mdata[idx:idx + len(sig_v2)] = sig_v1
    media_so.write_bytes(mdata)
    print(f"  -> WebOSSurface::WebOSSurface wl_webos_shell v2->v1 gepatcht an File-Offset 0x{idx:x}!")
elif cnt_v2 == 0 and cnt_v1 >= 3:
    print(f"  -> WebOSSurface::WebOSSurface war bereits auf v1 gepatcht ({cnt_v1}x).")
else:
    raise RuntimeError(f"Unerwartete WebOSSurface-Signaturzahl: sig_v2={cnt_v2}, sig_v1={cnt_v1}")

# Math symbols in libm.so.6 whose ARM32 ABI is unchanged across GLIBC_2.4..GLIBC_2.38
REMAP_TO_GLIBC_2_4 = {
    "exp", "exp2", "fmod", "fmodf", "hypot", "hypotf", "log", "log2", "pow",
}

UNVERSION_SYMBOLS = {
    "__libc_start_main",
    "__libc_single_threaded",
    "stat64", "fstat64", "lstat64", "fstatat64",
    "pthread_cond_clockwait",
    "arc4random",
    "close_range",
    "pthread_getname_np",
    "pthread_setname_np",
}

# In glibc 2.34+, libpthread/libdl/librt symbols moved into libc.so.6. Unversioning them
# (vs_val = 1) lets glibc 2.28-2.33 bind them from libpthread.so.0/libdl.so.2/librt.so.1
# without failing the Vernaux filename check if libc.so.6 appears earlier in a lookup scope,
# while still binding cleanly against libc.so.6 default versions on glibc 2.34+.
UNVERSION_THREAD_DL_RT_FILES = {
    "libc.so.6",
    "libpthread.so.0",
    "libdl.so.2",
    "librt.so.1",
}
DL_MOVE_SYMBOLS = {"dladdr", "dlclose", "dlerror", "dlopen", "dlsym"}

DISALLOWED_GLIBC_VERSIONS = {
    "GLIBC_2.29", "GLIBC_2.30", "GLIBC_2.31", "GLIBC_2.32", "GLIBC_2.33",
    "GLIBC_2.34", "GLIBC_2.35", "GLIBC_2.36", "GLIBC_2.37", "GLIBC_2.38", "GLIBC_2.39",
}

def patch_elf_cleanly(elf_path: Path):
    data = bytearray(elf_path.read_bytes())
    if data[:4] != b"\x7fELF" or data[4] != 1:
        return

    modified = False
    abi_sig = b"\x04\x00\x00\x00\x10\x00\x00\x00\x01\x00\x00\x00GNU\x00\x00\x00\x00\x00"
    pos = 0
    while True:
        abi_idx = data.find(abi_sig, pos)
        if abi_idx == -1:
            break
        ver_pos = abi_idx + len(abi_sig)
        if ver_pos + 12 <= len(data):
            k_maj, k_min, _ = struct.unpack_from("<III", data, ver_pos)
            if (k_maj, k_min) > (3, 2):
                struct.pack_into("<III", data, ver_pos, 3, 2, 0)
                modified = True
        pos = abi_idx + 4

    e_shoff = struct.unpack_from("<I", data, 32)[0]
    e_shentsize = struct.unpack_from("<H", data, 46)[0]
    e_shnum = struct.unpack_from("<H", data, 48)[0]

    dynsym_sh = None
    versym_sh = None
    verneed_sh = None
    dynamic_sh = None
    shdrs = []

    for i in range(e_shnum):
        off = e_shoff + i * e_shentsize
        if off + 40 > len(data):
            break
        sh = list(struct.unpack_from("<10I", data, off))
        shdrs.append((i, off, sh))
        sh_type = sh[1]
        if sh_type == 11:  # SHT_DYNSYM
            dynsym_sh = sh
        elif sh_type == 0x6FFFFFFF:  # SHT_GNU_versym
            versym_sh = sh
        elif sh_type == 0x6FFFFFFE:  # SHT_GNU_verneed
            verneed_sh = sh
        elif sh_type == 6:  # SHT_DYNAMIC
            dynamic_sh = sh

    if verneed_sh and versym_sh and dynsym_sh and verneed_sh[6] < len(shdrs):
        dynstr_off = shdrs[verneed_sh[6]][2][4]
        dynsym_off = dynsym_sh[4]
        dynsym_entsize = dynsym_sh[9] or 16
        dynsym_cnt = dynsym_sh[5] // dynsym_entsize

        def read_cstr(str_offset: int) -> str:
            start = dynstr_off + str_offset
            end = data.find(0, start)
            return data[start:end].decode("ascii", errors="ignore")

        vn_off = verneed_sh[4]
        vn_size = verneed_sh[5]
        vn_cnt = verneed_sh[7]

        vn_groups = []
        ndx_info = {}
        file_ver_to_ndx = {}
        cur_vn = vn_off
        for _ in range(vn_cnt):
            vn_version, cnt, vn_file, vn_aux, vn_next = struct.unpack_from("<HHIII", data, cur_vn)
            file_name = read_cstr(vn_file)
            aux_list = []
            cur_aux = cur_vn + vn_aux
            for _ in range(cnt):
                vna_hash, vna_flags, vna_other, vna_name, vna_next = struct.unpack_from("<IHHII", data, cur_aux)
                ver_name = read_cstr(vna_name)
                aux_rec = {
                    "hash": vna_hash,
                    "flags": vna_flags,
                    "other": vna_other,
                    "name_off": vna_name,
                    "ver_name": ver_name,
                }
                aux_list.append(aux_rec)
                raw_ndx = vna_other & 0x7FFF
                ndx_info[raw_ndx] = (file_name, ver_name)
                file_ver_to_ndx[(file_name, ver_name)] = raw_ndx
                if vna_next == 0:
                    break
                cur_aux += vna_next
            vn_groups.append({
                "version": vn_version,
                "file_off": vn_file,
                "file_name": file_name,
                "aux": aux_list,
            })
            if vn_next == 0:
                break
            cur_vn += vn_next

        vs_off = versym_sh[4]
        vs_cnt = versym_sh[5] // 2
        if vs_cnt != dynsym_cnt:
            raise RuntimeError(f"{elf_path.name}: versym count {vs_cnt} != dynsym count {dynsym_cnt}")

        for sym_idx in range(1, dynsym_cnt):
            st_name, _st_val, _st_size, _st_info, _st_other, st_shndx = struct.unpack_from(
                "<IIIBBH", data, dynsym_off + sym_idx * dynsym_entsize
            )
            if st_shndx != 0 or st_name == 0:
                continue
            sym_name = read_cstr(st_name)
            vs_val = struct.unpack_from("<H", data, vs_off + sym_idx * 2)[0]
            raw_ndx = vs_val & 0x7FFF
            if raw_ndx <= 1:
                continue
            vn_file, ver_name = ndx_info.get(raw_ndx, ("", ""))

            if (
                sym_name in UNVERSION_SYMBOLS
                or sym_name.startswith("__isoc23_")
                or (
                    vn_file in UNVERSION_THREAD_DL_RT_FILES
                    and (
                        sym_name.startswith(("pthread_", "sem_", "shm_"))
                        or sym_name in DL_MOVE_SYMBOLS
                    )
                )
            ):
                struct.pack_into("<H", data, vs_off + sym_idx * 2, 1)
                modified = True
            elif sym_name in REMAP_TO_GLIBC_2_4 and ver_name != "GLIBC_2.4":
                target_ndx = file_ver_to_ndx.get((vn_file, "GLIBC_2.4"))
                if target_ndx is None:
                    raise RuntimeError(f"{elf_path.name}: Kein GLIBC_2.4 Verneed-Eintrag fuer {sym_name}@{ver_name} ({vn_file})")
                struct.pack_into("<H", data, vs_off + sym_idx * 2, (vs_val & 0x8000) | target_ndx)
                modified = True

        used_indices = set()
        for sym_idx in range(1, dynsym_cnt):
            vs_val = struct.unpack_from("<H", data, vs_off + sym_idx * 2)[0]
            raw_ndx = vs_val & 0x7FFF
            if raw_ndx > 1:
                used_indices.add(raw_ndx)

        for raw_ndx in sorted(used_indices):
            vn_file, ver_name = ndx_info.get(raw_ndx, ("", ""))
            if ver_name in DISALLOWED_GLIBC_VERSIONS:
                # Diagnose leftover symbols still referencing disallowed GLIBC versions
                offenders = []
                for sym_idx in range(1, dynsym_cnt):
                    vs_val = struct.unpack_from("<H", data, vs_off + sym_idx * 2)[0]
                    if (vs_val & 0x7FFF) == raw_ndx:
                        st_name = struct.unpack_from("<I", data, dynsym_off + sym_idx * dynsym_entsize)[0]
                        offenders.append(read_cstr(st_name))
                raise RuntimeError(f"{elf_path.name}: Unbehandelte Version {ver_name} ({vn_file}) fuer {offenders}")

        # Rebuild .gnu.version_r cleanly keeping only referenced Vernaux entries
        kept_groups = []
        removed_any_aux = False
        for grp in vn_groups:
            kept_aux = []
            for a in grp["aux"]:
                raw_ndx = a["other"] & 0x7FFF
                if raw_ndx in used_indices:
                    kept_aux.append(a)
                elif a["ver_name"] in DISALLOWED_GLIBC_VERSIONS or a["ver_name"].startswith("GLIBC_"):
                    removed_any_aux = True
                else:
                    kept_aux.append(a)
            if kept_aux:
                kept_groups.append({**grp, "aux": kept_aux})
            else:
                removed_any_aux = True

        if removed_any_aux and not kept_groups:
            raise RuntimeError(f"{elf_path.name}: Verneed became empty after filtering")

        if removed_any_aux and kept_groups:
            new_blob = bytearray()
            for gi, grp in enumerate(kept_groups):
                aux_count = len(grp["aux"])
                grp_bytes = 16 + aux_count * 16
                vn_next_off = grp_bytes if (gi + 1 < len(kept_groups)) else 0
                new_blob += struct.pack("<HHIII", grp["version"], aux_count, grp["file_off"], 16, vn_next_off)
                for ai, a in enumerate(grp["aux"]):
                    vna_next_off = 16 if (ai + 1 < aux_count) else 0
                    new_blob += struct.pack("<IHHII", a["hash"], a["flags"], a["other"], a["name_off"], vna_next_off)
            if len(new_blob) > vn_size:
                raise RuntimeError(f"{elf_path.name}: Verneed overflow")
            data[vn_off:vn_off + vn_size] = new_blob + b"\x00" * (vn_size - len(new_blob))

            # Update Verneed section sh_info AND DT_VERNEEDNUM
            verneed_idx, verneed_hdr_off, verneed_fields = next(
                (idx, hoff, fields) for idx, hoff, fields in shdrs if fields[1] == 0x6FFFFFFE
            )
            verneed_fields[7] = len(kept_groups)
            struct.pack_into("<10I", data, verneed_hdr_off, *verneed_fields)
            if dynamic_sh:
                dyn_off = dynamic_sh[4]
                dyn_size = dynamic_sh[5]
                for doff in range(dyn_off, dyn_off + dyn_size, 8):
                    d_tag, _d_val = struct.unpack_from("<iI", data, doff)
                    if d_tag == 0:
                        break
                    if d_tag == 0x6FFFFFFF:  # DT_VERNEEDNUM
                        struct.pack_into("<I", data, doff + 4, len(kept_groups))
            modified = True

    if modified:
        elf_path.write_bytes(data)
        print(f"  -> {elf_path.name}: Verneed / ABI-Tag bereinigt.")

targets = [app_dir / "plezy"] + sorted((app_dir / "lib").glob("*.so*"))
for t in targets:
    if t.is_file() and not t.is_symlink() and t.name not in ("libwebos_compat32.so", "libapp.so"):
        patch_elf_cleanly(t)

def patch_multiseat_pointer(so_path: Path):
    if not so_path.exists():
        return
    data = bytearray(so_path.read_bytes())
    e_shoff = struct.unpack_from("<I", data, 0x20)[0]
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x2E)
    shdrs = [
        struct.unpack_from("<10I", data, e_shoff + idx * e_shentsize)
        for idx in range(e_shnum)
    ]
    shstr_off = shdrs[e_shstrndx][4]
    def sh_name(idx):
        off = shstr_off + shdrs[idx][0]
        return data[off:data.find(b"\x00", off)].decode("ascii", "replace")

    dynsym_sh = next((s for i, s in enumerate(shdrs) if sh_name(i) == ".dynsym"), None)
    dynstr_sh = next((s for i, s in enumerate(shdrs) if sh_name(i) == ".dynstr"), None)
    text_sh = next((s for i, s in enumerate(shdrs) if sh_name(i) == ".text"), None)
    if not dynsym_sh or not dynstr_sh or not text_sh:
        raise RuntimeError(f"{so_path.name}: fehlende ELF-Sektionen fuer Multi-Seat-Pointer-Patch")

    ds_off = dynstr_sh[4]
    def dyn_str(off):
        p = ds_off + off
        return data[p:data.find(b"\x00", p)].decode("ascii", "replace")

    sym_off, sym_size, sym_entsize = dynsym_sh[4], dynsym_sh[5], dynsym_sh[9]
    syms = {}
    for idx in range(sym_size // sym_entsize):
        st_name, st_value, st_size, _st_info, _st_other, st_shndx = struct.unpack_from(
            "<IIIBBH", data, sym_off + idx * sym_entsize
        )
        if st_shndx != 0 and st_name != 0:
            name = dyn_str(st_name)
            if "WaylandSeatInputs" in name:
                syms[name] = (st_value & ~1, st_size)

    text_vaddr, text_foff, text_size = text_sh[3], text_sh[4], text_sh[5]
    def v2f(va):
        return text_foff + (va - text_vaddr)

    changed = False

    add_ptr_sym = "_ZN7flutter17WaylandSeatInputs10AddPointerEP10wl_pointer"
    if add_ptr_sym in syms:
        va, sz = syms[add_ptr_sym]
        f0 = v2f(va)
        f1 = f0 + min(sz if sz > 0 else 0x48, 0x48)
        old_bytes = bytes.fromhex("60b18068a84218bfb0bd")
        new_bytes = bytes.fromhex("65b100bf00bf00bf00bf")
        pos = data.find(old_bytes, f0, f1)
        if pos >= 0:
            data[pos:pos + len(new_bytes)] = new_bytes
            changed = True
            print(f"  -> {so_path.name}: WaylandSeatInputs::AddPointer Multi-Seat-Filter entfernt (0x{pos:x}).")
        elif data.find(new_bytes, f0, f1) >= 0:
            print(f"  -> {so_path.name}: WaylandSeatInputs::AddPointer war bereits gepatcht.")
        else:
            raise RuntimeError(f"{so_path.name}: AddPointer-Signatur nicht gefunden in 0x{f0:x}..0x{f1:x}")
    else:
        raise RuntimeError(f"{so_path.name}: Symbol {add_ptr_sym} nicht gefunden")

    ctor_sym = "_ZN7flutter17WaylandSeatInputsC2EPNS_19ELinuxWindowWaylandEPNS_17FlutterELinuxViewE"
    if ctor_sym in syms:
        va, sz = syms[ctor_sym]
        f0 = v2f(va)
        f1 = f0 + min(sz if sz > 0 else 0xB0, 0xB0)
        head = bytes.fromhex("206a")
        tail = bytes.fromhex("48b18068b84206d1")
        nops = bytes.fromhex("00bf" * 7)
        patched_ctor = False
        already_ctor = False
        for i in range(f0, f1 - 14 + 1, 2):
            if data[i:i+2] == head and data[i+6:i+14] == tail:
                i1, i2 = struct.unpack_from("<HH", data, i + 2)
                if (i1 & 0xF800) == 0xF000 and (i2 & 0xE800) == 0xE800:
                    data[i:i+14] = nops
                    changed = True
                    patched_ctor = True
                    print(f"  -> {so_path.name}: WaylandSeatInputs ctor Multi-Seat-Filter entfernt (0x{i:x}).")
                    break
        if not patched_ctor:
            # Check idempotency: cbz r7 followed directly by 7 NOPs
            if data.find(bytes.fromhex("6fb1") + nops, f0, f1) >= 0:
                already_ctor = True
                print(f"  -> {so_path.name}: WaylandSeatInputs ctor war bereits gepatcht.")
            if not already_ctor:
                raise RuntimeError(f"{so_path.name}: WaylandSeatInputs ctor Signatur nicht gefunden in 0x{f0:x}..0x{f1:x}")
    else:
        raise RuntimeError(f"{so_path.name}: Symbol {ctor_sym} nicht gefunden")

    if changed:
        so_path.write_bytes(data)

patch_multiseat_pointer(app_dir / "lib" / "libflutter_webos_media.so")
PYEOF

rm -rf "$APP_DIR/appdata/"* "$APP_DIR/appdata/".* 2>/dev/null || true
chmod 0777 "$APP_DIR/appdata" 2>/dev/null || true
chmod 0755 "$APP_DIR/lib/"*.so* 2>/dev/null || true

echo "=== [7/7] Baue kompatibles Paket (SysV ar + POSIX ustar): ${APP_ID}_${APP_VER}_arm_webos6-24.ipk ==="
mkdir -p "$STAGE_DIR/ctrl_extract"
tar -xzf "$STAGE_DIR/ipk_extract/control.tar.gz" -C "$STAGE_DIR/ctrl_extract"

OUT_COMPAT_PATH="$OUT_DIR/${APP_ID}_${APP_VER}_arm_webos6-24.ipk"
rm -f "$OUT_COMPAT_PATH"

python3 - "$STAGE_DIR" "$OUT_COMPAT_PATH" "$APP_ID" << 'PYEOF'
import gzip
import io
import os
import re
import stat
import sys
import tarfile
from pathlib import Path

stage_dir = Path(sys.argv[1])
out_path = Path(sys.argv[2])
app_id = sys.argv[3]
data_root = stage_dir / "data_extract"
ctrl_path = stage_dir / "ctrl_extract" / "control"
ipk_extract = stage_dir / "ipk_extract"

# Fixed non-zero timestamp safely in the past (2024-01-01 00:00:00 UTC) so
# GNU tar in webOS pkgverifier never warns about epoch-zero OR future mtimes
# if a TV's RTC/NTP clock is behind the CI runner clock.
ipk_mtime = int(os.environ.get("IPK_MTIME", "1704067200"))
if ipk_mtime <= 0:
    raise RuntimeError(f"IPK_MTIME must be > 0, got {ipk_mtime}")

usr_root = data_root / "usr"
if not usr_root.is_dir():
    raise RuntimeError(f"missing usr/ directory under {data_root}")


def gzip_unix_bytes(raw_tar: bytes) -> bytes:
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0, compresslevel=6) as gz:
        gz.write(raw_tar)
    out = bytearray(buf.getvalue())
    out[9] = 3  # Unix OS byte, matching gzip -n / ares-package
    return bytes(out)


def add_ustar_dir(tf: tarfile.TarFile, arcname: str, mode: int) -> None:
    ti = tarfile.TarInfo(arcname)
    ti.type = tarfile.DIRTYPE
    ti.mode = mode
    ti.uid = 0
    ti.gid = 0
    ti.uname = "root"
    ti.gname = "root"
    ti.mtime = ipk_mtime
    ti.tobuf(tarfile.USTAR_FORMAT)
    tf.addfile(ti)


def add_ustar_file(tf: tarfile.TarFile, arcname: str, payload: bytes, mode: int) -> None:
    ti = tarfile.TarInfo(arcname)
    ti.type = tarfile.REGTYPE
    ti.mode = mode
    ti.uid = 0
    ti.gid = 0
    ti.uname = "root"
    ti.gname = "root"
    ti.mtime = ipk_mtime
    ti.size = len(payload)
    ti.tobuf(tarfile.USTAR_FORMAT)
    tf.addfile(ti, io.BytesIO(payload))


# Walk usr/ in deterministic directory-first order matching ares-package and compute Installed-Size.
file_bytes = 0
dir_count = 1  # count root '.' alongside every directory, matching ares-package getFileSize
entries = []  # (arcname, is_dir, src_path_or_none, mode, size)

for cur_dir, dirnames, filenames in os.walk(usr_root):
    dirnames.sort()
    filenames.sort()
    cur_path = Path(cur_dir)
    rel_dir = cur_path.relative_to(data_root).as_posix()
    dir_count += 1
    d_mode = 0o777 if rel_dir.endswith("/appdata") else 0o755
    entries.append((rel_dir, True, None, d_mode, 0))
    for fname in filenames:
        fpath = cur_path / fname
        st = fpath.lstat()
        if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
            raise RuntimeError(f"unsupported non-regular entry in package data: {fpath}")
        rel_file = fpath.relative_to(data_root).as_posix()
        is_exec = (st.st_mode & 0o111) != 0 or rel_file.endswith("/plezy") or ("/lib/" in rel_file and ".so" in fname)
        f_mode = 0o755 if is_exec else 0o644
        file_bytes += st.st_size
        entries.append((rel_file, False, fpath, f_mode, st.st_size))

installed_size = file_bytes + dir_count * 4096

ctrl_text = ctrl_path.read_text(encoding="utf-8")
if re.search(r"^Installed-Size:\s*\d+\s*$", ctrl_text, re.MULTILINE):
    ctrl_text = re.sub(
        r"^Installed-Size:\s*\d+\s*$",
        f"Installed-Size: {installed_size}",
        ctrl_text,
        count=1,
        flags=re.MULTILINE,
    )
elif re.search(r"^Architecture:.*$", ctrl_text, re.MULTILINE):
    ctrl_text = re.sub(
        r"^(Architecture:.*)$",
        rf"\1\nInstalled-Size: {installed_size}",
        ctrl_text,
        count=1,
        flags=re.MULTILINE,
    )
else:
    ctrl_text = ctrl_text.rstrip("\n") + f"\nInstalled-Size: {installed_size}\n"
if not ctrl_text.endswith("\n"):
    ctrl_text += "\n"
ctrl_bytes = ctrl_text.encode("utf-8")
ctrl_path.write_bytes(ctrl_bytes)

ctrl_tar_buf = io.BytesIO()
with tarfile.open(fileobj=ctrl_tar_buf, mode="w:", format=tarfile.USTAR_FORMAT) as tf:
    add_ustar_file(tf, "control", ctrl_bytes, 0o644)
ctrl_tar_raw = ctrl_tar_buf.getvalue()
assert ctrl_tar_raw[257:263] == b"ustar\x00", "control tar is not POSIX ustar"
control_tgz = gzip_unix_bytes(ctrl_tar_raw)
(ipk_extract / "control.tar.gz").write_bytes(control_tgz)

data_tar_buf = io.BytesIO()
with tarfile.open(fileobj=data_tar_buf, mode="w:", format=tarfile.USTAR_FORMAT) as tf:
    for arcname, is_dir, fpath, mode, _size in entries:
        if is_dir:
            add_ustar_dir(tf, arcname, mode)
        else:
            add_ustar_file(tf, arcname, fpath.read_bytes(), mode)
data_tar_raw = data_tar_buf.getvalue()
assert data_tar_raw[257:263] == b"ustar\x00", "data tar is not POSIX ustar"
data_tgz = gzip_unix_bytes(data_tar_raw)
(ipk_extract / "data.tar.gz").write_bytes(data_tgz)

debian_binary = b"2.0\n"
(ipk_extract / "debian-binary").write_bytes(debian_binary)

ar_chunks = [b"!<arch>\n"]
for name, payload in (
    ("debian-binary", debian_binary),
    ("control.tar.gz", control_tgz),
    ("data.tar.gz", data_tgz),
):
    hdr = (
        name.encode("ascii").ljust(16)
        + str(ipk_mtime).encode("ascii").ljust(12)
        + b"0".ljust(6)
        + b"0".ljust(6)
        + b"100644".ljust(8)
        + str(len(payload)).encode("ascii").ljust(10)
        + b"`\n"
    )
    assert len(hdr) == 60
    ar_chunks.append(hdr)
    ar_chunks.append(payload)
    if len(payload) % 2:
        ar_chunks.append(b"\n")

ipk_bytes = b"".join(ar_chunks)
out_path.write_bytes(ipk_bytes)

# Self-verify generated IPK structure against LG pkgverifier requirements.
raw = out_path.read_bytes()
assert raw[:8] == b"!<arch>\n"
pos = 8
parsed = {}
order = []
while pos < len(raw):
    hdr = raw[pos:pos + 60]
    assert len(hdr) == 60 and hdr[58:60] == b"`\n"
    raw_name = hdr[:16].decode("ascii").rstrip(" ")
    assert "/" not in raw_name, f"unexpected slash in ar member name: {raw_name!r}"
    ar_date = int(hdr[16:28].decode("ascii").strip())
    ar_mode = hdr[40:48].decode("ascii").strip()
    ar_size = int(hdr[48:58].decode("ascii").strip())
    assert ar_date == ipk_mtime and ar_date > 0
    assert ar_mode == "100644", f"unexpected ar mode {ar_mode!r} on {raw_name}"
    order.append(raw_name)
    parsed[raw_name] = raw[pos + 60:pos + 60 + ar_size]
    pos += 60 + ar_size + (ar_size % 2)
assert pos == len(raw)
assert order == ["debian-binary", "control.tar.gz", "data.tar.gz"], f"unexpected ar order {order}"
assert parsed["debian-binary"] == b"2.0\n"

with tarfile.open(fileobj=io.BytesIO(gzip.decompress(parsed["control.tar.gz"])), mode="r:") as tf:
    cm = tf.getmembers()
    assert [m.name for m in cm] == ["control"], f"unexpected control tar entries {[m.name for m in cm]}"
    assert cm[0].mtime == ipk_mtime and not cm[0].pax_headers
    ctext = tf.extractfile(cm[0]).read().decode("utf-8")
    m_size = re.search(r"^Installed-Size:\s*(\d+)$", ctext, re.MULTILINE)
    assert m_size and int(m_size.group(1)) == installed_size and installed_size >= file_bytes

with tarfile.open(fileobj=io.BytesIO(gzip.decompress(parsed["data.tar.gz"])), mode="r:") as tf:
    dm = tf.getmembers()
    names = {m.name: m for m in dm}
    for m in dm:
        assert m.name.startswith("usr"), f"bad tar path {m.name!r}"
        assert not m.pax_headers, f"PAX header present on {m.name!r}"
        assert 0 < m.mtime <= ipk_mtime
    for required in (
        f"usr/palm/applications/{app_id}/appinfo.json",
        f"usr/palm/packages/{app_id}/packageinfo.json",
        f"usr/palm/applications/{app_id}/plezy",
        f"usr/palm/applications/{app_id}/lib/libwebos_compat32.so",
        f"usr/palm/applications/{app_id}/lib/libsqlite3_dart.so",
        f"usr/palm/applications/{app_id}/lib/libstdc++.so.6",
        f"usr/palm/applications/{app_id}/data/flutter_assets/NativeAssetsManifest.json",
    ):
        assert required in names, f"missing {required} in data.tar.gz"
    assert (names[f"usr/palm/applications/{app_id}/plezy"].mode & 0o777) == 0o755
    for mname, m in names.items():
        if mname.startswith(f"usr/palm/applications/{app_id}/lib/") and ".so" in Path(mname).name and not m.isdir():
            assert (m.mode & 0o777) == 0o755, f"unexpected mode {oct(m.mode)} on {mname}"

print(
    f"Verified IPK {out_path.name}: {len(ipk_bytes)} bytes, "
    f"Installed-Size={installed_size} (files={file_bytes}, dirs={dir_count}), "
    f"entries={len(dm)}, mtime={ipk_mtime}"
)
PYEOF

echo ""
echo "=== FERTIGE PAKETE IN $OUT_DIR ==="
ls -lh "$MODERN_IPK_PATH" "$OUT_COMPAT_PATH"
