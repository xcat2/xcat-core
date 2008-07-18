#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::DSHContext;

use locale;
use strict;
require xCAT::DSHCore;

sub valid_context {
	return 1;
}

sub context_defaults {
	my %defaults = ();

	$defaults{'NodeRemoteShell'} = '/usr/bin/rsh';
	return \%defaults;
}

sub context_properties {
	return;
}

sub all_devices {
	return undef;
}

sub all_devicegroups {
	return undef;
}

sub all_nodes {
	return undef;
}

sub all_nodegroups {
	return undef;
}

sub devicegroup_members {
	return undef;
}

sub nodegroup_members {
	return undef;
}

sub resolve_device {
	return undef;
}

sub resolve_node {
	return 1;
}

sub verify_target {
	return 127;
}

sub verify_mode {
	return "NOXCAT";
}

sub resolve_hostnames {
	my ( $class, $resolved_targets, $unresolved_targets, @target_list ) = @_;
	xCAT::DSHCore->resolve_hostnames( undef, $resolved_targets, $unresolved_targets,
		undef, @target_list );
}

1;
