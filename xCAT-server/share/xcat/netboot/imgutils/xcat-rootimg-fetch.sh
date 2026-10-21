# Receive a stateless root image over UFTP multicast.  xcatroot sources this
# file when nodeset passes xcat.uftp=, and calls xcat_uftp_rootimg.  The file
# is not checked here: xcatroot checks it like an HTTP download.

: "${XCAT_UFTP_ATTEMPTS:=2}"
: "${XCAT_UFTP_GRACE:=30}"
: "${XCAT_UFTP_POLL:=5}"
: "${XCAT_UFTP_REQUEST_TIMEOUT:=15}"
: "${XCAT_UFTP_STOP_WAIT:=10}"

xcat_fetch_log() {
    if command -v logger >/dev/null 2>&1; then
        # SYSLOGHOST is either empty or "-n <server>" and must split.
        logger $SYSLOGHOST -t "${log_label:-xcat.deployment}" -p "local4.$1" "$2"
    fi
    echo "$2" >&2
}

xcat_uint_ok() {
    case "$1" in
    0) return 0 ;;
    ''|0*|*[!0-9]*) return 1 ;;
    esac
    [ "${#1}" -le 9 ] && [ "$1" -le "$2" ]
}

xcat_port_ok() {
    xcat_uint_ok "$1" 65535 && [ "$1" -gt 0 ]
}

xcat_ipv4_ok() {
    case "$1" in
    ''|*[!0-9.]*|.*|*.|*..*) return 1 ;;
    esac
    _xf_ifs=$IFS
    IFS=.
    set -- $1
    IFS=$_xf_ifs
    [ "$#" -eq 4 ] || return 1
    for _xf_octet do
        xcat_uint_ok "$_xf_octet" 255 || return 1
    done
}

xcat_sha256_ok() {
    case "$1" in
    *[!0-9a-f]*) return 1 ;;
    esac
    [ "${#1}" -eq 64 ]
}

xcat_fingerprint_ok() {
    case "$1" in
    ??:??:??:??:??:??:??:??:??:??:??:??:??:??:??:??:??:??:??:??) ;;
    *) return 1 ;;
    esac
    case "$1" in
    *[!0-9A-F:]*) return 1 ;;
    esac
}

# Print the first SHA-256 checksum that the sha256sum file $1 lists for the name $2.
xcat_listed_sha256() {
    [ -r "$1" ] || return 1
    while read -r _xf_sum _xf_name || [ -n "$_xf_sum" ]; do
        if [ "${_xf_name#\*}" = "$2" ] && xcat_sha256_ok "$_xf_sum"; then
            printf '%s\n' "$_xf_sum"
            return 0
        fi
    done < "$1"
    return 1
}

# Split an http(s) URL into XCAT_URL_SCHEME, XCAT_URL_HOST (IPv6 keeps its
# brackets), XCAT_URL_PORT (the scheme default when absent) and XCAT_URL_PATH.
xcat_url_parse() {
    case "$1" in
    http://*) XCAT_URL_SCHEME=http; _xf_rest=${1#http://} ;;
    https://*) XCAT_URL_SCHEME=https; _xf_rest=${1#https://} ;;
    *) return 1 ;;
    esac
    case "$_xf_rest" in
    */*) _xf_authority=${_xf_rest%%/*}; XCAT_URL_PATH=/${_xf_rest#*/} ;;
    *) _xf_authority=$_xf_rest; XCAT_URL_PATH=/ ;;
    esac
    case "$_xf_authority" in
    *@*) return 1 ;;
    \[*\]:*) XCAT_URL_HOST="${_xf_authority%%]:*}]"; XCAT_URL_PORT=${_xf_authority##*]:} ;;
    \[*\]) XCAT_URL_HOST=$_xf_authority; XCAT_URL_PORT= ;;
    *\[*|*\]*|*:*:*) return 1 ;;
    *:*) XCAT_URL_HOST=${_xf_authority%:*}; XCAT_URL_PORT=${_xf_authority##*:} ;;
    *) XCAT_URL_HOST=$_xf_authority; XCAT_URL_PORT= ;;
    esac
    case "$XCAT_URL_HOST" in
    ''|\[\]) return 1 ;;
    \[*\])
        _xf_inner=${XCAT_URL_HOST#\[}
        _xf_inner=${_xf_inner%\]}
        case "$_xf_inner" in
        *[!0-9A-Fa-f:.]*|*:*:*:*:*:*:*:*:*) return 1 ;;
        *:*) ;;
        *) return 1 ;;
        esac
        ;;
    *[!A-Za-z0-9.-]*|-*|.*) return 1 ;;
    esac
    if [ -z "$XCAT_URL_PORT" ]; then
        if [ "$XCAT_URL_SCHEME" = https ]; then
            XCAT_URL_PORT=443
        else
            XCAT_URL_PORT=80
        fi
    fi
    xcat_port_ok "$XCAT_URL_PORT" || return 1
    case "$XCAT_URL_PATH" in
    *[?#%]*) return 1 ;;
    esac
}

# Print the image path the listener expects: repeated slashes collapsed and
# every segment limited to the characters packimage accepts.
xcat_image_path() {
    _xf_path=$1
    while :; do
        case "$_xf_path" in
        *//*) _xf_path=${_xf_path%%//*}/${_xf_path#*//} ;;
        *) break ;;
        esac
    done
    case "$_xf_path" in
    /|*/|[!/]*) return 1 ;;
    esac
    _xf_ifs=$IFS
    IFS=/
    set -f
    set -- ${_xf_path#/}
    set +f
    IFS=$_xf_ifs
    for _xf_segment do
        case "$_xf_segment" in
        ''|.*|*[!A-Za-z0-9._+-]*) return 1 ;;
        esac
    done
    printf '%s\n' "$_xf_path"
}

# Print the transfer request URL for an image URL: same scheme and host,
# the listener port, and the image path.
xcat_uftp_url() {
    xcat_url_parse "$1" || return 1
    _xf_image=$(xcat_image_path "$XCAT_URL_PATH") || return 1
    printf '%s://%s:%s/xcat-uftp/v1/transfer/%s%s\n' \
        "$XCAT_URL_SCHEME" "$XCAT_URL_HOST" "$2" "$3" "$_xf_image"
}

xcat_http_get() {
    if command -v curl >/dev/null 2>&1; then
        curl --fail --silent --show-error --max-time "$3" -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        # wget -T limits idle time only, so a watchdog limits the whole request.
        wget -q -T "$3" -t 1 -O "$2" "$1" &
        _xf_get=$!
        (
            _xf_left=$3
            while [ "$_xf_left" -gt 0 ]; do
                sleep 1
                kill -0 "$_xf_get" 2>/dev/null || exit 0
                _xf_left=$((_xf_left - 1))
            done
            kill -KILL "$_xf_get" 2>/dev/null
        ) &
        _xf_dog=$!
        wait "$_xf_get"
        _xf_rc=$?
        kill "$_xf_dog" 2>/dev/null
        wait "$_xf_dog" 2>/dev/null
        return "$_xf_rc"
    else
        return 127
    fi
}

xcat_uftp_read_ack() {
    XCAT_ACK_STATUS='' XCAT_ACK_JOB='' XCAT_ACK_FILE='' XCAT_ACK_PORT='' XCAT_ACK_MCAST=''
    XCAT_ACK_SERVER_ID='' XCAT_ACK_SERVER_IP='' XCAT_ACK_CLIENT_IP=''
    XCAT_ACK_START_IN='' XCAT_ACK_TIMEOUT=''
    while IFS= read -r _xf_line || [ -n "$_xf_line" ]; do
        _xf_key=${_xf_line%%=*}
        _xf_value=${_xf_line#*=}
        [ "$_xf_key" != "$_xf_line" ] || return 1
        case "$_xf_key" in
        status) XCAT_ACK_STATUS=$_xf_value ;;
        job) XCAT_ACK_JOB=$_xf_value ;;
        file) XCAT_ACK_FILE=$_xf_value ;;
        port) XCAT_ACK_PORT=$_xf_value ;;
        mcast) XCAT_ACK_MCAST=$_xf_value ;;
        server_id) XCAT_ACK_SERVER_ID=$_xf_value ;;
        server_ip) XCAT_ACK_SERVER_IP=$_xf_value ;;
        client_ip) XCAT_ACK_CLIENT_IP=$_xf_value ;;
        start_in) XCAT_ACK_START_IN=$_xf_value ;;
        timeout) XCAT_ACK_TIMEOUT=$_xf_value ;;
        esac
    done < "$1"
    [ "$XCAT_ACK_STATUS" = queued ] || return 1
    case "$XCAT_ACK_JOB" in
    ????????????????) ;;
    *) return 1 ;;
    esac
    case "$XCAT_ACK_JOB" in
    *[!0-9a-f]*) return 1 ;;
    esac
    [ "$XCAT_ACK_FILE" = "$2" ] || return 1
    xcat_port_ok "$XCAT_ACK_PORT" || return 1
    xcat_ipv4_ok "$XCAT_ACK_MCAST" || return 1
    xcat_ipv4_ok "$XCAT_ACK_SERVER_IP" || return 1
    xcat_ipv4_ok "$XCAT_ACK_CLIENT_IP" || return 1
    case "$XCAT_ACK_SERVER_ID" in
    0x????????) ;;
    *) return 1 ;;
    esac
    case "${XCAT_ACK_SERVER_ID#0x}" in
    *[!0-9A-F]*) return 1 ;;
    esac
    : "${XCAT_ACK_START_IN:=0}"
    xcat_uint_ok "$XCAT_ACK_START_IN" 3600 || return 1
    xcat_uint_ok "$XCAT_ACK_TIMEOUT" 86400 && [ "$XCAT_ACK_TIMEOUT" -gt 0 ]
}

# Print a monotonic time in whole seconds.
xcat_now() {
    if [ -r /proc/uptime ]; then
        read -r _xf_uptime _xf_idle < /proc/uptime
        echo "${_xf_uptime%%.*}"
    else
        date +%s
    fi
}

# Print the last three lines of the file $1. The initramfs has no tail.
xcat_last_lines() {
    _xf_l1= _xf_l2= _xf_l3=
    while IFS= read -r _xf_line || [ -n "$_xf_line" ]; do
        _xf_l1=$_xf_l2 _xf_l2=$_xf_l3 _xf_l3=$_xf_line
    done < "$1"
    printf '%s %s %s' "$_xf_l1" "$_xf_l2" "$_xf_l3"
}

xcat_child_running() {
    kill -0 "$1" 2>/dev/null || return 1
    if [ -r "/proc/$1/stat" ]; then
        read -r _xf_pid _xf_comm _xf_state _xf_rest < "/proc/$1/stat" || return 1
        [ "$_xf_state" != Z ] || return 1
    fi
    return 0
}

xcat_uftp_start_receiver() {
    printf '%s|%s|0|%s\n' "$XCAT_ACK_SERVER_ID" "$XCAT_ACK_SERVER_IP" "$XCAT_FETCH_FP" \
        > "$1/servers" || return 1
    "$XCAT_UFTPD" -d -q -E -x 2 -p "$XCAT_ACK_PORT" -M "$XCAT_ACK_MCAST" \
        -I "$XCAT_ACK_CLIENT_IP" -S "$1/servers" -D "$1/dest" -T "$1/tmp" \
        -F "$1/status" </dev/null >"$1/uftpd.log" 2>&1 &
    XCAT_UFTP_PID=$!
}

xcat_uftp_stop_receiver() {
    _xf_receiver=$XCAT_UFTP_PID
    [ -n "$_xf_receiver" ] || return 0
    XCAT_UFTP_PID=
    kill -TERM "$_xf_receiver" 2>/dev/null
    (
        _xf_waited=0
        while [ "$_xf_waited" -lt "$XCAT_UFTP_STOP_WAIT" ]; do
            kill -0 "$_xf_receiver" 2>/dev/null || exit 0
            sleep 1
            _xf_waited=$((_xf_waited + 1))
        done
        kill -KILL "$_xf_receiver" 2>/dev/null
    ) &
    _xf_watchdog=$!
    wait "$_xf_receiver" 2>/dev/null
    wait "$_xf_watchdog" 2>/dev/null
    return 0
}

xcat_uftp_cleanup() {
    xcat_uftp_stop_receiver
    if [ -n "$XCAT_FETCH_STAGING" ]; then
        rm -rf "$XCAT_FETCH_STAGING"
        XCAT_FETCH_STAGING=
    fi
}

# Succeed when this attempt's receiver reported the expected file as copied
# in a session it opened with the expected server, and the file was moved
# out of the temporary directory.
xcat_uftp_completed() {
    [ -f "$1/dest/$XCAT_FETCH_FILE" ] && [ -r "$1/status" ] || return 1
    _xf_sid=${XCAT_ACK_SERVER_ID#0x}
    _xf_groups=
    while IFS=';' read -r _xf_kind _xf_stamp _xf_server _xf_group _xf_name _xf_size _xf_result; do
        [ "$_xf_server" = "$_xf_sid" ] || continue
        case "$_xf_kind" in
        CONNECT) _xf_groups="$_xf_groups $_xf_group " ;;
        RESULT)
            [ "$_xf_name" = "$XCAT_FETCH_FILE" ] && [ "$_xf_result" = copied ] || continue
            case "$_xf_groups" in
            *" $_xf_group "*) return 0 ;;
            esac
            ;;
        esac
    done < "$1/status"
    return 1
}

xcat_uftp_job_state() {
    XCAT_JOB_STATE='' XCAT_JOB_START_IN='' XCAT_JOB_REASON=''
    xcat_http_get "$XCAT_FETCH_JOB_URL" "$1/job" "$2" || return 1
    while IFS= read -r _xf_line || [ -n "$_xf_line" ]; do
        case "$_xf_line" in
        state=*) XCAT_JOB_STATE=${_xf_line#state=} ;;
        start_in=*) XCAT_JOB_START_IN=${_xf_line#start_in=} ;;
        reason=*) XCAT_JOB_REASON=${_xf_line#reason=} ;;
        esac
    done < "$1/job"
    case "$XCAT_JOB_STATE" in
    pending|running|done|failed) ;;
    *) return 1 ;;
    esac
    xcat_uint_ok "${XCAT_JOB_START_IN:-0}" 86400 || XCAT_JOB_START_IN=0
}

xcat_uftp_attempt() {
    _xf_staging=$XCAT_FETCH_DIR.xcat-uftp.$$.$1
    mkdir "$_xf_staging" || return 1
    XCAT_FETCH_STAGING=$_xf_staging
    mkdir "$XCAT_FETCH_STAGING/dest" "$XCAT_FETCH_STAGING/tmp" || return 1
    if ! xcat_http_get "$XCAT_FETCH_LISTENER" "$XCAT_FETCH_STAGING/ack" "$XCAT_UFTP_REQUEST_TIMEOUT"; then
        xcat_fetch_log warning "UFTP listener did not accept the request $XCAT_FETCH_LISTENER"
        return 1
    fi
    if ! xcat_uftp_read_ack "$XCAT_FETCH_STAGING/ack" "$XCAT_FETCH_FILE"; then
        xcat_fetch_log warning "UFTP listener sent an invalid reply"
        return 1
    fi
    XCAT_FETCH_JOB_URL="$XCAT_URL_SCHEME://$XCAT_URL_HOST:$XCAT_FETCH_PORT/xcat-uftp/v1/job/$XCAT_ACK_JOB"
    xcat_uftp_start_receiver "$XCAT_FETCH_STAGING" || return 1
    xcat_fetch_log info "UFTP transfer $XCAT_ACK_JOB queued; sending starts in ${XCAT_ACK_START_IN}s"
    _xf_start=$(xcat_now)
    _xf_deadline=$((_xf_start + XCAT_ACK_START_IN + XCAT_ACK_TIMEOUT + XCAT_UFTP_GRACE))
    _xf_cap=$((_xf_deadline + XCAT_ACK_TIMEOUT))
    _xf_next_poll=$((_xf_start + XCAT_UFTP_POLL))
    _xf_done_at=
    while _xf_now=$(xcat_now) && [ "$_xf_now" -lt "$_xf_deadline" ]; do
        if xcat_uftp_completed "$XCAT_FETCH_STAGING"; then
            xcat_uftp_stop_receiver
            # Check the type only after the receiver stops: a batch member can deliver a symbolic link.
            _xf_file=$XCAT_FETCH_STAGING/dest/$XCAT_FETCH_FILE
            if [ -f "$_xf_file" ] && [ ! -L "$_xf_file" ]; then
                return 0
            fi
            xcat_fetch_log warning "$XCAT_FETCH_FILE from UFTP is not a regular file"
            return 1
        fi
        if ! xcat_child_running "$XCAT_UFTP_PID"; then
            xcat_fetch_log warning "UFTP receiver stopped: $(xcat_last_lines "$XCAT_FETCH_STAGING/uftpd.log" 2>/dev/null)"
            return 1
        fi
        if [ "$_xf_now" -ge "$_xf_next_poll" ]; then
            _xf_next_poll=$((_xf_now + XCAT_UFTP_POLL))
            _xf_budget=$((_xf_deadline - _xf_now))
            [ "$_xf_budget" -le "$XCAT_UFTP_REQUEST_TIMEOUT" ] || _xf_budget=$XCAT_UFTP_REQUEST_TIMEOUT
            if xcat_uftp_job_state "$XCAT_FETCH_STAGING" "$_xf_budget"; then
                case "$XCAT_JOB_STATE" in
                failed)
                    xcat_fetch_log warning "UFTP transfer $XCAT_ACK_JOB failed on the server: $XCAT_JOB_REASON"
                    return 1
                    ;;
                done)
                    : "${_xf_done_at:=$_xf_now}"
                    if [ $((_xf_now - _xf_done_at)) -ge "$XCAT_UFTP_GRACE" ]; then
                        xcat_fetch_log warning "UFTP transfer $XCAT_ACK_JOB ended without this node"
                        return 1
                    fi
                    ;;
                pending)
                    _xf_wanted=$((_xf_now + XCAT_JOB_START_IN + XCAT_ACK_TIMEOUT + XCAT_UFTP_GRACE))
                    [ "$_xf_wanted" -le "$_xf_deadline" ] || _xf_deadline=$_xf_wanted
                    [ "$_xf_deadline" -le "$_xf_cap" ] || _xf_deadline=$_xf_cap
                    ;;
                esac
            fi
        fi
        sleep 1
    done
    xcat_fetch_log warning "UFTP transfer $XCAT_ACK_JOB did not finish in $((_xf_deadline - _xf_start))s"
    return 1
}

xcat_fetch_interrupted() {
    xcat_uftp_cleanup
    xcat_fetch_log err "Root image download interrupted"
    exit 130
}

xcat_uftp_usable() {
    if ! xcat_port_ok "$1" || ! xcat_fingerprint_ok "$2"; then
        xcat_fetch_log warning "Ignoring malformed xcat.uftp or xcat.uftpfp kernel arguments"
        return 1
    fi
    if ! xcat_url_parse "$XCAT_FETCH_URL" || [ "$XCAT_URL_SCHEME" != http ]; then
        xcat_fetch_log warning "UFTP is used only with http image URLs"
        return 1
    fi
    XCAT_UFTPD=$(command -v uftpd) || {
        xcat_fetch_log warning "uftpd is not in the initramfs; run genimage with uftp installed in the image"
        return 1
    }
    XCAT_FETCH_LISTENER=$(xcat_uftp_url "$XCAT_FETCH_URL" "$1" "$XCAT_FETCH_SHA256") || {
        xcat_fetch_log warning "Cannot build a UFTP request for $XCAT_FETCH_URL"
        return 1
    }
    XCAT_FETCH_PORT=$1
    XCAT_FETCH_FP=$2
}

# xcat_uftp_rootimg <imgurl> <file> <checksum file> <listener port> <server fingerprint>
# The checksum file is the sha256sum file published with the image, which
# names the archive to the listener.
xcat_uftp_rootimg() {
    XCAT_FETCH_URL=$1
    XCAT_FETCH_FILE=${1##*/}
    # uftpd takes only absolute directories.
    case "$2" in
    /*) XCAT_FETCH_DEST=$2 ;;
    *) XCAT_FETCH_DEST=${PWD%/}/$2 ;;
    esac
    XCAT_FETCH_DIR=${XCAT_FETCH_DEST%/*}/
    XCAT_FETCH_STAGING=
    XCAT_UFTP_PID=
    XCAT_FETCH_SHA256=$(xcat_listed_sha256 "$3" "$XCAT_FETCH_FILE") || {
        xcat_fetch_log warning "$XCAT_FETCH_URL.sha256 lists no SHA-256 checksum for $XCAT_FETCH_FILE"
        return 1
    }
    xcat_uftp_usable "$4" "$5" || return 1
    trap xcat_fetch_interrupted INT TERM HUP
    _xf_attempt=1
    while [ "$_xf_attempt" -le "$XCAT_UFTP_ATTEMPTS" ]; do
        if xcat_uftp_attempt "$_xf_attempt" && mv -f "$XCAT_FETCH_STAGING/dest/$XCAT_FETCH_FILE" "$XCAT_FETCH_DEST"; then
            xcat_uftp_cleanup
            trap - INT TERM HUP
            xcat_fetch_log info "Received $XCAT_FETCH_FILE over UFTP"
            return 0
        fi
        xcat_uftp_cleanup
        _xf_attempt=$((_xf_attempt + 1))
    done
    trap - INT TERM HUP
    return 1
}
