#include <sys/types.h>
#include <sys/proc.h>
#include <sys/sysctl.h>
#include <sys/user.h>
#include <sys/wait.h>

#include <err.h>
#include <errno.h>
#include <inttypes.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef XCAT_TEST_WRAP_PROCESS
int __real_sysctl(const int *, u_int, void *, size_t *, const void *, size_t);
int __real_sysctlbyname(const char *, void *, size_t *, const void *, size_t);

int
__wrap_sysctl(const int *name, u_int count, void *output, size_t *size,
    const void *input, size_t bytes)
{
    const char *mode = getenv("XCAT_TEST_PROCESS_QUERY");
    struct kinfo_proc *process = output;

    if (mode == NULL || count != 4 || name[0] != CTL_KERN ||
        name[1] != KERN_PROC || name[2] != KERN_PROC_PID)
        return __real_sysctl(name, count, output, size, input, bytes);
    if (strcmp(mode, "permission") == 0 || strcmp(mode, "io") == 0) {
        errno = strcmp(mode, "permission") == 0 ? EPERM : EIO;
        return -1;
    }
    if (strcmp(mode, "zero") == 0 || strcmp(mode, "short") == 0) {
        *size = strcmp(mode, "zero") == 0 ? 0 : 1;
        return 0;
    }
    if (strcmp(mode, "wrong-pid") == 0 || strcmp(mode, "wrong-size") == 0) {
        memset(process, 0, sizeof(*process));
        *size = sizeof(*process);
        process->ki_pid = strcmp(mode, "wrong-pid") == 0 ? name[3] + 1 : name[3];
        process->ki_structsize = strcmp(mode, "wrong-size") == 0 ? 1 : sizeof(*process);
        return 0;
    }
    return __real_sysctl(name, count, output, size, input, bytes);
}

int
__wrap_sysctlbyname(const char *name, void *output, size_t *size,
    const void *input, size_t bytes)
{
    const char *mode = getenv("XCAT_TEST_PROCESS_QUERY");

    if (mode != NULL && strcmp(name, "security.jail.jailed") == 0) {
        if (strcmp(mode, "jailed") == 0) {
            *(int *)output = 1;
            *size = sizeof(int);
            return 0;
        }
        if (strcmp(mode, "jail-shape") == 0) {
            *size = 0;
            return 0;
        }
        if (strcmp(mode, "jail-error") == 0) {
            errno = EPERM;
            return -1;
        }
    }
    return __real_sysctlbyname(name, output, size, input, bytes);
}
#else
static volatile sig_atomic_t released;
static volatile sig_atomic_t finished;

static void
release_child(int signal_number)
{
    if (signal_number == SIGUSR1)
        released = 1;
    else
        finished = 1;
}

int
main(void)
{
    sigset_t blocked, previous;
    siginfo_t info;
    pid_t child;
    int status, gate[2];
    char byte;

    sigemptyset(&blocked);
    sigaddset(&blocked, SIGUSR1);
    sigaddset(&blocked, SIGUSR2);
    if (sigprocmask(SIG_BLOCK, &blocked, &previous) != 0 ||
        signal(SIGUSR1, release_child) == SIG_ERR ||
        signal(SIGUSR2, release_child) == SIG_ERR || pipe(gate) != 0)
        err(1, "Cannot coordinate zombie fixture");
    child = fork();
    if (child < 0)
        err(1, "Cannot create zombie fixture");
    if (child == 0) {
        close(gate[1]);
        if (read(gate[0], &byte, 1) != 0)
            _exit(1);
        _exit(0);
    }
    close(gate[0]);
    if (printf("%jd\n", (intmax_t)child) < 0 || fflush(stdout) != 0)
        err(1, "Cannot identify live fixture");
    while (!released && !finished)
        sigsuspend(&previous);
    if (close(gate[1]) != 0)
        err(1, "Cannot release live fixture");
    if (waitid(P_PID, child, &info, WEXITED | WNOWAIT) != 0)
        err(1, "Cannot observe zombie fixture");
    if (printf("zombie\n") < 0 || fflush(stdout) != 0)
        err(1, "Cannot report zombie fixture");
    while (!finished)
        sigsuspend(&previous);
    if (waitpid(child, &status, 0) != child || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
        errx(1, "Cannot reap zombie fixture");
    return 0;
}
#endif
