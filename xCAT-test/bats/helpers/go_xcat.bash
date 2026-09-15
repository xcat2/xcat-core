#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/shell_source.bash"

# go-xcat is read from the checkout only.
go_xcat_require_source()
{
    GO_XCAT_SOURCE="$(require_repo_file 'xCAT-server/share/xcat/tools/go-xcat')" || return 1
    export GO_XCAT_SOURCE
}

# Prints the named go-xcat functions. A function that go-xcat does not define exactly once, that
# reaches the next function or the end of the file before its closing brace, fails instead of
# printing a partial body.
go_xcat_extract_functions()
{
    local function_name
    for function_name in "$@"; do
        awk -v name="$function_name" '
            $0 == "function " name "()" {
                found++
                if (found == 1) {
                    copy = 1
                    print
                    next
                }
            }
            copy {
                if ($0 ~ /^function [A-Za-z_][A-Za-z0-9_]*\(\)$/) {
                    reached_next = 1
                    copy = 0
                    next
                }
                print
                if ($0 == "}") {
                    closed = 1
                    copy = 0
                }
            }
            END {
                if (found != 1) {
                    printf "go-xcat defines %s %d times, expected 1\n", name, found > "/dev/stderr"
                    exit 1
                }
                if (reached_next) {
                    printf "%s: the next function starts before the closing brace\n", name > "/dev/stderr"
                    exit 1
                }
                if (!closed) {
                    printf "%s: no closing brace before the end of go-xcat\n", name > "/dev/stderr"
                    exit 1
                }
            }
        ' "$GO_XCAT_SOURCE" || return 1
    done
}

go_xcat_load_functions()
{
    local function_body function_name
    function_body="$(go_xcat_extract_functions "$@")" || return 1
    eval "$function_body"
    for function_name in "$@"; do
        declare -F "$function_name" >/dev/null || {
            printf 'missing %s\n' "$function_name" >&2
            return 70
        }
    done
}

joined_file_lines()
{
    local path="$1"
    local line separator=""
    [ -f "$path" ] || return 0
    while IFS= read -r line; do
        printf '%s%s' "$separator" "$line"
        separator=";"
    done <"$path"
}
