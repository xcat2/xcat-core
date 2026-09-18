"""Put `src/` first on sys.path, so the tests import the checkout.

Every test module imports this one first.
"""

import os
import sys
import tempfile

TESTS = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(TESTS)
SRC = os.path.join(ROOT, "src")
LIB = os.path.join(SRC, "blackboxtest_lib")
CONF = os.path.join(ROOT, "conf")

if SRC not in sys.path:
    sys.path.insert(0, SRC)


def conf_files():
    """Every shipped scenario file, sorted."""
    found = []
    for directory, _, names in os.walk(CONF):
        found.extend(os.path.join(directory, n) for n in names
                     if n.endswith(".conf"))
    return sorted(found)


def modules():
    """Every module of the tool, as `(name, path)`."""
    found = [("blackboxtest", os.path.join(SRC, "blackboxtest"))]
    for name in sorted(os.listdir(LIB)):
        if name.endswith(".py"):
            found.append((name[:-3], os.path.join(LIB, name)))
    return found


def write_conf(test, text, name="t.conf"):
    """Write `text` to a scratch file removed after `test`."""
    directory = tempfile.mkdtemp(prefix="blackboxtest-")
    test.addCleanup(__import__("shutil").rmtree, directory, True)
    path = os.path.join(directory, name)
    with open(path, "w") as handle:
        handle.write(text)
    return path
