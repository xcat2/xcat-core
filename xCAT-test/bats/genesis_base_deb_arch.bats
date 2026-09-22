#!/usr/bin/env bats
#
# debuild-xcat-genesis-base converts the EL Genesis base rpm to a deb. The rpm name carries the
# Genesis target architecture, and the deb must carry the Debian architecture: ppc64 becomes
# ppc64el, x86_64 becomes amd64. An unmapped architecture leaves the deb named after the rpm and
# makes it break a genesis-scripts package that no repository publishes. The rename also has to
# name the deb it supersedes, or an upgraded ppc node keeps xcat-genesis-base-ppc64 as well.
#
# The script is driven here with alien shadowed by a shell function.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(repo_path 'xCAT-genesis-builder/debuild-xcat-genesis-base')"
    # Fail rather than skip: a checkout without the converter has no deb rename to measure,
    # and a skip there covers nothing while reading green.
    [ -r "$SCRIPT" ]
    export SCRIPT
}

# alien names the deb after the rpm: lower case, and "_" written as "-".
shadow_alien()
{
    alien()
    {
        local rpm="${!#}"
        local name="${rpm##*/}"
        name="${name%.rpm}"
        local dir="${name%%-snap*}"
        local package="${dir%-*}"
        package="${package,,}"
        package="${package//_/-}"

        mkdir -p "${dir}/debian"
        cat >"${dir}/debian/control" <<CONTROL
Source: ${package}
Section: alien
Priority: extra
Maintainer: xCAT <xcat-user@lists.sourceforge.net>

Package: ${package}
Architecture: all
Description: xCAT genesis base
CONTROL
        printf '%s (%s) unstable; urgency=low\n' "${package}" "1.0" \
            >"${dir}/debian/changelog"
        printf '#!/usr/bin/make -f\nbinary:\n\t@true\n' >"${dir}/debian/rules"
        chmod 0755 "${dir}/debian/rules"
    }
}

# Convert one rpm name. Sets SOURCE_DIR to the produced source directory and CONTROL to its
# control file.
convert()
{
    local rpm="$1"
    local work="${BATS_TEST_TMPDIR}/convert"

    rm -rf "$work"
    mkdir -p "$work"
    (
        shadow_alien
        cd "$work" || exit 1
        : >"$rpm"
        source "$SCRIPT" "$rpm" >/dev/null 2>&1
    )

    SOURCE_DIR="$(find "$work" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)"
    [ -n "$SOURCE_DIR" ] || return 1
    CONTROL="$work/$SOURCE_DIR/debian/control"
    [ -f "$CONTROL" ] || return 1
}

@test "the x86_64 rpm becomes the amd64 deb, and replaces the package it supersedes" {
    convert 'xCAT-genesis-base-x86_64-2.13.10-snap202601010000.noarch.rpm'

    [[ "$SOURCE_DIR" == *-amd64-* ]]
    grep -qx 'Package: xcat-genesis-base-amd64' "$CONTROL"
    grep -qE '^Breaks:.*\bxcat-genesis-scripts-amd64\b' "$CONTROL"
    grep -qx 'Replaces: xcat-genesis-amd64' "$CONTROL"
    grep -qE '^Breaks: xcat-genesis-amd64\b' "$CONTROL"
}

@test "the ppc64 rpm becomes the ppc64el deb, and replaces the deb the rename leaves behind" {
    convert 'xCAT-genesis-base-ppc64-2.13.10-snap202601010000.noarch.rpm'

    [[ "$SOURCE_DIR" == *-ppc64el-* ]]
    grep -qx 'Package: xcat-genesis-base-ppc64el' "$CONTROL"
    grep -qE '^Breaks:.*\bxcat-genesis-scripts-ppc64el\b' "$CONTROL"
    grep -qx 'Replaces: xcat-genesis-ppc64, xcat-genesis-base-ppc64' "$CONTROL"
    grep -qE '^Breaks: xcat-genesis-ppc64, xcat-genesis-base-ppc64\b' "$CONTROL"
}
