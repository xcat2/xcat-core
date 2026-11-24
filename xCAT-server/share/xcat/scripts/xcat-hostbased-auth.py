"""Configure host-based authentication over an already authenticated SSH connection."""

from contextlib import suppress
import fcntl
import glob
import ipaddress
import json
import os
from pathlib import Path
import pwd
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile


KEYSIGN_PATHS = ("/usr/libexec/openssh/ssh-keysign", "/usr/lib/openssh/ssh-keysign")
DROPIN_NAME = "01-xcat-hostbased-auth.conf"
DROPIN_HEADER = "# Written by xCAT mkhostbased-auth. Do not edit.\n"


def run(*args):
    result = subprocess.run(
        args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, timeout=20
    )
    if result.returncode:
        raise ValueError(result.stderr.strip() or f"{args[0]} returned {result.returncode}")
    return result.stdout


def ssh_address():
    connection = os.environ.get("SSH_CONNECTION", "").split()
    if len(connection) != 4:
        raise ValueError("Cannot determine this node's SSH address")
    address = ipaddress.IPv4Address(connection[2])
    if address.is_loopback or address.is_unspecified or address.is_multicast:
        raise ValueError("Host-based authentication requires a stable unicast provisioning address")
    return str(address)


def inspect(sshdir, user):
    try:
        account = pwd.getpwnam(user)
    except KeyError:
        raise ValueError(f"Account {user} does not exist") from None
    if account.pw_uid == 0:
        raise ValueError(f"Account {user} has UID 0")
    for path in map(Path, KEYSIGN_PATHS):
        if path.is_file() and path.stat().st_uid == 0 and path.stat().st_mode & (stat.S_ISUID | stat.S_ISGID):
            break
    else:
        raise ValueError("OpenSSH ssh-keysign is missing or lacks its packaged privileges")

    keys = []
    for algorithm in ("ed25519", "ecdsa", "rsa"):
        path = sshdir / f"ssh_host_{algorithm}_key"
        if path.is_file():
            keys.append(" ".join(run("/usr/bin/ssh-keygen", "-y", "-P", "", "-f", path).split()[:2]))
    if not keys:
        raise ValueError("No standard OpenSSH host key is installed")
    return {"address": ssh_address(), "keys": keys}


def read_file(path):
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError(f"{path} must be a regular file")
    if not path.exists():
        return None
    # Preserve administrator comments, including comments outside the locale.
    return path.read_bytes().decode("utf-8", errors="surrogateescape")


def block_markers(label):
    return (f"# BEGIN xCAT mkhostbased-auth {label}\n", f"# END xCAT mkhostbased-auth {label}\n")


def remove_block(text, label):
    start, end = block_markers(label)
    lines = (text or "").splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines) if line == start]
    ends = [i for i, line in enumerate(lines) if line == end]
    if not starts and not ends:
        return text, None
    if len(starts) != 1 or len(ends) != 1 or starts[0] >= ends[0]:
        raise ValueError(f"Malformed xCAT host-based authentication block ({label})")
    return "".join(lines[:starts[0]] + lines[ends[0] + 1:]), "".join(lines[starts[0] + 1:ends[0]])


def add_block(text, label, body, *, prefix=False):
    start, end = block_markers(label)
    block = start + body + end
    text = text or ""
    if prefix:
        return block + text
    return text + ("\n" if text and not text.endswith("\n") else "") + block


def active_lines(text):
    return [line.strip() for line in (text or "").splitlines() if line.strip() and not line.lstrip().startswith("#")]


def directive(line):
    match = re.match(r"^\s*([a-z]+)[ \t=]+(.*)$", line, flags=re.IGNORECASE)
    return (match[1].lower(), match[2]) if match else ("", "")


def dropin_path(config):
    return config.parent / (config.name + ".d") / DROPIN_NAME


def includes_dropin(config, text):
    """Follow the standard OpenSSH include layout used by remoteshell-sshd-config."""
    pattern = str(dropin_path(config).parent / "*.conf")
    for line in active_lines(text):
        keyword, value = directive(line)
        if keyword in ("host", "match"):
            break
        if keyword == "include" and any(str(config.parent / name) == pattern
                                        for name in shlex.split(value, comments=True)):
            return True
    return False


def read_dropin(path):
    if path.parent.is_symlink():
        raise ValueError(f"{path.parent} must not be a symbolic link")
    text = read_file(path)
    if text is not None and not text.startswith(DROPIN_HEADER):
        raise ValueError(f"{path} is not managed by xCAT mkhostbased-auth")
    return text


def reject_existing_hostbased(text, sshdir, seen):
    # System-wide equivalence files are consulted by every sshd Match block that
    # enables this authentication method. Refuse to add entries alongside another policy.
    for line in active_lines(text):
        keyword, value = directive(line)
        if keyword == "hostbasedauthentication" and shlex.split(value.lower(), comments=True) == ["yes"]:
            raise ValueError("Another sshd configuration already enables host-based authentication")
        if keyword == "include":
            for pattern in shlex.split(value, comments=True):
                for name in glob.glob(str(sshdir / pattern)):
                    path = Path(name).resolve()
                    if path not in seen and path.is_file():
                        seen.add(path)
                        reject_existing_hostbased(read_file(path), sshdir, seen)


def reject_known_hosts_conflicts(text, peers, directory):
    if not active_lines(text):
        return
    with tempfile.NamedTemporaryFile(dir=directory) as known_hosts:
        known_hosts.write(text.encode("utf-8", errors="surrogateescape"))
        known_hosts.flush()
        for peer in peers:
            for host in (peer["address"], peer["name"]):
                command = ["/usr/bin/ssh-keygen", "-F", host, "-f", known_hosts.name]
                result = subprocess.run(
                    command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True, timeout=20
                )
                if result.returncode == 0:
                    raise ValueError(f"Existing system host trust for {host} conflicts with this configuration")
                if result.returncode != 1 or result.stderr:
                    raise ValueError(result.stderr.strip() or "Cannot check the existing system host trust")


def file_contents(sshdir, etcdir, request):
    server = sshdir / "sshd_config"
    client = sshdir / "ssh_config"
    equiv = sshdir / "shosts.equiv"
    known = sshdir / "ssh_known_hosts"
    server_dropin = dropin_path(server)
    client_dropin = dropin_path(client)
    before = {path: read_file(path) for path in (client, known, equiv, server)}
    for path in (server_dropin, client_dropin):
        before[path] = read_dropin(path)
    if before[server] is None or before[client] is None:
        raise ValueError("Standard OpenSSH client and server configuration files are required")

    server_text, _ = remove_block(before[server], "server")
    server_text, old_match = remove_block(server_text, "match")
    client_text, _ = remove_block(before[client], "client")
    equiv_text, old_equiv = remove_block(before[equiv], "equiv")
    known_text, old_keys = remove_block(before[known], "keys")
    after = {known: known_text if known_text or old_keys is None else None,
             equiv: equiv_text if equiv_text or old_equiv is None else None, client: client_text, server: server_text,
             client_dropin: None, server_dropin: None}
    if request["remove"]:
        return before, after

    reject_existing_hostbased(server_text, sshdir, {server.resolve(), server_dropin.resolve()})
    if active_lines(equiv_text) or active_lines(read_file(etcdir / "hosts.equiv")):
        raise ValueError("Existing host equivalence rules conflict with this configuration")
    peers = request["peers"]
    reject_known_hosts_conflicts(known_text, peers, sshdir)
    reject_known_hosts_conflicts(read_file(sshdir / "ssh_known_hosts2"), peers, sshdir)
    user = request["user"]
    addresses = [peer["address"] for peer in peers]
    match = (
        f"Match User {user} Address {','.join(addresses)}\n"
        "    HostbasedAuthentication yes\n"
        "    HostbasedUsesNameFromPacketOnly no\n"
        "    IgnoreRhosts yes\n"
    )
    _, dropin_match = remove_block(before[server_dropin], "match")
    if any(previous is not None and previous != match for previous in (old_match, dropin_match)):
        raise ValueError("Remove the previous xCAT configuration before changing the account or peers")

    server_policy = "HostbasedAuthentication no\nIgnoreUserKnownHosts yes\n"
    if includes_dropin(server, server_text):
        after[server_dropin] = add_block(DROPIN_HEADER + server_policy, "match", match)
    else:
        after[server] = add_block(add_block(server_text, "server", server_policy, prefix=True), "match", match)
    client_hosts = " ".join(f"{peer['name']} {peer['address']}" for peer in peers)
    client_policy = f"EnableSSHKeysign yes\nHost {client_hosts}\n    HostbasedAuthentication yes\n"
    if includes_dropin(client, client_text):
        after[client_dropin] = DROPIN_HEADER + client_policy
    else:
        after[client] = add_block(client_text, "client", client_policy + "Host *\n", prefix=True)
    # A host-only equivalence record grants access only when the client and server
    # usernames match. The sshd Match block limits this to the chosen account.
    after[equiv] = add_block(equiv_text, "equiv", "".join(f"{address}\n" for address in addresses))
    records = "".join(
        f"{peer['name']},{peer['address']} {key}\n" for peer in peers for key in sorted(peer["keys"])
    )
    after[known] = add_block(known_text, "keys", records)
    return before, after


def write_config(path, content):
    path.write_bytes(content.encode("utf-8", errors="surrogateescape"))


def stage_config(config, after, directory):
    # Preserve include order while substituting the proposed xCAT drop-in.
    fragment = dropin_path(config)
    staged = directory / fragment.parent.name
    staged.mkdir()
    for path in fragment.parent.glob("*.conf"):
        if path != fragment:
            (staged / path.name).symlink_to(path)
    if after[fragment] is not None:
        write_config(staged / fragment.name, after[fragment])
    standard = str(fragment.parent / "*.conf")
    lines = []
    for line in after[config].splitlines(keepends=True):
        keyword, value = directive(line)
        if keyword == "include":
            paths = [str(config.parent / name) for name in shlex.split(value, comments=True)]
            # With -F, ssh otherwise resolves relative Include paths against ~/.ssh.
            paths = [str(staged / "*.conf") if path == standard else path for path in paths]
            line = "Include " + " ".join(f'"{path}"' for path in paths) + "\n"
        lines.append(line)
    path = directory / config.name
    write_config(path, "".join(lines))
    return path


def effective_server(path, user, address):
    return dict(line.split(maxsplit=1) for line in run(
        "/usr/sbin/sshd", "-T", "-f", path, "-C", f"user={user},host={address},addr={address}"
    ).splitlines() if " " in line)


def validate(sshdir, after, request):
    server = sshdir / "sshd_config"
    client = sshdir / "ssh_config"
    with tempfile.TemporaryDirectory(prefix=".xcat-hostbased-", dir=sshdir) as staging:
        server_file = stage_config(server, after, Path(staging))
        client_file = stage_config(client, after, Path(staging))
        run("/usr/sbin/sshd", "-t", "-f", server_file)
        if request["remove"]:
            return
        user = request["user"]
        peers = request["peers"]
        addresses = {peer["address"] for peer in peers}
        outside = "192.0.2.1" if "192.0.2.1" not in addresses else "0.0.0.0"
        checks = [(user, peer["address"], "yes") for peer in peers]
        checks.extend(((user, outside, "no"), ("root", peers[0]["address"], "no")))
        for account, address, expected in checks:
            settings = effective_server(server_file, account, address)
            if settings.get("hostbasedauthentication") != expected:
                raise ValueError("The existing sshd configuration overrides the requested account or peer policy")
            if expected == "yes" and any(settings.get(key) != value for key, value in {
                "usedns": "no", "ignoreuserknownhosts": "yes", "ignorerhosts": "yes",
                "hostbasedusesnamefrompacketonly": "no",
            }.items()):
                raise ValueError("The existing sshd configuration overrides the required host-based trust settings")
            if expected == "yes" and not {"any", "hostbased"} & set(settings["authenticationmethods"].split()):
                raise ValueError("The existing sshd AuthenticationMethods policy does not permit host-based login")
        hosts = [(host, "yes") for peer in peers for host in (peer["name"], peer["address"])]
        for hostname, expected in hosts + [(outside, "no")]:
            settings = dict(line.split(maxsplit=1) for line in run(
                "/usr/bin/ssh", "-G", "-F", client_file, hostname
            ).splitlines() if " " in line)
            if settings.get("enablesshkeysign") != "yes" or settings.get("hostbasedauthentication") != expected:
                raise ValueError("The existing ssh client configuration conflicts with the requested peer policy")


def replace_file(path, content, attributes=None, *, mode=None):
    if content is None:
        with suppress(FileNotFoundError):
            path.unlink()
        return
    if path.name == DROPIN_NAME:
        path.parent.mkdir(mode=0o755, exist_ok=True)
    if mode is None:
        default_mode = 0o600 if path.name == DROPIN_NAME else 0o644
        mode = stat.S_IMODE(attributes.st_mode) if attributes else default_mode
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as staging:
        temporary = Path(staging.name)
        try:
            staging.write(content.encode("utf-8", errors="surrogateescape"))
            staging.flush()
            if attributes is not None:
                os.fchown(staging.fileno(), attributes.st_uid, attributes.st_gid)
            os.fchmod(staging.fileno(), mode)
            os.fsync(staging.fileno())
            temporary.replace(path)
            restorecon = shutil.which("restorecon")
            if restorecon:
                run(restorecon, str(path))
        finally:
            with suppress(FileNotFoundError):
                temporary.unlink()


def ssh_service():
    for service in ("sshd.service", "ssh.service"):
        if subprocess.run(["systemctl", "is-active", "--quiet", service], timeout=20).returncode == 0:
            return service
    raise ValueError("No active systemd OpenSSH service found")


def configure(sshdir, etcdir, request):
    before, after = file_contents(sshdir, etcdir, request)
    changes = [path for path in after if before[path] != after[path]]
    client_dropin = dropin_path(sshdir / "ssh_config")
    # OpenSSH clients read this file as the connecting user.
    if (after[client_dropin] is not None and client_dropin not in changes
            and stat.S_IMODE(client_dropin.stat().st_mode) != 0o644):
        changes.append(client_dropin)
    if not changes and request["remove"]:
        return
    validate(sshdir, after, request)
    service = ssh_service()
    if request["operation"] == "check" or not changes:
        return
    attributes = {path: path.stat() if before[path] is not None else None for path in changes}
    applied = []
    try:
        for path in changes:
            applied.append(path)
            replace_file(path, after[path], attributes[path], mode=0o644 if path == client_dropin else None)
        run("/usr/sbin/sshd", "-t", "-f", sshdir / "sshd_config")
        run("systemctl", "reload", service)
    except (OSError, ValueError, subprocess.SubprocessError) as failure:
        rollback_errors = []
        for path in reversed(applied):
            try:
                replace_file(path, before[path], attributes[path])
            except (OSError, ValueError, subprocess.SubprocessError) as error:
                rollback_errors.append(str(error))
        try:
            run("systemctl", "reload", service)
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            rollback_errors.append(str(error))
        if rollback_errors:
            raise ValueError(f"{failure}; rollback errors: {', '.join(rollback_errors)}") from failure
        raise


def main(payload):
    try:
        request = json.loads(payload)
        sshdir = Path("/etc/ssh")
        if request["operation"] == "inspect":
            result = inspect(sshdir, request["user"])
        else:
            if not request["remove"] and request["address"] != ssh_address():
                raise ValueError("This node's SSH address changed after verification")
            with open("/run/xcat-mkhostbased-auth-node.lock", "a", encoding="ascii") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                configure(sshdir, Path("/etc"), request)
            result = {}
        print(json.dumps(result))
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
