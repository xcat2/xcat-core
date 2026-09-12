#!/usr/bin/env bash

go_xcat_default_source()
{
    printf '%s\n' "${BATS_TEST_DIRNAME}/../../xCAT-server/share/xcat/tools/go-xcat"
}

go_xcat_require_source()
{
    GO_XCAT_SOURCE="${XCAT_TEST_GO_XCAT:-$(go_xcat_default_source)}"
    export GO_XCAT_SOURCE
    [ -r "$GO_XCAT_SOURCE" ] || skip "$GO_XCAT_SOURCE is required"
}

go_xcat_extract_functions()
{
    local function_name
    for function_name in "$@"; do
        awk -v name="$function_name" '
            $0 == "function " name "()" { copy = 1 }
            copy { print }
            copy && /^}$/ { exit }
        ' "$GO_XCAT_SOURCE"
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

read_file_or_empty()
{
    local path="$1"
    [ -f "$path" ] || return 0
    cat "$path"
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
