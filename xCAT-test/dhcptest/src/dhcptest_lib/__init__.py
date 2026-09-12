"""dhcptest -- a wire-level DHCP client test tool.

The package is deliberately layered so that most of it can be unit tested
without root, without a network, and without scapy installed:

    model, netutil, options, subst, assertions, machine, config, report, cli
        pure python, standard library only

    packets, transport
        the only modules allowed to import scapy

`tests/test_layering.py` enforces that split.
"""

__version__ = "0.1.0"
