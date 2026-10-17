#!/bin/sh

set -eu
[ "$#" -eq 1 ] || {
    printf 'Usage: %s native-bsdinstall-pkgbase\n' "$0" >&2
    exit 2
}
[ -f "$1" ] && [ ! -L "$1" ] &&
    [ "$(sha256 -q "$1")" = 502e4f8330e06f6c939a074315bf1b70fbd7b68e8f17e91cdaf12147c81ae778 ] || {
    printf 'Unsupported FreeBSD 15.1 pkgbase checksum.\n' >&2
    exit 1
}
awk '
    NR == 1 { print; next }
    /^local sys_wait =/ {
        print "local adapter = dofile(\"/usr/local/libexec/xcat-pkgbase.lua\")"
        print "local select_components = adapter.select_components"
        next
    }
    NR < 10 { print; next }
    /^local function append_list\(/ { append = 1 }
    append { print; if ($0 == "end") append = 0; next }
    /^local function select_packages\(/ { selection = 1 }
    /^local function parse_options\(/ { selection = 0 }
    selection {
        if ($0 == "\tlocal rquery = capture(pkg .. \"rquery -U -r FreeBSD-base %n\")") {
            print "\tlocal rquery = pkg(\"rquery\", \"-U\", \"-r\", \"FreeBSD-base\", \"%n\")"
            replaced++
        } else print
    }
    END {
        if (replaced != 1) exit 1
        print "local api = adapter.bind(select_packages,"
        print "    \"502e4f8330e06f6c939a074315bf1b70fbd7b68e8f17e91cdaf12147c81ae778\")"
        print "if ... == \"xcat-freebsd-pkgbase-selection-api-1\" then return api end"
        print "if arg[1] == \"--xcat-prepare-1\" then"
        print "    if #arg ~= 3 then error(\"Invalid xCAT prepare arguments\", 0) end"
        print "    local ok, result = pcall(api.prepare, arg[2], arg[3])"
        print "    if not ok then"
        print "        io.stderr:write(\"xCAT pkgbase selection: Preparation failed; retained inputs require inspection\\n\")"
        print "        os.exit(1)"
        print "    end"
        print "    if not io.write(result) or not io.stdout:flush() then"
        print "        error(\"Cannot write xCAT preparation result\", 0)"
        print "    end"
        print "    return"
        print "end"
        print "api.install()"
    }
' "$1"
