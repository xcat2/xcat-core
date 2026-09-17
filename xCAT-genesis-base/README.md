# xCAT Genesis

## OpenEmbedded builder

OpenEmbedded is the current Genesis build path. It builds a small, pinned
system instead of copying files from the build host.

Install the host packages required by OpenEmbedded, then install `kas` in a
Python virtual environment:

```sh
python3 -m venv .venv
. .venv/bin/activate
pip install -r xCAT-genesis-base/oe/requirements.txt
xCAT-genesis-base/oe/build x86_64
```

The build command accepts `x86`, `x86_64`, `ppc64`, `ppc64le`, `armv7hf`,
`aarch64`, `riscv64`, and `s390x`. Multiple architectures are built in the
order given.
Run `xCAT-genesis-base/oe/build --list-architectures` to print this list.
Artifacts are written below `xCAT-genesis-base/oe/.work/build/tmp/deploy/images`.
The `x86` artifact uses an i686 CPU baseline. The build carries the reviewed
Yocto release key in `oe/keys` and verifies its fingerprint locally.

The serial console normally opens a read-only Newt status screen. `F1` shows
help, `F2` shows diagnostics, and `F3` shows live logs. `F12` opens a confirmed
root maintenance shell; exiting returns to the status screen. Add
`xcat.console=plain` to the kernel command line for line output. In plain mode,
type `shell` and press Enter to open the same confirmed maintenance shell.

Export an image for xCAT after the build:

```sh
xCAT-genesis-base/oe/export x86_64 \
    xCAT-genesis-base/oe/.work/build/tmp/deploy \
    /tmp/xcat-genesis-x86_64
```

Copy the exported directory intact to the management node at
`/opt/xcat/share/xcat/netboot/genesis/x86_64`, then publish it:

```sh
mknb x86_64
```

`mknb` verifies the kernel and initramfs checksums before replacing the files
under the configured TFTP root.

### Signed extensions

Build an extension recipe with the same machine configuration as the Genesis
image. Then export it with the site's Ed25519 release key:

```sh
xCAT-genesis-base/oe/export-extension x86_64 my-extension \
    xCAT-genesis-base/oe/.work/build/tmp/deploy \
    /secure/genesis-extension.key /secure/genesis-extension.pub \
    /tmp/my-extension-bundle
```

The private key stays outside the source tree. The exported bundle contains
the extension image, manifest, signature, public key, and checksums.

A site layer can include that directory in its Genesis image with a small
append file:

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://my-extension-bundle"
XCAT_GENESIS_EXTENSION_BUNDLE = "my-extension-bundle"
```

Place the exported directory below the append file's `files` directory.
Genesis verifies every bundled extension before registration and stops the
boot workflow if the image, manifest, signature, key, release, or architecture
does not match.

Genesis records registration time and memory use in `/run/xcat/metrics.env`.
After copying that file from a test VM, create a report with image sizes and
runtime measurements:

```sh
xCAT-genesis-base/oe/report --runtime /tmp/metrics.env \
    x86_64 /tmp/xcat-genesis-x86_64 > /tmp/report.env
```

Compare a later build with the saved report:

```sh
xCAT-genesis-base/oe/report --runtime /tmp/metrics.env \
    --baseline /tmp/report.env \
    x86_64 /tmp/xcat-genesis-x86_64
```

Positive deltas mean a larger image, more memory use, or a slower registration.

See the [architecture plan](../docs/source/developers/guides/code/genesis_openembedded_plan.rst)
for the network, hardware, license, and signed-extension contracts.

# Open Source License

xCAT is made available under the EPL license: https://opensource.org/licenses/eclipse-1.0.php

# Developers

Want to help? Check out the [developers guide](http://xcat-docs.readthedocs.io/en/latest/developers)!
