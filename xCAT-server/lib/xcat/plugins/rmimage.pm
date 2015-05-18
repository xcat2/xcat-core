#!/usr/bin/env perl
# IBM(c) 2010 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT_plugin::rmimage;

BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}

use lib "$::XCATROOT/lib/perl";
use Getopt::Long;
use File::Path;
use xCAT::Utils;
use xCAT::TableUtils;
use xCAT::DBobjUtils;

Getopt::Long::Configure("bundling");
Getopt::Long::Configure("pass_through");

sub handled_commands {
     return {
            rmimage => "rmimage",
   }
}

sub process_request {
   my $request = shift;
   my $callback = shift;
   my $doreq = shift;
   my $installroot = xCAT::TableUtils->getInstallDir();
   my $tftproot = xCAT::TableUtils->getTftpDir();

   my $usage = "\nUsage:\n    rmimage [-h | --help]\n    rmimage [-V | --verbose] imagename [--xcatde]";

   @ARGV = @{$request->{arg}};

   my $osver;
   my $arch;
   my $profile;
   my $method;
   my $xcatdef;
   my $imagename;
   my $imagedir;

   if (!xCAT::Utils->isLinux()) {
      $callback->({error=>["The rmimage command is only supported on Linux."],errorcode=>[1]});
      return;
   }

   if (!GetOptions(
	'o=s' => \$osver,
	'a=s' => \$arch,
	'p=s' => \$profile,
	'h|help' => \$help,
	'V|verbose' => \$verbose,
	'xcatdef' => \$xcatdef
   )) {
      $callback->({error=>["$usage"],errorcode=>[1]});
      exit 1;
   }

   if ($help) {
      $callback->({info=>["$usage"]});
      return;
   }

   if (@ARGV > 0) {
       $imagename=$ARGV[0];
       if($verbose) {
           $callback->({info=>["image name is $imagename"]});
       }

       if ($arch or $osver or $profile) {
	   $callback->({error=>["-o, -a and -p options are not allowed when a image name is specified."],errorcode=>[1]});
	   return;
       }

   } else {
       
       if (!$osver or !$arch or !$profile) {
           $callback->({error=>["Missing flag -o, -a or -p"],errorcode=>[1]});
           return;
       }

       if ($xcatdef) {
           $callback->({error=>["--xcatdef can not be used with the -o, -a or -p"],errorcode=>[1]});
           return;
       }
   }

   if ($imagename) {
       #Check the provemethod when imagename is specified
       my $osimagetab = xCAT::Table->new('osimage', -create=>1);
       if (!$osimagetab) {
           $callback->({error=>["Can not open osimage table."],errorcode=>[1]});
           return;
       }
       (my $ref) = $osimagetab->getAttribs({imagename => $imagename}, 'osvers', 'osarch', 'profile', 'provmethod');
       if ($ref) {
           $osver = $ref->{'osvers'};
           $arch = $ref->{'osarch'};
           $profile = $ref->{'profile'};
           $method = $ref->{'provmethod'};;
       }
       if($verbose) {
           $callback->({info=>["For osimage $imagename: osver = $osver, arch = $arch, profile = $profile, method = $method in osimage table"]});
       }
       if (($method) && ($method ne "netboot") && ($method ne "statelite") && ($method ne "raw") && ($method ne "sysclone")) {
          $callback->({error=>["Invalid method \"$method\", the rmimage command can only be used to remove the netboot, statelite, sysclone or raw image files"], errorcode=>[1]});
          return;
       }
           
       #Check the rootimgdir when imagename is specified
       my $linuximagetab = xCAT::Table->new('linuximage', -create=>1);
       if (!$linuximagetab) {
            $callback->({error=>["Can not open linuximage table."],errorcode=>[1]});
            return;
       }
       (my $ref1) = $linuximagetab->getAttribs({imagename => $imagename}, 'rootimgdir');
       if (($ref1) && ($ref1->{'rootimgdir'})) {
           $imagedir = $ref1->{'rootimgdir'};
       }

       if($verbose) {
           $callback->({info=>["For osimage $imagename: rootimgdir = $imagedir in linuximage table"]});
       }

       # If the rootimgdir is empty, use the osver, arch and profile to form the rootimgdir
       if (!$imagedir) {
           # If any of the osver, arch or profile is empty in osimage table,
           # use the imagename to get the attributes
           if (!$osver or !$arch or !$profile) {
               #split the imagename
               ($osver, $arch, $method, $profile) = split(/-/, $imagename, 4);
               if (!$osver or !$arch or !$profile or !$method) {
                   $callback->({error=>["Invalid image name $imagename"],errorcode=>[1]});
                   return;
               }
               if (($method ne "netboot") && ($method ne "statelite") && ($method ne "raw") && ($method ne "sysclone")) {
                  $callback->({error=>["Invalid method \"$method\", the rmimage command can only be used to remove the netboot, statelite, sysclone or raw image files"], errorcode=>[1]});
                  return;
               }
           }
            
           if ($arch eq "s390x") {
               if (($method eq "raw") || ($method eq "sysclone")) {
                   $imagedir = "$installroot/$method/$osver/$arch/$profile";
               } else {
                   $imagedir = "$installroot/netboot/$osver/$arch/$profile";
               }
           } else {
               $imagedir = "$installroot/netboot/$osver/$arch/$profile";
           }
       }
   } else { # imagename is not specified
       if ($arch eq "s390x") {
           if (($method eq "raw") || ($method eq "sysclone")) {
               $imagedir = "$installroot/$method/$osver/$arch/$profile";
           } else {
               $imagedir = "$installroot/netboot/$osver/$arch/$profile";
           }
       } else {
           $imagedir = "$installroot/netboot/$osver/$arch/$profile";
       }
   }
   
   if($verbose) {
       $callback->({info=>["image directory is $imagedir"]});
   }

   if (! -d $imagedir) {
       $callback->({error=>["Image directory $imagedir does not exist"],errorcode=>[1]});
       return;
   }
   
   # Doing this extra check now because we now have a method and arch from either the node or the image name.
   if (($method eq "sysclone") && ($arch ne "s390x")) {
      # Only supporting removing sysclone images for s390x at this time.
      $callback->({error=>["rmimage cannot be used to remove sysclone images for \"$arch\" architecture"], errorcode=>[1]});
      return;
   }
   
   my @filestoremove = ("$imagedir/rootimg.gz", "$imagedir/kernel", "$imagedir/initrd-stateless.gz", "$imagedir/initrd-statelite.gz");

   #some rpms like atftp mount the rootimg/proc to /proc, we need to make sure rootimg/proc is free of junk 
   `umount -l $imagedir/rootimg/proc 2>&1 1>/dev/null`;
   # also umount the rootimg/sys
   `umount -l $imagedir/rootimg/sys 2>&1 1>/dev/null`;

   #Start removing the rootimg directory and files
   if (-d "$imagedir/rootimg") {
       $callback->({info=>["Removing directory $imagedir/rootimg"]});
       rmtree "$imagedir/rootimg";
   }

   foreach my $fremove (@filestoremove) {
       if (-f $fremove) {
           $callback->({info=>["Removing file $fremove"]});
           unlink("$fremove");
      }
   }

   #remove image files under tftpdir
   my $tftpdir = "$tftproot/xcat/netboot/$osver/$arch/$profile";
   if ($imagename) {
       $tftpdir = "$tftproot/xcat/osimage/$imagename";
   }
   if (-d "$tftpdir") {
       $callback->({info=>["Removing directory $tftpdir"]});
       rmtree "$tftpdir";
   }
   
   # For s390x, remove the image directory.
   if (($arch eq "s390x") && (-d "$imagedir") && (($method eq "raw") || ($method eq "netboot") || ($method eq "sysclone"))) {
       $callback->({info=>["Removing directory $imagedir"]});
       rmtree "$imagedir";	
   }

   $callback->({info=>["Image files have been removed successfully from this management node."]});

   if (!$imagename || ($method eq "statelite")) {
       $callback->({info=>["Please be aware that the statelite image files on the diskful service nodes are not removed, you can remove the image files on the service nodes manually if necessary, for example, use command \"rsync -az --delete $installroot <sn>:/\" to remove the image files on the service nodes, where the <sn> is the hostname of the service node."]});
   }

   if ($xcatdef && $imagename) {
       $callback->({info=>["Removing osimage definition for $imagename."]});
       my %objhash = ();
       $objhash{$imagename} = 'osimage';
       # remove the objects
       if (xCAT::DBobjUtils->rmobjdefs(\%objhash) != 0)
       {
            $callback->({error=>["Failed to remove the osimage definition for $imagename"],errorcode=>[1]});
       } else {
           $callback->({info=>["osimage definition for $imagename is removed successfully."]});
       }
   }
}

1;
