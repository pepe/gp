/* Process-scoped store ownership. The lock file is never unlinked: deleting it
 * would let another process lock a different inode under the same name. */
#include <janet.h>
#include <stdio.h>
#ifdef _WIN32
#include <windows.h>
typedef HANDLE OwnerHandle;
#define INVALID_OWNER INVALID_HANDLE_VALUE
#else
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/file.h>
#include <unistd.h>
typedef int OwnerHandle;
#define INVALID_OWNER -1
#endif

typedef struct { OwnerHandle handle; } Owner;

static int owner_gc(void *data, size_t size) {
    Owner *owner = data;
    (void) size;
    if (owner->handle != INVALID_OWNER) {
#ifdef _WIN32
        CloseHandle(owner->handle);
#else
        close(owner->handle);
#endif
        owner->handle = INVALID_OWNER;
    }
    return 0;
}

static const JanetAbstractType owner_type = {
    "gp/ownership", owner_gc, JANET_ATEND_GCMARK
};

static Janet acquire(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    const char *path = janet_getcstring(argv, 0);
    janet_sandbox_assert(JANET_SANDBOX_FS_WRITE);
#ifdef _WIN32
    /* No sharing and no inheritance: both graceful exit and a killed owner
     * release the claim in the kernel, without stale-lock recovery heuristics. */
    HANDLE handle = CreateFileA(path, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                                OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (handle == INVALID_HANDLE_VALUE)
        janet_panicf("Cannot claim store %s (Windows error %d)", path, (int) GetLastError());
#else
    int handle = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0600);
    if (handle < 0) janet_panicf("Cannot open store claim %s: %s", path, strerror(errno));
    if (flock(handle, LOCK_EX | LOCK_NB)) {
        int cause = errno;
        close(handle);
        janet_panicf("Cannot claim store %s: %s", path, strerror(cause));
    }
#endif
    Owner *owner = janet_abstract(&owner_type, sizeof(Owner));
    owner->handle = handle;
    return janet_wrap_abstract(owner);
}

static Janet release(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 1);
    Owner *owner = janet_getabstract(argv, 0, &owner_type);
    owner_gc(owner, sizeof(Owner));
    return janet_wrap_nil();
}

static Janet replace(int32_t argc, Janet *argv) {
    janet_fixarity(argc, 2);
    const char *from = janet_getcstring(argv, 0);
    const char *to = janet_getcstring(argv, 1);
    janet_sandbox_assert(JANET_SANDBOX_FS_WRITE);
#ifdef _WIN32
    if (!MoveFileExA(from, to, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
        janet_panicf("Cannot replace %s (Windows error %d)", to, (int) GetLastError());
#else
    if (rename(from, to))
        janet_panicf("Cannot replace %s: %s", to, strerror(errno));
#endif
    return janet_wrap_nil();
}

static const JanetReg functions[] = {
    {"acquire", acquire, "(ownership/acquire path)\n\nExclusively claims a stable lock file until release or process exit. Fails immediately if held."},
    {"release", release, "(ownership/release claim)\n\nReleases a process claim. Repeated release is safe; never deletes the lock file."},
    {"replace", replace, "(ownership/replace staged destination)\n\nAtomically renames a staged file over its destination on the same filesystem. Failure preserves the destination."},
    {NULL, NULL, NULL}
};

JANET_MODULE_ENTRY(JanetTable *env) {
    janet_cfuns(env, "gp/ownership", functions);
}
