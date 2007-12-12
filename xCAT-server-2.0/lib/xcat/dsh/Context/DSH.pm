#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package DSH;
use base xCAT::DSHContext;
use xCAT::MsgUtils;
use File::Path;


# Configure Node group path from environment

our $nodegroup_path = $ENV{'DSH_NODEGROUP_PATH'};

=head3
        context_defaults

        Assign default properties for the DSH context.  A default
        property for a context will be used if the property is
        not user configured in any other way.

        Arguments:
        	None

        Returns:
        	A reference to a hash table with the configured
        	default properties for the DSH context
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:
        	$default_properties = DSH->config_defaults;

        Comments:
        	$defaults hash table contents:
        	
        		$defaults{'NodeRemoteShell'} - default remote shell to use for node targets

=cut

sub context_defaults {
	my %defaults = ();

	if ( $ENV{'DSH_NODE_RSH'} ) {
		my @remoteshell_list = split ',', $ENV{'DSH_NODE_RSH'};

		foreach $context_remoteshell (@remoteshell_list) {
			my ( $context, $remoteshell ) = split ':', $context_remoteshell;

			if ( !$remoteshell ) {
				$remoteshell = $context;
				!$defaults{'NodeRemoteShell'}
				  && ( $defaults{'NodeRemoteShell'} = $remoteshell );
			}

			elsif ( $context eq 'DSH' ) {
				$defaults{'NodeRemoteShell'} = $remoteshell;
			}
		}
	}

	if ( !$defaults{'NodeRemoteShell'} ) {
		my $dsh_context_defaults = xCAT::DSHContext->context_defaults;
		$defaults{'NodeRemoteShell'} =
		  $$dsh_context_defaults{'NodeRemoteShell'};
	}

	return \%defaults;
}

=head3
        context_properties

        Configure the user specified context properties for the DSH context.
        These properties are configured by the user through environment
        variables or external configuration files.

        Arguments:
        	None

        Returns:
        	A reference to a hash table of user-configured properties for
        	the DSH context.
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:
        	$properties = DSH->config_properties

        Comments:

=cut

sub context_properties {
	my %properties = ();

	$properties{'DCP_DEVICE_OPTS'} = $ENV{'DCP_DEVICE_OPTS'};
	$properties{'DCP_DEVICE_RCP'}  = $ENV{'DCP_DEVICE_RCP'}
	  || $ENV{'DCP_DEVICE_COPY_CMD'};
	$properties{'DCP_NODE_OPTS'} = $ENV{'DCP_NODE_OPTS'};
	$properties{'DCP_NODE_RCP'}  = $ENV{'DCP_NODE_RCP'} || $ENV{'DCP_COPY_CMD'};
	$properties{'DSH_CONTEXT'}   = $ENV{'DSH_CONTEXT'};
	$properties{'DSH_DEVICE_LIST'} = $ENV{'DSH_DEVICE_LIST'};
	$properties{'DSH_DEVICE_OPTS'} = $ENV{'DSH_DEVICE_OPTS'}
	  || $ENV{'DSH_DEVICE_REMOTE_OPTS'};
	$properties{'DSH_DEVICE_RCP'} = $ENV{'DSH_DEVICE_RCP'};
	$properties{'DSH_DEVICE_RSH'} = $ENV{'DSH_DEVICE_RSH'}
	  || $ENV{'DSH_DEVICE_REMOTE_CMD'};
	$properties{'DSH_ENVIRONMENT'}    = $ENV{'DSH_ENVIRONMENT'};
	$properties{'DSH_FANOUT'}         = $ENV{'DSH_FANOUT'};
	$properties{'DSH_LOG'}            = $ENV{'DSH_LOG'};
	$properties{'DSH_NODEGROUP_PATH'} = $ENV{'DSH_NODEGROUP_PATH'};
	$properties{'DSH_NODE_LIST'}      = $ENV{'DSH_NODE_LIST'}
	  || $ENV{'DSH_LIST'}
	  || $ENV{'WCOLL'};
	$properties{'DSH_NODE_OPTS'} = $ENV{'DSH_NODE_OPTS'}
	  || $ENV{'DSH_REMOTE_OPTS'};
	$properties{'DSH_NODE_RCP'} = $ENV{'DSH_NODE_RCP'};
	$properties{'DSH_NODE_RSH'} = $ENV{'DSH_NODE_RSH'}
	  || $ENV{'DSH_REMOTE_SHELL'}
	  || $ENV{'DSH_REMOTE_CMD'};
	$properties{'DSH_OUTPUT'} = $ENV{'DSH_OUTPUT'};
	$properties{'DSH_PATH'}   = $ENV{'DSH_PATH'};
	$properties{'DSH_REPORT'} = $ENV{'DSH_REPORT'}
	  || $ENV{'DSH_REPORTS_DIRECTORY'};
	$properties{'DSH_SYNTAX'}  = $ENV{'DSH_SYNTAX'};
	$properties{'DSH_TIMEOUT'} = $ENV{'DSH_TIMEOUT'};
	$properties{'RSYNC_RSH'}   = $ENV{'RSYNC_RSH'};

	if($ENV{'DSH_ON_HMC'}){
		$properties{'DSH_NODE_RCP'} = '/usr/hmcrbin/scp';
		$properties{'DSH_NODE_RSH'} = '/usr/hmcrbin/ssh';
	}
	return \%properties;
}

=head3
        all_nodegroups

        Returns an array of all node group names in the DSH context

        Arguments:
        	None

        Returns:
        	An array of node group names
                
        Globals:
        	$nodegroup_path
    
        Error:
        	None
    
        Example:
        	@nodegroups = DSH->all_nodegroups;

        Comments:

=cut

sub all_nodegroups {
	my @nodegroups = ();

	if ($nodegroup_path) {
		opendir( DIR, $nodegroup_path );

		while ( my $nodegroup = readdir(DIR) ) {
			( $nodegroup !~ /^\./ ) && push @nodegroups, $nodegroup;
		}

		closedir DIR;
	}

	return @nodegroups;
}

=head3
        nodegroup_members

        Given a node group in the DSH context, this routine expands the
        membership of the node group and returns a list of its members.

        Arguments:
        	$nodegroup - node group name

        Returns:
        	An array of node group members
                
        Globals:
        	$nodegroup_path
    
        Error:
        	None
    
        Example:
        	$members = DSH->nodegroup_members('MyGroup1');

        Comments:

=cut

sub nodegroup_members {
	my ( $class, $nodegroup ) = @_;

	my %resolved_nodes   = ();
	my %unresolved_nodes = ();

	my $nodes = DSH->read_target_file("$nodegroup_path/$nodegroup");

	!$nodes && return undef;

	my @members = ();

	foreach $node (@$nodes) {
		if ( $node =~ /@/ ) {
			xCAT::MsgUtils->message("E",
				"$node is not a valid name for group $nodegroup");
		}

		else {
			push @members, $node;
		}
	}

	DSHContext->resolve_hostnames( \%resolved_nodes, \%unresolved_nodes,
		@members );

	@members = keys(%resolved_nodes);
	return \@members;
}

=head3
        all_nodes

        Returns an array of all node names in the DSH context

        Arguments:
        	None

        Returns:
        	An array of node names
                
        Globals:
        	$nodegroup_path
    
        Error:
        	None
    
        Example:
        	@nodes = DSH->all_nodes;

        Comments:

=cut

sub all_nodes {
	my $build_cache = undef;

	if ( -e "$ENV{'HOME'}/.dsh/$nodegroup_path/AllNodes" ) {
		my @stat_path     = stat $nodegroup_path;
		my @stat_allnodes =
		  stat "$ENV{'HOME'}/.dsh/$nodegroup_path/AllNodes.dsh";

		if ( $stat_path[9] > $stat_allnodes[9] ) {
			$build_cache = 1;
		}

		else {
			if ($nodegroup_path) {
				opendir( DIR, $nodegroup_path );

				while ( my $nodegroup = readdir(DIR) ) {

					if ( $nodegroup !~ /^\./ ) {
						my @stat_file = stat $nodegroup;
						( $stat_file[9] > $stat_allnodes[9] )
						  && ( $build_cache = 1 );
					}

					last if $build_cache;
				}

				closedir DIR;
			}
		}
	}

	else {
		$build_cache = 1;
	}

	if ($build_cache) {
		my @nodegroups = DSH->all_nodegroups;

		my @nodes = ();

		foreach $nodegroup (@nodegroups) {
			push @nodes, @{ DSH->nodegroup_members($nodegroup) };
		}

		if ( !( -d "$ENV{'HOME'}/.dsh/$nodegroup_path" ) ) {
			eval { mkpath( "$ENV{'HOME'}/.dsh/$nodegroup_path") };
			if ($@) {
				 xCAT::MsgUtils->message(
					"E",
				" Cannot make directory: $ENV{'HOME'}/.dsh/$nodegroup_path\n");
				return undef;
			}
		}

		DSH->write_target_file( "$ENV{'HOME'}/.dsh/$nodegroup_path/AllNodes",
			@nodes );
		return @nodes;
	}

	else {
		my $nodes =
		  DSH->read_target_file("$ENV{'HOME'}/.dsh/$nodegroup_path/AllNodes");
		return @$nodes;
	}
}

=head3
        read_target_file

        Processes the given filename and stores all targets in the file in an
        array

        Arguments:
        	$filename - file to read target names from

        Returns:
        	A reference to an array of target names
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:
        	DSH->read_target_file('/tmp/target_file');

        Comments:

=cut

sub read_target_file {
	my ( $class, $filename ) = @_;

	my %targets = ();

	if ( open( FILE, $filename ) ) {

		while ( my $target = <FILE> ) {
			$target =~ /^\s*#/     && next;
			$target =~ /^\s*$/     && next;
			$target =~ /;/         && next;
			$target =~ /\S+\s+\S+/ && next;
			$target =~ s/\s+$//;
			chomp($target);
			$targets{$target}++;
		}

		close FILE;

		my @target_list = keys(%targets);
		return \@target_list;
	}

	else {
		xCAT::MsgUtils->message( "E", "Cannot open file: $filename\n"); 
		return undef;
	}
}

=head3
        write_target_file

        Writes a list of supplied targets to a specified file.  Each target name
        is written to one line

        Arguments:
        	$filename - file to write target names
        	@targets - array of target names to write

        Returns:
        	None
                
        Globals:
        	None
    
        Error:
        	None
    
        Example:
        	DSH->read_target_file('/tmp/target_file');

        Comments:

=cut

sub write_target_file {
	my ( $class, $filename, @targets ) = @_;

	if ( open( FILE, ">$filename" ) ) {

		print FILE "#\n";
		print FILE "# DSH Utilities Target File\n";
		print FILE "#\n";

		foreach $target (@targets) {
			print FILE "$target\n";
		}

		close FILE;
	}

	else {
		xCAT::MsgUtils->message("E", "Error writing file $filename");
	}
}

sub query_node {
	my ( $class, $node ) = @_;
	my $res = 0;

	$~ = "NODES";
	NetworkUtils->tryHost( $node, \$res );
	if ($res) {
		print("$node : Valid\n");
	}
	else {
		print("$node : Invalid\n");
	}

	format NODES =
@<<<<<<<<<<<<<<<<<<<<<<<<<<<<<	@<<<<<<<<<<<<<<<<<
$node, $status
.

}

sub query_group {
	my ( $class, $group ) = @_;
	my @dsh_groups = all_nodegroups();

	$~ = "GROUPS";
	if ( grep( /^$group$/, @dsh_groups ) ) {
		print("$group : Valid\n");
	}
	else {
		print("$group : Invalid\n");
	}
}

1;    #end
