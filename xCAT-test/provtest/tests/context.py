"""Put `src/` on the path so the tests import the tool, not an installed copy.

The suite runs out of a checkout with no install step, so the import has to be
made to work rather than assumed. Every test module imports this one first.
"""

import os
import sys

TESTS = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(TESTS)
SRC = os.path.join(ROOT, "src")
LIB = os.path.join(SRC, "provtest_lib")
CONF = os.path.join(ROOT, "conf")

if SRC not in sys.path:
    sys.path.insert(0, SRC)


def conf_files():
    """Every shipped scenario file, sorted."""
    return sorted(os.path.join(CONF, name) for name in os.listdir(CONF)
                  if name.endswith(".conf"))


def modules():
    """Every module of the tool, as `(name, path)`."""
    found = [("provtest", os.path.join(SRC, "provtest"))]
    for name in sorted(os.listdir(LIB)):
        if name.endswith(".py"):
            found.append((name[:-3], os.path.join(LIB, name)))
    return found
