package xCAT_plugin::ipxe;

# netboot=ipxe boots x86 nodes with the upstream iPXE loaders of the ipxe-xcat package. It runs the
# boot scripts of the xnba method, which it keeps under xcat/ipxe instead of xcat/xnba.

use strict;
use warnings;

sub handled_commands {
    return { nodeset => 'noderes:netboot' };
}

# xcatd loads xnba.pm from the plugin directory, so load it here only when it is not there yet.
sub _xnba {
    require xCAT_plugin::xnba unless defined &xCAT_plugin::xnba::process_request;
    return;
}

sub preprocess_request {
    _xnba();
    local $xCAT_plugin::xnba::SCRIPTS = 'xcat/ipxe';
    local $xCAT_plugin::xnba::METHOD  = 'ipxe';
    return xCAT_plugin::xnba::preprocess_request(@_);
}

sub process_request {
    _xnba();
    local $xCAT_plugin::xnba::SCRIPTS = 'xcat/ipxe';
    local $xCAT_plugin::xnba::METHOD  = 'ipxe';
    return xCAT_plugin::xnba::process_request(@_);
}

sub getstate {
    _xnba();
    local $xCAT_plugin::xnba::SCRIPTS = 'xcat/ipxe';
    local $xCAT_plugin::xnba::METHOD  = 'ipxe';
    return xCAT_plugin::xnba::getstate(@_);
}

sub getNodesetStates {
    _xnba();
    local $xCAT_plugin::xnba::SCRIPTS = 'xcat/ipxe';
    local $xCAT_plugin::xnba::METHOD  = 'ipxe';
    return xCAT_plugin::xnba::getNodesetStates(@_);
}

1;
