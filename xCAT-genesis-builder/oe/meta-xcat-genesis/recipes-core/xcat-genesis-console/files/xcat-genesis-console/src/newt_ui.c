// SPDX-License-Identifier: EPL-1.0

#include "console.h"

#include <newt.h>
#include <systemd/sd-journal.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

struct status_field_layout {
    int label_left;
    int value_left;
    int row;
    int width;
};

static const struct status_field_layout status_layout[STATUS_FIELD_COUNT] = {
    [STATUS_FIELD_STATE] = {2, 15, 0, 23},
    [STATUS_FIELD_STAGE_TIME] = {40, 53, 0, 15},
    [STATUS_FIELD_ACTIVITY] = {2, 15, 1, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_NODE] = {2, 15, 3, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_SERIAL] = {2, 15, 4, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_INTERFACE] = {2, 15, 6, 23},
    [STATUS_FIELD_LINK] = {40, 53, 6, 15},
    [STATUS_FIELD_METHOD] = {2, 15, 7, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_ADDRESS] = {2, 15, 8, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_MAC] = {2, 15, 9, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_XCAT_SERVER] = {2, 15, 11, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_XCAT_STATUS] = {2, 15, 12, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_ACTION] = {2, 15, 14, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_DETAIL_ONE] = {2, 15, 15, MAIN_VALUE_WIDTH},
    [STATUS_FIELD_DETAIL_TWO] = {2, 15, 16, MAIN_VALUE_WIDTH},
};

_Static_assert(sizeof(status_layout) / sizeof(status_layout[0]) == STATUS_FIELD_COUNT,
               "status layout must cover every field");

struct console_form {
    newtComponent form;
    newtComponent keys[STATUS_FIELD_COUNT];
    newtComponent values[STATUS_FIELD_COUNT];
};

static newtComponent fixed_label(int left, int top, int width) {
    char blank[MAIN_VALUE_WIDTH + 1];

    if (width > MAIN_VALUE_WIDTH)
        width = MAIN_VALUE_WIDTH;
    memset(blank, ' ', (size_t)width);
    blank[width] = '\0';
    return newtLabel(left, top, blank);
}

static void set_label(newtComponent label, const char *value, int width) {
    char padded[MAIN_VALUE_WIDTH + 1];

    if (width > MAIN_VALUE_WIDTH)
        width = MAIN_VALUE_WIDTH;
    snprintf(padded, sizeof(padded), "%-*.*s", width, width, value);
    newtLabelSetText(label, padded);
}

static void add_status_field(struct console_form *screen, const struct status_view *view,
                             enum status_field field) {
    const struct status_field_layout *layout = &status_layout[field];

    screen->keys[field] = newtLabel(layout->label_left, layout->row, view->fields[field].label);
    screen->values[field] = fixed_label(layout->value_left, layout->row, layout->width);
    newtFormAddComponents(screen->form, screen->keys[field], screen->values[field], NULL);
}

static struct console_form create_form(const struct status_view *view) {
    struct console_form screen = {0};
    newtComponent separator;

    newtCenteredWindow(72, 17, "Genesis status");
    screen.form = newtForm(NULL, NULL, NEWT_FLAG_NOF12);
    for (enum status_field field = STATUS_FIELD_STATE; field < STATUS_FIELD_COUNT; field++)
        add_status_field(&screen, view, field);

    separator =
        newtLabel(2, 2, "--------------------------------------------------------------------");
    newtFormAddComponent(screen.form, separator);

    separator =
        newtLabel(2, 5, "--------------------------------------------------------------------");
    newtFormAddComponent(screen.form, separator);

    separator =
        newtLabel(2, 10, "--------------------------------------------------------------------");
    newtFormAddComponent(screen.form, separator);

    separator =
        newtLabel(2, 13, "--------------------------------------------------------------------");
    newtFormAddComponent(screen.form, separator);

    newtFormAddHotKey(screen.form, NEWT_KEY_F1);
    newtFormAddHotKey(screen.form, NEWT_KEY_F2);
    newtFormAddHotKey(screen.form, NEWT_KEY_F3);
    newtFormAddHotKey(screen.form, NEWT_KEY_F12);
    newtFormSetTimer(screen.form, 1000);
    return screen;
}

static void draw_header(const struct status_view *view) {
    char context[VALUE_SIZE];
    int available;
    int columns;

    newtGetScreenSize(&columns, NULL);
    available = columns - 20;
    xcat_set_text(context, sizeof(context), "%.*s", available, view->identity);
    if ((int)strlen(context) > available)
        context[available] = '\0';
    newtDrawRootText(1, 0, "xCAT Genesis");
    newtDrawRootText(-((int)strlen(context) + 1), 0, context);
}

static void update_form(struct console_form *screen, const struct status_view *view,
                        bool full_update) {
    int color = NEWT_COLORSET_CUSTOM(0);

    set_label(screen->values[STATUS_FIELD_STAGE_TIME], view->fields[STATUS_FIELD_STAGE_TIME].value,
              status_layout[STATUS_FIELD_STAGE_TIME].width);
    if (full_update) {
        for (enum status_field field = STATUS_FIELD_STATE; field < STATUS_FIELD_COUNT; field++) {
            if (field == STATUS_FIELD_STAGE_TIME)
                continue;
            newtLabelSetText(screen->keys[field], view->fields[field].label);
            set_label(screen->values[field], view->fields[field].value, status_layout[field].width);
        }

        if (view->severity == STATUS_SEVERITY_ERROR)
            color = NEWT_COLORSET_CUSTOM(2);
        else if (view->severity == STATUS_SEVERITY_WARNING)
            color = NEWT_COLORSET_CUSTOM(1);
        newtLabelSetColors(screen->values[STATUS_FIELD_STATE], color);
    }
    draw_header(view);
    newtRefresh();
}

static const char help_text[] =
    "This console reports Genesis status. Status pages are read-only. F12 "
    "opens a confirmed root maintenance shell.\n\n"
    "Screen fields\n\n"
    "State is the result of the stage currently controlling Genesis.\n"
    "In stage is how long that stage has been active.\n"
    "Activity describes what the stage is doing.\n"
    "Node is the name confirmed by xCAT. It remains unassigned before "
    "discovery or registration.\n"
    "Serial is the hardware serial reported by firmware. The title shows the "
    "assigned node, or the local hostname before assignment, followed by the "
    "serial when available.\n\n"
    "Interface is the selected management device. Method is DHCP, Static, or "
    "SLAAC/DHCPv6. Address and MAC identify that interface.\n\n"
    "xCAT server is the endpoint supplied by the management node. xCAT contact "
    "can be:\n"
    "  Not configured - no endpoint was supplied.\n"
    "  Waiting - services have not tried the endpoint yet.\n"
    "  Network ready - the management interface is ready.\n"
    "  Contacting - Genesis is waiting for xcatd.\n"
    "  Action received - xcatd returned the operation Genesis must run.\n"
    "  Failed - xcatd could not be reached or did not return an action.\n\n"
    "Action is the operation assigned by xCAT. Target names its image or "
    "argument. Progress shows retries or completion.\n\n"
    "Genesis states\n\n"
    "  STARTING - boot services are starting.\n"
    "  IDLE - Genesis is waiting for an assigned action.\n"
    "  WAITING_FOR_LINK - no usable management route exists.\n"
    "  CONFIGURING_NETWORK - Genesis is applying network settings.\n"
    "  CONTACTING_XCAT - Genesis is waiting for xcatd.\n"
    "  ACTION_RECEIVED - xcatd returned an action. The node may still be "
    "unassigned.\n"
    "  RUNNING - Genesis is executing the action.\n"
    "  READY - the current stage completed successfully.\n"
    "  DEGRADED - Genesis can continue, but a retry or operator check is "
    "needed.\n"
    "  FAILED - Genesis cannot continue. Read Error and Recovery.\n\n"
    "Keys\n\n"
    "  F2 opens diagnostics.\n"
    "  F3 opens recent Genesis logs and follows new entries. Scroll up to "
    "pause following; press End to resume.\n"
    "  F12 asks before opening a root maintenance shell. Exit returns here.\n"
    "  Up and Down scroll this page.";

static void show_help(void) {
    struct newtExitStruct event;
    newtComponent form;
    newtComponent text_box;

    newtCenteredWindow(72, 19, "Genesis help");
    form = newtForm(NULL, NULL, NEWT_FLAG_NOF12);
    text_box = newtTextbox(1, 1, 68, 17, NEWT_FLAG_WRAP | NEWT_FLAG_SCROLL);
    newtTextboxSetText(text_box, help_text);
    newtFormAddComponent(form, text_box);
    newtFormAddHotKey(form, NEWT_KEY_F1);
    newtFormAddHotKey(form, NEWT_KEY_ESCAPE);
    newtPushHelpLine(" F1 Back   Esc Back   Up/Down Scroll");

    while (!xcat_console_stop_requested) {
        newtFormRun(form, &event);
        if (event.reason == NEWT_EXIT_ERROR ||
            (event.reason == NEWT_EXIT_HOTKEY &&
             (event.u.key == NEWT_KEY_F1 || event.u.key == NEWT_KEY_ESCAPE)))
            break;
    }

    newtFormDestroy(form);
    newtPopHelpLine();
    newtPopWindow();
}

static void show_diagnostics(void) {
    struct console_state state;
    struct newtExitStruct event;
    newtComponent form;
    newtComponent text_box;
    char text[4096];

    newtCenteredWindow(72, 19, "Genesis diagnostics");
    form = newtForm(NULL, NULL, NEWT_FLAG_NOF12);
    text_box = newtTextbox(1, 1, 68, 17, NEWT_FLAG_WRAP | NEWT_FLAG_SCROLL);
    newtFormAddComponent(form, text_box);
    newtFormAddHotKey(form, NEWT_KEY_F2);
    newtFormAddHotKey(form, NEWT_KEY_ESCAPE);
    newtPushHelpLine(" F2 Back   Esc Back   Up/Down Scroll");

    xcat_load_console_state(&state);
    xcat_format_diagnostics(&state, text, sizeof(text));
    newtTextboxSetText(text_box, text);
    newtRefresh();
    while (!xcat_console_stop_requested) {
        newtFormRun(form, &event);
        if (event.reason == NEWT_EXIT_ERROR ||
            (event.reason == NEWT_EXIT_HOTKEY &&
             (event.u.key == NEWT_KEY_F2 || event.u.key == NEWT_KEY_ESCAPE)))
            break;
    }

    newtFormDestroy(form);
    newtPopHelpLine();
    newtPopWindow();
}

static bool journal_value(sd_journal *journal, const char *field, char *value, size_t size) {
    const void *data;
    const unsigned char *bytes;
    size_t data_size;
    size_t field_size = strlen(field);
    size_t index;
    size_t written = 0;

    if (size == 0 || sd_journal_get_data(journal, field, &data, &data_size) < 0 ||
        data_size <= field_size || memcmp(data, field, field_size) != 0 ||
        ((const char *)data)[field_size] != '=')
        return false;
    bytes = (const unsigned char *)data + field_size + 1;
    for (index = field_size + 1; index < data_size && written + 1 < size; index++, bytes++) {
        if (*bytes >= 32 && *bytes <= 126)
            value[written++] = (char)*bytes;
        else if (*bytes == '\t' || *bytes == '\r' || *bytes == '\n')
            value[written++] = ' ';
    }
    value[written] = '\0';
    return true;
}

static bool genesis_journal_entry(sd_journal *journal, char *source, size_t source_size) {
    char unit[128] = "";
    char identifier[128] = "";

    journal_value(journal, "_SYSTEMD_UNIT", unit, sizeof(unit));
    journal_value(journal, "SYSLOG_IDENTIFIER", identifier, sizeof(identifier));
    if (strncmp(unit, "xcat-genesis-", 13) != 0 && strncmp(identifier, "xcat-genesis-", 13) != 0)
        return false;
    xcat_set_text(source, source_size, "%s", identifier[0] != '\0' ? identifier : unit);
    return true;
}

static void format_logs(char *text, size_t size) {
    sd_journal *journal = NULL;
    char lines[LOG_LINE_COUNT][LOG_LINE_SIZE] = {{0}};
    unsigned int count = 0;
    unsigned int next = 0;
    int result;

    if (size == 0)
        return;
    text[0] = '\0';
    result = sd_journal_open(&journal, SD_JOURNAL_LOCAL_ONLY | SD_JOURNAL_SYSTEM);
    if (result < 0) {
        xcat_set_text(text, size, "Genesis journal is unavailable: %s", strerror(-result));
        return;
    }

    sd_journal_seek_tail(journal);
    sd_journal_previous_skip(journal, 2048);
    while (sd_journal_next(journal) > 0) {
        char message[256] = "";
        char source[96] = "";
        char timestamp[16] = "--:--:--";
        uint64_t realtime;

        if (!genesis_journal_entry(journal, source, sizeof(source)) ||
            !journal_value(journal, "MESSAGE", message, sizeof(message)))
            continue;
        if (sd_journal_get_realtime_usec(journal, &realtime) >= 0) {
            time_t seconds = (time_t)(realtime / 1000000ULL);
            struct tm local_time;

            if (localtime_r(&seconds, &local_time) != NULL)
                strftime(timestamp, sizeof(timestamp), "%H:%M:%S", &local_time);
        }
        snprintf(lines[next], sizeof(lines[next]), "%s %-24.24s %s", timestamp, source, message);
        next = (next + 1) % LOG_LINE_COUNT;
        count++;
    }
    sd_journal_close(journal);

    if (count == 0) {
        xcat_set_text(text, size, "No Genesis journal entries are available.");
        return;
    }
    {
        unsigned int available = count < LOG_LINE_COUNT ? count : LOG_LINE_COUNT;
        unsigned int start = count < LOG_LINE_COUNT ? 0 : next;
        unsigned int index;
        size_t used = 0;

        for (index = 0; index < available && used + 1 < size; index++) {
            unsigned int line = (start + index) % LOG_LINE_COUNT;
            int written =
                snprintf(text + used, size - used, "%s%s", index > 0 ? "\n" : "", lines[line]);

            if (written < 0 || (size_t)written >= size - used)
                break;
            used += (size_t)written;
        }
    }
}

static unsigned int append_wrapped_log_record(newtComponent list_box, const char *record,
                                              size_t length, unsigned int count) {
    if (length == 0) {
        newtListboxAppendEntry(list_box, "", (void *)(uintptr_t)(count + 1));
        return count + 1;
    }

    while (length > 0) {
        char line[LOG_VIEW_WIDTH + 1];
        size_t take = length < LOG_VIEW_WIDTH ? length : LOG_VIEW_WIDTH;
        size_t used;

        if (length > LOG_VIEW_WIDTH) {
            size_t word_end = take;

            while (word_end > 0 && record[word_end] != ' ')
                word_end--;
            if (word_end > 0)
                take = word_end;
        }
        memcpy(line, record, take);
        line[take] = '\0';
        used = take;
        while (used > 0 && line[used - 1] == ' ')
            line[--used] = '\0';
        newtListboxAppendEntry(list_box, line, (void *)(uintptr_t)(count + 1));
        count++;
        record += take;
        length -= take;
        while (length > 0 && *record == ' ') {
            record++;
            length--;
        }
    }
    return count;
}

static unsigned int populate_log_listbox(newtComponent list_box, const char *text) {
    const char *record = text;
    unsigned int count = 0;

    while (*record != '\0') {
        const char *end = strchr(record, '\n');
        size_t length = end != NULL ? (size_t)(end - record) : strlen(record);

        count = append_wrapped_log_record(list_box, record, length, count);
        if (end == NULL)
            break;
        record = end + 1;
    }
    if (count == 0)
        count = append_wrapped_log_record(list_box, "", 0, count);
    return count;
}

static void show_logs(void) {
    struct newtExitStruct event;
    newtComponent form;
    newtComponent list_box;
    char text[LOG_LINE_COUNT * LOG_LINE_SIZE];
    char previous[LOG_LINE_COUNT * LOG_LINE_SIZE] = "";
    unsigned int item_count = 0;
    unsigned int selected = 0;
    bool follow = true;

    newtCenteredWindow(72, 19, "Genesis logs");
    form = newtForm(NULL, NULL, NEWT_FLAG_NOF12);
    list_box = newtListbox(1, 1, LOG_VIEW_HEIGHT, NEWT_FLAG_SCROLL);
    newtListboxSetWidth(list_box, LOG_VIEW_WIDTH);
    newtFormAddComponent(form, list_box);
    newtFormAddHotKey(form, NEWT_KEY_F3);
    newtFormAddHotKey(form, NEWT_KEY_ESCAPE);
    newtFormAddHotKey(form, NEWT_KEY_UP);
    newtFormAddHotKey(form, NEWT_KEY_DOWN);
    newtFormAddHotKey(form, NEWT_KEY_PGUP);
    newtFormAddHotKey(form, NEWT_KEY_PGDN);
    newtFormAddHotKey(form, NEWT_KEY_HOME);
    newtFormAddHotKey(form, NEWT_KEY_END);
    newtFormSetTimer(form, 1000);
    newtPushHelpLine(" F3 Back   Esc Back   Up/Down Scroll   End Follow");

    while (!xcat_console_stop_requested) {
        format_logs(text, sizeof(text));
        if (previous[0] == '\0' || strcmp(previous, text) != 0) {
            newtListboxClear(list_box);
            item_count = populate_log_listbox(list_box, text);
            if (follow || selected == 0 || selected > item_count)
                selected = item_count;
            newtListboxSetCurrentByKey(list_box, (void *)(uintptr_t)selected);
            xcat_copy_printable(previous, sizeof(previous), text);
        }
        newtRefresh();
        newtFormRun(form, &event);
        if (event.reason == NEWT_EXIT_ERROR ||
            (event.reason == NEWT_EXIT_HOTKEY &&
             (event.u.key == NEWT_KEY_F3 || event.u.key == NEWT_KEY_ESCAPE)))
            break;
        if (event.reason != NEWT_EXIT_HOTKEY || item_count == 0)
            continue;
        if (event.u.key == NEWT_KEY_UP || event.u.key == NEWT_KEY_PGUP ||
            event.u.key == NEWT_KEY_HOME) {
            unsigned int distance = event.u.key == NEWT_KEY_UP ? 1 : LOG_VIEW_HEIGHT - 1;

            follow = false;
            if (event.u.key == NEWT_KEY_HOME || selected <= distance)
                selected = 1;
            else
                selected -= distance;
        } else if (event.u.key == NEWT_KEY_DOWN || event.u.key == NEWT_KEY_PGDN) {
            unsigned int distance = event.u.key == NEWT_KEY_DOWN ? 1 : LOG_VIEW_HEIGHT - 1;

            if (item_count - selected <= distance)
                selected = item_count;
            else
                selected += distance;
            follow = selected == item_count;
        } else if (event.u.key == NEWT_KEY_END) {
            selected = item_count;
            follow = true;
        }
        if (selected > 0)
            newtListboxSetCurrentByKey(list_box, (void *)(uintptr_t)selected);
    }

    newtFormDestroy(form);
    newtPopHelpLine();
    newtPopWindow();
}

static void show_maintenance_shell(void) {
    int shell_error;

    if (newtWinChoice("Maintenance shell", "Open", "Cancel",
                      "Open a root maintenance shell? Provisioning services continue "
                      "in the background.") != 1)
        return;

    newtSuspend();
    shell_error = xcat_run_maintenance_shell();
    newtResume();
    newtCursorOff();
    newtResizeScreen(1);
    if (shell_error != 0)
        newtWinMessage("Maintenance shell", "Close",
                       "The maintenance shell could not be opened: %s", strerror(shell_error));
}

int xcat_run_newt(void) {
    struct console_state state;
    struct status_view view;
    struct console_form screen;
    struct newtExitStruct event;
    struct status_view previous = {0};
    bool have_previous = false;
    unsigned int redraw = 0;
    int columns;
    int rows;
    int result = 0;

    if (getenv("TERM") == NULL)
        setenv("TERM", "xterm", 0);
    if (getenv("COLUMNS") == NULL)
        setenv("COLUMNS", "80", 0);
    if (getenv("LINES") == NULL)
        setenv("LINES", "24", 0);
    setenv("NEWT_NOFLOWCTRL", "1", 0);
    if (newtInit() != 0)
        return -1;
    newtGetScreenSize(&columns, &rows);
    if (columns < 80 || rows < 24) {
        newtFinished();
        return -1;
    }

    newtSetColor(NEWT_COLORSET_CUSTOM(0), "green", "lightgray");
    newtSetColor(NEWT_COLORSET_CUSTOM(1), "brown", "lightgray");
    newtSetColor(NEWT_COLORSET_CUSTOM(2), "red", "lightgray");
    newtCls();
    newtCursorOff();
    newtPushHelpLine(" F1 Help   F2 Diagnostics   F3 Logs   F12 Shell");
    xcat_load_console_state(&state);
    xcat_build_status_view(&state, &view);
    screen = create_form(&view);

    while (!xcat_console_stop_requested) {
        bool changed;

        xcat_load_console_state(&state);
        xcat_build_status_view(&state, &view);
        changed = !have_previous || xcat_status_view_changed(&previous, &view);
        update_form(&screen, &view, changed);
        if (changed) {
            previous = view;
            have_previous = true;
            newtResizeScreen(1);
            redraw = 0;
        }
        newtFormRun(screen.form, &event);
        if (event.reason == NEWT_EXIT_ERROR) {
            result = -1;
            break;
        }
        if (event.reason == NEWT_EXIT_HOTKEY) {
            if (event.u.key == NEWT_KEY_F1)
                show_help();
            else if (event.u.key == NEWT_KEY_F2)
                show_diagnostics();
            else if (event.u.key == NEWT_KEY_F3)
                show_logs();
            else if (event.u.key == NEWT_KEY_F12) {
                show_maintenance_shell();
                have_previous = false;
                redraw = 0;
            }
        }
        if (++redraw >= 30) {
            newtResizeScreen(1);
            redraw = 0;
        }
    }

    newtFormDestroy(screen.form);
    newtPopWindow();
    newtPopHelpLine();
    newtFinished();
    return result;
}
