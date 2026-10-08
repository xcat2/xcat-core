#!/bin/bash
PATH=""
source /tmp/source/xCAT-server/share/xcat/tools/go-xcat || exit 70
TMP_DIR=/tmp/fixture
GO_XCAT_DEFAULT_BASE_URL=https://repo.example.invalid
GO_XCAT_DEFAULT_INSTALL_PATH=/tmp/fixture/install

yum() { printf '%s\n' "$*" >> /tmp/fixture/yum.log; }
download_file()
{
    printf '%s\n' "$1" >> /tmp/fixture/download.log
    [ "$COMMON_PRESENT" = 1 ] || return 1
    printf '<repomd/>\n' > "$2"
}

add_xcat_dep_common_repo_yum_or_zypper "$1" "$2" || exit $?
refresh_xcat_dep_repository_ids
printf '%s\n' "${GO_XCAT_DEP_REPOSITORY_IDS[*]}" > /tmp/fixture/ids
