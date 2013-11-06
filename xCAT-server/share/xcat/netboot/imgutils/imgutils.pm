#!/usr/bin/perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# #(C)IBM Corp
package imgutils;

use strict;
use warnings "all";

use File::Basename;
use File::Path;
use Cwd qw(realpath);

sub get_profile_def_filename {
   my $osver = shift;
   my $profile = shift;
   my $arch = shift;

   my $tmp_base=shift;
   my $base=realpath($tmp_base); #get the full path
   if (!$base) { $base=$tmp_base;}
   
   my $ext=shift;
   
   my $dotpos;
   
   # OS version on s390x can contain 'sp', e.g. sles11sp1
   # If OS version contains 'sp', get the index of 'sp' instead of '.'
   if ($osver =~ /sles/ && $osver =~ /sp/) {
      $dotpos = rindex($osver, "sp");
   } else {
      $dotpos = rindex($osver, ".");
   }
   
   my $osbase = substr($osver, 0, $dotpos);
   if (-r "$base/$profile.$osver.$arch.$ext") {
      return "$base/$profile.$osver.$arch.$ext";
   } elsif (-r "$base/$profile.$osbase.$arch.$ext") {
      return "$base/$profile.$osbase.$arch.$ext";
   } elsif (-r "$base/$profile.$arch.$ext") {
      return "$base/$profile.$arch.$ext";
   } elsif (-r "$base/$profile.$osver.$ext") {
      return "$base/$profile.$osver.$ext";
   } elsif (-r "$base/$profile.$osbase.$ext") {
      return "$base/$profile.$osbase.$ext";
   } elsif (-r "$base/$profile.$ext") {
      return "$base/$profile.$ext";
   } 

   return "";
}

sub include_file
{
   my $file = shift;
   my $idir = shift;
   my @text = ();
   unless ($file =~ /^\//) {
       $file = $idir."/".$file;
   }
   
   open(INCLUDE,$file) || 
       return "#INCLUDEBAD:cannot open $file#";
   
   while(<INCLUDE>) {
       chomp($_);
       s/\s+$//;  #remove trailing spaces
       next if /^\s*$/; #-- skip empty lines
       next
          if (   /^\s*#/
              && !/^\s*#INCLUDE:[^#^\n]+#/
              && !/^\s*#NEW_INSTALL_LIST#/
              && !/^\s*#ENV:[^#^\n]+#/);    #-- skip comments
       push(@text, $_);
   }
   
   close(INCLUDE);
   
   return join(',', @text);
}

sub get_package_names {
   my $plist_file_list=shift;
   my %pkgnames=();

   my @plist_file_names = split ',', $plist_file_list;
   foreach my $plist_file_name ( @plist_file_names ) {

       # this variable needs to be cleaned when loop the pkglist files
       my @tmp_array=();

       if ($plist_file_name && -r $plist_file_name) {
           my $pkgfile;
           open($pkgfile,"<","$plist_file_name");
           while (<$pkgfile>) {
               chomp;
               s/\s+$//;   #remove trailing white spaces
               next if /^\s*$/; #-- skip empty lines
               next
               if (   /^\s*#/
                    && !/^\s*#INCLUDE:[^#^\n]+#/
                    && !/^\s*#NEW_INSTALL_LIST#/
                    && !/^\s*#ENV:[^#^\n]+#/);    #-- skip comments
               push(@tmp_array,$_);
            }
            close($pkgfile);

            if ( @tmp_array > 0) {
                 my $pkgtext=join(',',@tmp_array);
                 #handle the #INLCUDE# tag recursively
                 my $idir = dirname($plist_file_name);
                 my $doneincludes=0;
                 while (not $doneincludes) {
                     $doneincludes=1;
                     if ($pkgtext =~ /#INCLUDE:[^#^\n]+#/) {
                        $doneincludes=0;
                        $pkgtext =~ s/#INCLUDE:([^#^\n]+)#/include_file($1,$idir)/eg;
                    }
                }
     
                #print "\n\npkgtext=$pkgtext\n\n";
                my @tmp=split(',', $pkgtext);
                my $pass=1;
                foreach (@tmp) {
                    my $idir;
                    if (/^--/) {	
                        $idir="POST_REMOVE";   #line starts with -- means the package should be removed after otherpkgs are installed
                        s/^--//;
                    } elsif  (/^-/) {
                        $idir="PRE_REMOVE"; #line starts with single - means the package should be removed before otherpkgs are installed
                        s/^-//;
                    } elsif  (/^#NEW_INSTALL_LIST#/) {
                        $pass++;
                        next;
                    } elsif (/^#ENV:([^#^\n]+)#/) {
                        my $pa=$pkgnames{$pass}{ENVLIST};
                        my $env = $1;
                        if (exists($pkgnames{$pass}{ENVLIST})){
                            push(@$pa,$env);
                        } else {
                            $pkgnames{$pass}{ENVLIST} = [$env];
                        }
                        next;
                    } elsif  (/^#INCLUDEBAD:([^#^\n]+)#/){
                        my $pa=$pkgnames{$pass}{INCLUDEBAD};
                        my $file=$1;
                        if (exists($pkgnames{$pass}{INCLUDEBAD})){
                           push(@$pa,$file);
                        } else {
                           $pkgnames{$pass}{INCLUDEBAD} =[$file];
                        }
                        next;
                    } elsif  (/^#/) {
                        # ignore all other comment lines
                        next;
                    } else { 
                        $idir=dirname($_); 
                    }
                    my $fn=basename($_);
                    if (exists($pkgnames{$pass}{$idir})) {
                        my $pa=$pkgnames{$pass}{$idir};
                        push(@$pa, $fn);
                    } else {
                        $pkgnames{$pass}{$idir}=[$fn];
                    }
            
	        }
            }
       }
   }

   return %pkgnames;
}

1;
