// SPDX-License-Identifier: EPL-1.0

#include "console.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/utsname.h>
#include <unistd.h>

struct component_status {
    bool valid;
    char state[32];
    char detail[DETAIL_SIZE];
    char code[64];
    char recovery[DETAIL_SIZE];
    char node_name[64];
    char action[64];
    char target[VALUE_SIZE];
    unsigned long long started_seconds;
    unsigned long long updated_seconds;
    unsigned long long verified_seconds;
    unsigned int attempt;
    unsigned int attempt_limit;
    unsigned int next_retry_seconds;
    unsigned int progress_percent;
    bool has_verified_seconds;
    bool has_attempt;
    bool has_attempt_limit;
    bool has_next_retry_seconds;
    bool has_progress_percent;
};

static bool known_state(const char *state) {
    static const char *states[] = {"STARTING",         "IDLE",
                                   "WAITING_FOR_LINK", "CONFIGURING_NETWORK",
                                   "CONTACTING_XCAT",  "ACTION_RECEIVED",
                                   "RUNNING",          "READY",
                                   "DEGRADED",         "FAILED"};
    size_t index;

    for (index = 0; index < sizeof(states) / sizeof(states[0]); index++) {
        if (strcmp(state, states[index]) == 0)
            return true;
    }
    return false;
}

static struct component_status read_component_status(const char *component) {
    struct component_status status = {0};
    const char *directory = xcat_path_from_env("XCAT_STATUS_DIR", "/run/xcat/status");
    char path[VALUE_SIZE];
    char schema[8];
    unsigned long long number;

    if (!xcat_safe_name(component))
        return status;
    snprintf(path, sizeof(path), "%s/%s.env", directory, component);
    if (!xcat_read_key(path, "SCHEMA", schema, sizeof(schema)) || strcmp(schema, "1") != 0 ||
        !xcat_read_key(path, "STATE", status.state, sizeof(status.state)) ||
        !known_state(status.state) ||
        !xcat_read_unsigned_key(path, "UPDATED_SECONDS", &status.updated_seconds))
        return status;
    if (!xcat_read_unsigned_key(path, "STARTED_SECONDS", &status.started_seconds))
        status.started_seconds = status.updated_seconds;
    if (!xcat_read_key(path, "DETAIL", status.detail, sizeof(status.detail)))
        status.detail[0] = '\0';
    xcat_read_key(path, "CODE", status.code, sizeof(status.code));
    xcat_read_key(path, "RECOVERY", status.recovery, sizeof(status.recovery));
    xcat_read_key(path, "NODE_NAME", status.node_name, sizeof(status.node_name));
    xcat_read_key(path, "ACTION", status.action, sizeof(status.action));
    xcat_read_key(path, "TARGET", status.target, sizeof(status.target));
    status.has_verified_seconds =
        xcat_read_unsigned_key(path, "VERIFIED_SECONDS", &status.verified_seconds);
    status.has_attempt = xcat_read_unsigned_key(path, "ATTEMPT", &number) && number <= UINT_MAX;
    if (status.has_attempt)
        status.attempt = (unsigned int)number;
    status.has_attempt_limit =
        xcat_read_unsigned_key(path, "ATTEMPT_LIMIT", &number) && number <= UINT_MAX;
    if (status.has_attempt_limit)
        status.attempt_limit = (unsigned int)number;
    status.has_next_retry_seconds =
        xcat_read_unsigned_key(path, "NEXT_RETRY_SECONDS", &number) && number <= UINT_MAX;
    if (status.has_next_retry_seconds)
        status.next_retry_seconds = (unsigned int)number;
    status.has_progress_percent =
        xcat_read_unsigned_key(path, "PROGRESS_PERCENT", &number) && number <= 100;
    if (status.has_progress_percent)
        status.progress_percent = (unsigned int)number;
    status.valid = true;
    return status;
}

static bool component_has_state(const struct component_status *component, const char *state) {
    return component->valid && strcmp(component->state, state) == 0;
}

static void select_overall_status(struct console_state *state,
                                  const struct component_status *network,
                                  const struct component_status *extensions,
                                  const struct component_status *registration,
                                  const struct component_status *action, bool xcat_configured,
                                  unsigned long long uptime) {
    const struct component_status *selected = NULL;
    const struct component_status *failure_candidates[] = {network, extensions, registration};

    for (size_t index = 0; index < sizeof(failure_candidates) / sizeof(failure_candidates[0]);
         index++) {
        if (component_has_state(failure_candidates[index], "FAILED")) {
            selected = failure_candidates[index];
            break;
        }
    }

    if (selected == NULL) {
        if (action->valid)
            selected = action;
        else if (registration->valid)
            selected = registration;
        else if (component_has_state(network, "READY") && xcat_configured) {
            xcat_set_text(state->state, sizeof(state->state), "STARTING");
            xcat_set_text(state->activity, sizeof(state->activity), "Starting xCAT registration");
            xcat_format_duration(
                uptime >= network->updated_seconds ? uptime - network->updated_seconds : 0,
                state->stage_time, sizeof(state->stage_time));
            return;
        } else if (network->valid)
            selected = network;
    }

    if (selected != NULL) {
        xcat_set_text(state->state, sizeof(state->state), "%s", selected->state);
        xcat_set_text(state->activity, sizeof(state->activity), "%s",
                      selected->detail[0] != '\0' ? selected->detail : "No detail");
        if (strcmp(selected->state, "FAILED") == 0)
            xcat_set_text(state->error, sizeof(state->error), "%s%s%s", selected->code,
                          selected->code[0] != '\0' ? ": " : "", selected->detail);
        xcat_set_text(state->recovery, sizeof(state->recovery), "%s", selected->recovery);
        xcat_format_duration(
            uptime >= selected->started_seconds ? uptime - selected->started_seconds : 0,
            state->stage_time, sizeof(state->stage_time));
        if (selected->has_progress_percent) {
            xcat_set_text(state->progress, sizeof(state->progress), "%u%%",
                          selected->progress_percent);
        } else if (selected->has_attempt && selected->has_attempt_limit) {
            unsigned int retry_remaining = 0;
            unsigned long long update_age =
                uptime >= selected->updated_seconds ? uptime - selected->updated_seconds : 0;

            if (selected->has_next_retry_seconds && update_age < selected->next_retry_seconds)
                retry_remaining = selected->next_retry_seconds - (unsigned int)update_age;
            if (retry_remaining > 0)
                xcat_set_text(state->progress, sizeof(state->progress),
                              "Attempt %u of %u; retry in %us", selected->attempt,
                              selected->attempt_limit, retry_remaining);
            else
                xcat_set_text(state->progress, sizeof(state->progress), "Attempt %u of %u",
                              selected->attempt, selected->attempt_limit);
        }
    } else if (xcat_configured) {
        xcat_set_text(state->state, sizeof(state->state), "STARTING");
        xcat_set_text(state->activity, sizeof(state->activity), "Waiting for Genesis services");
        xcat_format_duration(uptime, state->stage_time, sizeof(state->stage_time));
    } else {
        xcat_set_text(state->state, sizeof(state->state), "IDLE");
        xcat_set_text(state->activity, sizeof(state->activity), "No xCAT endpoint configured");
        xcat_format_duration(uptime, state->stage_time, sizeof(state->stage_time));
    }
}

static void set_component_details(const struct component_status *component, char *state,
                                  size_t state_size, char *detail, size_t detail_size) {
    if (!component->valid) {
        xcat_set_text(state, state_size, "unavailable");
        xcat_set_text(detail, detail_size, "No status record");
        return;
    }

    xcat_set_text(state, state_size, "%s", component->state);
    xcat_set_text(detail, detail_size, "%s",
                  component->detail[0] != '\0' ? component->detail : "No detail");
}

static void normalize_network_method(char *method, size_t size, const char *address) {
    if (strcmp(method, "auto") == 0 || strcmp(method, "automatic") == 0 ||
        strcmp(method, "dhcp") == 0) {
        xcat_set_text(method, size, "%s", strchr(address, ':') != NULL ? "SLAAC/DHCPv6" : "DHCP");
    } else if (strcmp(method, "static") == 0 || strcmp(method, "manual") == 0) {
        xcat_set_text(method, size, "Static");
    }
}

static void set_boot_loader(const char *cmdline, char *loader, size_t size) {
    char value[32];

    if (xcat_cmdline_value(cmdline, "xcat.bootloader", value, sizeof(value))) {
        if (strcmp(value, "xnba") == 0)
            xcat_set_text(loader, size, "xNBA");
        else if (strcmp(value, "pxelinux") == 0)
            xcat_set_text(loader, size, "PXELINUX");
        else if (strcmp(value, "elilo") == 0)
            xcat_set_text(loader, size, "ELILO");
        else
            xcat_set_text(loader, size, "unrecognized");
    } else if (xcat_cmdline_value(cmdline, "BOOTIF", value, sizeof(value))) {
        xcat_set_text(loader, size, "PXE (unknown loader)");
    } else {
        xcat_set_text(loader, size, "not reported");
    }
}

static bool useful_identity(const char *value) {
    return value[0] != '\0' && strcmp(value, "None") != 0 && strcmp(value, "Not Specified") != 0 &&
           strcmp(value, "To be filled by O.E.M.") != 0 && strcmp(value, "not reported") != 0 &&
           strcmp(value, "unknown") != 0;
}

static void split_action(const char *destiny, char *action, size_t action_size, char *target,
                         size_t target_size) {
    const char *separator = strchr(destiny, '=');
    const char *space = strpbrk(destiny, " \t");

    if (separator == NULL || (space != NULL && space < separator))
        separator = space;
    if (separator == NULL) {
        xcat_set_text(action, action_size, "%s", destiny);
        target[0] = '\0';
        return;
    }
    snprintf(action, action_size, "%.*s", (int)(separator - destiny), destiny);
    do {
        separator++;
    } while (*separator == ' ' || *separator == '\t' || *separator == '=');
    xcat_copy_printable(target, target_size, separator);
}

static void describe_action(const char *action, char *description, size_t size) {
    const char *label = action;

    if (strcmp(action, "discover") == 0)
        label = "Discover hardware";
    else if (strcmp(action, "standby") == 0)
        label = "Wait for xCAT";
    else if (strcmp(action, "shell") == 0)
        label = "Maintenance wait";
    else if (strcmp(action, "osimage") == 0)
        label = "Boot assigned image";
    else if (strcmp(action, "ondiscover") == 0)
        label = "Complete discovery chain";
    else if (strcmp(action, "install") == 0)
        label = "Install assigned image";
    else if (strcmp(action, "netboot") == 0)
        label = "Boot stateless image";
    else if (strcmp(action, "statelite") == 0)
        label = "Boot statelite image";
    else if (strcmp(action, "boot") == 0 || strcmp(action, "reboot") == 0)
        label = "Reboot node";
    else if (strcmp(action, "shutdown") == 0)
        label = "Power off node";
    else if (strcmp(action, "configraid") == 0)
        label = "Configure storage";
    else if (strcmp(action, "runcmd") == 0)
        label = "Run command";
    else if (strcmp(action, "runimage") == 0)
        label = "Run service image";
    xcat_set_text(description, size, "%s", label);
}

void xcat_load_console_state(struct console_state *state) {
    const char *cmdline_path = xcat_path_from_env("XCAT_CMDLINE_FILE", "/proc/cmdline");
    const char *os_release = xcat_path_from_env("XCAT_OS_RELEASE", "/etc/os-release");
    const char *genesis_env = xcat_path_from_env("XCAT_STATE_FILE", "/run/xcat/genesis.env");
    const char *destiny_file = xcat_path_from_env("XCAT_DESTINY_FILE", "/run/xcat/destiny");
    const char *response_file =
        xcat_path_from_env("XCAT_RESPONSE_FILE", "/run/xcat/xcat-response.env");
    const char *sys_root = xcat_path_from_env("XCAT_SYS_ROOT", "/sys");
    const char *proc_root = xcat_path_from_env("XCAT_PROC_ROOT", "/proc");
    const char *extension_dir = xcat_path_from_env("XCAT_EXTENSION_DIR", "/run/extensions");
    const char *provider_dir =
        xcat_path_from_env("XCAT_PROVIDER_DIR", "/usr/share/xcat/genesis/providers");
    struct component_status network = read_component_status("network");
    struct component_status extensions = read_component_status("extensions");
    struct component_status registration = read_component_status("registration");
    struct component_status action = read_component_status("action");
    struct utsname system_name;
    unsigned long long uptime = xcat_read_uptime();
    char *cmdline = xcat_read_allocated_line(cmdline_path);
    const char *cmdline_text = cmdline != NULL ? cmdline : "";
    char value[VALUE_SIZE] = "";
    char path[VALUE_SIZE * 2];
    char release_name[64] = "xCAT Genesis";
    char release_version[32] = "";
    bool xcat_configured;
    bool interface_selected;

    memset(state, 0, sizeof(*state));
    xcat_configured = xcat_cmdline_value(cmdline_text, "xcatd", state->xcat_endpoint,
                                         sizeof(state->xcat_endpoint));
    set_component_details(&network, state->network_state, sizeof(state->network_state),
                          state->network_detail, sizeof(state->network_detail));
    set_component_details(&extensions, state->extension_state, sizeof(state->extension_state),
                          state->extension_detail, sizeof(state->extension_detail));
    set_component_details(&registration, state->registration_state,
                          sizeof(state->registration_state), state->registration_detail,
                          sizeof(state->registration_detail));
    set_component_details(&action, state->action_state, sizeof(state->action_state),
                          state->action_detail, sizeof(state->action_detail));

    if (gethostname(state->local_hostname, sizeof(state->local_hostname)) != 0)
        xcat_set_text(state->local_hostname, sizeof(state->local_hostname), "unknown");
    state->local_hostname[sizeof(state->local_hostname) - 1] = '\0';
    xcat_copy_printable(value, sizeof(value), state->local_hostname);
    xcat_set_text(state->local_hostname, sizeof(state->local_hostname), "%s", value);
    if (registration.node_name[0] != '\0')
        xcat_set_text(state->node, sizeof(state->node), "%s", registration.node_name);
    else if (!xcat_read_key(response_file, "XCAT_NODE_NAME", state->node, sizeof(state->node)) ||
             state->node[0] == '\0')
        xcat_set_text(state->node, sizeof(state->node), "unassigned");

    if (xcat_read_key(os_release, "NAME", value, sizeof(value)))
        xcat_set_text(release_name, sizeof(release_name), "%s", value);
    if (xcat_read_key(os_release, "VERSION_ID", value, sizeof(value)))
        xcat_set_text(release_version, sizeof(release_version), "%s", value);
    xcat_set_text(state->release, sizeof(state->release), "%s%s%s", release_name,
                  release_version[0] != '\0' ? " " : "", release_version);

    if (uname(&system_name) == 0) {
        xcat_set_text(state->architecture, sizeof(state->architecture), "%s", system_name.machine);
        xcat_set_text(state->kernel, sizeof(state->kernel), "%s", system_name.release);
    } else {
        xcat_set_text(state->architecture, sizeof(state->architecture), "unknown");
        xcat_set_text(state->kernel, sizeof(state->kernel), "unknown");
    }

    snprintf(path, sizeof(path), "%s/firmware/efi", sys_root);
    if (strncmp(state->architecture, "ppc64", 5) == 0) {
        snprintf(path, sizeof(path), "%s/device-tree/ibm,opal", proc_root);
        xcat_set_text(state->firmware, sizeof(state->firmware), "%s",
                      access(path, F_OK) == 0 ? "OPAL" : "PAPR");
    } else if (strncmp(state->architecture, "arm", 3) == 0 ||
               strcmp(state->architecture, "aarch64") == 0) {
        snprintf(path, sizeof(path), "%s/firmware/efi", sys_root);
        xcat_set_text(state->firmware, sizeof(state->firmware), "%s",
                      access(path, F_OK) == 0 ? "UEFI" : "Device Tree");
    } else if (strncmp(state->architecture, "riscv", 5) == 0) {
        xcat_set_text(state->firmware, sizeof(state->firmware), "OpenSBI");
    } else {
        snprintf(path, sizeof(path), "%s/firmware/efi", sys_root);
        xcat_set_text(state->firmware, sizeof(state->firmware), "%s",
                      access(path, F_OK) == 0 ? "UEFI" : "BIOS");
    }
    set_boot_loader(cmdline_text, state->boot_method, sizeof(state->boot_method));

    snprintf(path, sizeof(path), "%s/class/dmi/id/product_serial", sys_root);
    xcat_read_line(path, state->serial, sizeof(state->serial));
    if (!useful_identity(state->serial)) {
        snprintf(path, sizeof(path), "%s/firmware/devicetree/base/serial-number", sys_root);
        xcat_read_line(path, state->serial, sizeof(state->serial));
    }
    if (!useful_identity(state->serial)) {
        snprintf(path, sizeof(path), "%s/device-tree/system-id", proc_root);
        xcat_read_line(path, state->serial, sizeof(state->serial));
    }
    if (!useful_identity(state->serial))
        xcat_set_text(state->serial, sizeof(state->serial), "not reported");
    snprintf(path, sizeof(path), "%s/class/dmi/id/product_uuid", sys_root);
    if (!xcat_read_line(path, state->uuid, sizeof(state->uuid)) || !useful_identity(state->uuid))
        xcat_set_text(state->uuid, sizeof(state->uuid), "not reported");

    interface_selected =
        xcat_read_key(genesis_env, "XCAT_INTERFACE", state->interface, sizeof(state->interface));
    if (!xcat_read_key(genesis_env, "XCAT_SOURCE_PREFIXED_ADDRESS", state->address,
                       sizeof(state->address)))
        xcat_read_key(genesis_env, "XCAT_SOURCE_ADDRESS", state->address, sizeof(state->address));
    xcat_read_key(genesis_env, "XCAT_GATEWAY", state->gateway, sizeof(state->gateway));
    xcat_read_key(genesis_env, "XCAT_DNS_SERVERS", state->dns, sizeof(state->dns));
    xcat_read_key(genesis_env, "XCAT_NETWORK_METHOD", state->network_method,
                  sizeof(state->network_method));
    xcat_read_key(genesis_env, "XCAT_LINK_STATE", state->link_state, sizeof(state->link_state));
    xcat_read_key(genesis_env, "XCAT_MAC_ADDRESS", state->mac, sizeof(state->mac));
    if (xcat_read_key(genesis_env, "XCATDEST", value, sizeof(value))) {
        xcat_set_text(state->xcat_endpoint, sizeof(state->xcat_endpoint), "%s", value);
        xcat_configured = true;
    }
    if (state->interface[0] == '\0')
        xcat_set_text(state->interface, sizeof(state->interface), "waiting");
    if (state->address[0] == '\0')
        xcat_set_text(state->address, sizeof(state->address), "waiting");
    if (state->gateway[0] == '\0')
        xcat_set_text(state->gateway, sizeof(state->gateway), "not reported");
    if (state->dns[0] == '\0')
        xcat_set_text(state->dns, sizeof(state->dns), "not reported");
    if (state->network_method[0] == '\0')
        xcat_set_text(state->network_method, sizeof(state->network_method), "%s",
                      xcat_cmdline_value(cmdline_text, "hostip", value, sizeof(value)) ||
                              xcat_cmdline_value(cmdline_text, "ipaddr", value, sizeof(value))
                          ? "static"
                          : "automatic");
    normalize_network_method(state->network_method, sizeof(state->network_method), state->address);

    if (interface_selected && xcat_safe_name(state->interface)) {
        snprintf(path, sizeof(path), "%s/class/net/%s/operstate", sys_root, state->interface);
        if (state->link_state[0] == '\0' &&
            !xcat_read_line(path, state->link_state, sizeof(state->link_state)))
            xcat_set_text(state->link_state, sizeof(state->link_state), "unknown");
        snprintf(path, sizeof(path), "%s/class/net/%s/address", sys_root, state->interface);
        if (state->mac[0] == '\0' && !xcat_read_line(path, state->mac, sizeof(state->mac)))
            xcat_set_text(state->mac, sizeof(state->mac), "unknown");
    } else {
        xcat_set_text(state->link_state, sizeof(state->link_state), "waiting");
        xcat_set_text(state->mac, sizeof(state->mac), "unknown");
    }

    if (action.action[0] != '\0') {
        xcat_set_text(state->action_code, sizeof(state->action_code), "%s", action.action);
        xcat_set_text(state->target, sizeof(state->target), "%s", action.target);
    } else if (registration.action[0] != '\0') {
        xcat_set_text(state->action_code, sizeof(state->action_code), "%s", registration.action);
        xcat_set_text(state->target, sizeof(state->target), "%s", registration.target);
    } else if (xcat_read_line(destiny_file, value, sizeof(value)) ||
               xcat_cmdline_value(cmdline_text, "destiny", value, sizeof(value))) {
        split_action(value, state->action_code, sizeof(state->action_code), state->target,
                     sizeof(state->target));
    }
    if (state->action_code[0] == '\0')
        xcat_set_text(state->action_code, sizeof(state->action_code), "waiting");
    describe_action(state->action_code, state->action, sizeof(state->action));
    if (state->target[0] == '\0')
        xcat_set_text(state->target, sizeof(state->target), "none");

    if (registration.valid && strcmp(registration.state, "ACTION_RECEIVED") == 0)
        xcat_set_text(state->xcat_state, sizeof(state->xcat_state), "Action received");
    else if (registration.valid && strcmp(registration.state, "CONTACTING_XCAT") == 0)
        xcat_set_text(state->xcat_state, sizeof(state->xcat_state), "Contacting");
    else if (registration.valid && strcmp(registration.state, "FAILED") == 0)
        xcat_set_text(state->xcat_state, sizeof(state->xcat_state), "Failed");
    else if (network.valid && strcmp(network.state, "READY") == 0)
        xcat_set_text(state->xcat_state, sizeof(state->xcat_state), "Network ready");
    else if (xcat_configured)
        xcat_set_text(state->xcat_state, sizeof(state->xcat_state), "Waiting");
    else
        xcat_set_text(state->xcat_state, sizeof(state->xcat_state), "Not configured");

    state->extensions = xcat_list_files(extension_dir, ".raw", state->extension_names,
                                        sizeof(state->extension_names));
    state->providers = xcat_list_files(provider_dir, ".json", state->provider_names,
                                       sizeof(state->provider_names));
    if (state->extension_names[0] == '\0')
        xcat_set_text(state->extension_names, sizeof(state->extension_names), "none");
    if (state->provider_names[0] == '\0')
        xcat_set_text(state->provider_names, sizeof(state->provider_names), "none");
    free(cmdline);
    select_overall_status(state, &network, &extensions, &registration, &action, xcat_configured,
                          uptime);
}

static void format_xcat_status(const struct console_state *state, char *text, size_t size) {
    if (strcmp(state->xcat_state, "Failed") == 0 &&
        strcmp(state->registration_detail, "No status record") != 0)
        xcat_set_text(text, size, "%s: %s", state->xcat_state, state->registration_detail);
    else
        xcat_set_text(text, size, "%s", state->xcat_state);
}

static void set_status_field(struct status_view *view, enum status_field field, const char *label,
                             const char *value) {
    xcat_set_text(view->fields[field].label, sizeof(view->fields[field].label), "%s", label);
    xcat_set_text(view->fields[field].value, sizeof(view->fields[field].value), "%s", value);
}

void xcat_build_status_view(const struct console_state *state, struct status_view *view) {
    char xcat_status[DETAIL_SIZE];
    const char *identity;
    bool show_serial;

    memset(view, 0, sizeof(*view));
    identity = strcmp(state->node, "unassigned") != 0 && state->node[0] != '\0'
                   ? state->node
                   : state->local_hostname;
    show_serial = useful_identity(state->serial) && strcmp(state->serial, "not reported") != 0;
    if (show_serial)
        xcat_set_text(view->identity, sizeof(view->identity), "%s | %s", identity, state->serial);
    else
        xcat_set_text(view->identity, sizeof(view->identity), "%s", identity);

    format_xcat_status(state, xcat_status, sizeof(xcat_status));
    set_status_field(view, STATUS_FIELD_STATE, "State", state->state);
    set_status_field(view, STATUS_FIELD_STAGE_TIME, "In stage", state->stage_time);
    set_status_field(view, STATUS_FIELD_ACTIVITY, "Activity", state->activity);
    set_status_field(view, STATUS_FIELD_NODE, "Node", state->node);
    set_status_field(view, STATUS_FIELD_SERIAL, "Serial", state->serial);
    set_status_field(view, STATUS_FIELD_INTERFACE, "Interface", state->interface);
    set_status_field(view, STATUS_FIELD_LINK, "Link", state->link_state);
    set_status_field(view, STATUS_FIELD_METHOD, "Method", state->network_method);
    set_status_field(view, STATUS_FIELD_ADDRESS, "Address", state->address);
    set_status_field(view, STATUS_FIELD_MAC, "MAC", state->mac);
    set_status_field(view, STATUS_FIELD_XCAT_SERVER, "xCAT server",
                     state->xcat_endpoint[0] != '\0' ? state->xcat_endpoint : "none");
    set_status_field(view, STATUS_FIELD_XCAT_STATUS, "xCAT contact", xcat_status);
    set_status_field(view, STATUS_FIELD_ACTION, "Action", state->action);
    if (state->error[0] != '\0') {
        set_status_field(view, STATUS_FIELD_DETAIL_ONE, "Error", state->error);
        set_status_field(view, STATUS_FIELD_DETAIL_TWO, "Recovery",
                         state->recovery[0] != '\0' ? state->recovery : "See diagnostics");
    } else {
        set_status_field(view, STATUS_FIELD_DETAIL_ONE, "Target", state->target);
        set_status_field(view, STATUS_FIELD_DETAIL_TWO, "Progress",
                         state->progress[0] != '\0' ? state->progress : "none");
    }

    if (strcmp(state->state, "FAILED") == 0)
        view->severity = STATUS_SEVERITY_ERROR;
    else if (strcmp(state->state, "DEGRADED") == 0)
        view->severity = STATUS_SEVERITY_WARNING;
    else
        view->severity = STATUS_SEVERITY_NORMAL;
}

bool xcat_status_view_changed(const struct status_view *previous,
                              const struct status_view *current) {
    enum status_field field;

    if (previous->severity != current->severity ||
        strcmp(previous->identity, current->identity) != 0)
        return true;
    for (field = STATUS_FIELD_STATE; field < STATUS_FIELD_COUNT; field++) {
        if (field == STATUS_FIELD_STAGE_TIME)
            continue;
        if (strcmp(previous->fields[field].label, current->fields[field].label) != 0 ||
            strcmp(previous->fields[field].value, current->fields[field].value) != 0)
            return true;
    }
    return false;
}

void xcat_format_diagnostics(const struct console_state *state, char *text, size_t size) {
    snprintf(text, size,
             "Identity\n\n"
             "  Node: %s\n"
             "  Local hostname: %s\n"
             "  Serial: %s\n"
             "  UUID: %s\n"
             "\nSystem\n\n"
             "  Release: %s\n"
             "  Architecture: %s\n"
             "  Kernel: %s\n"
             "  Firmware: %s\n"
             "  Boot loader: %s\n"
             "\nManagement network\n\n"
             "  State: %s\n"
             "  Detail: %s\n"
             "  Interface: %s\n"
             "  Link: %s\n"
             "  Method: %s\n"
             "  Address: %s\n"
             "  MAC: %s\n"
             "  Gateway: %s\n"
             "  DNS: %s\n"
             "\nxCAT\n\n"
             "  State: %s\n"
             "  Detail: %s\n"
             "  Server: %s\n"
             "\nAction\n\n"
             "  Name: %s\n"
             "  Code: %s\n"
             "  State: %s\n"
             "  Detail: %s\n"
             "  Target: %s\n"
             "\nRuntime\n\n"
             "  Extension state: %s\n"
             "  Extension detail: %s\n"
             "  Extensions: %u\n"
             "  Extension names: %s\n"
             "  Providers: %u\n"
             "  Provider names: %s",
             state->node, state->local_hostname, state->serial, state->uuid, state->release,
             state->architecture, state->kernel, state->firmware, state->boot_method,
             state->network_state, state->network_detail, state->interface, state->link_state,
             state->network_method, state->address, state->mac, state->gateway, state->dns,
             state->registration_state, state->registration_detail,
             state->xcat_endpoint[0] != '\0' ? state->xcat_endpoint : "none", state->action,
             state->action_code, state->action_state, state->action_detail, state->target,
             state->extension_state, state->extension_detail, state->extensions,
             state->extension_names, state->providers, state->provider_names);
}
