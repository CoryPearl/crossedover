#include "CArchive.h"
#include <archive.h>
#include <archive_entry.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

static int safe_path(const char *path, int initial_depth) {
    if (!path || path[0] == '/' || strchr(path, '\\')) return 0;
    char *copy = strdup(path), *save = NULL;
    if (!copy) return 0;
    int depth = initial_depth;
    for (char *part = strtok_r(copy, "/", &save); part; part = strtok_r(NULL, "/", &save)) {
        if (!strcmp(part, "..")) { if (--depth < 0) { free(copy); return 0; } }
        else if (strcmp(part, ".")) depth++;
    }
    free(copy); return 1;
}

int crossedover_extract(const char *source, const char *destination, char *error, size_t error_size) {
    char canonical_destination[PATH_MAX];
    if (!realpath(destination, canonical_destination)) { snprintf(error,error_size,"Could not resolve extraction destination"); return -1; }
    destination = canonical_destination;
    struct archive *reader = archive_read_new(), *writer = archive_write_disk_new();
    struct archive_entry *entry;
    int result = -1, status;
    unsigned long long total = 0; unsigned int count = 0;
    archive_read_support_filter_all(reader); archive_read_support_format_all(reader);
    archive_write_disk_set_options(writer, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_SECURE_SYMLINKS | ARCHIVE_EXTRACT_SECURE_NODOTDOT);
    if (archive_read_open_filename(reader, source, 1024 * 1024) != ARCHIVE_OK) goto failure;
    while ((status = archive_read_next_header(reader, &entry)) == ARCHIVE_OK) {
        const char *name = archive_entry_pathname(entry);
        if (!safe_path(name, 0) || ++count > 150000 || archive_entry_size(entry) < 0) { snprintf(error,error_size,"Unsafe archive entry or entry limit exceeded"); goto done; }
        total += (unsigned long long)archive_entry_size(entry);
        if (total > 12ULL * 1024 * 1024 * 1024) { snprintf(error,error_size,"Archive exceeds 12 GiB extraction limit"); goto done; }
        int kind = archive_entry_filetype(entry);
        if (kind != AE_IFREG && kind != AE_IFDIR && kind != AE_IFLNK) { snprintf(error,error_size,"Unsupported archive entry type"); goto done; }
        if (archive_entry_hardlink(entry)) { snprintf(error,error_size,"Hard links are not accepted"); goto done; }
        const char *link = archive_entry_symlink(entry);
        if (link) {
            int depth = 0;
            for (const char *p = name; *p; p++) if (*p == '/') depth++;
            if (!safe_path(link, depth)) { snprintf(error,error_size,"Archive symlink escapes its destination"); goto done; }
        }
        char full[PATH_MAX];
        if (snprintf(full, sizeof(full), "%s/%s", destination, name) >= (int)sizeof(full)) { snprintf(error,error_size,"Archive path is too long"); goto done; }
        archive_entry_set_pathname(entry, full);
        archive_entry_set_perm(entry, archive_entry_perm(entry) & 0777);
        if (archive_write_header(writer, entry) != ARCHIVE_OK) goto failure;
        const void *buffer; size_t size; la_int64_t offset;
        while ((status = archive_read_data_block(reader, &buffer, &size, &offset)) == ARCHIVE_OK) {
            if (offset < 0 || (unsigned long long)offset + size > 12ULL * 1024 * 1024 * 1024) { snprintf(error,error_size,"Invalid archive block offset"); goto done; }
            if (archive_write_data_block(writer, buffer, size, offset) != ARCHIVE_OK) goto failure;
        }
        if (status != ARCHIVE_EOF || archive_write_finish_entry(writer) != ARCHIVE_OK) goto failure;
    }
    if (status != ARCHIVE_EOF) goto failure;
    result = 0; goto done;
failure:
    snprintf(error, error_size, "%s", archive_error_string(reader) ? archive_error_string(reader) : (archive_error_string(writer) ? archive_error_string(writer) : "Archive extraction failed"));
done:
    archive_read_free(reader); archive_write_free(writer); return result;
}
