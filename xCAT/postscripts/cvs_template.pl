#!/usr/bin/perl
#-- Example of "CVS-enabled" postscript
#-- Keeps track of every postscript run and it's version in /etc/IMGVERSION
#-- jurij.sikorsky@t-systems.cz
#--------------------------------------------------------------------------------
#-- DO NOT remove following lines
open(IMG, ">>/etc/IMGVERSION");
print IMG '$Id: cvs_template.pl,v 1.1 2008/09/05 08:40:16 sikorsky Exp $', "\n";

#--------------------------------------------------------------------------------
#--

