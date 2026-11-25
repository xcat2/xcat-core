xcat_disable_image_selinux()
{
    if [ -f "$1/etc/selinux/config" ]; then
        sed -i 's/^\([[:blank:]]*SELINUX=\)\(enforcing\|permissive\)\([[:blank:]]*\(#.*\)\{0,1\}\)$/\1disabled\3/' "$1/etc/selinux/config"
    fi
}

xcat_disable_image_firewalld()
{
    for xcat_firewalld_entry in \
        "$1/etc/systemd/system/multi-user.target.wants/firewalld.service" \
        "$1/etc/systemd/system/dbus-org.fedoraproject.FirewallD1.service"
    do
        if [ -f "$xcat_firewalld_entry" ] || [ -L "$xcat_firewalld_entry" ]; then
            rm -f "$xcat_firewalld_entry"
        fi
    done
}
