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

APP_VER="$(grep -E '^version:' "$REPO_ROOT/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d'+' -f1)"
APP_VER="${APP_VER:-2.26.0}"

mkdir -p "$OUT_DIR"

ORIG_IPK="${ORIG_IPK:-$(find "$REPO_ROOT/build" -name "*.ipk" 2>/dev/null | grep -v -E "(-32bit|_webos6-24|_webos25-26)\.ipk" | head -n 1 || true)}"
if [ -z "$ORIG_IPK" ] || [ ! -f "$ORIG_IPK" ]; then
  ORIG_IPK="$OUT_DIR/com.edde746.plezy_${APP_VER}_arm_webos25-26.ipk"
fi

if [ ! -f "$ORIG_IPK" ]; then
  echo "ERROR: Basis-IPK nicht gefunden. Bitte zuerst 'flutter-webos build webos --release' ausfuehren."
  exit 1
fi

MODERN_IPK_PATH="$OUT_DIR/com.edde746.plezy_${APP_VER}_arm_webos25-26.ipk"
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

#define EXPORT __attribute__((used, visibility("default")))
#define RTLD_NEXT ((void *)-1L)
#define RTLD_LAZY 0x00001
#define _STAT_VER_LINUX 3
#define WL_MARSHAL_FLAG_DESTROY 1
#define CLOCK_REALTIME 0
#define CLOCK_MONOTONIC 1
#define EINVAL 22

typedef struct _IO_FILE FILE;
typedef void *locale_t;

struct compat_timespec {
    long tv_sec;
    long tv_nsec;
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
extern int close(int fd);

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

static const char *get_writable_appdata_dir(void) {
    static const char *cached_dir = 0;
    if (cached_dir) return cached_dir;

    make_dir_writable("/media/developer/temp");
    make_dir_writable("/media/developer/temp/plezy_appdata");
    if (access("/media/developer/temp/plezy_appdata", 7) == 0) {
        make_dir_writable("/media/developer/temp/plezy_appdata/com.edde746.plezy");
        make_dir_writable("/media/developer/temp/plezy_appdata/.cache");
        make_dir_writable("/media/developer/temp/plezy_appdata/.cache/com.edde746.plezy");
        make_dir_writable("/media/developer/temp/plezy_appdata/.data");
        make_dir_writable("/media/developer/temp/plezy_appdata/.data/com.edde746.plezy");
        make_dir_writable("/media/developer/temp/plezy_appdata/.download");
        make_dir_writable("/media/developer/temp/plezy_appdata/.download/com.edde746.plezy");
        make_dir_writable("/media/developer/temp/plezy_appdata/log");
        cached_dir = "/media/developer/temp/plezy_appdata";
        return cached_dir;
    }

    make_dir_writable("/tmp/plezy_appdata");
    make_dir_writable("/tmp/plezy_appdata/com.edde746.plezy");
    make_dir_writable("/tmp/plezy_appdata/.cache");
    make_dir_writable("/tmp/plezy_appdata/.cache/com.edde746.plezy");
    make_dir_writable("/tmp/plezy_appdata/.data");
    make_dir_writable("/tmp/plezy_appdata/.data/com.edde746.plezy");
    make_dir_writable("/tmp/plezy_appdata/.download");
    make_dir_writable("/tmp/plezy_appdata/.download/com.edde746.plezy");
    make_dir_writable("/tmp/plezy_appdata/log");
    cached_dir = "/tmp/plezy_appdata";
    return cached_dir;
}

static const char *get_writable_cache_dir(void) {
    const char *base = get_writable_appdata_dir();
    if (strcmp(base, "/media/developer/temp/plezy_appdata") == 0) {
        return "/media/developer/temp/plezy_appdata/.cache";
    }
    return "/tmp/plezy_appdata/.cache";
}

static const char *get_writable_download_dir(void) {
    const char *base = get_writable_appdata_dir();
    if (strcmp(base, "/media/developer/temp/plezy_appdata") == 0) {
        return "/media/developer/temp/plezy_appdata/.download";
    }
    return "/tmp/plezy_appdata/.download";
}

static const char *get_writable_log_dir(void) {
    const char *base = get_writable_appdata_dir();
    if (strcmp(base, "/media/developer/temp/plezy_appdata") == 0) {
        return "/media/developer/temp/plezy_appdata/log";
    }
    return "/tmp/plezy_appdata/log";
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
    typedef int (*setenv_fn_t)(const char *, const char *, int);
    setenv_fn_t real_setenv = (setenv_fn_t)resolve_libc_sym("setenv");
    if (!real_setenv) return -1;

    const char *mapped = map_env_var(name);
    if (mapped) {
        return real_setenv(name, mapped, 1);
    }
    return real_setenv(name, value, overwrite);
}

EXPORT char *getenv(const char *name) {
    typedef char *(*getenv_fn_t)(const char *);
    getenv_fn_t real_getenv = (getenv_fn_t)resolve_libc_sym("getenv");

    if (name) {
        const char *mapped = map_env_var(name);
        if (mapped) {
            return (char *)mapped;
        }
        if (strcmp(name, "APP_ID") == 0 || strcmp(name, "FLUTTER_APP_ID") == 0) {
            char *val = real_getenv ? real_getenv(name) : 0;
            if (!val || !val[0]) return "com.edde746.plezy";
            return val;
        }
    }
    return real_getenv ? real_getenv(name) : 0;
}

__attribute__((constructor))
static void init_webos_compat32(void) {
    typedef int (*setenv_fn_t)(const char *, const char *, int);
    setenv_fn_t real_setenv = (setenv_fn_t)resolve_libc_sym("setenv");
    const char *dir = get_writable_appdata_dir();
    const char *cache_dir = get_writable_cache_dir();
    const char *dl_dir = get_writable_download_dir();
    const char *log_dir = get_writable_log_dir();
    if (real_setenv && dir) {
        real_setenv("APP_ID", "com.edde746.plezy", 0);
        real_setenv("FLUTTER_APP_ID", "com.edde746.plezy", 0);
        real_setenv("FLUTTER_HOME", dir, 1);
        real_setenv("FLUTTER_APPDATA_HOME", dir, 1);
        real_setenv("FLUTTER_TEMP_HOME", cache_dir, 1);
        real_setenv("FLUTTER_DOWNLOAD_HOME", dl_dir, 1);
        real_setenv("FLUTTER_EXT_STORAGE_PATH", dir, 1);
        real_setenv("FLUTTER_APP_LOG_PATH", log_dir, 1);
        real_setenv("XDG_DATA_HOME", dir, 1);
        real_setenv("XDG_CONFIG_HOME", dir, 1);
        real_setenv("XDG_CACHE_HOME", cache_dir, 1);
    }
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
        copy_str(buf, "com.edde746.plezy", size);
        return buf;
    }
    return "com.edde746.plezy";
}

EXPORT const char *SDL_webOSCreateExportedWindow(unsigned int exportedType) {
    (void)exportedType;
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
    (void)windowID;
    (void)name;
    (void)value;
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
    if (windowId && windowId[0]) {
        copy_str(g_last_window_id, windowId, sizeof(g_last_window_id));
    }
    fn2_t f2 = (fn2_t)resolve_ndl_sym("NDL_MediaInitWithWindowId");
    if (f2) return f2(arg, windowId);
    fn1_t f1 = (fn1_t)resolve_ndl_sym("NDL_MediaInit");
    if (f1) return f1(arg);
    return 0;
}

EXPORT int NDL_MediaUnsubscribeEvents(void *handle) {
    typedef int (*fn_t)(void *);
    fn_t f = (fn_t)resolve_ndl_sym("NDL_MediaUnsubscribeEvents");
    if (f) return f(handle);
    return 0;
}

EXPORT int NDL_MediaSelectAudioTrack(int trackIndex) {
    typedef int (*fn1_t)(int);
    fn1_t f1 = (fn1_t)resolve_ndl_sym("NDL_MediaSelectAudioTrack");
    if (f1) return f1(trackIndex);
    fn1_t f2 = (fn1_t)resolve_ndl_sym("NDL_MediaSelectTrack");
    if (f2) return f2(trackIndex);
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
  -fuse-ld=lld -shared -fPIC -O2 -nostdlib -fno-stack-protector \
  -Wl,-soname,libwebos_compat32.so \
  "$STAGE_DIR/webos_compat32.c" \
  -o "$APP_DIR/lib/libwebos_compat32.so"
chmod 0755 "$APP_DIR/lib/libwebos_compat32.so"
patchelf --set-rpath '$ORIGIN' --force-rpath "$APP_DIR/lib/libwebos_compat32.so"
patchelf --add-needed librt.so.1 "$APP_DIR/lib/libwebos_compat32.so"
patchelf --add-needed libpthread.so.0 "$APP_DIR/lib/libwebos_compat32.so"
patchelf --add-needed libdl.so.2 "$APP_DIR/lib/libwebos_compat32.so"
patchelf --add-needed libc.so.6 "$APP_DIR/lib/libwebos_compat32.so"

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
  local filtered
  filtered="$(printf '%s\n' $existing | grep -v -E '^(libwebos_compat32\.so|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1)$' || true)"
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

REMAP_TO_GLIBC_2_4 = {
    "dladdr", "dlclose", "dlerror", "dlopen", "dlsym",
    "exp", "exp2", "fmod", "fmodf", "hypot", "hypotf", "log", "log2", "pow",
    "pthread_attr_getstack", "pthread_attr_setstacksize",
    "pthread_condattr_setclock", "pthread_create", "pthread_detach",
    "pthread_getattr_np", "pthread_getspecific", "pthread_join",
    "pthread_key_create", "pthread_key_delete", "pthread_mutex_trylock",
    "pthread_mutexattr_destroy", "pthread_mutexattr_init", "pthread_mutexattr_settype",
    "pthread_once", "pthread_rwlock_destroy", "pthread_rwlock_init",
    "pthread_rwlock_rdlock", "pthread_rwlock_unlock", "pthread_rwlock_wrlock",
    "pthread_setspecific", "pthread_sigmask",
    "sem_destroy", "sem_init", "sem_post", "sem_trywait", "sem_wait",
    "shm_open", "shm_unlink",
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

            if sym_name in UNVERSION_SYMBOLS or sym_name.startswith("__isoc23_"):
                struct.pack_into("<H", data, vs_off + sym_idx * 2, 1)
                modified = True
            elif sym_name in REMAP_TO_GLIBC_2_4 and ver_name != "GLIBC_2.4":
                target_ndx = file_ver_to_ndx.get((vn_file, "GLIBC_2.4")) or file_ver_to_ndx.get(("libc.so.6", "GLIBC_2.4"))
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
                if raw_ndx in used_indices or a["ver_name"] not in DISALLOWED_GLIBC_VERSIONS:
                    # Drop unused GLIBC >= 2.29 entries, keep <= 2.28 or actually used entries
                    if a["ver_name"] in DISALLOWED_GLIBC_VERSIONS and raw_ndx not in used_indices:
                        removed_any_aux = True
                    elif raw_ndx not in used_indices and a["ver_name"].startswith("GLIBC_") and a["ver_name"] != "GLIBC_2.4":
                        removed_any_aux = True
                    else:
                        kept_aux.append(a)
                else:
                    removed_any_aux = True
            if kept_aux:
                kept_groups.append({**grp, "aux": kept_aux})
            else:
                removed_any_aux = True

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
PYEOF

rm -rf "$APP_DIR/appdata/"* "$APP_DIR/appdata/".* 2>/dev/null || true
chmod 0777 "$APP_DIR/appdata" 2>/dev/null || true

echo "=== [7/7] Baue kompatibles Paket (SysV ar + POSIX ustar): com.edde746.plezy_${APP_VER}_arm_webos6-24.ipk ==="
mkdir -p "$STAGE_DIR/ctrl_extract"
tar -xzf "$STAGE_DIR/ipk_extract/control.tar.gz" -C "$STAGE_DIR/ctrl_extract"

OUT_COMPAT_PATH="$OUT_DIR/com.edde746.plezy_${APP_VER}_arm_webos6-24.ipk"
rm -f "$OUT_COMPAT_PATH"

python3 - "$STAGE_DIR" "$OUT_COMPAT_PATH" << 'PYEOF'
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
        is_exec = (st.st_mode & 0o111) != 0 or rel_file.endswith("/plezy")
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
        "usr/palm/applications/com.edde746.plezy/appinfo.json",
        "usr/palm/packages/com.edde746.plezy/packageinfo.json",
        "usr/palm/applications/com.edde746.plezy/plezy",
        "usr/palm/applications/com.edde746.plezy/lib/libwebos_compat32.so",
        "usr/palm/applications/com.edde746.plezy/lib/libsqlite3_dart.so",
        "usr/palm/applications/com.edde746.plezy/lib/libstdc++.so.6",
        "usr/palm/applications/com.edde746.plezy/data/flutter_assets/NativeAssetsManifest.json",
    ):
        assert required in names, f"missing {required} in data.tar.gz"
    assert (names["usr/palm/applications/com.edde746.plezy/plezy"].mode & 0o777) == 0o755

print(
    f"Verified IPK {out_path.name}: {len(ipk_bytes)} bytes, "
    f"Installed-Size={installed_size} (files={file_bytes}, dirs={dir_count}), "
    f"entries={len(dm)}, mtime={ipk_mtime}"
)
PYEOF

echo ""
echo "=== FERTIGE PAKETE IN $OUT_DIR ==="
ls -lh "$MODERN_IPK_PATH" "$OUT_COMPAT_PATH"
