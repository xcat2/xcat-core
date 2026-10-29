#!/usr/bin/env bats
#
# On apt, go-xcat installs the packages the repositories provide and warns about each one they
# do not, as dnf does with strict=0. Only a missing xcat metapackage stops the install, and a
# translated apt must not hide the packages that are there.

load 'helpers/go_xcat'

setup()
{
    go_xcat_require_source
}

# Run install_packages_apt with apt-cache and apt-get doubles. apt-get records its arguments.
#
#	$@	Package names. The names in APT_UNKNOWN (default "missing") are unknown to apt, and
#		"nocandidate" is known with no candidate. apt-cache fails after it reports the
#		package in APT_FAIL_AFTER.
install_with_apt()
{
    (
        log="$BATS_TEST_TMPDIR/apt-get.log"
        PATH=""
        source "$GO_XCAT_SOURCE" || exit 70
        apt-cache()
        {
            [ "$1" = policy ] || return 1
            shift
            local installed='Installed:' candidate='Candidate:' package
            if [ "${LC_ALL:-${LANG:-}}" != C ]; then
                installed='已安装：'
                candidate='候选：'
            fi
            for package in "$@"; do
                case " ${APT_UNKNOWN:-missing} " in
                *" $package "*) continue ;;
                esac
                case "$package" in
                nocandidate) printf '%s:\n  %s (none)\n  %s (none)\n' "$package" "$installed" "$candidate" ;;
                *) printf '%s:\n  %s (none)\n  %s 1.0-1\n  Version table:\n     1.0-1 500\n' \
                    "$package" "$installed" "$candidate" ;;
                esac
                [ "$package" != "${APT_FAIL_AFTER:-}" ] || return 100
            done
        }
        apt-get() { printf '%s\n' "$*" >>"$log"; }
        install_packages_apt -y "$@"
    )
}

@test "packages the repositories do not provide are skipped with a warning" {
    run install_with_apt first missing nocandidate last
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    [ "$(cat "$BATS_TEST_TMPDIR/apt-get.log")" = '--allow-unauthenticated install -y first last' ]
    grep -Fq 'missing: the repositories do not provide it, skipped' <<<"$output"
    grep -Fq 'nocandidate: the repositories do not provide it, skipped' <<<"$output"
}

@test "a translated apt still installs the packages the repositories provide" {
    LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 run install_with_apt first last
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    [ "$(cat "$BATS_TEST_TMPDIR/apt-get.log")" = '--allow-unauthenticated install -y first last' ]
    ! grep -Fq 'skipped' <<<"$output"
}

@test "the install stops when the repositories do not provide the xcat metapackage" {
    APT_UNKNOWN=xcat run install_with_apt perl-xcat xcat xcat-server
    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/apt-get.log" ]
    grep -Fq 'xcat: the repositories do not provide it' <<<"$output"
}

@test "the install stops when apt cannot answer the candidate query" {
    APT_FAIL_AFTER=xcat run install_with_apt xcat xcat-server xcat-buildkit
    [ "$status" -ne 0 ]
    [ ! -e "$BATS_TEST_TMPDIR/apt-get.log" ]
    grep -Fq 'query apt package candidates failed' <<<"$output"
    ! grep -Fq 'skipped' <<<"$output"
}
