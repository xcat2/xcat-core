// SPDX-License-Identifier: EPL-1.0

#include "console.h"

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

int xcat_run_maintenance_shell(void) {
    int exec_error_pipe[2] = {-1, -1};
    int exec_error = 0;
    ssize_t exec_error_size = 0;
    pid_t child;
    int descriptor_flags;
    int result = 0;

    if (pipe(exec_error_pipe) < 0)
        return errno;

    descriptor_flags = fcntl(exec_error_pipe[1], F_GETFD);
    if (descriptor_flags < 0 ||
        fcntl(exec_error_pipe[1], F_SETFD, descriptor_flags | FD_CLOEXEC) < 0) {
        result = errno;
        close(exec_error_pipe[0]);
        close(exec_error_pipe[1]);
        return result;
    }

    child = fork();
    if (child == 0) {
        close(exec_error_pipe[0]);
        if (xcat_set_signal_handler(SIGINT, SIG_DFL) == 0 &&
            xcat_set_signal_handler(SIGTERM, SIG_DFL) == 0 &&
            xcat_set_signal_handler(SIGHUP, SIG_DFL) == 0) {
            execl("/usr/libexec/xcat/genesis-maintenance-shell", "genesis-maintenance-shell",
                  (char *)NULL);
        }
        exec_error = errno;
        {
            ssize_t written;

            do {
                written = write(exec_error_pipe[1], &exec_error, sizeof(exec_error));
            } while (written < 0 && errno == EINTR);
            (void)written;
        }
        _exit(127);
    }
    if (child < 0) {
        result = errno;
        close(exec_error_pipe[0]);
        close(exec_error_pipe[1]);
        return result;
    }

    close(exec_error_pipe[1]);
    do {
        exec_error_size = read(exec_error_pipe[0], &exec_error, sizeof(exec_error));
    } while (exec_error_size < 0 && errno == EINTR);
    if (exec_error_size < 0)
        result = errno;
    close(exec_error_pipe[0]);
    while (waitpid(child, NULL, 0) < 0 && errno == EINTR)
        ;
    if (exec_error_size == (ssize_t)sizeof(exec_error))
        result = exec_error;
    return result;
}
