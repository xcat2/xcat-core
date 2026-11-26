# Shared BMC field readers

Edit `bmc-fields.sh`, then run:

```
perl build-utils/sync-bmc-fields --write
perl build-utils/sync-bmc-fields --check
```

Commit the source and both generated `bmcsetup` blocks together. The Genesis
script and postscript remain standalone, including copies from a source checkout.
`buildrpms.pl` and `builddebs.pl` reject stale blocks before building either package.

Those release builders replace the postscript with the Genesis implementation
before packaging xCAT. Direct spec and Debian rules builds use the tracked
postscript instead. This reader generation does not change that distinction.

Run the check before a direct KAS/BitBake build too. The OpenEmbedded recipe
installs the tracked Genesis script without running the RPM or Debian builders.

Keep the field readers in POSIX shell. Keep vendor handling, retries and
caller-specific behavior outside the generated blocks.
