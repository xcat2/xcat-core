# Shared FIPS shell policy

Edit `fips-policy.sh`, then run:

```
perl build-utils/sync-fips-policy --write
perl build-utils/sync-fips-policy --check
```

Commit the source and both updated runtime libraries together. The generated
blocks in Genesis `usr/lib/xcat/fips.sh` and postscripts `xcatlib.sh` stay tracked
so source-checkout callers and standalone packages need no generation step.
The RPM and Debian builders reject stale blocks before building either package.

Keep caller-specific helpers outside the generated block. The policy source
must remain POSIX shell. It must not depend on the other package at runtime.
