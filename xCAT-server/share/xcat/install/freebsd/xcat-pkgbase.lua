-- SPDX-License-Identifier: BSD-2-Clause

local unistd = require("posix.unistd")
local sys_wait = require("posix.sys.wait")
local stdlib = require("posix.stdlib")
local adapter = {}
local MAX_BYTES = 8388608
local MAX_PACKAGES = 8192
local MAX_CATALOGUE_BYTES = 67108864
local MAX_CATALOGUE_PACKAGES = 100000
local INSTALLER = "/usr/libexec/bsdinstall/pkgbase"
local ADAPTER = "/usr/local/libexec/xcat-pkgbase.lua"
local NATIVE_SHA256 = "502e4f8330e06f6c939a074315bf1b70fbd7b68e8f17e91cdaf12147c81ae778"
local TIMER = "/usr/local/libexec/xcat-postscript-time"
local preparation_started
local installation_started
local preparation_seals
local PACKAGE_FIELDS = {"id", "repository", "name", "version", "origin", "abi",
    "repopath", "path", "size", "sha256", "native_sum"}

local function fail(message)
    error("xCAT pkgbase selection: " .. message, 0)
end

local function text(value, limit)
    if type(value) ~= "string" or #value == 0 or #value > limit * 4
        or value:find("[%z\1-\31\127]") then return false end
    local length = utf8.len(value)
    return length ~= nil and length <= limit
end

local function digest(value)
    return type(value) == "string" and #value == 64 and value:match("^[0-9a-f]+$")
end

local function fields(value, required, optional)
    if type(value) ~= "table" or getmetatable(value) then fail("Invalid object") end
    local allowed = {}
    for _, key in ipairs(required) do
        if value[key] == nil then fail("Missing object field") end
        allowed[key] = true
    end
    for _, key in ipairs(optional or {}) do allowed[key] = true end
    for key in pairs(value) do
        if not allowed[key] then fail("Unknown object field") end
    end
end

local function array(value, limit)
    if type(value) ~= "table" or getmetatable(value) or #value > limit then
        fail("Invalid array")
    end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or math.type(key) ~= "integer"
            or key < 1 or key > #value then fail("Invalid array index") end
        count = count + 1
    end
    if count ~= #value then fail("Sparse array") end
end

local function native_command(command, arguments, limit, sink, seconds)
    seconds = seconds or 60
    local read_fd, write_fd = unistd.pipe()
    if not read_fd then fail("Cannot create command pipe") end
    local pid = unistd.fork()
    if not pid then
        unistd.close(read_fd)
        unistd.close(write_fd)
        fail("Cannot fork command")
    end
    if pid == 0 then
        unistd.close(read_fd)
        unistd.close(0)
        if not unistd.dup2(write_fd, 1) or not unistd.dup2(write_fd, 2) then
            unistd._exit(126)
        end
        if write_fd ~= 1 and write_fd ~= 2 then unistd.close(write_fd) end
        local argv = {"-i", "PATH=/sbin:/bin:/usr/sbin:/usr/bin", "LC_ALL=C",
            "/bin/timeout", "-k", "5", tostring(seconds), command}
        for _, value in ipairs(arguments) do argv[#argv + 1] = value end
        unistd.execp("/usr/bin/env", argv)
        unistd._exit(127)
    end
    unistd.close(write_fd)
    local chunks, size, broken = {}, 0, false
    while true do
        local chunk = unistd.read(read_fd, 4096)
        if not chunk then broken = true; break end
        if chunk == "" then break end
        size = size + #chunk
        if size > limit then broken = true; break end
        if sink then
            if not sink:write(chunk) then broken = true; break end
        else
            chunks[#chunks + 1] = chunk
        end
    end
    unistd.close(read_fd)
    local waited, reason, code = sys_wait.wait(pid)
    if broken or waited ~= pid or reason ~= "exited" or code ~= 0 then
        fail("Native command failed or exceeded its bound")
    end
    return sink and size or table.concat(chunks)
end

local function monotonic_time()
    local bytes = native_command(TIMER, {"uptime"}, 13, nil, 5)
    local value = bytes:match("^(%d+)\n$")
    local seconds = value and tonumber(value)
    if not seconds or #value > 12 or tostring(seconds) ~= value then
        fail("Invalid native monotonic time")
    end
    return seconds
end

local function capture(command, arguments, limit, sink, seconds)
    seconds = seconds or 60
    local started = preparation_started or installation_started
    if started then
        local now = monotonic_time()
        local duration = preparation_started and 1800 or 3600
        if now < started or now >= started + duration then
            fail("Native operation exceeded its time bound")
        end
        seconds = math.min(seconds, started + duration - now)
    end
    return native_command(command, arguments, limit, sink, seconds)
end

local function path(value, kind)
    if not text(value, 4096) or #value > 4096 or value:sub(1, 1) ~= "/" or value == "/"
        or stdlib.realpath(value) ~= value then fail("Invalid canonical path") end
    local arguments = {"-f", "%u:%Op:%HT", "/"}
    local current = ""
    for component in value:gmatch("/[^/]+") do
        current = current .. component
        arguments[#arguments + 1] = current
        if #arguments > 67 then fail("Native path exceeds its depth bound") end
    end
    local attributes = capture("/usr/bin/stat", arguments, 16640)
    local index = 3
    for line in attributes:gmatch("([^\n]*)\n") do
        local owner, mode, actual = line:match("^(%d+):([0-7]+):(.+)$")
        local bits = mode and tonumber(mode, 8)
        local final = index == #arguments
        if index > #arguments or owner ~= "0" or not bits
            or actual ~= (final and kind or "Directory") or (bits & 3072) ~= 0
            or ((bits & 18) ~= 0 and (final or (bits & 512) == 0))
            or (final and (bits & 512) ~= 0) then
            fail("Unprotected native path")
        end
        index = index + 1
    end
    if attributes:sub(-1) ~= "\n" or index ~= #arguments + 1 then
        fail("Incomplete native path attributes")
    end
    return value
end

local function checksum(filename, expected)
    if not digest(expected) then fail("Invalid identity checksum") end
    path(filename, "Regular File")
    if capture("/sbin/sha256", {"-q", filename}, 256) ~= expected .. "\n" then
        fail("Native identity checksum mismatch")
    end
end

local function relative_path(value)
    if not text(value, 4096) or value:sub(1, 1) == "/" or value:sub(-1) == "/"
        or value:find("//", 1, true) then fail("Invalid package path") end
    for component in value:gmatch("[^/]+") do
        if #component > 255 or component == "." or component == ".."
            or not component:match("^[A-Za-z0-9_.,+:~@%%=-]+$") then
            fail("Invalid package path component")
        end
    end
end

local function source_path(value, repository)
    if type(value) ~= "string" then fail("Invalid package source path") end
    local role, suffix = value:match("^([^/]+)/(.+)$")
    if repository == "r0" and role ~= "base"
        or repository ~= "r0" and role ~= "applications" and role ~= "repository" then
        fail("Invalid package source role")
    end
    relative_path(suffix)
end

local function records(packages)
    array(packages, MAX_PACKAGES)
    if #packages == 0 then fail("Missing package records") end
    local names = {}
    for index, package in ipairs(packages) do
        fields(package, PACKAGE_FIELDS)
        if package.id ~= "p" .. (index - 1) or not text(package.repository, 3)
            or not package.repository:match("^r%d+$")
            or tonumber(package.repository:sub(2)) > 31
            or package.repository ~= "r" .. tonumber(package.repository:sub(2)) then
            fail("Invalid package record ID")
        end
        for _, key in ipairs({"name", "version", "origin", "abi"}) do
            if not text(package[key], 1024) then fail("Invalid package identity") end
        end
        if names[package.name] then fail("Conflicting package names") end
        relative_path(package.repopath)
        source_path(package.path, package.repository)
        if not package.repopath:match("%.pkg$") or not digest(package.sha256)
            or not text(package.native_sum, 256)
            or not package.native_sum:match("^[A-Za-z0-9$]+$")
            or type(package.size) ~= "string" or not package.size:match("^%d+$")
            or #package.size > 11 or tostring(tonumber(package.size)) ~= package.size
            or tonumber(package.size) > 17179869184 then fail("Invalid package record") end
        names[package.name] = package
    end
    return names
end

local function components(values)
    array(values, MAX_PACKAGES)
    local seen = {}
    for _, value in ipairs(values) do
        if not text(value, 64) or not value:match("^[a-z][a-z0-9-]*$")
            or seen[value] then fail("Invalid or duplicate component") end
        seen[value] = true
    end
end

function adapter.select_components(available, options)
    local selected = {"minimal"}
    if available.pkg then selected[#selected + 1] = "pkg" end
    selected[#selected + 1] = "kernel"
    for _, component in ipairs(options.components) do
        if not available[component] or (component ~= "debug" and #available[component] == 0) then
            fail("Unavailable native component")
        end
        selected[#selected + 1] = component
    end
    return selected
end

local function catalogue(bytes)
    if #bytes == 0 or bytes:sub(-1) ~= "\n" then fail("Incomplete native catalogue") end
    local names, identities, count = {}, {}, 0
    for line in bytes:gmatch("([^\n]*)\n") do
        local name, version, origin, abi = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
        for _, value in ipairs({name or false, version or false, origin or false, abi or false}) do
            if not text(value, 1024) then fail("Invalid native package identity") end
        end
        count = count + 1
        if count > MAX_CATALOGUE_PACKAGES or identities[name] then fail("Ambiguous native catalogue") end
        names[#names + 1] = name
        identities[name] = {version = version, origin = origin, abi = abi}
    end
    return table.concat(names, "\n"), identities
end

local function pkg_arguments(context, arguments)
    local argv = {"-C", "/dev/null", "--repo-conf-dir", context.repository_directory}
    for _, setting in ipairs({"ABI=FreeBSD:15:amd64", "OSVERSION=1501000",
        "PKG_DBDIR=" .. context.database_directory, "PKG_CACHEDIR=" .. context.cache_directory,
        "REPO_AUTOUPDATE=false", "PKG_ENABLE_PLUGINS=false", "PKG_TRIGGERS_ENABLE=false",
        "RUN_SCRIPTS=false", "HANDLE_RC_SCRIPTS=false", "IGNORE_OSVERSION=false", "SYSLOG=false",
        "CONSERVATIVE_UPGRADE=true"}) do
        argv[#argv + 1] = "-o"
        argv[#argv + 1] = setting
    end
    for _, value in ipairs(arguments) do argv[#argv + 1] = value end
    return argv
end

local function preflight(select_packages, context, base_id)
    fields(context, {"components", "packages", "plan_sha256", "repository_directory",
        "database_directory", "cache_directory", "installer_sha256", "adapter_sha256"}, {"tool"})
    if not digest(context.plan_sha256) then fail("Invalid plan reference") end
    components(context.components)
    local packages = records(context.packages)
    for _, key in ipairs({"repository_directory", "database_directory", "cache_directory"}) do
        path(context[key], "Directory")
    end
    local tool = context.tool or {path = "/usr/local/sbin/pkg-static",
        sha256 = "d75db8494ddab4a03fa8d4187305414fcd88ad64a9a76f326e829e9b32ed248b"}
    fields(tool, {"path", "sha256"})
    checksum(INSTALLER, context.installer_sha256)
    checksum(ADAPTER, context.adapter_sha256)
    checksum(tool.path, tool.sha256)
    if capture(tool.path, pkg_arguments(context, {"-v"}), 256) ~= "2.6.2\n" then
        fail("Unsupported native pkg version")
    end
    local bytes = capture(tool.path, pkg_arguments(context,
        {"rquery", "-U", "-r", base_id or "FreeBSD-base", "%n\t%v\t%o\t%q"}), MAX_CATALOGUE_BYTES)
    local names, identities = catalogue(bytes)
    local selected = select_packages(function(...)
        local argv = {...}
        if #argv ~= 5 or table.concat(argv, "\t") ~= "rquery\t-U\t-r\tFreeBSD-base\t%n" then
            fail("Unsupported native selector command")
        end
        return names
    end, {components = context.components})
    -- Every managed node needs the server used by target setup and updates.
    selected[#selected + 1] = "FreeBSD-ssh"
    selected[#selected + 1] = "FreeBSD-bsdconfig"
    array(selected, MAX_PACKAGES)
    local lines = {"format\txcat-freebsd-pkgbase-roots-1", "scope\tselection-only",
        "plan-reference\t" .. context.plan_sha256, "native-source\t" .. NATIVE_SHA256,
        "installer\t" .. INSTALLER .. "\t" .. context.installer_sha256,
        "adapter\t" .. ADAPTER .. "\t" .. context.adapter_sha256,
        "pkg\t" .. tool.path .. "\t2.6.2\t" .. tool.sha256,
        "repositories\t" .. context.repository_directory,
        "database\t" .. context.database_directory, "cache\t" .. context.cache_directory}
    for _, component in ipairs(context.components) do lines[#lines + 1] = "component\t" .. component end
    local seen = {}
    for _, name in ipairs(selected) do
        local package, identity = packages[name], identities[name]
        if not package or not identity or package.repository ~= "r0" then
            fail("Native root is absent from the base plan records")
        end
        for _, key in ipairs({"version", "origin", "abi"}) do
            if package[key] ~= identity[key] then fail("Native root identity differs from plan record") end
        end
        if not seen[name] then
            local record = {"root"}
            for _, key in ipairs(PACKAGE_FIELDS) do record[#record + 1] = package[key] end
            lines[#lines + 1] = table.concat(record, "\t")
            seen[name] = true
        end
    end
    checksum(tool.path, tool.sha256)
    checksum(INSTALLER, context.installer_sha256)
    checksum(ADAPTER, context.adapter_sha256)
    local receipt = table.concat(lines, "\n") .. "\n"
    if #receipt > MAX_BYTES then fail("Selection receipt exceeds its bound") end
    return receipt, selected, identities
end

local RUNTIME = "/xcat/runtime.tsv"
local DECODER = "/usr/local/libexec/xcat-package-plan.lua"
local RESOLVER = "/usr/local/libexec/freebsd-pkg-resolve"
local PKG = "/usr/local/sbin/pkg-static"
local INSTALL_LIBRARY = "/usr/local/libexec/xcat-install-lib.sh"
local POSTSCRIPT = "/usr/local/libexec/xcat-postscript"
local POSTBOOT = "/usr/local/libexec/xcat-postboot"
local FSYNC = "/usr/bin/fsync"
local MAX_CLOSURE = 68719476736
local RAM_RESERVE = 268435456

local function read_file(filename, limit, allow_empty)
    path(filename, "Regular File")
    local file = io.open(filename, "rb")
    if not file then fail("Cannot open preparation input") end
    local bytes = file:read(limit + 1)
    local closed = file:close()
    if not bytes or not closed or (#bytes == 0 and not allow_empty) or #bytes > limit then
        fail("Invalid preparation input size")
    end
    return bytes
end

local function file_hash(filename)
    path(filename, "Regular File")
    local value = capture("/sbin/sha256", {"-q", filename}, 256):match("^([0-9a-f]+)\n$")
    if not digest(value) then fail("Invalid native checksum output") end
    return value
end

local function protected(filename, kind, mode)
    path(filename, kind)
    local value = capture("/usr/bin/stat", {"-f", "%u:%g:%Lp:%l", filename}, 256)
    local owner, group, actual, links = value:match("^(%d+):(%d+):([0-7]+):(%d+)\n$")
    if owner ~= "0" or group ~= "0" or tonumber(actual, 8) ~= mode
        or (kind == "Regular File" and links ~= "1") then
        fail("Preparation input is not sealed")
    end
end

local function mkdir(directory)
    capture("/bin/mkdir", {"-m", "0700", directory}, 1024)
    protected(directory, "Directory", 448)
end

local function seal(filename)
    capture("/bin/chmod", {"0400", filename}, 1024)
    protected(filename, "Regular File", 256)
end

local function write_file(filename, bytes)
    -- All callers write new names beneath the exclusive preparation directory.
    if stdlib.realpath(filename) then fail("Preparation output already exists") end
    local file = io.open(filename, "wb")
    if not file then fail("Cannot create preparation output") end
    local written, closed = file:write(bytes), file:close()
    if not written or not closed then fail("Cannot write preparation output") end
    seal(filename)
    if read_file(filename, #bytes, true) ~= bytes then fail("Preparation output changed") end
    preparation_seals[filename] = file_hash(filename)
end

local function runtime(config)
    checksum(RUNTIME, config.runtime_sha256)
    local bytes = read_file(RUNTIME, 65536)
    local prefix = "format\txcat-freebsd-runtime-2\ntarget\t15.1-RELEASE\tFreeBSD:15:amd64\t1501000\n"
        .. "pkg-version\t2.6.2\nbsdinstall-contract\txcat-freebsd-pkgbase-1\n"
    if bytes:sub(1, #prefix) ~= prefix or bytes:sub(-1) ~= "\n" then
        fail("Unsupported preparation runtime")
    end
    local files, previous, count = {}, "", 0
    for line in bytes:sub(#prefix + 1):gmatch("([^\n]*)\n") do
        local name, sha = line:match("^file\t([^\t]+)\t([0-9a-f]+)$")
        if not name then fail("Invalid runtime record") end
        relative_path(name)
        if not name:match("^[A-Za-z0-9_./+-]+$") or name <= previous or not digest(sha) then
            fail("Invalid runtime file order or identity")
        end
        count = count + 1
        if count > 256 then fail("Runtime roster exceeds its bound") end
        files["/" .. name], previous = sha, name
    end
    for _, required in ipairs({INSTALLER, ADAPTER, DECODER, RESOLVER, PKG, INSTALL_LIBRARY,
        "/usr/local/sbin/xcat-install", "/usr/libexec/flua", "/bin/sh", "/bin/mkdir",
        "/bin/chmod", "/sbin/sha256", "/sbin/mount", "/sbin/mdconfig", "/sbin/glabel",
        "/usr/bin/stat", "/bin/df", "/usr/bin/env", "/bin/timeout", "/usr/bin/fetch",
        "/sbin/sysctl", FSYNC, TIMER}) do
        if not files[required] then fail("Runtime roster lacks a required preparation file") end
    end
    local postscript_files = 0
    for _, name in ipairs({POSTSCRIPT, POSTSCRIPT .. "-packages", POSTSCRIPT .. "-time", POSTBOOT}) do
        if files[name] then postscript_files = postscript_files + 1 end
    end
    if postscript_files ~= 0 and postscript_files ~= 4 then fail("Incomplete postscript runtime") end
    if config.format == "xcat-freebsd-install-4" or config.format == "xcat-freebsd-install-5" or config.format == "xcat-freebsd-install-6" then
        for _, name in ipairs({
            "/bin/rmdir", "/boot/gptzfsboot", "/boot/loader.efi", "/boot/pmbr",
            "/sbin/mount_msdosfs", "/sbin/newfs_msdos", "/sbin/zfs",
            "/usr/bin/basename", "/usr/bin/cut", "/usr/bin/od",
            "/usr/libexec/bsdconfig/040.password/include/messages.subr",
            "/usr/libexec/bsdconfig/include/messages.subr", "/usr/libexec/bsdinstall/bootconfig",
            "/usr/libexec/bsdinstall/config", "/usr/libexec/bsdinstall/entropy",
            "/usr/libexec/bsdinstall/mount", "/usr/libexec/bsdinstall/mount_aux",
            "/usr/libexec/bsdinstall/zfsboot", "/usr/local/libexec/xcat-storage",
            "/usr/local/libexec/xcat-storage-efi.sh", "/usr/share/bsdconfig/common.subr",
            "/usr/share/bsdconfig/device.subr", "/usr/share/bsdconfig/dialog.subr",
            "/usr/share/bsdconfig/geom.subr", "/usr/share/bsdconfig/password/password.subr",
            "/usr/share/bsdconfig/strings.subr", "/usr/share/bsdconfig/struct.subr",
            "/usr/share/bsdconfig/variable.subr", "/usr/sbin/chroot", "/usr/sbin/efibootmgr",
            "/usr/sbin/efivar", "/usr/sbin/fstyp"}) do
            if not files[name] then fail("Incomplete storage runtime") end
        end
    end
    for name, sha in pairs(files) do checksum(name, sha) end
    checksum(RUNTIME, config.runtime_sha256)
    return files, bytes
end

local function ram_available(workspace, needed)
    local selected
    for line in capture("/sbin/mount", {"-p"}, 65536):gmatch("([^\n]+)\n") do
        local device, mountpoint, filesystem, options = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+%d+%s+%d+$")
        if mountpoint and (mountpoint == "/" or workspace == mountpoint
            or workspace:sub(1, #mountpoint + 1) == mountpoint .. "/") then
            if not selected or #mountpoint > #selected.mountpoint then
                selected = {device = device, mountpoint = mountpoint, filesystem = filesystem, options = options}
            end
        end
    end
    if not selected or not ("," .. selected.options .. ","):find(",rw,", 1, true) then
        fail("Preparation workspace is not on writable RAM storage")
    end
    if selected.filesystem == "tmpfs" then
        if capture("/sbin/sysctl", {"-n", "vm.swap_total"}, 256) ~= "0\n" then
            fail("Preparation tmpfs can page to persistent swap")
        end
        local memory = capture("/sbin/sysctl", {"-n", "hw.pagesize", "vm.stats.vm.v_free_count"}, 256)
        local page_size, free_pages = memory:match("^(%d+)\n(%d+)\n$")
        if not page_size or #page_size > 6 or #free_pages > 13
            or tonumber(page_size) * tonumber(free_pages) < needed + RAM_RESERVE then
            fail("Insufficient free RAM for tmpfs preparation")
        end
    else
        if selected.filesystem ~= "ufs" then fail("Preparation workspace is not RAM-backed") end
        local device = selected.device:match("^/dev/(md%d+)$")
        if not device and selected.device:match("^/dev/ufs/[A-Za-z0-9_.-]+$") then
            for line in capture("/sbin/glabel", {"status", "-s"}, 65536):gmatch("([^\n]+)\n") do
                local name, status, backing = line:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s*$")
                if name and "/dev/" .. name == selected.device and status == "N/A"
                    and backing:match("^md%d+$") then
                    if device then fail("Ambiguous RAM device") end
                    device = backing
                end
            end
        end
        if not device then fail("Preparation workspace is not a direct memory disk") end
        local bytes = capture("/sbin/mdconfig", {"-l", "-v", "-u", device}, 4096)
        local name, kind = bytes:match("^(md%d+)\t([^\t]+)\t[^\n]+\n$")
        if name ~= device or (kind ~= "preload" and kind ~= "malloc") then
            fail("Preparation memory disk has a persistent backing store")
        end
    end
    local bytes = capture("/bin/df", {"-kP", workspace}, 4096)
    local device, total, used, available, mounted = bytes:match("^[^\n]+\n(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+%d+%%%s+(%S+)\n$")
    if not device or device ~= selected.device or mounted ~= selected.mountpoint
        or #available > 13 or tonumber(available) * 1024 < needed + RAM_RESERVE then
        fail("Insufficient RAM workspace capacity")
    end
    return selected.device .. "\t" .. selected.mountpoint .. "\t" .. selected.filesystem
end

local function url_path(value)
    return (value:gsub("[^A-Za-z0-9_./~-]", function(character)
        return string.format("%%%02X", character:byte())
    end))
end

local function fetch_file(url, filename, limit, expected, exact_size)
    if stdlib.realpath(filename) then fail("Fetch output already exists") end
    local file = io.open(filename, "wb")
    if not file then fail("Cannot create bounded fetch output") end
    -- Keep diagnostics out of binary stdout. The URL is an argument, not shell text.
    local ok, size = pcall(capture, "/bin/sh", {"-c",
        'exec /usr/bin/fetch -A -d -q -T 50 -o - "$1" 2>/dev/null', "xcat-fetch", url}, limit, file)
    local closed = file:close()
    if not ok or not closed or size == 0 or (exact_size and size ~= exact_size) then
        fail("Payload transfer failed or differed from its size bound")
    end
    seal(filename)
    checksum(filename, expected)
    preparation_seals[filename] = expected
end

local function native_config(directory, repositories)
    return 'ABI = "FreeBSD:15:amd64";\nOSVERSION = 1501000;\n'
        .. 'PKG_DBDIR = "' .. directory .. '/db";\nPKG_CACHEDIR = "' .. directory .. '/cache";\n'
        .. 'REPOS_DIR = [' .. (repositories and '"' .. directory .. '/repos"' or '') .. '];\n'
        .. 'REPOSITORIES = {};\nREPO_AUTOUPDATE = false;\nPKG_ENABLE_PLUGINS = false;\n'
        .. 'PKG_TRIGGERS_ENABLE = false;\nRUN_SCRIPTS = false;\n'
        .. 'HANDLE_RC_SCRIPTS = false;\nSYSLOG = false;\nIGNORE_OSVERSION = false;\n'
        .. 'PERMISSIVE = false;\nCASE_SENSITIVE_MATCH = true;\nPKG_ENV = {};\n'
        .. (repositories and 'CONSERVATIVE_UPGRADE = true;\nASSUME_ALWAYS_YES = false;\n'
            .. 'FETCH_RETRY = 1;\nFETCH_TIMEOUT = 3;\n' or '')
end

local function metadata(filename)
    -- Match FreeBSDRepo's restricted meta.conf profile before native parsing.
    local remaining, values = read_file(filename, 65536), {}
    while remaining:find("%S") do
        local key, value, next_byte = remaining:match('^%s*([a-z_]+)%s*=%s*"([^"%z\1-\31]*)"%s*;()')
        if not key then key, value, next_byte = remaining:match("^%s*([a-z_]+)%s*=%s*(%d+)%s*;()") end
        if not key or values[key] then fail("Unsupported repository metadata syntax") end
        values[key], remaining = value, remaining:sub(next_byte)
    end
    local fixed = {version = "2", packing_format = "tzst", manifests = "packagesite.yaml",
        data = "data", manifests_archive = "packagesite"}
    for key, value in pairs(fixed) do
        if values[key] ~= value then fail("Unsupported repository metadata value") end
    end
    for _, key in ipairs({"filesite", "filesite_archive"}) do
        if values[key] ~= "files" and values[key] ~= "filesite" and values[key] ~= "filesite.yaml" then
            fail("Unsupported repository file catalogue")
        end
    end
    for key in pairs(values) do
        if not fixed[key] and key ~= "filesite" and key ~= "filesite_archive" then
            fail("Unknown repository metadata field")
        end
    end
end

local function native_directory(directory)
    mkdir(directory)
    for _, name in ipairs({"db", "cache", "repos", "root"}) do mkdir(directory .. "/" .. name) end
end

local function repository_config(repository, source)
    local trust = repository.trust_type == "pubkey"
        and 'signature_type = "pubkey"; pubkey = "' .. source .. '/repository.pub";'
        or 'signature_type = "none";'
    return repository.id .. ' = { url = "file://' .. source .. '"; enabled = true; priority = '
        .. (1000 - tonumber(repository.id:sub(2))) .. '; ' .. trust .. ' };\n'
end

local function native_jobs(bytes, plan, base_names)
    local ucl = require("ucl")
    local parser = ucl.parser(96)
    if not parser or not parser:parse_string(bytes) then fail("Invalid native job response") end
    local response = parser:get_object()
    local function object(value)
        local meta = type(value) == "table" and getmetatable(value)
        return type(meta) == "table" and meta.class == "ucl.type.object"
    end
    if not object(response) or response.format ~= "xcat-freebsd-resolver-1"
        or response.version ~= "2.6.2" then fail("Unsupported native job response") end
    for key in pairs(response) do
        if key ~= "format" and key ~= "version" and key ~= "jobs" then fail("Unknown native job field") end
    end
    local jobs = response.jobs
    local meta = type(jobs) == "table" and getmetatable(jobs)
    if type(meta) ~= "table" or meta.class ~= "ucl.type.array" or #jobs ~= #plan.packages then
        fail("Native job closure differs from the plan")
    end
    local expected, seen, count = records(plan.packages), {}, 0
    for index, job in pairs(jobs) do
        if math.type(index) ~= "integer" or index < 1 or index > #jobs or not object(job)
            or job.job_type ~= "install" or not object(job.package) then fail("Invalid native install job") end
        for key in pairs(job) do
            if key ~= "job_type" and key ~= "repository" and key ~= "package" then fail("Unknown native install field") end
        end
        local package = job.package
        local locked = type(package.name) == "string" and expected[package.name]
        if not locked or seen[package.name] or job.repository ~= locked.repository then
            fail("Native job provider differs from the plan")
        end
        if job.repository ~= "r0" and (base_names[package.name]
            or package.name:match("^FreeBSD%-")
            or type(package.origin) == "string" and package.origin:match("^base/")) then
            fail("Native job selected a non-base provider for a protected package")
        end
        for _, key in ipairs({"name", "version", "origin", "abi", "repopath"}) do
            if package[key] ~= locked[key] then fail("Native package identity differs from the plan") end
        end
        if math.type(package.pkgsize) ~= "integer" or package.pkgsize ~= tonumber(locked.size)
            or package.sum ~= locked.native_sum then fail("Native package payload differs from the plan") end
        seen[package.name], count = true, count + 1
    end
    if count ~= #plan.packages then fail("Incomplete native install jobs") end
end

local function prepare_view(select_packages, stage, name, plan, files, config)
    local directory = stage .. "/" .. name .. "-view"
    native_directory(directory)
    local definitions = {}
    for _, repository in ipairs(plan.repositories) do
        local source = directory .. "/" .. repository.id
        mkdir(source)
        for _, leaf in ipairs({"meta.conf", name .. ".pkg", "repository.pub"}) do
            local original = stage .. "/metadata/" .. repository.id .. "/" .. leaf
            if leaf ~= "repository.pub" or repository.trust_type == "pubkey" then
                write_file(source .. "/" .. leaf, read_file(original, MAX_CATALOGUE_BYTES))
            end
        end
        definitions[#definitions + 1] = repository_config(repository, source)
    end
    write_file(directory .. "/repos/native.conf", table.concat(definitions))
    write_file(directory .. "/config", native_config(directory, true))
    -- A file-size limit bounds catalogue expansion in each disposable native view.
    local update = capture("/bin/sh", {"-c",
        'ulimit -f 262144 || exit 125; exec "$1" -C "$2" update -f',
        "xcat-update", PKG, directory .. "/config"}, MAX_CATALOGUE_BYTES)
    write_file(directory .. "/update-output", update)
    local receipt, selected, base_names = preflight(select_packages, {
        components = plan.components, packages = plan.packages, plan_sha256 = config.package_plan_sha256,
        repository_directory = directory .. "/repos", database_directory = directory .. "/db",
        cache_directory = directory .. "/cache", installer_sha256 = files[INSTALLER],
        adapter_sha256 = files[ADAPTER], tool = {path = PKG, sha256 = files[PKG]}}, "r0")
    write_file(directory .. "/selection.result", receipt)
    local roots, seen, by_id = {}, {}, {}
    for _, package in ipairs(plan.packages) do by_id[package.id] = package end
    for _, name in ipairs(selected) do
        if not seen[name] then roots[#roots + 1], seen[name] = name, true end
    end
    for _, id in ipairs(plan.applications) do
        local package = by_id[id]
        if not package or package.repository == "r0" then fail("Invalid application root") end
        if not seen[package.name] then roots[#roots + 1], seen[package.name] = package.name, true end
    end
    write_file(directory .. "/request", table.concat(roots, "\n") .. "\n")
    local jobs = capture(RESOLVER, {"-C", directory .. "/config", "resolve",
        directory .. "/request", directory .. "/root"}, MAX_CATALOGUE_BYTES)
    native_jobs(jobs, plan, base_names)
    write_file(directory .. "/jobs", jobs)
end

local function configuration(config_path, workspace)
    if type(workspace) ~= "string" or not workspace:match("^/[A-Za-z0-9_./-]+$")
        or #workspace + #"/pkgbase/local/request" >= 512 or config_path ~= workspace .. "/config" then
        fail("Invalid installer preparation paths")
    end
    protected(workspace, "Directory", 448)
    local config_bytes = read_file(config_path, 32768)
    local config, count = {}, 0
    if config_bytes:sub(-1) ~= "\n" or config_bytes:find("[^\32-\126\n]") then fail("Invalid installer config bytes") end
    for line in config_bytes:gmatch("([^\n]*)\n") do
        local key, value = line:match("^([a-z0-9_]+)=(.*)$")
        if not key or config[key] then fail("Invalid installer configuration field") end
        config[key], count = value, count + 1
    end
    if config.bootstrap_network_base64 then
        if config.format == "xcat-freebsd-install-2" then fail("Bootstrap graph requires boot settings") end
        count = count - 1
    end
    if not ((config.format == "xcat-freebsd-install-2" and count == 21)
        or (config.format == "xcat-freebsd-install-3" and count == 27)
        or (config.format == "xcat-freebsd-install-4" and count == 28)
        or (config.format == "xcat-freebsd-install-5" and count == 32)
        or (config.format == "xcat-freebsd-install-6" and count == 36)) then
        fail("Unsupported installer configuration")
    end
    local attempt = os.getenv("XCAT_ATTEMPT")
    if type(attempt) ~= "string" or #attempt ~= 32 or not attempt:match("^[0-9a-f]+$") then
        fail("Missing installer attempt identity")
    end
    return config_bytes, config, attempt
end

local function local_request(plan, plan_sha)
    local lines = {"format\txcat-freebsd-local-request-1", "plan\t" .. plan_sha}
    for _, package in ipairs(plan.packages) do
        local values = {"package"}
        for _, key in ipairs(PACKAGE_FIELDS) do values[#values + 1] = package[key] end
        lines[#lines + 1] = table.concat(values, "\t")
    end
    return table.concat(lines, "\n") .. "\n"
end

local function check_receipt(plan_sha, request_sha, count)
    return "format\txcat-freebsd-local-check-1\nscope\tlocal-check-only\nplan-reference\t"
        .. plan_sha .. "\nrequest-sha256\t" .. request_sha
        .. "\npkg\t2.6.2\npackages\t" .. count .. "\ncomplete\tyes\n"
end

local function prepare_receipt(config, attempt, stage, request_sha, count, total)
    return "format\txcat-freebsd-prepare-1\nscope\tprebegin-only\nnode\t" .. config.node
        .. "\ngeneration\t" .. config.generation .. "\nattempt\t" .. attempt
        .. "\nconfig-sha256\t" .. file_hash(stage .. "/install-config")
        .. "\nplan-sha256\t" .. config.package_plan_sha256 .. "\nruntime-sha256\t" .. config.runtime_sha256
        .. "\nrequest-sha256\t" .. request_sha .. "\ncheck-sha256\t" .. file_hash(stage .. "/local/local-check.result")
        .. "\npackages\t" .. count .. "\narchive-bytes\t" .. total .. "\ncomplete\tyes\n"
end

local function prepare(select_packages, config_path, workspace)
    local config_bytes, config, attempt = configuration(config_path, workspace)
    local files, runtime_bytes = runtime(config)
    local ram = ram_available(workspace, MAX_BYTES + 1048576)
    local stage = workspace .. "/pkgbase"
    mkdir(stage)
    write_file(stage .. "/install-config", config_bytes)
    write_file(stage .. "/runtime", runtime_bytes)
    capture("/bin/sh", {"-c", '. "$1"; xcat_read_config "$2" && case "$XCAT_FORMAT" in xcat-freebsd-install-2|xcat-freebsd-install-3|xcat-freebsd-install-4|xcat-freebsd-install-5|xcat-freebsd-install-6) ;; *) exit 1 ;; esac',
        "xcat-config", INSTALL_LIBRARY, stage .. "/install-config"}, 4096)
    local base_url = config.install_url:gsub("/+$", "") .. "/freebsd15.1/x86_64/"
    fetch_file(base_url .. "plans/" .. config.package_plan_sha256 .. ".plan",
        stage .. "/plan", MAX_BYTES, config.package_plan_sha256)
    local plan_bytes = read_file(stage .. "/plan", MAX_BYTES)
    local plan = dofile(DECODER).parse(plan_bytes)
    local total, metadata_bytes = 0, 0
    for _, package in ipairs(plan.packages) do
        if tonumber(package.size) <= 0 then fail("Empty package archive") end
        total = total + tonumber(package.size)
        if total > MAX_CLOSURE then fail("Package closure exceeds the RAM staging bound") end
    end
    for _, repository in ipairs(plan.repositories) do
        for _, file in ipairs(repository.files) do
            if tonumber(file.size) <= 0 then fail("Empty repository input") end
            metadata_bytes = metadata_bytes + tonumber(file.size)
        end
    end
    -- Retain two independent native databases and both signed catalogue views.
    local needed = total + metadata_bytes * 3 + #plan.repositories * 1073741824 + 536870912
    if ram_available(workspace, needed) ~= ram then fail("RAM workspace changed") end
    mkdir(stage .. "/metadata")
    for _, repository in ipairs(plan.repositories) do
        local directory = stage .. "/metadata/" .. repository.id
        mkdir(directory)
        for _, file in ipairs(repository.files) do
            local leaf = file.path:match("([^/]+)$")
            fetch_file(base_url .. "repositories/" .. repository.publication .. "/" .. url_path(file.path),
                directory .. "/" .. leaf, tonumber(file.size), file.sha256, tonumber(file.size))
        end
        metadata(directory .. "/meta.conf")
    end
    prepare_view(select_packages, stage, "data", plan, files, config)
    prepare_view(select_packages, stage, "packagesite", plan, files, config)
    local local_root = stage .. "/local"
    native_directory(local_root)
    mkdir(local_root .. "/archives")
    for _, package in ipairs(plan.packages) do
        local repository = plan.repositories[tonumber(package.repository:sub(2)) + 1]
        fetch_file(base_url .. "repositories/" .. repository.publication .. "/" .. url_path(package.path),
            local_root .. "/archives/" .. package.id .. ".pkg", tonumber(package.size), package.sha256, tonumber(package.size))
    end
    capture("/bin/chmod", {"0500", local_root .. "/archives"}, 1024)
    protected(local_root .. "/archives", "Directory", 320)
    write_file(local_root .. "/request", local_request(plan, config.package_plan_sha256))
    write_file(local_root .. "/config", native_config(local_root, false))
    local request_sha = file_hash(local_root .. "/request")
    local output = capture(RESOLVER, {"-C", local_root .. "/config", "local-check",
        local_root .. "/request", local_root .. "/root"}, MAX_BYTES)
    if output ~= "" then fail("Unexpected local-check output") end
    protected(local_root .. "/local-check.result", "Regular File", 384)
    local check = check_receipt(config.package_plan_sha256, request_sha, #plan.packages)
    if read_file(local_root .. "/local-check.result", MAX_BYTES) ~= check then fail("Local-check receipt differs") end
    checksum(local_root .. "/request", request_sha)
    checksum(stage .. "/plan", config.package_plan_sha256)
    for filename, sha in pairs(preparation_seals) do
        protected(filename, "Regular File", 256)
        checksum(filename, sha)
    end
    if read_file(config_path, 32768) ~= config_bytes or read_file(stage .. "/install-config", 32768) ~= config_bytes then
        fail("Installer configuration changed during preparation")
    end
    for name, sha in pairs(files) do checksum(name, sha) end
    checksum(RUNTIME, config.runtime_sha256)
    if ram_available(workspace, 0) ~= ram then fail("RAM workspace changed during preparation") end
    local result = prepare_receipt(config, attempt, stage, request_sha, #plan.packages, total)
    write_file(stage .. "/prepare.result", result)
    return result
end

local function absent(filename)
    capture("/bin/sh", {"-c", '[ ! -e "$1" ] && [ ! -L "$1" ]', "xcat-absent", filename}, 1024)
end

local function target_identity(target, filesystem)
    path(target, "Directory")
    local found = 0
    for line in capture("/sbin/mount", {"-p"}, 65536):gmatch("([^\n]+)\n") do
        local _, mounted, kind, options = line:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+%d+%s+%d+$")
        if mounted == target then
            if kind ~= filesystem or (kind ~= "ufs" and kind ~= "zfs")
                or not ("," .. options .. ","):find(",rw,", 1, true) then
                fail("Installation target is not the selected writable filesystem")
            end
            found = found + 1
        end
    end
    if found ~= 1 then fail("Installation target is not an exclusive mounted root") end
    local device, inode = capture("/usr/bin/stat", {"-f", "%d:%i", target}, 128):match("^(%d+):(%d+)\n$")
    if not device or #device > 20 or #inode > 20 then fail("Invalid mounted target identity") end
    return device, inode
end

local function ensure_directory(directory, mode)
    if not stdlib.realpath(directory) then
        capture("/bin/mkdir", {"-m", mode, directory}, 1024)
    end
    path(directory, "Directory")
end

local function apply_configuration(target, finalize)
    local prefix = finalize and "" or target
    return 'ABI = "FreeBSD:15:amd64";\nOSVERSION = 1501000;\n'
        .. 'PKG_DBDIR = "' .. prefix .. '/var/db/pkg";\n'
        .. 'PKG_CACHEDIR = "' .. prefix .. '/var/cache/pkg";\n'
        .. 'REPOS_DIR = [];\nREPOSITORIES = {};\nREPO_AUTOUPDATE = false;\n'
        .. 'PKG_ENABLE_PLUGINS = false;\nPKG_TRIGGERS_ENABLE = true;\nRUN_SCRIPTS = true;\n'
        .. 'HANDLE_RC_SCRIPTS = false;\nSYSLOG = false;\nIGNORE_OSVERSION = false;\n'
        .. 'PERMISSIVE = false;\nCASE_SENSITIVE_MATCH = true;\nPKG_ENV = {};\n'
end

local function install_postscripts(target, files, result_root, runtime_sha)
    if not files[POSTSCRIPT] then return end
    for _, directory in ipairs({"/usr", "/usr/local", "/usr/local/libexec", "/usr/local/etc", "/usr/local/etc/rc.d"}) do
        ensure_directory(target .. directory, "0755")
    end
    local copies = {
        {POSTSCRIPT, POSTSCRIPT, "0555"},
        {POSTSCRIPT .. "-packages", POSTSCRIPT .. "-packages", "0444"},
        {POSTSCRIPT .. "-time", POSTSCRIPT .. "-time", "0555"},
        {RESOLVER, RESOLVER, "0555"},
        {POSTBOOT, POSTBOOT, "0555"},
        {POSTBOOT, "/usr/local/etc/rc.d/xcatpostboot", "0555"},
    }
    for _, item in ipairs(copies) do absent(target .. item[2]) end
    for _, item in ipairs(copies) do
        local source, destination, mode = item[1], target .. item[2], item[3]
        checksum(source, files[source])
        write_file(destination, read_file(source, MAX_CATALOGUE_BYTES))
        capture("/bin/chmod", {mode, destination}, 1024)
        protected(destination, "Regular File", tonumber(mode, 8))
        checksum(destination, files[source])
        capture(FSYNC, {destination}, 1024)
    end
    for _, directory in ipairs({"/usr/local/etc/rc.d", "/usr/local/etc", "/usr/local/libexec", "/usr/local", "/usr"}) do
        capture(FSYNC, {target .. directory}, 1024)
    end
    local marker = result_root .. "/postscript-runtime"
    absent(marker)
    write_file(marker, "format\txcat-freebsd-postscripts-1\nruntime-sha256\t" .. runtime_sha .. "\n")
    capture(FSYNC, {marker}, 1024)
end

local function apply_receipt(scope, plan_sha, request_sha, count, device, inode)
    return "format\txcat-freebsd-local-apply-1\nscope\t" .. scope
        .. "\nplan-reference\t" .. plan_sha .. "\nrequest-sha256\t" .. request_sha
        .. "\npkg\t2.6.2\npackages\t" .. count .. "\ntarget-device\t" .. device
        .. "\ntarget-inode\t" .. inode .. "\ncomplete\tyes\n"
end

local function apply_phase(local_root, target, config_path, scope, expected, seconds)
    local output_path = local_root .. "/" .. scope .. ".output"
    absent(output_path)
    local output = io.open(output_path, "wb")
    if not output then fail("Cannot retain native apply output") end
    local ok = pcall(capture, RESOLVER,
        {"-C", config_path, scope, local_root .. "/request", target}, MAX_BYTES, output, seconds)
    local closed = output:close()
    if not ok or not closed then fail("Native apply phase failed; retained output requires inspection") end
    seal(output_path)
    local receipt_path = local_root .. "/" .. scope .. ".result"
    protected(receipt_path, "Regular File", 384)
    if read_file(receipt_path, 1024) ~= expected then fail("Native apply receipt differs") end
    return file_hash(receipt_path)
end

local function install()
    local workspace, target = os.getenv("XCAT_WORK"), os.getenv("BSDINSTALL_CHROOT")
    if type(workspace) ~= "string" or type(target) ~= "string" or target == "/"
        or #target >= 512 or not target:match("^/[A-Za-z0-9_./+-]+$")
        or target:sub(1, #workspace + 1) == workspace .. "/"
        or workspace:sub(1, #target + 1) == target .. "/" or target == workspace then
        fail("Invalid installation workspace or target")
    end
    local config_bytes, config, attempt = configuration(workspace .. "/config", workspace)
    local files, runtime_bytes = runtime(config)
    ram_available(workspace, 0)
    local stage, local_root = workspace .. "/pkgbase", workspace .. "/pkgbase/local"
    protected(stage, "Directory", 448)
    protected(local_root, "Directory", 448)
    for _, name in ipairs({"install-config", "plan", "runtime", "prepare.result", "local/request", "local/config"}) do
        protected(stage .. "/" .. name, "Regular File", 256)
    end
    if read_file(stage .. "/install-config", 32768) ~= config_bytes
        or read_file(stage .. "/runtime", 65536) ~= runtime_bytes then
        fail("Prepared configuration or runtime changed")
    end
    capture("/bin/sh", {"-c", '. "$1"; xcat_read_config "$2" && case "$XCAT_FORMAT" in xcat-freebsd-install-2|xcat-freebsd-install-3|xcat-freebsd-install-4|xcat-freebsd-install-5|xcat-freebsd-install-6) ;; *) exit 1 ;; esac',
        "xcat-config", INSTALL_LIBRARY, stage .. "/install-config"}, 4096)
    checksum(stage .. "/plan", config.package_plan_sha256)
    local plan = dofile(DECODER).parse(read_file(stage .. "/plan", MAX_BYTES))
    local request_bytes = local_request(plan, config.package_plan_sha256)
    if read_file(local_root .. "/request", MAX_BYTES) ~= request_bytes
        or read_file(local_root .. "/config", 8192) ~= native_config(local_root, false) then
        fail("Prepared native request or check configuration changed")
    end
    local request_sha = file_hash(local_root .. "/request")
    protected(local_root .. "/local-check.result", "Regular File", 384)
    if read_file(local_root .. "/local-check.result", 1024)
        ~= check_receipt(config.package_plan_sha256, request_sha, #plan.packages) then
        fail("Prepared local-check receipt differs")
    end
    protected(local_root .. "/archives", "Directory", 320)
    local total = 0
    for _, package in ipairs(plan.packages) do
        local filename = local_root .. "/archives/" .. package.id .. ".pkg"
        protected(filename, "Regular File", 256)
        checksum(filename, package.sha256)
        if capture("/usr/bin/stat", {"-f", "%z", filename}, 64) ~= package.size .. "\n" then
            fail("Prepared archive size differs")
        end
        total = total + tonumber(package.size)
        if total > MAX_CLOSURE then fail("Prepared closure exceeds its bound") end
    end
    local prepared = prepare_receipt(config, attempt, stage, request_sha, #plan.packages, total)
    if read_file(stage .. "/prepare.result", 4096) ~= prepared then fail("Preparation binding differs") end
    local prepared_sha = file_hash(stage .. "/prepare.result")
    for _, name in ipairs({"check-config", "local-install.started", "local-install.result",
        "local-finalize.started", "local-finalize.result"}) do absent(local_root .. "/" .. name) end
    local device, inode = target_identity(target, config.filesystem)
    -- Changing the check profile consumes this prepared workspace exactly once.
    if not os.rename(local_root .. "/config", local_root .. "/check-config") then
        fail("Cannot retain the consumed check configuration")
    end
    protected(local_root .. "/check-config", "Regular File", 256)
    write_file(local_root .. "/config", apply_configuration(target, false))
    for _, name in ipairs({"var", "var/db", "var/cache"}) do ensure_directory(target .. "/" .. name, "0755") end
    for _, name in ipairs({"var/db/pkg", "var/cache/pkg"}) do
        ensure_directory(target .. "/" .. name, "0755")
        protected(target .. "/" .. name, "Directory", 493)
    end
    ensure_directory(target .. "/var/db/xcat", "0700")
    protected(target .. "/var/db/xcat", "Directory", 448)
    local finalize_root = target .. "/var/db/xcat/pkg-apply"
    mkdir(finalize_root)
    mkdir(finalize_root .. "/repos")
    write_file(finalize_root .. "/config", apply_configuration(target, true))
    local install_sha = apply_phase(local_root, target, local_root .. "/config", "local-install",
        apply_receipt("local-install", config.package_plan_sha256, request_sha, #plan.packages, device, inode), 1800)
    local finalize_sha = apply_phase(local_root, target, finalize_root .. "/config", "local-finalize",
        apply_receipt("local-finalize", config.package_plan_sha256, request_sha, #plan.packages, device, inode), 600)
    local after_device, after_inode = target_identity(target, config.filesystem)
    if after_device ~= device or after_inode ~= inode then fail("Installed target identity changed") end
    for filename, sha in pairs(files) do checksum(filename, sha) end
    checksum(RUNTIME, config.runtime_sha256)
    checksum(local_root .. "/request", request_sha)
    checksum(local_root .. "/local-install.result", install_sha)
    checksum(local_root .. "/local-finalize.result", finalize_sha)
    checksum(stage .. "/prepare.result", prepared_sha)
    checksum(stage .. "/plan", config.package_plan_sha256)
    checksum(stage .. "/runtime", config.runtime_sha256)
    if read_file(workspace .. "/config", 32768) ~= config_bytes
        or read_file(stage .. "/install-config", 32768) ~= config_bytes
        or read_file(local_root .. "/check-config", 8192) ~= native_config(local_root, false)
        or read_file(local_root .. "/local-check.result", 1024)
            ~= check_receipt(config.package_plan_sha256, request_sha, #plan.packages) then
        fail("Prepared inputs changed during installation")
    end
    local result_root = target .. "/var/db/xcat/pkgbase-install"
    mkdir(result_root)
    local retained = {
        {"install-config", stage .. "/install-config", 32768},
        {"plan", stage .. "/plan", MAX_BYTES},
        {"runtime", stage .. "/runtime", 65536},
        {"request", local_root .. "/request", MAX_BYTES},
        {"prepare.result", stage .. "/prepare.result", 4096},
        {"local-check.result", local_root .. "/local-check.result", 1024},
        {"local-install.result", local_root .. "/local-install.result", 1024},
        {"local-finalize.result", local_root .. "/local-finalize.result", 1024},
    }
    for _, item in ipairs(retained) do
        local filename = result_root .. "/" .. item[1]
        write_file(filename, read_file(item[2], item[3]))
        capture(FSYNC, {filename}, 1024)
    end
    install_postscripts(target, files, result_root, config.runtime_sha256)
    local result = "format\txcat-freebsd-pkgbase-result-1\nscope\tinstall-finalize\nnode\t" .. config.node
        .. "\ngeneration\t" .. config.generation .. "\nattempt\t" .. attempt
        .. "\nconfig-sha256\t" .. file_hash(result_root .. "/install-config")
        .. "\nplan-sha256\t" .. config.package_plan_sha256 .. "\nruntime-sha256\t" .. config.runtime_sha256
        .. "\nprepare-sha256\t" .. file_hash(result_root .. "/prepare.result")
        .. "\nrequest-sha256\t" .. request_sha .. "\ninstall-result-sha256\t" .. install_sha
        .. "\nfinalize-result-sha256\t" .. finalize_sha .. "\ntarget-device\t" .. device
        .. "\ntarget-inode\t" .. inode .. "\npackages\t" .. #plan.packages .. "\ncomplete\tyes\n"
    write_file(result_root .. "/result", result)
    capture(FSYNC, {result_root .. "/result"}, 1024)
    for _, directory in ipairs({result_root, target .. "/var/db/xcat", target .. "/var/db", target .. "/var", target}) do
        capture(FSYNC, {directory}, 1024)
    end
    return result
end

function adapter.bind(select_packages, native_sha256)
    if type(select_packages) ~= "function" or native_sha256 ~= NATIVE_SHA256 then
        fail("Unsupported native selector")
    end
    return {
        preflight = function(context) return preflight(select_packages, context) end,
        prepare = function(config_path, workspace)
            if preparation_started then fail("Preparation is already active") end
            preparation_started = monotonic_time()
            preparation_seals = {}
            local ok, result = pcall(prepare, select_packages, config_path, workspace)
            preparation_started, preparation_seals = nil, nil
            if not ok then fail("Preparation failed; retained inputs require inspection: " .. tostring(result)) end
            return result
        end,
        install = function()
            if preparation_started or installation_started then fail("A package operation is already active") end
            installation_started = monotonic_time()
            preparation_seals = {}
            local ok, result = pcall(install)
            installation_started, preparation_seals = nil, nil
            if not ok then fail("Installation failed; retained inputs require inspection: " .. tostring(result)) end
            return result
        end,
    }
end

return adapter
