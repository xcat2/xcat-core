# Netboot image policy

`netboot-policy.sh` owns the SELinux and firewalld helpers used by the RHEL
and Rocky postinstall profiles listed in `netboot_policy_artifacts()`.
The profiles contain generated copies so an administrator can copy and
customize a profile without installing a separate runtime library.

After editing the policy, run:

```sh
build-utils/sync-netboot-policy --write
build-utils/sync-netboot-policy --check
```

Commit the canonical policy and regenerated profiles together. RPM and Debian
builders reject stale copies when building xCAT-server.

Each profile still selects which helpers to call. Generation does not add
firewalld removal to RHEL 7 or service profiles, and genimage does not apply
this policy when an administrator supplies a different postinstall script.
