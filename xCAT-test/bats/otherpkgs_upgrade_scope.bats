#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    [ "$(uname -s)" = Linux ] || skip 'otherpkgs filesystem isolation requires Linux'
    local utility executable
    local utilities=(bash sh basename dirname cat cp expr grep ls mkdir rm uname wc)
    local bwrap
    bwrap=$(PATH=/usr/bin:/bin type -P bwrap) || {
        echo 'Install bubblewrap to run the otherpkgs test' >&2
        return 1
    }
    postscripts=$(repo_path xCAT/postscripts)
    fixture="$BATS_TEST_TMPDIR/fixture"
    mkdir -p "$fixture/bin"
    sandbox=(env -i PATH=/usr/bin:/bin LC_ALL=C "$bwrap"
        --unshare-all --die-with-parent --new-session
        --ro-bind / / --tmpfs /etc --tmpfs /usr/bin --tmpfs /tmp
        --proc /proc --dev /dev --setenv PATH /usr/bin --setenv LC_ALL C)
    if PATH=/usr/bin:/bin type -P coreutils >/dev/null; then
        utilities+=(coreutils)
    fi
    for utility in "${utilities[@]}"; do
        executable=$(PATH=/usr/bin:/bin type -P "$utility") || {
            echo "Required utility is unavailable: $utility" >&2
            return 1
        }
        sandbox+=(--ro-bind "$executable" "/usr/bin/$utility")
    done
    run "${sandbox[@]}" /usr/bin/sh -c 'test ! -e /etc/os-release'
    if [ "$status" -ne 0 ]; then
        echo "Cannot isolate otherpkgs: $output" >&2
        return 1
    fi
}

run_case()
{
    local manager=$1 scenario=$2
    local verbose='' remote='' mounted='' repoonly='' multiple='' empty=''
    local upgrade_status=0 install_status=0
    case "$scenario" in
        http) verbose=1; remote=1 ;;
        mounted) mounted=1 ;;
        upgrade_failure) upgrade_status=17; verbose=1 ;;
        install_failure) install_status=23; verbose=1 ;;
        repoonly) repoonly=1; remote=1 ;;
        multiple) multiple=1; verbose=1 ;;
        empty) remote=1; empty=1 ;;
    esac
    printf '#!/usr/bin/sh\nexit 0\n' >"$fixture/bin/logger"
    printf '#!/usr/bin/sh\nexit 1\n' >"$fixture/bin/dpkg"
    printf '#!/usr/bin/sh\n[ "$*" = --version ]\n' >"$fixture/bin/rpm"
    if [ "$mounted" ]; then
        printf '#!/usr/bin/sh\nprintf "%%s\\n" "package-server:/install on /install type nfs (rw)"\n' >"$fixture/bin/mount"
    else
        printf '#!/usr/bin/sh\nexit 0\n' >"$fixture/bin/mount"
    fi
    cat >"$fixture/bin/$manager" <<'SH'
#!/usr/bin/sh
printf '%s\t' "${0##*/}" "SCOPE_ENV=${SCOPE_ENV:-}" "$@" >> /tmp/fixture/commands
printf '\n' >> /tmp/fixture/commands
sequence=$(wc -l < /tmp/fixture/commands)
mkdir "/tmp/fixture/repos.$sequence"
cp /etc/yum.repos.d/*.repo "/tmp/fixture/repos.$sequence/" 2>/dev/null || :
for argument do
    case "$argument" in
        upgrade) printf '%s\n' upgrade-result; exit "$UPGRADE_STATUS" ;;
        install) printf '%s\n' install-result; exit "$INSTALL_STATUS" ;;
    esac
done
exit 0
SH
    chmod +x "$fixture/bin/"*

    local otherpkgdir=/install/other packages=alpha/tool-one,beta/tool-two
    local list_count=1
    [ ! "$remote" ] || otherpkgdir=https://packages.example.invalid/extra,/install/other
    [ ! "$empty" ] || packages=
    [ ! "$multiple" ] || list_count=2
    local command=("${sandbox[@]}"
        --bind "$fixture" /tmp/fixture
        --ro-bind "$postscripts" /tmp/postscripts --chdir /tmp/fixture)
    local tool
    for tool in logger dpkg rpm mount "$manager"; do
        command+=(--ro-bind "$fixture/bin/$tool" "/usr/bin/$tool")
    done
    command+=(
        --setenv OSVER rhel9 --setenv ARCH x86_64 --setenv UPDATENODE 1
        --setenv NFSSERVER package-server --setenv HTTPPORT 80
        --setenv INSTALLDIR /install --setenv OTHERPKGDIR "$otherpkgdir"
        --setenv OTHERPKGS_INDEX "$list_count" --setenv OTHERPKGS1 "$packages"
        --setenv ENVLIST1 SCOPE_ENV=first --setenv VERBOSE "$verbose"
        --setenv UPGRADE_STATUS "$upgrade_status" --setenv INSTALL_STATUS "$install_status")
    if [ "$multiple" ]; then
        command+=(--setenv OTHERPKGS2 gamma/tool-three --setenv ENVLIST2 SCOPE_ENV=second)
    fi
    local runner
    runner=$(cat <<'SH'
/usr/bin/bash /tmp/postscripts/otherpkgs "$@"
status=$?
mkdir /tmp/fixture/final-repos
cp /etc/yum.repos.d/*.repo /tmp/fixture/final-repos/ 2>/dev/null || :
exit "$status"
SH
    )
    command+=(/usr/bin/sh -c "$runner" otherpkgs-test)
    [ ! "$repoonly" ] || command+=(--repoonly)

    run "${command[@]}"
    if [ "$status" -ne "$((upgrade_status + install_status))" ]; then
        echo "$output" >&2
        return 1
    fi
    [ -f "$fixture/commands" ]

    local line operand sequence=0
    local arguments=() paths=()
    : >"$fixture/transactions"
    while IFS= read -r line; do
        sequence=$((sequence + 1))
        IFS=$'\t' read -r -a arguments <<<"$line"
        operand=
        for operand in "${arguments[@]:2}"; do
            [[ "$operand" = -* ]] || break
        done
        case "$operand" in clean|list) continue ;; esac
        printf '%s\n' "$line" >>"$fixture/transactions"
        paths=(alpha beta)
        [ ! "$empty" ] || paths=()
        if [ "$multiple" ] && [ "${arguments[1]}" = SCOPE_ENV=second ]; then
            paths=(gamma)
        fi
        check_repositories "$fixture/repos.$sequence" "${paths[@]}"
    done <"$fixture/commands"

    : >"$fixture/expected-transactions"
    : >"$fixture/expected-printed"
    if [ ! "$repoonly" ]; then
        expect_transaction first -y '--disablerepo=*' '--enablerepo=xcat-otherpkgs*' upgrade
        if [ ! "$empty" ]; then
            expect_transaction first -y install tool-one tool-two
        fi
        if [ "$multiple" ]; then
            expect_transaction second -y '--disablerepo=*' '--enablerepo=xcat-otherpkgs*' upgrade
            expect_transaction second -y install tool-three
        fi
    fi
    diff -u "$fixture/expected-transactions" "$fixture/transactions"

    : >"$fixture/printed"
    while IFS= read -r line; do
        [[ "$line" = SCOPE_ENV=* ]] || continue
        read -r -a arguments <<<"$line"
        printf '%s\t' "${arguments[@]}" >>"$fixture/printed"
        printf '\n' >>"$fixture/printed"
    done <<<"$output"
    diff -u "$fixture/expected-printed" "$fixture/printed"

    paths=(alpha beta)
    [ ! "$empty" ] || paths=()
    [ ! "$multiple" ] || paths=(gamma)
    check_repositories "$fixture/final-repos" "${paths[@]}"
    if [ "$verbose" ] && [ ! "$repoonly" ]; then
        [[ $'\n'"$output"$'\n' = *$'\nupgrade-result\n'* ]]
        if [ ! "$empty" ]; then
            [[ $'\n'"$output"$'\n' = *$'\ninstall-result\n'* ]]
        fi
    fi
}

expect_transaction()
{
    local label=$1
    shift
    printf '%s\t' "$manager" "SCOPE_ENV=$label" "$@" >>"$fixture/expected-transactions"
    printf '\n' >>"$fixture/expected-transactions"
    if [ "$verbose" ]; then
        printf '%s\t' "SCOPE_ENV=$label" "$manager" "$@" >>"$fixture/expected-printed"
        printf '\n' >>"$fixture/expected-printed"
    fi
}

check_repositories()
{
    local directory=$1
    shift
    local base=http://package-server:80 index=0 pkgpath file
    [ ! "$mounted" ] || base=file://
    {
        printf '%s\t%s\t1\t0\n' xCAT-rhel9-path0 "$base/install/rhel9/x86_64/BaseOS"
        printf '%s\t%s\t1\t0\n' xCAT-rhel9-path1 "$base/install/rhel9/x86_64/AppStream"
        if [ "$remote" ]; then
            printf '%s\t%s\t1\t0\n' xcat-otherpkgs0 https://packages.example.invalid/extra
            index=1
        fi
        for pkgpath do
            printf '%s\t%s\t1\t0\n' "xcat-otherpkgs$index" "$base/install/other/$pkgpath"
            index=$((index + 1))
        done
    } | LC_ALL=C sort >"$fixture/expected-repos"
    : >"$fixture/repos"
    for file in "$directory/"*.repo; do
        [ -f "$file" ] || continue
        awk '
            /^\[[^]]+\]$/ { sections = sections substr($0, 2, length($0) - 2) "\t" }
            /^(baseurl|enabled|gpgcheck)=/ {
                key = substr($0, 1, index($0, "=") - 1)
                value = substr($0, index($0, "=") + 1)
                sub(/[[:space:]]+$/, "", value)
                values[key] = values[key] value "\t"
            }
            END {
                record = sections values["baseurl"] values["enabled"] values["gpgcheck"]
                sub(/\t$/, "", record)
                print record
            }
        ' "$file" >>"$fixture/repos"
    done
    LC_ALL=C sort "$fixture/repos" >"$fixture/sorted-repos"
    diff -u "$fixture/expected-repos" "$fixture/sorted-repos"
}

@test "dnf: HTTP and local repositories" { run_case dnf http; }
@test "dnf: mounted repositories" { run_case dnf mounted; }
@test "dnf: upgrade failure" { run_case dnf upgrade_failure; }
@test "dnf: install failure" { run_case dnf install_failure; }
@test "dnf: repository-only mode" { run_case dnf repoonly; }
@test "dnf: separate package lists" { run_case dnf multiple; }
@test "dnf: remote repository without installs" { run_case dnf empty; }
@test "yum: HTTP and local repositories" { run_case yum http; }
@test "yum: mounted repositories" { run_case yum mounted; }
@test "yum: upgrade failure" { run_case yum upgrade_failure; }
@test "yum: install failure" { run_case yum install_failure; }
@test "yum: repository-only mode" { run_case yum repoonly; }
@test "yum: separate package lists" { run_case yum multiple; }
@test "yum: remote repository without installs" { run_case yum empty; }
