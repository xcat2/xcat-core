#!/usr/bin/perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# #(C)IBM Corp
package imgutils;

use strict;
use warnings "all";

sub get_profile_def_filename {
   my $osver = shift;
   my $profile = shift;
   my $arch = shift;
   
   my $base=shift;
   my $ext=shift;
   my $dotpos = rindex($osver, ".");
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

1;
