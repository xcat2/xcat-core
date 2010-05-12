#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html

package xCAT::RSYNC;

# cannot use strict
use base xCAT::DSHRemoteShell;

# Determine if OS is AIX or Linux
# Configure standard locations of commands based on OS

if ($^O eq 'aix')
{

    if (-e ("/usr/bin/rsync")) {
      our $RSYNC_CMD = '/usr/bin/rsync';
    } else {
      our $RSYNC_CMD = '/usr/local/bin/rsync';
    }
}

if ($^O eq 'linux')
{
    our $RSYNC_CMD = '/usr/bin/rsync';
}
#-----------------------------------------------------------------------

=head3
        remote_copy_command

        This routine constructs an rsync remote copy command using the
        given arguments

        Arguments:
        	$class - Calling module name (discarded)
        	$config - Reference to copy command configuration hash table
        	$exec_path - Path to rsync executable

        Returns:
        	A command array for the rsync command with the appropriate
        	arguments as defined in the $config hash table
                
        Globals:
        	None
    
        Error:
        	None        	
    
        Example:
        	xCAT::RSYNC->remote_copy_command($config_hash, '/usr/bin/rsync');

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

#-----------------------------------------------------------------------

sub remote_copy_command
{
    my ($class, $config, $exec_path) = @_;

    $exec_path || ($exec_path = $RSYNC_CMD);

    # see if we are using rsh or ssh on AIX
    my $usersh=0;
    if ($^O eq 'aix')
    {
      my @useSSH = xCAT::Utils->get_site_attribute("useSSHonAIX");
      if (defined($useSSH[0])) { 
        $useSSH[0] =~ tr/a-z/A-Z/;    # convert to upper
        if (($useSSH[0] eq "0") || ($useSSH[0] eq "NO"))
        {
         $usersh=1;
        }
      }
    }


    my @command = ();
    my $rsyncfile;
    if ($$config{'destDir_srcFile'})
    {

        my $sync_opt;
        if ($^O eq 'aix')
        {
            if (-e ("/usr/bin/rsync")) {
             if ($usersh == 0) { # using ssh
                $sync_opt = '--rsync-path /usr/bin/rsync ';
             } else {
                $sync_opt = '--rsh /bin/rsh --rsync-path /usr/bin/rsync ';
             }
            } else {
             if ($usersh == 0) { # using ssh
                $sync_opt = '--rsync-path /usr/local/bin/rsync ';
             } else {
                $sync_opt = '--rsh /bin/rsh --rsync-path /usr/local/bin/rsync ';
             }
            }
        }
        else #linux
        {
            $sync_opt = '--rsync-path /usr/bin/rsync ';
        }

        $sync_opt .= '-Lpotz ';
        $sync_opt .= $$config{'options'};
        if ($::SYNCSN == 1)
        {    # syncing service node
            $rsyncfile = "/tmp/rsync_$$config{'dest-host'}";
            $rsyncfile .= "_s";
        }
        else
        {
            $rsyncfile = "/tmp/rsync_$$config{'dest-host'}";
        }
        open RSCYCCMDFILE, "> $rsyncfile"
          or die "Can not open file $rsyncfile";
        my $dest_dir_list = join ' ', keys %{$$config{'destDir_srcFile'}};
        my $dest_user_host = $$config{'dest-host'};
        if ($$config{'dest-user'})
        {
            $dest_user_host =
              "$$config{'dest-user'}@" . "$$config{'dest-host'}";
        }
        print RSCYCCMDFILE "#!/bin/sh\n";
        if ($usersh == 0) { # using ssh
          print RSCYCCMDFILE
            "/usr/bin/ssh  $dest_user_host '/bin/mkdir -p $dest_dir_list'\n";
        } else {
          print RSCYCCMDFILE
            "/usr/bin/rsh  $dest_user_host '/bin/mkdir -p $dest_dir_list'\n";
        }
        foreach my $dest_dir (keys %{$$config{'destDir_srcFile'}})
        {
            my @src_file =
              @{$$config{'destDir_srcFile'}{$dest_dir}{'same_dest_name'}};

            #Remove a file from the list if it does not exist
            #@src_file = map { $_ if -e $_; } @src_file;
            my $src_file_list = join ' ', @src_file;
            if ($src_file_list)
            {
                print RSCYCCMDFILE
                  "$exec_path $sync_opt $src_file_list $dest_user_host:$dest_dir\n";
            }
            my %diff_dest_hash =
              %{$$config{'destDir_srcFile'}{$dest_dir}{'diff_dest_name'}};
            foreach my $src_file_diff_dest (keys %diff_dest_hash)
            {
                next if !-e $src_file_diff_dest;
                my $diff_basename = $diff_dest_hash{$src_file_diff_dest};
                print RSCYCCMDFILE
                  "$exec_path $sync_opt $src_file_diff_dest $dest_user_host:$dest_dir/$diff_basename\n";
            }

        }

        #print RSCYCCMDFILE "/bin/rm -f $rsyncfile\n";
        close RSCYCCMDFILE;
        chmod 0755, $rsyncfile;
        @command = ('/bin/sh', '-c', $rsyncfile);

    }
    else
    {
        my @src_files = ();
        my @dest_file = ();

        my @src_file_list = split $::__DCP_DELIM, $$config{'src-file'};

        foreach $src_file (@src_file_list)
        {
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
        if ($usersh == 1) { # using rsh 
          push @command, "--rsh";
          push @command, "/bin/rsh";
        }
        $$config{'preserve'} && push @command, ('-p', '-t');
        $$config{'recursive'} && push @command, '-r';

        if ($$config{'options'})
        {
            my @options = split ' ', $$config{'options'};
            push @command, @options;
        }

        push @command, @src_files;
        push @command, (join '', @dest_file);

    }

    return @command;
}

1;
