#!/usr/bin/perl
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#This is ported forward from xCAT 1.3
#TODO: A lot of stuff was handled by the script portion of makedns, notably:
# db.cache
# forwarders
# chroot
# dnsallowq
# mucking with sysconfig
package xCAT_plugin::bind;
use strict;
no strict "refs";    #This code is as yet still very broken...

#use warnings;
use Sys::Hostname;
use Cwd;
use Getopt::Long;
use xCAT::Table;
use xCAT::MsgUtils;
use Data::Dumper;

sub handled_commands
{
    return {"makedns" => "bind"};
}

#NAME
#
#    h2n - Translate host table to name server file format
#    $Date: 1999/08/08 17:17:56 $  $Revision: 8.2 $
#
#SYNOPSIS
#
#    h2n -d DOMAIN -n NET [options]

# Various defaults
my $Host;
my $doaliases       = 1;
my $domx            = 1;
my $dowks           = 0;
my $dotxt           = 0;
my $dontdodomains   = 0;
my $Bootfile        = "/etc/named.conf";
my $DBDir           = "/var/named/";
my $Domain          = "";
my $Hostfile        = "/etc/hosts";
my $Commentfile     = "";
my $Commentfileread = 0;
my $User            = "root";
my $RespHost        = "";
my $RespUser        = "";
my $DefSerial       = 1;
my $DefRefresh      = 10800;
my $DefRetry        = 3600;
my $DefExpire       = 604800;
my $DefTtl          = 86400;
my $UseDefSOAValues = 0;
my $DefMxWeight     = 10;
my $Defsubnetmask   = "";
my $ForceSerial     = -1;
my $UseDateInSerial = 1;
my $DateSerial      = 0;
my $Version         = 8;
my $request;
my $callback;
my @forwarders;

#Declarations to alleviate use strict, since the code doesn't seem to be structured well enough to avoid it for these cases
my $Bootsecsaveaddr;
my $Bootsecaddr;
my @Networks;
my @bootmsgs_v4;
my @bootmsgs_v8;
my @elimpats;
my @cpats;
my @makesoa;
my $Domainfile;
my %cpatrel;
my @Servers;
my $Serial;
my $Refresh;
my @Mx;
my $Expire;
my %Hosts;
my %Comments;
my $Domainpattern;
my @Netpatterns;
my $Ttl;
my $Retry;
my %Cnames;
my %CommentRRs;
my $soa_warned;
my %Aliases;
my %Netfiles;

sub process_request
{
    $request    = shift;
    $callback   = shift;
    %Netfiles   = ();
    %Aliases    = ();
    $soa_warned = 0;
    my $canonical;
    my $aliases;
    %Comments    = ();
    %CommentRRs  = ();
    %Cnames      = ();
    %Hosts       = ();
    @Netpatterns = ();
    $DBDir       = "/var/named/";

    unless (-d $DBDir)
    {
        $DBDir = "/var/lib/named/";
    }

    # if both do not exist, make /var/named
    unless (-d $DBDir)
    {
        $DBDir = "/var/named/";
        my $cmd = "/bin/mkdir $DBDir";
        my $outref = xCAT::Utils->runcmd("$cmd", 0);
        if ($::RUNCMD_RC != 0)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Could not create $DBDir.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            exit 1;
        }
    }

    $Host = hostname;
    $Host =~ s/\..*//;
    my $sitetab = xCAT::Table->new('site');
    unless ($sitetab)
    {
        my $rsp = {};
        $rsp->{data}->[0] = "No site table found.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return;
    }
    my @args = ();
    if ($request->{arg})
    {
        @args = @{$request->{arg}};
        @ARGV = @{$request->{arg}};
    }
    &checkusageandversion($callback);

    (my $fent) = $sitetab->getAttribs({key => 'forwarders'}, 'value');
    if ($fent and defined $fent->{value})
    {
        @forwarders = split /[,:;]/, $fent->{value};
    }
    unless (grep /^-d$/, @args)
    {
        (my $dent) = $sitetab->getAttribs({key => 'domain'}, 'value');
        if ($dent and $dent->{value})
        {
            push @args, "-d";
            $dent->{value} =~ s/\.$//;
            push @args, $dent->{value};
        }
    }
    unless (grep /^-s$/, @args)
    {
        push @args, "-s";
        push @args, $Host;
    }
    unless (grep /^-n$/, @args)
    {
        my $nettab = xCAT::Table->new('networks');
        unless ($nettab)
        {
            my $rsp = {};
            $rsp->{data}->[0] =
              "Unable to open networks table, has makenetworks been run?.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            return;
        }
        foreach (@{$nettab->getAllEntries()})
        {
            push @args, "-n";
            push @args, $_->{net} . ":" . $_->{mask};
        }
    }

    push(@bootmsgs_v4, "primary\t0.0.127.IN-ADDR.ARPA db.127.0.0\n");
    push(@bootmsgs_v8,
         qq|zone "0.0.127.IN-ADDR.ARPA" in {\n\ttype master;\n\tfile "db.127.0.0";\n\tnotify no;\n};\n\n|
         );

    &PARSEARGS($callback, @args);
    &FIXUP($callback);
    unless (open(HOSTS, $Hostfile))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Unable to open $Hostfile\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        exit 1;
    }
    my $data;
    my $comment;
    my $addr;
    my $names;
  LINE: while (<HOSTS>)
    {
        next if /^[ \t]*#/;    # skip comment lines
        next if /^$/;          # skip empty lines
        chop;                  # remove the trailing newline
        tr/A-Z/a-z/;           # translate to lower case

        ($data, $comment) = split('#',     $_,    2);
        ($addr, $names)   = split(/[ 	]+/, $data, 2);
        if ($names =~ /^[ \t]*$/)
        {

            #$callback->({data=>["Bad line in hosts file ignored '$_'"]});
            next LINE;
        }
        $addr =~ s/^[    ]*//;
        $addr =~ s/[    ]*$//;
        if ($addr !~ /^\d+\.\d+\.\d+\.\d+$/)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Ignoring $addr (not a valid IPv4 address).\n";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            next LINE;
        }

        # Match -e args
        my $netpat;
        foreach $netpat (@elimpats)
        {
            next LINE if (/[.\s]$netpat/);
        }

        # Process -c args
        foreach $netpat (@cpats)
        {
            if (/\.$netpat/)
            {
                ($canonical, $aliases) = split(' ', $names, 2);
                $canonical =~ s/\.$netpat//;
                #If we feed in names with, say, underscores, bind complains usually due to default check-names behavior.  Later, we may should support putting check-names to ignore, but for now let them know it won't work and skip it
                unless ($canonical =~ /^[a-z0-9-]+$/i) {
                    xCAT::MsgUtils->message("E", {errorcode=>[1],error=>["$canonical contains invalid characters, skipping entry"]}, $callback, 1);
                    next LINE;
                }
                if ($Cnames{$canonical} != 1)
                {
                    printf DOMAIN "%-20s IN  CNAME %s.%s.\n", $canonical,
                      $canonical, $cpatrel{$netpat};
                    $Cnames{$canonical} = 1;
                }
                next LINE;
            }
        }

        # Check that the address is in the address list.
        my $match = 'none';
        foreach $netpat (@Netpatterns)
        {
            $match = $netpat, last
              if ($addr =~ /^$netpat\./ or $addr =~ /^$netpat$/);
        }
        next if ($match eq 'none');

        ($canonical, $aliases) = split(' ', $names, 2);   # separate out aliases
        next if ($dontdodomains && $canonical =~ /\./);   # skip domain names
        $canonical =~ s/$Domainpattern//;    # strip off domain if there is one
        unless ($canonical =~ /^[a-z0-9-]+$/i) {
            xCAT::MsgUtils->message("E", {errorcode=>[1],error=>["$canonical contains invalid characters, skipping entry"]}, $callback, 1);
            next;
         }
        $Hosts{$canonical} .= $addr . " ";   # index addresses by canonical name
        $Aliases{$addr} .= $aliases . " ";   # index aliases by address
        $Comments{"$canonical-$addr"} = $comment;

        # Print PTR records
        my $file = $Netfiles{$match};
        printf $file "%-30s\tIN  PTR   %s.%s.\n", &REVERSE($addr), $canonical,
          $Domain;
    }

    #
    # Go through the list of canonical names.
    # If there is more than 1 address associated with the
    # name, it is a multi-homed host.  For each address
    # look up the aliases since the aliases are associated
    # with the address, not the canonical name.
    #
    foreach $canonical (keys %Hosts)
    {
        my @addrs = split(' ', $Hosts{$canonical});
        my $numaddrs = $#addrs + 1;
        foreach my $addr (@addrs)
        {

            #
            # Print address record for canonical name.
            #
            if ($Cnames{$canonical} != 1)
            {
                printf DOMAIN "%-20s IN  A     %s\n", $canonical, $addr;
            }
            else
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "$canonical - cannot create A record because CNAME exists for name.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            }

            #
            # Print cname or address records for each alias.
            # If this is a multi-homed host, print an address
            # record for each alias.  If this is a single address
            # host, print a cname record.
            #
            my $alias;
            if ($doaliases)
            {
                my @aliases = split(' ', $Aliases{$addr});
                foreach $alias (@aliases)
                {

                    #
                    # Skip over the alias if the alias and canonical
                    # name only differ in that one of them has the
                    # domain appended to it.
                    #
                    next
                      if ($dontdodomains && $alias =~ /\./); # skip domain names
                    $alias =~ s/$Domainpattern//;
                    if ($alias eq $canonical)
                    {
                        next;
                    }
                    unless ($alias  =~ /^[a-z0-9-]+$/i) {
                        xCAT::MsgUtils->message("E", {errorcode=>[1],error=>["$canonical alias $alias contains invalid characters, skipping entry"]}, $callback, 1);
                        next;
                    }

                    my $aliasforallnames = 0;
                    if ($numaddrs > 1)
                    {

                        #
                        # If alias exists for *all* addresses of this host, we
                        # can use a CNAME instead of an address record.
                        #
                        my $aliasforallnames = 1;
                        my $xalias = $alias . " "; # every alias ends with blank
                        my @xaddrs = split(' ', $Hosts{$canonical});
                        foreach my $xaddr (@xaddrs)
                        {
                            if (!($Aliases{$xaddr} =~ /\b$xalias/))
                            {
                                $aliasforallnames = 0;
                            }
                        }
                    }

                    if (($numaddrs > 1) && !$aliasforallnames)
                    {
                        printf DOMAIN "%-20s IN  A     %s\n", $alias, $addr;
                    }
                    else
                    {

                        #
                        # Flag aliases that have already been used
                        # in CNAME records or have A records.
                        #
                        if (($Cnames{$alias} != 1) && (!$Hosts{$alias}))
                        {
                            printf DOMAIN "%-20s IN  CNAME %s.%s.\n", $alias,
                              $canonical, $Domain;
                            $Cnames{$alias} = 1;
                        }
                        else
                        {
                            my $rsp = {};
                            $rsp->{data}->[0] =
                              "$alias - CNAME or A exists already. alias ignored.\n";
                            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                        }
                    }

                    if ($aliasforallnames)
                    {

                        #
                        # Since a CNAME record was created, remove this
                        # name from the alias list so we don't encounter
                        # it again for the next address of this host.
                        #
                        my $xalias = $alias . " "; # every alias ends with blank
                        my @xaddrs = split(' ', $Hosts{$canonical});
                        my $xaddr;
                        foreach $xaddr (@xaddrs)
                        {
                            $Aliases{$xaddr} =~ s/\b$xalias//;
                        }
                    }
                }
            }
        }
        if ($domx)
        {
            &MX($callback, $canonical, @addrs);
        }
        if ($dotxt)
        {
            &TXT($canonical, @addrs);
        }
        if ($Commentfile ne "")
        {
            &DO_COMMENTS($callback, $canonical, @addrs);
        }
    }

    # Deal with spcl's
    if (-r "spcl.$Domainfile")
    {
        print DOMAIN "\$INCLUDE spcl.$Domainfile\n";
    }
    my $file;
    my $n;
    foreach $n (@Networks)
    {
        if (-r "spcl.$n")
        {
            $file = "DB.$n";
            print $file "\$INCLUDE spcl.$n\n";
        }
    }

    # generate boot.* files
    &GEN_BOOT($callback);
    my $rsp = {};
    $rsp->{data}->[0] = "Setup of DNS complete.";
    xCAT::MsgUtils->message("I", $rsp, $callback);
    exit 0;
}

#
# Generate resource record data for
# strings from the commment field that
# are found in the comment file (-C).
#
sub DO_COMMENTS
{
    my ($callback, $canonical, @addrs) = @_;
    my (@c, $c, $a, $comments);

    if (!$Commentfileread)
    {
        unless (open(F, $Commentfile))
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Unable to open file $Commentfile: $!.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            exit 1;
        }
        $Commentfileread++;
        while (<F>)
        {
            chop;
            my ($key, $c) = split(':', $_, 2);
            $CommentRRs{$key} = $c;
        }
        close(F);
    }

    my $key;
    foreach $a (@addrs)
    {
        $key = "$canonical-$a";
        $comments .= " $Comments{$key}";
    }

    @c = split(' ', $comments);
    foreach $c (@c)
    {
        if ($CommentRRs{$c})
        {
            printf DOMAIN "%-20s %s\n", $canonical, $CommentRRs{$c};
        }
    }
}

#
# Generate MX record data
#
sub MX
{
    my ($callback, $canonical, @addrs) = @_;
    my ($first, $a, $key, $comments);

    if ($Cnames{$canonical})
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "$canonical - cannot create MX record because CNAME exists for name.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        return;
    }
    $first = 1;

    foreach $a (@addrs)
    {
        $key = "$canonical-$a";
        $comments .= " $Comments{$key}";
    }

    if ($comments !~ /\[no smtp\]/)
    {

        # Add WKS if requested
        if ($dowks)
        {
            foreach $a (@addrs)
            {
                printf DOMAIN "%-20s IN  WKS   %s TCP SMTP\n", $canonical, $a;
            }
        }
        printf DOMAIN "%-20s IN  MX    %s %s.%s.\n", $canonical, $DefMxWeight,
          $canonical, $Domain;
        $first = 0;
    }
    if ($#Mx >= 0)
    {
        foreach $a (@Mx)
        {
            if ($first)
            {
                printf DOMAIN "%-20s IN  MX    %s\n", $canonical, $a;
                $first = 0;
            }
            else
            {
                printf DOMAIN "%-20s IN  MX    %s\n", "", $a;
            }
        }
    }

}

#
# Generate TXT record data
#
sub TXT
{
    my ($canonical, @addrs) = @_;
    my ($a, $key, $comments);

    foreach $a (@addrs)
    {
        $key = "$canonical-$a";
        $comments .= " $Comments{$key}";
    }
    $comments =~ s/\[no smtp\]//g;
    $comments =~ s/^\s*//;
    $comments =~ s/\s*$//;

    if ($comments ne "")
    {
        printf DOMAIN "%s IN  TXT   \"%s\"\n", $canonical, $comments;
    }
}

#
# Create the SOA record at the beginning of the file
#
sub MAKE_SOA
{
    my ($callback, $fname, $file) = @_;
    my ($s);

    if (-s $fname)
    {

        unless (open($file, "$fname"))
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Unable to open $fname: $!.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            exit 1;
        }
        $_ = <$file>;
        chop;
        if (/\($/)
        {
            my $junk;
            if (!$soa_warned)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Converting SOA format to new style.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                $soa_warned++;
            }
            if ($ForceSerial > 0)
            {
                $Serial = $ForceSerial;
            }
            else
            {
                ($Serial, $junk) = split(' ', <$file>, 2);
                $Serial++;
                if ($UseDateInSerial && ($DateSerial > $Serial))
                {
                    $Serial = $DateSerial;
                }
            }
            ($Refresh, $junk) = split(' ', <$file>, 2);
            ($Retry,   $junk) = split(' ', <$file>, 2);
            ($Expire,  $junk) = split(' ', <$file>, 2);
            ($Ttl,     $junk) = split(' ', <$file>, 2);
        }
        else
        {
            if (/TTL/)
            {
                $_ = <$file>;
            }
            split(' ');
            if ($#_ == 11)
            {
                if ($ForceSerial > 0)
                {
                    $Serial = $ForceSerial;
                }
                else
                {
                    $Serial = ++$_[6];
                    if ($UseDateInSerial && ($DateSerial > $Serial))
                    {
                        $Serial = $DateSerial;
                    }
                }
                $Refresh = $_[7];
                $Retry   = $_[8];
                $Expire  = $_[9];
                $Ttl     = $_[10];
            }
            else
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Improper format SOA in $fname.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit(1);
            }
        }
        if ($UseDefSOAValues)
        {
            $Refresh = $DefRefresh;
            $Retry   = $DefRetry;
            $Expire  = $DefExpire;
            $Ttl     = $DefTtl;
        }
        close($file);
    }
    else
    {
        if ($ForceSerial > 0)
        {
            $Serial = $ForceSerial;
        }
        else
        {
            $Serial = $DefSerial;
            if ($UseDateInSerial && ($DateSerial > $Serial))
            {
                $Serial = $DateSerial;
            }
        }
        $Refresh = $DefRefresh;
        $Retry   = $DefRetry;
        $Expire  = $DefExpire;
        $Ttl     = $DefTtl;
        close($file);
    }

    unless (open($file, "> $fname"))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Unable to open $fname: $!.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        exit 1;
    }
    print $file '$TTL 86400' . "\n";
    print $file "\@ IN  SOA $RespHost $RespUser ";
    print $file "( $Serial $Refresh $Retry $Expire $Ttl )\n";
    foreach $s (@Servers)
    {
        print $file "  IN  NS  $s\n";
    }
    print $file "\n";
}

#
# Reverse the octets of an IP address and append
# in-addr.arpa.
#
sub REVERSE
{
    join('.', reverse(split('\.', $_[0]))) . '.IN-ADDR.ARPA.';
}

#
# Establish what we will be using for SOA records
#
sub FIXUP
{
    my $callback = shift;
    my ($s);

    if ($Host =~ /\./)
    {
        $RespHost = "$Host.";
    }
    else
    {
        $RespHost = "$Host.$Domain.";
    }
    $RespHost =~ s/\.\././g;

    if ($User =~ /@/)
    {    # -u user@...
        if ($User =~ /\./)
        {
            $RespUser = "$User.";    # -u user@terminator.movie.edu
        }
        else
        {
            $RespUser = "$User.$Domain.";    # -u user@terminator
        }
        $RespUser =~ s/@/./;
    }
    elsif ($User =~ /\./)
    {
        $RespUser = "$User.";                # -u user.terminator.movie.edu
    }
    else
    {
        $RespUser = "$User.$RespHost";       # -u user
    }
    $RespUser =~ s/\.\././g;                 # Strip any ".."'s to "."

    # Clean up nameservers
    if (!@Servers)
    {
        my $rsp = {};
        $rsp->{data}->[0] =
          "No -s option specified.  Assuming \"-s $Host.$Domain\".\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        push(@Servers, "$Host.$Domain.");
    }
    else
    {
        foreach $s (@Servers)
        {
            if ($s !~ /\./)
            {
                $s .= ".$Domain";
            }
            if ($s !~ /\.$/)
            {
                $s .= ".";
            }
        }
    }

    # Clean up MX hosts
    foreach $s (@Mx)
    {
        $s =~ s/:/ /;
        if ($s !~ /\./)
        {
            $s .= ".$Domain";
        }
        if ($s !~ /\.$/)
        {
            $s .= ".";
        }
    }

    # Now open boot file (named.conf)  and print saved data
    unless (open(BOOT, "> $Bootfile"))
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Unable to  open $Bootfile.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        exit 1;
    }

    #
    # Write either the version 4 boot file directives or the
    # version 8 boot file directives.
    #

    if ($Version == 4)
    {
        print BOOT "\ndirectory $DBDir\n";
        foreach my $line (@bootmsgs_v4)
        {
            print BOOT $line;
        }
        print BOOT "cache\t. db.cache\n";
        if (-r "spcl.boot")
        {
            print BOOT "include\tspcl.boot\n";
        }
    }
    else
    {
        print BOOT qq|\noptions {\n\tdirectory "$DBDir";\n|;
        if (@forwarders)
        {
            print BOOT qq|\tforwarders {\n|;
            foreach (@forwarders)
            {
                print BOOT qq|\t\t$_;\n|;
            }
            print BOOT qq|\t};\n|;
        }
        if (-r "spcl.options")
        {
            print BOOT "\t# These options came from the file spcl.options\n";

            #
            # Copy the options in since "include" cannot be used
            # within a statement.
            #
            unless (open(OPTIONS, "<spcl.options"))
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Unable to open spcl.options.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit 1;
            }
            while (<OPTIONS>)
            {
                print BOOT;
            }
            close(OPTIONS);
        }
        print BOOT qq|};\n\n|;
        foreach my $line (@bootmsgs_v8)
        {
            print BOOT $line;
        }

        # hint zone is also needed for DNS forwarders on AIX
        if (xCAT::Utils->isAIX())
        {
            print BOOT
              qq|zone "." in {\n\ttype hint;\n\tfile "db.cache";\n};\n\n|;
        }
        else
        {
            unless (@forwarders)
            {
                print BOOT
                  qq|zone "." in {\n\ttype hint;\n\tfile "db.cache";\n};\n\n|;
            }
        }
        
        if (-r "spcl.boot")
        {
            print BOOT qq|include "spcl.boot";\n\n|;
        }
    }

    close(BOOT);

    # Go ahead and start creating files and making SOA's
    my $x1;
    my $x2;
    foreach my $i (@makesoa)
    {
        ($x1, $x2) = split(' ', $i);
        &MAKE_SOA($callback, $x1, $x2);
    }
    printf DOMAIN "%-20s IN  A     127.0.0.1\n", "localhost";

    my $file = "DB.127.0.0.1";
    &MAKE_SOA($callback, $DBDir . "db.127.0.0", $file);
    if (xCAT::Utils->isAIX())
    {
        # if forwarders is set, we need to create the hint file for root name servers.
        if (@forwarders)
        {
            my $tmpfile = $DBDir . "db.cache";
            my $cmd = qq~dig @"$forwarders[0]" . ns >> $tmpfile~;
            my $outref = xCAT::Utils->runcmd("$cmd", 0);
            if ($::RUNCMD_RC != 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Could not run command: $cmd.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit 1;
            }
        }
        else
        {
            my $nothing;
            open($nothing, ">>", $DBDir . "db.cache");
            close($nothing);

        }
    }
    else
    {
        my $nothing;
        open($nothing, ">>", $DBDir . "db.cache");
        close($nothing);

    }
    printf $file "%-30s\tIN  PTR   localhost.\n", &REVERSE("127.0.0.1");
    close($file);
}

sub PARSEARGS
{
    my ($callback, @args) = @_;
    my ($i, $net, $subnetmask, $option, $tmp1);
    my ($file, @newargs, @targs);
    my ($sec, $min, $hour, $mday, $mon, $year, $rest);
    ($sec, $min, $hour, $mday, $mon, $year, $rest) = localtime(time);
    $DateSerial =
      ($mday * 100) + (($mon + 1) * 10000) + (($year + 1900) * 1000000);

    $i = 0;
    while ($i <= $#args)
    {
        $option = $args[$i];
        if ($option eq "-d")
        {
            if ($Domain ne "")
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Only one -d option allowed.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit(1);
            }
            $Domain        = $args[++$i];
            $Domainpattern = "." . $Domain;
            $Domainpattern =~ s/\./\\./g;    # for stripping off domain

            # Add entry to the boot file.
            $Domainfile = $Domain;
            $Domainfile =~ s/\..*//;
            push(@makesoa,     $DBDir . "db.$Domainfile DOMAIN");
            push(@bootmsgs_v4, "primary\t$Domain db.$Domainfile\n");
            push(@bootmsgs_v8,
                 qq|zone "$Domain" in {\n\ttype master;\n\tfile "db.$Domainfile";\n};\n\n|
                 );

        }
        elsif ($option eq "-f")
        {
            $file = $args[++$i];
            unless (open(F, $file))
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Unable to open args file $file: $!.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit 1;
            }
            while (<F>)
            {
                next if (/^#/);
                next if (/^$/);
                chop;
                @targs = split(' ');
                push(@newargs, @targs);
            }
            close(F);
            &PARSEARGS($callback, @newargs);

        }
        elsif ($option eq "-z")
        {
            $Bootsecsaveaddr = $args[++$i];
            if (!defined($Bootsecaddr))
            {
                $Bootsecaddr = $Bootsecsaveaddr;
            }

        }
        elsif ($option eq "-Z")
        {
            $Bootsecaddr = $args[++$i];
            if (!defined($Bootsecsaveaddr))
            {
                $Bootsecsaveaddr = $Bootsecaddr;
            }

        }
        elsif ($option eq "-b")
        {
            $Bootfile = $args[++$i];

        }
        elsif ($option eq "-A")
        {
            $doaliases = 0;

        }
        elsif ($option eq "-M")
        {
            $domx = 0;

        }
        elsif ($option eq "-w")
        {
            $dowks = 1;

        }
        elsif ($option eq "-D")
        {
            $dontdodomains = 1;

        }
        elsif ($option eq "-t")
        {
            $dotxt = 1;

        }
        elsif ($option eq "-u")
        {
            $User = $args[++$i];

        }
        elsif ($option eq "-s")
        {
            while ($args[++$i] !~ /^-/ && $i <= $#args)
            {
                push(@Servers, $args[$i]);
            }
            $i--;

        }
        elsif ($option eq "-m")
        {
            if ($args[++$i] !~ /:/)
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "Improper format for -m option ignored ($args[$i]).\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            }
            push(@Mx, $args[$i]);

        }
        elsif ($option eq "-c")
        {
            my $tmp1 = $args[++$i];
            if ($tmp1 !~ /\./)
            {
                $tmp1 .= ".$Domain";
            }
            if ($Domain eq $tmp1)
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "Domain for -c option must not match domain for -d option.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit(1);
            }
            my $tmp2 = $tmp1;
            $tmp2 =~ s/\./\\./g;
            $cpatrel{$tmp2} = $tmp1;
            push(@cpats, $tmp2);

        }
        elsif ($option eq "-e")
        {
            $tmp1 = $args[++$i];
            if ($tmp1 !~ /\./)
            {
                $tmp1 .= ".$Domain";
            }
            $tmp1 =~ s/\./\\./g;
            push(@elimpats, $tmp1);

        }
        elsif ($option eq "-h")
        {
            $Host = $args[++$i];

        }
        elsif ($option eq "-o")
        {
            if ($args[++$i] !~ /^[:\d]*$/
                || split(':', $args[$i]) != 4)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Improper format for -o ($args[$i]).\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit(1);
            }
            ($DefRefresh, $DefRetry, $DefExpire, $DefTtl) =
              split(':', $args[$i]);
            $UseDefSOAValues = 1;

        }
        elsif ($option eq "-i")
        {
            $ForceSerial = $args[++$i];

        }
        elsif ($option eq "-H")
        {
            $Hostfile = $args[++$i];
            if (!-r $Hostfile || -z $Hostfile)
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "Invalid file specified for -H ($Hostfile).\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit(1);
            }

        }
        elsif ($option eq "-C")
        {
            $Commentfile = $args[++$i];
            if (!-r $Commentfile || -z $Commentfile)
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "Invalid file specified for -C ($Commentfile).\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit(1);
            }

        }
        elsif ($option eq "-N")
        {
            $Defsubnetmask = $args[++$i];
            if ($Defsubnetmask !~ /^[.\d]*$/
                || split('\.', $Defsubnetmask) != 4)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Improper subnet mask ($Defsubnetmask).\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                exit(1);
            }
            if ($#Networks >= 0)
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "-N option should be specified before any -n options.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            }

        }
        elsif ($option eq "-n")
        {
            (my $tnet, $subnetmask) = split(':', $args[++$i]);
            $net = "";
            my @netm  = split(/\./, $subnetmask);
            my @tnets = split(/\./, $tnet);
            foreach (0 .. 3)
            {
                my $res = ($tnets[$_] + 0) & ($netm[$_] + 0);
                if ($netm[$_])
                {
                    $net .= $res . '.';
                }
            }
            $net =~ s/\.$//;

            if (not $net)
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "Empty network found in networks table (i.e. ,,),This is almost certainly going to cause a problem....\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            }
            if ($subnetmask eq "")
            {
                my $rsp = {};
                $rsp->{data}->[0] =
                  "$net has no defined netmask in the networks table, the result will probably be wrong.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                foreach $tmp1 (&SUBNETS($net, $Defsubnetmask))
                {
                    &BUILDNET($tmp1);
                }
            }
            else
            {
                if ($subnetmask !~ /^[.\d]*$/
                    || split('\.', $subnetmask) != 4)
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Improper subnet mask ($subnetmask).\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                    exit(1);
                }
                foreach $tmp1 (&SUBNETS($net, $subnetmask))
                {
                    &BUILDNET($tmp1);
                }
            }

        }
        else
        {
            if ($option =~ /^-.*/)
            {
                my $rsp = {};
                $rsp->{data}->[0] = "Unknown option: $option ... ignored.\n";
                xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            }
        }
        $i++;
    }

    if (!@Networks || $Domain eq "")
    {
        my $rsp = {};
        $rsp->{data}->[0] = "Must specify one -d and at least one -n.\n";
        xCAT::MsgUtils->message("E", $rsp, $callback, 1);
        exit(1);
    }
}

sub BUILDNET
{
    my ($net) = @_;

    push(@Networks, $net);

    #
    # Create pattern to match against.
    # The dots must be changed to \. so they
    # aren't used as wildcards.
    #
    my $netpat = $net;
    $netpat =~ s/\./\\./g;
    push(@Netpatterns, $netpat);

    #
    # Create db files for PTR records.
    # Save the file names in an array for future use.
    #
    my $netfile = "DB.$net";
    $Netfiles{$netpat} = $netfile;
    push(@makesoa, $DBDir . "db.$net $netfile");

    # Add entry to the boot file.
    my $revaddr = &REVERSE($net);
    chop($revaddr);    # remove trailing dot
    push(@bootmsgs_v4, "primary $revaddr db.$net\n");
    push(@bootmsgs_v8,
         qq|zone "$revaddr" in {\n\ttype master;\n\tfile "db.$net";\n};\n\n|);
}

#
# Calculate all the subnets from a network number and mask.
# This was originally written for awk, not perl.
#
sub SUBNETS
{
    my ($network, $mask) = @_;
    my (@ans, @net, @mask, $buf, $number, $i, $j, $howmany);

    @net  = split(/\./, $network);
    @mask = split(/\./, $mask);
    $number = '';

    #
    # Only expand bytes 1, 2, or 3
    # for DNS purposes
    #
    for ($i = 0 ; $i < 4 ; $i++)
    {
        if ($mask[$i] == 255)
        {
            $number = $number . $net[$i] . '.';
        }
        elsif (($mask[$i] == 0) || $mask[$i] eq '')
        {
            push(@ans, $network);
            last;
        }
        else
        {

            #
            # This should be done as a bit-wise or
            # but awk does not have an or symbol
            #
            $howmany = 255 - $mask[$i];
            for ($j = 0 ; $j <= $howmany ; $j++)
            {
                if ($net[$i] + $j <= 255)
                {
                    $buf = sprintf("%s%d", $number, $net[$i] + $j);
                    push(@ans, $buf);
                }
            }
            last;
        }
    }

    if ($#ans == -1)
    {
        push(@ans, $network);
    }

    @ans;
}

sub GEN_BOOT
{
    $callback = shift;
    my ($revaddr, $n);

    if (0)
    {    #! -e "boot.cacheonly") { DISABLE THIS PART
            #
            # Create a boot file for a cache-only server
            #
        unless (open(F, ">boot.cacheonly"))
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Unable to open boot.cacheonly: $!.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            exit 1;
        }
        if ($Version == 4)
        {
            print F "directory\t$DBDir\n";
            print F "primary\t\t0.0.127.IN-ADDR.ARPA    db.127.0.0\n";
            print F "cache\t\t.                       db.cache\n";
            if (-r "spcl.cacheonly")
            {
                printf F "include\t\tspcl.cacheonly\n";
            }
            close(F);
        }
        else
        {
            print F qq|\noptions {\n\tdirectory "$DBDir";\n|;
            if (@forwarders)
            {
                print F qq|\tforwarders {\n|;
                foreach (@forwarders)
                {
                    print F qq|\t\t$_;\n|;
                }
                print F qq|\t};\n|;
            }
            if (-r "spcl.options")
            {
                print F "\t# These options came from the file spcl.options\n";

                #
                # Copy the options in since "include" cannot be used
                # within a statement.
                #

                unless (open(OPTIONS, "<spcl.options"))
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Unable to open boot.cacheonly: $!.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                    exit 1;
                }

                while (<OPTIONS>)
                {
                    print F;
                }
                close(OPTIONS);
            }
            print F qq|};\n\n|;
            print F qq|zone "0.0.127.IN-ADDR.ARPA" in {\n\ttype master;|;
            print F qq|\n\tfile "db.127.0.0";|;
            print F qq|\n\tnotify no;\n};\n\n|;

            #print F qq|zone "." in {\n\ttype hint;\n\tfile "db.cache";\n};\n\n|;
            if (-r "spcl.cacheonly")
            {
                print F qq|include "spcl.cacheonly";\n\n|;
            }
        }
    }

    #
    # Create a 2 boot files for a secondary (slave) servers.
    # One boot file doesn't save the zone data in a file.  The
    # other boot file does save the zone data in a file.
    #
    if (defined($Bootsecaddr))
    {
        unless (open(F, ">boot.sec"))
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Unable to open boot.sec: $!.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            exit 1;
        }

        if ($Version == 4)
        {
            print F "directory\t$DBDir\n";
            print F "primary\t\t0.0.127.IN-ADDR.ARPA    db.127.0.0\n";
            printf F "secondary\t%-23s $Bootsecaddr\n", $Domain;
            foreach $n (@Networks)
            {
                $revaddr = &REVERSE($n);
                chop($revaddr);
                printf F "secondary\t%-23s $Bootsecaddr\n", $revaddr;
            }
            print F "cache\t\t.                       db.cache\n";
            if (-r "spcl.boot")
            {
                printf F "include\t\tspcl.boot\n";
            }
        }
        else
        {
            print F qq|\noptions {\n\tdirectory "$DBDir";\n|;
            if (-r "spcl.options")
            {
                print F "\t# These options came from the file spcl.options\n";

                #
                # Copy the options in since "include" cannot be used
                # within a statement.
                #
                unless (open(OPTIONS, "<spcl.options"))
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Unable to open spcl.options.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                    exit 1;
                }

                while (<OPTIONS>)
                {
                    print F;
                }
                close(OPTIONS);
            }
            print F qq|};\n\n|;
            print F qq|zone "0.0.127.IN-ADDR.ARPA" in {\n\ttype master;|;
            print F qq|\n\tfile "db.127.0.0";|;
            print F qq|\n\tnotify no;\n};\n\n|;
            print F qq|zone "$Domain" in {\n\ttype slave;\n\tmasters {|;
            print F qq| $Bootsecaddr; };\n};\n\n|;

            foreach $n (@Networks)
            {
                $revaddr = &REVERSE($n);
                chop($revaddr);
                print F qq|zone "$revaddr" in {\n\ttype slave;\n\tmasters {|;
                print F qq| $Bootsecaddr; };\n};\n\n|;
            }

            #print F qq|zone "." in {\n\ttype hint;\n\tfile "db.cache";\n};\n\n|;
            if (-r "spcl.boot")
            {
                print F qq|include "spcl.boot";\n\n|;
            }
        }
        close(F);

        unless (open(F, ">boot.sec.save"))
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Unable to open  boot.sec.save: $!.\n";
            xCAT::MsgUtils->message("E", $rsp, $callback, 1);
            exit 1;
        }

        if ($Version == 4)
        {
            print F "directory\t$DBDir\n";
            print F "primary\t\t0.0.127.IN-ADDR.ARPA    db.127.0.0\n";
            printf F "secondary\t%-23s $Bootsecsaveaddr db.%s\n", $Domain,
              $Domainfile;
            foreach $n (@Networks)
            {
                $revaddr = &REVERSE($n);
                chop($revaddr);
                printf F "secondary\t%-23s $Bootsecsaveaddr db.%s\n", $revaddr,
                  $n;
            }
            print F "cache\t\t.                       db.cache\n";
            if (-r "spcl.boot")
            {
                printf F "include\t\tspcl.boot\n";
            }
        }
        else
        {
            print F qq|\noptions {\n\tdirectory "$DBDir";\n|;
            if (-r "spcl.options")
            {
                print F "\t# These options came from the file spcl.options\n";

                #
                # Copy the options in since "include" cannot be used
                # within a statement.
                #
                unless (open(OPTIONS, "<spcl.options"))
                {
                    my $rsp = {};
                    $rsp->{data}->[0] = "Can't open spcl.options.\n";
                    xCAT::MsgUtils->message("E", $rsp, $callback, 1);
                    exit 1;
                }
                while (<OPTIONS>)
                {
                    print F;
                }
                close(OPTIONS);
            }
            print F qq|};\n\n|;
            print F qq|zone "0.0.127.IN-ADDR.ARPA" in {\n\ttype master;|;
            print F qq|\n\tfile "db.127.0.0";|;
            print F qq|\n\tnotify no;\n};\n\n|;

            print F
              qq|zone "$Domain" in {\n\ttype slave;\n\tfile "db.$Domainfile";|;
            print F qq|\n\tmasters { $Bootsecsaveaddr; };\n};\n\n|;

            foreach $n (@Networks)
            {
                $revaddr = &REVERSE($n);
                chop($revaddr);
                print F
                  qq|zone "$revaddr" in {\n\ttype slave;\n\tfile "db.$n";\n\tmasters {|;
                print F qq| $Bootsecsaveaddr; };\n};\n\n|;
            }

            #print F qq|zone "." in {\n\ttype hint;\n\tfile "db.cache";\n};\n\n|;
            if (-r "spcl.boot")
            {
                print F qq|include "spcl.boot";\n\n|;
            }
        }
        close(F);
    }
}

# subroutine to display the usage
sub checkusageandversion
{
    my $callback = shift;

    # parse the options
    if (
        GetOptions('h|help'    => \$::HELP,
                   'v|version' => \$::VERSION)
      )
    {
        if ($::HELP)
        {
            my $rsp = {};
            $rsp->{data}->[0] = "Usage:";
            $rsp->{data}->[1] = "  makedns <options>";
            $rsp->{data}->[2] = "  makedns [-h|--help|-v|--version]";
            $rsp->{data}->[3] = "     <options> See man makedns";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            exit 0;
        }
        if ($::VERSION)
        {
            my $version = xCAT::Utils->Version();
            my $rsp     = {};
            $rsp->{data}->[0] = "$version";
            xCAT::MsgUtils->message("I", $rsp, $callback);
            exit 0;
        }
    }
    return;
}

1;
