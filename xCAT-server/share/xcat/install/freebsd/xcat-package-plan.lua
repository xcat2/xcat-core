-- SPDX-License-Identifier: BSD-2-Clause

local package_plan = {}
local MAX_BYTES = 8388608
local MAX_LINE = 32768
local IDENTITY = {"name", "version", "origin", "abi"}
local PACKAGE = {"id", "repository", "name", "version", "origin", "abi",
    "repopath", "path", "size", "sha256", "native_sum"}
local REPOSITORY = {"id", "publication", "role", "trust_type", "trust_digest"}
local FILE = {"kind", "path", "size", "sha256"}
local ARITY = {format = 1, target = 3, resolver = 2, ["resolver-libraries"] = 1,
    repository = 5, prefix = 2, file = 5, component = 1, application = 1, package = 11}

local function fail(message)
    error("FreeBSD package plan: " .. message, 0)
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

local function count(value, maximum)
    return type(value) == "string" and #value <= 11
        and (value == "0" or value:match("^[1-9][0-9]*$"))
        and tonumber(value) <= maximum
end

local function before(left, right)
    -- UTF-8 byte order matches scalar order without using the process locale.
    for index = 1, math.min(#left, #right) do
        local a, b = left:byte(index), right:byte(index)
        if a ~= b then return a < b end
    end
    return #left < #right
end

local function path(value)
    if not text(value, 4096) then fail("Invalid package plan path") end
    for component in (value .. "/"):gmatch("([^/]*)/") do
        if #component == 0 or #component > 255 or component == "." or component == ".."
            or not component:match("^[A-Za-z0-9_.,+:~@%%=-]+$") then
            fail("Invalid package plan path component")
        end
    end
end

local function repository_index(id, repositories)
    if not text(id, 3) or not id:match("^r[0-9]+$") then
        fail("Unknown package repository")
    end
    local index = tonumber(id:sub(2))
    if id ~= "r" .. index or index >= #repositories then fail("Unknown package repository") end
    return index + 1
end

local function object(keys, values, offset)
    local result = {}
    for index, key in ipairs(keys) do result[key] = values[index + (offset or 0)] end
    return result
end

local function decode_line(line)
    if #line > MAX_LINE then fail("Package plan record is too long") end
    if not utf8.len(line) then fail("Invalid package plan UTF-8") end
    local values = {}
    for value in (line .. "\t"):gmatch("([^\t]*)\t") do values[#values + 1] = value end
    local kind = table.remove(values, 1)
    if not ARITY[kind] or #values ~= ARITY[kind] then fail("Invalid package plan record") end
    for _, value in ipairs(values) do
        if not text(value, MAX_LINE) then fail("Invalid package plan record") end
    end
    return kind, values
end

local function record(plan, seen, kind, values)
    if kind == "format" or kind == "target" or kind == "resolver" or kind == "resolver-libraries" then
        if seen[kind] then fail("Duplicate package plan singleton") end
        seen[kind] = true
        if kind == "format" and values[1] ~= "xcat-freebsd-package-plan-1" then
            fail("Unsupported package plan format")
        elseif kind == "target" and table.concat(values, "\t") ~= "15.1-RELEASE\tFreeBSD:15:amd64\t1501000" then
            fail("Unsupported package plan target")
        elseif kind == "resolver" then
            plan.resolver.version, plan.resolver.sha256 = values[1], values[2]
        elseif kind == "resolver-libraries" then
            plan.resolver.library_digest = values[1]
        end
    elseif kind == "repository" then
        local repository = object(REPOSITORY, values)
        repository.prefix, repository.files = "", {}
        plan.repositories[#plan.repositories + 1] = repository
    elseif kind == "prefix" or kind == "file" then
        local index = repository_index(values[1], plan.repositories)
        local repository = plan.repositories[index]
        if kind == "prefix" then
            if seen["prefix-" .. index] then fail("Duplicate repository prefix") end
            seen["prefix-" .. index] = true
            repository.prefix = values[2]
        else
            repository.files[#repository.files + 1] = object(FILE, values, 1)
        end
    elseif kind == "component" or kind == "application" then
        local values_list = plan[kind .. "s"]
        values_list[#values_list + 1] = values[1]
    else
        plan.packages[#plan.packages + 1] = object(PACKAGE, values)
    end
end

local function repository_files(repository)
    if repository.prefix ~= "" then path(repository.prefix) end
    local directory = repository.role
    if repository.prefix ~= "" then directory = directory .. "/" .. repository.prefix end
    local expected = {[directory .. "/meta.conf"] = "meta", [directory .. "/data.pkg"] = "catalogue",
        [directory .. "/packagesite.pkg"] = "catalogue"}
    if repository.trust_type == "pubkey" then expected["repository.pub"] = "key" end
    local limits = {catalogue = 67108864, key = 1048576, meta = 65536}
    for _, file in ipairs(repository.files) do
        local kind = expected[file.path]
        if not kind or file.kind ~= kind then fail("Missing, duplicate or misplaced repository file") end
        expected[file.path] = nil
        if not digest(file.sha256) or not count(file.size, limits[kind]) then
            fail("Invalid repository file size or checksum")
        end
        if kind == "key" and file.sha256 ~= repository.trust_digest then
            fail("Repository public key and trust digest disagree")
        end
    end
    if next(expected) then fail("Missing repository metadata or catalogue") end
end

local function repositories(values)
    if #values == 0 or #values > 32 then fail("Invalid repository count") end
    local seen = {}
    for index, repository in ipairs(values) do
        if repository.id ~= "r" .. (index - 1) then fail("Repository IDs must be sequential") end
        if not digest(repository.publication) then fail("Invalid repository publication digest") end
        local role = repository.role
        if index == 1 and role ~= "base"
            or index ~= 1 and role ~= "applications" and role ~= "repository" then
            fail("Invalid repository role order")
        end
        local key = repository.publication .. "/" .. role
        if seen[key] then fail("Duplicate repository publication and role") end
        seen[key] = true
        local trust = repository.trust_type
        if role == "repository" and trust ~= "pubkey" and trust ~= "operator-trusted-tree"
            or role ~= "repository" and trust ~= "operator-trusted-release" then
            fail("Invalid repository trust type")
        end
        if not digest(repository.trust_digest) then fail("Invalid repository trust digest") end
        repository_files(repository)
    end
end

local function packages(plan)
    if #plan.packages == 0 or #plan.packages > 8192 then fail("Invalid package count") end
    local names, result, paths, logical, previous = {}, {}, {}, {}, nil
    for index, package in ipairs(plan.packages) do
        if package.id ~= "p" .. (index - 1) then fail("Package IDs must be sequential") end
        local identity = {}
        for _, key in ipairs(IDENTITY) do
            if not text(package[key], 1024) then fail("Invalid package identity") end
            identity[#identity + 1] = package[key]
        end
        if names[package.name] then fail("Conflicting selected package providers") end
        names[package.name] = true
        local repo = repository_index(package.repository, plan.repositories)
        local sortkey = string.format("%02d", repo - 1) .. "\0" .. table.concat(identity, "\0")
        if previous and not before(previous, sortkey) then fail("Noncanonical package order") end
        previous = sortkey
        local source_key = package.repository .. "\0" .. package.path
        local logical_key = package.repository .. "\0" .. package.repopath
        if paths[source_key] or logical[logical_key] then fail("Duplicate selected archive path") end
        paths[source_key], logical[logical_key] = true, true
        path(package.repopath)
        if not package.repopath:match("%.pkg$") then fail("Invalid logical package archive path") end
        local prefix = plan.repositories[repo].role .. "/"
        if package.path:sub(1, #prefix) ~= prefix then fail("Package source path has the wrong role") end
        path(package.path:sub(#prefix + 1))
        if not count(package.size, 17179869184) or not digest(package.sha256) then
            fail("Invalid package size or checksum")
        end
        if not text(package.native_sum, 256) or not package.native_sum:match("^[A-Za-z0-9$]+$") then
            fail("Invalid native package checksum")
        end
        result[package.id] = package
    end
    return result
end

local function check(plan)
    if plan.resolver.version ~= "2.8.2" then fail("Unsupported native resolver version") end
    if not digest(plan.resolver.sha256) then fail("Invalid native resolver checksum") end
    if plan.resolver.library_digest and not digest(plan.resolver.library_digest) then
        fail("Invalid native resolver library checksum")
    end
    repositories(plan.repositories)
    local components, applications = {}, {}
    for _, component in ipairs(plan.components) do
        if #component > 64 or not component:match("^[a-z][a-z0-9-]*$") or components[component] then
            fail("Invalid or duplicate base component")
        end
        components[component] = true
    end
    local indexed = packages(plan)
    for _, id in ipairs(plan.applications) do
        if not indexed[id] or applications[id] then fail("Unknown or duplicate application root") end
        if indexed[id].repository == "r0" then fail("Application root cannot select a base package") end
        applications[id] = true
    end
end

local function encode(plan)
    local rows = {"format\txcat-freebsd-package-plan-1", "target\t15.1-RELEASE\tFreeBSD:15:amd64\t1501000",
        "resolver\t" .. plan.resolver.version .. "\t" .. plan.resolver.sha256}
    local function append(kind, value, keys, id)
        local row = {kind}
        if id then row[#row + 1] = id end
        for _, key in ipairs(keys) do row[#row + 1] = value[key] end
        rows[#rows + 1] = table.concat(row, "\t")
    end
    if plan.resolver.library_digest then
        rows[#rows + 1] = "resolver-libraries\t" .. plan.resolver.library_digest
    end
    for _, repository in ipairs(plan.repositories) do append("repository", repository, REPOSITORY) end
    for _, repository in ipairs(plan.repositories) do
        if repository.prefix ~= "" then
            rows[#rows + 1] = "prefix\t" .. repository.id .. "\t" .. repository.prefix
        end
    end
    for _, repository in ipairs(plan.repositories) do
        local files = {}
        for index, file in ipairs(repository.files) do files[index] = file end
        table.sort(files, function(left, right) return before(left.path, right.path) end)
        for _, file in ipairs(files) do append("file", file, FILE, repository.id) end
    end
    for _, component in ipairs(plan.components) do rows[#rows + 1] = "component\t" .. component end
    for _, id in ipairs(plan.applications) do rows[#rows + 1] = "application\t" .. id end
    for _, package in ipairs(plan.packages) do append("package", package, PACKAGE) end
    return table.concat(rows, "\n") .. "\n"
end

function package_plan.parse(...)
    local bytes = ...
    if select("#", ...) ~= 1 or type(bytes) ~= "string" or #bytes == 0 or #bytes > MAX_BYTES then
        fail("Parsing requires one bounded byte string")
    end
    if bytes:sub(-1) ~= "\n" or bytes:find("\r", 1, true) then
        fail("Plan requires LF records and a final LF")
    end
    local plan = {resolver = {}, repositories = {}, components = {}, applications = {}, packages = {}}
    local seen, lines = {}, 0
    for line in bytes:gmatch("([^\n]*)\n") do
        lines = lines + 1
        if lines > 16384 then fail("Too many package plan records") end
        local kind, values = decode_line(line)
        record(plan, seen, kind, values)
    end
    if not seen.format or not seen.target or not seen.resolver then fail("Missing package plan singleton") end
    check(plan)
    if encode(plan) ~= bytes then fail("Noncanonical package plan encoding") end
    return plan
end

return package_plan
