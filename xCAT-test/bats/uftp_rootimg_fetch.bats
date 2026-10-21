#!/usr/bin/env bats

load 'helpers/shell_source'

FP=31:94:09:9D:B1:24:3F:32:C0:B9:1A:BB:AC:F4:74:2B:80:F9:77:B2
SERVER=192.0.2.1
NAME=rootimg.cpio.xz
URL=http://$SERVER:80//install/netboot/rhels9/x86_64/compute/$NAME

setup()
{
    command -v sha256sum >/dev/null || skip 'sha256sum is required'
    export FX="$BATS_TEST_TMPDIR/fx"
    mkdir -p "$FX/bin" "$FX/root"
    head -c 300000 /dev/urandom >"$FX/payload"
    SHA=$(sha256sum "$FX/payload")
    SHA=${SHA%% *}
    printf '%s  %s\n' "$SHA" "$NAME" >"$FX/sums"

    cat >"$FX/bin/logger" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >>"$FX/log"
SH
    cat >"$FX/bin/curl" <<'SH'
#!/bin/sh
out=
maxtime=
for arg do
    if [ "$prev" = -o ]; then out=$arg; fi
    if [ "$prev" = --max-time ]; then maxtime=$arg; fi
    case "$arg" in *://*) url=$arg ;; esac
    prev=$arg
done
printf '%s\n' "$url" >>"$FX/curl.log"
case "$url" in
*/xcat-uftp/v1/transfer/*)
    [ -r "$FX/ack" ] || exit 7
    cp "$FX/ack" "$out"
    ;;
*/xcat-uftp/v1/job/*)
    if [ -r "$FX/job_delay" ]; then
        delay=$(cat "$FX/job_delay")
        if [ -n "$maxtime" ] && [ "$maxtime" -lt "$delay" ]; then
            sleep "$maxtime"
            exit 28
        fi
        sleep "$delay"
    fi
    [ -r "$FX/job" ] || exit 22
    cp "$FX/job" "$out"
    ;;
*) exit 22 ;;
esac
SH
    cat >"$FX/bin/uftpd" <<'SH'
#!/bin/sh
echo $$ >"$FX/receiver.pid"
printf '%s\n' "$*" >"$FX/uftpd.args"
while [ $# -gt 0 ]; do
    case "$1" in
    -D) dest=$2; shift ;;
    -T) temp=$2; shift ;;
    -F) status=$2; shift ;;
    -S) cp "$2" "$FX/servers"; shift ;;
    -p|-M|-I|-x) shift ;;
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
sleeper=
trap 'echo terminated >>"$FX/uftpd.events"; [ "$mode" != swap ] || { rm -f "$dest/rootimg.cpio.xz"; "$LN" -s "$FX/payload" "$dest/rootimg.cpio.xz"; }; [ -z "$sleeper" ] || kill "$sleeper" 2>/dev/null; exit 0' TERM
mode=$(cat "$FX/uftpd.mode" 2>/dev/null || echo deliver)
server=C0000201
case "$mode" in
exit) echo 'Error binding to interface: the receiver failed' >&2; exit 3 ;;
delayed:*) sleep "${mode#delayed:}"; mode=deliver ;;
stale) server=0A0A0A0A ;;
esac
case "$mode" in
deliver|stale|link|swap)
    printf 'CONNECT;2026/10/07-21:05:38;%s;438BAE90;192.0.2.1;mn\n' "$server" >>"$status"
    cp "$FX/payload" "$temp/rootimg.cpio.xz"
    printf 'RESULT;2026/10/07-21:05:39;%s;438BAE90;rootimg.cpio.xz;293KB;copied\n' "$server" >>"$status"
    if [ "$mode" = link ]; then
        rm "$temp/rootimg.cpio.xz"
        "$LN" -s "$FX/payload" "$dest/rootimg.cpio.xz"
    else
        mv "$temp/rootimg.cpio.xz" "$dest/rootimg.cpio.xz"
    fi
    ;;
esac
while :; do
    sleep 1 &
    sleeper=$!
    wait "$sleeper"
done
SH
    chmod +x "$FX/bin/"*
    mkdir "$FX/tools"
    # The initramfs has no tail or head.
    for tool in sh cat cp mv rm mkdir sleep kill; do
        path=$(PATH=/usr/bin:/bin command -v "$tool") || skip "$tool is required"
        ln -s "$path" "$FX/tools/$tool"
    done
    LN=$(PATH=/usr/bin:/bin command -v ln) || skip 'ln is required'
    export LN
    PATH="$FX/bin:$PATH"
    export XCAT_UFTP_ATTEMPTS=1 XCAT_UFTP_GRACE=2 XCAT_UFTP_POLL=1 XCAT_UFTP_STOP_WAIT=3
    . "$(repo_path xCAT-server/share/xcat/netboot/imgutils/xcat-rootimg-fetch.sh)"
}

fetch()
{
    PATH="$FX/bin:$FX/tools" xcat_uftp_rootimg "${1:-$URL}" "$FX/root/$NAME" "$FX/sums" "${2-1045}" "${3-$FP}"
}

# xcatroot names the image file relative to its working directory.
fetch_relative()
{
    (cd "$FX/root" && PATH="$FX/bin:$FX/tools" xcat_uftp_rootimg "$URL" "$NAME" "$FX/sums" 1045 "$FP")
}

ack()
{
    printf '%s\n' status=queued job=0123456789abcdef "file=$NAME" size=300000 port=1044 \
        mcast=230.4.4.1 server_id=0xC0000201 "server_ip=$SERVER" client_ip=192.0.2.50 "$@" >"$FX/ack"
}

refute_grep()
{
    if grep -q -- "$1" "$2" 2>/dev/null; then
        echo "unexpected '$1' in $2"
        return 1
    fi
}

no_leftovers()
{
    [ -z "$(find "$FX/root" -name '.xcat-uftp*')" ]
    if [ -r "$FX/receiver.pid" ] && kill -0 "$(cat "$FX/receiver.pid")" 2>/dev/null; then
        echo 'the receiver is still running'
        return 1
    fi
    if pgrep -f "$FX/bin/uftpd" >/dev/null; then
        echo 'a receiver process survived'
        return 1
    fi
}

received()
{
    cmp "$FX/payload" "$FX/root/$NAME"
}

not_received()
{
    [ ! -e "$FX/root/$NAME" ]
}

@test 'listener URLs replace only the authority port and keep the scheme' {
    run xcat_uftp_url "$URL" 1045 "$SHA"
    [ "$output" = "http://$SERVER:1045/xcat-uftp/v1/transfer/$SHA/install/netboot/rhels9/x86_64/compute/$NAME" ]
    run xcat_uftp_url http://10.80.0.80/install/x80/$NAME 1045 "$SHA"
    [ "$output" = "http://10.80.0.80:1045/xcat-uftp/v1/transfer/$SHA/install/x80/$NAME" ]
    run xcat_uftp_url http://mn.cluster:8080/install/img/$NAME 2045 "$SHA"
    [ "$output" = "http://mn.cluster:2045/xcat-uftp/v1/transfer/$SHA/install/img/$NAME" ]
    run xcat_uftp_url 'http://[2001:db8::1]:80/install/img/rootimg.sfs' 1045 "$SHA"
    [ "$output" = "http://[2001:db8::1]:1045/xcat-uftp/v1/transfer/$SHA/install/img/rootimg.sfs" ]
    run xcat_uftp_url 'http://[2001:db8::1]/install/img/rootimg.sfs' 1045 "$SHA"
    [ "$output" = "http://[2001:db8::1]:1045/xcat-uftp/v1/transfer/$SHA/install/img/rootimg.sfs" ]
    run xcat_uftp_url https://mn/install/img/$NAME 1045 "$SHA"
    [ "$output" = "https://mn:1045/xcat-uftp/v1/transfer/$SHA/install/img/$NAME" ]
}

@test 'implicit ports follow the scheme' {
    xcat_url_parse http://mn/install/x
    [ "$XCAT_URL_PORT" = 80 ] && [ "$XCAT_URL_PATH" = /install/x ]
    xcat_url_parse https://mn/install/x
    [ "$XCAT_URL_PORT" = 443 ] && [ "$XCAT_URL_SCHEME" = https ]
    xcat_url_parse 'http://[fe80::1]:8080'
    [ "$XCAT_URL_HOST" = '[fe80::1]' ] && [ "$XCAT_URL_PORT" = 8080 ] && [ "$XCAT_URL_PATH" = / ]
}

@test 'malformed or ambiguous image URLs are refused' {
    for bad in ftp://mn/install/x/$NAME http://user@mn/install/$NAME http://2001:db8::1/install/$NAME \
        http://mn:0/install/$NAME http://mn:99999/install/$NAME http://mn:8a/install/$NAME \
        http://mn/install/../etc/$NAME http://mn/install/./$NAME http://mn/install/.uftp/$NAME \
        "http://mn/install/$NAME?x=1" http://mn/install/%2e%2e/$NAME 'http://[zz::1]/install/x' \
        'http://[2001:db8::1/install/x' http:///install/x; do
        if xcat_uftp_url "$bad" 1045 "$SHA" >/dev/null; then
            echo "accepted $bad"
            return 1
        fi
    done
}

@test 'the request names the first checksum that the checksum file lists for the image' {
    other=$(printf '%064d' 7)
    printf '%s  rootimg.cpio.gz\n%s *%s\n%s  %s\n' "$other" "$SHA" "$NAME" "$other" "$NAME" >"$FX/sums"
    run xcat_listed_sha256 "$FX/sums" "$NAME"
    [ "$status" -eq 0 ] && [ "$output" = "$SHA" ]
    printf 'not-a-digest  %s\n%s  %s' "$NAME" "$SHA" "$NAME" >"$FX/sums"
    run xcat_listed_sha256 "$FX/sums" "$NAME"
    [ "$status" -eq 0 ] && [ "$output" = "$SHA" ]
    for bad in "$(printf '%s  rootimg.cpio.gz' "$SHA")" "$(printf '%s  %s' "${SHA%?}" "$NAME")" \
        "$(printf '%s  %s' "$(printf '%s' "$SHA" | tr a-f A-F)" "$NAME")" '<html>busy</html>'; do
        printf '%s\n' "$bad" >"$FX/sums"
        if xcat_listed_sha256 "$FX/sums" "$NAME" >/dev/null; then
            echo "accepted $bad"
            return 1
        fi
    done
    run xcat_listed_sha256 "$FX/missing" "$NAME"
    [ "$status" -eq 1 ] && [ -z "$output" ]
}

@test 'a checksum file without the image is never sent to the listener' {
    ack start_in=0 timeout=5
    printf '%064d  rootimg.cpio.gz\n' 0 >"$FX/sums"
    run fetch
    [ "$status" -eq 1 ]
    not_received
    grep -q "lists no SHA-256 checksum for $NAME" "$FX/log"
    [ ! -e "$FX/curl.log" ]
}

@test 'listener replies are validated and the batch delay defaults to zero' {
    ack start_in=7 timeout=60
    xcat_uftp_read_ack "$FX/ack" "$NAME"
    [ "$XCAT_ACK_START_IN" = 7 ] && [ "$XCAT_ACK_TIMEOUT" = 60 ]
    ack timeout=60
    xcat_uftp_read_ack "$FX/ack" "$NAME"
    [ "$XCAT_ACK_START_IN" = 0 ]
    ack start_in=0 timeout=60
    xcat_uftp_read_ack "$FX/ack" "$NAME"
    [ "$XCAT_ACK_START_IN" = 0 ]
    for bad in 'start_in=abc timeout=60' 'start_in=-1 timeout=60' 'start_in=3601 timeout=60' \
        'timeout=0' 'start_in=00 timeout=60' 'timeout=60 file=rootimg.cpio.gz' \
        'timeout=60 server_id=0xc0000201' 'timeout=60 job=xyz' 'timeout=60 port=70000' \
        'timeout=60 client_ip=192.0.2.256' 'timeout=60 status=refused'; do
        ack $bad
        if xcat_uftp_read_ack "$FX/ack" "$NAME"; then
            echo "accepted $bad"
            return 1
        fi
    done
    printf 'status=queued\nnot a key value\n' >"$FX/ack"
    if xcat_uftp_read_ack "$FX/ack" "$NAME"; then
        echo 'accepted a line without a key'
        return 1
    fi
}

@test 'a UFTP transfer puts the image in place' {
    ack start_in=0 timeout=5
    run fetch
    [ "$status" -eq 0 ]
    received
    no_leftovers
    grep -q "Received $NAME over UFTP" "$FX/log"
    [ "$(cat "$FX/curl.log")" = "http://$SERVER:1045/xcat-uftp/v1/transfer/$SHA/install/netboot/rhels9/x86_64/compute/$NAME" ]
    [ "$(cat "$FX/servers")" = "0xC0000201|$SERVER|0|$FP" ]
    args=" $(cat "$FX/uftpd.args") "
    for option in -d -q -E '-p 1044' '-M 230.4.4.1' '-I 192.0.2.50'; do
        case "$args" in
        *" $option "*) ;;
        *) echo "missing $option"; return 1 ;;
        esac
    done
    grep -q -- "-D $FX/root/.xcat-uftp.[0-9]*.1/dest -T $FX/root/.xcat-uftp.[0-9]*.1/tmp" "$FX/uftpd.args"
    grep -q terminated "$FX/uftpd.events"
}

@test 'an image file named relative to the working directory gets absolute receiver directories' {
    ack start_in=0 timeout=5
    run fetch_relative
    [ "$status" -eq 0 ]
    received
    no_leftovers
    grep -q -- "-D $FX/root/.xcat-uftp.[0-9]*.1/dest -T $FX/root/.xcat-uftp.[0-9]*.1/tmp" "$FX/uftpd.args"
}

@test 'completion lines from another server or a stale log do not count' {
    ack start_in=0 timeout=1
    echo stale >"$FX/uftpd.mode"
    mkdir -p "$FX/root/tmp"
    printf 'File transfer complete\nRESULT;x;C0000201;1;%s;1KB;copied\n' "$NAME" >"$FX/root/tmp/uftpd.log"
    run fetch
    [ "$status" -eq 1 ]
    grep -q 'did not finish in 3s' "$FX/log"
    not_received
    no_leftovers
}

@test 'a symbolic link that the receiver delivers is never put in place of the image' {
    ack start_in=0 timeout=5
    echo link >"$FX/uftpd.mode"
    run fetch
    [ "$status" -eq 1 ]
    [ ! -L "$FX/root/$NAME" ]
    not_received
    no_leftovers
    grep -q "$NAME from UFTP is not a regular file" "$FX/log"
}

@test 'a symbolic link that replaces the image while the receiver stops is never put in place' {
    ack start_in=0 timeout=5
    echo swap >"$FX/uftpd.mode"
    run fetch
    [ "$status" -eq 1 ]
    [ ! -L "$FX/root/$NAME" ]
    not_received
    no_leftovers
    grep -q terminated "$FX/uftpd.events"
    grep -q "$NAME from UFTP is not a regular file" "$FX/log"
}

@test 'a missing receiver sends no request' {
    rm "$FX/bin/uftpd"
    ack start_in=0 timeout=5
    run fetch
    [ "$status" -eq 1 ]
    not_received
    grep -q 'uftpd is not in the initramfs' "$FX/log"
    [ ! -e "$FX/curl.log" ]
}

@test 'an unavailable listener is asked once for each attempt' {
    XCAT_UFTP_ATTEMPTS=2
    run fetch
    [ "$status" -eq 1 ]
    not_received
    no_leftovers
    grep -q 'did not accept the request' "$FX/log"
    [ "$(grep -c /xcat-uftp/v1/transfer/ "$FX/curl.log")" -eq 2 ]
}

@test 'a sender failure reported by the server ends the wait early' {
    ack start_in=0 timeout=60
    echo hang >"$FX/uftpd.mode"
    printf 'state=failed\ntimeout=60\nreason=uftp exited with status 7\n' >"$FX/job"
    start=$(date +%s)
    run fetch
    [ "$status" -eq 1 ]
    [ $(( $(date +%s) - start )) -lt 20 ]
    grep -q 'failed on the server: uftp exited with status 7' "$FX/log"
    not_received
    no_leftovers
}

@test 'a stalled status request cannot extend the transfer deadline' {
    ack start_in=0 timeout=2
    echo hang >"$FX/uftpd.mode"
    echo 30 >"$FX/job_delay"
    printf 'state=running\ntimeout=2\n' >"$FX/job"
    start=$(date +%s)
    run fetch
    [ "$status" -eq 1 ]
    [ $(( $(date +%s) - start )) -lt 12 ]
    grep -q 'did not finish in 4s' "$FX/log"
    not_received
    no_leftovers
}

@test 'a trickling wget status reply cannot extend the transfer deadline' {
    rm "$FX/bin/curl"
    cat >"$FX/bin/wget" <<'SH'
#!/bin/sh
out=
for arg do
    if [ "$prev" = -O ]; then out=$arg; fi
    case "$arg" in *://*) url=$arg ;; esac
    prev=$arg
done
printf '%s\n' "$url" >>"$FX/curl.log"
case "$url" in
*/xcat-uftp/v1/transfer/*) cp "$FX/ack" "$out" ;;
*/xcat-uftp/v1/job/*)
    while :; do
        printf x >>"$out"
        sleep 1
    done
    ;;
*) exit 8 ;;
esac
SH
    chmod +x "$FX/bin/wget"
    ack start_in=0 timeout=2
    echo hang >"$FX/uftpd.mode"
    start=$(date +%s)
    run fetch
    [ "$status" -eq 1 ]
    [ $(( $(date +%s) - start )) -lt 15 ]
    grep -q 'did not finish in 4s' "$FX/log"
    not_received
    no_leftovers
    if pgrep -f "$FX/bin/wget" >/dev/null; then
        echo 'a wget request survived'
        return 1
    fi
}

@test 'a receiver that exits is detected' {
    ack start_in=0 timeout=60
    echo exit >"$FX/uftpd.mode"
    run fetch
    [ "$status" -eq 1 ]
    grep -q 'UFTP receiver stopped: .*the receiver failed' "$FX/log"
    not_received
    no_leftovers
}

@test 'a transfer that does not finish in time stops its receiver' {
    ack start_in=0 timeout=1
    echo hang >"$FX/uftpd.mode"
    run fetch
    [ "$status" -eq 1 ]
    grep -q 'did not finish in 3s' "$FX/log"
    grep -q terminated "$FX/uftpd.events"
    not_received
    no_leftovers
}

@test 'a pending job extends the wait within the server deadline' {
    ack start_in=0 timeout=3
    echo delayed:6 >"$FX/uftpd.mode"
    printf 'state=pending\nstart_in=3\ntimeout=3\n' >"$FX/job"
    run fetch
    [ "$status" -eq 0 ]
    grep -q "Received $NAME over UFTP" "$FX/log"
    received
}

@test 'an interrupted transfer stops its receiver and removes its files' {
    ack start_in=0 timeout=60
    echo hang >"$FX/uftpd.mode"
    helper=$(repo_path xCAT-server/share/xcat/netboot/imgutils/xcat-rootimg-fetch.sh)
    PATH="$FX/bin:$FX/tools" sh -c '. "$1"; xcat_uftp_rootimg "$2" "$3" "$4" 1045 "$5"' fetch "$helper" "$URL" \
        "$FX/root/$NAME" "$FX/sums" "$FP" >"$FX/interrupted.out" 2>&1 &
    fetcher=$!
    for _ in $(seq 50); do
        [ -s "$FX/receiver.pid" ] && break
        sleep 0.1
    done
    [ -s "$FX/receiver.pid" ]
    sleep 1
    kill -TERM "$fetcher"
    wait "$fetcher" || rc=$?
    [ "${rc:-0}" -eq 130 ]
    grep -q 'interrupted' "$FX/log"
    not_received
    no_leftovers
}

@test 'an HTTPS image URL is never sent to the listener over HTTP' {
    ack start_in=0 timeout=5
    run fetch "https://mn/install/netboot/img/$NAME"
    [ "$status" -eq 1 ]
    not_received
    [ ! -e "$FX/curl.log" ]
    grep -q 'UFTP is used only with http image URLs' "$FX/log"
}

@test 'malformed kernel arguments send no request' {
    ack start_in=0 timeout=5
    for args in '70000 '"$FP" "1045 ${FP%:*}" '1045 31:94:09:9d:B1:24:3F:32:C0:B9:1A:BB:AC:F4:74:2B:80:F9:77:B2' "0 $FP"; do
        set -- $args
        run fetch "$URL" "$1" "$2"
        [ "$status" -eq 1 ]
    done
    run fetch "$URL" '' "$FP"
    [ "$status" -eq 1 ]
    not_received
    [ "$(grep -c 'Ignoring malformed xcat.uftp' "$FX/log")" -eq 5 ]
    [ ! -e "$FX/curl.log" ]
}
