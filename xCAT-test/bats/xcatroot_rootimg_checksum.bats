#!/usr/bin/env bats

load 'helpers/shell_source'

URL=http://192.0.2.1:80//install/netboot/img/rootimg.cpio.gz
FP=31:94:09:9D:B1:24:3F:32:C0:B9:1A:BB:AC:F4:74:2B:80:F9:77:B2

ALL_SCRIPTS='xCAT-server/share/xcat/netboot/rh/dracut_033/xcatroot bash
xCAT-server/share/xcat/netboot/rh/dracut_047/xcatroot bash
xCAT-server/share/xcat/netboot/rh/dracut_105/stateless/xcatroot bash
xCAT-server/share/xcat/netboot/sles/dracut_033/xcatroot bash
xCAT-server/share/xcat/netboot/ubuntu/dracut/xcatroot dash'

# The scripts that receive the root image over UFTP when nodeset asks for it.
UFTP_SCRIPTS='xCAT-server/share/xcat/netboot/rh/dracut_033/xcatroot bash
xCAT-server/share/xcat/netboot/rh/dracut_047/xcatroot bash
xCAT-server/share/xcat/netboot/rh/dracut_105/stateless/xcatroot bash
xCAT-server/share/xcat/netboot/sles/dracut_033/xcatroot bash'

setup()
{
    [ "$(uname -s)" = Linux ] || skip 'xcatroot needs a Linux root filesystem sandbox'
    bwrap=$(PATH=/usr/bin:/bin type -P bwrap) || {
        echo 'Install bubblewrap to run the xcatroot test' >&2
        return 1
    }
    for tool in bash dash cpio gzip sha256sum timeout; do
        PATH=/usr/bin:/bin type -P "$tool" >/dev/null || {
            echo "Required utility is unavailable: $tool" >&2
            return 1
        }
    done
    FX="$BATS_TEST_TMPDIR/fx"

    # nodeset asks a node to check its root image with this kernel argument.
    CMDLINE=rootimgchecksum=yes
    mkdir -p "$FX/bin" "$FX/served" "$FX/tree/etc" "$FX/lib"
    printf 'packed image\n' >"$FX/tree/etc/marker"
    (cd "$FX/tree" && find . | cpio -H newc -o 2>/dev/null | gzip -c) >"$FX/served/rootimg.cpio.gz"
    (cd "$FX/served" && sha256sum rootimg.cpio.gz >rootimg.cpio.gz.sha256)
    SHA=$(cat "$FX/served/rootimg.cpio.gz.sha256")
    SHA=${SHA%% *}
    TRANSFER=http://192.0.2.1:1045/xcat-uftp/v1/transfer/$SHA/install/netboot/img/rootimg.cpio.gz
    cp "$FX/served/rootimg.cpio.gz" "$FX/payload"
    printf '%s\n' status=queued job=0123456789abcdef file=rootimg.cpio.gz port=1044 mcast=230.4.4.1 \
        server_id=0xC0000201 server_ip=192.0.2.1 client_ip=192.0.2.50 start_in=0 timeout=5 >"$FX/ack"

    cat >"$FX/lib/dracut-lib.sh" <<'SH'
getarg() {
    _found=1
    _value=
    for _token in $(cat /fx/cmdline); do
        case "$1" in
        *=)
            case "$_token" in
            "$1"*) _value=${_token#"$1"}; _found=0 ;;
            esac
            ;;
        *) [ "$_token" != "$1" ] || _found=0 ;;
        esac
    done
    [ -z "$_value" ] || echo "$_value"
    return $_found
}
SH
    # /fx/image.plan and /fx/checksum.plan hold one answer for each request: ok, damaged, 503, garbage or other.
    # other is a checksum file that lists another image, as after packimage replaced it.
    cat >"$FX/bin/serve" <<'SH'
#!/bin/sh
url=$1 out=$2
printf '%s\n' "$url" >>/fx/downloads
case "$url" in
*/xcat-uftp/v1/transfer/*) [ -f /fx/ack ] && cp /fx/ack "$out" && echo 200 || echo 503; exit ;;
*/xcat-uftp/v1/job/*) echo 404; exit ;;
esac
name=${url##*/}
case "$name" in *.sha256) plan=/fx/checksum.plan ;; *) plan=/fx/image.plan ;; esac
set -- $(cat "$plan" 2>/dev/null)
answer=${1:-ok}
[ $# -eq 0 ] || shift
echo "$*" >"$plan"
[ -f "/fx/served/$name" ] || { echo 404; exit; }
case "$answer" in
503) echo 503; exit ;;
damaged) head -c 100 "/fx/served/$name" >"$out" ;;
garbage) echo '<html>busy</html>' >"$out" ;;
other) printf '%064d  %s\n' 0 "${name%.sha256}" >"$out" ;;
*) cp "/fx/served/$name" "$out" ;;
esac
echo 200
SH
    cat >"$FX/bin/curl" <<'SH'
#!/bin/sh
out= format= fail=
for arg do
    [ "$prev" != -o ] || out=$arg
    [ "$prev" != -w ] || format=$arg
    [ "$arg" != --fail ] || fail=1
    case "$arg" in *://*) url=$arg ;; esac
    prev=$arg
done
code=$(/fx/bin/serve "$url" "${out:-${url##*/}}")
[ -z "$format" ] || printf '%s' "$code"
[ "$code" = 200 ] || [ -z "$fail" ] || exit 22
SH
    cat >"$FX/bin/wget" <<'SH'
#!/bin/sh
out=
for arg do
    [ "$prev" != -O ] || out=$arg
    case "$arg" in *://*) url=$arg ;; esac
    prev=$arg
done
code=$(/fx/bin/serve "$url" "${out:-${url##*/}}")
echo "  HTTP/1.1 $code" >&2
[ "$code" = 200 ] || exit 8
SH
    for tool in logger mount; do
        printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>/fx/%s\n' "$tool" >"$FX/bin/$tool"
    done
    # uftpd delivers /fx/payload in a session with the server that the listener named.
    cat >"$FX/bin/uftpd" <<'SH'
#!/bin/sh
while [ $# -gt 0 ]; do
    case "$1" in
    -D) dest=$2; shift ;;
    -T) temp=$2; shift ;;
    -F) status=$2; shift ;;
    -p|-M|-I|-x|-S) shift ;;
    esac
    shift
done
# uftpd takes only absolute directories.
for dir in "$dest" "$temp"; do
    case "$dir" in
    /*) ;;
    *) echo "ERROR: must specify absolute pathname for $dir" >&2; exit 1 ;;
    esac
done
printf 'CONNECT;t;C0000201;1;192.0.2.1;mn\n' >>"$status"
cp /fx/payload "$temp/rootimg.cpio.gz"
printf 'RESULT;t;C0000201;1;rootimg.cpio.gz;1KB;copied\n' >>"$status"
mv "$temp/rootimg.cpio.gz" "$dest/rootimg.cpio.gz"
trap 'exit 0' TERM
while :; do sleep 1 & wait $!; done
SH
    # A node retries for ever, so the stub stops xcatroot after /fx/maxwaits waits.
    # The UFTP receiver and its helper poll every second, which really waits.
    cat >"$FX/bin/sleep" <<'SH'
#!/bin/sh
[ "$*" != 1 ] || exec /usr/bin/sleep 1
printf '%s\n' "$*" >>/fx/sleep
[ "$(grep -c . /fx/sleep)" -lt "$(cat /fx/maxwaits)" ] || kill -TERM "$PPID"
SH
    chmod +x "$FX/bin/"*
}

# Run xcatroot as dracut does: from /, with the new root as the third argument.
run_xcatroot()
{
    local script="$1" shell="$2"
    shift 2
    local sandbox=("$bwrap" --unshare-all --die-with-parent --new-session
        --ro-bind /usr /usr --ro-bind /etc /etc --symlink usr/bin /bin --symlink usr/sbin /sbin
        --dir /lib --proc /proc --dev /dev --tmpfs /tmp --dir /sysroot
        --bind "$FX" /fx --ro-bind "$FX/lib/dracut-lib.sh" /lib/dracut-lib.sh
        --ro-bind "$(repo_path "$script")" /xcatroot --chdir /
        --setenv PATH /fx/bin:/usr/bin:/bin --setenv imgurl "$URL" --setenv XCAT 192.0.2.1:3001
        --setenv rootimgchecksum "${CMDLINE#rootimgchecksum=}" --setenv XCAT_UFTP_POLL 60 "$@")
    [ ! -e /usr/lib64 ] || sandbox+=(--symlink usr/lib64 /lib64)
    for multiarch in /usr/lib/*-linux-gnu; do
        [ ! -d "$multiarch" ] || sandbox+=(--ro-bind "$multiarch" "/lib/${multiarch##*/}")
    done
    # genimage puts the helper in every initial ramdisk that can receive the root image over UFTP.
    [ -n "$NO_UFTP_HELPER" ] || sandbox+=(--ro-bind "$(repo_path xCAT-server/share/xcat/netboot/imgutils/xcat-rootimg-fetch.sh)" /lib/xcat-rootimg-fetch.sh)
    echo "imgurl=$URL XCAT=192.0.2.1:3001 nonodestatus $CMDLINE $UFTP" >"$FX/cmdline"
    echo "$IMAGE_PLAN" >"$FX/image.plan"
    echo "$CHECKSUM_PLAN" >"$FX/checksum.plan"
    echo "${MAXWAITS:-100}" >"$FX/maxwaits"
    rm -f "$FX/downloads" "$FX/sleep" "$FX/logger" "$FX/extracted"
    timeout 60 "${sandbox[@]}" /bin/bash -c "
        [ ! -e /fx/stale ] || cp /fx/stale /rootimg.cpio.gz
        $shell /xcatroot eth0 xcat /sysroot </dev/null >/fx/console 2>&1
        cat /sysroot/etc/marker >/fx/extracted 2>/dev/null
        true"
}

# Every script must end with the expected extraction, downloads, waits and message.
check_each_script()
{
    local extracted="$1" downloads="$2" waits="$3" message="$4" script shell log
    shift 4
    while read -r script shell; do
        run_xcatroot "$script" "$shell" "$@"
        [ "$(cat "$FX/extracted" 2>/dev/null)" = "$extracted" ] || { echo "$script extracted: $(cat "$FX/extracted" 2>/dev/null)"; return 1; }
        [ "$(tr '\n' ' ' <"$FX/downloads")" = "$downloads" ] || { echo "$script fetched: $(cat "$FX/downloads")"; return 1; }
        [ "$(cat "$FX/sleep" 2>/dev/null | grep -c .)" = "$waits" ] || { echo "$script waited: $(cat "$FX/sleep" 2>/dev/null)"; return 1; }
        case "$script" in */ubuntu/*) log="$FX/console" ;; *) log="$FX/logger" ;; esac
        [ -z "$message" ] || grep -q -- "$message" "$log" || { echo "$script did not log: $message"; return 1; }
    done <<<"${SCRIPTS:-$ALL_SCRIPTS}"
}

@test 'an image that matches its published checksum is extracted' {
    check_each_script 'packed image' "$URL.sha256 $URL $URL.sha256 " 0 ''
}

@test 'an image that matches a later line of the checksum file is extracted, as while packimage replaces it' {
    { printf '%064d  rootimg.cpio.gz\n' 0; cat "$FX/served/rootimg.cpio.gz.sha256"; } >"$FX/list"
    mv "$FX/list" "$FX/served/rootimg.cpio.gz.sha256"
    check_each_script 'packed image' "$URL.sha256 $URL $URL.sha256 " 0 ''
}

@test 'a download that began before packimage replaced the image matches the checksum file fetched before it' {
    CHECKSUM_PLAN='ok other'
    check_each_script 'packed image' "$URL.sha256 $URL $URL.sha256 " 0 ''
}

@test 'an image that matches no line of the checksum file is never extracted' {
    printf '%064d  rootimg.cpio.gz\n%064d  rootimg.cpio.gz\n' 0 1 >"$FX/served/rootimg.cpio.gz.sha256"
    MAXWAITS=2
    check_each_script '' "$URL.sha256 $URL $URL.sha256 $URL.sha256 $URL $URL.sha256 " 2 'rootimg.cpio.gz does not match'
}

@test 'a damaged download is fetched again until it matches the checksum' {
    IMAGE_PLAN=damaged
    check_each_script 'packed image' "$URL.sha256 $URL $URL.sha256 $URL.sha256 $URL $URL.sha256 " 1 'rootimg.cpio.gz does not match'
}

@test 'a failed checksum download is retried, also after a damaged download' {
    IMAGE_PLAN='damaged ok' CHECKSUM_PLAN='ok ok ok 503'
    check_each_script 'packed image' "$URL.sha256 $URL $URL.sha256 $URL.sha256 $URL $URL.sha256 $URL.sha256 $URL $URL.sha256 " 2 'cannot download'
}

@test 'a checksum file that holds no checksum is retried' {
    CHECKSUM_PLAN='garbage garbage'
    check_each_script 'packed image' "$URL.sha256 $URL $URL.sha256 $URL.sha256 $URL $URL.sha256 " 1 'rootimg.cpio.gz does not match'
}

@test 'a file that an interrupted download left is checked before it is used' {
    head -c 100 "$FX/served/rootimg.cpio.gz" >"$FX/stale"
    check_each_script 'packed image' "$URL.sha256 $URL.sha256 $URL $URL.sha256 " 0 ''
}

@test 'an image without a published checksum is never extracted while the check is on' {
    rm "$FX/served/rootimg.cpio.gz.sha256"
    MAXWAITS=2
    check_each_script '' "$URL.sha256 $URL $URL.sha256 $URL.sha256 $URL $URL.sha256 " 2 'cannot download .*rootimg.cpio.gz.sha256'
}

@test 'an initial ramdisk without sha256sum never extracts the image while the check is on' {
    # /usr/bin becomes links to the real tools, without sha256sum.
    mkdir "$FX/usrbin"
    for tool in /usr/bin/*; do
        [ "${tool##*/}" = sha256sum ] || ln -s "/realusr/bin/${tool##*/}" "$FX/usrbin/${tool##*/}"
    done
    MAXWAITS=2
    check_each_script '' "$URL.sha256 $URL $URL.sha256 $URL " 2 'has no sha256sum' --ro-bind /usr /realusr --ro-bind "$FX/usrbin" /usr/bin
}

@test 'an image is extracted unchecked when nodeset does not ask for the check' {
    rm "$FX/served/rootimg.cpio.gz.sha256"
    CMDLINE=
    check_each_script 'packed image' "$URL " 0 'did not ask for a check of rootimg.cpio.gz, so it is not checked'
}

@test 'an image is extracted unchecked when the check is turned off' {
    rm "$FX/served/rootimg.cpio.gz.sha256"
    CMDLINE=rootimgchecksum=no
    check_each_script 'packed image' "$URL " 0 'did not ask for a check of rootimg.cpio.gz, so it is not checked'
}

@test 'an image received over UFTP that matches its checksum is extracted without an HTTP download' {
    SCRIPTS=$UFTP_SCRIPTS UFTP="xcat.uftp=1045 xcat.uftpfp=$FP"
    check_each_script 'packed image' "$URL.sha256 $TRANSFER $URL.sha256 " 0 'Received rootimg.cpio.gz over UFTP'
}

@test 'an image received over UFTP that does not match its checksum is downloaded again over HTTP' {
    head -c 100 "$FX/served/rootimg.cpio.gz" >"$FX/payload"
    SCRIPTS=$UFTP_SCRIPTS UFTP="xcat.uftp=1045 xcat.uftpfp=$FP"
    check_each_script 'packed image' "$URL.sha256 $TRANSFER $URL.sha256 $URL.sha256 $URL $URL.sha256 " 1 'rootimg.cpio.gz does not match'
}

@test 'an image received over UFTP while packimage replaces it matches the checksum file fetched before the request' {
    CHECKSUM_PLAN='ok other'
    SCRIPTS=$UFTP_SCRIPTS UFTP="xcat.uftp=1045 xcat.uftpfp=$FP"
    check_each_script 'packed image' "$URL.sha256 $TRANSFER $URL.sha256 " 0 'Received rootimg.cpio.gz over UFTP'
}

@test 'an unavailable listener is followed by an HTTP download without a wait' {
    rm "$FX/ack"
    SCRIPTS=$UFTP_SCRIPTS UFTP="xcat.uftp=1045 xcat.uftpfp=$FP"
    check_each_script 'packed image' "$URL.sha256 $TRANSFER $TRANSFER $URL $URL.sha256 " 0 'Cannot receive .*rootimg.cpio.gz over UFTP'
}

@test 'a checksum file that cannot be downloaded before the request is followed by an HTTP download' {
    CHECKSUM_PLAN=503
    SCRIPTS=$UFTP_SCRIPTS UFTP="xcat.uftp=1045 xcat.uftpfp=$FP"
    check_each_script 'packed image' "$URL.sha256 $URL $URL.sha256 " 0 'lists no SHA-256 checksum for rootimg.cpio.gz'
}

@test 'an initial ramdisk without the UFTP helper downloads the image over HTTP' {
    NO_UFTP_HELPER=1 SCRIPTS=$UFTP_SCRIPTS UFTP="xcat.uftp=1045 xcat.uftpfp=$FP"
    check_each_script 'packed image' "$URL.sha256 $URL $URL.sha256 " 0 'Cannot receive .*rootimg.cpio.gz over UFTP'
}

@test 'UFTP is not used for an image that is not checked' {
    rm "$FX/served/rootimg.cpio.gz.sha256"
    CMDLINE= SCRIPTS=$UFTP_SCRIPTS UFTP="xcat.uftp=1045 xcat.uftpfp=$FP"
    check_each_script 'packed image' "$URL " 0 'Cannot receive .*rootimg.cpio.gz over UFTP'
}
