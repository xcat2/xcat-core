#!/usr/bin/env perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#

package xCAT::RemoteShellExp;

#-----------------------------------------------------------------------------

=head1   RemoteShellExp 
 Uses perl  Expect to set up ssh passwordless login on the input node list
 Called from  xdsh  <nodelist> -K command
 It works for node and devices ( such as QLogic Switch).
 See man xdsh.
 It works for root and non-root userids.

 Environment Variables input to drive the setup:

   DSH_REMOTE_CMD  set to path to remote shell (ssh)
     root password must agree on all the nodes

   XCAT_ROOT set to root of xCAT install

   DSH_REMOTE_PASSWORD  - to_user password for -s option  required to sendkeys)
			  Note this is obtained in the xdsh client frontend.

   SSH_SETUP_COMMAND - Command to be sent to the IB switch to setup SSH.

   DSH_FROM_USERID_HOME - The home directory of the userid from
                  where the ssh keys will be obtained
                  to send

   DSH_FROM_USERID - The userid from where the ssh keys will be obtained
                  to send
                  to the node,  or generated and then obtained to send to the
                  node.
   DSH_TO_USERID - The userid on the node where the ssh keys will be updated.
   DSH_ENABLE_SSH - Node to node root passwordless ssh will be setup.
   DSH_ZONE_SSHKEYS  - directory containing the zones root .ssh keys 

 Usage: remoteshellexp
   [-t node list]  test ssh connection to the node 
   [-k] Generates the ssh keys needed , for the user on the MN. 
   [-s node list]  copies the ssh keys to the nodes 
   optional $timeout = timeout value for the expect.  Usually from the xdsh -t flag
   default timeout is 10 seconds
    exit 0 - good
    exit 1 - abort
    exit 2 - usage error

Examples:
$rc=xCAT::RemoteShellExp->remoteshellexp("k",$callback,$remoteshellcmd,$nodes,$timeout); 
$rc=xCAT::RemoteShellExp->remoteshellexp("s",$callback,$remoteshellcmd,$nodes,$timeout); 
$rc=xCAT::RemoteShellExp->remoteshellexp("t",$callback,$remoteshellcmd,$nodes,$timeout); 

=cut

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
    $::XCATDIR  = $ENV{'XCATDIR'}  ? $ENV{'XCATDIR'}  : '/etc/xcat';
}


use lib "$::XCATROOT/lib/perl";
use xCAT::Utils;
use Getopt::Long;
use xCAT::MsgUtils;
use Expect;
use strict;

#-----------------------------------------------------------------------------
sub remoteshellexp 
{
  my ($class, $flag, $callback, $remoteshell, $nodes, $timeout) = @_;
  my $rc=0;
  $::CALLBACK = $callback;
  if (!($flag))
  {
       my $rsp = {};
       $rsp->{error}->[0] = 
       "No flag provide to remoteshellexp.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 2);
        return 2;
  }

  if (($flag ne "k") && ($flag ne "t") && ($flag ne "s")) {
       my $rsp = {};
       $rsp->{error}->[0] = 
        "Invalid  flag  $flag provided.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
       return 2;
       
  }
  my  $expecttimeout=10; # default
  if (defined($timeout)) {  # value supplied
     $expecttimeout=$timeout;
  }

  # for -s flag must have nodes and a $to_userid password
  my $to_user_password;
  if ($ENV{'DSH_REMOTE_PASSWORD'}) {
     $to_user_password=$ENV{'DSH_REMOTE_PASSWORD'};
  } 
  if ($flag eq "s"){
	if (!$to_user_password) {
       my $rsp = {};
       $rsp->{error}->[0] = 
        "The DSH_REMOTE_PASSWORD environment variable has not been set to the user id password on the node which will have their ssh keys updated (ususally root).";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
       return 2;
	}
	if (!$nodes) {
       my $rsp = {};
       $rsp->{error}->[0] = 
        "No nodes were input to update the user's ssh keys.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
       return 2;
	}
  }
  my $ssh_setup_cmd;
  my $from_userid;
  my $to_userid;
  my $home;
  my $remotecopy;
  # if caller input a path to ssh remote command, use it
  if ($ENV{'DSH_REMOTE_CMD'}) {
     $remoteshell=$ENV{'DSH_REMOTE_CMD'};
  } else {
    if (!$remoteshell) {
     $remoteshell="/usr/bin/ssh";
    }
  }
  # figure out path to scp
  my ($path,$ssh) = split(/ssh/,$remoteshell);
  $remotecopy=$path . "scp";
  # if caller input the ssh setup command (such as for IB Switch)
  if ($ENV{'SSH_SETUP_COMMAND'}) {
     $ssh_setup_cmd=$ENV{'SSH_SETUP_COMMAND'};
  }
  # set User on the Management node that has the ssh keys 
  # this id can be a local (non-root) id as well as root 
  if ($ENV{'DSH_FROM_USERID'}) {
     $from_userid=$ENV{'DSH_FROM_USERID'};
  } else {
     $from_userid="root";
  }
  # set User  on the node where we will send the keys 
  # this id can be a local id as well as root 
  if ($ENV{'DSH_TO_USERID'}) {
     $to_userid=$ENV{'DSH_TO_USERID'};
  } else {
     $to_userid="root";
  }
  # set User home directory to find the ssh public key to send 
  # For non-root ids information may not be in /etc/passwd
  #  but elsewhere like LDAP 
   
  if ($ENV{'DSH_FROM_USERID_HOME'}) {
       $home=$ENV{'DSH_FROM_USERID_HOME'};
  } else {
      $home=xCAT::Utils->getHomeDir($from_userid);
  }
  # This indicates we will generate new ssh keys for the user,
  # if they are not already there
  # unless using zones
   my $key="$home/.ssh/id_rsa";
   my $key2="$home/.ssh/id_rsa.pub";
   # Check to see if empty
   if (-z $key) {
         my $rsp = {};
         $rsp->{error}->[0] = 
         "The $key file is empty. Remove it and rerun the command.";
         xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
         return 1;

  } 
  if (-z $key2) {
         my $rsp = {};
         $rsp->{error}->[0] = 
         "The $key2 file is empty. Remove it and rerun the command.";
         xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
         return 1;

  } 
  if (($flag eq "k") && (!(-e $key))) 
  {
     # updating keys and the key file does not exist 
     $rc=xCAT::RemoteShellExp->gensshkeys($expecttimeout);
  }
  # send ssh keys to the nodes/devices, to setup passwordless ssh 
  if ($flag eq "s")
  {
    if (!($nodes)) {
         my $rsp = {};
         $rsp->{error}->[0] = 
         "There are no nodes defined to update the ssh keys.";
         xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
         return 1;
    }
    if ($ssh_setup_cmd) { # setup ssh on devices
     $rc=xCAT::RemoteShellExp->senddeviceskeys($remoteshell,$remotecopy,$to_userid,$to_user_password,$home,$ssh_setup_cmd,$nodes, $expecttimeout);
    } else {  #setup ssh on nodes
     if ($ENV{'DSH_ZONE_SSHKEYS'}) {   # if using zones the override the location of the keys
        $home= $ENV{'DSH_ZONE_SSHKEYS'};
     }  
     $rc=xCAT::RemoteShellExp->sendnodeskeys($remoteshell,$remotecopy,$to_userid,$to_user_password,$home,$nodes, $expecttimeout);
    } 
  }
  # test ssh setup on the node
  if ($flag eq "t")
  {
     $rc=xCAT::RemoteShellExp->testkeys($remoteshell,$to_userid,$nodes,$expecttimeout);
  }
  return $rc;
}

#-----------------------------------------------------------------------------

=head3    gensshkeys 
	
      Generates new ssh keys for the input userid on the MN, if they do not
      already exist.  Test for id_rsa key existence. 

=cut

#-----------------------------------------------------------------------------

sub gensshkeys 

{
    my ($class, $expecttimeout) = @_;
    my $keygen;
    my $timeout  = $expecttimeout;    # sets Expect default timeout, 0 accepts immediately
    my $keygen_sent = 0;
    my $prompt1   = 'Generating public/private rsa';
    my $prompt2   = 'Enter file.*:';
    my $prompt3   = 'Enter passphrase.*:';
    my $prompt4   = 'Enter same passphrase.*:';
    my $expect_log   = undef;
    my $debug        = 0;
    if ($::VERBOSE)
    {
        $debug = 1;
    }
    $keygen = new Expect;
    
    #  run /usr/bin/ssh-keygen -t rsa
    # prompt1   = 'Generating public/private rsa';
    # prompt2   = 'Enter file.*:';
    # -re "\r"
    # prompt3   = 'Enter passphrase.*:';
    # -re "\r"
    # prompt4   = 'Enter same passphrase.*:';
    # -re "\r"


    # disable command echoing
    #$keygen->slave->stty(qw(sane -echo));

    #
    # exp_internal(1) sets exp_internal debugging
    # to STDERR.
    #
    #$keygen->exp_internal(1);
    $keygen->exp_internal($debug);

    #
    # log_stdout(0) prevent the program's output from being shown.
    #  turn on if debugging error
    #$keygen->log_stdout(1);
    $keygen->log_stdout($debug);

    # Run the ssh key gen command
    my $spawncmd = "/usr/bin/ssh-keygen -t rsa";
    unless ($keygen->spawn($spawncmd))
    {
       my $rsp = {};
       $rsp->{error}->[0] = 
        "Unable to run $spawncmd.";
       xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
       return 1;

    }

    #
    #ssh-keygen prompts starts here 
    #

    my @result = $keygen->expect(
        $timeout,
        [
         $prompt1,   # Generating public/private rsa
         sub {
             $keygen->send("\r");
             $keygen->clear_accum();
             $keygen->exp_continue();
           }
        ],
        [
         $prompt2,  # Enter file.*:
         sub {
             $keygen->send("\r");
             $keygen->clear_accum();
             $keygen->exp_continue();
           }
        ],
        [
         $prompt3, # Enter passphrase.*
         sub {
             $keygen->send("\r");
             $keygen->clear_accum();
             $keygen->exp_continue();
           }
        ],
        [
         $prompt4, # Enter same passphrase.
         sub {
             $keygen->send("\r");
             $keygen->clear_accum();
             $keygen->exp_continue();
           }
        ]
        );   # end prompts
    ##########################################
    # Expect error - report and quit
    ##########################################
    if (defined($result[1]))
    {
        my $msg = $result[1];
        $keygen->soft_close();
        if ($msg =~ /status 0/i) { # no error
          return 0;
        } else {
          my $rsp = {};
          $rsp->{error}->[0] =  $msg;
          xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
          return 1;
        }

    } else {
      $keygen->soft_close();
      return 0;
   }
}
#-----------------------------------------------------------------------------

=head3    testkeys 
	
      Test to see if the remoteshell setup worked 

=cut

#-----------------------------------------------------------------------------

sub testkeys 

{
    my ($class,$remoteshell,$to_userid,$nodes, $expecttimeout) = @_;
    my $testkeys;
    my $timeout  = $expecttimeout;    # sets Expect default timeout
    my $testkeys_sent = 0;
    my $prompt1   = 'Are you sure you want to continue connecting (yes/no)?';
    my $prompt2   = 'ssword:';
    my $prompt3   = 'Permission denied*';
    my $prompt4   = 'test.success';
    my $expect_log   = undef;
    my $debug        = 0;
    my $rc=1;   # default to error
    if ($::VERBOSE)
    {
        $debug = 1;
    }
    $testkeys = new Expect;
    
    #  run ssh <node> -l to_userid  echo test.success 
    # possible return
    # bad
    ##  Are you sure you want to continue connecting (yes/no)?
    ##  *ssword*
    ## Permission denied.
    # Good
    ## test.success

    # disable command echoing
    #$testkeys->slave->stty(qw(sane -echo));

    #
    # exp_internal(1) sets exp_internal debugging
    # to STDERR.
    #
    #$testkeys->exp_internal(1);
    $testkeys->exp_internal($debug);

    #
    # log_stdout(0) prevent the program's output from being shown.
    #  turn on if debugging error
    #$testkeys->log_stdout(1);
    $testkeys->log_stdout($debug);

    # Run the ssh key gen command
    my $spawncmd = "$remoteshell $nodes -l $to_userid echo test.success";
    unless ($testkeys->spawn($spawncmd))
    {
       my $rsp = {};
       $rsp->{error}->[0] = 
        "Unable to run $spawncmd.";
       xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
       return 1;

    }

    #
    #testkeys prompts starts here 
    #

    my @result = $testkeys->expect(
        $timeout,
        [
         $prompt1,  # Are you sure you want to ...
         sub {
             $rc= 1; 
             $testkeys->hard_close();         
           }
        ],
        [
         $prompt2,  # *ssword*
         sub {
             $rc= 1; 
             $testkeys->hard_close();         
           }
        ],
        [
         $prompt3,  # Permission denied
         sub {
             $rc= 1; 
             $testkeys->hard_close();         
           }
        ],
        [
         $prompt4, # test.success
         sub {
             $rc= 0; 
           }
        ]
        );   # end prompts
    ##########################################
    # Expect error - report and quit
    ##########################################
    if (defined($result[1]))
    {
        my $msg = $result[1];
        $testkeys->soft_close();
        if ($msg =~ /status 0/i) { # no error
          return 0;
        } else {
          my $rsp = {};
          $rsp->{error}->[0] =  $msg;
          xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
          return 1;
        }

    } else {
      $testkeys->soft_close();
      return $rc;
   }
}
#-------------------------------------------------------------------------------

=head3    sendnodeskeys 
	
      Setup the ssh keys on the nodes 

=cut

#-----------------------------------------------------------------------------

sub sendnodeskeys 

{
   my ($class,$remoteshell,$remotecopy,$to_userid,$to_userpassword,$home,$nodes, $expecttimeout) = @_;
    my $sendkeys;
    my $timeout  = $expecttimeout;    # sets Expect default timeout, 0 accepts immediately
    my $sendkeys_sent = 0;
    my $prompt1   = 'Are you sure you want to continue connecting (yes/no)?';
    my $prompt2   = 'ssword:';
    my $prompt3   = 'Permission denied*';
    my $expect_log   = undef;
    my $debug        = 0;
    my $rc=0;  
    if ($::VERBOSE)
    {
        $debug = 1;
    }
    # For each node
    #  make a temporary directory on the node
    #  run scp <nodename> -l <to user> /bin/mkdir -p /tmp/$to_userid/.ssh 
    #  xdsh has built an authorized_keys file for the node 
    #  in $HOME/.ssh/tmp/authorized_keys 
    #  copy to the node to the temp directory 
    #  scp $HOME/.ssh/tmp/authorized_keys to_userid@<node>:/tmp/$to_userid/.ssh
    #  scp $HOME/.ssh/id_rsa.pub to_userid@<node>:/tmp/$to_userid/.ssh
    #  Note if using zones,  the keys do not come from ~/.ssh but from the
    #  zone table, sshkeydir attribute.  For zones the userid is always root
    #  If you are going to enable ssh to ssh between nodes, then
    #  scp $HOME/.ssh/id_rsa to that temp directory on the node
    #  copy the script $HOME/.ssh/copy.sh to the node, it will do the 
    #  the work of setting up the user's ssh keys  and clean up
    #  ssh (run)  copy.sh on the node
    
    my @nodelist=split(/,/,$nodes);
    foreach my $node (@nodelist) {
      $sendkeys = new Expect;

      # disable command echoing
      #$sendkeys->slave->stty(qw(sane -echo));
      #
      # exp_internal(1) sets exp_internal debugging
      # to STDERR.
      #
      #$sendkeys->exp_internal(1);
      $sendkeys->exp_internal($debug);
      #
      # log_stdout(0) prevent the program's output from being shown.
      #  turn on if debugging error
      #$sendkeys->log_stdout(1);
      $sendkeys->log_stdout($debug);
   
      # command to make the temp directory on the node 
      my $spawnmkdir=
      "$remoteshell $node -l $to_userid /bin/mkdir -p /tmp/$to_userid/.ssh";  
      # command to copy the needed files to the node
    
      # send mkdir command 
      unless ($sendkeys->spawn($spawnmkdir))
      {
        my $rsp = {};
        $rsp->{error}->[0] = 
         "Unable to run $spawnmkdir on $node";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        next;
      }

      #
      #mkdir prompts starts here 
      #

      my @result = $sendkeys->expect(
        $timeout,
        [
         $prompt1,  # Are you sure you want to ...
         sub {
             $sendkeys->send("yes\r");
             $sendkeys->clear_accum();
             $sendkeys->exp_continue();
           }
        ],
        [
         $prompt2,  # *ssword*
         sub {
             $sendkeys->send("$to_userpassword\r");
             $sendkeys->clear_accum();
             $sendkeys->exp_continue();
           }
        ],
        [
         $prompt3,  # Permission denied
         sub {
             $rc= 1; 
             $sendkeys->hard_close(); 
           }
        ],
        );   # end prompts
        ##########################################
        # Expect error - report 
        ##########################################
        if (defined($result[1]))
        {
            my $msg = $result[1];
           if ($msg =~ /status 0/i) { # no error
              $rc=0;
            } else {
               if ($msg =~ /2:EOF/i) { # no error
                  $rc=0;
               } else {
                 my $rsp = {};
                 $rsp->{error}->[0] =  "mkdir:$node has error,$msg";
                 xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                 $rc=1;
               }
            }
        }
      $sendkeys->soft_close(); 

      #
      #copy files prompts starts here 
      #

      $sendkeys = new Expect;

      # disable command echoing
      #$sendkeys->slave->stty(qw(sane -echo));
      #
      # exp_internal(1) sets exp_internal debugging
      # to STDERR.
      #
      #$sendkeys->exp_internal(1);
      $sendkeys->exp_internal($debug);
      #
      # log_stdout(0) prevent the program's output from being shown.
      #  turn on if debugging error
      #$sendkeys->log_stdout(1);
      $sendkeys->log_stdout($debug);

      my $spawncopyfiles;
      if ($ENV{'DSH_ENABLE_SSH'}) { # we will enable node to node ssh 
         $spawncopyfiles=
        "$remotecopy $home/.ssh/id_rsa $home/.ssh/id_rsa.pub $home/.ssh/copy.sh $home/.ssh/tmp/authorized_keys $to_userid\@$node:/tmp/$to_userid/.ssh "; 
          
      } else {    # no node to node ssh ( don't send private key)
         $spawncopyfiles=
        "$remotecopy $home/.ssh/id_rsa.pub $home/.ssh/copy.sh $home/.ssh/tmp/authorized_keys $to_userid\@$node:/tmp/$to_userid/.ssh "; 
      }
      # send copy command 
      unless ($sendkeys->spawn($spawncopyfiles))
      {
        my $rsp = {};
        $rsp->{error}->[0] = 
         "Unable to run $spawncopyfiles on $node.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        next; 
      }

        @result = $sendkeys->expect(
        $timeout,
        [
         $prompt1,  # Are you sure you want to ...
         sub {
             $sendkeys->send("yes\r");
             $sendkeys->clear_accum();
             $sendkeys->exp_continue();
           }
        ],
        [
         $prompt2,  # *ssword*
         sub {
             $sendkeys->send("$to_userpassword\r");
             $sendkeys->clear_accum();
             $sendkeys->exp_continue();
           }
        ],
        [
         $prompt3,  # Permission denied
         sub {
             $rc= 1; 
             $sendkeys->hard_close(); 
             
           }
        ],
        );   # end prompts
        ##########################################
        # Expect error - report 
        ##########################################
        if (defined($result[1]))
        {
            my $msg = $result[1];
            if ($msg =~ /status 0/i) { # no error
              $rc=0;
            } else {
               if ($msg =~ /2:EOF/i) { # no error
                  $rc=0;
               } else {
                my $rsp = {};
                $rsp->{error}->[0] =  "copykeys:$node has error,$msg";
                xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                $rc=1;
              }
            }
        }
        $sendkeys->soft_close();

      #
      # ssh to the node to run  the copy.sh to setup the keys starts here
      #
      $sendkeys = new Expect;

      # disable command echoing
      #$sendkeys->slave->stty(qw(sane -echo));
      #
      # exp_internal(1) sets exp_internal debugging
      # to STDERR.
      #
      #$sendkeys->exp_internal(1);
      $sendkeys->exp_internal($debug);
      #
      # log_stdout(0) prevent the program's output from being shown.
      #  turn on if debugging error
      #$sendkeys->log_stdout(1);
      $sendkeys->log_stdout($debug);
   
      # command to run copy.sh 
      my $spawnruncopy=
      "$remoteshell $node -l $to_userid /tmp/$to_userid/.ssh/copy.sh";  
    
      # send mkdir command 
      unless ($sendkeys->spawn($spawnruncopy))
      {
        my $rsp = {};
        $rsp->{error}->[0] = 
         "Unable to run $spawnruncopy.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        next; # go to next node

      }

      #
      #run copy.sh prompts starts here 
      #

        @result = $sendkeys->expect(
        $timeout,
        [
         $prompt1,  # Are you sure you want to ...
         sub {
             $sendkeys->send("yes\r");
             $sendkeys->clear_accum();
             $sendkeys->exp_continue();
           }
        ],
        [
         $prompt2,  # *ssword*
         sub {
             $sendkeys->send("$to_userpassword\r");
             $sendkeys->clear_accum();
             $sendkeys->exp_continue();
           }
        ],
        [
         $prompt3,  # Permission denied
         sub {
             $rc= 1; 
             $sendkeys->hard_close(); 
           }
        ],
        );   # end prompts
        ##########################################
        # Expect error - report 
        ##########################################
        if (defined($result[1]))
        {
            my $msg = $result[1];
            if ($msg =~ /status 0/i) { # no error
              $rc=0;
            } else {
               if ($msg =~ /2:EOF/i) { # no error
                  $rc=0;
               } else {
                 my $rsp = {};
                 $rsp->{error}->[0] =  "copy.sh:$node has error,$msg";
                 xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
                 $rc=1;
              }
            }
        }
      $sendkeys->soft_close(); 


  }  # end foreach node
  return $rc;
}
#-------------------------------------------------------------------------------

=head3    senddeviceskeys 
	
      Setup the ssh keys on the switches 

=cut

#-----------------------------------------------------------------------------

sub senddeviceskeys 

{
   my ($class,$remoteshell,$remotecopy,$to_userid,$to_userpassword,$home,$ssh_setup_cmd,$nodes, $expecttimeout) = @_;
    my $sendkeys;
    my $timeout  = $expecttimeout;    # sets Expect default timeout, 0 accepts immediately
    my $sendkeys_sent = 0;
    my $prompt1   = 'Are you sure you want to continue connecting (yes/no)?';
    my $prompt2   = 'ssword:';
    my $prompt3   = 'Permission denied*';
    my $expect_log   = undef;
    my $debug        = 0;
    my $rc=0;  
    if ($::VERBOSE)
    {
        $debug = 1;
    }
    
    # quote the setup command and key "sshKey add \"<key\""
    my $setupcmd="\"";
    $setupcmd .= $ssh_setup_cmd;
    $setupcmd .=" ";
    
    # get the public key
    my $key="\\";
    $key .="\"";
    $key .=`cat $home/.ssh/tmp/authorized_keys  `;
    chop ($key);
    $key .="\\";
    $key .="\"";
    # add to the command
    $setupcmd .=$key; 
    $setupcmd .="\"";
    # For each input device
    my @nodelist=split(/,/,$nodes);
    foreach my $node (@nodelist) {
      #
      # ssh to the node to run  the copy.sh to setup the keys starts here
      #
      $sendkeys = new Expect;

      # disable command echoing
      #$sendkeys->slave->stty(qw(sane -echo));
      #
      # exp_internal(1) sets exp_internal debugging
      # to STDERR.
      #
      #$sendkeys->exp_internal(1);
      $sendkeys->exp_internal($debug);
      #
      # log_stdout(0) prevent the program's output from being shown.
      #  turn on if debugging error
      #$sendkeys->log_stdout(1);
      $sendkeys->log_stdout($debug);
   
      # command to send key to the device
      # sshKey add "key" 
      my $spawnaddkey=
      "$remoteshell $node -l $to_userid $setupcmd ";  
    
      # send mkdir command 
      unless ($sendkeys->spawn($spawnaddkey))
      {
        my $rsp = {};
        $rsp->{error}->[0] = 
         "Unable to run $spawnaddkey.";
        xCAT::MsgUtils->message("E", $rsp, $::CALLBACK, 1);
        next; # go to next node

      }

      #
      #run copy.sh prompts starts here 
      #

      my @result = $sendkeys->expect(
        $timeout,
        [
         $prompt1,  # Are you sure you want to ...
         sub {
             $sendkeys->send("yes\r");
             $sendkeys->clear_accum();
             $sendkeys->exp_continue();
           }
        ],
        [
         $prompt2,  # *ssword*
         sub {
             $sendkeys->send("$to_userpassword\r");
             $sendkeys->clear_accum();
             $sendkeys->exp_continue();
           }
        ],
        [
         $prompt3,  # Permission denied
         sub {
             $rc= 1; 
             $sendkeys->soft_close(); 
             next; # go to next node
           }
        ],
        );   # end prompts
        ##########################################
        # Expect error - report 
        ##########################################
        if (defined($result[1]))
        {
            my $msg = $result[1];
            if ($msg =~ /status 0/i) { # no error
              $rc=0;
            } else {
              my $rsp = {};
              $rsp->{error}->[0] =  "$node has error,$msg";
              xCAT::MsgUtils->message("E", $rsp, $::CALLBACK);
              $rc=1;
              next; # go to next node
            }
        }
      $sendkeys->soft_close(); 
    } # end foreach node
    return $rc;
}
1;

