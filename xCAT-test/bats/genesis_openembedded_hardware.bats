#!/usr/bin/env bats
#
# genesis-hardware runs in the OpenEmbedded Genesis image. It lists hardware providers from
# their JSON manifests, runs a provider capability, and writes an audit trail for each
# destructive change. The nvme, mstflint and iprutils providers wrap one tool each. The
# providers, the tools and the sysfs trees here are scratch files.

load 'helpers/shell_source'

HW_FILES='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-hardware-control/files'

setup()
{
    command -v jq >/dev/null || skip 'jq is required'
    DISPATCHER="$(require_repo_file "$HW_FILES/genesis-hardware")"
    root="$BATS_TEST_TMPDIR"
    bin="$root/bin"
    manifests="$root/manifests"
    executables="$root/providers"
    audit="$root/audit/hardware.jsonl"
    request="$root/request.json"
    mkdir -p "$bin" "$manifests" "$executables"

    cat >"$executables/mock" <<'SH'
#!/bin/sh
case "$1" in
    probe)
        printf '%s\n' '{"detected":true,"devices":["controller0"]}'
        ;;
    run)
        case "$2" in
            storage.inventory) printf '%s\n' '{"devices":["controller0"]}' ;;
            storage.array.create) printf '{"created":"%s"}\n' "$3" ;;
            storage.array.delete) printf '%s\n' 'delete failed' >&2; exit 9 ;;
            storage.logs) printf '%s\n' 'not-json' ;;
            *) exit 8 ;;
        esac
        ;;
    *) exit 7 ;;
esac
SH
    chmod 0755 "$executables/mock"
    jq -n '{
        capabilities: [
            {destructive: false, name: "storage.inventory"},
            {destructive: false, name: "storage.logs"},
            {destructive: true, name: "storage.array.create"},
            {destructive: true, name: "storage.array.delete"}
        ],
        kind: "storage", name: "mock", schema: 1, version: "1.0"
    }' >"$manifests/mock.json"
    printf '{"level":"1"}\n' >"$request"

    export PATH="$bin:$PATH"
    export XCAT_GENESIS_HARDWARE_AUDIT="$audit"
    export XCAT_GENESIS_PROVIDER_DIR="$manifests"
    export XCAT_GENESIS_PROVIDER_EXEC_DIR="$executables"
    export XCAT_GENESIS_PROVIDER_TIMEOUT=5
}

hardware()
{
    run /bin/bash "$DISPATCHER" "$@"
}

create_array()
{
    hardware run mock storage.array.create "$@"
}

audit_phases()
{
    jq -r .phase "$audit" | paste -sd' '
}

@test "the provider list returns the manifest" {
    hardware providers
    [ "$status" -eq 0 ]
    [ "$(jq -r '.providers[0].name' <<<"$output")" = mock ]
}

@test "the provider capabilities are returned" {
    hardware capabilities mock
    [ "$status" -eq 0 ]
    [ "$(jq '.capabilities | length' <<<"$output")" -eq 4 ]
}

@test "a provider probe returns the detected hardware" {
    hardware probe mock
    [ "$status" -eq 0 ]
    [ "$(jq '.probes[0].result.detected' <<<"$output")" = true ]
}

@test "a read-only capability succeeds, is normalized, and is not audited as a change" {
    hardware run mock storage.inventory
    [ "$status" -eq 0 ]
    [ "$(jq -r '.result.devices[0]' <<<"$output")" = controller0 ]
    [ ! -e "$audit" ]
}

@test "a destructive capability requires a task identity, an exact device and a request" {
    create_array
    [ "$status" -ne 0 ]
    [[ "$output" == *'destructive capability requires a task identity'* ]]
    create_array --task-id task-1 --request "$request"
    [ "$status" -ne 0 ]
    [[ "$output" == *'destructive capability requires an exact device identity'* ]]
    create_array --task-id task-1 --device-id controller0
    [ "$status" -ne 0 ]
    [[ "$output" == *'destructive capability requires a request file'* ]]
    create_array --task-id task-1 --device-id all --request "$request"
    [ "$status" -ne 0 ]
    [[ "$output" == *'destructive capability requires an exact device identity'* ]]
}

@test "an authorized destructive capability succeeds with a closed audit trail" {
    create_array --task-id task-1 --device-id controller0 --request "$request"
    [ "$status" -eq 0 ]
    [ "$(jq -r '.result.created' <<<"$output")" = controller0 ]
    [ "$(audit_phases)" = 'started completed' ]
    [ "$(head -n1 "$audit" | jq -r .task_id)" = task-1 ]
    head -n1 "$audit" | jq -r .request_sha256 | grep -Eqx '[0-9a-f]{64}'
}

@test "a provider failure is returned, and the failed change has a closed audit trail" {
    create_array --task-id task-1 --device-id controller0 --request "$request"
    hardware run mock storage.array.delete --task-id task-2 --device-id controller0 --request "$request"
    [ "$status" -ne 0 ]
    [[ "$output" == *'provider mock failed capability storage.array.delete'* ]]
    [ "$(audit_phases)" = 'started completed started failed' ]
}

@test "invalid provider JSON and an undeclared capability are rejected" {
    hardware run mock storage.logs
    [ "$status" -ne 0 ]
    [[ "$output" == *'provider mock returned invalid JSON'* ]]
    hardware run mock storage.unknown
    [ "$status" -ne 0 ]
    [[ "$output" == *'provider mock does not support storage.unknown'* ]]
}

@test "a linked or invalid provider manifest is rejected" {
    # The target is a valid manifest for "linked", so only the link itself is wrong.
    jq '.name = "linked"' "$manifests/mock.json" >"$root/linked.json"
    ln -s "$root/linked.json" "$manifests/linked.json"
    hardware providers
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid provider manifest: linked'* ]]
    rm "$manifests/linked.json"
    printf '{}\n' >"$manifests/invalid.json"
    hardware providers
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid provider manifest: invalid'* ]]
}

@test "a linked provider executable is rejected" {
    mv "$executables/mock" "$executables/mock.real"
    ln -s "$executables/mock.real" "$executables/mock"
    hardware probe mock
    [ "$status" -ne 0 ]
    [[ "$output" == *'provider executable not found: mock'* ]]
}

@test "a linked hardware request is rejected" {
    ln -s "$request" "$root/linked-request.json"
    create_array --task-id task-3 --device-id controller0 --request "$root/linked-request.json"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid request file: $root/linked-request.json"* ]]
}

@test "an invalid provider timeout is rejected" {
    XCAT_GENESIS_PROVIDER_TIMEOUT=0 hardware providers
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid provider timeout'* ]]
}

@test "a linked audit lock is rejected, and its target is untouched" {
    mkdir -p "$(dirname "$audit")"
    printf 'unchanged\n' >"$root/lock-target"
    ln -s "$root/lock-target" "$audit.lock"
    create_array --task-id task-3 --device-id controller0 --request "$request"
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid hardware audit lock'* ]]
    [ "$(cat "$root/lock-target")" = unchanged ]
}

@test "the NVMe provider returns exact controllers and queries the selected one" {
    provider="$(require_repo_file "$HW_FILES/provider-nvme")"
    printf '#!/bin/sh\nprintf "{\\"arguments\\":\\"%%s\\"}\\n" "$*"\n' >"$bin/nvme"
    chmod 0755 "$bin/nvme"
    mkdir -p "$root/sys/class/nvme/nvme0" "$root/dev"
    : >"$root/dev/nvme0"
    export XCAT_GENESIS_DEV_DIR="$root/dev" XCAT_GENESIS_SYS_CLASS_NVME="$root/sys/class/nvme"

    run /bin/bash "$provider" probe
    [ "$status" -eq 0 ]
    [ "$(jq -r '.devices[0]' <<<"$output")" = nvme0 ]

    run /bin/bash "$provider" run storage.health nvme0 -
    [ "$status" -eq 0 ]
    jq -r .arguments <<<"$output" | grep -Eq 'smart-log .*/nvme0 -o json'

    run /bin/bash "$provider" run storage.health nvme0n1 -
    [ "$status" -ne 0 ]
    [[ "$output" == *'invalid NVMe controller identity'* ]]
}

@test "the mstflint provider returns Mellanox devices only, with the tool output" {
    provider="$(require_repo_file "$HW_FILES/provider-mstflint")"
    printf '#!/bin/sh\nprintf "%%s\\n" "firmware query"\n' >"$bin/mstflint"
    chmod 0755 "$bin/mstflint"
    pci="$root/sys/bus/pci/devices"
    mkdir -p "$pci/0000:03:00.0" "$pci/0000:04:00.0"
    printf '0x15b3\n' >"$pci/0000:03:00.0/vendor"
    printf '0x8086\n' >"$pci/0000:04:00.0/vendor"
    export XCAT_GENESIS_SYS_PCI_DEVICES="$pci"

    run /bin/bash "$provider" probe
    [ "$status" -eq 0 ]
    [ "$(jq -c .devices <<<"$output")" = '["0000:03:00.0"]' ]

    run /bin/bash "$provider" run network.firmware.inventory 0000:03:00.0 -
    [ "$status" -eq 0 ]
    [ "$(jq -r .raw <<<"$output")" = 'firmware query' ]

    run /bin/bash "$provider" run network.firmware.inventory 0000:04:00.0 -
    [ "$status" -ne 0 ]
    [[ "$output" == *'device is not NVIDIA or Mellanox: 0000:04:00.0'* ]]
}

@test "the iprutils provider returns Power RAID hosts, the tool output, and rejects changes" {
    provider="$(require_repo_file "$HW_FILES/provider-iprutils")"
    cat >"$bin/iprconfig" <<'SH'
#!/bin/sh
case "$*" in
    '-c show-config') printf '%s\n' 'Power RAID configuration' ;;
    '-c show-arrays') printf '%s\n' 'Power RAID arrays healthy' ;;
    '-c show-ucode-levels') printf '%s\n' 'Power RAID firmware levels' ;;
    *) exit 2 ;;
esac
SH
    chmod 0755 "$bin/iprconfig"
    hosts="$root/sys/class/scsi_host"
    mkdir -p "$hosts/host0" "$hosts/host1"
    printf 'ipr\n' >"$hosts/host0/proc_name"
    printf 'megaraid_sas\n' >"$hosts/host1/proc_name"
    export XCAT_GENESIS_SYS_SCSI_HOSTS="$hosts"

    run /bin/bash "$provider" probe
    [ "$status" -eq 0 ]
    [ "$(jq -c .devices <<<"$output")" = '["host0"]' ]

    for pair in 'storage.inventory:Power RAID configuration' \
        'storage.health:Power RAID arrays healthy' \
        'storage.firmware.inventory:Power RAID firmware levels'; do
        run /bin/bash "$provider" run "${pair%%:*}" host0 -
        [ "$status" -eq 0 ]
        [ "$(jq -r .raw <<<"$output")" = "${pair#*:}" ]
    done

    run /bin/bash "$provider" run storage.array.create host0 -
    [ "$status" -ne 0 ]
    [[ "$output" == *'unsupported capability: storage.array.create'* ]]
}
