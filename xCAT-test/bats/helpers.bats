#!/usr/bin/env bats
# The helpers in helpers/ must fail closed: a missing file, an extraction that matches more or
# less than expected, and a path outside the scratch directory each fail instead of letting a
# test run something else. Every case uses fixtures in its own scratch directory.

load 'helpers/go_xcat'

fixture()
{
    local file="${BATS_TEST_TMPDIR}/script"
    cat >"$file" <<'EOF'
if [ -r $ROOTDIR/etc/x ]
then
    echo first
fi
if [ -r $ROOTDIR/etc/x ]
then
    echo second
fi
start marker
middle
end marker
EOF
    printf '%s\n' "$file"
}

@test "require_repo_file fails for a file that is not in the checkout" {
    run require_repo_file 'xCAT-test/bats/no-such-file'
    [ "$status" -ne 0 ]
    [[ "$output" == *'the checkout file is missing'* ]]
}

@test "require_repo_file prints the path of a checkout file" {
    run require_repo_file 'xCAT-test/bats/README.md'
    [ "$status" -eq 0 ]
    [ -r "$output" ]
}

@test "require_scratch_path accepts the scratch directory and paths below it" {
    run require_scratch_path "$BATS_TEST_TMPDIR"
    [ "$status" -eq 0 ]
    run require_scratch_path "${BATS_TEST_TMPDIR}/root/etc"
    [ "$status" -eq 0 ]
}

@test "require_scratch_path refuses an empty path, a host path and a sibling of the scratch directory" {
    run require_scratch_path ''
    [ "$status" -ne 0 ]
    run require_scratch_path /etc
    [ "$status" -ne 0 ]
    run require_scratch_path "${BATS_TEST_TMPDIR}-sibling"
    [ "$status" -ne 0 ]
}

@test "sandbox_path wraps a tool that bash also has as a builtin" {
    local dir
    dir="$(sandbox_path echo printf)"
    run timeout 10 "${dir}/echo" hello
    [ "$status" -eq 0 ]
    [ "$output" = hello ]
}

@test "sandbox_path leaves every other command out of PATH" {
    local dir
    dir="$(sandbox_path cat)"
    run env PATH="$dir" /bin/sh -c 'uname -s'
    [ "$status" -eq 127 ]
}

@test "sandbox_path fails for a tool that is not installed" {
    run sandbox_path xcat-bats-no-such-tool
    [ "$status" -ne 0 ]
}

@test "a fake written over a sandbox tool replaces the wrapper, not the host binary" {
    local dir real
    dir="$(sandbox_path cat)"
    [ ! -L "${dir}/cat" ]
    printf '#!/bin/sh\nexit 0\n' >"${dir}/cat"
    real="$(type -P cat)"
    [ "$(head -c 2 "$real")" != '#!' ]
}

@test "extract_shell_if_block fails when the start line occurs more often than expected" {
    run extract_shell_if_block "$(fixture)" 'if [ -r $ROOTDIR/etc/x ]'
    [ "$status" -ne 0 ]
    [[ "$output" == *'occurs 2 times, expected 1'* ]]
}

@test "extract_shell_if_block takes the pinned occurrence" {
    run extract_shell_if_block "$(fixture)" 'if [ -r $ROOTDIR/etc/x ]' 2 2
    [ "$status" -eq 0 ]
    [[ "$output" == *second* ]]
    [[ "$output" != *first* ]]
}

@test "extract_shell_if_block fails for a block without its fi" {
    local file="${BATS_TEST_TMPDIR}/unclosed"
    printf 'if true\nthen\n    echo x\n' >"$file"
    run extract_shell_if_block "$file" 'if true'
    [ "$status" -ne 0 ]
}

@test "extract_line_range fails when the end never follows the start" {
    run extract_line_range "$(fixture)" '^start marker$' '^no such end$'
    [ "$status" -ne 0 ]
}

@test "extract_unique_line fails for a pattern that matches more than one line" {
    run extract_unique_line "$(fixture)" 'marker'
    [ "$status" -ne 0 ]
    run extract_unique_line "$(fixture)" '^middle$'
    [ "$status" -eq 0 ]
    [ "$output" = middle ]
}

@test "refute_grep passes when the pattern is absent and fails when it is present" {
    run refute_grep -q 'no such text' "$(fixture)"
    [ "$status" -eq 0 ]
    run refute_grep -q 'start marker' "$(fixture)"
    [ "$status" -ne 0 ]
}

@test "extract_first_matching_line takes the first of several matches and fails when none match" {
    run extract_first_matching_line "$(fixture)" 'marker'
    [ "$status" -eq 0 ]
    [ "$output" = 'start marker' ]
    run extract_first_matching_line "$(fixture)" '^no such line$'
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "extract_shell_function prints one function and fails for a name the file does not define" {
    local file="${BATS_TEST_TMPDIR}/functions"
    printf 'first()\n{\n    echo one\n}\n\nsecond()\n{\n    if true\n    then\n        echo two\n    fi\n}\n' >"$file"

    run extract_shell_function "$file" first
    [ "$status" -eq 0 ]
    [[ "$output" == *'echo one'* ]]
    [[ "$output" != *'echo two'* ]]

    run extract_shell_function "$file" second
    [ "$status" -eq 0 ]
    [[ "$output" == *'echo two'* ]]
    [[ "$output" == *fi* ]]

    run extract_shell_function "$file" missing
    [ "$status" -ne 0 ]
}

@test "go_xcat_extract_functions fails for a missing function and for one without a closing brace" {
    GO_XCAT_SOURCE="${BATS_TEST_TMPDIR}/go-xcat"
    printf 'function good()\n{\n\techo good\n}\nfunction open()\n{\n\techo open\nfunction next()\n{\n}\n' >"$GO_XCAT_SOURCE"

    run go_xcat_extract_functions good
    [ "$status" -eq 0 ]
    run go_xcat_extract_functions missing
    [ "$status" -ne 0 ]
    run go_xcat_extract_functions open
    [ "$status" -ne 0 ]
    [[ "$output" == *'the next function starts before the closing brace'* ]]
}
