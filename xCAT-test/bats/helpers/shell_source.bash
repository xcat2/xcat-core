#!/usr/bin/env bash

repo_root()
{
    printf '%s\n' "${BATS_TEST_DIRNAME}/../.."
}

repo_path()
{
    printf '%s/%s\n' "$(repo_root)" "$1"
}

require_repo_file()
{
    local path
    path="$(repo_path "$1")"
    [ -r "$path" ] || skip "$path is required"
    printf '%s\n' "$path"
}

read_file_or_empty()
{
    local path="$1"
    [ -f "$path" ] || return 0
    cat "$path"
}

extract_shell_function()
{
    local file="$1"
    local name="$2"

    awk -v name="$name" '
        BEGIN {
            signature = "^[[:space:]]*(function[[:space:]]+)?" name "([[:space:]]*\\(\\))?[[:space:]]*$"
            inline_signature = "^[[:space:]]*(function[[:space:]]+)?" name "([[:space:]]*\\(\\))?[[:space:]]*\\{"
        }
        $0 ~ signature || $0 ~ inline_signature {
            copy = 1
        }
        copy {
            print
            opened += gsub(/\{/, "{")
            closed += gsub(/\}/, "}")
            if (opened > 0 && opened == closed) {
                found = 1
                exit
            }
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' "$file"
}

extract_shell_if_block()
{
    local file="$1"
    local start="$2"

    awk -v start="$start" '
        index($0, start) {
            copy = 1
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
                found = 1
                exit
            }
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' "$file"
}

extract_line_range()
{
    local file="$1"
    local start="$2"
    local end="$3"

    awk -v start="$start" -v end="$end" '
        $0 ~ start {
            copy = 1
        }
        copy {
            print
            if ($0 ~ end) {
                found = 1
                exit
            }
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' "$file"
}

extract_first_matching_line()
{
    local file="$1"
    local pattern="$2"

    awk -v pattern="$pattern" '
        $0 ~ pattern {
            print
            found = 1
            exit
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' "$file"
}
