#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::SSH;

# cannot use strict
use base xCAT::DSHRemoteShell;
# Determine if OS is AIX or Linux
# Configure standard locations of commands based on OS

if ($^O eq 'aix') {
    our $SCP_CMD = '/usr/bin/scp';
    our $SSH_CMD = '/usr/bin/ssh';
}

if ($^O eq 'linux') {
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
    my ($class, $config, $exec_path) = @_;

    $exec_path || ($exec_path = $SSH_CMD);
    $exec_path = '/usr/hmcrbin/ssh' if $$config{'ishmc'};

    my @command = ();

    push @command, $exec_path;

    if ($$config{'options'}) {
        my @options = split ' ', $$config{'options'};
        push @command, @options;
    }

    if ($ssh_version eq 'OpenSSH') {
        push @command, '-o';
        push @command, 'BatchMode=yes';

        ($$config{'options'} !~ /-X/) && push @command, '-x';
    }

    $$config{'user'} && ($$config{'user'} .= '@');
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
    my ($class, $config, $exec_path) = @_;

    $exec_path || ($exec_path = $SCP_CMD);
    $exec_path = '/usr/hmcrbin/scp' if $$config{'ishmc'};

    my @command   = ();
    my @src_files = ();
    my @dest_file = ();

    if ($$config{'destDir_srcFile'}){
        my $dest_dir_list = join ' ', keys %{ $$config{'destDir_srcFile'} };
        my $dest_user_host = $$config{'dest-host'};
        if ($::SYNCSN == 1)
        {                                                 # syncing service node
            #todo
            $scpfile = "/tmp/scp_$$config{'dest-host'}";
        }
        else
        {
            $scpfile = "/tmp/scp_$$config{'dest-host'}";
        }

        open SCPCMDFILE, "> $scpfile"
          or die "Can not open file $scpfile";
        if (getpwnam($$config{'dest-user'}))
        {
            $dest_user_host =
              "$$config{'dest-user'}@" . "$$config{'dest-host'}";
        }
        if ($$config{'trace'}) {
            print SCPCMDFILE "#!/bin/sh -x\n";
        } else {
            print SCPCMDFILE "#!/bin/sh\n";
        }

        print SCPCMDFILE
            "/usr/bin/ssh  $dest_user_host '/bin/mkdir -p $dest_dir_list'\n";

        foreach my $dest_dir (keys %{ $$config{'destDir_srcFile'} }){
            if($$config{'destDir_srcFile'}{$dest_dir}{'same_dest_name'}){
                my @src_file =
                  @{ $$config{'destDir_srcFile'}{$dest_dir}{'same_dest_name'} };
                my $src_file_list = join ' ', @src_file;
                print SCPCMDFILE
                    "$exec_path -p -r $src_file_list $dest_user_host:$dest_dir\n";
            }

            if($$config{'destDir_srcFile'}{$dest_dir}{'diff_dest_name'}){
                my %diff_dest_hash =
                    %{ $$config{'destDir_srcFile'}{$dest_dir}{'diff_dest_name'} };
                foreach my $src_file_diff_dest (keys %diff_dest_hash)
                {
                    my $diff_basename = $diff_dest_hash{$src_file_diff_dest};
                    print SCPCMDFILE
                        "$exec_path -p -r $src_file_diff_dest $dest_user_host:$dest_dir/$diff_basename\n";
                }
            }
        }

        close SCPCMDFILE;
        chmod 0755, $scpfile;
        @command = ('/bin/sh', '-c', $scpfile);
    }else{
        my @src_file_list = split $::__DCP_DELIM, $$config{'src-file'};

        foreach $src_file (@src_file_list) {
            my @src_path = ();
            $$config{'src-user'} && push @src_path, "$$config{'src-user'}@";
            $$config{'src-host'} && push @src_path, "$$config{'src-host'}:";
            $$config{'src-file'} && push @src_path, $src_file;
            push @src_files, (join '', @src_path);
        }

        $$config{'dest-user'} && push @dest_file, "$$config{'dest-user'}@";
        $$config{'dest-host'} && push @dest_file, "$$config{'dest-host'}:";
        $$config{'dest-file'} && push @dest_file, $$config{'dest-file'};

        push @command, $exec_path;
        $$config{'preserve'}  && push @command, '-p';
        $$config{'recursive'} && push @command, '-r';

        if ($$config{'options'}) {
            my @options = split ' ', $$config{'options'};
            push @command, @options;
        }

        ($ssh_version eq 'OpenSSH') && push @command, '-B';
        push @command, @src_files;
        push @command, (join '', @dest_file);
    }
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

    ($output[0] =~ /OpenSSH/) && return 'OpenSSH';
    return undef;
}

1;
