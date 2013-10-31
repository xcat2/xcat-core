# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::cloud;
BEGIN
{
  $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use lib "$::XCATROOT/lib/perl";

use strict;
use xCAT::Table;
use Getopt::Long;
Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");
#use xCAT::Utils;
#use xCAT::TableUtils;
use xCAT::Template;



sub handled_commands
{
    return {makeclouddata => "cloud",};
}

############################################################
# check_options will process the options for makeclouddata and 
# give a usage error for any invalid options 
############################################################
sub check_options
{
    my $req = shift;
    my $callback = shift;
    my $rc       = 0;
    
    Getopt::Long::Configure("bundling");
    $Getopt::Long::ignorecase = 0;
    Getopt::Long::Configure("no_pass_through");

    # Exit if the packet has been preprocessed
    if ($req->{_xcatpreprocessed}->[0] == 1) { return [$req]; }

    # Save the arguements in ARGV for GetOptions
    if ($req && $req->{arg}) { @ARGV = @{$req->{arg}}; }
    else { @ARGV = (); }


    # Parse the options for makedhcp 
    if (!GetOptions(
                     'h|help'    => \$::opt_h,
                   )) 
    {
        # If the arguements do not pass GetOptions then issue error message and return 
        return -1;
    }

    # display the usage if -h
    if ($::opt_h)
    {
        return 1;
    
    }

    my $cloudlist =shift( @ARGV );
   
    if( defined($cloudlist) ) {
        my @clouds = split(",", $cloudlist);
        $req->{clouds} = \@clouds;
    }
   
    return 0; 
}

sub cloudvars {

  my $inf = shift;
  my $outf = shift;
  my $cloud = shift;
  my $callback = shift;
  my $outh; 
  my $inh;
  open($inh,"<",$inf);
  unless ($inh) {
     my $rsp;
     $rsp->{errorcode}->[0]=1;
     $rsp->{error}->[0]="Unable to open $inf, aborting\n";
     $callback->($rsp);
     return;
  }
  my $inc;
  #First load input into memory..
  while (<$inh>) {
    $inc.=$_;
  }
  close($inh);
  $inc =~ s/\$CLOUD/$cloud/eg;
  $inc =~ s/#TABLE:([^:]+):([^:]+):([^#]+)#/xCAT::Template::tabdb($1,$2,$3)/eg;

  open($outh,">",$outf);
  unless($outh) {
     my $rsp;
     $rsp->{errorcode}->[0]=1;
     $rsp->{error}->[0]="Unable to open $inf, aborting\n";
     $callback->($rsp);
     return;
  }
  print $outh $inc;
  close($outh);
  return 0;
}


sub process_request
{
    my $req = shift;
    my $callback = shift;
    my $rc       = 0;
    
    # define usage statement
    my $usage="Usage: \n\tmkcloudata\n\tmakeclouddata <cloudname>\n\tmakeclouddata [-h|--help]";

    $rc = check_options($req,$callback);
    if ($rc == -1) {
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return;
    } elsif ($rc == 1) {
        my $rsp = {};
        $rsp->{data}->[0] = $usage;
        xCAT::MsgUtils->message("I", $rsp, $callback, 0);
        return;
    }

    my $tab  = "clouds";
    my $ptab = xCAT::Table->new("$tab");

    unless ($ptab) {
        my $rsp;
        $rsp->{errorcode}->[0]=1;
        $rsp->{error}->[0]="Unable to open $tab table";
        $callback->($rsp);
        return;
    }


    my $t = $req->{clouds};
    my %h;
    if( defined(@$t) ) {
        %h = map { $_ => 1} @$t;
    }

    my @cloudentries = $ptab->getAllAttribs('name', 'template', 'repository');
        
    foreach my $cloudentry (@cloudentries)  {

        my $cloud = $cloudentry->{name};
        if( %h )  { 
            # if makeclouddata <cloudA>, and 
            if( $h{$cloud} != 1) {
                next; 
            }
        }        

        my $tmplfile = $cloudentry->{template};
        my $repos = $cloudentry->{repository};
       
        unless ( -r "$tmplfile") {
            my $rsp;
            $rsp->{errorcode}->[0]=1;
            $rsp->{error}->[0]="The environment template for the cloud $cloud doesn't exist. Please check the clouds table";
            $callback->($rsp);
            next;
        }
        
        unless ( -r "$repos") {
            my $rsp;
            $rsp->{errorcode}->[0]=1;
            $rsp->{error}->[0]="The repository $repos for the cloud $cloud doesn't exist. Pleae check the clouds table.";
            $callback->($rsp);
            next;
        }
         
        my $tmperr = cloudvars(
            $tmplfile,
            "$repos/environments/$cloud.rb",
            $cloud,
            $callback 
        );

    }    
    return;
}

1;
