// SPDX-License-Identifier: EPL-1.0

#include "console.h"

#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

volatile sig_atomic_t xcat_console_stop_requested;

static void stop_console(int signal_number) {
    (void)signal_number;
    xcat_console_stop_requested = 1;
}

static void usage(const char *program) {
    fprintf(stderr, "Usage: %s [--plain] [--once]\n", program);
}

int main(int argc, char **argv) {
    const char *cmdline_path = xcat_path_from_env("XCAT_CMDLINE_FILE", "/proc/cmdline");
    char cmdline[2048] = "";
    char console_mode[16] = "";
    bool plain = false;
    bool once = false;

    for (int index = 1; index < argc; index++) {
        if (strcmp(argv[index], "--plain") == 0)
            plain = true;
        else if (strcmp(argv[index], "--once") == 0) {
            once = true;
            plain = true;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    if (xcat_set_signal_handler(SIGINT, stop_console) < 0 ||
        xcat_set_signal_handler(SIGTERM, stop_console) < 0 ||
        xcat_set_signal_handler(SIGHUP, stop_console) < 0) {
        perror("sigaction");
        return EXIT_FAILURE;
    }
    xcat_read_line(cmdline_path, cmdline, sizeof(cmdline));
    if (xcat_cmdline_value(cmdline, "xcat.console", console_mode, sizeof(console_mode)) &&
        strcmp(console_mode, "plain") == 0)
        plain = true;

#ifndef XCAT_CONSOLE_PLAIN_ONLY
    const char *term = getenv("TERM");

    if (!plain && isatty(STDIN_FILENO) && isatty(STDOUT_FILENO) &&
        (term == NULL || strcmp(term, "dumb") != 0)) {
        if (xcat_run_newt() == 0)
            return 0;
    }
#else
    (void)plain;
#endif
    return xcat_run_plain(once);
}
