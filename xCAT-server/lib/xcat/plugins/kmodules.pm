#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle kernel modules
#
#####################################################

package xCAT_plugin::kmodules;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

require xCAT::Table;
require xCAT::Utils;
require xCAT::TableUtils;
require Data::Dumper;
require Getopt::Long;
require xCAT::MsgUtils;
use File::Path qw(make_path remove_tree);
use File::Basename qw(basename);
use Text::Balanced qw(extract_bracketed);
use Safe;
my $evalcpt = new Safe;

use strict;
use warnings;

#
# Globals
#

#------------------------------------------------------------------------------

=head1    kmodules   

This program module file performs kernel module functions

Supported commands:
   lskmodules -- List the kernel modules in one or more:
                    osimage.driverupdatesrc (duds or rpms)
                    kitcomponent.driverpacks (rpms in repodir)
                    osdistro (kernel-<kernvers> rpms)
                    osdistroupdate (kernel-<kernvers> rpms)

=cut

#------------------------------------------------------------------------------

=head2    Kernel Modules Support

=cut

#------------------------------------------------------------------------------

#----------------------------------------------------------------------------

=head3  handled_commands

        Return a list of commands handled by this plugin

=cut

#-----------------------------------------------------------------------------
sub handled_commands {
    return {
             lskmodules  => "kmodules"
    };
}

#----------------------------------------------------------------------------

=head3   preprocess_request


        Arguments:

        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
# sub preprocess_request {
#
# NOT REQUIRED -- no hierarchy for this command
#    my $req = shift;
#    return [$req];
# }

#----------------------------------------------------------------------------

=head3   process_request

        Process the kernel modules commands

        Arguments:

        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
sub process_request {
    $::request  = shift;
    $::CALLBACK = shift;
    $::SUBREQ   = shift;
    my $ret;

    # globals used by all subroutines.
    $::command   = $::request->{command}->[0];
    $::args      = $::request->{arg};
    $::stdindata = $::request->{stdin}->[0];

    # figure out which cmd and call the subroutine to process
    if ( $::command eq "lskmodules" ) {
        $ret = &lskmodules($::request);
    }

    return $ret;
}

#----------------------------------------------------------------------------

=head3  lskmodules_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

# display the usage
sub lskmodules_usage {
    my $rsp;
    push @{ $rsp->{data} },
      "\nUsage: lskmodules - List kernel modules in specified input \n";
    push @{ $rsp->{data} },
      "  lskmodules [-V|--verbose] [-x|--xml|--XML] [-c|--kitcomponent kit_comp1,kit_comp2,...] [-o|--osdistro os_distro] [-u|--osdistroupdate os_distro_update] [-i|--osimage osimage]  \n ";
    push @{ $rsp->{data} }, "  lskmodules [-h|--help|-?] \n";
    push @{ $rsp->{data} },
      "  lskmodules [-v|--version]  \n ";
    xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    return 0;
}


#----------------------------------------------------------------------------
=head3   processArgs

        Process the command line 

        Arguments:

        Returns:
                0 - OK
                1 - just print usage
                2 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
sub processArgs {

    if ( defined( @{$::args} ) ) {
        @ARGV = @{$::args};
    }

    # parse the options
    # options can be bundled up like -vV, flag unsupported options
    Getopt::Long::Configure( "bundling", "no_ignore_case", "no_pass_through" );
    Getopt::Long::GetOptions(
                              'help|h|?'  => \$::opt_h,
                              'kitcomponent|c=s' => \$::opt_c,
                              'osimage|i=s' => \$::opt_i,
                              'osdistro|o=s' => \$::opt_o,
                              'osdistroupdate|u=s' => \$::opt_u,
                              'verbose|V' => \$::opt_V,
                              'version|v' => \$::opt_v,
                              'xml|XML|x' => \$::opt_x,
    );

    # Option -h for Help
    if ( defined($::opt_h) ) {
        return 2;
    }

    # Option -v for version
    if ( defined($::opt_v) ) {
        my $rsp;
        my $version = xCAT::Utils->Version();
        push @{ $rsp->{data} }, "$::command - $version\n";
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
        return 1;    # no usage - just exit
    }

    # Option -V for verbose output
    if ( defined($::opt_V) ) {
        $::verbose = 1;
        $::VERBOSE = 1;
    }

    if ( !defined($::opt_c) &&
         !defined($::opt_i) &&
         !defined($::opt_o) &&
         !defined($::opt_u) ) {
        my $rsp;
        push @{ $rsp->{data} }, "Specify a search location \n";
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
        return 2;
        }

    my $more_input = shift(@ARGV);
    if ( defined($more_input) ) {
        my $rsp;
        push @{ $rsp->{data} }, "Invalid input: $more_input \n";
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
        return 2;
        }

    return 0;
}


#----------------------------------------------------------------------------

=head3  lskmodules

        Support for listing kernel modules

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub lskmodules {

    my $rc    = 0;

    # process the command line
    $rc = &processArgs;
    if ( $rc != 0 ) {

        # rc: 0 - ok, 1 - return, 2 - help, 3 - error
        if ( $rc != 1 ) {
            &lskmodules_usage;
        }
        return ( $rc - 1 );
    }
    if ($::VERBOSE) {
        my $rsp;
        push @{ $rsp->{data} }, "Running lskmodules command... ";
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
    }
    
    # Get all the rpms and img files to search based on command input
    my @sources = &set_sources;
    if (!(@sources)){
        my $rsp;
        push @{ $rsp->{data} }, "No input search source found.";
        xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
        return 1;
    }

    # Get the list of kernel modules in each rpm/img file
    foreach my $source (@sources) {
        my %modlist;
        if ( $source =~ /^dud:/ ) {
           $source =~ s/^dud://;
           %modlist = &mods_in_img($source);
        } else {
           $source =~ s/^rpm://;
           %modlist = &mods_in_rpm($source);
        }

        # Return the module list for this rpm/img file
        my $rsp={};
        foreach my $mn (keys %modlist) {
           if ($::opt_x) {
               push @{ $rsp->{data} }, '<module> <name> '.$mn.' </name> <description> '.$modlist{$mn}.' </description> </module>';
           } else {
               push @{ $rsp->{data} }, $mn.': '.$modlist{$mn};
           }
        }
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );

    }

    return $rc;
}
#----------------------------------------------------------------------------

=head3  set_sources

        return array of input kernel module sources

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub set_sources {

  my $installdir = xCAT::TableUtils->getInstallDir;
  my @sources;

# Kit Components (kitcomp.driverpacks)
  if ( defined($::opt_c) ) {
       my $kctab = xCAT::Table->new('kitcomponent');
       my $krtab = xCAT::Table->new('kitrepo');
       foreach my $kc (split( ',', $::opt_c)) {
          my ($kc_entry) = $kctab->getAttribs({'kitcompname'=>$kc},('kitreponame','driverpacks'));
          if ( !($kc_entry) ) {
              my $rsp;
              push @{ $rsp->{data} }, "No driverpacks attribute for kitcomponent $kc found.  Skipping.";
              xCAT::MsgUtils->message( "W", $rsp, $::CALLBACK );
              next;
          } 
          my ($kr_entry) = $krtab->getAttribs({'kitreponame'=>$kc_entry->{'kitreponame'}},('kitrepodir'));
          if ( !($kr_entry) ) {
              my $rsp;
              push @{ $rsp->{data} }, "Kitrepo $kc_entry->{'kitreponame' } not found in database.  Error in kitcomponent definition for $kc.  Skipping.";
              xCAT::MsgUtils->message( "W", $rsp, $::CALLBACK );
              next;
          }
          foreach my $dp (split( ',', $kc_entry->{'driverpacks'})) {
              push @sources, $kr_entry->{'kitrepodir'}.'/'.$dp;
          }
       }
       $kctab->close;
  }

# OS images (osimage.driverupdatesrc)
  if ( defined($::opt_i) ) {
       my $litab = xCAT::Table->new('linuximage');
       foreach my $li (split( ',', $::opt_i)) {
          my ($li_entry) = $litab->getAttribs({'imagename'=>$li},('driverupdatesrc'));
          if ( !($li_entry) ) {
              my $rsp;
              push @{ $rsp->{data} }, "No driverupdatesrc attribute for osimage $li found.  Skipping. ";
              xCAT::MsgUtils->message( "W", $rsp, $::CALLBACK );
              next;
          }
          push @sources, split( ',', $li_entry->{'driverupdatesrc'});
       }
       $litab->close;
  }

# OS distro 
  if ( defined($::opt_o) ) {
       my $odtab = xCAT::Table->new('osdistro');
       foreach my $od (split( ',', $::opt_o)) {
          my ($od_entry) = $odtab->getAttribs({'osdistroname'=>$od},('dirpaths'));
          if ( !($od_entry) ) {
              # try building dirpath from distro_name/local_arch
              my $arch = `uname -m`;
              chomp($arch);
              $arch = "x86" if ($arch =~ /i.86$/);
              my $dirpath = $installdir.'/'.$od.'/'.$arch;      
              if (!(-e $dirpath)) {
                  my $rsp;
                  push @{ $rsp->{data} }, "No dirpaths attribute for osdistro $od found.  Skipping. ";
                  xCAT::MsgUtils->message( "W", $rsp, $::CALLBACK );
                  next;
              }
              my @kernel_rpms = grep{ /\/kernel-\d+/ } <$dirpath/Packages/kernel-*>;
              push @sources, @kernel_rpms;
          } else {
              foreach my $dirpath (split( ',', $od_entry->{'dirpaths'})){
                  my @kernel_rpms = grep{ /\/kernel-\d+/ } <$dirpath/Packages/kernel-*>;
                  if (@kernel_rpms) {
                      push @sources, @kernel_rpms;
                  } 
              }
          }
       }
       $odtab->close;
  }


# OS distro update
  if ( defined($::opt_u) ) {
       my $outab = xCAT::Table->new('osdistroupdate');
       foreach my $ou (split( ',', $::opt_u)) {
          my ($ou_entry) = $outab->getAttribs({'osupdatename'=>$ou},('dirpath'));
          if ( !($ou_entry) ) {
              my $rsp;
              push @{ $rsp->{data} }, "No dirpath attribute for osdistroupdate $ou found.  Skipping.";
              xCAT::MsgUtils->message( "W", $rsp, $::CALLBACK );
              next;
          } 
          my $dirpath = $ou_entry->{'dirpath'};
          my @kernel_rpms = grep{ /\/kernel-\d+/ } <$dirpath/kernel-*>;
          if (@kernel_rpms) {
              push @sources, @kernel_rpms;
          } 
       }
       $outab->close;
  }


  if ($::VERBOSE && @sources) {
        my $rsp;
        push @{ $rsp->{data} }, "Searching the following locations for kernel modules: ";
        push @{ $rsp->{data} }, @sources ;
        xCAT::MsgUtils->message( "I", $rsp, $::CALLBACK );
  }


  return @sources;
}

#----------------------------------------------------------------------------

=head3  mods_in_rpm

        return hash of module names/descriptions found in rpm

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub mods_in_rpm {

  my $krpm = shift;
  my %modlist;
 

  my $tmp_path = "/tmp/lskmodules_expanded_rpm";
  make_path($tmp_path);
  if (-r $krpm) {
     if (system ("cd $tmp_path; rpm2cpio $krpm | cpio -idum *.ko")) {
         my $rsp;
         push @{ $rsp->{data} }, "Unable to extract files from the rpm $krpm.";
         xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
         remove_tree($tmp_path);
         return;
     }
  } else {
     my $rsp;
     push @{ $rsp->{data} }, "Unable to read rpm $krpm.";
     xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
     remove_tree($tmp_path);
     return;
  }
 
  my @ko_files = `find $tmp_path -name *.ko`;
  foreach my $ko (@ko_files) {
      chomp($ko);
      my $name = basename($ko);
      my $desc = `modinfo -d $ko`;
      chomp ($desc);
      if ( $desc =~ /^\w*$/ ) {
          $desc = "  ";     
      }
      $modlist{$name} = $desc;
  }
  
  remove_tree($tmp_path);

  return %modlist;

}

#----------------------------------------------------------------------------

=head3  mods_in_img

        return hash of module names/descriptions found in 
           driver update image

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub mods_in_img {

  my $img_file = shift;
  my %modlist;

  my $mnt_path = "/tmp/lskmodules_mnt";
  make_path($mnt_path);

  my $rc = system ("mount -o loop $img_file $mnt_path");
  if ($rc) {
     my $rsp;
     push @{ $rsp->{data} }, "Mount of driver disk image $img_file failed";
     xCAT::MsgUtils->message( "E", $rsp, $::CALLBACK );
     remove_tree($mnt_path);
     return;
  }

  my @ko_files = `find $mnt_path -name *.ko`;
  foreach my $ko (@ko_files) {
      chomp($ko);
      my $name = basename($ko);
      my $desc = `modinfo -d $ko`;
      chomp ($desc);
      if ( $desc =~ /^\w*$/ ) {
          $desc = "  ";     
      }
      $modlist{$name} = $desc;
  }
  
  $rc = system ("umount $mnt_path");
  remove_tree($mnt_path);

  return %modlist;
}

1;
