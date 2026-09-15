#!/usr/bin/env bash
# Helpers for BATS tests that run xCAT shell code from the checkout. They fail closed: a missing
# checkout file, or an extraction that matches nothing, matches more than one place or stops
# before its end, fails the test. It never skips the test, and it never hands back a partial
# block to evaluate.

repo_root()
{
    (cd "${BATS_TEST_DIRNAME:?}/../.." && pwd -P)
}

repo_path()
{
    printf '%s/%s\n' "$(repo_root)" "$1"
}

# A missing checkout file is a broken checkout, not a host without a dependency.
require_repo_file()
{
    local path
    path="$(repo_path "$1")"
    if [ ! -r "$path" ]; then
        printf 'the checkout file is missing: %s\n' "$path" >&2
        return 1
    fi
    printf '%s\n' "$path"
}

# Code under test uses some variables as a root directory. An empty value, or one outside the
# test's own scratch directory, would make that code act on the host. The scratch directory
# itself is accepted.
require_scratch_path()
{
    local path="$1"
    local scratch
    scratch="$(cd "${BATS_TEST_TMPDIR:?}" && pwd -P)"
    case "$path" in
        "$scratch" | "$scratch"/* | "${BATS_TEST_TMPDIR}" | "${BATS_TEST_TMPDIR}"/*) return 0 ;;
    esac
    printf 'the path is not inside the test scratch directory: %s\n' "${path:-<empty>}" >&2
    return 1
}

# Prints a directory to use as the whole PATH. It holds a wrapper for each listed host tool and
# nothing else, so a command the test did not shadow is "not found" instead of running on the
# host. A wrapper is a file, not a link: a fake written later under the same name replaces the
# wrapper instead of writing through a link onto the host binary.
sandbox_path()
{
    local dir="${BATS_TEST_TMPDIR:?}/sandbox-bin"
    local tool real
    mkdir -p "$dir"
    for tool in "$@"; do
        # type -P returns the file even for a name bash also has as a builtin, such as echo.
        # command -v returns the bare name there, and a wrapper that execs a bare name finds
        # itself on this PATH and execs itself forever.
        real="$(PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin type -P "$tool")"
        case "$real" in
            /*) ;;
            *)
                printf 'sandbox_path: %s is not installed\n' "$tool" >&2
                return 1
                ;;
        esac
        printf '#!/bin/sh\nexec %s "$@"\n' "'$real'" >"$dir/$tool"
        chmod 0755 "$dir/$tool"
    done
    printf '%s\n' "$dir"
}

# run_in_sandbox_path COMMAND [ARGS]
# Runs COMMAND with PATH limited to the tools listed in SANDBOX_TOOLS. Use it under `run`, which
# keeps the PATH change out of the test shell.
run_in_sandbox_path()
{
    local path
    path="$(sandbox_path ${SANDBOX_TOOLS:-})" || return 125
    PATH="$path" "$@"
}

read_file_or_empty()
{
    local path="$1"
    [ -f "$path" ] || return 0
    cat "$path"
}

# extract_shell_if_block FILE START [NTH TOTAL]
# Prints the if block whose first line contains START. START must occur TOTAL times in FILE
# (default 1), the block taken is occurrence NTH (default 1), and that line must open an if.
extract_shell_if_block()
{
    local file="$1"
    local start="$2"
    local nth="${3:-1}"
    local total="${4:-1}"

    awk -v start="$start" -v nth="$nth" -v total="$total" '
        index($0, start) {
            seen++
            if (seen == nth) {
                copy = 1
                if ($0 !~ /^[[:space:]]*if[[:space:]\[]/) {
                    not_if = 1
                }
            }
        }
        copy {
            print
            if ($0 ~ /^[[:space:]]*if[[:space:]\[]/) {
                depth++
            }
            line = $0
            while (line ~ /(^|[;[:space:]])fi([;[:space:]]|$)/) {
                depth--
                sub(/(^|[;[:space:]])fi([;[:space:]]|$)/, " ", line)
            }
            if (depth == 0) {
                closed = 1
                copy = 0
            }
        }
        END {
            if (seen != total) {
                printf "extract_shell_if_block: \"%s\" occurs %d times, expected %d\n", start, seen, total > "/dev/stderr"
                exit 1
            }
            if (not_if) {
                printf "extract_shell_if_block: \"%s\" does not open an if block\n", start > "/dev/stderr"
                exit 1
            }
            if (!closed) {
                printf "extract_shell_if_block: the block at \"%s\" has no closing fi\n", start > "/dev/stderr"
                exit 1
            }
        }
    ' "$file"
}

# extract_line_range FILE START END
# Prints the lines from the only line matching START through the next line matching END.
extract_line_range()
{
    local file="$1"
    local start="$2"
    local end="$3"

    awk -v start="$start" -v end="$end" '
        $0 ~ start {
            starts++
            if (starts == 1) {
                copy = 1
            }
        }
        copy {
            print
            if ($0 ~ end) {
                closed = 1
                copy = 0
            }
        }
        END {
            if (starts != 1) {
                printf "extract_line_range: /%s/ matches %d lines, expected 1\n", start, starts > "/dev/stderr"
                exit 1
            }
            if (!closed) {
                printf "extract_line_range: no line matches /%s/ after /%s/\n", end, start > "/dev/stderr"
                exit 1
            }
        }
    ' "$file"
}

# extract_unique_line FILE PATTERN
# Prints the only line matching PATTERN.
extract_unique_line()
{
    local file="$1"
    local pattern="$2"

    awk -v pattern="$pattern" '
        $0 ~ pattern {
            matches++
            line = $0
        }
        END {
            if (matches != 1) {
                printf "extract_unique_line: /%s/ matches %d lines, expected 1\n", pattern, matches > "/dev/stderr"
                exit 1
            }
            print line
        }
    ' "$file"
}
