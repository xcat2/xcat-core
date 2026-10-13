#!/usr/bin/env python3
"""Run in a configured kas shell; exercise BitBake's evaluated recipes and tasks."""

import configparser
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import unittest

BITBAKE = shutil.which("bitbake")
if not BITBAKE:
    raise SystemExit("Run this test inside the Genesis kas shell")
sys.path.insert(0, str(Path(BITBAKE).resolve().parents[1] / "lib"))
import bb.build
import bb.fetch2
import bb.process
import bb.providers
import bb.tinfoil

ROOT = Path(__file__).resolve().parents[2]
LAYER = ROOT / "xCAT-genesis-base/oe/meta-xcat-genesis"
MACHINES = {
    "x86": ("i686", "ttyS0"),
    "x86_64": ("x86-64", "ttyS0"),
    "ppc64": ("powerpc64", "hvc0"),
    "ppc64le": ("ppc64p8le", "hvc0"),
    "armv7hf": ("armv7ahf", "ttyAMA0"),
    "aarch64": ("aarch64", "ttyAMA0"),
    "riscv64": ("riscv64", "ttyS0"),
    "s390x": ("s390x", "ttysclp0"),
}


class GenesisMetadata(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tinfoil = bb.tinfoil.Tinfoil()
        cls.addClassCleanup(cls.tinfoil.shutdown)
        cls.tinfoil.prepare(quiet=2)
        sys.path.insert(0, str(Path(cls.tinfoil.config_data.getVar("COREBASE")) / "meta/lib"))
        from oe import utils
        cls.oe_utils = utils
        cls.recipes = {}
        cls.image = cls.recipe("xcat-genesis-image")
        cls.arch = cls.image.getVar("XCAT_GENESIS_ARCHITECTURE")
        if cls.arch not in MACHINES:
            raise AssertionError("Unknown Genesis architecture: " + str(cls.arch))
        if cls.arch != os.environ["GENESIS_ARCHITECTURE"]:
            raise AssertionError("Configured machine does not match the requested architecture")

    @classmethod
    def recipe(cls, name):
        if name not in cls.recipes:
            data = cls.tinfoil.parse_recipe(name)
            if name.startswith("xcat-genesis") or name == "packagegroup-xcat-genesis-hardware":
                Path(data.getVar("FILE")).resolve().relative_to(LAYER)
            cls.recipes[name] = data
        return cls.recipes[name].createCopy()

    def words(self, data, variable):
        return set((data.getVar(variable) or "").split())

    def dependencies(self, recipe):
        data = self.recipe(recipe)
        return self.words(data, "RDEPENDS:" + data.getVar("PN"))

    def task_data(self, recipe):
        data = self.recipe(recipe)
        temporary = tempfile.TemporaryDirectory(prefix="genesis-metadata-")
        self.addCleanup(temporary.cleanup)
        work = Path(temporary.name)
        for variable, directory in (("WORKDIR", work), ("UNPACKDIR", work / "sources"),
                                    ("D", work / "image"), ("T", work / "temp")):
            directory.mkdir(exist_ok=True)
            data.setVar(variable, str(directory))
        # These local-file tasks need host tools, not an unbuilt target sysroot.
        data.setVar("PATH", os.environ["PATH"])
        return data

    def install(self, recipe):
        data = self.task_data(recipe)
        urls = data.getVar("SRC_URI").split()
        self.assertTrue(urls)
        self.assertTrue(all(url.startswith("file://") for url in urls))
        fetcher = bb.fetch2.Fetch(urls, data)
        fetcher.download()
        fetcher.unpack(data.getVar("UNPACKDIR"))
        bb.build.exec_func("do_install", data, dirs=[data.getVar("WORKDIR")])
        return data, Path(data.getVar("D"))

    def installed(self, data, root, variable, suffix, mode):
        file = root / data.getVar(variable).lstrip("/") / suffix
        self.assertTrue(file.is_file(), str(file))
        self.assertEqual(stat.S_IMODE(file.stat().st_mode), mode, str(file))
        return file

    def unit(self, file):
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        parser.optionxform = str
        parser.read(file)
        return parser

    def test_release_configuration(self):
        config = json.loads(Path(os.environ["GENESIS_KAS_CONFIG"]).read_text())
        self.assertEqual(config["machine"], self.image.getVar("MACHINE"))
        self.assertEqual(config["distro"], "xcat-genesis")
        pins = {
            "bitbake": "acfe02fa38b5da9e6a36c6cedcf91d4fcbefbfbd",
            "openembedded-core": "5d1aa5c806c061a2994f4decb59016610f093213",
            "meta-openembedded": "af8b6d6b2f0b11595b0a0d5b82efa3129d52a628",
        }
        for name, revision in pins.items():
            self.assertEqual(config["repos"][name]["commit"], revision)
        for name in ("bitbake", "openembedded-core"):
            repo = config["repos"][name]
            self.assertEqual(repo["tag"], "yocto-6.0.2")
            self.assertIs(repo["signed"], True)
            self.assertEqual(repo["allowed_signers"], ["yocto-release"])
        self.assertEqual(config["signers"]["yocto-release"], {
            "fingerprint": "2AFB13F28FBBB0D1B9DAF63087EB3D32FB631AD9",
            "repo": "xcat-core", "path": "xCAT-genesis-base/oe/keys/yocto-release.asc",
        })
        self.assertNotIn("gpg_keyserver", config)
        self.assertIn("xCAT-genesis-base/oe/meta-xcat-genesis", config["repos"]["xcat-core"]["layers"])
        self.assertLessEqual({"archiver", "create-spdx", "vex"}, self.words(self.image, "INHERIT"))
        for flag, value in (("src", "original"), ("diff", "1"), ("recipe", "1")):
            self.assertEqual(self.image.getVarFlag("ARCHIVER_MODE", flag), value)

    def test_machine_and_distro(self):
        data = self.image
        tune, terminal = MACHINES[self.arch]
        for variable, value in {
            "DEFAULTTUNE": tune, "XCAT_GENESIS_CONSOLE_TTY": terminal,
            "DISTRO_CODENAME": "cheetah", "LINUX_VERSION_EXTENSION": "-xCAT-genesis",
            "TCLIBC": "glibc", "INIT_MANAGER": "systemd", "NO_RECOMMENDATIONS": "1",
            "QB_DEFAULT_FSTYPE": "ext4",
        }.items():
            self.assertEqual(data.getVar(variable), value, variable)
        self.assertEqual(self.words(data, "IMAGE_FSTYPES"), {"cpio.gz", "ext4"})
        self.assertEqual(self.words(data, "DISTRO_FEATURES"),
                         {"acl", "ipv4", "ipv6", "largefile", "pci", "seccomp", "systemd", "usrmerge"})
        self.assertEqual("pci" in self.words(data, "MACHINE_FEATURES"), self.arch != "s390x")
        if self.arch == "x86_64":
            self.assertEqual(self.words(data, "MACHINE_FEATURES"), {"pci", "qemu-usermode", "rtc"})
        self.assertNotIn("xcat.debug-shell", self.words(data, "QB_KERNEL_CMDLINE_APPEND"))
        if self.arch == "ppc64le":
            self.assertEqual(data.getVar("KERNEL_IMAGETYPE"), "vmlinux")
        if self.arch == "x86":
            self.assertEqual(data.getVar("QB_SYSTEM_NAME"), "qemu-system-i386")
        if self.arch == "armv7hf":
            self.assertEqual(data.getVar("ARM_INSTRUCTION_SET"), "arm")
            self.assertNotIn("neon", self.words(data, "TUNE_FEATURES"))
        if self.arch == "riscv64":
            self.assertIn("opensbi", self.words(data, "EXTRA_IMAGEDEPENDS"))
            self.assertEqual(data.getVar("QB_DEFAULT_BIOS"), "fw_jump.elf")
        qemu = {
            "ppc64": ("-machine pseries", "-cpu POWER8"),
            "ppc64le": ("-machine pseries", "-cpu POWER8"),
            "armv7hf": ("-machine virt,highmem=off", "-cpu cortex-a15"),
            "aarch64": ("-machine virt", "-cpu cortex-a57"),
            "riscv64": ("-machine virt", "-cpu rva23s64,pmp=true"),
        }
        if self.arch in qemu:
            self.assertEqual((data.getVar("QB_MACHINE"), data.getVar("QB_CPU")), qemu[self.arch])

    def test_image_and_hardware_packages(self):
        image = self.words(self.image, "IMAGE_INSTALL")
        self.assertLessEqual({"xcat-genesis-network", "xcat-genesis-protocol", "xcat-genesis-extensions",
                              "xcat-genesis-console", "packagegroup-xcat-genesis-hardware"}, image)
        self.assertFalse(image & {"dhclient", "dhcpcd", "busybox-udhcpc", "systemd-networkd"})
        hardware = self.dependencies("packagegroup-xcat-genesis-hardware")
        self.assertLessEqual(set("pciutils usbutils hwloc ethtool rdma-core iproute2-rdma lldpd ipmitool curl jq "
                                 "nvme-cli smartmontools sg3-utils lsscsi mdadm hdparm parted lvm2 memtester "
                                 "stress-ng edac-utils kernel-modules mstflint xcat-genesis-hardware-control".split()), hardware)
        scoped = {"x86_64": {"dmidecode", "lshw", "mcelog"}, "x86": {"dmidecode", "lshw"},
                  "armv7hf": {"dmidecode", "lshw"}, "aarch64": {"dmidecode", "lshw"},
                  "ppc64": {"dmidecode", "xcat-genesis-hardware-control-iprutils"},
                  "ppc64le": {"dmidecode", "xcat-genesis-hardware-control-iprutils"},
                  "riscv64": {"lshw"}, "s390x": set()}
        self.assertEqual(hardware & {"dmidecode", "lshw", "mcelog", "xcat-genesis-hardware-control-iprutils"},
                         scoped[self.arch])
        self.assertFalse((image | hardware) & {"storcli", "perccli", "ssacli", "arcconf", "nvidia-smi", "rocm-smi"})

    def test_runtime_dependencies(self):
        for recipe, expected in {
            "xcat-genesis-network": "networkmanager-daemon networkmanager-nmcli",
            "xcat-genesis-protocol": "bash openssl-bin",
            "xcat-genesis-extensions": "bash coreutils jq openssl-bin systemd xcat-genesis-init",
            "xcat-genesis-hardware-control": "bash coreutils jq mstflint nvme-cli util-linux-flock",
            "xcat-genesis-console": "libnewt libsystemd ncurses-terminfo-base xcat-genesis-init",
            "mstflint": "python3-modules",
        }.items():
            self.assertEqual(self.dependencies(recipe), set(expected.split()), recipe)
        self.assertLessEqual({"coreutils", "util-linux-logger"}, self.dependencies("xcat-genesis-init"))
        console = self.recipe("xcat-genesis-console")
        self.assertLessEqual({"libnewt", "systemd"}, self.words(console, "DEPENDS"))
        self.assertIn("sysext", self.words(self.recipe("systemd"), "PACKAGECONFIG"))
        self.assertIn("rdma", self.words(self.recipe("iproute2"), "PACKAGECONFIG"))
        network = self.recipe("networkmanager")
        self.assertEqual(self.words(network, "PACKAGECONFIG"),
                         set("crypto-null libedit man-resolv-conf nmcli systemd".split()))
        self.assertEqual(network.getVar("NETWORKMANAGER_DHCP_DEFAULT"), "internal")
        self.assertEqual(network.getVar("NETWORKMANAGER_DNS_RC_MANAGER_DEFAULT"), "symlink")
        self.assertIn("-Dtests=no", self.words(network, "EXTRA_OEMESON"))

    def test_hardware_recipe_policy(self):
        data = self.recipe("mstflint")
        self.assertEqual(data.getVar("LICENSE"), "Linux-OpenIB & MIT & BSD-2-Clause")
        self.assertEqual(data.getVar("SRCREV"), "b9d9e844a14ae1c85cb90c76ccd4a56a0eccd599")
        self.assertEqual(self.words(data, "PACKAGECONFIG"), set("adb cables dc inband openssl".split()))
        self.assertFalse(self.words(data, "EXTRA_OECONF") & {"--enable-fw-mgr", "--enable-nvml"})
        if self.arch in {"ppc64", "ppc64le"}:
            data = self.recipe("iprutils")
            self.assertEqual(data.getVar("COMPATIBLE_HOST"), "powerpc64.*-linux")
            self.assertEqual(data.getVar("LICENSE"), "CPL-1.0")
            self.assertEqual(data.getVar("SRCREV"), "9961e538736a6e81f1072a926c3ad91b8513c8c1")
            self.assertLessEqual({"--without-systemd", "--without-initscripts"}, self.words(data, "EXTRA_OECONF"))
            control = self.recipe("xcat-genesis-hardware-control")
            self.assertIn("xcat-genesis-hardware-control-iprutils", self.words(control, "PACKAGES"))
            self.assertEqual(self.words(control, "RDEPENDS:xcat-genesis-hardware-control-iprutils"),
                             {"xcat-genesis-hardware-control", "bash", "iprutils"})
        else:
            with self.assertRaisesRegex(bb.providers.NoProvider, "incompatible with host"):
                self.tinfoil.get_recipe_file("iprutils")

    def test_kernel_fragment_selection(self):
        data = self.recipe("linux-yocto")
        fragments = {
            "x86": {"x86-common", "x86"}, "x86_64": {"x86-common", "x86-64"},
            "ppc64": {"powerpc64", "ppc64"}, "ppc64le": {"powerpc64"},
        }.get(self.arch, {self.arch})
        urls = {url.split(";")[0] for url in data.getVar("SRC_URI").split()}
        self.assertLessEqual({"file://xcat-genesis-" + name + ".cfg" for name in fragments}, urls)
        if self.arch not in {"x86", "x86_64"}:
            self.assertEqual(data.getVar("SRCREV_machine"), "b1ba5428513b52c2bd6acfd3ad0a910f699bc395")
        self.assertEqual(data.getVar("KERNEL_MODULE_PACKAGE_SUFFIX"), "-" + data.getVar("KERNEL_VERSION_PKG_NAME"))

    def test_installed_protocol(self):
        data, root = self.install("xcat-genesis-protocol")
        for name in ("getdestiny", "nextdestiny"):
            file = self.installed(data, root, "bindir", name, 0o755)
            self.assertEqual(file.read_bytes(), (ROOT / "xCAT-genesis-scripts/usr/bin" / name).read_bytes())
        self.assertFalse(list(root.rglob("doxcat")))

    def test_installed_network(self):
        data, root = self.install("xcat-genesis-network")
        file = self.installed(data, root, "sysconfdir", "NetworkManager/conf.d/10-xcat-genesis.conf", 0o644)
        config = self.unit(file)
        self.assertEqual(config["connection"]["ipv4.dhcp-timeout"], "20")
        self.assertEqual(config["connection"]["ipv6.dhcp-timeout"], "20")
        self.assertEqual(config["connection"]["ipv6.dhcp-duid"], "ll")

    def test_installed_hardware_providers(self):
        data, root = self.install("xcat-genesis-hardware-control")
        providers = {"mstflint", "nvme"}
        if self.arch in {"ppc64", "ppc64le"}:
            providers.add("iprutils")
        directory = root / data.getVar("datadir").lstrip("/") / "xcat/genesis/providers"
        self.assertEqual({file.stem for file in directory.glob("*.json")}, providers)
        for name in providers:
            file = self.installed(data, root, "datadir", "xcat/genesis/providers/" + name + ".json", 0o644)
            manifest = json.loads(file.read_text())
            self.assertEqual(manifest["name"], name)
            self.assertTrue(manifest["capabilities"])
            for capability in manifest["capabilities"]:
                self.assertIs(capability["destructive"], False)
            self.installed(data, root, "libexecdir", "xcat/genesis/providers/" + name, 0o755)

    def test_installed_init(self):
        data, root = self.install("xcat-genesis-init")
        self.installed(data, root, "libexecdir", "xcat/genesis-functions", 0o644)
        for name in ("genesis-status", "genesis-maintenance-shell"):
            self.installed(data, root, "libexecdir", "xcat/" + name, 0o755)
        self.assertFalse(list(root.rglob("*debug-shell*")))
        network = self.unit(self.installed(data, root, "systemd_system_unitdir", "xcat-genesis-network-state.service", 0o644))
        self.assertEqual(network["Unit"]["After"], "NetworkManager.service")
        self.assertEqual(network["Unit"]["Before"], "xcat-genesis-network-ready.target")
        register = self.unit(self.installed(data, root, "systemd_system_unitdir", "xcat-genesis-register.service", 0o644))
        for option in ("After", "Requires"):
            self.assertEqual(set(register["Unit"][option].split()),
                             {"xcat-genesis-network-ready.target", "xcat-genesis-extensions.service"})
        preset = root / data.getVar("systemd_unitdir").lstrip("/") / "system-preset/00-xcat-genesis.preset"
        self.assertEqual(preset.read_text(), "disable getty@.service\n")

    def test_installed_extension_service(self):
        data, root = self.install("xcat-genesis-extensions")
        service = self.unit(self.installed(data, root, "systemd_system_unitdir", "xcat-genesis-extensions.service", 0o644))
        self.assertEqual(service["Unit"]["ConditionDirectoryNotEmpty"], "/var/lib/xcat/genesis/extensions")
        self.assertEqual(service["Unit"]["Before"], "xcat-genesis-register.service")

    def test_extension_manifest(self):
        data = self.task_data("xcat-genesis-extension-smoke")
        self.assertEqual(self.words(data, "IMAGE_FSTYPES"), {"squashfs-zst"})
        self.assertEqual(data.getVar("XCAT_GENESIS_EXTENSION_ARCHITECTURE"), self.arch)
        deploy = Path(data.getVar("WORKDIR")) / "deploy"
        deploy.mkdir()
        data.setVar("IMGDEPLOYDIR", str(deploy))
        data.setVar("IMAGE_LINK_NAME", "test-extension")
        payload = b"extension image fixture\n"
        image = deploy / "test-extension.squashfs-zst"
        image.write_bytes(payload)
        expected = {
            "architecture": self.arch, "capabilities": ["diagnostic.smoke"],
            "genesis_release": data.getVar("DISTRO_VERSION"), "kernel_modules": False,
            "kernel_release": None, "key_id": "xcat-release", "license_class": "open",
            "name": "xcat-smoke", "pci_ids": [], "schema": 1,
            "sha256": hashlib.sha256(payload).hexdigest(), "version": "1.0",
        }
        for unused in range(2):
            self.oe_utils.execute_pre_post_process(data, data.getVar("IMAGE_POSTPROCESS_COMMAND"))
            self.assertEqual(json.loads((deploy / "test-extension.manifest.json").read_text()), expected)
        data.setVar("XCAT_GENESIS_EXTENSION_KERNEL_MODULES", "true")
        data.setVar("XCAT_GENESIS_EXTENSION_KERNEL_RELEASE", "6.18-test")
        expected.update(kernel_modules=True, kernel_release="6.18-test")
        self.oe_utils.execute_pre_post_process(data, data.getVar("IMAGE_POSTPROCESS_COMMAND"))
        self.assertEqual(json.loads((deploy / "test-extension.manifest.json").read_text()), expected)
        image.unlink()
        with self.assertRaises(bb.process.ExecutionError) as failure:
            self.oe_utils.execute_pre_post_process(data, data.getVar("IMAGE_POSTPROCESS_COMMAND"))
        self.assertEqual(failure.exception.exitcode, 1)

    def test_extension_parse_policy(self):
        recipe = self.tinfoil.get_recipe_file("xcat-genesis-extension-smoke")
        cases = [
            ({"ARCHITECTURE": "armv7"}, "Invalid Genesis extension architecture"),
            ({"NAME": "../escape"}, "Invalid Genesis extension name"),
            ({"VERSION": "bad version"}, "Invalid Genesis extension version"),
            ({"KEY_ID": "bad/key"}, "Invalid Genesis extension key ID"),
            ({"LICENSE_CLASS": "unknown"}, "Invalid Genesis extension license class"),
            ({"LICENSE_CLASS": "restricted"}, "Restricted Genesis extensions must set LICENSE_FLAGS"),
            ({"KERNEL_MODULES": "yes"}, "must be true or false"),
            ({"KERNEL_MODULES": "true"}, "Kernel extensions must declare"),
            ({"CAPABILITIES": "invalid"}, "Invalid JSON"),
            ({"CAPABILITIES": "{}"}, "must be a JSON string array"),
            ({"PCI_IDS": '["not-a-pci-id"]'}, "Invalid value"),
        ]
        for values, message in cases:
            with self.subTest(values=values):
                config = self.tinfoil.config_data.createCopy()
                for name, value in values.items():
                    config.setVar("XCAT_GENESIS_EXTENSION_" + name + ":forcevariable", value)
                with self.assertLogs("BitBake", level="ERROR") as errors:
                    with self.assertRaises(bb.BBHandledException):
                        self.tinfoil.parse_recipe_file(recipe, config_data=config)
                self.assertTrue(any(message in error for error in errors.output), errors.output)
        for values in ({"ARCHITECTURE": "armv7hf"},
                       {"LICENSE_CLASS": "restricted"},
                       {"KERNEL_MODULES": "true", "KERNEL_RELEASE": "6.18-test"}):
            config = self.tinfoil.config_data.createCopy()
            config.setVar("LICENSE_FLAGS:forcevariable", "commercial_test")
            config.setVar("LICENSE_FLAGS_ACCEPTED", "commercial_test")
            for name, value in values.items():
                config.setVar("XCAT_GENESIS_EXTENSION_" + name + ":forcevariable", value)
            self.assertIsNotNone(self.tinfoil.parse_recipe_file(recipe, config_data=config))


if __name__ == "__main__":
    unittest.main(verbosity=2)
