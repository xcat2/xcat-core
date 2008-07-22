#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::RSH;
# cannot use strict
# cannot use strict
use base xCAT::DSHRemoteShell;

# Determine if OS is AIX or Linux
# Configure standard locations of commands based on OS

if ( $^O eq 'aix' ) {
	our $RCP_CMD = '/bin/rcp';
	our $RSH_CMD = '/bin/rsh';
}

if ( $^O eq 'linux' ) {
	our $RCP_CMD = '/usr/bin/rcp';
	our $RSH_CMD = '/usr/bin/rsh';
}

=head3
        remote_shell_command

        This routine constructs an rsh remote shell command using the
        given arguments

        Arguments:
        	$class - Calling module name (discarded)
        	$config - Reference to remote shell command configuration hash table
        	$exec_path - Path to rsh executable

        Returns:
        	A command array for the rsh command with the appropriate
        	arguments as defined in the $config hash table
               
        Globals:
        	$RSH_CMD
    
        Error:
        	None
    
        Example:
        	xCAT::RSH->remote_shell_command($config_hash, '/usr/bin/rsh');

        Comments:
        	$config hash table contents:
        	
        		$config{'command'} - command to execute on destination host
        		$config{'hostname'} - destination hostname where command will be executed
        		$config{'options'} - user ID of destination host        	
        		$config{'user'} - user ID of destination host
=cut

sub remote_shell_command {
	my ( $class, $config, $exec_path ) = @_;

	$exec_path || ( $exec_path = $RSH_CMD );

	my @command = ();

	push @command, $exec_path;
	push @command, $$config{'hostname'};

	if ( $$config{'user'} ) {
		push @command, '-l';
		push @command, $$config{'user'};
	}

	if ( $$config{'options'} ) {
		my @options = split ' ', $$config{'options'};
		push @command, @options;
	}

	push @command, $$config{'command'};

	return @command;
}

=head3
        remote_copy_command

        This routine constructs an rcp remote copy command using the
        given arguments

        Arguments:
        	$class - Calling module name (discarded)
        	$config - Reference to copy command configuration hash table
        	$exec_path - Path to rcp executable

        Returns:
        	A command array for the rcp command with the appropriate
        	arguments as defined in the $config hash table
                
        Globals:
        	$RCP_CMD
    
        Error:
        	None        	
    
        Example:
        	xCAT::RSH->remote_copy_command($config_hash, '/usr/bin/rcp');

        Comments:
        	$config hash table contents:
        	
        		$config{'dest-file'} - path to file on destination host
        		$config{'dest-host'} - destination hostname where file will be copied
        		$config{'dest-user'} - user ID of destination host
        		$config{'options'} - custom options string to include in scp command
        		$config{'preserve'} - configure the preserve attributes on scp command
        		$config{'recursive'} - configure the recursive option on scp command        	
        		$config{'src-file'} - path to file on source host
        		$config{'src-host'} - hostname where source file is located
        		$config{'src-user'} - user ID of source host

=cut

sub remote_copy_command {
	my ( $class, $config, $exec_path ) = @_;

	$exec_path || ( $exec_path = $RCP_CMD );

	my @command   = ();
	my @src_files = ();
	my @dest_file = ();

	my @src_file_list = split $::__DCP_DELIM, $$config{'src-file'};

	foreach $src_file (@src_file_list) {
		my @src_path = ();
		$$config{'src-user'} && push @src_path, "$$config{'src-user'}@";
		$$config{'src-host'} && push @src_path, "$$config{'src-host'}:";
		$$config{'src-file'} && push @src_path, $src_file;
		push @src_files, ( join '', @src_path );
	}

	$$config{'dest-user'} && push @dest_file, "$$config{'dest-user'}@";
	$$config{'dest-host'} && push @dest_file, "$$config{'dest-host'}:";
	$$config{'dest-file'} && push @dest_file, $$config{'dest-file'};

	push @command, $exec_path;
	$$config{'preserve'}  && push @command, '-p';
	$$config{'recursive'} && push @command, '-r';

	if ( $$config{'options'} ) {
		my @options = split ' ', $$config{'options'};
		push @command, @options;
	}

	push @command, @src_files;
	push @command, ( join '', @dest_file );

	return @command;
}

1;
