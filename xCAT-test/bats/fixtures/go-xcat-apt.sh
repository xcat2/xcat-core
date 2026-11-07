#!/bin/bash
PATH=""
source /tmp/go-xcat || exit 70
TMP_DIR=/tmp/fixture
GO_XCAT_DEFAULT_BASE_URL=https://repo.example.invalid

# apt 3 has no apt-key: a call to it is the defect under test.
apt-key() { printf '%s\n' "$*" >> /tmp/fixture/apt-key.log; return 127; }
dpkg() { [ "$1" = --print-architecture ] && echo riscv64; }
download_file()
{
    printf '%s\n' "$1" >> /tmp/fixture/download.log
    cp /tmp/fixture/key.asc "$2"
}

case "$1" in
add) add_xcat_core_repo_apt "" latest ;;
trash) trash_xcat ;;
*) exit 64 ;;
esac
