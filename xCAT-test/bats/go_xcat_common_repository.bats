#!/usr/bin/env bats

load 'helpers/go_xcat'

setup()
{
    go_xcat_require_source
}

run_common_repository_case()
{
    local case_dir="$1"
    local common_present="$2"
    shift 2

    mkdir -p "$case_dir"
    export ADD_LOG="${case_dir}/add.log"
    export COMMON_PRESENT="$common_present"
    export DOWNLOAD_LOG="${case_dir}/download.log"
    export ID_LOG="${case_dir}/id.log"
    export TEST_TMP="$case_dir"

    go_xcat_load_functions \
        add_xcat_dep_common_repo_yum_or_zypper \
        xcat_dep_common_repo_configured \
        refresh_xcat_dep_repository_ids

    TMP_DIR="$TEST_TMP"
    GO_XCAT_DEFAULT_BASE_URL=https://repo.example.invalid
    GO_XCAT_DEP_REPOSITORY_IDS=(xcat-dep)

    yum() { :; }

    download_file()
    {
        printf '%s\n' "$1" >>"$DOWNLOAD_LOG"
        [[ ${COMMON_PRESENT:-0} == 1 ]] || return 1
        : >"$2"
    }

    add_repo_by_url_yum_or_zypper()
    {
        printf '%s %s\n' "$1" "$2" >>"$ADD_LOG"
    }

    xcat_dep_common_repo_configured()
    {
        [[ -s "$ADD_LOG" ]]
    }

    ( add_xcat_dep_common_repo_yum_or_zypper "$@" )
    refresh_xcat_dep_repository_ids
    printf '%s\n' "${GO_XCAT_DEP_REPOSITORY_IDS[*]}" >"$ID_LOG"
}

run_template_generation()
{
    local tmp_dir="$1"
    local repo_log="$2"

    mkdir -p "$tmp_dir"
    export REPO_LOG="$repo_log"
    export TEST_TMP="$tmp_dir"

    go_xcat_load_functions add_repo_by_url_yum_or_zypper

    TMP_DIR="$TEST_TMP"
    GO_XCAT_DEFAULT_INSTALL_PATH=/install/xcat
    yum() { :; }
    add_repo_by_file() { cp "$1" "$REPO_LOG"; }

    add_repo_by_url_yum_or_zypper \
        https://repo.example.invalid/xcat-dep/common xcat-dep-common optional
}

@test "an available remote common repository is enabled" {
    local case_dir="${BATS_TEST_TMPDIR}/remote-present"

    run run_common_repository_case "$case_dir" 1 "" latest
    [ "$status" -eq 0 ]
    [ "$(read_file_or_empty "${case_dir}/download.log")" = "https://repo.example.invalid/yum/latest/xcat-dep/common/repodata/repomd.xml" ]
    [ "$(read_file_or_empty "${case_dir}/add.log")" = "https://repo.example.invalid/yum/latest/xcat-dep/common xcat-dep-common" ]
    [ "$(read_file_or_empty "${case_dir}/id.log")" = "xcat-dep xcat-dep-common" ]
}

@test "a release without the remote common repository remains usable" {
    local case_dir="${BATS_TEST_TMPDIR}/remote-missing"

    run run_common_repository_case "$case_dir" 0 "" 2.18
    [ "$status" -eq 0 ]
    [ "$(read_file_or_empty "${case_dir}/add.log")" = "" ]
    [ "$(read_file_or_empty "${case_dir}/id.log")" = "xcat-dep" ]
}

@test "a custom repository file does not guess an unrelated common repository" {
    local case_dir="${BATS_TEST_TMPDIR}/repo-file"

    run run_common_repository_case "$case_dir" 1 https://repo.example.invalid/custom/xcat-dep.repo latest
    [ "$status" -eq 0 ]
    [ "$(read_file_or_empty "${case_dir}/download.log")" = "" ]
    [ "$(read_file_or_empty "${case_dir}/add.log")" = "" ]
}

@test "a local common repository is enabled beside the distribution repository" {
    local local_root="${BATS_TEST_TMPDIR}/local-repository"
    local case_dir="${BATS_TEST_TMPDIR}/local-present"
    mkdir -p "${local_root}/common/repodata"
    : >"${local_root}/common/repodata/repomd.xml"

    run run_common_repository_case "$case_dir" 0 "$local_root" latest
    [ "$status" -eq 0 ]
    [ "$(read_file_or_empty "${case_dir}/add.log")" = "${local_root}/common xcat-dep-common" ]
}

@test "the optional common repository template tolerates outages and verifies metadata" {
    local template_log="${BATS_TEST_TMPDIR}/generated-common.repo"

    run run_template_generation "$BATS_TEST_TMPDIR" "$template_log"
    [ "$status" -eq 0 ]
    grep -Fxq 'skip_if_unavailable=1' "$template_log"
    grep -Fxq 'repo_gpgcheck=1' "$template_log"
}
