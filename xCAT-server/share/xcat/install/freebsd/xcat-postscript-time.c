#include <sys/types.h>
#include <sys/file.h>
#include <sys/proc.h>
#include <sys/procctl.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/time.h>
#include <sys/user.h>
#include <sys/wait.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <kenv.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define BOOT_VARIABLE "xcat.postscript.boot-id"

static volatile sig_atomic_t capture_signal;
static int capture_reaper;

struct capture_stream {
    int reader;
    int writer;
    int output;
    size_t bytes;
    int truncated;
};

static int
private_directory(int parent, const char *name)
{
    struct stat st;
    int fd;

    fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0 || fstat(fd, &st) != 0)
        err(1, "Cannot open boot identity directory");
    if (st.st_uid != 0 || (st.st_mode & 0022) != 0)
        errx(1, "Boot identity directory is writable");
    return fd;
}

static void
boot_identity(void)
{
    static const char hex[] = "0123456789abcdef";
    unsigned char random[32];
    char value[129];
    struct stat st;
    int var, run, lock, length;
    size_t i;

    var = private_directory(AT_FDCWD, "/var");
    run = private_directory(var, "run");
    lock = openat(run, "xcat-postscript-time.lock",
        O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (lock < 0 || fstat(lock, &st) != 0)
        err(1, "Cannot open boot identity lock");
    if (!S_ISREG(st.st_mode) || st.st_uid != 0 || st.st_gid != 0 ||
        (st.st_mode & 07777) != 0600 || st.st_nlink != 1 || st.st_size != 0)
        errx(1, "Invalid boot identity lock");
    if (flock(lock, LOCK_EX) != 0)
        err(1, "Cannot lock boot identity");

    /* The kernel environment is rebuilt at boot and survives wall-clock corrections. */
    length = kenv(KENV_GET, BOOT_VARIABLE, value, sizeof(value));
    if (length < 0) {
        if (errno != ENOENT)
            err(1, "Cannot read boot identity");
        arc4random_buf(random, sizeof(random));
        for (i = 0; i < sizeof(random); i++) {
            value[2 * i] = hex[random[i] >> 4];
            value[2 * i + 1] = hex[random[i] & 15];
        }
        value[64] = '\0';
        if (kenv(KENV_SET, BOOT_VARIABLE, value, 65) != 0)
            err(1, "Cannot publish boot identity");
        length = 65;
    }
    if (length != 65 || value[64] != '\0' || strspn(value, hex) != 64)
        errx(1, "Invalid boot identity");
    close(lock);
    close(run);
    close(var);
    if (printf("%s\n", value) < 0 || fflush(stdout) != 0)
        err(1, "Cannot return boot identity");
}

static void
boot_time(struct timeval *value)
{
    size_t size = sizeof(*value);

    if (sysctlbyname("kern.boottime", value, &size, NULL, 0) != 0)
        err(1, "Cannot read kernel boot time");
    if (size != sizeof(*value) || value->tv_usec < 0 || value->tv_usec >= 1000000)
        errx(1, "Invalid kernel boot time");
}

static void
process_identity(const char *argument, int report_state)
{
    struct timeval before, after, start;
    struct kinfo_proc process;
    uintmax_t pid;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, 0 };
    size_t size;
    unsigned int attempt;
    int jailed;

    if (report_state) {
        size = sizeof(jailed);
        if (sysctlbyname("security.jail.jailed", &jailed, &size, NULL, 0) != 0)
            err(1, "Cannot observe process visibility");
        if (size != sizeof(jailed) || jailed != 0)
            errx(1, "Process observation requires the host root context");
    }
    if (*argument == '\0' || *argument == '0' || strlen(argument) > 8 ||
        strspn(argument, "0123456789") != strlen(argument))
        errx(1, "Invalid process identifier");
    pid = strtoumax(argument, NULL, 10);
    if (pid > 99999999)
        errx(1, "Process identifier exceeds its bound");
    mib[3] = (int)pid;
    for (attempt = 0; attempt < 16; attempt++) {
        boot_time(&before);
        size = sizeof(process);
        if (sysctl(mib, 4, &process, &size, NULL, 0) != 0) {
            if (report_state && errno == ESRCH) {
                if (printf("format\txcat-freebsd-process-state-1\npid\t%ju\nstate\tabsent\nidentity\t-\n", pid) < 0 ||
                    fflush(stdout) != 0)
                    err(1, "Cannot return absent process state");
                return;
            }
            err(1, "Cannot read process identity");
        }
        if (size != sizeof(process) || process.ki_structsize != (int)sizeof(process) ||
            process.ki_pid != (pid_t)pid)
            errx(1, "Invalid process identity response");
        if (!report_state && process.ki_stat == SZOMB)
            errx(1, "Process is no longer running");
        boot_time(&after);
        if (timercmp(&before, &after, !=))
            continue;
        /* FreeBSD exports process start as its uptime plus the current boot-time estimate. */
        timersub(&process.ki_start, &before, &start);
        if (start.tv_sec < 0 || start.tv_usec < 0 || start.tv_usec >= 1000000)
            errx(1, "Invalid process start time");
        if (report_state && printf("format\txcat-freebsd-process-state-1\npid\t%ju\nstate\t%s\nidentity\t",
            pid, process.ki_stat == SZOMB ? "zombie" : "running") < 0)
            err(1, "Cannot return process state");
        if (printf("%ju:%jd.%06ld\n", pid, (intmax_t)start.tv_sec,
            (long)start.tv_usec) < 0 || fflush(stdout) != 0)
            err(1, "Cannot return process identity");
        return;
    }
    errx(1, "Clock changed while reading process identity");
}

static uintmax_t
capture_number(const char *value, uintmax_t minimum, uintmax_t maximum)
{
    uintmax_t number;

    if (*value == '\0' || strlen(value) > 8 ||
        strspn(value, "0123456789") != strlen(value))
        errx(125, "Invalid capture bound");
    number = strtoumax(value, NULL, 10);
    if (number < minimum || number > maximum)
        errx(125, "Capture bound is out of range");
    return number;
}

static int64_t
capture_clock(void)
{
    struct timespec value;

    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
        err(125, "Cannot time command");
    if (value.tv_sec < 0 || value.tv_sec > 999999999999LL)
        errx(125, "Command clock is out of range");
    return (int64_t)value.tv_sec * 1000 + value.tv_nsec / 1000000;
}

static void
capture_interrupt(int signal_number)
{
    if (capture_signal == 0)
        capture_signal = signal_number;
}

static void
capture_cleanup(void)
{
    struct procctl_reaper_kill request;

    if (!capture_reaper)
        return;
    memset(&request, 0, sizeof(request));
    request.rk_sig = SIGKILL;
    (void)procctl(P_PID, getpid(), PROC_REAP_KILL, &request);
    (void)procctl(P_PID, getpid(), PROC_REAP_RELEASE, NULL);
}

static void
capture_kill(int signal_number)
{
    struct procctl_reaper_kill request;

    memset(&request, 0, sizeof(request));
    request.rk_sig = signal_number;
    if (procctl(P_PID, getpid(), PROC_REAP_KILL, &request) != 0) {
        if (errno != ESRCH)
            err(125, "Cannot stop command descendants");
    } else if (request.rk_fpid > 0)
        errx(125, "Cannot stop a command descendant");
}

static void
capture_open(struct capture_stream *stream, const char *path)
{
    struct stat st;
    int descriptors[2], flags;

    memset(stream, 0, sizeof(*stream));
    stream->output = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (stream->output < 0 || fstat(stream->output, &st) != 0)
        err(125, "Cannot create command log");
    if (!S_ISREG(st.st_mode) || st.st_uid != 0 || st.st_gid != 0 ||
        (st.st_mode & 07777) != 0600 || st.st_nlink != 1)
        errx(125, "Invalid command log");
    if (pipe2(descriptors, O_CLOEXEC) != 0)
        err(125, "Cannot create command pipe");
    stream->reader = descriptors[0];
    stream->writer = descriptors[1];
    flags = fcntl(stream->reader, F_GETFL);
    if (flags < 0 || fcntl(stream->reader, F_SETFL, flags | O_NONBLOCK) != 0)
        err(125, "Cannot configure command pipe");
}

static void
capture_read(struct capture_stream *stream, size_t limit)
{
    char buffer[8192];
    ssize_t length, written;
    size_t retained, offset;
    unsigned int attempt;

    if (stream->reader < 0)
        return;
    for (attempt = 0; attempt < 8; attempt++) {
        length = read(stream->reader, buffer, sizeof(buffer));
        if (length < 0) {
            if (errno == EAGAIN || errno == EINTR)
                return;
            err(125, "Cannot read command output");
        }
        if (length == 0) {
            close(stream->reader);
            stream->reader = -1;
            return;
        }
        retained = (size_t)length;
        if (retained > limit - stream->bytes) {
            retained = limit - stream->bytes;
            stream->truncated = 1;
        }
        for (offset = 0; offset < retained; offset += (size_t)written) {
            written = write(stream->output, buffer + offset, retained - offset);
            if (written < 0 && errno == EINTR) {
                written = 0;
                continue;
            }
            if (written < 0)
                err(125, "Cannot retain command output");
            if (written == 0)
                errx(125, "Command output write made no progress");
        }
        stream->bytes += retained;
    }
}

static void
capture_command(char **arguments, int guard_lock, int observe_only)
{
    static const int signals[] = { SIGHUP, SIGINT, SIGQUIT, SIGTERM };
    struct capture_stream streams[2];
    struct procctl_reaper_status descendants;
    struct sigaction action;
    struct pollfd pollers[2];
    int64_t current, deadline, kill_deadline = 0, drain_deadline = 0;
    size_t i, limit;
    uintmax_t seconds;
    pid_t child, observed;
    int status = 0, wait_status, finished = 0, timed_out = 0, stopping = 0, killed = 0, flags;
    unsigned int attempt;

    seconds = capture_number(arguments[0], observe_only ? 0 : 1, observe_only ? 0 : 86400);
    /* The framework body has independently bounded prerequisite and driver phases. */
    deadline = observe_only ? 0 : capture_clock() + (int64_t)seconds * 1000;
    limit = (size_t)capture_number(arguments[1], 0, 1048576);
    if (guard_lock) {
        /* Keep the worker lock in this supervisor, but not in started services. */
        flags = fcntl(9, F_GETFD);
        if (flags < 0 || fcntl(9, F_SETFD, flags | FD_CLOEXEC) != 0)
            err(125, "Cannot guard inherited worker lock");
    }
    capture_open(&streams[0], arguments[2]);
    capture_open(&streams[1], arguments[3]);
    memset(&action, 0, sizeof(action));
    action.sa_handler = capture_interrupt;
    sigemptyset(&action.sa_mask);
    for (i = 0; i < sizeof(signals) / sizeof(signals[0]); i++)
        if (sigaction(signals[i], &action, NULL) != 0)
            err(125, "Cannot supervise command signals");
    if (procctl(P_PID, getpid(), PROC_REAP_ACQUIRE, NULL) != 0)
        err(125, "Cannot acquire command descendants");
    capture_reaper = 1;
    if (atexit(capture_cleanup) != 0)
        errx(125, "Cannot register command cleanup");
    child = fork();
    if (child < 0)
        err(125, "Cannot start command");
    if (child == 0) {
        capture_reaper = 0;
        for (i = 0; i < sizeof(signals) / sizeof(signals[0]); i++)
            signal(signals[i], SIG_DFL);
        for (i = 0; i < 2; i++) {
            close(streams[i].reader);
            close(streams[i].output);
            if (dup2(streams[i].writer, (int)i + 1) < 0)
                err(126, "Cannot open command stream");
            close(streams[i].writer);
        }
        execvp(arguments[4], arguments + 4);
        err(errno == ENOENT ? 127 : 126, "Cannot execute command");
    }
    for (i = 0; i < 2; i++)
        close(streams[i].writer);
    for (;;) {
        for (attempt = 0; attempt < 64; attempt++) {
            observed = waitpid(-1, &wait_status, WNOHANG);
            if (observed < 0 && errno != EINTR && errno != ECHILD)
                err(125, "Cannot observe command");
            if (observed <= 0)
                break;
            if (observed == child && !finished) {
                finished = 1;
                status = WIFEXITED(wait_status) ? WEXITSTATUS(wait_status) : 128 + WTERMSIG(wait_status);
            }
        }
        current = capture_clock();
        if (!stopping && (capture_signal != 0 || (!finished && deadline != 0 && current >= deadline))) {
            timed_out = capture_signal == 0;
            stopping = capture_signal == 0 ? SIGTERM : capture_signal;
            drain_deadline = 0;
            capture_kill(stopping);
            capture_kill(SIGCONT);
            kill_deadline = current + 5000;
        }
        if (stopping) {
            if (!killed && current >= kill_deadline) {
                capture_kill(SIGKILL);
                killed = 1;
            }
            memset(&descendants, 0, sizeof(descendants));
            if (procctl(P_PID, getpid(), PROC_REAP_STATUS, &descendants) != 0)
                err(125, "Cannot observe command descendants");
            if (finished && descendants.rs_descendants == 0) {
                if (drain_deadline == 0)
                    drain_deadline = current + 100;
            /* A full reap batch can leave more zombies for the next pass. */
            } else if (killed && current >= kill_deadline + 1000 && attempt < 64)
                errx(125, "Command descendants did not stop");
        } else if (finished && drain_deadline == 0)
            drain_deadline = current + 100;
        for (i = 0; i < 2; i++)
            capture_read(&streams[i], limit);
        if (drain_deadline != 0 &&
            ((streams[0].reader < 0 && streams[1].reader < 0) || current >= drain_deadline))
            break;
        for (i = 0; i < 2; i++) {
            pollers[i].fd = streams[i].reader;
            pollers[i].events = POLLIN;
            pollers[i].revents = 0;
        }
        if (poll(pollers, 2, 20) < 0 && errno != EINTR)
            err(125, "Cannot wait for command output");
    }
    for (i = 0; i < 2; i++)
        if (fsync(streams[i].output) != 0 || close(streams[i].output) != 0)
            err(125, "Cannot sync command output");
    /* Successful scripts may leave detached services running. */
    if (procctl(P_PID, getpid(), PROC_REAP_RELEASE, NULL) != 0)
        err(125, "Cannot release command descendants");
    capture_reaper = 0;
    if (timed_out)
        status = 124;
    else if (stopping)
        status = 128 + stopping;
    if (printf("format\txcat-freebsd-postscript-capture-1\nstatus\t%d\nstdout-bytes\t%zu\nstderr-bytes\t%zu\nstdout-truncated\t%s\nstderr-truncated\t%s\nstdout-open\t%s\nstderr-open\t%s\n",
        status, streams[0].bytes, streams[1].bytes,
        streams[0].truncated ? "yes" : "no", streams[1].truncated ? "yes" : "no",
        streams[0].reader >= 0 ? "yes" : "no", streams[1].reader >= 0 ? "yes" : "no") < 0 ||
        fflush(stdout) != 0)
        err(125, "Cannot return command status");
}

int
main(int argc, char **argv)
{
    struct timespec value;

    if (getuid() != 0 || geteuid() != 0)
        errx(1, "Native root execution is required");
    umask(0077);
    if (argc == 2 && strcmp(argv[1], "boot") == 0)
        boot_identity();
    else if (argc == 3 && strcmp(argv[1], "process") == 0)
        process_identity(argv[2], 0);
    else if (argc == 3 && strcmp(argv[1], "process-state") == 0)
        process_identity(argv[2], 1);
    else if (argc >= 7 && strcmp(argv[1], "capture") == 0)
        capture_command(argv + 2, 0, 0);
    else if (argc >= 7 && strcmp(argv[1], "capture-guard") == 0)
        capture_command(argv + 2, 1, 0);
    else if (argc >= 7 && strcmp(argv[1], "capture-watch") == 0)
        capture_command(argv + 2, 0, 1);
    else if (argc == 2 && strcmp(argv[1], "uptime") == 0) {
        if (clock_gettime(CLOCK_MONOTONIC, &value) != 0)
            err(1, "Cannot read monotonic time");
        if (value.tv_sec < 0 || value.tv_sec > 999999999999LL)
            errx(1, "Monotonic time exceeds its bound");
        if (printf("%jd\n", (intmax_t)value.tv_sec) < 0 || fflush(stdout) != 0)
            err(1, "Cannot return monotonic time");
    } else
        errx(2, "Usage: xcat-postscript-time boot | process pid | process-state pid | uptime | capture[-guard|-watch] seconds limit stdout stderr command [argument ...]");
    return 0;
}
