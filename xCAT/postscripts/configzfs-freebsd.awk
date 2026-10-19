function fail(message) {
    print "configzfs: " message > "/dev/stderr"
    failed = 1
    exit 1
}

function draid_geometry(text,    parts) {
    if (text !~ /^draid[123]:[1-9][0-9]*d:[1-9][0-9]*c:(0|[1-9][0-9]*)s$/)
        fail("dRAID requires explicit parity, data width, children and distributed spares")
    split(text, parts, ":")
    draid_parity = substr(parts[1], 6) + 0
    draid_data = parts[2] + 0
    draid_children = parts[3] + 0
    draid_spares = parts[4] + 0
    if (draid_children > 128 || draid_data + draid_parity + draid_spares > draid_children)
        fail("Invalid dRAID geometry")
}

function members(role, text, minimum, grouping,    n, groups, g, count, list, i, pair, device, serial, unit, kind, tokens, nt, singles, ns) {
    if (text == "-")
        return
    n = split(text, groups, ";")
    if (grouping != "groups" && n != 1)
        fail("Unexpected member groups for " role)
    for (g = 1; g <= n; g++) {
        count = split(groups[g], list, ",")
        if (count < minimum)
            fail("Insufficient members for " role)
        if (role == "data" && draid_children && count != draid_children)
            fail("The dRAID child count differs from the listed devices")
        if (role == "special" && count != minimum)
            fail("Special devices must match the data replication level")
        kind = "stripe"
        if (role == "data") {
            kind = value["topology"] == "raid10" ? "mirror" : value["topology"]
            if (value["topology"] == "raid10" && (count != 2 || n < 2))
                fail("Striped mirrors require at least two pairs")
        } else if (role == "special" || (role == "log" && count > 1))
            kind = "mirror"
        group_type[role, g] = kind
        if (role != "os") group_row[++group_rows] = "G\t" role "\t" g "\t" kind
        for (i = 1; i <= count; i++) {
            if (split(list[i], pair, "@") != 2 || pair[1] !~ /^(ada|da|nda|nvd|vtbd)(0|[1-9][0-9]*)$/ ||
                pair[2] !~ /^[A-Za-z0-9_.:+-]+$/ || length(pair[2]) > 128)
                fail("Invalid device and serial for " role)
            unit = pair[1]
            sub(/^[a-z]+/, "", unit)
            if (length(unit) > 5) fail("Invalid device unit for " role)
            device = pair[1]; serial = pair[2]
            if (devices[device]++ || serials[serial]++)
                fail("OS and data device identities overlap or repeat")
            if (++total > 128)
                fail("Storage policy exceeds 128 disks")
            row[++rows] = "D\t" role "\t" device "\t" serial "\t" g
            if (role != "os") {
                if (i == 1 && kind != "stripe")
                    tokens[++nt] = kind
                if (role == "log" && kind == "stripe")
                    singles[++ns] = "/dev/" device
                else
                    tokens[++nt] = "/dev/" device
            }
        }
    }
    for (i = 1; i <= ns; i++) command[++commands] = singles[i]
    for (i = 1; i <= nt; i++) command[++commands] = tokens[i]
}

function compile(    allowed, keys, i, key, minimum, special_min, n) {
    split("format action pool guid os_disks topology vdevs log_vdevs cache_vdevs special_vdevs compression ashift special_small_blocks encryption keyfile mountpoint", keys, " ")
    for (i in keys)
        allowed[keys[i]] = 1
    for (key in value)
        if (!(key in allowed))
            fail("Unsupported storage setting " key)
    if (value["format"] != "xcat-freebsd-data-1" || value["action"] !~ /^(create|import)$/)
        fail("An explicit create or import data policy is required")
    if (value["pool"] !~ /^[a-z][a-z0-9_-]*$/ || length(value["pool"]) > 63 ||
        value["pool"] ~ /^(zroot|log|mirror|raidz[0-9]*|draid[0-9]*|spare|cache|special|dedup)$/)
        fail("Invalid data pool name")
    if (!("guid" in value)) value["guid"] = "-"
    if (value["action"] == "import") {
        if (value["guid"] !~ /^[1-9][0-9]*$/ || length(value["guid"]) > 20 ||
            (length(value["guid"]) == 20 && "g" value["guid"] > "g18446744073709551615"))
            fail("Import requires the preserved pool GUID")
    } else if (value["guid"] != "-")
        fail("A new pool must not reuse a GUID")
    if (!("compression" in value)) value["compression"] = "lz4"
    if (value["compression"] !~ /^(off|lz4|gzip(-[1-9])?|zstd(-([1-9]|1[0-9]))?)$/)
        fail("Unsupported compression")
    if (value["compression"] == "gzip-6") value["compression"] = "gzip"
    if (!("ashift" in value)) value["ashift"] = "12"
    if (value["ashift"] !~ /^(9|1[0-6])$/)
        fail("Invalid ashift")
    if (!("special_small_blocks" in value)) value["special_small_blocks"] = "0"
    n = value["special_small_blocks"]
    if (n !~ /^(0|[1-9][0-9]*)$/ || n + 0 > 16777216 || (n + 0 > 0 && n + 0 < 512))
        fail("Invalid special_small_blocks size")
    while (n > 1 && n % 2 == 0) n /= 2
    if (n > 1) fail("special_small_blocks must be a power of two")
    if (!("encryption" in value)) value["encryption"] = "off"
    if (!("keyfile" in value)) value["keyfile"] = "-"
    if (value["encryption"] == "aes-256-gcm") {
        if (value["keyfile"] != "/etc/xcat/keys/" value["pool"] ".key")
            fail("Automatic encryption requires the pool key file under /etc/xcat/keys")
    } else if (value["encryption"] != "off" || value["keyfile"] != "-")
        fail("Unsupported encryption or key policy")
    if (!("mountpoint" in value)) value["mountpoint"] = "/data/" value["pool"]
    if (value["mountpoint"] !~ /^\/(data|srv)\/[A-Za-z0-9_-][A-Za-z0-9_.-]*$/)
        fail("The data mountpoint must be a direct child of /data or /srv")
    if (value["topology"] ~ /^draid/)
        draid_geometry(value["topology"])
    else if (value["topology"] !~ /^(stripe|mirror|raid10|raidz[123])$/)
        fail("Unsupported data topology")
    minimum = 2
    if (value["topology"] == "stripe") minimum = 1
    if (value["topology"] == "raidz1") minimum = 3
    if (value["topology"] == "raidz2") minimum = 4
    if (value["topology"] == "raidz3") minimum = 5
    if (draid_children) minimum = draid_children
    if (value["os_disks"] == "-" || value["vdevs"] == "-") fail("OS and data disks must be explicit")
    if (mode != "compile-auto" || value["os_disks"] != "auto")
        members("os", value["os_disks"], 1, "flat")
    members("data", value["vdevs"], minimum, value["topology"] == "raid10" || draid_children ? "groups" : "flat")
    special_min = 2
    if (value["topology"] == "mirror") special_min = split(value["vdevs"], keys, ",")
    if (value["topology"] == "raidz2") special_min = 3
    if (value["topology"] == "raidz3") special_min = 4
    if (draid_children) special_min = draid_parity + 1
    for (i = 1; i <= 3; i++) {
        key = i == 1 ? "special" : i == 2 ? "log" : "cache"
        if (!(key "_vdevs" in value)) value[key "_vdevs"] = "-"
        if (value[key "_vdevs"] == "-") continue
        if (key == "special" && value["topology"] == "stripe")
            fail("Striped data cannot use mirrored special devices")
        command[++commands] = key
        members(key, value[key "_vdevs"], key == "special" ? special_min : 1, key == "cache" ? "flat" : "groups")
    }
    if (value["special_small_blocks"] != 0 && value["special_vdevs"] == "-")
        fail("Small blocks require a redundant special vdev")
    split("format action pool guid compression ashift special_small_blocks encryption keyfile mountpoint", keys, " ")
    for (i = 1; i <= 10; i++) print "K\t" keys[i] "\t" value[keys[i]]
    for (i = 1; i <= rows; i++) print row[i]
    for (i = 1; i <= group_rows; i++) print group_row[i]
    for (i = 1; i <= commands; i++) print "C\t" command[i]
}

function cache_pool(    prior) {
    if (cache_name == "") return
    if (cache_guids != 1) fail("A cached pool lacks one GUID")
    prior = cached[cache_name]
    if ((prior != "" && "g" prior != "g" cache_guid) ||
        (cache_guid in cache_names && cache_names[cache_guid] != cache_name))
        fail("Conflicting cached pool identities")
    cached[cache_name] = cache_guid
    cache_names[cache_guid] = cache_name
}

BEGIN {
    if (mode == "") mode = "compile"
    if (mode != "compile" && mode != "compile-auto" && mode != "verify" && mode != "cache") fail("Unknown storage operation")
}

mode == "cache" {
    if ($0 ~ /^[^ \t]/) {
        cache_pool()
        if ($0 !~ /^[A-Za-z][A-Za-z0-9_.:-]*:$/ || length($0) > 256)
            fail("Invalid cached pool name")
        cache_name = substr($0, 1, length($0) - 1)
        cache_guids = 0
    } else if ($1 == "pool_guid:") {
        if (cache_name == "" || NF != 2 || $2 !~ /^[1-9][0-9]*$/ || length($2) > 20 ||
            (length($2) == 20 && "g" $2 > "g18446744073709551615"))
            fail("Invalid cached pool GUID")
        cache_guid = $2
        cache_guids++
    }
    next
}

mode == "compile" || mode == "compile-auto" {
    bytes += length($0) + 1
    if (bytes > 32768 || $0 ~ /[^ -~]/) fail("Invalid policy size or characters")
    if ($0 ~ /^([ ]*|#.*)$/) next
    p = index($0, "=")
    key = substr($0, 1, p - 1)
    if (!p || key !~ /^[a-z_]+$/ || key in value) fail("Malformed or repeated storage setting")
    value[key] = substr($0, p + 1)
    next
}

mode == "verify" && FILENAME == ARGV[1] {
    n = split($0, f, "\t")
    if (f[1] == "K" && f[2] == "pool") pool = f[3]
    if (f[1] == "D" && f[2] != "os") {
        expected_role["/dev/" f[3]] = f[2]
        expected_group["/dev/" f[3]] = f[2] SUBSEP f[5]
    }
    if (f[1] == "G") expected_type[f[2], f[3]] = f[4]
    next
}

mode == "verify" {
    if ($1 == "state:") {
        if ($2 != "ONLINE") fail("The pool is not online")
        state_seen++
        next
    }
    if ($1 == "NAME" && $2 == "STATE") {active = 1; role = "data"; group = ""; next}
    if ($0 ~ /^errors:/) {
        if ($0 != "errors: No known data errors") fail("The pool reports data errors")
        active = 0; errors_seen = 1; next
    }
    if (!active || !NF) next
    if (NF == 1 && $1 ~ /^(logs|cache|special|spares)$/) {
        role = $1 == "logs" ? "log" : $1
        group = ""
        next
    }
    if (role == "spares") {
        if (NF != 2 || $2 != "AVAIL" || !($1 in expected_spare) || seen_spare[$1]++)
            fail("Unexpected or unavailable distributed spare")
        next
    }
    if (NF != 5 || $2 != "ONLINE" || $3 != 0 || $4 != 0 || $5 != 0)
        fail("The pool has unavailable members or errors")
    if ($1 == pool && !root_seen++) next
    if ($1 ~ /^(mirror|raidz[123]|draid[123]:[1-9][0-9]*d:[1-9][0-9]*c:(0|[1-9][0-9]*)s)-[0-9]+$/) {
        group = role SUBSEP (++group_number)
        group_indent = match($0, /[^ \t]/)
        actual_type = $1; sub(/-[0-9]+$/, "", actual_type)
        if (actual_type ~ /^draid/) {
            if (role != "data") fail("dRAID is only supported for data vdevs")
            draid_geometry(actual_type)
            vdev_id = $1; sub(/^.*-/, "", vdev_id)
            draid_groups[group] = 1
            for (spare = 0; spare < draid_spares; spare++) {
                name = "draid" draid_parity "-" vdev_id "-" spare
                if (name in expected_spare) fail("Repeated dRAID vdev identity")
                expected_spare[name] = 1
            }
        }
        next
    }
    if (group != "" && match($0, /[^ \t]/) <= group_indent)
        group = ""
    if (!($1 in expected_role) || seen[$1]++ || expected_role[$1] != role)
        fail("The pool contains an unexpected or missing device role")
    wanted = expected_group[$1]
    actual = group == "" ? (role SUBSEP (role == "log" ? ++group_number : "stripe")) : group
    kind = group == "" ? "stripe" : actual_type
    if (expected_type[wanted] != kind || (actual in group_map && group_map[actual] != wanted) ||
        (wanted in reverse_group && reverse_group[wanted] != actual))
        fail("The pool vdev grouping differs from the policy")
    group_map[actual] = wanted; reverse_group[wanted] = actual
}

END {
    if (failed) exit 1
    if (mode == "cache") {
        cache_pool()
        for (cache_name in cached) print cache_name "\t" cached[cache_name]
    } else if (mode == "compile" || mode == "compile-auto") compile()
    else {
        if (!root_seen || !errors_seen || state_seen != 1) fail("No complete pool status was returned")
        for (device in expected_role) if (!seen[device]) fail("A required pool device is missing")
        for (name in expected_spare) if (!seen_spare[name]) fail("A distributed spare is missing")
        for (group in draid_groups) if (!(group in group_map)) fail("A dRAID vdev has no matching members")
    }
}
