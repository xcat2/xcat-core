# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#-------------------------------------------------------

=head1
  xCAT plugin package to handle rinstall and winstall 

   Supported command:
         rinstall - runs nodeset, rsetboot,rpower commands
         winstall - also opens the console

=cut

#-------------------------------------------------------
package xCAT_plugin::rinstall;
use strict;

require xCAT::Utils;
require xCAT::MsgUtils;
use xCAT::NodeRange;
use xCAT::Table;

use Data::Dumper;
use Getopt::Long;

#-------------------------------------------------------

=head3  handled_commands

Return list of commands handled by this plugin

=cut

#-------------------------------------------------------

sub handled_commands
{
    return {
            rinstall => "rinstall",
            winstall => "rinstall",
            };
}

#-------------------------------------------------------

=head3  Process the command

=cut

#-------------------------------------------------------
sub process_request
{

    my $request  = shift;
    my $callback = shift;
    my $subreq  = shift;

    rinstall($request, $callback, $subreq);
}

#-------------------------------------------------------

=head3  rinstall 

   Wrapper around nodeset, rsetboot, rpower for the admin convenience 


=cut

#-------------------------------------------------------
sub rinstall
{
    my ($req, $callback, $subreq) = @_;
    $::CALLBACK=$callback;
    my $OSVER;
    my $PROFILE;
    my $ARCH;
    my $CONSOLE;
    my $OSIMAGE;
    my $HELP;
    my $VERSION;
    my $command = $req->{command}->[0];    # could be rinstall on winstall
    my $args;
    if (defined($req->{arg}) ) { # there are arguments
     $args=$req->{arg};   # argument
     @ARGV = @{$args};
    }
    my $nodes;
    my @nodes;
    if (defined ($req->{node})) { # there are nodes
     $nodes   = $req->{node};
     @nodes=@$nodes;
    }
    # no arguments, no nodes then input wrong
    if ((scalar(@nodes) == 0) && (scalar(@ARGV) == 0)){
        &usage($command,$callback);
        return  1;
    }
    #print Dumper($req);
    Getopt::Long::Configure("bundling");

    unless (
            GetOptions(
                       'o|osver=s'   => \$OSVER,
                       'p|profile=s' => \$PROFILE,
                       'a|arch=s'    => \$ARCH,
                       'O|osimage=s' => \$OSIMAGE,
                       'h|help' =>      \$HELP,
                       'v|version' =>   \$VERSION,
                       'c|console'   => \$CONSOLE
            )
      )
    {
        &usage($command,$callback);
        return 1;
    }
    if ($HELP) 
    {
        &usage($command,$callback);
        return  0;
    }
    if ($VERSION)
    {
        my $version = xCAT::Utils->Version();
        my $rsp = {};
        $rsp->{data}->[0] = "$version";
        xCAT::MsgUtils->message("I", $rsp, $callback);
        return (0);
    }

    if (scalar @$nodes eq 0)
    {
        my $rsp = {};
        $rsp->{error}->[0] ="noderange not supplied";
        xCAT::MsgUtils->message("E", $rsp, $callback);
        return 1;
    }

    my $rc        = 0;
    my %pnhash;

    
    if ($OSIMAGE)
    {

        # -O|--osimage is specified, ignore any -a,-p,-o options,
        # call "nodeset ... osimage= ..." to set the boot state of the noderange to the specified osimage,
        # "nodeset" will handle the updating of node attributes such as os,arch,profile,provmethod
        # verify input
         &checkoption("[-O|--osimage] $OSIMAGE",$OSVER,$PROFILE,$ARCH,$callback);

        # run nodeset $noderange osimage=$OSIMAGE
         my @osimageargs;
         push @osimageargs,"osimage=$OSIMAGE" ;
         my $res  =
         xCAT::Utils->runxcmd(
                           {
                            command => ["nodeset"],
                            node    => \@nodes,
                            arg     => \@osimageargs
                           },
                           $subreq, -1, 1);
       
         my $rsp = {};
         if ($::RUNCMD_RC ==0 ) {
           foreach my $line (@$res) {
              $rsp->{data} ->[0] = $line;
               xCAT::MsgUtils->message("I", $rsp, $callback);
           }      
         }  else {  
           foreach my $line (@$res) {
              $rsp->{error} ->[0] = $line;
               xCAT::MsgUtils->message("E", $rsp, $callback);
           }      
           return 1;
         }      
    }
    else
    {

        # no osimage specified, update the node attributes specified by -a,-p,-o options thru "nodech",
        # then set the boot state of each node based on the nodetype.provmethod:
        # 1) if nodetype.provmethod = <osimage>, ignore any -p,-o,-a option,
        #  then call "nodeset ... osimage"
        # 2) if nodetype.provmethod = [install/netboot/statelite], 
        #  update the node attributes specified by -a,-p,-o options thru "nodech", 
        #  call "nodeset ... [install/netboot/statelite]"
        # 3) if nodetype.provmethod is not set, use 'install' as the default value

        # group the nodes according to the nodetype.provmethod

        foreach (@$nodes)
        {
            my $tab = xCAT::Table->new("nodetype");
            my $nthash = $tab->getNodeAttribs($_, ['provmethod']);
            $tab->close();
            if (defined($nthash) and defined($nthash->{'provmethod'}))
            {
                push(@{$pnhash{$nthash->{'provmethod'}}}, $_);
            }
            else
            {

                #if nodetype.provmethod is not specified,
                push(@{$pnhash{'install'}}, $_);
            }
        }
        # Now for each group  based on provmethod
        foreach my $key (keys %pnhash)
        {
            $::RUNCMD_RC =0;
            my $nodes = join(',', @{$pnhash{$key}});
            if ($key =~ /^(install|netboot|statelite)$/)
            {

                # nodetype.provmethod = [install|netboot|statelite]
                my @nodechline;
                if ($OSVER)
                {
                    push @nodechline, "nodetype.os=$OSVER";
                }
                if ($PROFILE)
                {
                    push @nodechline, "nodetype.profile=$PROFILE";
                }
                if ($ARCH)
                {
                    push @nodechline, "nodetype.arch=$ARCH";
                }
                if (@nodechline)
                {
                    # run nodech $nodes $nodechline
                    my $res  =
                    xCAT::Utils->runxcmd(
                           {
                            command => ["nodech"],
                            node    => \@nodes,
                            arg     => \@nodechline
                           },
                           $subreq, -1, 1);
       
                   my $rsp = {};
                   $rc=$::RUNCMD_RC;
                   if ($rc == 0 ) {
                     foreach my $line (@$res) {
                       $rsp->{data} ->[0] = $line;
                       xCAT::MsgUtils->message("I", $rsp, $callback);
                     }      
                   }  else {  # error
                     $rsp->{error} ->[0] = "nodech error";
                     xCAT::MsgUtils->message("E", $rsp, $callback);
                     foreach my $line (@$res) {
                       $rsp->{error} ->[0] = $line;
                       xCAT::MsgUtils->message("E", $rsp, $callback);
                     }      
                   }      
                } # end nodechline    

                if ($rc == 0)   # if no error from nodech then run nodeset
                {
                   # run nodeset $nodes $key  ( where key is install/netboot/statelite)
                   my @nodesetarg;
                   push @nodesetarg, "$key";
                   my $res  =
                    xCAT::Utils->runxcmd(
                           {
                            command => ["nodeset"],
                            node    => \@nodes,
                            arg     => \@nodesetarg
                           },
                           $subreq, -1, 1);
                    
                   my $rsp = {};
                   $rc=$::RUNCMD_RC;
                   if ($rc ==0 ) {
                     foreach my $line (@$res) {
                       $rsp->{data} ->[0] = $line;
                       xCAT::MsgUtils->message("I", $rsp, $callback);
                     }      
                   }  else {  # error
                     foreach my $line (@$res) {
                       $rsp->{error} ->[0] = $line;
                       xCAT::MsgUtils->message("E", $rsp, $callback);
                     }      
                   }      
                }
            }
            else   # if not install/netboot/statelite
            {

                # nodetype.provmethod = <osimage>
                &checkoption("nodetype.provmethod=$key",$OSVER,$PROFILE,$ARCH,$callback);
                #  run nodeset $nodes osimage
                 my @nodesetarg;
                 push @nodesetarg, "osimage";
                 my $res  =
                    xCAT::Utils->runxcmd(
                           {
                            command => ["nodeset"],
                            node    => \@nodes,
                            arg     => \@nodesetarg
                           },
                           $subreq, -1, 1);
                    
                 my $rsp = {};
                 $rc=$::RUNCMD_RC;
                 if ($rc ==0 ) {
                     foreach my $line (@$res) {
                       $rsp->{data} ->[0] = $line;
                       xCAT::MsgUtils->message("I", $rsp, $callback);
                     }      
                 }  else {  # error
                     foreach my $line (@$res) {
                       $rsp->{error} ->[0] = $line;
                       xCAT::MsgUtils->message("E", $rsp, $callback);
                     }      
                 }      
            }

        }
    } # end nodech/nodeset for each group

    if ($rc != 0)   # we got an error with the nodeset 
    {
       my $rsp = {};
       $rsp->{error}->[0] = "nodeset failure will not continue ";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }

    # call "rsetboot" to set the boot order of the nodehm.mgt=ipmi nodes,for others, 
    #  assume user has set the correct boot order before "rinstall"

    # run rsetboot $noderange net

    my @rsetbootarg;
    push @rsetbootarg, "net";
    my $res  =
       xCAT::Utils->runxcmd(
       {
           command => ["rsetboot"],
           node    => \@nodes,
           arg     => \@rsetbootarg
       },
       $subreq, -1, 1);
    # fix output it is a hash and you must get error out of the hash.               
    my $rsp = {};
    $rc=$::RUNCMD_RC;
    if ($rc ==0 ) {
        foreach my $line (@$res) {
          $rsp->{data} ->[0] = $line;
          xCAT::MsgUtils->message("I", $rsp, $callback);
        }      
    }  else {  # error
         foreach my $line (@$res) {
            $rsp->{error} ->[0] = $line;
            xCAT::MsgUtils->message("E", $rsp, $callback);
         }      
    }      
    if ($rc != 0)   # we got an error with the rsetboot 
    {
       my $rsp = {};
       $rsp->{error}->[0] = "rsetboot failure will not continue ";
       xCAT::MsgUtils->message("E", $rsp, $callback);
       return 1;
    }

    # call "rpower" to start the node provision process

    #run rpower $noderange boot
    my @rpowerarg;
    push @rpowerarg, "boot";
    my $res  =
       xCAT::Utils->runxcmd(
       {
           command => ["rpower"],
           node    => \@nodes,
           arg     => \@rpowerarg
       },
       $subreq, -1, 1);
                   
    my $rsp = {};
    $rc=$::RUNCMD_RC;
    if ($rc ==0 ) {
        foreach my $line (@$res) {
          $rsp->{data} ->[0] = $line;
          xCAT::MsgUtils->message("I", $rsp, $callback);
        }      
    }  else {  # error
         foreach my $line (@$res) {
            $rsp->{error} ->[0] = $line;
            xCAT::MsgUtils->message("E", $rsp, $callback);
         }      
    }      
    # Check if they asked to bring up a console ( -c) from rinstall  always for winstall
    $req->{startconsole}->[0] =0;
    if ($command =~ /rinstall/)
    {

        # for rinstall, the -c|--console option can provide the remote console for only 1 node
        if ($CONSOLE)
        {
            if (scalar @$nodes ne 1)
            {
               my $rsp = {};
               $rsp->{error}->[0] = "rinstall -c only accepts one node in the noderange. See winstall for support for support of consoles on multiple nodes.";
                xCAT::MsgUtils->message("E", $rsp, $callback);
                return 1;
            } else {  # tell rinstall client ok to start rcons
                $req->{startconsole}->[0] =1;
            }
                
        }
    }
    elsif ($command =~ /winstall/)
    {

       # winstall can start a wcons command to multiple nodes for monitoring the provision cycle
       $req->{startconsole}->[0] =1;

    }

    return 0;
}

#-------------------------------------------------------

=head3  Usage 


=cut

#-------------------------------------------------------

sub usage
{
    my $command = shift;
    my $callback = shift;
    my $rsp = {};
    $rsp->{data}->[0] = "$command usage:";
    if ($command =~ /rinstall/) {
      $rsp->{data}->[1] = " [-o|--osver] [-p|--profile] [-a|--arch]  [-c|--console] <noderange>";
    } else { # winstall
      $rsp->{data}->[1] = " [-o|--osver] [-p|--profile] [-a|--arch]  <noderange>";
    }
    if ($command =~ /rinstall/) {
      $rsp->{data}->[2] = " [-O|--osimage] [-c|--console] <noderange>";
    } else {  # wininstall
      $rsp->{data}->[2] = " [-O|--osimage] <noderange>";
    }

    $rsp->{data}->[3] = " [-h|--help]";
    $rsp->{data}->[4] = " [-v|--version]";
    xCAT::MsgUtils->message("I", $rsp, $callback);
}

# check and complain about the invalid combination of the options,
# ignore -o,-p and -a options and prompt a warning message  when provmethod=osimagename
sub checkoption{
    my $optstring=shift;
    my $OSVER=shift;
    my $PROFILE=shift;
    my $ARCH=shift;
    my $callback=shift;
    my $rsp = {};
    if($OSVER) { 
       $rsp->{data}->[0] = "-o option not valid with $optstring. It is ignored.";
       xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    if($PROFILE) { 
       $rsp->{data}->[0] = "-p option not valid with $optstring. It is ignored.";
       xCAT::MsgUtils->message("I", $rsp, $callback);
    }
    if($ARCH) { 
       $rsp->{data}->[0] = "-a option not valid with $optstring. It is ignored.";
       xCAT::MsgUtils->message("I", $rsp, $callback);
    }
}



1;
