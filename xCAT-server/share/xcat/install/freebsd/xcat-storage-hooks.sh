xcat_storage_call()
{
    /usr/local/libexec/xcat-storage "$XCAT_STORAGE_WORK" "$@"
}

xcat_storage_step()
{
    if [ -z "${XCAT_STORAGE_WORK:-}" ]; then
        "$@"
        return
    fi
    xcat_storage_call step-before "$@" || exit 1
    "$@" || exit 1
    xcat_storage_call step-after "$@" || exit 1
}

xcat_storage_eval()
{
    if [ -z "${XCAT_STORAGE_WORK:-}" ]; then
        f_eval_catch "$@"
        return
    fi
    local xcat_action xcat_result=0
    xcat_action=$(xcat_storage_call before "$@") || exit 1
    case "$xcat_action" in
        run) f_eval_catch "$@" || xcat_result=$? ;;
        skip) ;;
        *) exit 1 ;;
    esac
    [ "$xcat_result" -eq 0 ] || exit 1
    xcat_storage_call after "$@" || exit 1
}

xcat_storage_boot()
{
    if [ -z "${XCAT_STORAGE_WORK:-}" ]; then
        "$@"
        return
    fi
    xcat_storage_call boot-before "$xcat_storage_esp" "$@" || exit 1
    "$@" || exit 1
    xcat_storage_call boot-after "$xcat_storage_esp" "$@" || exit 1
}
