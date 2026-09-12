"""provtest -- drive the xCAT provision chain the way a booting node does.

A node that is being provisioned speaks five protocols in turn: it resolves
names, fetches a loader and a configuration over TFTP, fetches a kernel and a
kickstart over HTTP, asks xcatd where it is going, and reports back while it
installs. This tool speaks all five, from a client's side, and asserts on what
comes back.

It never reads the xCAT database and never runs an xCAT command. Every value it
expects is supplied to it, so a test cannot be satisfied by asking xCAT to
confirm its own output.
"""

__version__ = "1.0"
