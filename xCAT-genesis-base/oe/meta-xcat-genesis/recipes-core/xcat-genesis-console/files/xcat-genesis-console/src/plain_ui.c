// SPDX-License-Identifier: EPL-1.0

#include "console.h"

#include <ctype.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void print_plain_label(const char *label) {
    char plain_label[24];

    xcat_set_text(plain_label, sizeof(plain_label), "%s", label);
    if (plain_label[0] >= 'A' && plain_label[0] <= 'Z' && strcmp(plain_label, "MAC") != 0)
        plain_label[0] = (char)tolower((unsigned char)plain_label[0]);
    fputs(plain_label, stdout);
}

static void print_plain(const struct status_view *view) {
    enum status_field field;

    printf("\nxCAT Genesis | %s | in stage %s\n", view->fields[STATUS_FIELD_STATE].value,
           view->fields[STATUS_FIELD_STAGE_TIME].value);
    for (field = STATUS_FIELD_ACTIVITY; field < STATUS_FIELD_COUNT; field++) {
        print_plain_label(view->fields[field].label);
        printf(": %s\n", view->fields[field].value);
    }
    fflush(stdout);
}

static bool read_plain_command(char *command, size_t size) {
    struct pollfd input = {STDIN_FILENO, POLLIN, 0};
    size_t length;
    int result;

    result = poll(&input, 1, 1000);
    if (result <= 0 || !(input.revents & POLLIN) || fgets(command, (int)size, stdin) == NULL)
        return false;
    length = strlen(command);
    while (length > 0 && isspace((unsigned char)command[length - 1]))
        command[--length] = '\0';
    return true;
}

static void open_plain_maintenance_shell(void) {
    char answer[16];
    int shell_error;

    printf("Open a root maintenance shell? [y/N] ");
    fflush(stdout);
    if (fgets(answer, sizeof(answer), stdin) == NULL)
        return;
    if (answer[0] != 'y' && answer[0] != 'Y') {
        printf("Maintenance shell cancelled.\n");
        return;
    }
    shell_error = xcat_run_maintenance_shell();
    if (shell_error != 0)
        printf("Maintenance shell could not be opened: %s\n", strerror(shell_error));
}

int xcat_run_plain(bool once) {
    struct console_state state;
    struct status_view view;
    struct status_view previous = {0};
    bool have_previous = false;
    bool interactive = !once && isatty(STDIN_FILENO) && isatty(STDOUT_FILENO);
    unsigned int heartbeat = 30;

    while (!xcat_console_stop_requested) {
        xcat_load_console_state(&state);
        xcat_build_status_view(&state, &view);
        if (!have_previous || xcat_status_view_changed(&previous, &view) || heartbeat >= 30) {
            print_plain(&view);
            if (interactive)
                printf("Type shell and press Enter for maintenance.\n");
            previous = view;
            have_previous = true;
            heartbeat = 0;
        }
        if (once)
            break;
        if (interactive) {
            char command[32];

            if (read_plain_command(command, sizeof(command))) {
                if (strcmp(command, "shell") == 0) {
                    open_plain_maintenance_shell();
                    have_previous = false;
                    heartbeat = 30;
                    printf("Returned to the Genesis status console.\n");
                } else if (command[0] != '\0') {
                    printf("Unknown command. Type shell and press Enter.\n");
                }
            }
        } else {
            sleep(1);
        }
        heartbeat++;
    }
    return 0;
}
