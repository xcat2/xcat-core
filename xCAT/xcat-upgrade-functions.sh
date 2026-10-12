xcat_run_upgrade()
{
    mkdir -p /var/log/xcat
    date >> /var/log/xcat/upgrade.log
    xcatupgradeout=$(mktemp /tmp/xcat-upgrade.XXXXXX)
    "$@" > "$xcatupgradeout" 2>&1
    cat "$xcatupgradeout" >> /var/log/xcat/upgrade.log

    # Only the current run can trigger a warning; the log retains earlier runs.
    if grep -q "command returned error code" "$xcatupgradeout"; then
        echo "WARNING: mknb did not complete, so the Genesis netboot image may be missing or out of date."
        echo "         See /var/log/xcat/upgrade.log, then rerun 'mknb <arch>' once the cause is resolved."
    fi
    rm -f "$xcatupgradeout"
}
