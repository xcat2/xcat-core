/* The target uses native chroot and anonymous shared mappings. */
#if !defined(__FreeBSD__) || !defined(XCAT_PKG_TARGET_VERSION) || XCAT_PKG_TARGET_VERSION != 20602
#define _XOPEN_SOURCE 700
#endif

#include <sys/stat.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <locale.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pkg.h>

#ifndef XCAT_PKG_TARGET_VERSION
#define XCAT_PKG_TARGET_VERSION 20802
#endif

#if XCAT_PKG_TARGET_VERSION == 20802
#define EXPECTED_PKG_VERSION "2.8.2"
#elif XCAT_PKG_TARGET_VERSION == 20602
#define EXPECTED_PKG_VERSION "2.6.2"
#else
#error "Unsupported XCAT_PKG_TARGET_VERSION"
#endif

#define MAX_REQUEST_BYTES 8388608U
#define MAX_NAMES 8192U
#define MAX_NAME_BYTES 4096U

struct request {
    char *bytes;
    char *names[MAX_NAMES];
    size_t count;
};

struct selected {
    struct pkg *package;
    const char *repository;
};

static int
error(const char *message)
{
    fprintf(stderr, "FreeBSD resolver: %s\n", message);
    return -1;
}

static int
empty_root(DIR *directory, const char *path, const struct stat *original)
{
    struct stat opened, named;
    if (fstat(dirfd(directory), &opened) != 0 || lstat(path, &named) != 0 ||
        !S_ISDIR(named.st_mode) || opened.st_dev != original->st_dev ||
        opened.st_ino != original->st_ino || named.st_dev != opened.st_dev ||
        named.st_ino != opened.st_ino || opened.st_uid != 0 ||
        opened.st_gid != original->st_gid || opened.st_mode != original->st_mode)
        return error("resolver root changed during inspection");
    rewinddir(directory);
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (entry == NULL)
            return errno == 0 ? 0 : error("cannot read resolver root");
        if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0)
            return error("resolver root must be empty");
    }
}

static DIR *
open_directory(const char *path, struct stat *original, bool require_empty)
{
    char *canonical = realpath(path, NULL);
    DIR *directory = NULL;
    if (canonical == NULL || path[0] != '/' || path[1] == '\0' ||
        strcmp(canonical, path) != 0) {
        error("resolver root must be an absolute canonical directory");
        goto done;
    }
    struct stat ancestor;
    if (lstat("/", &ancestor) != 0 || !S_ISDIR(ancestor.st_mode) ||
        ancestor.st_uid != 0 || ((ancestor.st_mode & 0022) != 0 &&
            (ancestor.st_mode & S_ISVTX) == 0)) {
        error("resolver root path must be protected and root-owned");
        goto done;
    }
    for (char *end = canonical + 1;; end++) {
        if (*end != '/' && *end != '\0')
            continue;
        bool final = *end == '\0';
        char saved = *end;
        *end = '\0';
        struct stat state;
        int status = lstat(canonical, &state);
        *end = saved;
        if (status != 0 || !S_ISDIR(state.st_mode) || state.st_uid != 0 ||
            (final && (state.st_mode & (S_ISUID | S_ISGID | S_ISVTX)) != 0) ||
            ((state.st_mode & 0022) != 0 &&
                (final || (state.st_mode & S_ISVTX) == 0))) {
            error("resolver root path must be protected and root-owned");
            goto done;
        }
        if (final)
            break;
    }
    int fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) {
        error("cannot open resolver root");
        goto done;
    }
    if (fstat(fd, original) != 0 || !S_ISDIR(original->st_mode) ||
        original->st_uid != 0 ||
        (original->st_mode & (0022 | S_ISUID | S_ISGID | S_ISVTX)) != 0) {
        error("resolver root must be protected and root-owned");
        close(fd);
        goto done;
    }
    directory = fdopendir(fd);
    if (directory == NULL) {
        error("cannot inspect resolver root");
        close(fd);
        goto done;
    }
    if (require_empty && empty_root(directory, path, original) != 0) {
        closedir(directory);
        directory = NULL;
    }
done:
    free(canonical);
    return directory;
}

static DIR *
open_root(const char *path, struct stat *original)
{
    return open_directory(path, original, true);
}

static int
events(void *data, struct pkg_event *event)
{
    bool *failed = data;
    if (failed != NULL && (event->type == PKG_EVENT_ERROR ||
        event->type == PKG_EVENT_ERRNO || event->type == PKG_EVENT_MISSING_DEP))
        *failed = true;
    if (event->type == PKG_EVENT_ERROR)
        fprintf(stderr, "FreeBSD resolver: %s\n",
            event->e_pkg_error.msg != NULL ? event->e_pkg_error.msg : "native package error");
    if (event->type == PKG_EVENT_ERRNO)
        fprintf(stderr, "FreeBSD resolver: %s(%s): %s\n",
            event->e_errno.func != NULL ? event->e_errno.func : "native package operation",
            event->e_errno.arg != NULL ? event->e_errno.arg : "", strerror(event->e_errno.no));
    if (event->type == PKG_EVENT_MISSING_DEP && event->e_missing_dep.dep != NULL) {
        const char *name = NULL;
        if (event->e_missing_dep.pkg != NULL)
            pkg_get(event->e_missing_dep.pkg, PKG_ATTR_NAME, &name);
        const char *dependency = pkg_dep_name(event->e_missing_dep.dep);
        const char *version = pkg_dep_version(event->e_missing_dep.dep);
        fprintf(stderr, "FreeBSD resolver: missing dependency %s-%s required by %s\n",
            dependency != NULL ? dependency : "(unknown)",
            version != NULL ? version : "(unknown)", name != NULL ? name : "(unknown)");
    }
    return 0;
}

static bool
valid_name(const unsigned char *name, size_t length)
{
    if (length == 0 || length > MAX_NAME_BYTES)
        return false;
    for (size_t i = 0; i < length;) {
        unsigned char c = name[i++];
        if (c < 0x20 || c == 0x7f)
            return false;
        if (c < 0x80)
            continue;
        uint32_t code;
        uint32_t minimum;
        size_t remaining;
        if (c >= 0xc2 && c <= 0xdf) {
            code = c & 0x1f;
            minimum = 0x80;
            remaining = 1;
        } else if (c >= 0xe0 && c <= 0xef) {
            code = c & 0x0f;
            minimum = 0x800;
            remaining = 2;
        } else if (c >= 0xf0 && c <= 0xf4) {
            code = c & 0x07;
            minimum = 0x10000;
            remaining = 3;
        } else {
            return false;
        }
        if (remaining > length - i)
            return false;
        while (remaining-- != 0) {
            c = name[i++];
            if ((c & 0xc0) != 0x80)
                return false;
            code = (code << 6) | (c & 0x3f);
        }
        if (code < minimum || code > 0x10ffff ||
            (code >= 0xd800 && code <= 0xdfff))
            return false;
    }
    return true;
}

static int
read_request(const char *path, struct request *request)
{
    int fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0)
        return error("cannot open request file");
    struct stat state;
    int result = -1;
    if (fstat(fd, &state) != 0 || !S_ISREG(state.st_mode) ||
        state.st_size <= 0 || state.st_size > MAX_REQUEST_BYTES) {
        error("request must be a bounded nonempty regular file");
        goto done;
    }
    request->bytes = malloc(MAX_REQUEST_BYTES + 1);
    if (request->bytes == NULL) {
        error("cannot allocate request buffer");
        goto done;
    }
    size_t length = 0;
    for (;;) {
        ssize_t received = read(fd, request->bytes + length,
            MAX_REQUEST_BYTES + 1 - length);
        if (received < 0 && errno == EINTR)
            continue;
        if (received < 0) {
            error("cannot read request file");
            goto done;
        }
        if (received == 0)
            break;
        length += (size_t)received;
        if (length > MAX_REQUEST_BYTES) {
            error("request exceeds its byte limit");
            goto done;
        }
    }
    if (length != (size_t)state.st_size || request->bytes[length - 1] != '\n') {
        error("request changed or lacks its final newline");
        goto done;
    }
    size_t start = 0;
    for (size_t i = 0; i < length; i++) {
        if (request->bytes[i] != '\n')
            continue;
        if (request->count == MAX_NAMES ||
            !valid_name((unsigned char *)request->bytes + start, i - start)) {
            error("invalid package name or too many request records");
            goto done;
        }
        request->bytes[i] = '\0';
        request->names[request->count++] = request->bytes + start;
        start = i + 1;
    }
    result = 0;
done:
    if (close(fd) != 0)
        result = error("cannot close request file");
    return result;
}

static bool
archive_selector(const char *name)
{
    if (strcmp(name, "-") == 0)
        return true;
    const char *dot = strrchr(name, '.');
    if (dot == NULL)
        return false;
    return strcmp(dot, ".pkg") == 0 || strcmp(dot, ".tzst") == 0 ||
        strcmp(dot, ".txz") == 0 || strcmp(dot, ".tbz") == 0 ||
        strcmp(dot, ".tgz") == 0 || strcmp(dot, ".tar") == 0;
}

static char *
literal_regex(const char *name)
{
    char *pattern = malloc(strlen(name) * 9 + 3);
    if (pattern == NULL)
        return NULL;
    char *p = pattern;
    *p++ = '^';
    for (const unsigned char *n = (const unsigned char *)name; *n; n++) {
        if (*n == '/') {
            /* A literal slash makes libpkg query origins instead of package names. */
            const unsigned char slash[] = {'[', '^', 1, '-', '.', '0', '-', 255, ']'};
            memcpy(p, slash, sizeof(slash));
            p += sizeof(slash);
        } else {
            if (strchr(".^$[]\\*+?{}()|", *n) != NULL)
                *p++ = '\\';
            *p++ = *n;
        }
    }
    *p++ = '$';
    *p = '\0';
    return pattern;
}

static int
add_name(struct pkgdb *db, struct pkg_jobs *jobs, const char *name)
{
    bool regex = archive_selector(name);
    char *pattern = regex ? literal_regex(name) : (char *)name;
    struct pkg *candidate = NULL;
    struct pkgdb_it *query = NULL;
    int result = -1;
    if (pattern == NULL)
        return error("cannot allocate selector");
    match_t match = regex ? MATCH_REGEX : MATCH_INTERNAL;
    query = pkgdb_repo_query(db, pattern, match, NULL);
    if (query == NULL) {
        error("cannot query root candidates");
        goto done;
    }
    int status;
    size_t count = 0;
    while ((status = pkgdb_it_next(query, &candidate, PKG_LOAD_BASIC)) == EPKG_OK) {
        const char *found = NULL;
        pkg_get(candidate, PKG_ATTR_NAME, &found);
        /* Regex queries also match name-version aliases, which must not become extra roots. */
        if (found == NULL || strcmp(found, name) != 0) {
            error("ambiguous package name selector");
            goto done;
        }
        count++;
    }
    if (status != EPKG_END || count == 0) {
        error("literal package name not found");
        goto done;
    }
    if (pkg_jobs_add(jobs, match, &pattern, 1) != EPKG_OK) {
        error("cannot add package request");
        goto done;
    }
    result = 0;
done:
    pkg_free(candidate);
    if (query != NULL)
        pkgdb_it_free(query);
    if (regex)
        free(pattern);
    return result;
}

static bool
valid_repository(const char *name)
{
    if (name == NULL || name[0] != 'r')
        return false;
    size_t length = strlen(name);
    if (length == 2)
        return name[1] >= '0' && name[1] <= '9';
    return length == 3 && ((name[1] >= '1' && name[1] <= '2' &&
        name[2] >= '0' && name[2] <= '9') ||
        (name[1] == '3' && name[2] >= '0' && name[2] <= '1'));
}

static int
compare_names(const void *left, const void *right)
{
    return strcmp(*(const char *const *)left, *(const char *const *)right);
}

static int
check_requirements(const struct selected *selected, size_t count,
    pkg_list provided_list, pkg_attr provided_attr, pkg_attr required_attr,
    const char *missing)
{
    const char **provided = NULL;
    size_t expected = 0, used = 0;
    int result = -1;
    for (size_t i = 0; i < count; i++) {
        int entries = pkg_list_count(selected[i].package, provided_list);
        if (entries < 0 || (size_t)entries > SIZE_MAX / sizeof(*provided) - expected)
            return error("invalid native provider count");
        expected += (size_t)entries;
    }
    if (expected != 0) {
        provided = malloc(expected * sizeof(*provided));
        if (provided == NULL)
            return error("cannot allocate selected providers");
    }
    for (size_t i = 0; i < count; i++) {
        struct pkg_stringlist *list = NULL;
        pkg_get(selected[i].package, provided_attr, &list);
        if (list == NULL) {
            error("missing native provider metadata");
            goto done;
        }
        struct pkg_stringlist_iterator *iterator = pkg_stringlist_iterator(list);
        const char *name;
        bool invalid = false;
        while ((name = pkg_stringlist_next(iterator)) != NULL) {
            if (name[0] == '\0' || used >= expected) {
                invalid = true;
                break;
            }
            provided[used++] = name;
        }
        free(iterator);
        free(list);
        if (invalid) {
            error("invalid native provider metadata");
            goto done;
        }
    }
    if (used != expected) {
        error("native provider count changed");
        goto done;
    }
    if (used > 1)
        qsort(provided, used, sizeof(*provided), compare_names);
    for (size_t i = 0; i < count; i++) {
        struct pkg_stringlist *list = NULL;
        pkg_get(selected[i].package, required_attr, &list);
        if (list == NULL) {
            error("missing native requirement metadata");
            goto done;
        }
        struct pkg_stringlist_iterator *iterator = pkg_stringlist_iterator(list);
        const char *name;
        bool absent = false;
        while ((name = pkg_stringlist_next(iterator)) != NULL) {
            if (name[0] == '\0' || used == 0 ||
                bsearch(&name, provided, used, sizeof(*provided), compare_names) == NULL) {
                absent = true;
                break;
            }
        }
        free(iterator);
        free(list);
        if (absent) {
            error(missing);
            goto done;
        }
    }
    result = 0;
done:
    free(provided);
    return result;
}

static int
check_selected_requirements(const struct selected *selected, size_t count)
{
    if (check_requirements(selected, count, PKG_SHLIBS_PROVIDED,
        PKG_ATTR_SHLIBS_PROVIDED, PKG_ATTR_SHLIBS_REQUIRED,
        "selected packages lack a required shared-library provider") != 0)
        return -1;
    return check_requirements(selected, count, PKG_PROVIDES,
        PKG_ATTR_PROVIDES, PKG_ATTR_REQUIRES,
        "selected packages lack a required capability provider");
}

static int
emit_jobs(struct pkg_jobs *jobs)
{
    int expected = pkg_jobs_count(jobs);
    if (expected <= 0 || expected > (int)MAX_NAMES)
        return error("invalid selected package count");
    struct selected *selected = calloc((size_t)expected, sizeof(*selected));
    if (selected == NULL)
        return error("cannot allocate selected package list");
    struct pkg *next = NULL, *old = NULL;
    void *iterator = NULL;
    int type = -1, count = 0, result = -1;
    bool invalid = false;
    while (pkg_jobs_iter(jobs, &iterator, &next, &old, &type)) {
        const char *repository = NULL;
        if (next != NULL)
            pkg_get(next, PKG_ATTR_REPONAME, &repository);
        if (count >= expected || next == NULL || old != NULL ||
            type != PKG_SOLVED_INSTALL || !valid_repository(repository)) {
            invalid = true;
            continue;
        }
        selected[count++] = (struct selected){next, repository};
    }
    if (invalid || count != expected) {
        error("invalid native install solution");
        goto done;
    }
    if (check_selected_requirements(selected, (size_t)count) != 0)
        goto done;
    if (printf("{\"format\":\"xcat-freebsd-resolver-1\",\"version\":\"%s\",\"jobs\":[",
        pkg_libversion()) < 0)
        goto output_error;
    for (int i = 0; i < count; i++) {
        if (printf("%s{\"job_type\":\"install\",\"repository\":\"%s\",\"package\":",
            i == 0 ? "" : ",", selected[i].repository) < 0 ||
            pkg_emit_manifest_file(selected[i].package, stdout,
                PKG_MANIFEST_EMIT_COMPACT | PKG_MANIFEST_EMIT_JSON) != EPKG_OK ||
            putchar('}') == EOF)
            goto output_error;
    }
    if (puts("]}") == EOF || fflush(stdout) != 0 || ferror(stdout))
        goto output_error;
    result = 0;
    goto done;
output_error:
    error("cannot write resolver output");
done:
    free(selected);
    return result;
}

#if defined(__FreeBSD__) && XCAT_PKG_TARGET_VERSION == 20602
#include <sha256.h>
#include <sys/mman.h>
#include <inttypes.h>
#include <signal.h>
#include <strings.h>

/* Private interface from the pinned pkg 2.6.2 static library. */
int pkg_checksum_validate_fileat(int fd, const char *path, const char *sum);

#define LOCAL_LINE_BYTES 32768U
#define LOCAL_ARCHIVE_BYTES UINT64_C(17179869184)
#define LOCAL_TOTAL_BYTES UINT64_C(68719476736)
#define LOCAL_MANIFEST_BYTES UINT64_C(134217728)
#define LOCAL_MANIFEST_TOTAL_BYTES UINT64_C(536870912)
#define LOCAL_PATH_BYTES 1024U

enum local_field {
    L_ID, L_REPOSITORY, L_NAME, L_VERSION, L_ORIGIN, L_ABI, L_REPOPATH,
    L_SOURCE, L_SIZE, L_SHA256, L_NATIVE_SUM, L_FIELDS
};

struct local_record {
    char *field[L_FIELDS];
    uint64_t size;
    char *manifest_digest;
    uint64_t manifest_size;
    struct stat archive_state;
    bool seen;
};

struct local_request {
    char *bytes;
    char *plan;
    char sha256[SHA256_DIGEST_STRING_LENGTH];
    struct local_record records[MAX_NAMES];
    struct local_record *by_name[MAX_NAMES];
    size_t count;
    bool manifests;
};

static bool
local_same_file(const struct stat *a, const struct stat *b)
{
    return a->st_dev == b->st_dev && a->st_ino == b->st_ino &&
        a->st_mode == b->st_mode && a->st_uid == b->st_uid &&
        a->st_gid == b->st_gid && a->st_nlink == b->st_nlink &&
        a->st_size == b->st_size && a->st_flags == b->st_flags &&
        a->st_mtim.tv_sec == b->st_mtim.tv_sec &&
        a->st_mtim.tv_nsec == b->st_mtim.tv_nsec &&
        a->st_ctim.tv_sec == b->st_ctim.tv_sec &&
        a->st_ctim.tv_nsec == b->st_ctim.tv_nsec;
}

static bool
local_hex(const char *value)
{
    return strlen(value) == 64 && strspn(value, "0123456789abcdef") == 64;
}

static bool
local_native_sum(const char *sum)
{
    const char *alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769";
    size_t length = strlen(sum);
    if (local_hex(sum))
        return true;
    if (length < 2 || sum[1] != '$')
        return false;
    if (sum[0] == '1')
        return local_hex(sum + 2);
    if (sum[0] != '0' && sum[0] != '2' && sum[0] != '5')
        return false;
    size_t payload = sum[0] == '2' ? 103 : 52;
    if (length != payload + 2 || strspn(sum + 2, alphabet) != payload)
        return false;
    return strchr(sum[0] == '2' ? "ybnd" : "yb", sum[length - 1]) != NULL;
}

/* Inputs are sealed by the privileged caller, not by archive contents. */
static int
local_read_mode(int directory, const char *name, uint64_t limit, const char *native_sum,
    char **bytes, char digest[SHA256_DIGEST_STRING_LENGTH], struct stat *state, mode_t mode)
{
    int fd = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
    int result = -1;
    struct stat before, after, named;
    char *copy = NULL;
    if (fd < 0)
        return error("cannot open local-check input");
    if (fstat(fd, &before) != 0 || !S_ISREG(before.st_mode) ||
        before.st_uid != 0 || before.st_gid != 0 || before.st_nlink != 1 ||
        (before.st_mode & 07777) != mode || before.st_size <= 0 ||
        (uint64_t)before.st_size > limit) {
        error("invalid local-check input protection or size");
        goto done;
    }
    if (bytes != NULL) {
        copy = malloc((size_t)before.st_size + 1);
        if (copy == NULL) {
            error("cannot allocate local-check input");
            goto done;
        }
    }
    SHA256_CTX hash;
    SHA256_Init(&hash);
    unsigned char block[65536];
    uint64_t total = 0;
    for (;;) {
        ssize_t length = read(fd, block, sizeof(block));
        if (length < 0 && errno == EINTR)
            continue;
        if (length < 0) {
            error("cannot read local-check input");
            goto done;
        }
        if (length == 0)
            break;
        if ((uint64_t)length > (uint64_t)before.st_size - total) {
            error("local-check input grew during inspection");
            goto done;
        }
        SHA256_Update(&hash, block, (size_t)length);
        if (copy != NULL)
            memcpy(copy + (size_t)total, block, (size_t)length);
        total += (uint64_t)length;
    }
    if (native_sum != NULL &&
        pkg_checksum_validate_fileat(directory, name, native_sum) != 0) {
        error("local-check native archive checksum mismatch");
        goto done;
    }
    if (total != (uint64_t)before.st_size || fstat(fd, &after) != 0 ||
        fstatat(directory, name, &named, AT_SYMLINK_NOFOLLOW) != 0 ||
        !local_same_file(&before, &after) || !local_same_file(&before, &named)) {
        error("local-check input changed during inspection");
        goto done;
    }
    SHA256_End(&hash, digest);
    *state = before;
    if (copy != NULL) {
        copy[total] = '\0';
        *bytes = copy;
        copy = NULL;
    }
    result = 0;
done:
    free(copy);
    if (close(fd) != 0)
        result = error("cannot close local-check input");
    return result;
}

static int
local_read(int directory, const char *name, uint64_t limit, const char *native_sum,
    char **bytes, char digest[SHA256_DIGEST_STRING_LENGTH], struct stat *state)
{
    return local_read_mode(directory, name, limit, native_sum, bytes, digest, state, 0400);
}

static bool
local_decimal(const char *text, uint64_t *value)
{
    if (*text < '1' || *text > '9')
        return false;
    uint64_t number = 0;
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        if (*p < '0' || *p > '9' ||
            number > (LOCAL_ARCHIVE_BYTES - (*p - '0')) / 10)
            return false;
        number = number * 10 + (*p - '0');
    }
    *value = number;
    return true;
}

static bool
local_identity(const char *value)
{
    if (!valid_name((const unsigned char *)value, strlen(value)))
        return false;
    size_t characters = 0;
    for (const unsigned char *p = (const unsigned char *)value; *p; p++)
        if ((*p & 0xc0) != 0x80)
            characters++;
    return characters <= 1024;
}

static int
local_name_order(const void *left, const void *right)
{
    const struct local_record *const *a = left;
    const struct local_record *const *b = right;
    return strcmp((*a)->field[L_NAME], (*b)->field[L_NAME]);
}

/* This is a fixed invocation projection, not the canonical plan decoder. */
static int
local_parse(struct local_request *request, size_t length, bool allow_empty, bool allow_manifests)
{
    char *cursor = request->bytes;
    char *end = cursor + length;
    size_t line_number = 0;
    uint64_t total = 0, manifest_total = 0;
    if (memchr(cursor, '\0', length) != NULL || length == 0 || end[-1] != '\n')
        return error("invalid local-check request framing");
    while (cursor < end) {
        char *newline = memchr(cursor, '\n', (size_t)(end - cursor));
        if (newline == NULL || newline == cursor ||
            (size_t)(newline - cursor) > LOCAL_LINE_BYTES)
            return error("invalid local-check request line");
        *newline = '\0';
        if (line_number == 0) {
            if (allow_manifests && strcmp(cursor, "format\txcat-freebsd-local-manifests-1") == 0)
                request->manifests = true;
            else if (strcmp(cursor, "format\txcat-freebsd-local-request-1") != 0)
                return error("invalid local-check request format");
        } else if (line_number == 1) {
            if (strncmp(cursor, "plan\t", 5) != 0 || !local_hex(cursor + 5))
                return error("invalid local-check plan reference");
            request->plan = cursor + 5;
        } else {
            if (request->count == MAX_NAMES || strncmp(cursor, "package\t", 8) != 0)
                return error("invalid local-check package record");
            struct local_record *record = &request->records[request->count];
            char *field = cursor + 8;
            char *metadata[2] = {NULL, NULL};
            size_t fields = L_FIELDS + (request->manifests ? 2 : 0);
            for (size_t i = 0; i < fields; i++) {
                char *tab = strchr(field, '\t');
                if ((i + 1 < fields) != (tab != NULL))
                    return error("invalid local-check field count");
                if (tab != NULL)
                    *tab = '\0';
                if (*field == '\0')
                    return error("empty local-check field");
                for (const unsigned char *p = (const unsigned char *)field; *p; p++)
                    if (*p < 0x20 || *p == 0x7f)
                        return error("control byte in local-check field");
                if (i < L_FIELDS)
                    record->field[i] = field;
                else
                    metadata[i - L_FIELDS] = field;
                if (tab != NULL)
                    field = tab + 1;
            }
            char id[32];
            snprintf(id, sizeof(id), "p%zu", request->count);
            if (strcmp(record->field[L_ID], id) != 0 ||
                !valid_repository(record->field[L_REPOSITORY]) ||
                !local_hex(record->field[L_SHA256]) ||
                !local_native_sum(record->field[L_NATIVE_SUM]) ||
                !local_decimal(record->field[L_SIZE], &record->size))
                return error("invalid local-check package identity or digest");
            for (size_t i = L_NAME; i <= L_ABI; i++)
                if (!local_identity(record->field[i]))
                    return error("invalid local-check native identity");
            const char *abi = record->field[L_ABI];
            if (strcasecmp(abi, "FreeBSD:15:amd64") != 0 &&
                strcasecmp(abi, "FreeBSD:15:*") != 0 &&
                strcasecmp(abi, "FreeBSD:15") != 0 &&
                strcasecmp(abi, "FreeBSD:*") != 0 &&
                strcasecmp(abi, "FreeBSD") != 0)
                return error("local-check requires a supported target ABI");
            if (record->size > LOCAL_TOTAL_BYTES - total)
                return error("local-check archive set exceeds its byte limit");
            total += record->size;
            if (request->manifests) {
                if (!local_decimal(metadata[0], &record->manifest_size) ||
                    record->manifest_size > LOCAL_MANIFEST_BYTES || !local_hex(metadata[1]) ||
                    record->manifest_size > LOCAL_MANIFEST_TOTAL_BYTES - manifest_total)
                    return error("invalid local verification manifest size or digest");
                record->manifest_digest = metadata[1];
                manifest_total += record->manifest_size;
            }
            request->by_name[request->count] = record;
            request->count++;
        }
        line_number++;
        cursor = newline + 1;
    }
    if (line_number < 2 || (!allow_empty && request->count == 0))
        return error("local-check requires package records");
    qsort(request->by_name, request->count, sizeof(request->by_name[0]), local_name_order);
    for (size_t i = 1; i < request->count; i++)
        if (local_name_order(&request->by_name[i - 1], &request->by_name[i]) == 0)
            return error("duplicate local-check package name");
    return 0;
}

static int
local_archive_roster(DIR *archives, const struct local_request *request)
{
    size_t found = 0;
    rewinddir(archives);
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(archives);
        if (entry == NULL)
            return errno == 0 && found == request->count ? 0 :
                error("invalid local-check archive roster");
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        char *end = NULL;
        errno = 0;
        unsigned long id = entry->d_name[0] == 'p' ?
            strtoul(entry->d_name + 1, &end, 10) : MAX_NAMES;
        char expected[32];
        snprintf(expected, sizeof(expected), "p%lu.%s", id, request->manifests ? "manifest" : "pkg");
        if (errno != 0 || end == NULL || id >= request->count ||
            strcmp(entry->d_name, expected) != 0 || ++found > request->count)
            return error("unexpected local-check archive entry");
    }
}

static int
local_archives(DIR *archives, struct local_request *request, bool repeat)
{
    if (local_archive_roster(archives, request) != 0)
        return -1;
    for (size_t i = 0; i < request->count; i++) {
        struct local_record *record = &request->records[i];
        char name[32], digest[SHA256_DIGEST_STRING_LENGTH];
        struct stat state;
        snprintf(name, sizeof(name), "p%zu.%s", i, request->manifests ? "manifest" : "pkg");
        uint64_t limit = request->manifests ? LOCAL_MANIFEST_BYTES : LOCAL_ARCHIVE_BYTES;
        if (local_read(dirfd(archives), name, limit,
            request->manifests ? NULL : record->field[L_NATIVE_SUM], NULL, digest, &state) != 0)
            return -1;
        if ((uint64_t)state.st_size != (request->manifests ? record->manifest_size : record->size) ||
            strcmp(digest, request->manifests ? record->manifest_digest : record->field[L_SHA256]) != 0 ||
            (repeat && !local_same_file(&state, &record->archive_state)))
            return error("local-check archive size, digest or identity changed");
        record->archive_state = state;
    }
    return 0;
}

static bool
local_native_identity(struct pkg *package, const struct local_record *record)
{
    const char *name = NULL, *version = NULL, *origin = NULL, *abi = NULL;
    pkg_get(package, PKG_ATTR_NAME, &name);
    pkg_get(package, PKG_ATTR_VERSION, &version);
    pkg_get(package, PKG_ATTR_ORIGIN, &origin);
    pkg_get(package, PKG_ATTR_ABI, &abi);
    return name != NULL && version != NULL && origin != NULL && abi != NULL &&
        strcmp(name, record->field[L_NAME]) == 0 &&
        strcmp(version, record->field[L_VERSION]) == 0 &&
        strcmp(origin, record->field[L_ORIGIN]) == 0 &&
        strcmp(abi, record->field[L_ABI]) == 0;
}

static int
local_add_archives(struct pkg_jobs *jobs, const char *workspace,
    struct local_request *request)
{
    for (size_t i = 0; i < request->count; i++) {
        char path[LOCAL_PATH_BYTES];
        snprintf(path, sizeof(path), "%s/archives/p%zu.pkg", workspace, i);
        struct pkg *package = NULL;
        int status = pkg_open(&package, path, PKG_OPEN_MANIFEST_ONLY);
        bool valid = status == EPKG_OK && package != NULL &&
            pkg_type(package) == PKG_FILE && pkg_is_valid(package) == EPKG_OK &&
            local_native_identity(package, &request->records[i]);
        pkg_free(package);
        if (!valid)
            return error("local-check archive native identity mismatch");
        char *operand = path;
        if (pkg_jobs_add(jobs, MATCH_EXACT, &operand, 1) != EPKG_OK)
            return error("cannot add local-check archive");
    }
    return 0;
}

static int
local_jobs(struct pkg_jobs *jobs, struct local_request *request)
{
    if (pkg_jobs_count(jobs) != (int)request->count)
        return error("local-check job count differs from request");
    struct selected *selected = calloc(request->count, sizeof(*selected));
    if (selected == NULL)
        return error("cannot allocate selected package list");
    struct pkg *next = NULL, *old = NULL;
    void *iterator = NULL;
    size_t count = 0;
    int type = -1, result = -1;
    bool invalid = false;
    while (pkg_jobs_iter(jobs, &iterator, &next, &old, &type)) {
        const char *name = NULL;
        if (next != NULL)
            pkg_get(next, PKG_ATTR_NAME, &name);
        if (++count > request->count || next == NULL || old != NULL ||
            type != PKG_SOLVED_INSTALL || pkg_type(next) != PKG_FILE || name == NULL) {
            invalid = true;
            continue;
        }
        struct local_record key = {0};
        key.field[L_NAME] = (char *)name;
        struct local_record *key_pointer = &key;
        struct local_record **found = bsearch(&key_pointer, request->by_name,
            request->count, sizeof(request->by_name[0]), local_name_order);
        if (found == NULL || (*found)->seen || !local_native_identity(next, *found)) {
            invalid = true;
            continue;
        }
        (*found)->seen = true;
        selected[count - 1] = (struct selected){next, NULL};
    }
    if (invalid || count != request->count) {
        error("local-check jobs are not the exact file-backed request");
        goto done;
    }
    for (size_t i = 0; i < request->count; i++) {
        if (!request->records[i].seen) {
            error("local-check job omitted a requested archive");
            goto done;
        }
    }
    result = check_selected_requirements(selected, count);
done:
    free(selected);
    return result;
}

static int
local_empty_database(struct pkgdb *db)
{
    struct pkgdb_it *query = pkgdb_query(db, NULL, MATCH_ALL);
    if (query == NULL)
        return error("cannot inspect local-check database");
    struct pkg *package = NULL;
    int status = pkgdb_it_next(query, &package, PKG_LOAD_BASIC);
    pkg_free(package);
    pkgdb_it_free(query);
    return status == EPKG_END ? 0 : error("local-check database must have no packages");
}

static int
local_directory_identity(DIR *directory, const char *path, const struct stat *original)
{
    struct stat opened, named;
    if (fstat(dirfd(directory), &opened) != 0 || lstat(path, &named) != 0 ||
        !S_ISDIR(named.st_mode) || opened.st_dev != original->st_dev ||
        opened.st_ino != original->st_ino || named.st_dev != opened.st_dev ||
        named.st_ino != opened.st_ino || opened.st_mode != original->st_mode ||
        opened.st_uid != original->st_uid || opened.st_gid != original->st_gid)
        return error("local-check state directory changed");
    return 0;
}

static int
local_events(void *data, struct pkg_event *event)
{
    bool *failed = data;
    switch (event->type) {
    case PKG_EVENT_DEBUG:
    case PKG_EVENT_NOTICE:
    case PKG_EVENT_PROGRESS_START:
    case PKG_EVENT_PROGRESS_TICK:
    case PKG_EVENT_INTEGRITYCHECK_BEGIN:
    case PKG_EVENT_INTEGRITYCHECK_FINISHED:
        return 0;
    default:
        *failed = true;
        error("unexpected native event during local-check");
        return 0;
    }
}

static bool
local_environment(void)
{
    extern char **environ;
    bool path = false, locale = false;
    for (char **entry = environ; *entry != NULL; entry++) {
        if (strcmp(*entry, "PATH=/sbin:/bin:/usr/sbin:/usr/bin") == 0 && !path)
            path = true;
        else if (strcmp(*entry, "LC_ALL=C") == 0 && !locale)
            locale = true;
        else
            return false;
    }
    return path && locale;
}

/* Explicit config paths are host paths; pkg_set_rootdir does not rebase them. */
static int
local_config(int directory, const char *workspace, char digest[65], struct stat *state)
{
    char expected[8192], *actual = NULL;
    int length = snprintf(expected, sizeof(expected),
        "ABI = \"FreeBSD:15:amd64\";\nOSVERSION = 1501000;\n"
        "PKG_DBDIR = \"%s/db\";\nPKG_CACHEDIR = \"%s/cache\";\n"
        "REPOS_DIR = [];\nREPOSITORIES = {};\n"
        "REPO_AUTOUPDATE = false;\nPKG_ENABLE_PLUGINS = false;\n"
        "PKG_TRIGGERS_ENABLE = false;\nRUN_SCRIPTS = false;\n"
        "HANDLE_RC_SCRIPTS = false;\nSYSLOG = false;\nIGNORE_OSVERSION = false;\n"
        "PERMISSIVE = false;\nCASE_SENSITIVE_MATCH = true;\n"
        "PKG_ENV = {};\n", workspace, workspace);
    if (length < 0 || (size_t)length >= sizeof(expected) ||
        local_read(directory, "config", sizeof(expected) - 1, NULL,
            &actual, digest, state) != 0)
        return error("cannot read fixed local-check configuration");
    bool valid = state->st_size == length && memcmp(actual, expected, (size_t)length) == 0;
    free(actual);
    return valid ? 0 : error("local-check configuration differs from fixed profile");
}

static int
local_effective_config(const char *workspace)
{
    const char *disabled[] = {"REPO_AUTOUPDATE", "PKG_ENABLE_PLUGINS",
        "PKG_TRIGGERS_ENABLE", "RUN_SCRIPTS", "HANDLE_RC_SCRIPTS", "SYSLOG",
        "IGNORE_OSVERSION", "PERMISSIVE"};
    for (size_t i = 0; i < sizeof(disabled) / sizeof(disabled[0]); i++) {
        const pkg_object *value = pkg_config_get(disabled[i]);
        if (value == NULL || pkg_object_type(value) != PKG_BOOL || pkg_object_bool(value))
            return error("unsafe effective local-check configuration");
    }
    const char *unset[] = {"CUDF_SOLVER", "SAT_SOLVER", "EVENT_PIPE", "METALOG"};
    for (size_t i = 0; i < sizeof(unset) / sizeof(unset[0]); i++)
        if (pkg_object_string(pkg_config_get(unset[i])) != NULL)
            return error("unexpected local-check external output or solver");
    char database[LOCAL_PATH_BYTES], cache[LOCAL_PATH_BYTES];
    snprintf(database, sizeof(database), "%s/db", workspace);
    snprintf(cache, sizeof(cache), "%s/cache", workspace);
    const char *keys[] = {"PKG_DBDIR", "PKG_CACHEDIR", "ABI", "OSVERSION"};
    const char *expected[] = {database, cache, "FreeBSD:15:amd64", "1501000"};
    for (size_t i = 0; i < 4; i++) {
        const char *value = pkg_object_string(pkg_config_get(keys[i]));
        if (value == NULL || strcmp(value, expected[i]) != 0)
            return error("local-check paths or target identity changed");
    }
    return 0;
}

static int
local_result(int directory, const struct local_request *request)
{
    char receipt[512];
    int length = snprintf(receipt, sizeof(receipt),
        "format\txcat-freebsd-local-check-1\nscope\tlocal-check-only\n"
        "plan-reference\t%s\nrequest-sha256\t%s\npkg\t2.6.2\n"
        "packages\t%zu\ncomplete\tyes\n",
        request->plan, request->sha256, request->count);
    if (length < 0 || (size_t)length >= sizeof(receipt))
        return error("cannot format local-check result");
    int fd = openat(directory, "local-check.result",
        O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0)
        return error("cannot create protected local-check result");
    size_t written = 0;
    int result = -1;
    while (written < (size_t)length) {
        ssize_t size = write(fd, receipt + written, (size_t)length - written);
        if (size < 0 && errno == EINTR)
            continue;
        if (size <= 0) {
            error("cannot write local-check result");
            goto done;
        }
        written += (size_t)size;
    }
    if (fsync(fd) != 0) {
        error("cannot sync local-check result");
        goto done;
    }
    result = 0;
done:
    if (close(fd) != 0)
        result = error("cannot close local-check result");
    return result;
}

static int
local_check(const char *config, const char *request_path, const char *root_path)
{
    char workspace[LOCAL_PATH_BYTES], path[LOCAL_PATH_BYTES];
    struct stat root_state, request_state, config_state, workspace_state, archives_state;
    struct stat directory_state[3];
    const char *directory_names[] = {"db", "cache", "repos"};
    DIR *root = NULL, *archives = NULL, *directories[3] = {NULL};
    int workspace_fd = -1, result = EXIT_FAILURE;
    struct local_request *request = NULL;
    struct pkgdb *db = NULL;
    struct pkg_jobs *jobs = NULL;
    bool initialized = false, locked = false, event_failed = false;
    char config_digest[65];
    if (geteuid() != 0 || getuid() != 0 || !local_environment() ||
        strcmp(pkg_libversion(), "2.6.2") != 0 || setlocale(LC_ALL, "C") == NULL) {
        error("local-check requires root, pkg 2.6.2 and its clean environment");
        goto done;
    }
    size_t length = strlen(request_path);
    if (length <= 8 || length >= sizeof(workspace) / 2 ||
        strcmp(request_path + length - 8, "/request") != 0) {
        error("invalid local-check workspace request path");
        goto done;
    }
    memcpy(workspace, request_path, length - 8);
    workspace[length - 8] = '\0';
    if (workspace[0] != '/' || strspn(workspace,
        "/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-+") != strlen(workspace)) {
        error("local-check workspace requires a literal absolute path");
        goto done;
    }
    snprintf(path, sizeof(path), "%s/config", workspace);
    if (strcmp(path, config) != 0) {
        error("local-check config must belong to its workspace");
        goto done;
    }
    snprintf(path, sizeof(path), "%s/root", workspace);
    if (strcmp(path, root_path) != 0 || (root = open_root(root_path, &root_state)) == NULL)
        goto done;
    if (root_state.st_gid != 0 || (root_state.st_mode & 07777) != 0700) {
        error("local-check root must be mode 0700");
        goto done;
    }
    workspace_fd = open(workspace, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (workspace_fd < 0 || fstat(workspace_fd, &workspace_state) != 0 ||
        workspace_state.st_uid != 0 || workspace_state.st_gid != 0 ||
        (workspace_state.st_mode & 07777) != 0700) {
        error("local-check workspace must be root-owned mode 0700");
        goto done;
    }
    struct stat prior_result;
    if (fstatat(workspace_fd, "local-check.result", &prior_result, AT_SYMLINK_NOFOLLOW) == 0 ||
        errno != ENOENT) {
        error("local-check result must not already exist");
        goto done;
    }
    umask(0077);
    for (size_t i = 0; i < 3; i++) {
        snprintf(path, sizeof(path), "%s/%s", workspace, directory_names[i]);
        directories[i] = open_root(path, &directory_state[i]);
        if (directories[i] == NULL || directory_state[i].st_gid != 0 ||
            (directory_state[i].st_mode & 07777) != 0700) {
            error("local-check state directories must be fresh mode 0700");
            goto done;
        }
    }
    int archive_fd = openat(workspace_fd, "archives",
        O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (archive_fd < 0) {
        error("cannot open local-check archives directory");
        goto done;
    }
    archives = fdopendir(archive_fd);
    if (archives == NULL) {
        close(archive_fd);
        error("cannot inspect local-check archives directory");
        goto done;
    }
    if (fstat(dirfd(archives), &archives_state) != 0 || archives_state.st_uid != 0 ||
        archives_state.st_gid != 0 || (archives_state.st_mode & 07777) != 0500) {
        error("local-check archives directory must be root-owned mode 0500");
        goto done;
    }
    request = calloc(1, sizeof(*request));
    if (request == NULL || local_read(workspace_fd, "request", MAX_REQUEST_BYTES, NULL,
        &request->bytes, request->sha256, &request_state) != 0 ||
        local_parse(request, (size_t)request_state.st_size, false, false) != 0 ||
        local_config(workspace_fd, workspace, config_digest, &config_state) != 0 ||
        local_archives(archives, request, false) != 0)
        goto done;
    pkg_event_register(local_events, &event_failed);
    if (pkg_set_rootdir(root_path) != EPKG_OK) {
        error("cannot set local-check empty root");
        goto done;
    }
    snprintf(path, sizeof(path), "%s/repos", workspace);
    if (pkg_init(config, path) != EPKG_OK) {
        error("cannot initialize fixed local-check runtime");
        goto done;
    }
    initialized = true;
    if (event_failed || local_effective_config(workspace) != 0 || pkg_repos_total_count() != 0 ||
        pkg_repos_activated_count() != 0 ||
        pkgdb_open(&db, PKGDB_DEFAULT) != EPKG_OK) {
        error("cannot open repository-free local-check database");
        goto done;
    }
    if (pkgdb_obtain_lock(db, PKGDB_LOCK_ADVISORY) != EPKG_OK) {
        error("cannot lock local-check database");
        goto done;
    }
    locked = true;
    if (local_empty_database(db) != 0 ||
        pkg_jobs_new(&jobs, PKG_JOBS_INSTALL, db) != EPKG_OK)
        goto done;
    pkg_jobs_set_flags(jobs, PKG_FLAG_DRY_RUN | PKG_FLAG_NOSCRIPT);
    if (local_add_archives(jobs, workspace, request) != 0 || event_failed ||
        pkg_jobs_solve(jobs) != EPKG_OK || event_failed ||
        local_jobs(jobs, request) != 0 || local_empty_database(db) != 0) {
        error("local-check native validation failed");
        goto done;
    }
    result = EXIT_SUCCESS;
done:
    pkg_jobs_free(jobs);
    if (locked && pkgdb_release_lock(db, PKGDB_LOCK_ADVISORY) != EPKG_OK)
        result = EXIT_FAILURE;
    if (db != NULL)
        pkgdb_close(db);
    if (initialized)
        pkg_shutdown();
    if (event_failed)
        result = EXIT_FAILURE;
    if (result == EXIT_SUCCESS) {
        struct stat state;
        char digest[65];
        if (fstatat(workspace_fd, ".", &state, AT_SYMLINK_NOFOLLOW) != 0 ||
            !S_ISDIR(state.st_mode) || state.st_dev != workspace_state.st_dev ||
            state.st_ino != workspace_state.st_ino || state.st_uid != 0 ||
            state.st_gid != 0 || (state.st_mode & 07777) != 0700 ||
            lstat(workspace, &state) != 0 || state.st_dev != workspace_state.st_dev ||
            state.st_ino != workspace_state.st_ino ||
            fstatat(workspace_fd, "archives", &state, AT_SYMLINK_NOFOLLOW) != 0 ||
            !local_same_file(&state, &archives_state) ||
            local_archives(archives, request, true) != 0 ||
            local_read(workspace_fd, "request", MAX_REQUEST_BYTES, NULL, NULL,
                digest, &state) != 0 || strcmp(digest, request->sha256) != 0 ||
            !local_same_file(&state, &request_state) ||
            local_config(workspace_fd, workspace, digest, &state) != 0 ||
            strcmp(digest, config_digest) != 0 || !local_same_file(&state, &config_state) ||
            empty_root(root, root_path, &root_state) != 0)
            result = EXIT_FAILURE;
        snprintf(path, sizeof(path), "%s/db", workspace);
        if (local_directory_identity(directories[0], path, &directory_state[0]) != 0)
            result = EXIT_FAILURE;
        for (size_t i = 1; i < 3; i++) {
            snprintf(path, sizeof(path), "%s/%s", workspace, directory_names[i]);
            if (empty_root(directories[i], path, &directory_state[i]) != 0)
                result = EXIT_FAILURE;
        }
    }
    for (size_t i = 0; i < 3; i++)
        if (directories[i] != NULL && closedir(directories[i]) != 0)
            result = EXIT_FAILURE;
    if (archives != NULL && closedir(archives) != 0)
        result = EXIT_FAILURE;
    if (root != NULL && closedir(root) != 0)
        result = EXIT_FAILURE;
    if (result == EXIT_SUCCESS && local_result(workspace_fd, request) != 0)
        result = EXIT_FAILURE;
    if (workspace_fd >= 0 && close(workspace_fd) != 0)
        result = EXIT_FAILURE;
    if (request != NULL)
        free(request->bytes);
    free(request);
    return result;
}
/* The caller must authorize the disk separately, after pre-begin staging. */
struct local_apply {
    char workspace[LOCAL_PATH_BYTES];
    char paths[6][LOCAL_PATH_BYTES];
    DIR *directories[6];
    struct stat states[6];
    struct stat request_state, config_state;
    char config_digest[65];
    struct local_request *request;
    bool finalize;
};

enum apply_directory { A_WORK, A_ROOT, A_ARCHIVES, A_DB, A_CACHE, A_REPOS };
enum apply_phase { A_VALIDATE, A_INSTALL, A_FINALIZE, A_READBACK };

/* A native script callback can run in a forked child. Failure is monotonic. */
struct apply_events {
    volatile sig_atomic_t failed;
    enum apply_phase phase;
    const struct local_request *request;
    size_t actions;
    unsigned char installed[MAX_NAMES];
};

static struct local_record *
apply_record(const struct local_request *request, struct pkg *package)
{
    const char *name = NULL;
    if (package == NULL)
        return NULL;
    pkg_get(package, PKG_ATTR_NAME, &name);
    if (name == NULL)
        return NULL;
    struct local_record key = {0};
    key.field[L_NAME] = (char *)name;
    struct local_record *pointer = &key;
    struct local_record **found = bsearch(&pointer, request->by_name,
        request->count, sizeof(request->by_name[0]), local_name_order);
    return found != NULL && local_native_identity(package, *found) ? *found : NULL;
}

static int
apply_event(void *data, struct pkg_event *event)
{
    struct apply_events *state = data;
    struct pkg *package = NULL;
    unsigned char bit = 0;
    switch (event->type) {
    case PKG_EVENT_DEBUG:
    case PKG_EVENT_NOTICE:
    case PKG_EVENT_MESSAGE:
    case PKG_EVENT_PROGRESS_START:
    case PKG_EVENT_PROGRESS_TICK:
    case PKG_EVENT_INTEGRITYCHECK_BEGIN:
    case PKG_EVENT_INTEGRITYCHECK_FINISHED:
        return 0;
    case PKG_EVENT_SANDBOX_CALL:
        return pkg_handle_sandboxed_call(event->e_sandbox_call.call,
            event->e_sandbox_call.fd, event->e_sandbox_call.userdata);
    case PKG_EVENT_SANDBOX_GET_STRING:
        return pkg_handle_sandboxed_get_string(event->e_sandbox_call_str.call,
            event->e_sandbox_call_str.result, event->e_sandbox_call_str.len,
            event->e_sandbox_call_str.userdata);
    case PKG_EVENT_INSTALL_BEGIN:
        package = event->e_install_begin.pkg;
        bit = 1;
        break;
    case PKG_EVENT_INSTALL_FINISHED:
        if (event->e_install_finished.old != NULL)
            break;
        package = event->e_install_finished.pkg;
        bit = 2;
        break;
    case PKG_EVENT_EXTRACT_BEGIN:
        package = event->e_extract_begin.pkg;
        break;
    case PKG_EVENT_EXTRACT_FINISHED:
        package = event->e_extract_finished.pkg;
        break;
    case PKG_EVENT_NEW_ACTION:
        if (state->phase == A_INSTALL && event->e_action.total == state->request->count &&
            event->e_action.current == state->actions + 1 &&
            state->actions < state->request->count) {
            state->actions++;
            return 0;
        }
        break;
    case PKG_EVENT_CLEANUP_CALLBACK_REGISTER:
    case PKG_EVENT_CLEANUP_CALLBACK_UNREGISTER:
        if (state->phase == A_INSTALL)
            return 0;
        break;
    case PKG_EVENT_TRIGGERS_BEGIN:
    case PKG_EVENT_TRIGGER:
    case PKG_EVENT_TRIGGERS_FINISHED:
        if (state->phase == A_INSTALL || state->phase == A_FINALIZE)
            return 0;
        break;
    default:
        break;
    }
    struct local_record *record = apply_record(state->request, package);
    if (state->phase == A_INSTALL && record != NULL) {
        size_t index = (size_t)(record - state->request->records);
        unsigned char prior = state->installed[index];
        if ((bit == 0 || (prior & bit) == 0) && (bit != 2 || prior == 1)) {
            state->installed[index] = prior | bit;
            return 0;
        }
    }
    state->failed = 1;
    error("native local apply reported an error or an unexpected event");
    return 0;
}

static int
apply_database(struct pkgdb *db, struct local_request *request)
{
    struct pkgdb_it *query = pkgdb_query(db, NULL, MATCH_ALL);
    if (query == NULL)
        return error("cannot inspect installed package database");
    for (size_t i = 0; i < request->count; i++)
        request->records[i].seen = false;
    struct pkg *package = NULL;
    size_t count = 0;
    int status;
    bool valid = true;
    while ((status = pkgdb_it_next(query, &package, PKG_LOAD_BASIC)) == EPKG_OK) {
        struct local_record *record = apply_record(request, package);
        if (++count > request->count || record == NULL || record->seen ||
            pkg_type(package) != PKG_INSTALLED) {
            valid = false;
            continue;
        }
        record->seen = true;
    }
    pkg_free(package);
    pkgdb_it_free(query);
    return valid && status == EPKG_END && count == request->count ? 0 :
        error("installed database differs from the complete local request");
}

static int
apply_config(struct local_apply *apply, char digest[65], struct stat *state)
{
    char expected[8192], *actual = NULL;
    const char *database = apply->finalize ? "/var/db/pkg" : apply->paths[A_DB];
    const char *cache = apply->finalize ? "/var/cache/pkg" : apply->paths[A_CACHE];
    int length = snprintf(expected, sizeof(expected),
        "ABI = \"FreeBSD:15:amd64\";\nOSVERSION = 1501000;\n"
        "PKG_DBDIR = \"%s\";\nPKG_CACHEDIR = \"%s\";\n"
        "REPOS_DIR = [];\nREPOSITORIES = {};\n"
        "REPO_AUTOUPDATE = false;\nPKG_ENABLE_PLUGINS = false;\n"
        "PKG_TRIGGERS_ENABLE = true;\nRUN_SCRIPTS = true;\n"
        "HANDLE_RC_SCRIPTS = false;\nSYSLOG = false;\nIGNORE_OSVERSION = false;\n"
        "PERMISSIVE = false;\nCASE_SENSITIVE_MATCH = true;\n"
        "PKG_ENV = {};\n", database, cache);
    int directory = dirfd(apply->directories[apply->finalize ? A_ROOT : A_WORK]);
    const char *name = apply->finalize ? "var/db/xcat/pkg-apply/config" : "config";
    if (length < 0 || (size_t)length >= sizeof(expected) ||
        local_read(directory, name, sizeof(expected) - 1, NULL,
            &actual, digest, state) != 0)
        return error("cannot read fixed local apply configuration");
    bool valid = state->st_size == length && memcmp(actual, expected, (size_t)length) == 0;
    free(actual);
    return valid ? 0 : error("local apply configuration differs from fixed profile");
}

static int
apply_effective_config(const struct local_apply *apply)
{
    const char *disabled[] = {"REPO_AUTOUPDATE", "PKG_ENABLE_PLUGINS",
        "HANDLE_RC_SCRIPTS", "SYSLOG", "IGNORE_OSVERSION", "PERMISSIVE"};
    for (size_t i = 0; i < sizeof(disabled) / sizeof(disabled[0]); i++) {
        const pkg_object *value = pkg_config_get(disabled[i]);
        if (value == NULL || pkg_object_type(value) != PKG_BOOL || pkg_object_bool(value))
            return error("unsafe effective local apply configuration");
    }
    const char *enabled[] = {"PKG_TRIGGERS_ENABLE", "RUN_SCRIPTS", "CASE_SENSITIVE_MATCH"};
    for (size_t i = 0; i < sizeof(enabled) / sizeof(enabled[0]); i++) {
        const pkg_object *value = pkg_config_get(enabled[i]);
        if (value == NULL || pkg_object_type(value) != PKG_BOOL || !pkg_object_bool(value))
            return error("required native local apply behavior is disabled");
    }
    const char *unset[] = {"CUDF_SOLVER", "SAT_SOLVER", "EVENT_PIPE", "METALOG"};
    for (size_t i = 0; i < sizeof(unset) / sizeof(unset[0]); i++)
        if (pkg_object_string(pkg_config_get(unset[i])) != NULL)
            return error("unexpected local apply external output or solver");
    const char *keys[] = {"PKG_DBDIR", "PKG_CACHEDIR", "ABI", "OSVERSION"};
    const char *expected[] = {
        apply->finalize ? "/var/db/pkg" : apply->paths[A_DB],
        apply->finalize ? "/var/cache/pkg" : apply->paths[A_CACHE],
        "FreeBSD:15:amd64", "1501000"};
    for (size_t i = 0; i < 4; i++) {
        const char *value = pkg_object_string(pkg_config_get(keys[i]));
        if (value == NULL || strcmp(value, expected[i]) != 0)
            return error("local apply paths or target identity changed");
    }
    return pkg_repos_total_count() == 0 && pkg_repos_activated_count() == 0 ? 0 :
        error("local apply must not configure repositories");
}

static bool
apply_same_directory(const struct stat *a, const struct stat *b)
{
    return S_ISDIR(a->st_mode) && a->st_dev == b->st_dev && a->st_ino == b->st_ino &&
        a->st_mode == b->st_mode && a->st_uid == b->st_uid && a->st_gid == b->st_gid;
}

/* Retained descriptors remain usable after the finalizer enters the target. */
static int
apply_inputs(struct local_apply *apply, bool inside)
{
    struct stat state;
    char digest[65];
    for (size_t i = 0; i < 6; i++) {
        if (fstat(dirfd(apply->directories[i]), &state) != 0 ||
            !apply_same_directory(&state, &apply->states[i]))
            return error("local apply directory identity changed");
        if (!inside && (lstat(apply->paths[i], &state) != 0 ||
            !apply_same_directory(&state, &apply->states[i])))
            return error("local apply directory path changed");
    }
    int work = dirfd(apply->directories[A_WORK]);
    if (fstatat(work, "archives", &state, AT_SYMLINK_NOFOLLOW) != 0 ||
        !local_same_file(&state, &apply->states[A_ARCHIVES]) ||
        local_archives(apply->directories[A_ARCHIVES], apply->request, true) != 0 ||
        local_read(work, "request", MAX_REQUEST_BYTES, NULL, NULL, digest, &state) != 0 ||
        strcmp(digest, apply->request->sha256) != 0 ||
        !local_same_file(&state, &apply->request_state) ||
        apply_config(apply, digest, &state) != 0 ||
        strcmp(digest, apply->config_digest) != 0 ||
        !local_same_file(&state, &apply->config_state))
        return error("local apply sealed input changed");
    const char *root = inside ? "/" : apply->paths[A_ROOT];
    const char *database = inside ? "/var/db/pkg" : apply->paths[A_DB];
    if (lstat(root, &state) != 0 || !apply_same_directory(&state, &apply->states[A_ROOT]) ||
        lstat(database, &state) != 0 || !apply_same_directory(&state, &apply->states[A_DB]))
        return error("local apply target or database path changed");
    return 0;
}

static int
apply_receipt_text(char *text, size_t size, const struct local_apply *apply,
    const char *scope, bool complete)
{
    int length = snprintf(text, size,
        "format\txcat-freebsd-local-apply-1\nscope\t%s\n"
        "plan-reference\t%s\nrequest-sha256\t%s\npkg\t2.6.2\n"
        "packages\t%zu\ntarget-device\t%ju\ntarget-inode\t%ju\ncomplete\t%s\n",
        scope, apply->request->plan, apply->request->sha256, apply->request->count,
        (uintmax_t)apply->states[A_ROOT].st_dev, (uintmax_t)apply->states[A_ROOT].st_ino,
        complete ? "yes" : "no");
    return length > 0 && (size_t)length < size ? length :
        error("cannot format local apply record");
}

static int
apply_record_write(int directory, const char *name, const char *text, size_t length)
{
    int fd = openat(directory, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0)
        return error("cannot create exclusive local apply record");
    size_t written = 0;
    int result = -1;
    while (written < (size_t)length) {
        ssize_t count = write(fd, text + written, (size_t)length - written);
        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0) {
            error("cannot write local apply record");
            goto done;
        }
        written += (size_t)count;
    }
    if (fsync(fd) == 0)
        result = 0;
    else
        error("cannot sync local apply record");
done:
    if (close(fd) != 0 || fsync(directory) != 0)
        result = error("cannot close or persist local apply record");
    return result;
}

static int
apply_write(const struct local_apply *apply, const char *scope, bool complete)
{
    char name[64], text[768];
    int length = apply_receipt_text(text, sizeof(text), apply, scope, complete);
    if (length < 0)
        return -1;
    snprintf(name, sizeof(name), "%s.%s", scope, complete ? "result" : "started");
    return apply_record_write(dirfd(apply->directories[A_WORK]), name, text, (size_t)length);
}

static int
apply_install_receipt(const struct local_apply *apply)
{
    char expected[768], digest[65], *actual = NULL;
    struct stat state;
    int length = apply_receipt_text(expected, sizeof(expected), apply, "local-install", true);
    if (length < 0 || local_read_mode(dirfd(apply->directories[A_WORK]),
        "local-install.result", sizeof(expected) - 1, NULL, &actual, digest, &state, 0600) != 0)
        return error("finalization requires a protected install result");
    bool valid = state.st_size == length && memcmp(expected, actual, (size_t)length) == 0;
    free(actual);
    return valid ? 0 : error("install result does not match finalization inputs");
}

static int
apply_absent(int directory, const char *name)
{
    struct stat state;
    if (fstatat(directory, name, &state, AT_SYMLINK_NOFOLLOW) == -1 && errno == ENOENT)
        return 0;
    return error("local apply phase has already started or has a result");
}

static int
apply_prepare(struct local_apply *apply, const char *config,
    const char *request_path, const char *root_path)
{
    size_t length = strlen(request_path), root_length = strlen(root_path);
    if (length <= 8 || length >= LOCAL_PATH_BYTES / 2 ||
        strcmp(request_path + length - 8, "/request") != 0 || root_length < 2 ||
        root_length >= LOCAL_PATH_BYTES / 2)
        return error("invalid local apply path bound");
    memcpy(apply->workspace, request_path, length - 8);
    apply->workspace[length - 8] = '\0';
    const char *alphabet = "/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-+";
    if (apply->workspace[0] != '/' || root_path[0] != '/' ||
        strspn(apply->workspace, alphabet) != strlen(apply->workspace) ||
        strspn(root_path, alphabet) != root_length ||
        (strncmp(apply->workspace, root_path, root_length) == 0 &&
            (apply->workspace[root_length] == '/' || apply->workspace[root_length] == '\0')))
        return error("local apply inputs must be literal paths outside the target");
    snprintf(apply->paths[A_WORK], LOCAL_PATH_BYTES, "%s", apply->workspace);
    snprintf(apply->paths[A_ROOT], LOCAL_PATH_BYTES, "%s", root_path);
    snprintf(apply->paths[A_ARCHIVES], LOCAL_PATH_BYTES, "%s/archives", apply->workspace);
    snprintf(apply->paths[A_DB], LOCAL_PATH_BYTES, "%s/var/db/pkg", root_path);
    snprintf(apply->paths[A_CACHE], LOCAL_PATH_BYTES, "%s/var/cache/pkg", root_path);
    snprintf(apply->paths[A_REPOS], LOCAL_PATH_BYTES, "%s/%s",
        apply->finalize ? root_path : apply->workspace,
        apply->finalize ? "var/db/xcat/pkg-apply/repos" : "repos");
    char expected[LOCAL_PATH_BYTES];
    snprintf(expected, sizeof(expected), "%s/%s",
        apply->finalize ? root_path : apply->workspace,
        apply->finalize ? "var/db/xcat/pkg-apply/config" : "config");
    if (strcmp(config, expected) != 0)
        return error("local apply configuration path differs from fixed profile");
    for (size_t i = 0; i < 6; i++) {
        apply->directories[i] = open_directory(apply->paths[i], &apply->states[i],
            i == A_REPOS || i == A_CACHE || (i == A_DB && !apply->finalize));
        mode_t mode = i == A_ARCHIVES ? 0500 :
            (i == A_DB || i == A_CACHE ? 0755 : 0700);
        if (apply->directories[i] == NULL || apply->states[i].st_gid != 0 ||
            (i != A_ROOT && (apply->states[i].st_mode & 07777) != mode))
            return error("local apply directories have invalid protection");
        if (i == A_WORK) {
            const char *scope = apply->finalize ? "local-finalize" : "local-install";
            char name[64];
            snprintf(name, sizeof(name), "%s.started", scope);
            if (apply_absent(dirfd(apply->directories[A_WORK]), name) != 0)
                return -1;
            snprintf(name, sizeof(name), "%s.result", scope);
            if (apply_absent(dirfd(apply->directories[A_WORK]), name) != 0)
                return -1;
        }
    }
    if (apply->finalize) {
        snprintf(expected, sizeof(expected), "%s/var/db/xcat/pkg-apply", root_path);
        struct stat state;
        DIR *owner = open_directory(expected, &state, false);
        if (owner == NULL)
            return -1;
        bool valid = state.st_gid == 0 && (state.st_mode & 07777) == 0700;
        if (closedir(owner) != 0 || !valid)
            return error("finalizer configuration owner is not protected");
    }
    apply->request = calloc(1, sizeof(*apply->request));
    if (apply->request == NULL || local_read(dirfd(apply->directories[A_WORK]),
        "request", MAX_REQUEST_BYTES, NULL, &apply->request->bytes,
        apply->request->sha256, &apply->request_state) != 0 ||
        local_parse(apply->request, (size_t)apply->request_state.st_size, false, false) != 0 ||
        apply_config(apply, apply->config_digest, &apply->config_state) != 0 ||
        local_archives(apply->directories[A_ARCHIVES], apply->request, false) != 0 ||
        (apply->finalize && apply_install_receipt(apply) != 0))
        return -1;
    return 0;
}

/* Native deferred files are executable input; hidden and special entries fail. */
static int
apply_queue(int database, bool require_empty, char digest[65])
{
    SHA256_CTX hash;
    SHA256_Init(&hash);
    int fd = openat(database, "triggers", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0) {
        if (errno != ENOENT)
            return error("cannot open deferred trigger queue");
        SHA256_End(&hash, digest);
        return 0;
    }
    struct stat state;
    if (fstat(fd, &state) != 0 || state.st_uid != 0 || state.st_gid != 0 ||
        (state.st_mode & (0022 | S_ISUID | S_ISGID | S_ISVTX)) != 0) {
        close(fd);
        return error("deferred trigger queue is not protected");
    }
    struct stat queue_state = state;
    DIR *queue = fdopendir(fd);
    if (queue == NULL) {
        close(fd);
        return error("cannot inspect deferred trigger queue");
    }
    size_t count = 0;
    uint64_t bytes = 0;
    int result = -1;
    char **names = calloc(MAX_NAMES, sizeof(*names));
    if (names == NULL) {
        closedir(queue);
        return error("cannot allocate deferred trigger roster");
    }
    for (;;) {
        errno = 0;
        struct dirent *entry = readdir(queue);
        if (entry == NULL) {
            if (errno == 0)
                result = 0;
            else
                error("cannot read deferred trigger queue");
            break;
        }
        if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
            continue;
        if (require_empty || entry->d_name[0] == '.' || count == MAX_NAMES ||
            fstatat(fd, entry->d_name, &state, AT_SYMLINK_NOFOLLOW) != 0 ||
            !S_ISREG(state.st_mode) || state.st_uid != 0 || state.st_gid != 0 ||
            state.st_nlink != 1 || (state.st_mode & (0022 | S_ISUID | S_ISGID | S_ISVTX)) != 0 ||
            state.st_size <= 0 || state.st_size > MAX_REQUEST_BYTES ||
            (bytes += (uint64_t)state.st_size) > UINT64_C(134217728)) {
            error(require_empty ? "deferred triggers remain after finalization" :
                "invalid deferred trigger queue entry");
            break;
        }
        names[count] = strdup(entry->d_name);
        if (names[count] == NULL) {
            error("cannot retain deferred trigger roster");
            break;
        }
        count++;
    }
    if (result == 0) {
        char identity[128];
        if (fstat(fd, &state) != 0) {
            result = error("cannot identify deferred trigger queue");
        } else {
            int length = snprintf(identity, sizeof(identity), "%ju:%ju:%o:%ju:%ju\n",
                (uintmax_t)state.st_dev, (uintmax_t)state.st_ino,
                (unsigned)state.st_mode, (uintmax_t)state.st_uid, (uintmax_t)state.st_gid);
            if (length <= 0 || (size_t)length >= sizeof(identity))
                result = error("cannot bind deferred trigger queue");
            else
                SHA256_Update(&hash, identity, (size_t)length);
        }
        qsort(names, count, sizeof(*names), compare_names);
        for (size_t i = 0; result == 0 && i < count; i++) {
            char file_digest[65];
            if (fstatat(fd, names[i], &state, AT_SYMLINK_NOFOLLOW) != 0 ||
                (state.st_mode & (0022 | S_ISUID | S_ISGID | S_ISVTX)) != 0 ||
                local_read_mode(fd, names[i], MAX_REQUEST_BYTES, NULL, NULL,
                    file_digest, &state, state.st_mode & 07777) != 0) {
                result = error("cannot verify deferred trigger bytes");
                break;
            }
            SHA256_Update(&hash, names[i], strlen(names[i]) + 1);
            SHA256_Update(&hash, file_digest, 64);
        }
        if (result == 0)
            SHA256_End(&hash, digest);
    }
    if (result == 0 && (fstat(fd, &state) != 0 || !local_same_file(&state, &queue_state) ||
        fstatat(database, "triggers", &state, AT_SYMLINK_NOFOLLOW) != 0 ||
        !local_same_file(&state, &queue_state)))
        result = error("deferred trigger queue changed during verification");
    for (size_t i = 0; i < count; i++)
        free(names[i]);
    free(names);
    if (closedir(queue) != 0)
        result = error("cannot close deferred trigger queue");
    return result;
}

static int
local_apply(const char *config, const char *request_path, const char *root_path, bool finalize)
{
    struct local_apply apply = {.finalize = finalize};
    struct pkgdb *db = NULL;
    struct pkg_jobs *jobs = NULL;
    struct apply_events *events = MAP_FAILED;
    bool initialized = false, locked = false, inside = false;
    char queue_digest[65], repeated_queue[65];
    int result = EXIT_FAILURE;
    if (geteuid() != 0 || getuid() != 0 || !local_environment() ||
        strcmp(pkg_libversion(), "2.6.2") != 0 || setlocale(LC_ALL, "C") == NULL) {
        error("local apply requires root, pkg 2.6.2 and its clean environment");
        goto done;
    }
    /* Scripts must not inherit the installer's open files or input stream. */
    int input = open("/dev/null", O_RDONLY | O_NOFOLLOW);
    if (input == -1 || dup2(input, STDIN_FILENO) == -1) {
        if (input != -1)
            close(input);
        error("cannot isolate local apply input");
        goto done;
    }
    if (input > STDERR_FILENO)
        close(input);
    closefrom(STDERR_FILENO + 1);
    umask(0022);
    if (apply_prepare(&apply, config, request_path, root_path) != 0)
        goto done;
    events = mmap(NULL, sizeof(*events), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANON, -1, 0);
    if (events == MAP_FAILED) {
        error("cannot allocate native event state");
        goto done;
    }
    events->phase = A_VALIDATE;
    events->request = apply.request;
    pkg_event_register(apply_event, events);
    if (apply_inputs(&apply, false) != 0)
        goto done;
    if (finalize && apply_queue(dirfd(apply.directories[A_DB]), false, queue_digest) != 0)
        goto done;
    /* Initialization can create SQLite state, so the one-shot marker precedes it. */
    if (apply_write(&apply, finalize ? "local-finalize" : "local-install", false) != 0)
        goto done;
    if (finalize) {
        if (fchdir(dirfd(apply.directories[A_ROOT])) != 0 || chroot(".") != 0 ||
            chdir("/") != 0 || pkg_set_ischrooted(true) != EPKG_OK) {
            error("cannot enter verified finalization root");
            goto done;
        }
        inside = true;
    } else if (pkg_set_rootdir(root_path) != EPKG_OK ||
        fchdir(dirfd(apply.directories[A_ROOT])) != 0) {
        error("cannot set local installation root");
        goto done;
    }
    if (apply_inputs(&apply, inside) != 0 ||
        pkg_init(finalize ? "/var/db/xcat/pkg-apply/config" : config,
            finalize ? "/var/db/xcat/pkg-apply/repos" : apply.paths[A_REPOS]) != EPKG_OK) {
        error("cannot initialize repository-free local apply");
        goto done;
    }
    initialized = true;
    if (events->failed || apply_effective_config(&apply) != 0 ||
        pkgdb_open(&db, PKGDB_DEFAULT) != EPKG_OK ||
        pkgdb_obtain_lock(db, PKGDB_LOCK_ADVISORY) != EPKG_OK) {
        error("cannot open and lock local apply database");
        goto done;
    }
    locked = true;
    if (finalize) {
        if (apply_database(db, apply.request) != 0 ||
            apply_queue(dirfd(apply.directories[A_DB]), false, repeated_queue) != 0 ||
            apply_inputs(&apply, true) != 0 || apply_install_receipt(&apply) != 0 || events->failed)
            goto done;
        if (strcmp(queue_digest, repeated_queue) != 0) {
            error("deferred trigger queue changed before execution");
            goto done;
        }
        events->phase = A_FINALIZE;
        if (pkg_execute_deferred_triggers() != EPKG_OK || events->failed ||
            apply_queue(dirfd(apply.directories[A_DB]), true, repeated_queue) != 0) {
            error("native deferred trigger finalization failed");
            goto done;
        }
    } else {
        if (local_empty_database(db) != 0 ||
            apply_queue(dirfd(apply.directories[A_DB]), true, repeated_queue) != 0 ||
            pkg_jobs_new(&jobs, PKG_JOBS_INSTALL, db) != EPKG_OK)
            goto done;
        pkg_jobs_set_flags(jobs, PKG_FLAG_NONE);
        if (local_add_archives(jobs, apply.workspace, apply.request) != 0 || events->failed ||
            pkg_jobs_solve(jobs) != EPKG_OK || events->failed ||
            local_jobs(jobs, apply.request) != 0 || local_empty_database(db) != 0 ||
            apply_inputs(&apply, false) != 0)
            goto done;
        events->phase = A_INSTALL;
        if (pkg_jobs_apply(jobs) != EPKG_OK || events->failed ||
            events->actions != apply.request->count) {
            error("native local installation failed");
            goto done;
        }
        for (size_t i = 0; i < apply.request->count; i++) {
            if (events->installed[i] != 3) {
                error("native installation did not complete every requested package");
                goto done;
            }
        }
    }
    events->phase = A_READBACK;
    if (apply_database(db, apply.request) == 0 && !events->failed)
        result = EXIT_SUCCESS;
done:
    pkg_jobs_free(jobs);
    if (locked && pkgdb_release_lock(db, PKGDB_LOCK_ADVISORY) != EPKG_OK)
        result = EXIT_FAILURE;
    if (db != NULL)
        pkgdb_close(db);
    if (initialized)
        pkg_shutdown();
    if (events != MAP_FAILED && events->failed)
        result = EXIT_FAILURE;
    if (result == EXIT_SUCCESS && apply_inputs(&apply, inside) != 0)
        result = EXIT_FAILURE;
    if (result == EXIT_SUCCESS) {
        const char *cache = inside ? "/var/cache/pkg" : apply.paths[A_CACHE];
        const char *repos = inside ? "/var/db/xcat/pkg-apply/repos" : apply.paths[A_REPOS];
        if (empty_root(apply.directories[A_CACHE], cache, &apply.states[A_CACHE]) != 0 ||
            empty_root(apply.directories[A_REPOS], repos, &apply.states[A_REPOS]) != 0)
            result = EXIT_FAILURE;
    }
    if (events != MAP_FAILED && munmap(events, sizeof(*events)) != 0)
        result = EXIT_FAILURE;
    /* A result must be paired with this process's successful exit by the caller. */
    if (result == EXIT_SUCCESS &&
        apply_write(&apply, finalize ? "local-finalize" : "local-install", true) != 0)
        result = EXIT_FAILURE;
    for (size_t i = 0; i < 6; i++)
        if (apply.directories[i] != NULL && closedir(apply.directories[i]) != 0)
            result = EXIT_FAILURE;
    if (apply.request != NULL)
        free(apply.request->bytes);
    free(apply.request);
    return result;
}
/* Private interfaces from the pinned native library. */
pkg_object *pkg_emit_object(struct pkg *, short);
int pkg_jobs_schedule(struct pkg_jobs *);
int xcat_pkg_jobs_add_installed(struct pkg_jobs *, struct pkg *);

#define UPDATE_LOAD (PKG_LOAD_DEPS | PKG_LOAD_FILES | PKG_LOAD_SCRIPTS | \
    PKG_LOAD_OPTIONS | PKG_LOAD_DIRS | PKG_LOAD_CATEGORIES | PKG_LOAD_LICENSES | \
    PKG_LOAD_USERS | PKG_LOAD_GROUPS | PKG_LOAD_SHLIBS_REQUIRED | \
    PKG_LOAD_SHLIBS_PROVIDED | PKG_LOAD_ANNOTATIONS | PKG_LOAD_CONFLICTS | \
    PKG_LOAD_PROVIDES | PKG_LOAD_REQUIRES | PKG_LOAD_LUA_SCRIPTS | \
    PKG_LOAD_SHLIBS_REQUIRED_IGNORE | PKG_LOAD_SHLIBS_PROVIDED_IGNORE)

struct update_package {
    struct pkg *package;
    const char *name;
    char digest[65];
    bool automatic, locked;
    int64_t timestamp;
};

struct update_snapshot {
    struct update_package packages[MAX_NAMES];
    size_t count;
};

struct update_step {
    size_t record;
    int type;
};

struct update_operation {
    struct local_apply apply;
    struct local_request *prior;
    struct stat prior_state;
    struct update_snapshot *before;
    struct pkg *archives[MAX_NAMES];
    char digests[MAX_NAMES][65];
    struct update_package *old[MAX_NAMES];
    bool changed[MAX_NAMES];
    size_t changes, additions, step_count;
    struct update_step steps[MAX_NAMES * 2];
};

struct update_events {
    volatile sig_atomic_t failed;
    const struct update_operation *operation;
    struct pkg_jobs *jobs;
    enum apply_phase phase;
    size_t actions;
    unsigned char finished;
};

static const char *
update_attribute(struct pkg *package, pkg_attr attribute)
{
    const char *value = NULL;
    pkg_get(package, attribute, &value);
    return value;
}

/* The native database can return several licenses as one comma-separated value. */
static int
update_licenses(const pkg_object *licenses, SHA256_CTX *hash)
{
    char *names[256] = {0};
    size_t count = 0;
    int result = -1;
    pkg_iter iterator = NULL;
    const pkg_object *value;
    if (pkg_object_type(licenses) != PKG_ARRAY)
        return error("invalid native package license list");
    while ((value = pkg_object_iterate(licenses, &iterator)) != NULL) {
        const char *text = pkg_object_string(value);
        if (text == NULL || strlen(text) > MAX_NAME_BYTES)
            goto done;
        while (*text != '\0') {
            const char *end = strchr(text, ',');
            if (end == NULL)
                end = text + strlen(text);
            const char *next = *end == ',' ? end + 1 : end;
            while (text < end && *text == ' ')
                text++;
            while (end > text && end[-1] == ' ')
                end--;
            if (text == end || count == sizeof(names) / sizeof(names[0]))
                goto done;
            names[count] = strndup(text, (size_t)(end - text));
            if (names[count] == NULL)
                goto done;
            count++;
            text = next;
        }
    }
    qsort(names, count, sizeof(names[0]), compare_names);
    for (size_t i = 0; i < count; i++) {
        if (i > 0 && strcmp(names[i - 1], names[i]) == 0)
            goto done;
        SHA256_Update(hash, names[i], strlen(names[i]) + 1);
    }
    result = 0;
done:
    for (size_t i = 0; i < count; i++)
        free(names[i]);
    return result == 0 ? 0 : error("cannot compare native package licenses");
}

/* Dependencies have a separate comparison because pkg updates their versions. */
static int
update_digest(struct pkg *package, char digest[65])
{
    pkg_object *object = pkg_emit_object(package, 0);
    if (object == NULL)
        return error("cannot inspect installed package metadata");
    SHA256_CTX hash;
    SHA256_Init(&hash);
    pkg_iter iterator = NULL;
    const pkg_object *value;
    int result = 0;
    while ((value = pkg_object_iterate(object, &iterator)) != NULL) {
        const char *key = pkg_object_key(value);
        if (key == NULL) {
            result = error("native package metadata lacks a key");
            break;
        }
        if (strcmp(key, "deps") == 0 || strcmp(key, "sum") == 0 ||
            strcmp(key, "path") == 0 || strcmp(key, "repopath") == 0)
            continue;
        if (strcmp(key, "licenses") == 0) {
            SHA256_Update(&hash, key, strlen(key) + 1);
            if (update_licenses(value, &hash) != 0) {
                result = -1;
                break;
            }
            continue;
        }
        if (strcmp(key, "annotations") == 0) {
            pkg_iter annotation = NULL;
            if (pkg_object_iterate(value, &annotation) == NULL)
                continue;
        }
        char *bytes = pkg_object_dump(value);
        if (bytes == NULL || strlen(bytes) > UINT64_C(134217728)) {
            free(bytes);
            result = error("native package metadata exceeds its bound");
            break;
        }
        SHA256_Update(&hash, key, strlen(key) + 1);
        SHA256_Update(&hash, bytes, strlen(bytes) + 1);
        free(bytes);
    }
    pkg_object_free(object);
    if (result == 0)
        SHA256_End(&hash, digest);
    return result;
}

static int
update_package_order(const void *left, const void *right)
{
    const struct update_package *a = left, *b = right;
    return strcmp(a->name, b->name);
}

static struct update_package *
update_find(struct update_snapshot *snapshot, const char *name)
{
    struct update_package key = {.name = name};
    return bsearch(&key, snapshot->packages, snapshot->count,
        sizeof(snapshot->packages[0]), update_package_order);
}

static void
update_free_snapshot(struct update_snapshot *snapshot)
{
    if (snapshot != NULL)
        for (size_t i = 0; i < snapshot->count; i++)
            pkg_free(snapshot->packages[i].package);
    free(snapshot);
}

static int
update_snapshot(struct pkgdb *db, struct update_snapshot *snapshot)
{
    struct pkgdb_it *query = pkgdb_query(db, NULL, MATCH_ALL);
    struct pkg *package = NULL;
    int status = EPKG_FATAL, result = -1;
    if (query == NULL)
        return error("cannot query installed package state");
    while ((status = pkgdb_it_next(query, &package, UPDATE_LOAD)) == EPKG_OK) {
        const char *name = update_attribute(package, PKG_ATTR_NAME);
        if (snapshot->count == MAX_NAMES || pkg_type(package) != PKG_INSTALLED ||
            name == NULL || !local_identity(name)) {
            error("invalid installed package roster");
            goto done;
        }
        const pkg_attr fields[] = {PKG_ATTR_VERSION, PKG_ATTR_ORIGIN, PKG_ATTR_ABI};
        for (size_t i = 0; i < sizeof(fields) / sizeof(fields[0]); i++) {
            const char *value = update_attribute(package, fields[i]);
            if (value == NULL || !local_identity(value)) {
                error("invalid installed package identity");
                goto done;
            }
        }
        struct update_package *entry = &snapshot->packages[snapshot->count];
        entry->package = package;
        entry->name = name;
        pkg_get(package, PKG_ATTR_AUTOMATIC, &entry->automatic);
        pkg_get(package, PKG_ATTR_LOCKED, &entry->locked);
        pkg_get(package, PKG_ATTR_TIME, &entry->timestamp);
        if (update_digest(package, entry->digest) != 0)
            goto done;
        snapshot->count++;
        package = NULL;
    }
    if (status != EPKG_END || snapshot->count == 0) {
        error("installed operation requires an existing package roster");
        goto done;
    }
    qsort(snapshot->packages, snapshot->count, sizeof(snapshot->packages[0]),
        update_package_order);
    for (size_t i = 1; i < snapshot->count; i++) {
        if (strcmp(snapshot->packages[i - 1].name, snapshot->packages[i].name) == 0) {
            error("ambiguous installed package name");
            goto done;
        }
    }
    result = 0;
done:
    pkg_free(package);
    pkgdb_it_free(query);
    return result;
}

static int
update_roster(int directory, const char *name, const struct update_snapshot *snapshot,
    char digest[65])
{
    char *bytes = NULL;
    size_t length = 0;
    FILE *stream = open_memstream(&bytes, &length);
    if (stream == NULL)
        return error("cannot format installed package roster");
    fprintf(stream, "format\txcat-freebsd-installed-state-1\n");
    for (size_t i = 0; i < snapshot->count; i++) {
        const struct update_package *entry = &snapshot->packages[i];
        fprintf(stream, "package\t%s\t%s\t%s\t%s\t%s\t%d\t%d\t%jd\n", entry->name,
            update_attribute(entry->package, PKG_ATTR_VERSION),
            update_attribute(entry->package, PKG_ATTR_ORIGIN),
            update_attribute(entry->package, PKG_ATTR_ABI), entry->digest,
            entry->automatic, entry->locked, (intmax_t)entry->timestamp);
        struct pkg_dep *dep = NULL;
        while (pkg_deps(entry->package, &dep) == EPKG_OK) {
            const char *fields[] = {pkg_dep_name(dep), pkg_dep_origin(dep), pkg_dep_version(dep)};
            for (size_t f = 0; f < 3; f++) {
                if (fields[f] == NULL || !local_identity(fields[f])) {
                    fclose(stream);
                    free(bytes);
                    return error("invalid installed dependency identity");
                }
            }
            fprintf(stream, "dependency\t%s\t%s\t%s\t%s\n", entry->name,
                fields[0], fields[1], fields[2]);
        }
    }
    bool failed = ferror(stream) != 0;
    if (fclose(stream) != 0)
        failed = true;
    int result = failed || length > UINT64_C(134217728) ?
        error("installed package roster exceeds its bound") : apply_record_write(directory, name, bytes, length);
    if (result == 0)
        SHA256_Data(bytes, length, digest);
    free(bytes);
    return result;
}

static bool
update_dependencies(struct pkg *expected, struct pkg *actual,
    const struct local_request *desired)
{
    struct pkg_dep *a = NULL, *b = NULL;
    for (;;) {
        int left = pkg_deps(expected, &a), right = pkg_deps(actual, &b);
        if (left == EPKG_END && right == EPKG_END)
            return true;
        if (left != EPKG_OK || right != EPKG_OK || pkg_dep_name(a) == NULL ||
            pkg_dep_name(b) == NULL || pkg_dep_origin(a) == NULL || pkg_dep_origin(b) == NULL ||
            pkg_dep_version(a) == NULL || pkg_dep_version(b) == NULL ||
            strcmp(pkg_dep_name(a), pkg_dep_name(b)) != 0 ||
            strcmp(pkg_dep_origin(a), pkg_dep_origin(b)) != 0)
            return false;
        if (strcmp(pkg_dep_version(a), pkg_dep_version(b)) == 0)
            continue;
        struct local_record key = {0};
        key.field[L_NAME] = (char *)pkg_dep_name(b);
        struct local_record *pointer = &key;
        struct local_record **found = bsearch(&pointer, desired->by_name, desired->count,
            sizeof(desired->by_name[0]), local_name_order);
        if (found == NULL || strcmp((*found)->field[L_ORIGIN], pkg_dep_origin(b)) != 0 ||
            strcmp((*found)->field[L_VERSION], pkg_dep_version(b)) != 0)
            return false;
    }
}

static int
update_prepare(struct update_operation *operation, const char *config, const char *request_path,
    bool verify_only, bool recovering)
{
    struct local_apply *apply = &operation->apply;
    size_t length = strlen(request_path);
    const char *alphabet = "/ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_.-+";
    if (length <= 8 || length >= LOCAL_PATH_BYTES / 2 || request_path[0] != '/' ||
        strcmp(request_path + length - 8, "/request") != 0 ||
        strspn(request_path, alphabet) != length)
        return error("invalid installed-operation request path");
    memcpy(apply->workspace, request_path, length - 8);
    apply->workspace[length - 8] = '\0';
    snprintf(apply->paths[A_WORK], LOCAL_PATH_BYTES, "%s", apply->workspace);
    snprintf(apply->paths[A_ROOT], LOCAL_PATH_BYTES, "/");
    snprintf(apply->paths[A_DB], LOCAL_PATH_BYTES, "/var/db/pkg");
    snprintf(apply->paths[A_ARCHIVES], LOCAL_PATH_BYTES, "%s/archives", apply->workspace);
    snprintf(apply->paths[A_CACHE], LOCAL_PATH_BYTES, "%s/cache", apply->workspace);
    snprintf(apply->paths[A_REPOS], LOCAL_PATH_BYTES, "%s/repos", apply->workspace);
    char expected[LOCAL_PATH_BYTES];
    snprintf(expected, sizeof(expected), "%s/config", apply->workspace);
    if (strcmp(config, expected) != 0)
        return error("installed-operation configuration must belong to its workspace");
    for (size_t i = 0; i < 6; i++) {
        if (i == A_ROOT) {
            apply->directories[i] = opendir("/");
            if (apply->directories[i] == NULL ||
                fstat(dirfd(apply->directories[i]), &apply->states[i]) != 0)
                return error("cannot open live target root");
        } else {
            apply->directories[i] = open_directory(apply->paths[i], &apply->states[i],
                i == A_CACHE || i == A_REPOS);
        }
        mode_t mode = i == A_ARCHIVES ? 0500 : i == A_DB || i == A_ROOT ? 0755 : 0700;
        if (apply->directories[i] == NULL || apply->states[i].st_uid != 0 ||
            apply->states[i].st_gid != 0 || (apply->states[i].st_mode & 07777) != mode)
            return error("installed-operation directory is not protected");
    }
    int directory = dirfd(apply->directories[A_WORK]);
    const char *records[] = {"local-update.started", "local-update.result",
        "local-update.rejected", "local-verify.started", "local-verify.result",
        "local-verify.rejected",
        "before", "after", "managed.request", "actions"};
    for (size_t i = 0; !recovering && i < sizeof(records) / sizeof(records[0]); i++)
        if (apply_absent(directory, records[i]) != 0)
            return -1;
    apply->request = calloc(1, sizeof(*apply->request));
    operation->prior = calloc(1, sizeof(*operation->prior));
    if (apply->request == NULL || operation->prior == NULL ||
        local_read(directory, "request", MAX_REQUEST_BYTES, NULL, &apply->request->bytes,
            apply->request->sha256, &apply->request_state) != 0 ||
        local_parse(apply->request, (size_t)apply->request_state.st_size, true, verify_only) != 0 ||
        local_read(directory, "prior-request", MAX_REQUEST_BYTES, NULL, &operation->prior->bytes,
            operation->prior->sha256, &operation->prior_state) != 0 ||
        local_parse(operation->prior, (size_t)operation->prior_state.st_size, false, false) != 0 ||
        apply_config(apply, apply->config_digest, &apply->config_state) != 0 ||
        local_archives(apply->directories[A_ARCHIVES], apply->request, false) != 0)
        return -1;
    return 0;
}

static int
update_inputs(struct update_operation *operation)
{
    struct stat state;
    char digest[65];
    if (apply_inputs(&operation->apply, false) != 0 ||
        local_read(dirfd(operation->apply.directories[A_WORK]), "prior-request",
            MAX_REQUEST_BYTES, NULL, NULL, digest, &state) != 0 ||
        strcmp(digest, operation->prior->sha256) != 0 ||
        !local_same_file(&state, &operation->prior_state))
        return error("installed-operation inputs changed");
    return 0;
}

static int
update_manifest(struct update_operation *operation, size_t index, struct pkg **package)
{
    const struct local_record *record = &operation->apply.request->records[index];
    char name[32], digest[SHA256_DIGEST_STRING_LENGTH], *bytes = NULL;
    struct stat state;
    snprintf(name, sizeof(name), "p%zu.manifest", index);
    /* The controller binds these full manifest bytes to the original archive. */
    bool valid = local_read(dirfd(operation->apply.directories[A_ARCHIVES]), name,
        LOCAL_MANIFEST_BYTES, NULL, &bytes, digest, &state) == 0 &&
        local_same_file(&state, &record->archive_state) &&
        strcmp(digest, record->manifest_digest) == 0 &&
        pkg_new(package, PKG_FILE) == EPKG_OK &&
        pkg_parse_manifest(*package, bytes, (size_t)state.st_size) == EPKG_OK;
    free(bytes);
    return valid ? 0 : error("cannot read sealed native verification manifest");
}

static int
update_select(struct update_operation *operation, struct pkg_jobs *jobs, struct pkgdb *db)
{
    struct local_request *request = operation->apply.request;
    /* An empty operation must retain every prior managed identity. */
    if (request->count == 0) {
        for (size_t i = 0; i < operation->prior->count; i++) {
            struct local_record *prior = &operation->prior->records[i];
            struct update_package *installed = update_find(operation->before, prior->field[L_NAME]);
            if (installed == NULL || !local_native_identity(installed->package, prior))
                return error("empty operation prior provenance differs from installed state");
        }
    }
    for (size_t i = 0; i < request->count; i++) {
        struct local_record *record = &request->records[i];
        char path[LOCAL_PATH_BYTES];
        snprintf(path, sizeof(path), "%s/archives/p%zu.pkg", operation->apply.workspace, i);
        struct pkg **archive = &operation->archives[i];
        int opened = request->manifests ? update_manifest(operation, i, archive) :
            (pkg_open(archive, path, PKG_OPEN_MANIFEST_ONLY) == EPKG_OK ? 0 : -1);
        if (opened != 0 || *archive == NULL ||
            pkg_type(*archive) != PKG_FILE || pkg_is_valid(*archive) != EPKG_OK ||
            !local_native_identity(*archive, record) || update_digest(*archive, operation->digests[i]) != 0)
            return error("installed-operation archive metadata differs");
        struct update_package *old = update_find(operation->before, record->field[L_NAME]);
        operation->old[i] = old;
        if (request->manifests && (old == NULL ||
            strcmp(update_attribute(old->package, PKG_ATTR_VERSION), record->field[L_VERSION]) != 0))
            return error("required packages are not satisfied; verification cannot install or upgrade");
        if (old != NULL) {
            if (strcmp(update_attribute(old->package, PKG_ATTR_ORIGIN), record->field[L_ORIGIN]) != 0 ||
                strcmp(update_attribute(old->package, PKG_ATTR_ABI), record->field[L_ABI]) != 0)
                return error("installed-operation origin or ABI change is not allowed");
            int comparison = pkg_version_cmp(update_attribute(old->package, PKG_ATTR_VERSION),
                record->field[L_VERSION]);
            if (comparison > 0)
                return error("installed-operation downgrade is not allowed");
            if (comparison == 0) {
                struct local_record *prior = apply_record(operation->prior, old->package);
                if (prior == NULL || strcmp(prior->field[L_SHA256], record->field[L_SHA256]) != 0 ||
                    strcmp(old->digest, operation->digests[i]) != 0 ||
                    !update_dependencies(*archive, old->package, request)) {
                    fprintf(stderr, "FreeBSD resolver: package %s\n", record->field[L_NAME]);
                    return error("same-version package lacks matching archive provenance or metadata");
                }
                continue;
            }
            if (old->locked)
                return error("requested installed package is locked");
            struct pkgdb_it *query = pkgdb_query(db, record->field[L_NAME], MATCH_EXACT);
            struct pkg *installed = NULL, *extra = NULL;
            if (query == NULL)
                return error("cannot load installed upgrade input");
            int status = pkgdb_it_next(query, &installed, UPDATE_LOAD | PKG_LOAD_RDEPS);
            bool valid = status == EPKG_OK && installed != NULL &&
                strcmp(update_attribute(installed, PKG_ATTR_VERSION),
                    update_attribute(old->package, PKG_ATTR_VERSION)) == 0 &&
                pkgdb_it_next(query, &extra, PKG_LOAD_BASIC) == EPKG_END;
            pkg_free(extra);
            pkgdb_it_free(query);
            if (!valid || xcat_pkg_jobs_add_installed(jobs, installed) != EPKG_OK) {
                pkg_free(installed);
                return error("cannot bind installed package to native upgrade solution");
            }
        } else {
            operation->additions++;
        }
        operation->changed[i] = true;
        operation->changes++;
        char *operand = path;
        if (pkg_jobs_add(jobs, MATCH_EXACT, &operand, 1) != EPKG_OK)
            return error("cannot select installed-operation archive");
    }
    return 0;
}

static bool
update_old_identity(const struct update_operation *operation, size_t index, struct pkg *package)
{
    const struct update_package *old = operation->old[index];
    if (old == NULL || package == NULL || pkg_type(package) != PKG_INSTALLED)
        return false;
    const pkg_attr fields[] = {PKG_ATTR_NAME, PKG_ATTR_VERSION, PKG_ATTR_ORIGIN, PKG_ATTR_ABI};
    for (size_t i = 0; i < sizeof(fields) / sizeof(fields[0]); i++) {
        const char *a = update_attribute(old->package, fields[i]);
        const char *b = update_attribute(package, fields[i]);
        if (a == NULL || b == NULL || strcmp(a, b) != 0)
            return false;
    }
    return true;
}

static int
update_jobs(struct update_operation *operation, struct pkg_jobs *jobs, bool repeat)
{
    unsigned char seen[MAX_NAMES] = {0};
    struct pkg *next = NULL, *old = NULL;
    void *iterator = NULL;
    size_t count = 0;
    int type, result = 0;
    while (pkg_jobs_iter(jobs, &iterator, &next, &old, &type)) {
        const char *name = next != NULL ? update_attribute(next, PKG_ATTR_NAME) : NULL;
        struct local_record key = {0};
        key.field[L_NAME] = (char *)name;
        struct local_record *pointer = &key;
        struct local_request *request = operation->apply.request;
        struct local_record **found = name == NULL ? NULL : bsearch(&pointer,
            request->by_name, request->count, sizeof(request->by_name[0]), local_name_order);
        if (found == NULL || count >= MAX_NAMES * 2) {
            result = -1;
            continue;
        }
        size_t index = (size_t)(*found - request->records);
        bool valid = operation->changed[index];
        unsigned char bit = 0;
        if (type == PKG_SOLVED_UPGRADE_REMOVE) {
            bit = 2;
            valid = valid && seen[index] == 0 && old == NULL && update_old_identity(operation, index, next);
        } else {
            bit = 1;
            valid = valid && pkg_type(next) == PKG_FILE && local_native_identity(next, *found);
            if (type == PKG_SOLVED_INSTALL)
                valid = valid && seen[index] == 0 && old == NULL && operation->old[index] == NULL;
            else if (type == PKG_SOLVED_UPGRADE)
                valid = valid && seen[index] == 0 && update_old_identity(operation, index, old);
            else if (type == PKG_SOLVED_UPGRADE_INSTALL)
                valid = valid && old == NULL && operation->old[index] != NULL && seen[index] == 2;
            else
                valid = false;
        }
        if (!valid || (seen[index] & bit) != 0 ||
            (repeat && (count >= operation->step_count ||
                operation->steps[count].record != index || operation->steps[count].type != type)))
            result = -1;
        seen[index] |= bit;
        if (!repeat)
            operation->steps[count] = (struct update_step){index, type};
        count++;
    }
    for (size_t i = 0; i < operation->apply.request->count; i++)
        if ((operation->changed[i] && seen[i] != 1 && seen[i] != 3) ||
            (!operation->changed[i] && seen[i] != 0))
            result = -1;
    if (count != (size_t)pkg_jobs_count(jobs) || (repeat && count != operation->step_count))
        result = -1;
    if (!repeat)
        operation->step_count = count;
    return result == 0 ? 0 : error("native actions differ from requested additions and upgrades");
}

static int
update_event(void *data, struct pkg_event *event)
{
    struct update_events *state = data;
    const struct update_operation *operation = state->operation;
    struct pkg *package = NULL, *old = NULL;
    unsigned char bit = 0;
    bool old_only = false;
    int expected_type = -1;
    switch (event->type) {
    case PKG_EVENT_DEBUG:
    case PKG_EVENT_NOTICE:
    case PKG_EVENT_MESSAGE:
    case PKG_EVENT_PROGRESS_START:
    case PKG_EVENT_PROGRESS_TICK:
    case PKG_EVENT_INTEGRITYCHECK_BEGIN:
    case PKG_EVENT_INTEGRITYCHECK_FINISHED:
        return 0;
    case PKG_EVENT_CONFLICTS:
        if (state->phase == A_VALIDATE)
            return 0;
        break;
    case PKG_EVENT_SANDBOX_CALL:
        return pkg_handle_sandboxed_call(event->e_sandbox_call.call,
            event->e_sandbox_call.fd, event->e_sandbox_call.userdata);
    case PKG_EVENT_SANDBOX_GET_STRING:
        return pkg_handle_sandboxed_get_string(event->e_sandbox_call_str.call,
            event->e_sandbox_call_str.result, event->e_sandbox_call_str.len,
            event->e_sandbox_call_str.userdata);
    case PKG_EVENT_NEW_ACTION:
        if (!state->failed && state->phase == A_INSTALL &&
            event->e_action.total == operation->step_count &&
            event->e_action.current == state->actions + 1 &&
            state->actions < operation->step_count &&
            (state->actions == 0 || state->finished == 3) &&
            update_jobs((struct update_operation *)operation, state->jobs, true) == 0) {
            state->actions++;
            state->finished = 0;
            return 0;
        }
        /* This callback precedes mutation; do not execute an unvalidated action. */
        error("stopping before an unexpected native update action");
        _exit(EXIT_FAILURE);
    case PKG_EVENT_INSTALL_BEGIN:
        package = event->e_install_begin.pkg;
        bit = 1;
        expected_type = PKG_SOLVED_INSTALL;
        break;
    case PKG_EVENT_INSTALL_FINISHED:
        package = event->e_install_finished.pkg;
        old = event->e_install_finished.old;
        bit = 2;
        expected_type = PKG_SOLVED_INSTALL;
        break;
    case PKG_EVENT_UPGRADE_BEGIN:
        package = event->e_upgrade_begin.n;
        old = event->e_upgrade_begin.o;
        bit = 1;
        expected_type = PKG_SOLVED_UPGRADE;
        break;
    case PKG_EVENT_UPGRADE_FINISHED:
        package = event->e_upgrade_finished.n;
        old = event->e_upgrade_finished.o;
        bit = 2;
        expected_type = PKG_SOLVED_UPGRADE;
        break;
    case PKG_EVENT_DEINSTALL_BEGIN:
        package = event->e_deinstall_begin.pkg;
        bit = 1;
        old_only = true;
        expected_type = PKG_SOLVED_UPGRADE_REMOVE;
        break;
    case PKG_EVENT_DEINSTALL_FINISHED:
        package = event->e_deinstall_finished.pkg;
        bit = 2;
        old_only = true;
        expected_type = PKG_SOLVED_UPGRADE_REMOVE;
        break;
    case PKG_EVENT_DELETE_FILES_BEGIN:
        package = event->e_delete_files_begin.pkg;
        old_only = true;
        break;
    case PKG_EVENT_DELETE_FILES_FINISHED:
        package = event->e_delete_files_finished.pkg;
        old_only = true;
        break;
    case PKG_EVENT_EXTRACT_BEGIN:
        package = event->e_extract_begin.pkg;
        break;
    case PKG_EVENT_EXTRACT_FINISHED:
        package = event->e_extract_finished.pkg;
        break;
    case PKG_EVENT_CLEANUP_CALLBACK_REGISTER:
    case PKG_EVENT_CLEANUP_CALLBACK_UNREGISTER:
    case PKG_EVENT_TRIGGERS_BEGIN:
    case PKG_EVENT_TRIGGER:
    case PKG_EVENT_TRIGGERS_FINISHED:
        if (state->phase == A_INSTALL && operation->changes > 0)
            return 0;
        break;
    default:
        events(NULL, event);
        break;
    }
    if (state->phase == A_INSTALL && state->actions > 0 && package != NULL) {
        const struct update_step *step = &operation->steps[state->actions - 1];
        size_t index = step->record;
        bool valid = old_only ? update_old_identity(operation, index, package) :
            local_native_identity(package, &operation->apply.request->records[index]);
        if (expected_type == PKG_SOLVED_INSTALL && step->type == PKG_SOLVED_UPGRADE_INSTALL)
            expected_type = PKG_SOLVED_UPGRADE_INSTALL;
        valid = valid && (expected_type == -1 || step->type == expected_type);
        if (old != NULL)
            valid = valid && step->type != PKG_SOLVED_INSTALL &&
                update_old_identity(operation, index, old);
        else if (expected_type == PKG_SOLVED_UPGRADE ||
            (expected_type == PKG_SOLVED_UPGRADE_INSTALL && bit == 2))
            valid = false;
        if (valid && (bit != 0 || state->finished == 1) && (bit == 0 || (state->finished & bit) == 0) &&
            (bit != 2 || state->finished == 1)) {
            state->finished |= bit;
            return 0;
        }
    }
    state->failed = 1;
    error("native installed operation reported an error or unexpected event");
    return 0;
}

static int
update_readback(struct update_operation *operation, struct update_snapshot *after)
{
    const struct local_request *request = operation->apply.request;
    if (after->count != operation->before->count + operation->additions)
        return error("installed operation changed the package roster unexpectedly");
    for (size_t i = 0; i < after->count; i++) {
        struct update_package *entry = &after->packages[i];
        struct update_package *prior = update_find(operation->before, entry->name);
        struct local_record *record = apply_record(request, entry->package);
        struct pkg *expected;
        const char *digest;
        bool changed = false;
        if (record != NULL) {
            size_t index = (size_t)(record - request->records);
            expected = operation->archives[index];
            digest = operation->digests[index];
            changed = operation->changed[index];
            record->seen = true;
        } else if (prior != NULL) {
            expected = prior->package;
            digest = prior->digest;
        } else {
            return error("installed operation added an unrequested package");
        }
        if (strcmp(entry->digest, digest) != 0 ||
            !update_dependencies(expected, entry->package, request) ||
            (prior != NULL && (prior->automatic != entry->automatic || prior->locked != entry->locked ||
                (!changed && prior->timestamp != entry->timestamp))))
            return error("installed package metadata differs from the authorized result");
    }
    for (size_t i = 0; i < request->count; i++)
        if (!request->records[i].seen)
            return error("installed operation omitted a requested package");
    return 0;
}

static bool
update_same_identity(struct pkg *left, struct pkg *right)
{
    const pkg_attr attributes[] = {PKG_ATTR_NAME, PKG_ATTR_VERSION, PKG_ATTR_ORIGIN, PKG_ATTR_ABI};
    if (left == NULL || right == NULL)
        return false;
    for (size_t i = 0; i < 4; i++)
        if (strcmp(update_attribute(left, attributes[i]), update_attribute(right, attributes[i])) != 0)
            return false;
    return true;
}

static int
update_managed(struct update_operation *operation, struct update_snapshot *after,
    int directory, bool recovering, char digest[65])
{
    struct local_record **records = calloc(MAX_NAMES, sizeof(*records));
    if (records == NULL)
        return error("cannot allocate managed package provenance");
    size_t count = 0;
    for (size_t i = 0; i < after->count; i++) {
        struct pkg *package = after->packages[i].package;
        struct update_package *old = recovering ? update_find(operation->before, after->packages[i].name) : NULL;
        bool unchanged = old != NULL && update_same_identity(old->package, package);
        struct local_record *record = recovering && unchanged ? apply_record(operation->prior, package) : NULL;
        /* An unchanged unmanaged identity does not acquire new archive provenance. */
        if (record == NULL && (!recovering || !unchanged))
            record = apply_record(operation->apply.request, package);
        if (record == NULL && !recovering)
            record = apply_record(operation->prior, package);
        if (record != NULL)
            records[count++] = record;
    }
    char *bytes = NULL;
    size_t length = 0;
    FILE *stream = open_memstream(&bytes, &length);
    if (stream == NULL) {
        free(records);
        return error("cannot format managed package provenance");
    }
    fprintf(stream, "format\txcat-freebsd-local-request-1\nplan\t%s\n", operation->apply.request->plan);
    for (size_t i = 0; i < count; i++) {
        fprintf(stream, "package\tp%zu", i);
        for (size_t f = 1; f < L_FIELDS; f++)
            fprintf(stream, "\t%s", records[i]->field[f]);
        fputc('\n', stream);
    }
    free(records);
    bool failed = ferror(stream) != 0;
    if (fclose(stream) != 0)
        failed = true;
    int result = failed || count == 0 || length > MAX_REQUEST_BYTES ?
        error("invalid managed package provenance") :
        apply_record_write(directory, "managed.request", bytes, length);
    if (result == 0)
        SHA256_Data(bytes, length, digest);
    free(bytes);
    return result;
}

static int
update_rejection(struct update_operation *operation, const char *scope)
{
    struct local_apply *apply = &operation->apply;
    int directory = dirfd(apply->directories[A_WORK]);
    char name[64], receipt[1024];
    snprintf(name, sizeof(name), "%s.result", scope);
    if (apply_absent(directory, name) != 0 || update_inputs(operation) != 0)
        return -1;
    int length = snprintf(receipt, sizeof(receipt),
        "format\txcat-freebsd-local-rejection-1\nscope\t%s\n"
        "plan-reference\t%s\nrequest-sha256\t%s\nprior-request-sha256\t%s\n"
        "config-sha256\t%s\npkg\t2.6.2\napply\tnot-started\noutcome\trejected\ncomplete\tyes\n",
        scope, apply->request->plan, apply->request->sha256,
        operation->prior->sha256, apply->config_digest);
    snprintf(name, sizeof(name), "%s.rejected", scope);
    if (length <= 0 || (size_t)length >= sizeof(receipt))
        return error("cannot format installed-operation rejection");
    return apply_record_write(directory, name, receipt, (size_t)length);
}

/* Reconstruct only the metadata needed to compare a retained before roster. */
static int
recovery_before(struct update_operation *operation, char digest[65], struct stat *state)
{
    char *bytes = NULL;
    int result = -1;
    struct update_snapshot *snapshot = operation->before;
    if (local_read_mode(dirfd(operation->apply.directories[A_WORK]), "before",
        UINT64_C(134217728), NULL, &bytes, digest, state, 0600) != 0)
        return -1;
    size_t length = (size_t)state->st_size;
    const char *header = "format\txcat-freebsd-installed-state-1\n";
    if (length <= strlen(header) || memchr(bytes, '\0', length) != NULL ||
        bytes[length - 1] != '\n' || strncmp(bytes, header, strlen(header)) != 0)
        goto done;
    char *cursor = bytes + strlen(header), *line;
    struct update_package *entry = NULL;
    while ((line = strsep(&cursor, "\n")) != NULL && *line != '\0') {
        char *fields[9], *part = line;
        size_t count = 0;
        if (strlen(line) > LOCAL_LINE_BYTES)
            goto done;
        while (count < 9 && (fields[count] = strsep(&part, "\t")) != NULL)
            count++;
        if (part != NULL)
            goto done;
        if (count == 9 && strcmp(fields[0], "package") == 0) {
            if (snapshot->count == MAX_NAMES || !local_hex(fields[5]) ||
                (strcmp(fields[6], "0") != 0 && strcmp(fields[6], "1") != 0) ||
                (strcmp(fields[7], "0") != 0 && strcmp(fields[7], "1") != 0))
                goto done;
            for (size_t i = 1; i <= 4; i++)
                if (!local_identity(fields[i]))
                    goto done;
            if (entry != NULL && strcmp(entry->name, fields[1]) >= 0)
                goto done;
            errno = 0;
            char *end, canonical[32];
            intmax_t timestamp = strtoimax(fields[8], &end, 10);
            /* pkg can retain an unavailable timestamp as -1. */
            if (errno != 0 || *end != '\0' || timestamp < INT64_MIN || timestamp > INT64_MAX)
                goto done;
            snprintf(canonical, sizeof(canonical), "%jd", timestamp);
            if (strcmp(canonical, fields[8]) != 0)
                goto done;
            entry = &snapshot->packages[snapshot->count];
            if (pkg_new(&entry->package, PKG_INSTALLED) != EPKG_OK)
                goto done;
            snapshot->count++;
            const pkg_attr attributes[] = {PKG_ATTR_NAME, PKG_ATTR_VERSION, PKG_ATTR_ORIGIN, PKG_ATTR_ABI};
            for (size_t i = 0; i < 4; i++)
                if (pkg_set(entry->package, attributes[i], fields[i + 1]) != EPKG_OK)
                    goto done;
            entry->name = update_attribute(entry->package, PKG_ATTR_NAME);
            memcpy(entry->digest, fields[5], 65);
            entry->automatic = strcmp(fields[6], "1") == 0;
            entry->locked = strcmp(fields[7], "1") == 0;
            entry->timestamp = (int64_t)timestamp;
        } else if (count == 5 && strcmp(fields[0], "dependency") == 0 &&
            entry != NULL && strcmp(fields[1], entry->name) == 0) {
            for (size_t i = 2; i <= 4; i++)
                if (!local_identity(fields[i]))
                    goto done;
            if (pkg_adddep(entry->package, fields[2], fields[3], fields[4], false) != EPKG_OK)
                goto done;
        } else {
            goto done;
        }
    }
    if (cursor == NULL && snapshot->count != 0)
        result = 0;
done:
    free(bytes);
    return result == 0 ? 0 : error("invalid retained installed package roster");
}

static int
recovery_started(struct update_operation *operation, char digest[65], struct stat *state,
    char name[32], bool *verify_only)
{
    int directory = dirfd(operation->apply.directories[A_WORK]);
    struct stat other;
    const char *scope = "local-update";
    if (fstatat(directory, "local-update.started", &other, AT_SYMLINK_NOFOLLOW) != 0) {
        if (errno != ENOENT)
            return error("cannot inspect interrupted package start");
        scope = "local-verify";
    } else if (fstatat(directory, "local-verify.started", &other, AT_SYMLINK_NOFOLLOW) == 0 || errno != ENOENT) {
        return error("ambiguous interrupted package start");
    }
    snprintf(name, 32, "%s.started", scope);
    *verify_only = strcmp(scope, "local-verify") == 0;
    if (!*verify_only && operation->apply.request->manifests)
        return error("recovery update requires archive inputs");
    char *bytes = NULL, expected[768];
    if (local_read_mode(directory, name, sizeof(expected) - 1, NULL, &bytes, digest, state, 0600) != 0)
        return -1;
    int prefix = snprintf(expected, sizeof(expected),
        "format\txcat-freebsd-local-apply-1\nscope\t%s\nplan-reference\t%s\n"
        "request-sha256\t%s\npkg\t2.6.2\npackages\t%zu\ntarget-device\t",
        scope, operation->apply.request->plan, operation->apply.request->sha256,
        operation->apply.request->count);
    bool valid = prefix > 0 && (size_t)prefix < sizeof(expected) &&
        state->st_size > prefix && memchr(bytes, '\0', (size_t)state->st_size) == NULL &&
        strncmp(bytes, expected, (size_t)prefix) == 0;
    char *tail = valid ? bytes + prefix : NULL;
    /* Device numbers need not remain equal across the explicit recovery boot. */
    if (valid) {
        size_t digits = strspn(tail, "0123456789");
        valid = digits > 0 && digits <= 20 && strncmp(tail + digits, "\ntarget-inode\t", 14) == 0;
        if (valid) {
            tail += digits + 14;
            digits = strspn(tail, "0123456789");
            valid = digits > 0 && digits <= 20 && strcmp(tail + digits, "\ncomplete\tno\n") == 0;
        }
    }
    free(bytes);
    return valid ? 0 : error("interrupted package start differs from its request");
}

struct recovery_record {
    bool present;
    struct stat state;
    char digest[65];
};

/* Missing records do not authorize changes. Retain their absence for readback. */
static int
recovery_record(int directory, const char *name, struct recovery_record *record, char **bytes)
{
    if (fstatat(directory, name, &record->state, AT_SYMLINK_NOFOLLOW) != 0) {
        if (errno != ENOENT)
            return error("cannot inspect retained package operation record");
        record->present = false;
        snprintf(record->digest, sizeof(record->digest), "-");
        return 0;
    }
    record->present = true;
    return local_read_mode(directory, name, UINT64_C(134217728), NULL,
        bytes, record->digest, &record->state, 0600);
}

static int
recovery_record_same(int directory, const char *name, const struct recovery_record *record)
{
    struct recovery_record repeated = {0};
    if (recovery_record(directory, name, &repeated, NULL) != 0 ||
        repeated.present != record->present || strcmp(repeated.digest, record->digest) != 0 ||
        (record->present && !local_same_file(&record->state, &repeated.state)))
        return error("retained package operation record changed");
    return 0;
}

/* The complete plan is written only after the complete before roster is durable. */
static int
recovery_actions(struct update_operation *operation, struct recovery_record *record)
{
    char *bytes = NULL;
    if (recovery_record(dirfd(operation->apply.directories[A_WORK]), "actions", record, &bytes) != 0)
        return -1;
    if (!record->present)
        return 0;
    struct local_request *request = operation->apply.request;
    const char *header = "format\txcat-freebsd-update-actions-1\n";
    size_t length = (size_t)record->state.st_size, count = 0;
    unsigned char seen[MAX_NAMES] = {0};
    int result = -1;
    if (length < strlen(header) || memchr(bytes, '\0', length) != NULL ||
        bytes[length - 1] != '\n' || strncmp(bytes, header, strlen(header)) != 0)
        goto done;
    for (size_t i = 0; i < request->count; i++) {
        const struct local_record *wanted = &request->records[i];
        struct update_package *old = update_find(operation->before, wanted->field[L_NAME]);
        operation->old[i] = old;
        if (old == NULL) {
            operation->changed[i] = true;
            continue;
        }
        if (strcmp(update_attribute(old->package, PKG_ATTR_ORIGIN), wanted->field[L_ORIGIN]) != 0 ||
            strcmp(update_attribute(old->package, PKG_ATTR_ABI), wanted->field[L_ABI]) != 0)
            goto done;
        const char *version = update_attribute(old->package, PKG_ATTR_VERSION);
        if (strcmp(version, wanted->field[L_VERSION]) == 0)
            continue;
        if (old->locked || pkg_version_cmp(version, wanted->field[L_VERSION]) >= 0)
            goto done;
        operation->changed[i] = true;
    }
    char *cursor = bytes + strlen(header), *line;
    while ((line = strsep(&cursor, "\n")) != NULL && *line != '\0') {
        char *fields[6], *part = line;
        size_t fields_count = 0;
        if (++count > MAX_NAMES * 2 || strlen(line) > LOCAL_LINE_BYTES)
            goto done;
        while (fields_count < 6 && (fields[fields_count] = strsep(&part, "\t")) != NULL)
            fields_count++;
        if (fields_count != 6 || part != NULL || strcmp(fields[0], "action") != 0)
            goto done;
        char ordinal[32];
        snprintf(ordinal, sizeof(ordinal), "%zu", count);
        if (strcmp(fields[1], ordinal) != 0)
            goto done;
        struct local_record key = {0};
        key.field[L_NAME] = fields[3];
        struct local_record *pointer = &key;
        struct local_record **found = bsearch(&pointer, request->by_name,
            request->count, sizeof(request->by_name[0]), local_name_order);
        if (found == NULL)
            goto done;
        size_t index = (size_t)(*found - request->records);
        const struct update_package *old = operation->old[index];
        if (!operation->changed[index] || strcmp(fields[5], (*found)->field[L_VERSION]) != 0 ||
            strcmp(fields[4], old == NULL ? "-" : update_attribute(old->package, PKG_ATTR_VERSION)) != 0)
            goto done;
        const int types[] = {PKG_SOLVED_INSTALL, PKG_SOLVED_UPGRADE,
            PKG_SOLVED_UPGRADE_REMOVE, PKG_SOLVED_UPGRADE_INSTALL};
        int type = -1;
        for (size_t i = 0; i < sizeof(types) / sizeof(types[0]); i++) {
            char value[32];
            snprintf(value, sizeof(value), "%d", types[i]);
            if (strcmp(fields[2], value) == 0)
                type = types[i];
        }
        if (type == PKG_SOLVED_INSTALL && old == NULL && seen[index] == 0)
            seen[index] = 1;
        else if (type == PKG_SOLVED_UPGRADE && old != NULL && seen[index] == 0)
            seen[index] = 1;
        else if (type == PKG_SOLVED_UPGRADE_REMOVE && old != NULL && seen[index] == 0)
            seen[index] = 2;
        else if (type == PKG_SOLVED_UPGRADE_INSTALL && old != NULL && seen[index] == 2)
            seen[index] = 3;
        else
            goto done;
    }
    if (cursor != NULL)
        goto done;
    for (size_t i = 0; i < request->count; i++)
        if ((operation->changed[i] && seen[i] != 1 && seen[i] != 3) ||
            (!operation->changed[i] && seen[i] != 0))
            goto done;
    result = 0;
done:
    free(bytes);
    return result == 0 ? 0 : error("recovery requires a complete matching action plan");
}

static int
recovery_compare(struct update_operation *operation, struct update_snapshot *current,
    bool verify_only, const struct recovery_record *actions, const struct recovery_record *rejected)
{
    struct local_request *request = operation->apply.request;
    for (size_t i = 0; i < operation->prior->count; i++) {
        struct local_record *prior = &operation->prior->records[i];
        struct update_package *old = update_find(operation->before, prior->field[L_NAME]);
        if (old == NULL || !local_native_identity(old->package, prior)) {
            if (request->count == 0 || rejected->present || !actions->present)
                return error("recovery prior request differs from its retained roster");
            /* A recorded nonempty operation can replace or drop prior drift. */
            fprintf(stderr, "FreeBSD resolver: prior identity not retained from before: %s %s\n",
                prior->field[L_NAME], prior->field[L_VERSION]);
        }
    }
    for (size_t i = 0; i < operation->before->count; i++)
        if (update_find(current, operation->before->packages[i].name) == NULL)
            return error("recovery cannot adopt a missing installed package");
    for (size_t i = 0; i < current->count; i++) {
        struct update_package *actual = &current->packages[i];
        struct update_package *old = update_find(operation->before, actual->name);
        struct local_record *desired = apply_record(request, actual->package);
        struct pkg *expected = old == NULL ? NULL : old->package;
        const char *digest = old == NULL ? NULL : old->digest;
        bool same = old != NULL && update_same_identity(old->package, actual->package);
        if (!same) {
            if (verify_only)
                return error("recovery cannot adopt changes from a verification operation");
            if (rejected->present)
                return error("recovery cannot adopt changes from a rejected operation");
            if (!actions->present)
                return error("recovery requires a complete matching action plan");
            if (desired == NULL || (old != NULL && (old->locked ||
                strcmp(update_attribute(old->package, PKG_ATTR_ORIGIN), desired->field[L_ORIGIN]) != 0 ||
                strcmp(update_attribute(old->package, PKG_ATTR_ABI), desired->field[L_ABI]) != 0 ||
                pkg_version_cmp(update_attribute(old->package, PKG_ATTR_VERSION), desired->field[L_VERSION]) >= 0)))
                return error("recovery found an unauthorized installed identity");
            size_t index = (size_t)(desired - request->records);
            if (!operation->changed[index])
                return error("recovery identity has no authorized action");
            struct pkg **archive = &operation->archives[index];
            char path[LOCAL_PATH_BYTES];
            snprintf(path, sizeof(path), "%s/archives/p%zu.pkg", operation->apply.workspace, index);
            int opened = request->manifests ? update_manifest(operation, index, archive) :
                (pkg_open(archive, path, PKG_OPEN_MANIFEST_ONLY) == EPKG_OK ? 0 : -1);
            if (opened != 0 || *archive == NULL || pkg_type(*archive) != PKG_FILE ||
                pkg_is_valid(*archive) != EPKG_OK || !local_native_identity(*archive, desired) ||
                update_digest(*archive, operation->digests[index]) != 0)
                return error("recovery archive metadata differs");
            expected = *archive;
            digest = operation->digests[index];
        }
        if (expected == NULL || digest == NULL || strcmp(actual->digest, digest) != 0 ||
            !update_dependencies(expected, actual->package, request) ||
            (old != NULL && (old->automatic != actual->automatic || old->locked != actual->locked ||
                (same && old->timestamp != actual->timestamp))))
            return error("recovery installed metadata differs from retained inputs");
        struct pkg_dep *dependency = NULL;
        while (pkg_deps(actual->package, &dependency) == EPKG_OK) {
            const char *name = pkg_dep_name(dependency), *origin = pkg_dep_origin(dependency);
            const char *version = pkg_dep_version(dependency);
            struct update_package *installed = name == NULL ? NULL : update_find(current, name);
            if (installed == NULL || origin == NULL || version == NULL ||
                strcmp(update_attribute(installed->package, PKG_ATTR_ORIGIN), origin) != 0 ||
                strcmp(update_attribute(installed->package, PKG_ATTR_VERSION), version) != 0)
                return error("recovery requires present installed dependency identities");
        }
    }
    return 0;
}

/* This mode records provenance only. It never schedules or applies package jobs. */
static int
local_recover(const char *config, const char *request_path, const char *output_path)
{
    struct update_operation *operation = calloc(1, sizeof(*operation));
    struct update_snapshot *current = NULL;
    struct update_events events = {0};
    struct recovery_record actions = {0}, rejected = {0};
    struct pkgdb *db = NULL;
    DIR *output = NULL;
    struct stat output_state, before_state, started_state, repeated_state;
    char before_digest[65], started_digest[65], current_digest[65], managed_digest[65];
    char repeated_digest[65], queue[65], started_name[32], rejected_name[32], repeated_name[32];
    bool initialized = false, locked = false, verify_only = false, repeated_verify = false;
    int result = EXIT_FAILURE;
    if (operation == NULL)
        return EXIT_FAILURE;
    struct local_apply *apply = &operation->apply;
    if (geteuid() != 0 || getuid() != 0 || !local_environment() ||
        strcmp(pkg_libversion(), "2.6.2") != 0 || setlocale(LC_ALL, "C") == NULL) {
        error("package recovery requires root, pkg 2.6.2 and its clean environment");
        goto done;
    }
    closefrom(STDERR_FILENO + 1);
    umask(0022);
    if (update_prepare(operation, config, request_path, true, true) != 0)
        goto done;
    struct stat database_state;
    if (fstatat(dirfd(apply->directories[A_DB]), "local.sqlite", &database_state, AT_SYMLINK_NOFOLLOW) != 0 ||
        !S_ISREG(database_state.st_mode) || database_state.st_uid != 0 || database_state.st_gid != 0 ||
        database_state.st_nlink != 1 || (database_state.st_mode & 0022) != 0 || database_state.st_size <= 0) {
        error("package recovery requires an existing protected database");
        goto done;
    }
    char prefix[LOCAL_PATH_BYTES];
    int length = snprintf(prefix, sizeof(prefix), "%s/recovery.", apply->workspace);
    if (length <= 0 || (size_t)length >= sizeof(prefix) ||
        strlen(output_path) != (size_t)length + 8 || strncmp(output_path, prefix, (size_t)length) != 0 ||
        strspn(output_path + length, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789") != 8) {
        error("package recovery output must be a fresh protected attempt directory");
        goto done;
    }
    output = open_directory(output_path, &output_state, true);
    if (output == NULL || output_state.st_uid != 0 || output_state.st_gid != 0 ||
        (output_state.st_mode & 07777) != 0700)
        goto done;
    operation->before = calloc(1, sizeof(*operation->before));
    current = calloc(1, sizeof(*current));
    if (operation->before == NULL || current == NULL ||
        recovery_started(operation, started_digest, &started_state, started_name, &verify_only) != 0 ||
        recovery_before(operation, before_digest, &before_state) != 0)
        goto done;
    snprintf(rejected_name, sizeof(rejected_name), "%s.rejected", verify_only ? "local-verify" : "local-update");
    if (recovery_record(dirfd(apply->directories[A_WORK]), rejected_name, &rejected, NULL) != 0)
        goto done;
    events.operation = operation;
    events.phase = A_READBACK;
    pkg_event_register(update_event, &events);
    if (update_inputs(operation) != 0 || apply_queue(dirfd(apply->directories[A_DB]), true, queue) != 0 ||
        chdir("/") != 0 || pkg_init(config, apply->paths[A_REPOS]) != EPKG_OK)
        goto done;
    initialized = true;
    if (events.failed || apply_effective_config(apply) != 0 ||
        pkgdb_open(&db, PKGDB_DEFAULT) != EPKG_OK || pkgdb_obtain_lock(db, PKGDB_LOCK_ADVISORY) != EPKG_OK)
        goto done;
    locked = true;
    if (apply_queue(dirfd(apply->directories[A_DB]), true, queue) != 0 ||
        recovery_actions(operation, &actions) != 0 || update_snapshot(db, current) != 0 ||
        recovery_compare(operation, current, verify_only, &actions, &rejected) != 0 || events.failed ||
        update_roster(dirfd(output), "observed", current, current_digest) != 0 ||
        update_managed(operation, current, dirfd(output), true, managed_digest) != 0)
        goto done;
    result = EXIT_SUCCESS;
done:
    if (locked && pkgdb_release_lock(db, PKGDB_LOCK_ADVISORY) != EPKG_OK)
        result = EXIT_FAILURE;
    if (db != NULL)
        pkgdb_close(db);
    if (initialized)
        pkg_shutdown();
    if (events.failed)
        result = EXIT_FAILURE;
    if (result == EXIT_SUCCESS && (update_inputs(operation) != 0 ||
        fstat(dirfd(output), &repeated_state) != 0 || !apply_same_directory(&output_state, &repeated_state) ||
        lstat(output_path, &repeated_state) != 0 || !apply_same_directory(&output_state, &repeated_state) ||
        local_read_mode(dirfd(apply->directories[A_WORK]), "before", UINT64_C(134217728),
            NULL, NULL, repeated_digest, &repeated_state, 0600) != 0 ||
        strcmp(before_digest, repeated_digest) != 0 || !local_same_file(&before_state, &repeated_state) ||
        recovery_started(operation, repeated_digest, &repeated_state, repeated_name, &repeated_verify) != 0 ||
        repeated_verify != verify_only ||
        strcmp(started_digest, repeated_digest) != 0 || !local_same_file(&started_state, &repeated_state) ||
        recovery_record_same(dirfd(apply->directories[A_WORK]), "actions", &actions) != 0 ||
        recovery_record_same(dirfd(apply->directories[A_WORK]), rejected_name, &rejected) != 0 ||
        empty_root(apply->directories[A_CACHE], apply->paths[A_CACHE], &apply->states[A_CACHE]) != 0 ||
        empty_root(apply->directories[A_REPOS], apply->paths[A_REPOS], &apply->states[A_REPOS]) != 0))
        result = EXIT_FAILURE;
    if (result == EXIT_SUCCESS) {
        char receipt[1536];
        int length = snprintf(receipt, sizeof(receipt),
            "format\txcat-freebsd-local-recover-1\nscope\tprovenance-only\n"
            "plan-reference\t%s\nrequest-sha256\t%s\nprior-request-sha256\t%s\n"
            "started-sha256\t%s\nbefore-sha256\t%s\nobserved-sha256\t%s\nmanaged-request-sha256\t%s\n"
            "operation-scope\t%s\nactions-sha256\t%s\nrejected-sha256\t%s\n"
            "pkg\t2.6.2\npackages\t%zu\nexecution\tuncertain\ncomplete\tyes\n",
            apply->request->plan, apply->request->sha256, operation->prior->sha256,
            started_digest, before_digest, current_digest, managed_digest,
            verify_only ? "local-verify" : "local-update", actions.digest, rejected.digest, current->count);
        if (length <= 0 || (size_t)length >= sizeof(receipt) ||
            apply_record_write(dirfd(output), "local-recover.result", receipt, (size_t)length) != 0)
            result = EXIT_FAILURE;
    }
    for (size_t i = 0; i < MAX_NAMES; i++)
        pkg_free(operation->archives[i]);
    update_free_snapshot(operation->before);
    update_free_snapshot(current);
    for (size_t i = 0; i < 6; i++)
        if (apply->directories[i] != NULL && closedir(apply->directories[i]) != 0)
            result = EXIT_FAILURE;
    if (output != NULL && closedir(output) != 0)
        result = EXIT_FAILURE;
    if (apply->request != NULL)
        free(apply->request->bytes);
    if (operation->prior != NULL)
        free(operation->prior->bytes);
    free(apply->request);
    free(operation->prior);
    free(operation);
    return result;
}

static int
local_update(const char *config, const char *request_path, const char *root_path,
    bool verify_only)
{
    struct update_operation *operation = calloc(1, sizeof(*operation));
    struct update_snapshot *after = NULL;
    struct update_events *events = MAP_FAILED;
    struct pkgdb *db = NULL;
    struct pkg_jobs *jobs = NULL;
    bool initialized = false, locked = false, prepared = false, apply_entered = false;
    char queue[65], before_digest[65], after_digest[65], managed_digest[65];
    const char *scope = verify_only ? "local-verify" : "local-update";
    int result = EXIT_FAILURE;
    if (operation == NULL)
        return EXIT_FAILURE;
    struct local_apply *apply = &operation->apply;
    if (strcmp(root_path, "/") != 0 || geteuid() != 0 || getuid() != 0 ||
        !local_environment() || strcmp(pkg_libversion(), "2.6.2") != 0 || setlocale(LC_ALL, "C") == NULL) {
        error("installed operation requires the live root, pkg 2.6.2 and its clean environment");
        goto done;
    }
    int input = open("/dev/null", O_RDONLY | O_NOFOLLOW);
    if (input == -1 || dup2(input, STDIN_FILENO) == -1) {
        if (input != -1)
            close(input);
        error("cannot isolate installed-operation input");
        goto done;
    }
    if (input > STDERR_FILENO)
        close(input);
    closefrom(STDERR_FILENO + 1);
    umask(0022);
    if (update_prepare(operation, config, request_path, verify_only, false) != 0)
        goto done;
    prepared = true;
    operation->before = calloc(1, sizeof(*operation->before));
    after = calloc(1, sizeof(*after));
    events = mmap(NULL, sizeof(*events), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANON, -1, 0);
    if (operation->before == NULL || after == NULL || events == MAP_FAILED) {
        error("cannot allocate installed-operation state");
        goto done;
    }
    events->operation = operation;
    events->phase = A_VALIDATE;
    pkg_event_register(update_event, events);
    /* pkg_set_rootdir defers triggers, including when its argument is the live root. */
    if (update_inputs(operation) != 0 || apply_queue(dirfd(apply->directories[A_DB]), true, queue) != 0 ||
        apply_write(apply, scope, false) != 0 ||
        chdir("/") != 0 || pkg_init(config, apply->paths[A_REPOS]) != EPKG_OK)
        goto done;
    initialized = true;
    if (events->failed || apply_effective_config(apply) != 0 ||
        pkgdb_open(&db, PKGDB_DEFAULT) != EPKG_OK ||
        pkgdb_obtain_lock(db, PKGDB_LOCK_ADVISORY) != EPKG_OK)
        goto done;
    locked = true;
    if (apply_queue(dirfd(apply->directories[A_DB]), true, queue) != 0 ||
        update_snapshot(db, operation->before) != 0 ||
        update_roster(dirfd(apply->directories[A_WORK]), "before", operation->before, before_digest) != 0 ||
        pkg_jobs_new(&jobs, PKG_JOBS_INSTALL, db) != EPKG_OK)
        goto done;
    events->jobs = jobs;
    pkg_jobs_set_flags(jobs, PKG_FLAG_NONE);
    if (update_select(operation, jobs, db) != 0 || events->failed)
        goto done;
    if (verify_only && operation->changes != 0) {
        error("required packages are not satisfied; verification cannot install or upgrade");
        goto done;
    }
    if (operation->changes != 0 && (pkg_jobs_solve(jobs) != EPKG_OK || events->failed ||
        pkg_jobs_schedule(jobs) != EPKG_OK || update_jobs(operation, jobs, false) != 0))
        goto done;
    if (update_inputs(operation) != 0 || events->failed)
        goto done;
    char *actions = NULL;
    size_t action_bytes = 0;
    FILE *stream = open_memstream(&actions, &action_bytes);
    if (stream == NULL)
        goto done;
    fprintf(stream, "format\txcat-freebsd-update-actions-1\n");
    for (size_t i = 0; i < operation->step_count; i++) {
        const struct update_step *step = &operation->steps[i];
        fprintf(stream, "action\t%zu\t%d\t%s\t%s\t%s\n", i + 1, step->type,
            apply->request->records[step->record].field[L_NAME],
            operation->old[step->record] == NULL ? "-" :
                update_attribute(operation->old[step->record]->package, PKG_ATTR_VERSION),
            apply->request->records[step->record].field[L_VERSION]);
    }
    bool output_failed = ferror(stream) != 0;
    if (fclose(stream) != 0)
        output_failed = true;
    int written = output_failed ? -1 : apply_record_write(dirfd(apply->directories[A_WORK]),
        "actions", actions, action_bytes);
    free(actions);
    if (written != 0)
        goto done;
    if (operation->changes != 0) {
        events->phase = A_INSTALL;
        apply_entered = true;
        int status = pkg_jobs_apply(jobs);
        if (status != EPKG_OK || events->failed ||
            events->actions != operation->step_count || events->finished != 3) {
            fprintf(stderr, "FreeBSD resolver: update status %d, actions %zu/%zu, last action %u\n",
                status, events->actions, operation->step_count, events->finished);
            error("native installed operation did not complete");
            goto done;
        }
    }
    events->phase = A_READBACK;
    if (apply_queue(dirfd(apply->directories[A_DB]), true, queue) != 0 ||
        update_snapshot(db, after) != 0 || update_readback(operation, after) != 0 ||
        update_roster(dirfd(apply->directories[A_WORK]), "after", after, after_digest) != 0 ||
        update_managed(operation, after, dirfd(apply->directories[A_WORK]), false, managed_digest) != 0 || events->failed)
        goto done;
    result = EXIT_SUCCESS;
done:
    pkg_jobs_free(jobs);
    if (locked && pkgdb_release_lock(db, PKGDB_LOCK_ADVISORY) != EPKG_OK)
        result = EXIT_FAILURE;
    if (db != NULL)
        pkgdb_close(db);
    if (initialized)
        pkg_shutdown();
    if (events != MAP_FAILED && events->failed)
        result = EXIT_FAILURE;
    if (result == EXIT_SUCCESS && (update_inputs(operation) != 0 ||
        empty_root(apply->directories[A_CACHE], apply->paths[A_CACHE], &apply->states[A_CACHE]) != 0 ||
        empty_root(apply->directories[A_REPOS], apply->paths[A_REPOS], &apply->states[A_REPOS]) != 0))
        result = EXIT_FAILURE;
    if (result == EXIT_SUCCESS) {
        char receipt[1024];
        int length = snprintf(receipt, sizeof(receipt),
            "format\t%s\nscope\t%s\n"
            "plan-reference\t%s\nrequest-sha256\t%s\nprior-request-sha256\t%s\n"
            "before-sha256\t%s\nafter-sha256\t%s\nmanaged-request-sha256\t%s\n"
            "pkg\t2.6.2\npackages\t%zu\nchanges\t%zu\nactions\t%zu\n"
            "outcome\t%s\ncomplete\tyes\n",
            verify_only ? "xcat-freebsd-local-verify-1" : "xcat-freebsd-local-update-1", scope,
            apply->request->plan, apply->request->sha256,
            operation->prior->sha256, before_digest, after_digest, managed_digest,
            after->count, operation->changes, events->actions,
            operation->changes == 0 ? "no-change" : "changed");
        const char *record = verify_only ? "local-verify.result" : "local-update.result";
        if (length <= 0 || (size_t)length >= sizeof(receipt) ||
            apply_record_write(dirfd(apply->directories[A_WORK]), record, receipt, (size_t)length) != 0)
            result = EXIT_FAILURE;
    }
    if (result != EXIT_SUCCESS && prepared && !apply_entered)
        update_rejection(operation, scope);
    if (events != MAP_FAILED && munmap(events, sizeof(*events)) != 0)
        result = EXIT_FAILURE;
    for (size_t i = 0; i < MAX_NAMES; i++)
        pkg_free(operation->archives[i]);
    update_free_snapshot(operation->before);
    update_free_snapshot(after);
    for (size_t i = 0; i < 6; i++)
        if (apply->directories[i] != NULL && closedir(apply->directories[i]) != 0)
            result = EXIT_FAILURE;
    if (apply->request != NULL)
        free(apply->request->bytes);
    if (operation->prior != NULL)
        free(operation->prior->bytes);
    free(apply->request);
    free(operation->prior);
    free(operation);
    return result;
}
#endif

int
main(int argc, char **argv)
{
    if ((argc != 4 && argc != 6) || strcmp(argv[1], "-C") != 0 ||
        argv[2][0] != '/') {
        error("usage: freebsd-pkg-resolve -C /config {-v | resolve /request /empty-root}");
        return EXIT_FAILURE;
    }
    if (argc == 4 && strcmp(argv[3], "-v") == 0)
        return printf("%s\n", pkg_libversion()) < 0 || fflush(stdout) != 0;
#if defined(__FreeBSD__) && XCAT_PKG_TARGET_VERSION == 20602
    if (argc == 6 && strcmp(argv[3], "local-recover") == 0)
        return local_recover(argv[2], argv[4], argv[5]);
    if (argc == 6 && (strcmp(argv[3], "local-update") == 0 || strcmp(argv[3], "local-verify") == 0))
        return local_update(argv[2], argv[4], argv[5], strcmp(argv[3], "local-verify") == 0);
    if (argc == 6 && strcmp(argv[3], "local-check") == 0)
        return local_check(argv[2], argv[4], argv[5]);
    if (argc == 6 && (strcmp(argv[3], "local-install") == 0 ||
        strcmp(argv[3], "local-finalize") == 0))
        return local_apply(argv[2], argv[4], argv[5], strcmp(argv[3], "local-finalize") == 0);
#endif
    if (argc != 6 || strcmp(argv[3], "resolve") != 0 || argv[4][0] != '/' ||
        argv[5][0] != '/') {
        error("invalid resolver arguments");
        return EXIT_FAILURE;
    }
    struct request request = {0};
    struct pkgdb *db = NULL;
    struct pkg_jobs *jobs = NULL;
    struct stat root_state;
    DIR *root = NULL;
    bool initialized = false, failed = false;
    int result = EXIT_FAILURE;
    if (strcmp(pkg_libversion(), EXPECTED_PKG_VERSION) != 0 || setlocale(LC_ALL, "C") == NULL) {
        error("pkg " EXPECTED_PKG_VERSION " and the C locale are required");
        goto done;
    }
    if (read_request(argv[4], &request) != 0)
        goto done;
    root = open_root(argv[5], &root_state);
    if (root == NULL)
        goto done;
    pkg_event_register(events, &failed);
    /* System-library discovery must use the empty target, not the runtime filesystem. */
    if (pkg_set_rootdir(argv[5]) != EPKG_OK) {
        error("cannot set resolver root");
        goto done;
    }
    if (pkg_init(argv[2], NULL) != EPKG_OK) {
        error("cannot initialize pkg");
        goto done;
    }
    initialized = true;
    if (failed)
        goto done;
    pkgdb_set_case_sensitivity(true);
    if (pkgdb_open_all(&db, PKGDB_MAYBE_REMOTE, NULL) != EPKG_OK || failed ||
        pkg_jobs_new(&jobs, PKG_JOBS_INSTALL, db) != EPKG_OK) {
        error("cannot open isolated package jobs");
        goto done;
    }
    pkg_jobs_set_flags(jobs,
        PKG_FLAG_DRY_RUN | PKG_FLAG_NOSCRIPT | PKG_FLAG_PKG_VERSION_TEST);
    for (size_t i = 0; i < request.count; i++)
        if (add_name(db, jobs, request.names[i]) != 0)
            goto done;
    if (failed || pkg_jobs_solve(jobs) != EPKG_OK || failed) {
        error("cannot solve package requests");
        goto done;
    }
    if (empty_root(root, argv[5], &root_state) == 0 && emit_jobs(jobs) == 0 && !failed)
        result = EXIT_SUCCESS;
done:
    pkg_jobs_free(jobs);
    if (db != NULL)
        pkgdb_close(db);
    if (initialized)
        pkg_shutdown();
    if (failed)
        result = EXIT_FAILURE;
    if (root != NULL) {
        if (result == EXIT_SUCCESS && empty_root(root, argv[5], &root_state) != 0)
            result = EXIT_FAILURE;
        if (closedir(root) != 0) {
            error("cannot close resolver root");
            result = EXIT_FAILURE;
        }
    }
    free(request.bytes);
    return result;
}
