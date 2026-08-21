// SPDX-License-Identifier: EPL-1.0

#ifndef XCAT_GENESIS_CONSOLE_H
#define XCAT_GENESIS_CONSOLE_H

#include <signal.h>
#include <stdbool.h>
#include <stddef.h>

enum xcat_console_limit {
    VALUE_SIZE = 192,
    DETAIL_SIZE = 161,
    LINE_SIZE = 512,
    MAIN_VALUE_WIDTH = 54,
    NAME_LIST_SIZE = 256,
    LOG_LINE_COUNT = 128,
    LOG_LINE_SIZE = 384,
    LOG_VIEW_HEIGHT = 17,
    LOG_VIEW_WIDTH = 68,
    HEADER_RESERVED_COLUMNS = 20,
};

struct console_state {
    char state[32];
    char activity[DETAIL_SIZE];
    char stage_time[32];
    char progress[80];
    char error[DETAIL_SIZE];
    char recovery[DETAIL_SIZE];
    char network_state[32];
    char network_detail[DETAIL_SIZE];
    char extension_state[32];
    char extension_detail[DETAIL_SIZE];
    char registration_state[32];
    char registration_detail[DETAIL_SIZE];
    char action_state[32];
    char action_detail[DETAIL_SIZE];
    char node[64];
    char local_hostname[64];
    char serial[VALUE_SIZE];
    char uuid[VALUE_SIZE];
    char release[96];
    char architecture[32];
    char kernel[96];
    char firmware[32];
    char boot_method[32];
    char interface[32];
    char link_state[24];
    char network_method[16];
    char address[80];
    char mac[32];
    char gateway[80];
    char dns[VALUE_SIZE];
    char xcat_endpoint[128];
    char xcat_state[32];
    char action_code[64];
    char action[64];
    char target[VALUE_SIZE];
    unsigned int extensions;
    unsigned int providers;
    char extension_names[NAME_LIST_SIZE];
    char provider_names[NAME_LIST_SIZE];
};

enum status_field {
    STATUS_FIELD_STATE,
    STATUS_FIELD_STAGE_TIME,
    STATUS_FIELD_ACTIVITY,
    STATUS_FIELD_NODE,
    STATUS_FIELD_SERIAL,
    STATUS_FIELD_INTERFACE,
    STATUS_FIELD_LINK,
    STATUS_FIELD_METHOD,
    STATUS_FIELD_ADDRESS,
    STATUS_FIELD_MAC,
    STATUS_FIELD_XCAT_SERVER,
    STATUS_FIELD_XCAT_STATUS,
    STATUS_FIELD_ACTION,
    STATUS_FIELD_DETAIL_ONE,
    STATUS_FIELD_DETAIL_TWO,
    STATUS_FIELD_COUNT,
};

enum status_severity {
    STATUS_SEVERITY_NORMAL,
    STATUS_SEVERITY_WARNING,
    STATUS_SEVERITY_ERROR,
};

struct status_field_value {
    char label[24];
    char value[DETAIL_SIZE];
};

struct status_view {
    char identity[VALUE_SIZE];
    struct status_field_value fields[STATUS_FIELD_COUNT];
    enum status_severity severity;
};

extern volatile sig_atomic_t xcat_console_stop_requested;

int xcat_set_signal_handler(int signal_number, void (*handler)(int));
const char *xcat_path_from_env(const char *name, const char *fallback);
void xcat_copy_printable(char *destination, size_t size, const char *source);
void xcat_set_text(char *destination, size_t size, const char *format, ...);
char *xcat_read_allocated_line(const char *path);
bool xcat_read_line(const char *path, char *value, size_t size);
bool xcat_read_key(const char *path, const char *key, char *value, size_t size);
bool xcat_safe_name(const char *value);
bool xcat_cmdline_value(const char *cmdline, const char *key, char *value, size_t size);
unsigned long long xcat_read_uptime(void);
void xcat_format_duration(unsigned long long seconds, char *value, size_t size);
bool xcat_read_unsigned_key(const char *path, const char *key, unsigned long long *number);
unsigned int xcat_list_files(const char *directory, const char *suffix, char *names,
                             size_t names_size);
int xcat_header_context_columns(int screen_columns);

void xcat_load_console_state(struct console_state *state);
void xcat_build_status_view(const struct console_state *state, struct status_view *view);
bool xcat_status_view_changed(const struct status_view *previous,
                              const struct status_view *current);
void xcat_format_diagnostics(const struct console_state *state, char *text, size_t size);

int xcat_run_maintenance_shell(void);
int xcat_run_plain(bool once);
#ifndef XCAT_CONSOLE_PLAIN_ONLY
int xcat_run_newt(void);
#endif

#endif
