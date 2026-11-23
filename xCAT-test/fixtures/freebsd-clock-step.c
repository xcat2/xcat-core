/* Run only in a disposable FreeBSD guest with no other clock-sensitive work. */
#include <sys/types.h>
#include <sys/wait.h>

#include <err.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static struct timespec real_start, mono_start;
static volatile sig_atomic_t changed;
static volatile sig_atomic_t report_restore = 1;

static void
restore(void)
{
    struct timespec mono, target, after;
    long long error;

    if (!changed)
        return;
    if (clock_gettime(CLOCK_MONOTONIC, &mono) != 0)
        _exit(90);
    target.tv_sec = real_start.tv_sec + mono.tv_sec - mono_start.tv_sec;
    target.tv_nsec = real_start.tv_nsec + mono.tv_nsec - mono_start.tv_nsec;
    if (target.tv_nsec < 0) {
        target.tv_nsec += 1000000000L;
        target.tv_sec--;
    } else if (target.tv_nsec >= 1000000000L) {
        target.tv_nsec -= 1000000000L;
        target.tv_sec++;
    }
    if (clock_settime(CLOCK_REALTIME, &target) != 0 ||
        clock_gettime(CLOCK_REALTIME, &after) != 0)
        _exit(91);
    changed = 0;
    error = (after.tv_sec - target.tv_sec) * 1000000000LL + after.tv_nsec - target.tv_nsec;
    if (report_restore)
        fprintf(stderr, "xcat-clock-step restored error_ns=%lld\n", error);
    if (llabs(error) > 100000000LL)
        _exit(92);
}

static void
interrupted(int signal_number)
{
    report_restore = 0;
    restore();
    _exit(128 + signal_number);
}

int
main(int argc, char **argv)
{
    struct timespec target;
    int offset, status;
    pid_t child;

    if (argc < 3 || getuid() != 0 ||
        (strcmp(argv[1], "300") != 0 && strcmp(argv[1], "-300") != 0))
        errx(2, "Usage in a disposable guest: freebsd-clock-step {300|-300} command [arguments]");
    offset = atoi(argv[1]);
    if (clock_gettime(CLOCK_REALTIME, &real_start) != 0 ||
        clock_gettime(CLOCK_MONOTONIC, &mono_start) != 0)
        err(1, "Cannot read clocks");
    atexit(restore);
    signal(SIGTERM, interrupted);
    signal(SIGINT, interrupted);
    signal(SIGHUP, interrupted);
    changed = 1;
    target = real_start;
    target.tv_sec += offset;
    if (clock_settime(CLOCK_REALTIME, &target) != 0)
        err(1, "Cannot step clock");
    fprintf(stderr, "xcat-clock-step offset=%d\n", offset);
    child = fork();
    if (child < 0)
        err(1, "Cannot fork clock fixture");
    if (child == 0) {
        execvp(argv[2], argv + 2);
        _exit(127);
    }
    if (waitpid(child, &status, 0) != child)
        err(1, "Cannot wait for clock fixture");
    restore();
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128 + WTERMSIG(status);
}
