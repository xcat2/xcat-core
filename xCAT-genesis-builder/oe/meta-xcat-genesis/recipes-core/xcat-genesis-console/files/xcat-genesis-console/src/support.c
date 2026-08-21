// SPDX-License-Identifier: EPL-1.0

#include "console.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

int xcat_set_signal_handler(int signal_number, void (*handler)(int)) {
    struct sigaction action = {.sa_handler = handler};

    sigemptyset(&action.sa_mask);
    return sigaction(signal_number, &action, NULL);
}

const char *xcat_path_from_env(const char *name, const char *fallback) {
    const char *value = getenv(name);

    return value != NULL && value[0] != '\0' ? value : fallback;
}

void xcat_copy_printable(char *destination, size_t size, const char *source) {
    size_t written = 0;

    if (size == 0)
        return;
    while (*source != '\0' && written + 1 < size) {
        unsigned char byte = (unsigned char)*source++;

        if (byte >= 32 && byte <= 126)
            destination[written++] = (char)byte;
        else if (byte == '\t' || byte == '\r' || byte == '\n')
            destination[written++] = ' ';
    }
    destination[written] = '\0';
}

void xcat_set_text(char *destination, size_t size, const char *format, ...) {
    char buffer[VALUE_SIZE * 2];
    va_list arguments;

    va_start(arguments, format);
    vsnprintf(buffer, sizeof(buffer), format, arguments);
    va_end(arguments);
    xcat_copy_printable(destination, size, buffer);
}

char *xcat_read_allocated_line(const char *path) {
    FILE *stream;
    char *line = NULL;
    size_t capacity = 0;
    char *line_end;
    struct stat file_status;

    if (stat(path, &file_status) != 0 || !S_ISREG(file_status.st_mode))
        return NULL;
    stream = fopen(path, "r");
    if (stream == NULL)
        return NULL;
    if (getline(&line, &capacity, stream) < 0) {
        fclose(stream);
        free(line);
        return NULL;
    }
    fclose(stream);
    line_end = strpbrk(line, "\r\n");
    if (line_end != NULL)
        *line_end = '\0';
    return line;
}

bool xcat_read_line(const char *path, char *value, size_t size) {
    char *line = xcat_read_allocated_line(path);

    if (line == NULL)
        return false;
    xcat_copy_printable(value, size, line);
    free(line);
    return true;
}

static void strip_quotes(char *value) {
    size_t length = strlen(value);

    if (length >= 2 && value[0] == '"' && value[length - 1] == '"') {
        memmove(value, value + 1, length - 2);
        value[length - 2] = '\0';
    }
}

bool xcat_read_key(const char *path, const char *key, char *value, size_t size) {
    FILE *stream;
    char line[LINE_SIZE];
    size_t key_length = strlen(key);
    char *line_end;
    struct stat file_status;
    bool found = false;

    if (key_length == 0 || key_length + 1 >= sizeof(line))
        return false;
    if (stat(path, &file_status) != 0 || !S_ISREG(file_status.st_mode))
        return false;
    stream = fopen(path, "r");
    if (stream == NULL)
        return false;
    while (fgets(line, sizeof(line), stream) != NULL) {
        if (strncmp(line, key, key_length) != 0 || line[key_length] != '=')
            continue;
        line_end = strpbrk(line, "\r\n");
        if (line_end != NULL)
            *line_end = '\0';
        xcat_copy_printable(value, size, line + key_length + 1);
        strip_quotes(value);
        found = true;
        break;
    }
    fclose(stream);
    return found;
}

bool xcat_safe_name(const char *value) {
    const unsigned char *cursor = (const unsigned char *)value;

    if (*cursor == '\0')
        return false;
    for (; *cursor != '\0'; cursor++) {
        if (!isalnum(*cursor) && *cursor != '_' && *cursor != '-' && *cursor != '.' &&
            *cursor != ':')
            return false;
    }
    return true;
}

bool xcat_cmdline_value(const char *cmdline, const char *key, char *value, size_t size) {
    char *copy;
    char *save = NULL;
    char *token;
    size_t key_length = strlen(key);
    bool found = false;

    copy = strdup(cmdline);
    if (copy == NULL)
        return false;
    for (token = strtok_r(copy, " ", &save); token != NULL; token = strtok_r(NULL, " ", &save)) {
        if (strncmp(token, key, key_length) == 0 && token[key_length] == '=') {
            xcat_copy_printable(value, size, token + key_length + 1);
            found = true;
            break;
        }
    }
    free(copy);
    return found;
}

unsigned long long xcat_read_uptime(void) {
    const char *path = xcat_path_from_env("XCAT_UPTIME_FILE", "/proc/uptime");
    FILE *stream = fopen(path, "r");
    double seconds = 0;

    if (stream == NULL)
        return 0;
    if (fscanf(stream, "%lf", &seconds) != 1 || seconds < 0)
        seconds = 0;
    fclose(stream);
    return (unsigned long long)seconds;
}

void xcat_format_duration(unsigned long long seconds, char *value, size_t size) {
    unsigned long long days = seconds / 86400;
    unsigned int hours = (unsigned int)((seconds % 86400) / 3600);
    unsigned int minutes = (unsigned int)((seconds % 3600) / 60);
    unsigned int remaining = (unsigned int)(seconds % 60);

    if (days > 0)
        snprintf(value, size, "%llud %02u:%02u:%02u", days, hours, minutes, remaining);
    else
        snprintf(value, size, "%02u:%02u:%02u", hours, minutes, remaining);
}

static bool parse_unsigned(const char *value, unsigned long long *number) {
    char *end = NULL;

    errno = 0;
    *number = strtoull(value, &end, 10);
    return errno == 0 && end != value && *end == '\0';
}

bool xcat_read_unsigned_key(const char *path, const char *key, unsigned long long *number) {
    char value[32];

    return xcat_read_key(path, key, value, sizeof(value)) && parse_unsigned(value, number);
}

unsigned int xcat_list_files(const char *directory, const char *suffix, char *names,
                             size_t names_size) {
    DIR *stream;
    const struct dirent *entry;
    unsigned int count = 0;
    size_t suffix_length = strlen(suffix);

    if (names_size > 0)
        names[0] = '\0';

    stream = opendir(directory);
    if (stream == NULL)
        return 0;
    while ((entry = readdir(stream)) != NULL) {
        size_t name_length = strlen(entry->d_name);
        char path[VALUE_SIZE * 2];
        struct stat file_status;

        if (name_length <= suffix_length ||
            strcmp(entry->d_name + name_length - suffix_length, suffix) != 0)
            continue;
        snprintf(path, sizeof(path), "%s/%s", directory, entry->d_name);
        if (lstat(path, &file_status) == 0 && S_ISREG(file_status.st_mode)) {
            size_t used = strlen(names);

            count++;
            if (used + name_length + 3 < names_size) {
                snprintf(names + used, names_size - used, "%s%s", used > 0 ? ", " : "",
                         entry->d_name);
            }
        }
    }
    closedir(stream);
    return count;
}

int xcat_header_context_columns(int screen_columns) {
    if (screen_columns <= HEADER_RESERVED_COLUMNS)
        return 0;
    return screen_columns - HEADER_RESERVED_COLUMNS;
}
