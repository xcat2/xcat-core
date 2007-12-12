#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::SSH;

use base xCAT::DSHRemoteShell;

# Determine if OS is AIX or Linux
# Configure standard locations of commands based on OS

if ( $^O eq 'aix' ) {
	our $SCP_CMD = '/usr/bin/scp';
	our $SSH_CMD = '/usr/bin/ssh';
}

if ( $^O eq 'linux' ) {
	our $SCP_CMD = '/usr/bin/scp';
	our $SSH_CMD = '/usr/bin/ssh';
}

# Store the version string of SSH

our $ssh_version = xCAT::SSH->validate_ssh_version;

=head3
        remote_shell_command

        This routine constructs an ssh remote shell command using the
        given arguments

        Arguments:
        	$class - Calling module name (discarded)
        	$config - Reference to remote shell command configuration hash table
        	$exec_path - Path to ssh executable

        Returns:
        	A command array for the ssh command with the appropriate
        	arguments as defined in the $config hash table
               
        Globals:
        	$ssh_version
        	$SSH_CMD
    
        Error:
        	None
    
        Example:
        	xCAT::SSH->remote_shell_command($config_hash, '/usr/bin/ssh');

        Comments:
        	$config hash table contents:
        	
        		$config{'command'} - command to execute on destination host
        		$config{'hostname'} - destination hostname where command will be executed
        		$config{'options'} - user ID of destination host        	
        		$config{'user'} - user ID of destination host
=cut

sub remote_shell_command {
	my ( $class, $config, $exec_path ) = @_;

	$exec_path || ( $exec_path = $SSH_CMD );
	$exec_path = '/usr/hmcrbin/ssh' if $$config{'ishmc'};

	my @command = ();

	push @command, $exec_path;

	if ( $$config{'options'} ) {
		my @options = split ' ', $$config{'options'};
		push @command, @options;
	}

	if ( $ssh_version eq 'OpenSSH' ) {
		push @command, '-o';
		push @command, 'BatchMode=yes';

		( $$config{'options'} !~ /-X/ ) && push @command, '-x';
	}

	$$config{'user'} && ( $$config{'user'} .= '@' );
	push @command, "$$config{'user'}$$config{'hostname'}";
	push @command, $$config{'command'};

	return @command;
}

=head3
        remote_copy_command

        This routine constructs an scp remote copy command using the
        given arguments

        Arguments:
        	$class - Calling module name (discarded)
        	$config - Reference to copy command configuration hash table
        	$exec_path - Path to scp executable

        Returns:
        	A command array for the scp command with the appropriate
        	arguments as defined in the $config hash table
                
        Globals:
        	$ssh_version
        	$SCP_CMD
    
        Error:
        	None        	
    
        Example:
        	xCAT::SSH->remote_copy_command($config_hash, '/usr/bin/scp');

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

	$exec_path || ( $exec_path = $SCP_CMD );
	$exec_path = '/usr/hmcrbin/scp' if $$config{'ishmc'};

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

	( $ssh_version eq 'OpenSSH' ) && push @command, '-B';
	push @command, @src_files;
	push @command, ( join '', @dest_file );

	return @command;
}

=head3
        validate_ssh_version

        This subroutine determines if OpenSSH is the version of the SSH command
        defined in $SSH_CMD

        Arguments:
        	None

        Returns:
        	The string 'OpenSSH' if OpenSSH is used
        	undef otherwise
                
        Globals:
        	$SSH_CMD
    
        Error:
        	None
    
        Example:
        	$ssh_version = xCAT::SSH->validate_ssh_version;

        Comments:

=cut

sub validate_ssh_version {
	my $command = "$SSH_CMD -V 2>&1";
	my @output  = `$command`;

	( $output[0] =~ /OpenSSH/ ) && return 'OpenSSH';
	return undef;
}

1;
