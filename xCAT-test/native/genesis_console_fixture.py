"""Private filesystem paths for Genesis console tests."""


def console_paths(root):
    return {
        "XCAT_" + name: str(root / name.lower())
        for name in ("CMDLINE_FILE", "UPTIME_FILE", "OS_RELEASE", "STATUS_DIR", "STATE_FILE",
                     "DESTINY_FILE", "RESPONSE_FILE", "SYS_ROOT", "PROC_ROOT", "EXTENSION_DIR", "PROVIDER_DIR")
    }
