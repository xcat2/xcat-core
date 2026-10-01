"""blackboxtest -- a client-side test of the xCAT provisioning services.

A booting node speaks DHCP, DNS, TFTP, HTTP and the xcatd protocols, in that
order. This package speaks all of them from the client's side and asserts on
what comes back. It never reads the xCAT database and never runs an xCAT
command: every value it expects is given to it on the command line.
"""
