"""Put src/ on sys.path so the tests run straight from a checkout."""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "src")
CONF = os.path.join(ROOT, "conf")

if SRC not in sys.path:
    sys.path.insert(0, SRC)
