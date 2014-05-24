#!/usr/bin/env perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
#####################################################
#
#  xCAT plugin package to handle commands that manage the xCAT object
#     definitions
#
#####################################################

package xCAT_plugin::DBobjectdefs;
BEGIN
{
    $::XCATROOT = $ENV{'XCATROOT'} ? $ENV{'XCATROOT'} : '/opt/xcat';
}
use xCAT::NodeRange;
use xCAT::Schema;
use xCAT::DBobjUtils;
use Data::Dumper;
use Getopt::Long;
use xCAT::MsgUtils;
use xCAT::Utils;
use xCAT::SvrUtils;
use strict;

# options can be bundled up like -vV
Getopt::Long::Configure("bundling");
$Getopt::Long::ignorecase = 0;

#
# Globals
#

%::CLIATTRS;      # attr=values provided on the command line
%::FILEATTRS;     # attr=values provided in an input file
%::FINALATTRS;    # final set of attr=values that are used to set
                  #    the object

%::objfilehash;   #  hash of objects/types based of "-f" option
                  #    (list in file)

%::WhereHash;     # hash of attr=val from "-w" option
@::AttrList;      # list of attrs from "-i" option
%::NicsAttrHash;  # hash of nics attributes specified with "-i" option
                  # e.g. $::NicsAttrHash{'nicips'} = ("eth0","eth1");

# object type lists
@::clobjtypes;      # list of object types derived from the command line.
@::fileobjtypes;    # list of object types from input file ("-x" or "-z")

#  object name lists
@::clobjnames;      # list of object names derived from the command line
@::fileobjnames;    # list of object names from an input file
@::objfilelist;     # list of object names from the "-f" option
@::allobjnames;     # combined list

@::noderange;       # list of nodes derived from command line

#------------------------------------------------------------------------------

=head1    DBobjectdefs

This program module file supports the management of the xCAT data object
definitions.

Supported xCAT data object commands:
     mkdef - create xCAT data object definitions.
     lsdef - list xCAT data object definitions.
     chdef - change xCAT data object definitions.
     rmdef - remove xCAT data object definitions.

If adding to this file, please take a moment to ensure that:

    1. Your contrib has a readable pod header describing the purpose and use of
      the subroutine.

    2. Your contrib is under the correct heading and is in alphabetical order
    under that heading.

    3. You have run tidypod on your this file and saved the html file

=cut

#------------------------------------------------------------------------------

=head2    xCAT data object definition support

=cut

#------------------------------------------------------------------------------

#----------------------------------------------------------------------------

=head3  handled_commands

        Return a list of commands handled by this plugin

=cut

#-----------------------------------------------------------------------------

sub handled_commands
{
    return {
            mkdef => "DBobjectdefs",
            lsdef => "DBobjectdefs",
            chdef => "DBobjectdefs",
            rmdef => "DBobjectdefs"
            };
}

#----------------------------------------------------------------------------

=head3   process_request

        Check for xCAT command and call the appropriate subroutine.

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

sub process_request
{

    $::request  = shift;
    $::callback = shift;

    my $ret;
    my $msg;

    &initialize_variables();
    # globals used by all subroutines.
    $::command  = $::request->{command}->[0];
    $::args     = $::request->{arg};
    $::filedata = $::request->{stdin}->[0];

    # figure out which cmd and call the subroutine to process
    if ($::command eq "mkdef")
    {
        ($ret, $msg) = &defmk;
    }
    elsif ($::command eq "lsdef")
    {
        ($ret, $msg) = &defls;
    }
    elsif ($::command eq "chdef")
    {
        ($ret, $msg) = &defch;
    }
    elsif ($::command eq "rmdef")
    {
        ($ret, $msg) = &defrm;
    }

    my $rsp;
    if ($msg)
    {
        $rsp->{data}->[0] = $msg;
    }
    if ($ret > 0) {
        $rsp->{errorcode}->[0] = $ret;
    }
    $::callback->($rsp);
}

sub parse_attr_for_osimage{
    my $command = shift;
    my $attr_hash = shift;
    if (!exists($attr_hash->{profile}) or !exists($attr_hash->{provmethod})) {
        my $rsp;
        $rsp->{data}->[0] = "The profile and provmethod are all need to be specified.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return -1;
    } else {
        my $tmp_profile = $attr_hash->{profile};
        my $tmp_provmethod = $attr_hash->{provmethod};
        if ($tmp_provmethod !~ /install|netboot|statelite/) {
            my $rsp;
            $rsp->{data}->[0] = "The provmethod: $tmp_provmethod is incorrect.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return -1;
        }
        my ($tmp_imagetype, $tmp_arch, $tmp_osname,$tmp_ostype,$tmp_osvers);
        if (!exists($attr_hash->{osarch})) {
            $tmp_arch = `uname -m`;
            chomp($tmp_arch);
            $tmp_arch = "x86" if ($tmp_arch =~ /i.86$/);
            $attr_hash->{osarch} = $tmp_arch;
        } else {
            $tmp_arch = $attr_hash->{osarch};
        }
        if (!exists($attr_hash->{osvers})) {
            $tmp_osvers = xCAT::Utils->osver("all");
            $tmp_osvers =~ s/,//;
            $attr_hash->{osvers} = $tmp_osvers; 
        } else {
            $tmp_osvers =$attr_hash->{osvers};
        }
        $tmp_osname = $tmp_osvers;
        $tmp_ostype="Linux";  #like Linux, Windows
        $tmp_imagetype="linux";
        my $prov_dir = ($tmp_provmethod eq "install") ? "install" : "netboot"; 
        if (($tmp_osvers =~ /^win/) || ($tmp_osvers =~ /^imagex/)) {
            $tmp_osname="windows";
            $tmp_ostype="Windows";
            $tmp_imagetype="windows";
        } elsif ($tmp_osvers =~ /^hyperv/) {
            $tmp_osname="hyperv";
            $tmp_ostype="Windows";
            $tmp_imagetype="windows";
        } else {
            until (-r  "$::XCATROOT/share/xcat/$prov_dir/$tmp_osname/" or not $tmp_osname) {
                chop($tmp_osname);
            }
            unless ($tmp_osname) {
                my $rsp;
                $rsp->{data}->[0] = "Unable to find $::XCATROOT/share/xcat/$prov_dir directory for $tmp_osvers.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return -1;
            }
        }
        #for rhels5.1  genos=rhel5
        my $tmp_genos = $tmp_osvers;
        $tmp_genos =~ s/\..*//;
        if ($tmp_genos =~ /rh.*s(\d*)/) {
            $tmp_genos = "rhel$1";
        }             
        if (exists($attr_hash->{imagetype}) && ($attr_hash->{imagetype} !~ /^$tmp_imagetype/i)) {
            my $rsp;
            $rsp->{data}->[0] = "The input imagetype:$attr_hash->{imagetype} not match $tmp_imagetype.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return -1;
        } elsif (!exists($attr_hash->{imagetype})) {
            $attr_hash->{imagetype} = $tmp_imagetype;
        }
        if (exists($attr_hash->{osname}) && ($attr_hash->{osname} !~ /^$tmp_ostype/i)) {
            my $rsp;
            $rsp->{data}->[0] = "The input osname:$attr_hash->{osname} not match $tmp_ostype.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return -1;
        } elsif (!exists($attr_hash->{osname})) {
            $attr_hash->{osname} = $tmp_ostype;
        } 
        #if (!exists($attr_hash->{osdistroname})) {
            $attr_hash->{osdistroname} = "$tmp_osvers-$tmp_arch";
        #}
        if (!exists($attr_hash->{synclists}) || $command eq "chdef") {
            my $tmp_synclist=xCAT::SvrUtils->getsynclistfile(undef, $tmp_osvers, $tmp_arch, $tmp_profile, "netboot");
            if ($tmp_synclist) {
                $attr_hash->{synclists} = $tmp_synclist;
            }
        }
        my @non_win_attr = qw(pkglist pkgdir otherpkglist otherpkgdir exlist postinstall rootimgdir template);
        if ($tmp_osname =~ /^win/) {
            my @invalid_attr = ();
            foreach (@non_win_attr) {
                if (exists($attr_hash->{$_})) {
                    push @invalid_attr, $_;
                }
            }
            if ($#invalid_attr) {
                my $rsp;
                $rsp->{data}->[0] = "$tmp_osvers can not work with @invalid_attr.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return -1;
            }
        } else {
            my $installroot = xCAT::TableUtils->getInstallDir();
            my @installdirs = xCAT::TableUtils->get_site_attribute("installdir");
            my $tmp = $installdirs[0];
            if ( defined($tmp)) {
                $installroot = $tmp;
            }
            my $cuspath="$installroot/custom/$prov_dir/$tmp_osname";
            my $defpath="$::XCATROOT/share/xcat/$prov_dir/$tmp_osname";
            if ($tmp_provmethod eq "install") {
                $attr_hash->{exlist} = '';
                $attr_hash->{postinstall} = '';
                $attr_hash->{rootimgdir} = '';
                if ((!exists($attr_hash->{template})) || ($command eq "chdef")) {
                my $tmp_tmplfile = xCAT::SvrUtils->get_tmpl_file_name($cuspath, $tmp_profile, $tmp_osvers, $tmp_arch, $tmp_genos);
                if (!$tmp_tmplfile) {
                    $tmp_tmplfile = xCAT::SvrUtils->get_tmpl_file_name($defpath, $tmp_profile, $tmp_osvers, $tmp_arch, $tmp_genos);
                } 
                if ($tmp_tmplfile) {
                    $attr_hash->{template} = $tmp_tmplfile;
                }
                }
            }
            if ($tmp_provmethod ne "install") {
                $attr_hash->{template} = '';
                if (!exists($attr_hash->{exlist})) {
                    my $tmp_exlist = xCAT::SvrUtils->get_exlist_file_name($cuspath, $tmp_profile, $tmp_osvers, $tmp_arch);
                    if (!$tmp_exlist) {
                        $tmp_exlist = xCAT::SvrUtils->get_exlist_file_name($defpath, $tmp_profile, $tmp_osvers, $tmp_arch);
                    }
                    if ($tmp_exlist) {
                        $attr_hash->{exlist} = $tmp_exlist;
                    }
                }
                if (!exists($attr_hash->{postinstall})) {
                    my $tmp_post = xCAT::SvrUtils->get_postinstall_file_name($cuspath, $tmp_profile, $tmp_osvers, $tmp_arch);
                    if (!$tmp_post) {
                        $tmp_post = xCAT::SvrUtils->get_postinstall_file_name($defpath, $tmp_profile, $tmp_osvers, $tmp_arch);
                    }
                    if ($tmp_post) {
                        $attr_hash->{postinstall} = $tmp_post;
                    }
                }
                if (!exists($attr_hash->{rootimgdir})) {
                    $attr_hash->{rootimgdir}="$installroot/netboot/$tmp_osvers/$tmp_arch/$tmp_profile";
                }
            }
            if (!exists($attr_hash->{pkglist})) {
                my $tmp_pkglist = xCAT::SvrUtils->get_pkglist_file_name($cuspath, $tmp_profile, $tmp_osvers, $tmp_arch);
                if (!$tmp_pkglist) {
                    $tmp_pkglist = xCAT::SvrUtils->get_pkglist_file_name($defpath, $tmp_profile, $tmp_osvers, $tmp_arch);
                }
                if ($tmp_pkglist) {
                    $attr_hash->{pkglist} = $tmp_pkglist;
                }
            }
            if (!exists($attr_hash->{otherpkglist})) {
                my $tmp_othpkglist = xCAT::SvrUtils->get_otherpkgs_pkglist_file_name($cuspath, $tmp_profile, $tmp_osvers, $tmp_arch);
                if (!$tmp_othpkglist) {
                    $tmp_othpkglist = xCAT::SvrUtils->get_otherpkgs_pkglist_file_name($defpath, $tmp_profile, $tmp_osvers, $tmp_arch);
                }
                if ($tmp_othpkglist) {
                    $attr_hash->{otherpkglist} = $tmp_othpkglist;
                }
            }
            if (!exists($attr_hash->{otherpkgdir})) {
                $attr_hash->{otherpkgdir}="$installroot/post/otherpkgs/$tmp_osvers/$tmp_arch";
            }
            if (!exists($attr_hash->{pkgdir})) {
                $attr_hash->{pkgdir}="$installroot/$tmp_osvers/$tmp_arch";
            }
        }
    }
    return 0;
}
#----------------------------------------------------------------------------

=head3   processArgs

        Process the command line. Covers all four commands.

        Also - Process any input files provided on cmd line.

        Arguments:

        Returns:
                0 - OK
                1 - just return
                2 - just print usage
                3 - error
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub processArgs
{
    my $gotattrs = 0;
    if ( defined ($::args) && @{$::args} ) {
        @ARGV = @{$::args};
    } else {
        if ($::command eq "lsdef") {
            push @ARGV, "-t";
            push @ARGV, "node";
            push @ARGV, "-s";
        } else {
            return 2;
        }
    }
    if ( defined ($::args) && @{$::args} ) {
      if ( scalar(@{$::args}) eq 1 and $::args->[0] eq '-S')
      {
        if ($::command eq "lsdef") {
            push @ARGV, "-t";
            push @ARGV, "node";
            push @ARGV, "-s";
        } else {
            return 2;
        }
      }
    }

    if ($::command eq "lsdef") {
        if (scalar(@ARGV) == 2 && (($ARGV[0] eq "-l" && $ARGV[1] eq "-S") || ($ARGV[0] eq "-S" && $ARGV[1] eq "-l"))){
            push @ARGV, "-t";
            push @ARGV, "node";
        }
    }
    if ($::command eq "lsdef") {
        if (scalar(@ARGV) == 1 && $ARGV[0] eq "-l") {
            push @ARGV, "-t";
            push @ARGV, "node";
        }
    }

    if (scalar(@ARGV) <= 0) {
        return 2;
    }

    # parse the options - include any option from all 4 cmds
    Getopt::Long::Configure("no_pass_through");
    if (
        !GetOptions(
                    'all|a'     => \$::opt_a,
                    'compress|c'=> \$::opt_c,
                    'dynamic|d' => \$::opt_d,
                    'f|force'   => \$::opt_f,
                    'i=s'       => \$::opt_i,
                    'help|h|?'    => \$::opt_h,
                    'long|l'    => \$::opt_l,
                    'short|s'    => \$::opt_s,
                    'm|minus'   => \$::opt_m,
                    'n=s'       => \$::opt_n,
                    'o=s'       => \$::opt_o,
                    'p|plus'    => \$::opt_p,
                    't=s'       => \$::opt_t,
                    'verbose|V' => \$::opt_V,
                    'version|v' => \$::opt_v,
                    'w=s@'       => \$::opt_w,
                    'x|xml'     => \$::opt_x,
                    'z|stanza'  => \$::opt_z,
                    'nocache'  => \$::opt_nc,
                    'S'        => \$::opt_S,
                    'osimage'  => \$::opt_osimg,
                    'nics'  => \$::opt_nics,
                    'u'     => \$::opt_setattr,
        )
      )
    {

        my $rsp;
        $rsp->{data}->[0] = "Invalid option..";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }

    if (defined($::opt_setattr) && ($::command ne "chdef") && ($::command ne "mkdef")) {
        my $rsp;
        $rsp->{data}->[0]="Option \'-u\' can not work with $::command.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }

    if (defined($::opt_setattr)) {
        if (!$::opt_t && !$::filedata) {
            $::opt_t = 'osimage';
        } elsif ($::opt_t ne "osimage") {
            my $rsp;
            $rsp->{data}->[0]="Option \'-u\' only work for objtype \'osimage\'.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 2;
        }
    }
    # -t node is the default value
    if (!$::opt_t && !$::opt_a && !$::opt_h && ($::command eq "lsdef"))
    {
        $::opt_t = 'node';
    }

    # Initialize some global arrays in case this is being called twice in the same process.
    # Currently only doing this when --nocache is specified, but i think it should be done all of the time.
    if ($::opt_nc) {
            &initialize_variables();
    }

    #  opt_x not yet supported
    if ($::opt_x)
    {

        my $rsp;
        $rsp->{data}->[0] =
          "The \'-x\' (XML format) option is not yet implemented.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }

    # -i and --osimage cannot be used together
    if ($::opt_i && $::opt_osimg) {
        my $rsp;
        $rsp->{data}->[0] = "The flags \'-i'\ and \'--osimage'\ cannot be used together.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }

    # -z and --osimage cannot be used together
    if ($::opt_z && $::opt_osimg) {
        my $rsp;
        $rsp->{data}->[0] = "The flags \'-z'\ and \'--osimage'\ cannot be used together.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }

    # -a and -t cannot be used together
    if ($::opt_a && $::opt_t) {
        my $rsp;
        $rsp->{data}->[0] = "The flags \'-a'\ and \'-t'\ cannot be used together.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }

    # -l and -s cannot be used together
    if ($::opt_l && $::opt_s) {
        my $rsp;
        $rsp->{data}->[0] = "The flags \'-l'\ and \'-s'\ cannot be used together.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }

    # -i and --nics cannot be used together
    if ($::opt_nics && $::opt_i) {
        my $rsp;
        $rsp->{data}->[0] = "The flags \'-i'\ and \'--nics'\ cannot be used together.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }

    # --nics is the equivalent of -i nicips,nichostnamesuffixes...
    if ($::opt_nics) {
        $::opt_i="nicips,nichostnamesuffixes,nichostnameprefixes,nictypes,niccustomscripts,nicnetworks,nicaliases";
    }

    # -i and -s cannot be used together
    if ($::opt_i && $::opt_s) {
        my $rsp;
        $rsp->{data}->[0] = "The flags \'-i'\ and \'-s'\ cannot be used together.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }

    # -c must be used together with -i
    if ($::opt_c && !$::opt_i) {
        my $rsp;
        $rsp->{data}->[0] = "The flags \'-c'\ and \'-i'\ must be used together.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 2;
    }
    # can get object names in many ways - easier to keep track
    $::objectsfrom_args = 0;
    $::objectsfrom_opto = 0;
    $::objectsfrom_optt = 0;
    $::objectsfrom_opta = 0;
    $::objectsfrom_nr   = 0;
    $::objectsfrom_file = 0;

    #
    # process @ARGV
    #

    #  - put attr=val operands in ATTRS hash
    my $noderangespace = 0;
    while (my $a = shift(@ARGV))
    {

        if (!($a =~ /=/))
        {

            # can not have spaces in the noderange
            if ($noderangespace)
            {
               my $rsp;
               $rsp->{data}->[0] = "noderange can not contain spaces.";
               xCAT::MsgUtils->message("E", $rsp, $::callback);
               return 2;
            }
            $noderangespace++;
            # the first arg could be a noderange or a list of args
            if (($::opt_t) && ($::opt_t ne 'node'))
            {

                # if we know the type isn't "node" then set the object list
                @::clobjnames = split(',', $a);
                @::noderange = @::clobjnames;
                $::objectsfrom_args = 1;
            }
            elsif (!$::opt_t || ($::opt_t eq 'node'))
            {

                # if the type was not provided or it is "node"
                #    then set noderange
                if (($::command ne 'mkdef') && ($a =~ m/^\//))
                {
                    @::noderange = &noderange($a, 1); # Use the "verify" option to support regular expression
                }
                else
                {
                    @::noderange = &noderange($a, 0); # mkdef could not spport regular expression
                }
                if (scalar(@::noderange) == 0)
                {
                    my $rsp;
                    $rsp->{data}->[0] = "No node in \'$a\', check the noderange syntax.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    return 3;
                }
            }

        }
        else
        {

            # if it has an "=" sign its an attr=val - we hope
            #   - this will handle "attr= "
            # The attribute itself might contain "space", like "nics.Local Connection Adapter 1" on windows
            my ($attr, $value) = $a =~ /^\s*(.*?)\s*=\s*(\S*.*)$/;
            if (!defined($attr) || !defined($value))
            {
                my $rsp;
                $rsp->{data}->[0] = "Incorrect \'attr=val\' pair - $a.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 3;
            }

            $gotattrs = 1;

            # put attr=val in hash
            $::ATTRS{$attr} = $value;

        }
    }

    if ((!$::opt_t || $::opt_t eq 'node') && ($::command eq 'chdef') && ($::opt_m || $::opt_p))
    {
        my $nicattrs = 0;
        foreach my $kattr (keys %::ATTRS)
        {
            if ($kattr =~ /^nic\w+\..*$/)
            {
                $nicattrs = 1;
            }
            last;
        }
        if ($nicattrs)
        {
            my $rsp;
            $rsp->{data}->[0] = "chdef does not support to change the nic related attributes with -m or -p flag.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 3;
        }
    }

    # Check arguments for rmdef command
    # rmdef is very dangerous if wrong flag is specified
    # it may cause all the objects to be deleted, check the flags
    # for example: rmdef -t node -d, the user want to delete the node named "-d",
    # but it will delete all the nodes!
    # use -o instead
    if ($::command eq 'rmdef')
    {
        if (defined($::opt_d) || defined($::opt_i) || defined($::opt_l) 
           || defined($::opt_m) || defined($::opt_p) || defined($::opt_w) 
           || defined($::opt_x) || defined($::opt_z) || defined($::opt_s))
        {
            my $rsp;
            $rsp->{data}->[0] = "Invalid flag specified, see rmdef manpage for details.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 2;
        }
    }

    # Option -h for Help
    # if user specifies "-t" & "-h" they want a list of valid attrs
    if (defined($::opt_h) && !defined($::opt_t))
    {
        return 2;
    }

    # Option -v for version - do we need this???
    if (defined($::opt_v))
    {
        my $rsp;
        my $version=xCAT::Utils->Version();
        push @{$rsp->{data}}, "$::command - $version";
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        return 1;    # no usage - just exit
    }

    # Option -V for verbose output
    if (defined($::opt_V))
    {
        $::verbose = 1;
        $::VERBOSE = 1;
    } else {
        $::verbose = 0;
        $::VERBOSE = 0;
    }

    #
    # process the input file - if provided
    #
    if ($::filedata)
    {

        my $rc = xCAT::DBobjUtils->readFileInput($::filedata);

        if ($rc)
        {
            my $rsp;
            $rsp->{data}->[0] = "Could not process file input data.";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
            return 1;
        }

        #   - %::FILEATTRS{fileobjname}{attr}=val
        # set @::fileobjtypes, @::fileobjnames, %::FILEATTRS

        $::objectsfrom_file = 1;
    }

    #
    #  determine the object types
    #

    # could have comma seperated list of types
    if ($::opt_t)
    {
        my @tmptypes;

        if ($::opt_t =~ /,/)
        {

            # can't have mult types when using attr=val
            if ($gotattrs)
            {
                my $rsp;
                $rsp->{data}->[0] =
                  "Cannot combine multiple types with \'att=val\' pairs on the command line.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 3;
            }
            else
            {
                @tmptypes = split(',', $::opt_t);
            }
        }
        else
        {
            push(@tmptypes, $::opt_t);
        }

        # check for valid types
        my @xdeftypes;
        foreach my $k (keys %{xCAT::Schema::defspec})
        {
            push(@xdeftypes, $k);
        }

        foreach my $t (@tmptypes)
        {
            if (!grep(/^$t$/, @xdeftypes))
            {
                my $rsp;
                $rsp->{data}->[0] =
                  "\nType \'$t\' is not a valid xCAT object type.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 3;
            }
            else
            {
                chomp $t;
                push(@::clobjtypes, $t);
            }
        }
    }


    # must have object type(s) - default if not provided
    if (!@::clobjtypes && !@::fileobjtypes && !$::opt_a && !$::opt_t)
    {

        # make the default type = 'node' if not specified
        push(@::clobjtypes, 'node');
        my $rsp;
        if ( !$::opt_z && !$::opt_x) {
            # don't want this msg in stanza or xml output
            #$rsp->{data}->[0] = "Assuming an object type of \'node\'.";
            #xCAT::MsgUtils->message("I", $rsp, $::callback);
        }
    }

    # if user specifies "-t" & "-h" they want valid type or attrs info
    if ($::opt_h && $::opt_t)
    {

        # give the list of attr names for each type specified
        foreach my $t (@::clobjtypes)
        {
            my $rsp;

            if ($t eq 'site') {
                if ($::opt_i)
                {
                    my $tmprsp;
                    $tmprsp->{data}->[0] = "It is not supported to list the description of some specific site attributes, displaying the description for all site attributes instead.";
                    xCAT::MsgUtils->message("W", $tmprsp, $::callback);
                }
                my $schema = xCAT::Table->getTableSchema('site');
                my $desc;

                $rsp->{data}->[0] = "\nThere can only be one xCAT site definition. This definition consists \nof an unlimited list of user-defined attributes and values that represent \nglobal settings for the whole cluster. The following is a list \nof the attributes currently supported by xCAT."; 

                $desc = $schema->{descriptions}->{'key'};
                $rsp->{data}->[1] = $desc;

                xCAT::MsgUtils->message("I", $rsp, $::callback);
                next;
            }

            # get the data type  definition from Schema.pm
            my $datatype = $xCAT::Schema::defspec{$t};

            if (!$::opt_i)
            {
                $rsp->{data}->[0] = "The valid attribute names for object type '$t' are:";
            }

            # get the objkey for this type object (ex. objkey = 'node')
            my $objkey = $datatype->{'objkey'};

            $rsp->{data}->[1] = "Attribute          Description\n";

            my @alreadydone;    # the same attr may appear more then once
            my @attrlist;
            my $outstr = "";
            my @dispattrs = ();
            my %dispattrhash = ();
            if ($::opt_i)
            {
                @dispattrs = split(/,/, $::opt_i);
                foreach my $dattr (@dispattrs)
                {
                    # lsdef -t node -h -i nicips.eth0
                    if($dattr =~ /^(nic\w+)\..*$/)
                    {
                        $dattr = $1;
                    }
                    $dispattrhash{$dattr} = 1;
                }
            }
            foreach my $this_attr (@{$datatype->{'attrs'}})
            {
                my $attr = $this_attr->{attr_name};
                # Only display the specified attributes
                if ($::opt_i)
                {
                    if (!defined($dispattrhash{$attr}) || !$dispattrhash{$attr})
                    {
                        next;
                    }
                }
                my $desc = $this_attr->{description};
                if (!defined($desc)) {     
                    # description key not there, so go to the corresponding 
                    #    entry in tabspec to get the description
                    my ($tab, $at) = split(/\./, $this_attr->{tabentry});
                    my $schema = xCAT::Table->getTableSchema($tab);
                    $desc = $schema->{descriptions}->{$at};
                }

                # could display the table that the attr is in
                # however some attrs are in more than one table!!!
                #my ($tab, $junk) = split('\.', $this_attr->{tabentry});

                if (!grep(/^$attr$/, @alreadydone))
                {
                    my $space = (length($attr)<7 ? "\t\t" : "\t");
                    push(@attrlist, "$attr:$space$desc\n\n");
                }
                push(@alreadydone, $attr);
            }

            # print the output in alphabetical order
            foreach my $a (sort @attrlist) {
                $outstr .= "$a";
            }
            chop($outstr);  chop($outstr);
            $rsp->{data}->[2] = $outstr;

            # the monitoring table is  special
            if ($t eq 'monitoring') {
                $rsp->{data}->[3] = "\nYou can also include additional monitoring plug-in specific settings. These settings will be used by the monitoring plug-in to customize the behavior such as event filter, sample interval, responses etc.";
            }
            
            xCAT::MsgUtils->message("I", $rsp, $::callback);
        }

        return 1;
    }

    #
    #  determine the object names
    #

    # -  get object names from the -o option or the noderange
    if ($::opt_o)
    {

        $::objectsfrom_opto = 1;

        # special handling for site table !!!!!
        if (($::opt_t eq 'site') && ($::opt_o ne 'clustersite'))
        {
            push(@::clobjnames, $::opt_o);
            push(@::clobjnames, 'clustersite');

        }
        elsif ($::opt_t eq 'node')
        {
            if (($::command ne 'mkdef') && ($::opt_o =~ m/^\//))
            {
                @::clobjnames = &noderange($::opt_o, 1); #Use the "verify" option to support regular expression
            }
            else
            {
                @::clobjnames = &noderange($::opt_o, 0); #mkdef can not support regular expression
            }
        }
        else
        {

            # make a list
            if ($::opt_o =~ /,/)
            {
                @::clobjnames = split(',', $::opt_o);
            }
            else
            {
                push(@::clobjnames, $::opt_o);
            }
        }
    }
    elsif (@::noderange && (@::clobjtypes[0] eq 'node'))
    {

        # if there's no object list and the type is node then the
        #   noderange list is assumed to be the object names list
        @::clobjnames     = @::noderange;
        $::objectsfrom_nr = 1;
    }

    # special case for site table!!!!!!!!!!!!!!
    if (($::opt_t eq 'site') && !$::opt_o)
    {
        push(@::clobjnames, 'clustersite');
        $::objectsfrom_opto = 1;
    }

    # if there is no other input for object names then we need to
    #    find all the object names for the specified types
    #   Do NOT do this for rmdef
    if ($::opt_t
        && !(   $::opt_o
             || $::filedata
             || $::opt_a
             || @::noderange
             || @::clobjnames))
    {
        my @tmplist;

        if (($::command eq 'rmdef') || ($::command eq 'chdef'))
        {
            my $rsp;
            $rsp->{data}->[0] =
              "No object names were provided.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 2;
        }
        # also ne chdef ????????
        if ($::command ne 'mkdef')
        {

            $::objectsfrom_optt = 1;

            # could have multiple type
            foreach my $t (@::clobjtypes)
            {

                # special case for site table !!!!
                if ($t eq 'site')
                {
                    push(@tmplist, 'clustersite');

                }
                else
                {

                    #  look up all objects of this type in the DB ???
                    @tmplist = xCAT::DBobjUtils->getObjectsOfType($t);

                    unless (@tmplist)
                    {
                        my $rsp;
                        $rsp->{data}->[0] =
                          "Could not get objects of type \'$t\'.";
                        #$rsp->{data}->[1] = "Skipping to the next type.\n";
                        xCAT::MsgUtils->message("E", $rsp, $::callback);
                        return 3;
                    }
                }

                # add objname and type to hash and global list
                foreach my $o (@tmplist)
                {
                    push(@::clobjnames, $o);
                    $::ObjTypeHash{$o} = $t;
                }
            }
        }
    }


    # can't have -a with other obj sources
    if ($::opt_a
        && ($::opt_o || $::filedata || @::noderange))
    {

        my $rsp;
        $rsp->{data}->[0] =
          "Cannot use \'-a\' with \'-o\', a noderange or file input.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 3;
    }

    #  if -a then get a list of all DB objects
    if ($::opt_a)
    {

        my @tmplist;

        # for every type of data object get the list of defined objects
        foreach my $t (keys %{xCAT::Schema::defspec})
        {
            # exclude the auditlog and eventlog,
            # the auditlog and eventlog tables might be very big
            # use lsdef -t auditlog or lsdef -t eventlog instead
            if (($t eq 'auditlog') || ($t eq 'eventlog')) { next; }

            $::objectsfrom_opta = 1;

            my @tmplist;
            @tmplist = xCAT::DBobjUtils->getObjectsOfType($t);

            # add objname and type to hash and global list
            if (scalar(@tmplist) > 0)
            {
                foreach my $o (@tmplist)
                {
                    push(@::clobjnames, $o);
                    $::AllObjTypeHash{$o} = $t;
                }
            }
        }
    }

    # must have object name(s) -
    if ((scalar(@::clobjnames) == 0) && (scalar(@::fileobjnames) == 0))
    {
        my $rsp;
        $rsp->{data}->[0] =
          "No object names were provided.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 3;
    }

    # combine object name all object names provided
    @::allobjnames = @::clobjnames;
    if (scalar(@::fileobjnames) > 0)
    {

        # add list from stanza or xml file
        push @::allobjnames, @::fileobjnames;
    }
    elsif (scalar(@::objfilelist) > 0)
    {

        # add list from "-f" file option
        push @::allobjnames, @::objfilelist;
    }

    #  check for the -w option
    if ($::opt_w)
    {
        my $rc = xCAT::Utils->parse_selection_string($::opt_w, \%::WhereHash);
        if ($rc != 0)
        {
            my $rsp;
            $rsp->{data}->[0] = "Incorrect selection string specified with -w flag.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 3;
        }
        # For dynamic node groups, check the selection string
        if (($::opt_t eq 'group') && ($::opt_d))
        {
            my $datatype = $xCAT::Schema::defspec{'node'};
            my @nodeattrs = ();
            foreach my $this_attr (@{$datatype->{'attrs'}})
            {
                push @nodeattrs, $this_attr->{attr_name};
            }
            foreach my $whereattr (keys %::WhereHash)
            {
                if (!grep(/^$whereattr$/, @nodeattrs))
                {
                    my $rsp;
                    $rsp->{data}->[0] = "Incorrect attribute \'$whereattr\' in the selection string specified with -w flag.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    return 1;
                }
             }
        }
    }

    #  check for the -i option
    if ($::opt_i && ($::command ne 'lsdef'))
    {
        my $rsp;
        $rsp->{data}->[0] =
          "The \'-i\' option is only valid for the lsdef command.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 3;
    }

    #  just make a global list of the attr names provided
    if ($::opt_i)
    {
        @::AttrList = split(',', $::opt_i);
        # nicips.<nic> should be changed to nicips
        my $i = 0;
        for ($i=0; $i < (scalar @::AttrList) ; $i++ )
        {
            if($::AttrList[$i] =~ /^(nic\w+)\.(.*)$/)
            {
                $::AttrList[$i] = $1; 
                push @{$::NicsAttrHash{$::AttrList[$i]}}, $2;
            }
        }
    }

    return 0;
}

#----------------------------------------------------------------------------

=head3   defmk

        Support for the xCAT mkdef command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
            Object names to create are derived from
                -o, -t, w, -z, -x, or noderange!
            Attr=val pairs come from cmd line args or -z/-x files
=cut

#-----------------------------------------------------------------------------

sub defmk
{

    @::allobjnames = [];

    my $rc    = 0;
    my $error = 0;

    my %objTypeLists;

    # process the command line
    $rc = &processArgs;

    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - return, 2 - help, 3 - error
        # 0 - continue
        # 1 - return  (like for version option)
        # 2 - return with usage
        # 3 - return error
        if ($rc == 1) {
            return 0;
        } elsif ($rc == 2) {
            &defmk_usage;
            return 0;
        } elsif ($rc == 3) {
            return 1;
        }
    }

    # check options unique to these commands
    if ($::opt_p || $::opt_m)
    {

        # error
        my $rsp;
        $rsp->{data}->[0] =
          "The \'-p\' and \'-m\' options are not valid for the mkdef command.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        &defmk_usage;
        return 1;
    }

    if ($::opt_t && ($::opt_a || $::opt_z || $::opt_x))
    {
        my $rsp;
        $rsp->{data}->[0] =
          "Cannot combine \'-t\' and \'-a\', \'-z\', or \'-x\' options.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        &defmk_usage;
        return 1;
    }

    # can't have -z with other obj sources
    if ($::opt_z && ($::opt_o || @::noderange))
    {
        my $rsp;
        $rsp->{data}->[0] = "Cannot use \'-z\' with \'-o\' or a noderange.";
        $rsp->{data}->[1] = "Example of -z usage:\n\t\'cat stanzafile | mkdef -z\'";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        &defmk_usage;
        return 1;
    }

    # check to make sure we have a list of objects to work with
    if (!@::allobjnames)
    {
        my $rsp;
        $rsp->{data}->[0] = "No object names were provided.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        &defmk_usage;
        return 1;
    } else {
        my $invalidnodename = ();
        foreach my $node (@::allobjnames) {
            if (($node =~ /[A-Z]/) && ((!$::opt_t) || ($::opt_t eq "node"))) {
                $invalidnodename .= ",$node";
            }
        }
        if ($invalidnodename) {
            $invalidnodename =~ s/,//;
            my $rsp;
            $rsp->{data}->[0] = "The node name \'$invalidnodename\' contains capital letters which may not be resolved correctly by the dns server.";
            xCAT::MsgUtils->message("W", $rsp, $::callback);
        }
    }

    # set $objtype & fill in cmd line hash
    if (%::ATTRS || ($::opt_t eq "group"))
    {

        # if attr=val on cmd line then could only have one type
        $::objtype = @::clobjtypes[0];

        #
        #  set cli attrs for each object definition
        #
        foreach my $objname (@::clobjnames)
        {

            #  set the objtype attr - if provided
            if ($::objtype)
            {
                $::CLIATTRS{$objname}{objtype} = $::objtype;
            }

            # get the data type definition from Schema.pm
            my $datatype = $xCAT::Schema::defspec{$::objtype};
            my @list;
            foreach my $this_attr (sort @{$datatype->{'attrs'}})
            {
                my $a = $this_attr->{attr_name};
                push(@list, $a);
            }

            # set the attrs from the attr=val pairs
            foreach my $attr (keys %::ATTRS)
            {
                my $attrorig = $attr;
                # nicips.eth0 => nicips
                if ($attr =~ /^(nic\w+)\..*$/)
                {
                    $attr = $1;
                }
                if (!grep(/^$attr$/, @list) && ($::objtype ne 'site') && ($::objtype ne 'monitoring'))
                {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "\'$attr\' is not a valid attribute name for an object type of \'$::objtype\'.";
                    $rsp->{data}->[1] = "Skipping to the next attribute.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    $error = 1;
                    next;
                }
                else
                {
                    $::CLIATTRS{$objname}{$attrorig} = $::ATTRS{$attrorig};
                    if ($::verbose)
                    {
                        my $rsp;
                        $rsp->{data}->[0] = "\nFunction: defmk-->set the attrs for each object definition";
                        $rsp->{data}->[1] = "defmk: objname=$objname, attr=$attrorig, value=$::ATTRS{$attrorig}";
                        xCAT::MsgUtils->message("I", $rsp, $::callback);
                    }
                }
            }    # end - foreach attr

        }
    }

    #
    #   Pull all the pieces together for the final hash
    #        - combines the command line attrs and input file attrs if provided
    #
    if (&setFINALattrs != 0)
    {
        $error = 1;
    }

    # we need a list of objects that are
    #    already defined for each type.
    foreach my $t (@::finalTypeList)
    {

        # special case for site table !!!!!!!!!!!!!!!!!!!!
        if ($t eq 'site')
        {
            @{$objTypeLists{$t}} = 'clustersite';
        }
        else
        {

            @{$objTypeLists{$t}} = xCAT::DBobjUtils->getObjectsOfType($t);
        }
        if ($::verbose)
        {
            my $rsp;
            $rsp->{data}->[0] = "\ndefmk: list objects that are defined for each type";
            $rsp->{data}->[1] = "@{$objTypeLists{$t}}";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
        }
    }

    # Build up a hash for the array in objTypeLists
    # for performance consideration, grep the array is not effective
    my %objTypeListsHash;
    foreach my $objk (keys %objTypeLists)
    {
        foreach my $obj (@{$objTypeLists{$objk}}) {
            $objTypeListsHash{$objk}{$obj} = 1;
        }
    }

    OBJ: foreach my $obj (keys %::FINALATTRS)
    {

        my $type = $::FINALATTRS{$obj}{objtype};

        # check to make sure we have type
        if (!$type)
        {
            my $rsp;
            $rsp->{data}->[0] = "No type was provided for object \'$obj\'.";
            $rsp->{data}->[1] = "Skipping to the next object.";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
            $error = 1;
            next;
        }

        # we don't want to overwrite any existing table row.  This could
        #    happen if there are multiple table keys. (ex. networks table -
        #        where the object name is not either of the table keys - net 
        #        & mask)
        #  just handle network objects for now - 
        if ($type eq 'network') {
            my @nets = xCAT::DBobjUtils->getObjectsOfType('network');
            my %objhash;
            foreach my $n (@nets) {
                $objhash{$n} = $type;
            }
            my %nethash = xCAT::DBobjUtils->getobjdefs(\%objhash);
            foreach my $o (keys %nethash) {
                if ( ($nethash{$o}{net} eq $::FINALATTRS{$obj}{net})  && ($nethash{$o}{mask} eq $::FINALATTRS{$obj}{mask}) ) {
                    my $rsp;
                    $rsp->{data}->[0] = "A network definition called \'$o\' already exists that contains the same net and mask values. Cannot create a definition for \'$obj\'.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    $error = 1;
                    delete $::FINALATTRS{$obj};
                    next OBJ;
                }    
            }
        }

        # if object already exists
        if (defined($objTypeListsHash{$type}{$obj}) && ($objTypeListsHash{$type}{$obj} == 1))
        {
            if ($::opt_f)
            {
                # remove the old object
                my %objhash;
                $objhash{$obj} = $type;
                if (xCAT::DBobjUtils->rmobjdefs(\%objhash) != 0)
                {
                    $error = 1;
                    my $rsp;
                    $rsp->{data}->[0] =
                      "Could not remove the definition for \'$obj\'.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                }
            }
            else
            {

                #  won't remove the old one unless the force option is used
                my $rsp;
                $rsp->{data}->[0] =
                  "\nA definition for \'$obj\' already exists.";
                $rsp->{data}->[1] =
                  "To remove the old definition and replace it with \na new definition use the force \'-f\' option.";
                $rsp->{data}->[2] =
                  "To change the existing definition use the \'chdef\' command.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                $error = 1;
                delete $::FINALATTRS{$obj};
                next;

            }

        }

        # need to handle group definitions - special!
        if ($type eq 'group')
        {

            my @memberlist;

            # if the group type was not set then set it
            if (!$::FINALATTRS{$obj}{grouptype})
            {
                if ($::opt_d)
                {
                    # For dynamic node group, 
                    # can not assign attributes for inherit
                    # only the 'objtype' in %::FINALATTRS
                    if (scalar(keys %{$::FINALATTRS{$obj}}) > 1)
                    {
                        my $rsp;
                        $rsp->{data}->[0] = "Can not assign attributes to dynamic node group \'$obj\'.";
                        xCAT::MsgUtils->message("E", $rsp, $::callback);
                        $error = 1;
                        delete($::FINALATTRS{$obj});
                        next;
                    } 
                    $::FINALATTRS{$obj}{grouptype} = 'dynamic';
                    $::FINALATTRS{$obj}{members}   = 'dynamic';
                }
                else
                {
                    $::FINALATTRS{$obj}{grouptype} = 'static';
                }
            }

            # if dynamic and wherevals not set then set to opt_w
            if ($::FINALATTRS{$obj}{grouptype} eq 'dynamic')
            {
                if (!$::FINALATTRS{$obj}{wherevals})
                {
                    if ($::opt_w)
                    {
                        $::FINALATTRS{$obj}{wherevals} = join ('::', @{$::opt_w});
                        #$::FINALATTRS{$obj}{wherevals} = $::opt_w;
                    }
                    else
                    {
                        my $rsp;
                        $rsp->{data}->[0] =
                          "The \'where\' attributes and values were not provided for dynamic group \'$obj\'.";
                        $rsp->{data}->[1] = "Skipping to the next group.";
                        xCAT::MsgUtils->message("E", $rsp, $::callback);
                        next;
                    }
                }
            }

            # if static group then figure out memberlist
            if ($::FINALATTRS{$obj}{grouptype} eq 'static')
            {
                if ($::opt_w && $::FINALATTRS{$obj}{members})
                {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "Cannot use a list of members together with the \'-w\' option.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    return 1;
                }

                if ($::FINALATTRS{$obj}{members})
                {
                    @memberlist = &noderange($::FINALATTRS{$obj}{members}, 0);

                    #  don't list all the nodes in the group table
                    #    set the value to static and we'll figure out the list
                    #     by looking in the nodelist table
                    $::FINALATTRS{$obj}{members} = 'static';

                }
                else
                {
                    if ($::opt_w)
                    {
                        $::FINALATTRS{$obj}{members} = 'static';

                        #  get a list of nodes whose attr values match the
                        #   "where" values and make that the memberlist of
                        #   the group.

                        # get a list of all node nodes
                        my @tmplist =
                          xCAT::DBobjUtils->getObjectsOfType('node');

                        # create a hash of obj names and types
                        my %objhash;
                        foreach my $n (@tmplist)
                        {
                            $objhash{$n} = 'node';
                        }

                        # get all the attrs for these nodes
                        my @whereattrs = keys %::WhereHash;
                        my %myhash = xCAT::DBobjUtils->getobjdefs(\%objhash, 0, \@whereattrs);

                        # see which ones match the where values
                        foreach my $objname (keys %myhash)
                        {

                            if (xCAT::Utils->selection_string_match(\%myhash, $objname, \%::WhereHash)) {
                                push(@memberlist, $objname);

                            }
                        }

                    }
                    else
                    {
                        my $rsp;
                        $rsp->{data}->[0] =
                          "Cannot determine a member list for group \'$obj\'.";
                        xCAT::MsgUtils->message("W", $rsp, $::callback);
                    }
                }

                # mkdef -t group should not create new nodes
                my @tmpmemlist = ();
                my @allnodes = xCAT::DBobjUtils->getObjectsOfType('node');
                foreach my $tmpnode (@memberlist)
                {
                    if (!grep(/^$tmpnode$/, @allnodes))
                    {
                        my $rsp;
                        $rsp->{data}->[0] = "Could not find a node named \'$tmpnode\', skipping to the next node.";
                        xCAT::MsgUtils->message("E", $rsp, $::callback);
                    }
                    else
                    {
                        push @tmpmemlist, $tmpnode;
                    }
                }
                @memberlist = @tmpmemlist;

                #  need to add group name to all members in nodelist table
                my $tab =
                  xCAT::Table->new('nodelist', -create => 1, -autocommit => 0);

                my $newgroups;
                my $changed=0;
                foreach my $n (@memberlist)
                {
                    if ($::verbose)
                    {
                        my $rsp;
                        $rsp->{data}->[0] = "defmk: add group name [$n] to nodelist table";
                        xCAT::MsgUtils->message("I", $rsp, $::callback);
                    }

                    #  add this group name to the node entry in
                    #        the nodelist table
                    #$nodehash{$n}{groups} = $obj;

                    # get the current value
                    my $grps = $tab->getNodeAttribs($n, ['groups']);

                    # if it's not already in the "groups" list then add it
                    my @tmpgrps = split(/,/, $grps->{'groups'});

                    if (!grep(/^$obj$/, @tmpgrps))
                    {
                        if ($grps and $grps->{'groups'})
                        {
                            $newgroups = "$grps->{'groups'},$obj";

                        }
                        else
                        {
                            $newgroups = $obj;
                        }
                    }

                    #  add this group name to the node entry in
                    #       the nodelist table
                    if ($newgroups)
                    {
                        $tab->setNodeAttribs($n, {groups => $newgroups});
            $changed=1;
                    }

                }
        if ($changed) {
            $tab->commit;
        }


            }
        }    # end - if group type

        # If none of the attributes in nodelist is defined: groups,status,appstatus,primarysn,comments,disable
        # the nodelist table will not be updated, caused mkdef failed.
        # We give a restriction that the "groups" must be specified with mkdef.
        if (($type eq "node") && !defined($::FINALATTRS{$obj}{groups}))
        {
            my $rsp;
            $rsp->{data}->[0] =
            "Attribute \'groups\' is not specified for node \'$obj\', skipping to the next node.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            $error = 1;
            next;
        }
        # Removed the code to handle the nodegroup table with mkdef -t node groups=xxx
        # Only dynamic groups should be in nodegroup table
        # Do not try to add static group into the nodegroup table
        # performance!!!!
        if (defined($::opt_setattr) && $type eq "osimage") {
            my $rc = &parse_attr_for_osimage($::command, $::FINALATTRS{$obj});
            if ($rc) {
                $error = $rc;
                next;
            } 
        } 

    } # end of each obj

    #
    #  write each object into the tables in the xCAT database
    #

    if (xCAT::DBobjUtils->setobjdefs(\%::FINALATTRS) != 0)
    {
        my $rsp;
        $rsp->{data}->[0] = "Could not write data to the xCAT database.";

        #        xCAT::MsgUtils->message("E", $rsp, $::callback);
        $error = 1;
    }

    if ($error)
    {
        my $rsp;
        $rsp->{data}->[0] =
          "One or more errors occured when attempting to create or modify xCAT \nobject definitions.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    else
    {
        if ($::verbose)
        {

            #  give results
            my $rsp;
            $rsp->{data}->[0] =
              "The database was updated for the following objects:";
            xCAT::MsgUtils->message("I", $rsp, $::callback);

            my $n = 1;
            foreach my $o (sort(keys %::FINALATTRS))
            {
                $rsp->{data}->[$n] = "$o";
                $n++;
            }
            xCAT::MsgUtils->message("I", $rsp, $::callback);
        }
        else
        {
            my $rsp;
            my $nodenum = scalar(keys %::FINALATTRS);
            $rsp->{data}->[0] =
              "$nodenum object definitions have been created or modified.";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
        }
        return 0;
    }
}

#----------------------------------------------------------------------------

=head3   defch

        Support for the xCAT chdef command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
            Object names to create are derived from
                -o, -t, w, -z, -x, or noderange!
            Attr=val pairs come from cmd line args or -z/-x files
=cut

#-----------------------------------------------------------------------------

sub defch
{

    @::allobjnames = [];

    my $rc    = 0;
    my $error = 0;
    my $firsttime = 1;

    my %objTypeLists;

    # hash that contains all the new objects that are being created
    my %newobjects;

    # process the command line
    $rc = &processArgs;

    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - return, 2 - help, 3 - error
        # 0 - continue
        # 1 - return  (like for version option)
        # 2 - return with usage
        # 3 - return error
        if ($rc == 1) {
            return 0;
        } elsif ($rc == 2) {
            &defch_usage;
            return 0;
        } elsif ($rc == 3) {
            return 1;
        }
    }


    #
    # check options unique to this command
    #
    if ($::opt_n) {
        # check the option for changing object name
        if ($::opt_n && ($::opt_d || $::opt_p || $::opt_m || $::opt_z || $::opt_w)) {
            my $rsp;
            $rsp->{data}->[0] = "Cannot combine \'-n\' and \'-d\',\'-p\',\'-m\',\'-z\',\'-w\' options.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            &defch_usage;
            return 1;
        }

        if (scalar (@::clobjnames) > 1) {
            my $rsp;
            $rsp->{data}->[0] =
              "The \'-n\' option (changing object name) can only work on one object.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            &defch_usage;
            return 1;
        }

        my %objhash = ($::clobjnames[0] => $::clobjtypes[0]);

        my @validnode = xCAT::DBobjUtils->getObjectsOfType($::clobjtypes[0]);
        if (! grep /^$::clobjnames[0]$/, @validnode) {
            my $rsp;
            $rsp->{data}->[0] =
              "The $::clobjnames[0] is not a valid object.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 1;
        }

        # Use the getobjdefs function to get a hash which including
        # all the records in the table that should be changed
        my %chnamehash = ();
        xCAT::DBobjUtils->getobjdefs(\%objhash, $::VERBOSE, undef, \%chnamehash);

        foreach my $tb (keys %chnamehash) {
            my $tab = xCAT::Table->new( $tb);
            unless ( $tab) {
                my $rsp;
                push @{$rsp->{data}}, "Unable to open $tb table.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }
            
            my $index = 0;
            my @taben = @{$chnamehash{$tb}};
            # In the @taben, there are several pair of value for 
            # changing the key value of a table entry
            my @keystrs = ();
            while ($taben[$index]) {
                # Make a key word string to avoid that changing 
                # one table record multiple times
                my $keystr;
                foreach my $key (sort(keys %{$taben[$index]})) {
                    $keystr .= "$key:$taben[$index]{$key}:";
                }
                if (grep /^$keystr$/, @keystrs) {
                    $index += 2;
                    next;
                }
                push @keystrs, $keystr;

                my %chname = ($taben[$index+1] => $::opt_n);
                $tab->setAttribs($taben[$index], \%chname);
                $index += 2;
            }
        }

        my $rsp;
        push @{$rsp->{data}}, "Changed the object name from $::clobjnames[0] to $::opt_n.";
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        
        return 0;
    }

    if ($::opt_f)
    {

        # error
        my $rsp;
        $rsp->{data}->[0] =
          "The \'-f\' option is not valid for the chdef command.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        &defch_usage;
        return 1;
    }

    if ($::opt_t && ($::opt_a || $::opt_z || $::opt_x))
    {
        my $rsp;
        $rsp->{data}->[0] =
          "Cannot combine \'-t\' and \'-a\', \'-z\', or \'-x\' options.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        &defch_usage;
        return 1;
    }

    # can't have -z with other obj sources
    if ($::opt_z && ($::opt_o || @::noderange))
    {
        my $rsp;
        $rsp->{data}->[0] = "Cannot use \'-z\' with \'-o\' or a noderange.";
        $rsp->{data}->[1] = "Example of -z usage:\n\t\'cat stanzafile | chdef -z\'";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        &defch_usage;
        return 1;
    }
    
    if ($::opt_t eq "osimage" && $::opt_setattr && ($::opt_p || $::opt_m)) {
        my $rsp;
        $rsp->{data}->[0] = "Cannot use \'-u\' with \'-p\' or \'-m\'.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }

    # check to make sure we have a list of objects to work with
    if (!@::allobjnames)
    {
        my $rsp;
        $rsp->{data}->[0] = "No object names were provided.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        &defch_usage;
        return 1;
    }

    # set $objtype & fill in cmd line hash
    if (%::ATTRS || ($::opt_t eq "group"))
    {

        # if attr=val on cmd line then could only have one type
        $::objtype = @::clobjtypes[0];

        #
        #  set cli attrs for each object definition
        #
        foreach my $objname (@::clobjnames)
        {

            #  set the objtype attr - if provided
            if ($::objtype)
            {
                chomp $::objtype;
                $::CLIATTRS{$objname}{objtype} = $::objtype;
            }

            # get the data type definition from Schema.pm
            my $datatype = $xCAT::Schema::defspec{$::objtype};
            my %list;
            foreach my $this_attr (sort @{$datatype->{'attrs'}})
            {
                my $a = $this_attr->{attr_name};
                $list{$a} = 1;
            }

            # set the attrs from the attr=val pairs
            foreach my $attr (keys %::ATTRS)
            {
                my $attrorig = $attr;
                # nicips.eth0 => nicips
                if ($attr =~ /^(nic\w+)\..*$/)
                {
                    $attr = $1;
                }
                if (!defined($list{$attr}) && ($::objtype ne 'site') && ($::objtype ne 'monitoring'))
                {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "\'$attr\' is not a valid attribute name for an object type of \'$::objtype\'.";
                    $rsp->{data}->[1] = "Skipping to the next attribute.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    $error = 1;
                    next;
                }
                else
                {
                    $::CLIATTRS{$objname}{$attrorig} = $::ATTRS{$attrorig};
                }
            }
        }
    }

    #
    #   Pull all the pieces together for the final hash
    #        - combines the command line attrs and input file attrs if provided
    #
    if (&setFINALattrs != 0)
    {
        $error = 1;
    }

    # we need a list of objects that are
    #   already defined for each type.
    foreach my $t (@::finalTypeList)
    {

        # special case for site table !!!!!!!!!!!!!!!!!!!!
        if ($t eq 'site')
        {
            @{$objTypeLists{$t}} = 'clustersite';
        }
        else
        {
            @{$objTypeLists{$t}} = xCAT::DBobjUtils->getObjectsOfType($t);
        }
        if ($::verbose)
        {
            my $rsp;
            $rsp->{data}->[0] = "\ndefch: list objects that are defined for each type";
            $rsp->{data}->[1] = "@{$objTypeLists{$t}}";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
        }
    }
    # Build up a hash for the array in objTypeLists
    # for performance consideration, grep the array is not effective
    my %objTypeListsHash;
    foreach my $objk (keys %objTypeLists)
    {
        foreach my $obj (@{$objTypeLists{$objk}}) {
            $objTypeListsHash{$objk}{$obj} = 1;
        }
    }

    foreach my $obj (keys %::FINALATTRS)
    {

        my $isDefined = 0;
        my $type      = $::FINALATTRS{$obj}{objtype};
        my %attrhash;
        my @img_attrs = qw(imagetype provmethod profile osname osvers osarch);
        if ($::opt_setattr && $type eq "osimage") {
            my %tmp_objhash = ();
            %attrhash = xCAT::DBobjUtils->getobjdefs({$obj=>$type}, $::VERBOSE, \@img_attrs);
        }
        # check to make sure we have type
        if (!$type)
        {
            my $rsp;
            $rsp->{data}->[0] = "No type was provided for object \'$obj\'.";
            $rsp->{data}->[1] = "Skipping to the next object.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            $error = 1;
            next;
        }

        if (defined($objTypeListsHash{$type}{$obj}) && ($objTypeListsHash{$type}{$obj} == 1))
        {
            $isDefined = 1;
        }

        if (!$isDefined)
        {
            $newobjects{$obj} = $type;
            if (! grep (/^groups$/, keys %{$::FINALATTRS{$obj}}) ) {
                $::FINALATTRS{$obj}{'groups'} = "all";
            }
        }

        if (!$isDefined && $::opt_m)
        {

            #error - cannot remove items from an object that does not exist.
            my $rsp;
            $rsp->{data}->[0] =
              "The \'-m\' option is not valid since the \'$obj\' definition does not exist.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            $error = 1;
            next;
        }

        #
        # need to handle group definitions - special!
        #    - may need to update the node definitions for the group members
        #
        if ($type eq 'group')
        {
            my %grphash;
            my @memberlist;

            # what kind of group is this? - static or dynamic
            my $grptype;
            my %objhash;
            if ($::opt_d)
            {
               # For dynamic node group,
               # can not assign attributes for inherit
               # only the 'objtype' in %::FINALATTRS
               if (scalar(keys %{$::FINALATTRS{$obj}}) > 1)
               {
                   my $rsp;
                   $rsp->{data}->[0] = "Can not assign attributes to dynamic node group \'$obj\'.";
                   xCAT::MsgUtils->message("E", $rsp, $::callback);
                   $error = 1;
                   delete($::FINALATTRS{$obj});
                   next;
               }
            }
            if ($isDefined)
            {
                $objhash{$obj} = $type;
                my @finalattrs = keys %{$::FINALATTRS{$obj}};
                push @finalattrs, 'grouptype';
                %grphash = xCAT::DBobjUtils->getobjdefs(\%objhash, 0, \@finalattrs);
                if (!(%grphash))
                {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "Could not get xCAT object definitions.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    return 1;

                }
                $grptype = $grphash{$obj}{grouptype};
                if (($grptype eq "dynamic") && (scalar(keys %{$::FINALATTRS{$obj}}) > 1))
                {
                    my $rsp;
                   $rsp->{data}->[0] = "Can not assign attributes to dynamic node group \'$obj\'.";
                   xCAT::MsgUtils->message("E", $rsp, $::callback);
                   $error = 1; 
                   delete($::FINALATTRS{$obj});
                   next;
                }
                # for now all groups are static
                #$grptype = 'static';
            }
            else
            {    #not defined
                if ($::FINALATTRS{$obj}{grouptype})
                {
                    $grptype = $::FINALATTRS{$obj}{grouptype};
                }
                elsif ($::opt_d)
                {
                    $grptype = 'dynamic';
                }
                else
                {
                    $grptype = 'static';
                }
            }

            # make sure wherevals was set - if info provided
            if (!$::FINALATTRS{$obj}{wherevals})
            {
                if ($::opt_w)
                {
                    $::FINALATTRS{$obj}{wherevals} = join ('::', @{$::opt_w});
                    #$::FINALATTRS{$obj}{wherevals} = $::opt_w;
                }
            }

            #  get the @memberlist for static group
            #    - if provided - to use below
            #  if the static group is not defined in the nodegroup table
            #  the grptype will be undef
            if(!$grptype || ($grptype eq 'static'))
            {

                # check for bad cmd line options
                if ($::opt_w && $::FINALATTRS{$obj}{members})
                {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "Cannot use a list of members together with the \'-w\' option.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    $error = 1;
                    next;
                }

                if ($::FINALATTRS{$obj}{members})
                {
                    @memberlist = &noderange($::FINALATTRS{$obj}{members}, 0);
                    #  don't list all the nodes in the group table
                    #   set the value to static and we figure out the list
                    #   by looking in the nodelist table
                    $::FINALATTRS{$obj}{members} = 'static';

                }
                elsif ($::FINALATTRS{$obj}{wherevals})
                {
                    $::FINALATTRS{$obj}{members} = 'static';

                    #  get a list of nodes whose attr values match the
                    #   "where" values and make that the memberlist of
                    #   the group.

                    # get a list of all node nodes
                    my @tmplist = xCAT::DBobjUtils->getObjectsOfType('node');

                    # create a hash of obj names and types
                    my %objhash;
                    foreach my $n (@tmplist)
                    {
                        $objhash{$n} = 'node';
                    }

                    # get a list of attr=val pairs, is it really necessary??
                    my @wherevals = split(/::/, $::FINALATTRS{$obj}{wherevals});
                    my $rc = xCAT::Utils->parse_selection_string(\@wherevals, \%::WhereHash);
                    if ($rc != 0)
                    {
                         my $rsp;
                         $rsp->{data}->[0] = "Incorrect selection string";
                         xCAT::MsgUtils->message("E", $rsp, $::callback);
                         return 3;
                    }

                    # get the attrs for these nodes
                    my @whereattrs = keys %::WhereHash;
                    my %myhash = xCAT::DBobjUtils->getobjdefs(\%objhash, 0, \@whereattrs);

                    # see which ones match the where values
                    foreach my $objname (keys %myhash)
                    {

                        if (xCAT::Utils->selection_string_match(\%myhash, $objname, \%::WhereHash)) {
                            push(@memberlist, $objname);
                        }

                    }

                }

            }    # end - get memberlist for static group

            # chdef -t group should not create new nodes
            my @tmpmemlist = ();
            my @allnodes = xCAT::DBobjUtils->getObjectsOfType('node');
            foreach my $tmpnode (@memberlist)
            {
                if (!grep(/^$tmpnode$/, @allnodes))
                {
                    my $rsp;
                    $rsp->{data}->[0] = "Could not find a node named \'$tmpnode\', skipping to the next node.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                }
                else
                {
                    push @tmpmemlist, $tmpnode;
                }
            }
            @memberlist = @tmpmemlist;

            if (!$isDefined)
            {

                # if the group type was not set then set it
                if (!$::FINALATTRS{$obj}{grouptype})
                {
                    if ($::opt_d)
                    {
                        $::FINALATTRS{$obj}{grouptype} = 'dynamic';
                        $::FINALATTRS{$obj}{members}   = 'dynamic';
                        if (!$::FINALATTRS{$obj}{wherevals})
                        {
                            my $rsp;
                            $rsp->{data}->[0] =
                              "The \'where\' attributes and values were not provided for dynamic group \'$obj\'.";
                            $rsp->{data}->[1] = "Skipping to the next group.";
                            xCAT::MsgUtils->message("E", $rsp, $::callback);
                            $error = 1;
                            next;
                        }
                    }
                    else
                    {
                        $::FINALATTRS{$obj}{grouptype} = 'static';
                    }
                }

                # if this is a static group
                #    then update the "groups" attr of each member node
                if ($::FINALATTRS{$obj}{grouptype} eq 'static')
                {

                    # for each node in memberlist add this group
                    # name to the groups attr of the node
                    my %membhash;
                    foreach my $n (@memberlist)
                    {

                        $membhash{$n}{groups} = $obj;
                        $membhash{$n}{objtype} = 'node';
                    }
                    $::plus_option  = 1;
                    $::minus_option = 0;
                    if (xCAT::DBobjUtils->setobjdefs(\%membhash) != 0)
                    {
                        $error = 1;
                    }
                    $::plus_option = 0;

                }

            }
            else
            {    # group is defined

                # if a list of members is provided then update the node entries
                #   note: the members attr of the group def will be set
                #    to static
                if (@memberlist)
                {

                    #  options supported
                    if ($::opt_m)
                    {    # removing these members

                        # for each node in memberlist - remove this group
                        #  from the groups attr
                        my %membhash;
                        foreach my $n (@memberlist)
                        {
                            $membhash{$n}{groups}  = $obj;
                            $membhash{$n}{objtype} = 'node';
                        }

                        $::plus_option  = 0;
                        $::minus_option = 1;
                        if (xCAT::DBobjUtils->setobjdefs(\%membhash) != 0)
                        {
                            $error = 1;
                        }
                        $::minus_option = 0;

                    }
                    elsif ($::opt_p)
                    {    #adding these new members
                            # for each node in memberlist add this group
                            # name to the groups attr
                        my %membhash;
                        foreach my $n (@memberlist)
                        {
                            $membhash{$n}{groups}  = $obj;
                            $membhash{$n}{objtype} = 'node';
                        }
                        $::plus_option  = 1;
                        $::minus_option = 0;
                        if (xCAT::DBobjUtils->setobjdefs(\%membhash) != 0)
                        {
                            $error = 1;
                        }
                        $::plus_option = 0;

                    }
                    else
                    {    # replace the members list altogether

                        # this is the default for the chdef command
                if ($firsttime) {
                        # get the current members list

                        $grphash{$obj}{'grouptype'} = "static";
                        my $list =
                          xCAT::DBobjUtils->getGroupMembers($obj, \%grphash);
                        my @currentlist = split(',', $list);

                        # for each node in currentlist - remove group name
                        #    from groups attr

                        my %membhash;
                        foreach my $n (@currentlist)
                        {
                            $membhash{$n}{groups}  = $obj;
                            $membhash{$n}{objtype} = 'node';
                        }

                        $::plus_option  = 0;
                        $::minus_option = 1;


                        if (xCAT::DBobjUtils->setobjdefs(\%membhash) != 0)
                        {
                            $error = 1;
                        }
                    $firsttime=0;
                } # end - first time
                        $::minus_option = 0;

                        # for each node in memberlist add this group
                        # name to the groups attr

                        my %membhash;
                        foreach my $n (@memberlist)
                        {
                            $membhash{$n}{groups}  = $obj;
                            $membhash{$n}{objtype} = 'node';
                        }
                        $::plus_option  = 1;
                        $::minus_option = 0;


                        if (xCAT::DBobjUtils->setobjdefs(\%membhash) != 0)
                        {
                            $error = 1;
                        }
                        $::plus_option = 0;

                    }

                }    # end - if memberlist

            }    # end - if group is defined

        }    # end - if group type
        if ($type eq 'osimage' && !$::opt_m && !$::opt_p && $::opt_setattr && exists($attrhash{$obj})) {
            foreach my $tmp_attr (@img_attrs) {
                if (!exists($::FINALATTRS{$obj}{$tmp_attr}) && exists($attrhash{$obj}{$tmp_attr}) &&
                                                                 defined($attrhash{$obj}{$tmp_attr})) {
                    $::FINALATTRS{$obj}{$tmp_attr} = $attrhash{$obj}{$tmp_attr};
                }
            }
            my $rc = &parse_attr_for_osimage($::command, $::FINALATTRS{$obj});

            if ($rc) {
                next;
            }
        }

        # Removed the code to handle the nodegroup table with chdef -t node groups=xxx
        # Only dynamic groups should be in nodegroup table
        # Do not try to add static group into the nodegroup table
        # performance!!!!

        #special case for osimage, if the osimage was not defined,
        #chdef can not create it correctly if no attribute in osimage table is defined
        #set the default imagetype 'NIM' if it is not specified
        if ((!$isDefined) && ($type eq 'osimage') && (!defined($::FINALATTRS{$obj}{imagetype})))
        {
            $::FINALATTRS{$obj}{imagetype} = 'NIM';
        }

    }    # end - for each object to update

    #
    #  write each object into the tables in the xCAT database
    #

    # set update option
    $::plus_option  = 0;
    $::minus_option = 0;
    if ($::opt_p)
    {
        $::plus_option = 1;
    }
    elsif ($::opt_m)
    {
        $::minus_option = 1;
    }

    if (xCAT::DBobjUtils->setobjdefs(\%::FINALATTRS) != 0)
    {
        my $rsp;
        $rsp->{data}->[0] = "Could not write data to the xCAT database.";

        #        xCAT::MsgUtils->message("E", $rsp, $::callback);
        $error = 1;
    }
    
    if ($error)
    {
        my $rsp;
        $rsp->{data}->[0] =
          "One or more errors occured when attempting to create or modify xCAT \nobject definitions.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    else
    {
        if ($::verbose)
        {

            #  give results
            my $rsp;
            my $nodenum = scalar(keys %::FINALATTRS);
            if ($nodenum) {
                $rsp->{data}->[0] =
                  "The database was updated for the following objects:";
                xCAT::MsgUtils->message("I", $rsp, $::callback);

                my $n = 1;
                foreach my $o (sort(keys %::FINALATTRS))
                {
                    $rsp->{data}->[$n] = "$o\n";
                    $n++;
                }
            } else {
                $rsp->{data}->[0] = 
                "No database was updated";
            }
            xCAT::MsgUtils->message("I", $rsp, $::callback);
        }
        else
        {
            my $rsp;
            my $nodenum = scalar(keys %::FINALATTRS);
            if ($nodenum) {
                $rsp->{data}->[0] =
                  "$nodenum object definitions have been created or modified.";
            } else {
               $rsp->{data}->[0] =
                  "No object definitions have been created or modified.";
            }
            xCAT::MsgUtils->message("I", $rsp, $::callback);
            if (scalar(keys %newobjects) > 0)
            {
                my $newobj = ();
                my $invalidnodename = ();
                foreach my $node (keys %newobjects) {
                    if (($node =~ /[A-Z]/) && ((!$::opt_t) || ($::opt_t eq "node"))) {
                        $invalidnodename .= ",$node";
                    }
                    $newobj .= ",$node";
                }

                if ($newobj) {
                    $newobj =~ s/,//;
                    my $rsp;
                    $rsp->{data}->[0] = "New object definitions \'$newobj\' have been created.";
                    xCAT::MsgUtils->message("I", $rsp, $::callback);
                }
                if ($invalidnodename) {
                    $invalidnodename =~ s/,//;
                    my $rsp;
                    $rsp->{data}->[0] = "The node name \'$invalidnodename\' contains capital letters which may not be resolved correctly by the dns server.";
                    xCAT::MsgUtils->message("W", $rsp, $::callback);
                }
   
            }
        }  
        return 0;
    }
}

#----------------------------------------------------------------------------

=head3   setFINALattrs

        create %::FINALATTRS{objname}{attr}=val hash
        conbines %::FILEATTRS, and %::CLIATTR

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
sub setFINALattrs
{

    my $error = 0;

    # set the final hash based on the info from the file hash and cmd line hash
    @::finalTypeList = ();

    # set the final hash based on the info from the input file
    if (@::fileobjnames)
    {
        foreach my $objname (@::fileobjnames)
        {

            #  check if this object is one of the type specified
            if (@::clobtypes)
            {
                if (!grep(/^$::FILEATTRS{$objname}{objtype}$/, @::clobtypes))
                {
                    next;
                }

            }

            # get the data type definition from Schema.pm

            if (!$::FILEATTRS{$objname}{objtype}) {
                my $rsp;
                $rsp->{data}->[0] = "\nNo objtype value was specified for \'$objname\'. Cannot create object definition.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                $error = 1;
                next;
            }

            # special case for the nic* attributes
            # merge nic*.eth0, nic*.eth1
            if (($::FILEATTRS{$objname}{objtype} eq 'node') || ($::FILEATTRS{$objname}{objtype} eq 'group'))
            {
                xCAT::DBobjUtils->collapsenicsattr($::FILEATTRS{$objname}, $objname);
            }

            my $datatype =
              $xCAT::Schema::defspec{$::FILEATTRS{$objname}{objtype}};
            my @list;
            foreach my $this_attr (sort @{$datatype->{'attrs'}})
            {
                my $a = $this_attr->{attr_name};
                push(@list, $a);
            }
            push(@list, "objtype");

            # if so then add it to the final hash
            foreach my $attr (keys %{$::FILEATTRS{$objname}})
            {

                # see if valid attr
                if (!grep(/^$attr$/, @list) && ($::FILEATTRS{$objname}{objtype} ne 'site') && ($::FILEATTRS{$objname}{objtype} ne 'monitoring'))
                {

                    my $rsp;
                    $rsp->{data}->[0] =
                      "\'$attr\' is not a valid attribute name for an object type of \'$::objtype\'.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    $error = 1;
                    next;
                }
                else
                {
                    $::FINALATTRS{$objname}{$attr} =
                      $::FILEATTRS{$objname}{$attr};
                    if ($attr eq 'objtype')
                    {
                        if (!grep(/^$::FINALATTRS{$objname}{objtype}$/, @::finalTypeList))
                        {
                            my $type = $::FINALATTRS{$objname}{objtype};
                            chomp $type;
                            push @::finalTypeList, $type;
                        }
                    }
                }

            }
            # need to make sure the node attr is set otherwise nothing 
            #    gets set in the nodelist table
            if ($::FINALATTRS{$objname}{objtype} eq "node") {
                $::FINALATTRS{$objname}{node} = $objname;
            }
        }
    }

    foreach my $objname (@::clobjnames)
    {
        # special case for the nic* attributes
        # merge nic*.eth0, nic*.eth1
        unless(exists($::CLIATTRS{$objname})) {
            next;
        }
        if (($::CLIATTRS{$objname}{objtype} eq 'node') || ($::CLIATTRS{$objname}{objtype} eq 'group'))
        {
            # Even if only the nicips.eth0 is specified with CLI,
            # need to read the whole nicips attribute from the nics table,
            # then merge the nicips.eth0 into the nicips attribute,
            my %tmphash = ();
            foreach my $nodeattr (keys %{$::CLIATTRS{$objname}})
            {
                if ($nodeattr =~ /^(nic\w+)\..*$/)
                {
                    my $tmpnicattr = $1;
                    if (!defined($tmphash{$tmpnicattr}))
                    {
                        my $nicstable = xCAT::Table->new("nics", -create => 1, -autocommit => 0);
                        if (!$nicstable) {
                            my $rsp;
                            $rsp->{data}->[0] = "Could not open the \'nics\' table.";
                            xCAT::MsgUtils->message("E", $rsp, $::callback);
                            return 1;
                        } 
                        my $nichash = $nicstable->getNodeAttribs($objname, [$tmpnicattr]);
                        if ($nichash && $nichash->{$tmpnicattr})
                        {
                            $tmphash{$tmpnicattr} = $nichash->{$tmpnicattr};
                        }
                        $nicstable->close();
                    }
                }
            }
            # $tmphash{nicips} = "eth0!1.1.1.1|1.2.1.1,eth1!2.1.1.1|2.2.1.1"
            foreach my $nicattr (keys %tmphash)
            {
                # eth0!1.1.1.1|1.2.1.1,eth1!2.1.1.1|2.2.1.1
                my $nicval = $tmphash{$nicattr};
                my @nicarray = split(/,/, $nicval);
                foreach my $nicv (@nicarray)
                {
                    my @nica = split(/!/, $nicv);

                    # put the additional nicips.eth1, nicips.eth2 into %::CLIATTRS
                    if (!defined $::CLIATTRS{$objname}{"$nicattr.$nica[0]"})
                    {
                        $::CLIATTRS{$objname}{"$nicattr.$nica[0]"} = $nica[1];
                    }
                }
            }

            xCAT::DBobjUtils->collapsenicsattr($::CLIATTRS{$objname}, $objname);
        }

        foreach my $attr (keys %{$::CLIATTRS{$objname}})
        {

            $::FINALATTRS{$objname}{$attr} = $::CLIATTRS{$objname}{$attr};
            if ($attr eq 'objtype')
            {
                if (
                    !grep(/^$::FINALATTRS{$objname}{objtype}$/, @::finalTypeList)
                  )
                {
                    my $type = $::FINALATTRS{$objname}{objtype};
                    chomp $type;
                    push @::finalTypeList, $type;
                }

            }

        }
        # need to make sure the node attr is set otherwise nothing 
        #   gets set in the nodelist table
        if ($::FINALATTRS{$objname}{objtype} eq "node") {
            $::FINALATTRS{$objname}{node} = $objname;
        }
    }

    if ($error)
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

#----------------------------------------------------------------------------

=head3   defls

        Support for the xCAT defls command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
            Object names derived from -o, -t, w, -a or noderange!
            List of attrs to display is given by -i.
            Output goes to standard out or a stanza/xml file (-z or -x)

=cut

#-----------------------------------------------------------------------------

sub defls
{
    my $long = 0;
    my %myhash;
    my %objhash;

    my @objectlist;
    @::allobjnames;
    my @displayObjList;

    my $numtypes = 0;
    my $rsp_info;

    # process the command line
    my $rc = &processArgs;

    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - return, 2 - help, 3 - error
        # 0 - continue
        # 1 - return  (like for version option)
        # 2 - return with usage
        # 3 - return error
        if ($rc == 1) {
            return 0;
        } elsif ($rc == 2) {
            &defls_usage;
            return 0;
        } elsif ($rc == 3) {
            return 1;
        }
    }


    # do we want just the object names or all the attr=val
    if ($::opt_l || @::noderange || $::opt_o || $::opt_i)
    {

        # assume we want the the details - not just the names
        #     - if provided object names or noderange
        $long++;

    }
    if ($::opt_s) {
        $long = 0;
    }
    
    # which attrs do we want?
    # this is a temp hack to help scaling when you only 
    #   want a list of nodes - needs to be fully implemented
    if ($::opt_l || $::opt_w) {
        # if long or -w then get all the attrs
        $::ATTRLIST="all";
    } elsif ($::opt_i) {
        # is -i then just get the ones in the list
        $::ATTRLIST=$::opt_i;
    } elsif ( @::noderange || $::opt_o) {
        # if they gave a list of objects then they must want more
        # than the object names!
        if ($::opt_s) {
            $::ATTRLIST="none";
        } else {
            $::ATTRLIST="all";
        }
    } else {
        # otherwise just get a list of object names
        $::ATTRLIST="none";
    }

    #
    #    put together a hash with the list of objects and the associated types
    #          - need to figure out which objects to look up
    #

    # if a set of objects was provided on the cmd line then there can
    #    be only one type value

    # Figure out the attributes that needed in the def operation
    my @neededattrs = ();
    if ($::opt_i) {
        @neededattrs = (@neededattrs, @::AttrList);
        if ($::opt_w) {
            my @whereattrs = keys %::WhereHash;
            @neededattrs = (@neededattrs, @whereattrs);
        }
    }
    
    if ($::objectsfrom_opto || $::objectsfrom_nr || $::objectsfrom_args)
    {
        my $type = @::clobjtypes[0];

        $numtypes = 1;

        foreach my $obj (sort @::clobjnames)
        {
            $objhash{$obj} = $type;

        }

        %myhash = xCAT::DBobjUtils->getobjdefs(\%objhash, $::VERBOSE, \@neededattrs);
        if (!(%myhash))
        {
            my $rsp;
            $rsp->{data}->[0] = "Could not get xCAT object definitions.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 1;

        }

    }

    #  if just provided type list then find all objects of these types
    if ($::objectsfrom_optt)
    {
        %objhash = %::ObjTypeHash;

        %myhash = xCAT::DBobjUtils->getobjdefs(\%objhash, $::VERBOSE, \@neededattrs);
        if (!(%myhash))
        {
            my $rsp;
            $rsp->{data}->[0] = "Could not get xCAT object definitions.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            return 1;
        }
    }

    # if specify all
    if ($::opt_a)
    {

        # could be modified by type
        if ($::opt_t)
        {

            # get all objects matching type list
            # Get all object in this type list
            foreach my $t (@::clobjtypes)
            {
                my @tmplist = xCAT::DBobjUtils->getObjectsOfType($t);

                if (scalar(@tmplist) > 1)
                {
                    foreach my $obj (@tmplist)
                    {

                        $objhash{$obj} = $t;
                    }
                }
                else
                {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "Could not get objects of type \'$t\'.";
                    xCAT::MsgUtils->message("I", $rsp, $::callback);
                }
            }

            %myhash = xCAT::DBobjUtils->getobjdefs(\%objhash);
            if (!(%myhash))
            {
                my $rsp;
                $rsp->{data}->[0] = "Could not get xCAT object definitions.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }

        }
        else
        {

            %myhash = xCAT::DBobjUtils->getobjdefs(\%::AllObjTypeHash, $::VERBOSE);
            if (!(%myhash))
            {
                my $rsp;
                $rsp->{data}->[0] = "Could not get xCAT object definitions.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            }

        }
        foreach my $t (keys %{xCAT::Schema::defspec})
        {
            push(@::clobjtypes, $t);
        }
    } # end - if specify all

    if (!(%myhash))
    {
        my $rsp;
        $rsp->{data}->[0] = "Could not find any objects to display.";
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        return 0;
    }


    # need a special case for the node postscripts attribute,
    # The 'xcatdefaults' postscript should be added to the postscripts and postbootscripts attribute
    my $getnodes = 0;
    if (!$::opt_z) { #if -z flag is specified, do not add the xcatdefaults
        foreach my $objtype (@::clobjtypes)
        {
            if ($objtype eq 'node')
            {
                $getnodes = 1;
                last;
            }
        }
    }
    my %nodeosimagehash = ();
    if ($getnodes)
    {
        # Show osimage information
        if($::opt_osimg)
        {
            my %nodeosimgname;
            my %imghash;
            my %imglist;
            my %tmpprofilelist;

            # get the site.installdir for osimage searching with nodes prvomethod= install/netboot/statelite
            # it might not be used at all, but should not do this for each node
            my $installroot = "/install";
            my @ents = xCAT::TableUtils->get_site_attribute("installdir");
            my $site_ent = $ents[0];
            if ( defined($site_ent) )
            {
                $installroot = $site_ent;
            }

            foreach my $obj (keys %myhash)
            {
                if ($myhash{$obj}{'objtype'} eq 'node')
                {
                    my $osimagename;
                    #provmethod can be set to osimage name
                    if($myhash{$obj}{'provmethod'} && ($myhash{$obj}{'provmethod'} ne 'install')
                      && ($myhash{$obj}{'provmethod'} ne 'netboot') && ($myhash{$obj}{'provmethod'} ne 'statelite')) 
                    {
                        $osimagename = $myhash{$obj}{'provmethod'};
                    }
                    else
                    {
                        # prvomethod = install/netboot/statelite,
                        # search /opt/xcat/share/xcat/<provmethod/<platform> 
                        # and /install/custom/<provmethod/<platform>
                        my $profile = $myhash{$obj}{'profile'};
                        my $os = $myhash{$obj}{'os'};
                        my $arch = $myhash{$obj}{'arch'};
                        my $provmethod = $myhash{$obj}{'provmethod'};

                        # tmp hash for performance considerations,
                        # do not search paths for each node.
                        if (defined($tmpprofilelist{$os}{$arch}{$provmethod}{$profile}))
                        {
                            $nodeosimagehash{$obj}{'template'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'template'};
                            $nodeosimagehash{$obj}{'pkglist'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'pkglist'};
                            $nodeosimagehash{$obj}{'otherpkglist'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'otherpkglist'};
                            $nodeosimagehash{$obj}{'postinstall'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'postinstall'};
                            $nodeosimagehash{$obj}{'extlist'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'extlist'};
                            $nodeosimagehash{$obj}{'synclists'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'synclists'};
                            $nodeosimagehash{$obj}{'pkgdir'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'pkgdir'};
                            $nodeosimagehash{$obj}{'otherpkgdir'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'otherpkgdir'};
                            $nodeosimagehash{$obj}{'rootimgdir'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'rootimgdir'};
                            $nodeosimagehash{$obj}{'osvers'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'osvers'};
                            $nodeosimagehash{$obj}{'osarch'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'osarch'};
                            $nodeosimagehash{$obj}{'imagetype'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'imagetype'};
                            $nodeosimagehash{$obj}{'osname'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'osname'};
                            $nodeosimagehash{$obj}{'profile'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'profile'};
                            $nodeosimagehash{$obj}{'provmethod'} = $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'provmethod'};
                            next;
                        }
                        if ($myhash{$obj}{'os'} && $myhash{$obj}{'arch'} 
                           && $myhash{$obj}{'provmethod'} && $myhash{$obj}{'profile'})
                        {
                            #$osimagename = "$myhash{$obj}{'os'}-$myhash{$obj}{'arch'}-$myhash{$obj}{'provmethod'}-$myhash{$obj}{'profile'}";
                            my $platform = xCAT::SvrUtils->getplatform($myhash{$obj}{'os'});
                            my $pm = $myhash{$obj}{'provmethod'};
                            if ($pm eq 'statelite') { $pm = 'netboot'; }
                            my $custpath = "$installroot/custom/$pm/$platform";
                            my $defpath = "$::XCATROOT/share/xcat/$pm/$platform";

                            $nodeosimagehash{$obj}{'osvers'} = $os;
                            $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'osvers'} = $os;
                            $nodeosimagehash{$obj}{'osarch'} = $arch;
                            $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'osarch'} = $arch;
                            $nodeosimagehash{$obj}{'imagetype'} = "linux";
                            $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'imagetype'} = "linux";
                            $nodeosimagehash{$obj}{'osname'} = "Linux";
                            $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'osname'} = "Linux";
                            $nodeosimagehash{$obj}{'profile'} = $profile;
                            $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'profile'} = $profile;
                            $nodeosimagehash{$obj}{'provmethod'} = $provmethod;
                            $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'provmethod'} = $provmethod;
                                
                            # pkgdir both diskful and diskless
			                $nodeosimagehash{$obj}{'pkgdir'} = "$installroot/$os/$arch";
			                $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'pkgdir'} = "$installroot/$os/$arch";
                            # rootimgdir only for diskless
			                if (($provmethod eq 'netboot') || ($provmethod eq 'statelite'))
			                {
			                   $nodeosimagehash{$obj}{'rootimgdir'} = "$installroot/netboot/$os/$arch/$profile";
			                   $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'rootimgdir'} = "$installroot/netboot/$os/$arch/$profile";
			                }
                            # otherpkgdir for both diskful and diskless
			                $nodeosimagehash{$obj}{'otherpkgdir'} = "$installroot/post/otherpkgs/$os/$arch";
			                $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'otherpkgdir'} = "$installroot/post/otherpkgs/$os/$arch";

                            # template file only for diskful
			                if ($provmethod eq 'install')
                            {
                                my $tmplfile = xCAT::SvrUtils->get_tmpl_file_name($custpath, $profile, $os, $arch, $os);
                                if (!$tmplfile)
                                {
                                    $tmplfile = xCAT::SvrUtils->get_tmpl_file_name($defpath, $profile, $os, $arch, $os);
                                }
                                if ($tmplfile)
                                {
                                    $nodeosimagehash{$obj}{'template'} = $tmplfile;
                                    $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'template'} = $tmplfile;
                                }
                            }
                            # pkglist for both diskful and diskless
                            my $pkglistfile = xCAT::SvrUtils->get_pkglist_file_name($custpath, $profile, $os, $arch, $os);
                            if (!$pkglistfile)
                            {
                                $pkglistfile = xCAT::SvrUtils->get_pkglist_file_name($defpath, $profile, $os, $arch, $os);
                            }
                            if ($pkglistfile)
                            {
                                $nodeosimagehash{$obj}{'pkglist'} = $pkglistfile;
                                $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'pkglist'} = $pkglistfile;
                            }
                            #otherpkglist for both diskful and diskless
                            my $otherpkgsfile = xCAT::SvrUtils->get_otherpkgs_pkglist_file_name($custpath, $profile, $os, $arch);
                            if (!$otherpkgsfile)
                            {
                                $otherpkgsfile = xCAT::SvrUtils->get_otherpkgs_pkglist_file_name($defpath, $profile, $os, $arch);
                            }
                            if ($otherpkgsfile)
                            {
                                $nodeosimagehash{$obj}{'otherpkglist'} = $otherpkgsfile;
                                $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'otherpkglist'} = $otherpkgsfile;
                            }
                            # postinstall and exlist only for diskless
			                if (($provmethod eq 'netboot') || ($provmethod eq 'statelite'))
                            {
                                # Get postinstall file
                                my $postfile = xCAT::SvrUtils->get_postinstall_file_name($custpath, $profile, $os, $arch);
                                if (!$postfile)
                                {
                                    $postfile = xCAT::SvrUtils->get_postinstall_file_name($defpath, $profile, $os, $arch);
                                }
                                if ($postfile)
                                {
                                    $nodeosimagehash{$obj}{'postinstall'} = $postfile;
                                    $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'postinstall'} = $postfile;
                                }
                                # Get exclude list
                                my $extfile = xCAT::SvrUtils->get_exlist_file_name($custpath, $profile, $os, $arch);
                                if (!$extfile)
                                {
                                    $extfile = xCAT::SvrUtils->get_exlist_file_name($defpath, $profile, $os, $arch);
                                }
                                if ($extfile)
                                {
                                    $nodeosimagehash{$obj}{'extlist'} = $extfile;
                                    $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'extlist'} = $extfile;
                                }
                            }
                            # Get synclist
                            my $synclist = xCAT::SvrUtils->getsynclistfile(undef, $os, $arch, $profile, $provmethod);
                            if ($synclist)
                            {
                                $nodeosimagehash{$obj}{'synclists'} = $synclist;
                                $tmpprofilelist{$os}{$arch}{$provmethod}{$profile}{'synclists'} = $synclist;
                            }
                        }
                        else
                        {
                            my $rsp;
                            $rsp->{data}->[0] =
                            "Missing attributes for node $obj, check the node attributes \'os\', \'arch\',\'profile\' and \'provmethod\'.";
                            xCAT::MsgUtils->message("E", $rsp, $::callback);
                            next;
                        }
                    }
                    # do not call xCAT::DBobjUtils->getobjdefs for each object
                    # for performance consideration
                    if($osimagename)
                    {
                        if(!defined($imglist{$osimagename}))
                        {
                            $imglist{$osimagename} = 'osimage';
                        }
                        $nodeosimgname{$obj} = $osimagename;
                    }
                }
            }

            # Get osimage definition info in one invocation
            if(scalar(keys %imglist) > 0)
            {
                my @attrs = ();
                %imghash = xCAT::DBobjUtils->getobjdefs(\%imglist, 0, \@attrs);
            }

            # Put the osimage definition in %nodeosimagehash
            foreach my $obj (keys %myhash)
            {    
                if ($myhash{$obj}{'objtype'} eq 'node')
                {
                    my $imgname = $nodeosimgname{$obj};
                    if($imgname && defined($imghash{$imgname}))
                    {
                        my %imgentry = %{$imghash{$imgname}};
                        foreach my $imgattr (keys %imgentry)
                        {
                            # Only store the attributes that are not in general node attributes
                            # This is not the right thing to do, list all the osimage attributes instead,
                            # like the postscripts and postbootscripts attributes,
                            #if(!defined($myhash{$obj}{$imgattr}) && defined($imgentry{$imgattr}))
                            #{
                                $nodeosimagehash{$obj}{$imgattr} = $imgentry{$imgattr};
                            #}
                        }
                    }
                    if (scalar(keys %{$nodeosimagehash{$obj}}) == 0)
                    {
                        my $rsp;
                        $rsp->{data}->[0] = "$obj: could not find information for osimage $nodeosimgname{$obj}";
                        xCAT::MsgUtils->message("W", $rsp, $::callback);
                    }
                }
            }
        }
        my $xcatdefaultsps;
        my $xcatdefaultspbs;
        my @TableRowArray = xCAT::DBobjUtils->getDBtable('postscripts');
        if (@TableRowArray)
        {
            foreach my $tablerow (@TableRowArray)
            {
                if(($tablerow->{node} eq 'xcatdefaults') && !($tablerow->{disable}))
                {
                    $xcatdefaultsps = $tablerow->{postscripts};
                    $xcatdefaultspbs = $tablerow->{postbootscripts};
                    last;
                }
             }
         }
         foreach my $obj (keys %myhash)
         {
             if ($myhash{$obj}{objtype} eq 'node')
             {
                 if($xcatdefaultsps)
                 {
                     if ($myhash{$obj}{postscripts})
                     {
                         $myhash{$obj}{postscripts} = $xcatdefaultsps . ',' . $myhash{$obj}{postscripts};
                     }
                     else
                     {
                         $myhash{$obj}{postscripts} = $xcatdefaultsps;
                     }
                     if($::opt_V && ($myhash{$obj}{postscripts} eq $xcatdefaultsps))
                     {
                         $myhash{$obj}{postscripts} .= "     (Table:postscripts - Key:node - Column:postscripts)";
                     }
                 }
                 if($xcatdefaultspbs)
                 {
                     if ($myhash{$obj}{postbootscripts})
                     {
                         $myhash{$obj}{postbootscripts} = $xcatdefaultspbs . ',' . $myhash{$obj}{postbootscripts};
                     }
                     else
                     {
                         $myhash{$obj}{postbootscripts} = $xcatdefaultspbs;
                     }
                     if($::opt_V && ($myhash{$obj}{postbootscripts} eq $xcatdefaultspbs))
                     {
                         $myhash{$obj}{postbootscripts} .= "       (Table:postscripts - Key:node - Column:postbootscripts)";
                     }
                 }
             }
         }
    }
      
    # the list of objects may be limited by the "-w" option
    # see which objects have attr/val that match the where values
    #        - if provided
    if ($::opt_w)
    {
        foreach my $obj (sort (keys %myhash))
        {
            if (xCAT::Utils->selection_string_match(\%myhash, $obj, \%::WhereHash)) {
                push(@displayObjList, $obj);
            }
        }
    }

    #
    # output in specified format
    #

    my @foundobjlist;

    if ($::opt_z)
    {
        push (@{$rsp_info->{data}}, "# <xCAT data object stanza file>");
    }

    # group the objects by type to make the output easier to read
    my $numobjects = 0;    # keep track of how many object we want to display
    # for each type
    foreach my $type (@::clobjtypes)
    {
       # Check if -i specifies valid attributes
       # get the data type definition from Schema.pm
       my %validattrslist;
       if ($::opt_i)
       {
           my $datatype = $xCAT::Schema::defspec{$type};
           foreach my $this_attr (sort @{$datatype->{'attrs'}})
           {
               my $a = $this_attr->{attr_name};
               $validattrslist{$a} = 1;
           }
        }

        my %defhash;

        foreach my $obj (keys %myhash)
        {
            if ($obj)
            {
                $numobjects++;
                if ($myhash{$obj}{'objtype'} eq $type)
                {
                    $defhash{$obj} = $myhash{$obj};

                }
            }
        }

        if ($numobjects == 0)
        {
            my $rsp;
            $rsp->{data}->[0] =
              "Could not find any object definitions to display.";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
            return 0;
        }

        
        if ($type eq "node") {
            my %newhash;
            my $listtab  = xCAT::Table->new( 'nodelist' );
            if (!$listtab) {
                my $rsp;
                $rsp->{data}->[0] =
                 "Could not open nodelist table.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                return 1;
            } 
            
            if (!defined($::opt_S) ) {
                #my $tmp1=$listtab->getAllEntries("all");
                #if (defined($tmp1) && (@$tmp1 > 0)) {
                #    foreach(@$tmp1) {
                #        $newhash{$_->{node}} = 1;
                #    }
                #}                
            
                foreach my $n (keys %defhash) {
                    #if ($newhash{$n} eq 1) {
                        my ($hidhash) = $listtab->getNodeAttribs($n ,['hidden']);
                        if ($hidhash) {
                            if ( $hidhash->{hidden} eq 1)  {  
                                delete $defhash{$n};
                            }
                        }
                    #}
                }
            }
        }            
            
        # Get all the objects of this type
        my @allobjoftype;
        @allobjoftype = xCAT::DBobjUtils->getObjectsOfType($type);

        unless (@allobjoftype)
        {
            my $rsp;
            $rsp->{data}->[0] =
              "Could not find any objects of type \'$type\'.";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
            next;
        }

        my @attrlist;
        if (($type ne 'site') && ($type ne 'monitoring'))
        {
            # -i is specified
            if (scalar(@::AttrList) > 0) {
                foreach my $attr (@::AttrList)
                {
                    # For site and monitoring, does not check if -i attributes are valid
                    if (($type eq 'site') || ($type eq 'monitoring'))
                    {
                        @attrlist = @::AttrList;
                    } else {
                        if (defined($validattrslist{$attr}))
                        {
                            if (!grep(/^$attr$/, @attrlist))
                            {
                                push @attrlist, $attr;
                            }
                        } else {
                            my $rsp;
                            $rsp->{data}->[0] =
                                "\'$attr\' is not a valid attribute name for an object type of \'$type\'.";
                            xCAT::MsgUtils->message("E", $rsp, $::callback);
                            next;
                        }
                   }
                }
            } else {
                # get the list of all attrs for this type object
                # get the data type  definition from Schema.pm
                my $datatype =
                  $xCAT::Schema::defspec{$type};
    
                foreach my $this_attr (@{$datatype->{'attrs'}})
                {
                    if (!grep(/^$this_attr->{attr_name}$/, @attrlist)) {
                        push(@attrlist, $this_attr->{attr_name});
                    }
                }
            }
        }
            
        # for each object
        foreach my $obj (sort keys %defhash)
        {

            unless ($obj)
            {
                next;
            }

            #  Return if this obj does not match the filter string
            if ($::opt_w)
            {
                #  just display objects that match -w
                if (! grep /^$obj$/, @displayObjList)
                {
                    next;
                }
            }

            # check the object names only if
            # the object names are passed in through command line
            if ($::objectsfrom_args || $::opt_o || (($type eq 'node') && ($::opt_o || @::noderange)))
            {
                if (!grep(/^$obj$/, @allobjoftype))
                {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "Could not find an object named \'$obj\' of type \'$type\'.";
                    xCAT::MsgUtils->message("E", $rsp, $::callback);
                    next;
                }
             }

            # special handling for site table - for now !!!!!!!
            if (($type eq 'site') || ($type eq 'monitoring'))
            {
                foreach my $a (keys %{$defhash{$obj}})
                {
                    push(@attrlist, $a);
                }
            }

            if ($::opt_x)
            {

                # TBD - do output in XML format
            }
            else
            {
                
                # display all data
                # do we want the short or long output?
                if ($long)
                {
                    if ($::opt_z)
                    {
                        push (@{$rsp_info->{data}}, "\n$obj:");
                        push (@{$rsp_info->{data}}, "    objtype=$defhash{$obj}{'objtype'}");
                    }
                    else
                    {
                        if ($#::clobjtypes > 0)
                        {
                            push (@{$rsp_info->{data}}, "Object name: $obj  ($defhash{$obj}{'objtype'})");
                        }
                        else
                        {
                            if (!$::opt_c)
                            {
                                push (@{$rsp_info->{data}}, "Object name: $obj");
                            } 
                        }
                    }

                    foreach my $showattr (sort @attrlist)
                    {
                        if ($showattr eq 'objtype')
                        {
                            next;
                        }

                        my $attrval;
                        if ( exists($defhash{$obj}{$showattr}))
                        {
                            $attrval = $defhash{$obj}{$showattr};
                        }

                        # if an attr list was provided then just display those
                        if ($::opt_i)
                        {
                            if (grep (/^$showattr$/, @::AttrList))
                            {

                                if ( ($defhash{$obj}{'objtype'} eq 'group') && ($showattr eq 'members'))
                                {
                                    my $memberlist =
                                      xCAT::DBobjUtils->getGroupMembers(
                                                                 $obj,
                                                                 \%defhash);
                                    push (@{$rsp_info->{data}}, "    $showattr=$memberlist");
                                }
                                else
                                {
                                    # nics attributes, like nicips, nichostnamesuffix.
                                    if ($showattr =~ /^nic/)
                                    {
                                        my $nicval = "$showattr=$attrval";
                                        my $nicnames;
                                        if (defined($::NicsAttrHash{$showattr}))
                                        {
                                            $nicnames = join(',', @{$::NicsAttrHash{$showattr}});
                                        }
                                        my $nicsstr;
                                        if ($nicnames)
                                        {
                                            $nicsstr = xCAT::DBobjUtils->expandnicsattr($nicval, $nicnames);
                                        }
                                        else
                                        {
                                            $nicsstr = xCAT::DBobjUtils->expandnicsattr($nicval);
                                        }
                                        # Compress mode, format the output
                                        if ($::opt_c)
                                        {
                                            $nicsstr =~ s/^\s+/$obj: /;
                                            $nicsstr =~ s/\n\s+/\n$obj: /g;
                                        }
                                        if ($nicsstr)
                                        {
                                            push (@{$rsp_info->{data}}, "$nicsstr");
                                        }
                                    }
                                    else
                                    {
                                        # since they asked for this attr
                                        #   show it even if not set
                                        if (!$::opt_c)
                                        {
                                            push (@{$rsp_info->{data}}, "    $showattr=$attrval");
                                        } 
                                        else
                                        {
                                            push (@{$rsp_info->{data}}, "$obj: $showattr=$attrval");

                                        } 
                                    }
                                }
                            }
                        }
                        else
                        {

                            if (   ($defhash{$obj}{'objtype'} eq 'group')
                                && ($showattr eq 'members'))

                            {
                                #$defhash{$obj}{'grouptype'} = "static";
                                my $memberlist =
                                  xCAT::DBobjUtils->getGroupMembers($obj,\%defhash);
                                push (@{$rsp_info->{data}}, "    $showattr=$memberlist");
                            }
                            else
                            {

                                # don't print unless set
                                if ( (defined($attrval)) && ($attrval ne '') )
                                {
                                    # nics attributes, like nicips, nichostnamesuffix.
                                    if ($showattr =~ /^nic/)
                                    {
                                        my $nicval = "$showattr=$attrval";
                                        my $nicsstr = xCAT::DBobjUtils->expandnicsattr($nicval);
                                        if ($nicsstr)
                                        {
                                            push (@{$rsp_info->{data}}, "$nicsstr");
                                        }
                                    }
                                    else
                                    {
                                        push (@{$rsp_info->{data}}, "    $showattr=$attrval");
                                    }
                                }
                            }
                        }
                    }
                    # Additional osimage attributes
                    if(($type eq "node") && $::opt_osimg)
                    {
                        if(defined($nodeosimagehash{$obj}))
                        {
                            foreach my $attr (keys %{$nodeosimagehash{$obj}})
                            {
                                if($nodeosimagehash{$obj}{$attr})
                                {
                                    push (@{$rsp_info->{data}}, "    $attr=$nodeosimagehash{$obj}{$attr}");
                                }
                            }
                        }
                    }
                }
                else
                {

                    if ($::opt_a)
                    {
                        if ($::opt_z)
                        {
                            push (@{$rsp_info->{data}}, "\n$obj:");
                        }
                        else
                        {
                            # give the type also
                            push (@{$rsp_info->{data}}, "$obj ($::AllObjTypeHash{$obj})");
                        }
                    }
                    else
                    {

                        # just give the name
                        if ($::opt_z)
                        {
                            push (@{$rsp_info->{data}}, "\n$obj:");
                        }
                        else
                        {
                            if (scalar(@::clobjtypes) > 0)
                            {
                                push (@{$rsp_info->{data}}, "$obj  ($defhash{$obj}{'objtype'})");
                            }
                            else
                            {
                                push (@{$rsp_info->{data}}, "$obj");
                            }
                        }
                    }
                }
            }
        } # end - for each object
    } # end - for each type

    #delete the fsp and bpa node from the hash
    #my $newrsp;
    #my $listtab  = xCAT::Table->new( 'nodelist' );
    #if ($listtab and  (!defined($::opt_S))  ) {
    #    foreach my $n (@{$rsp_info->{data}}) {
    #        if ( $n =~ /\(node\)/ ) {
    #            $_= $n;
    #            s/ +\(node\)//;
    #            my ($hidhash) = $listtab->getNodeAttribs($_ ,['hidden']);
    #            if ( $hidhash->{hidden} ne 1)  {
    #                push (@{$newrsp->{data}}, $n);
    #            }
    #        }else{
    #        push (@{$newrsp->{data}}, $n);
    #        }
    #    }
    #    if (defined($newrsp->{data}) && scalar(@{$newrsp->{data}}) > 0) {
    #        xCAT::MsgUtils->message("I", $newrsp, $::callback);
    #        return 0;
    #    }
    #}else {
    #    my $rsp;
    #    $rsp->{data}->[0] =
    #     "Could not open nodelist table.";
    #    xCAT::MsgUtils->message("I", $rsp, $::callback);
    #}

    # Display the definition of objects
    if (defined($rsp_info->{data}) && scalar(@{$rsp_info->{data}}) > 0) {
        xCAT::MsgUtils->message("I", $rsp_info, $::callback);
    }
    
    return 0;
}

#----------------------------------------------------------------------------

=head3  defrm

        Support for the xCAT defrm command.

        Arguments:
        Returns:
                0 - OK
                1 - error
        Globals:

        Error:

        Example:

        Comments:
            Object names to remove are derived from -o, -t, w, -a, -f,
                 or noderange!
=cut

#-----------------------------------------------------------------------------

sub defrm
{

    my %objhash;
    my $error = 0;
    my %rmhash;
    my %myhash;
    my %childrenhash;
    my %typehash;

    # process the command line
    my $rc = &processArgs;

    if ($rc != 0)
    {

        # rc: 0 - ok, 1 - return, 2 - help, 3 - error
        # 0 - continue
        # 1 - return  (like for version option)
        # 2 - return with usage
        # 3 - return error
        if ($rc == 1) {
            return 0;
        } elsif ($rc == 2) {
            &defrm_usage;
            return 0;
        } elsif ($rc == 3) {
            return 1;
        }
    }


    if ($::opt_a && !$::opt_f)
    {
        my $rsp;
        $rsp->{data}->[0] =
          "You must use the \'-f\' option when using the \'-a\' option.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        &defrm_usage;
        return 1;
    }

    #
    #  build a hash of object names and their types
    #

    # the list of objects to remove could have come from: the arg list,
    #    opt_o, a noderange, opt_t, or opt_a. (rmdef doesn't take file
    #    input)

    # if a set of objects was specifically provided on the cmd line then
    #    there can only be one type value
    if ($::objectsfrom_opto || $::objectsfrom_nr || $::objectsfrom_args)
    {
        my $type = @::clobjtypes[0];

        foreach my $obj (sort @::clobjnames)
        {
            $objhash{$obj} = $type;
        }
    }

    # if we derived a list of objects from a list of types
    if ($::objectsfrom_optt)
    {
        %objhash = %::ObjTypeHash;
    }

    # if we derived the list of objects from the "all" option
    if ($::objectsfrom_opta)
    {
        %objhash = %::AllObjTypeHash;
    }

    # handle the "-w" value - if provided
    # the list of objects may be limited by the "-w" option
    # see which objects have attr/val that match the where values
    #       - if provided
    #  !!!!! don't support -w for now - gets way too complicated with groups!!!!
    if ($::opt_w)
    {
        my $rsp;
        $rsp->{data}->[0] =
          "The \'-w\' option is not supported for the rmdef command.";
        xCAT::MsgUtils->message("I", $rsp, $::callback);
        $error = 1;
        return 1;
    }
    if (0)
    {

        # need to get object defs from DB
        %myhash = xCAT::DBobjUtils->getobjdefs(\%objhash);
        if (!(%myhash))
        {
            $error = 1;
        }

        foreach my $obj (sort (keys %objhash))
        {
            foreach my $testattr (keys %::WhereHash)
            {
                if ($myhash{$obj}{$testattr} eq $::WhereHash{$testattr})
                {

                    # add this object to the remove hash
                    $rmhash{$obj} = $objhash{$obj};
                }
            }

        }
        %objhash = %rmhash;
    }

    # if the object to remove is a group then the "groups" attr of
    #    the memberlist nodes must be updated.

    my $numobjects = 0;
    my %objTypeLists;
    foreach my $obj (keys %objhash)
    {
        my $objtype = $objhash{$obj};
        if (!defined($objTypeLists{$objtype})) # Do no call getObjectsOfType for the same objtype more than once.
        {
            @{$objTypeLists{$objtype}} = xCAT::DBobjUtils->getObjectsOfType($objtype);
        }
        if (!grep(/^$obj$/, @{$objTypeLists{$objtype}})) #Object is not in the db, do not need to delete
        {
            my $rsp;
            $rsp->{data}->[0] = "Could not find an object named \'$obj\' of type \'$objtype\'.";
            xCAT::MsgUtils->message("E", $rsp, $::callback);
            next;
        }
        $numobjects++;

        if ($objhash{$obj} eq 'group')
        {

            # get the group object definition
            my %ghash;
            $ghash{$obj} = 'group';
            my @attrs = ('grouptype', 'wherevals');
            my %grphash = xCAT::DBobjUtils->getobjdefs(\%ghash, 0, \@attrs);
            if (!(%grphash))
            {
                my $rsp;
                $rsp->{data}->[0] =
                  "Could not get xCAT object definition for \'$obj\'.";
                xCAT::MsgUtils->message("I", $rsp, $::callback);
                next;
            }

            # Dynamic node group stores in nodegroup table
            # do not need to update the nodelist table
            if ($grphash{$obj}{'grouptype'} eq 'dynamic')
            {
                next;
            }
            # get the members list
            #  all groups are "static" for now
            $grphash{$obj}{'grouptype'} = "static";
            my $memberlist = xCAT::DBobjUtils->getGroupMembers($obj, \%grphash);
            my @members = split(',', $memberlist);

            # No node in the group
            if (scalar(@members) == 0)
            {
                next;
            }
            # foreach member node of the group
            my %nodehash;
            my %nhash;
            my @gprslist;
            foreach my $m (@members)
            {
                # get the def of this node
                $nhash{$m} = 'node';
            }
            # Performance: Only call getobjdefs once
            my @attrs = ('groups');
                %nodehash = xCAT::DBobjUtils->getobjdefs(\%nhash, 0, \@attrs);
                if (!(%nodehash))
                {
                    my $rsp;
                my @nodes = keys %nhash;
                my $m = join ',', @nodes;
                    $rsp->{data}->[0] =
                      "Could not get xCAT object definition for \'$m\'.";
                    xCAT::MsgUtils->message("I", $rsp, $::callback);
                    next;
                }

            foreach my $m (keys %nodehash)
            {
                # need to update the "groups" attr of the node def
                # split the "groups" to get a list
                @gprslist = split(',', $nodehash{$m}{groups});

                # make a new "groups" list for the node without the
                #      group that is being removed
                my $first = 1;
                my $newgrps = "";
                foreach my $grp (@gprslist)
                {
                    chomp($grp);
                    if ($grp eq $obj)
                    {
                        next;
                    }
                    else
                    {

                        # set new groups list for node
                        if (!$first)
                        {
                            $newgrps .= ",";
                        }
                        $newgrps .="$grp";
                        $first = 0;

                    }
                }

                # make the change to %nodehash
                $nodehash{$m}{groups} = $newgrps;
            }

            # set the new node attr values
            if (xCAT::DBobjUtils->setobjdefs(\%nodehash) != 0)
            {
                my $rsp;
                $rsp->{data}->[0] = "Could not write data to xCAT database.";
                xCAT::MsgUtils->message("E", $rsp, $::callback);
                $error = 1;
            }
        }
    }
    # find the children of the node.
    for my $tob (keys %objhash)  {
        if ( $objhash{$tob} eq 'node' ) {
            my $ntype = xCAT::DBobjUtils->getnodetype($tob);
            if ( $ntype =~ /^(cec|frame)$/ )  {
                my $cnodep = xCAT::DBobjUtils->getchildren($tob);
                if ($cnodep) {
                    my $cnode = join ',', @$cnodep;            
                    $childrenhash{$tob} = $cnode;
                    $typehash{$tob} = $ntype;
                }
            }
        }
    }
    # remove the objects
    if (xCAT::DBobjUtils->rmobjdefs(\%objhash) != 0)
    {
        $error = 1;
    }

    if ($error)
    {
        my $rsp;
        $rsp->{data}->[0] =
          "One or more errors occured when attempting to remove xCAT object definitions.";
        xCAT::MsgUtils->message("E", $rsp, $::callback);
        return 1;
    }
    else
    {
        if ($numobjects > 0)
        {
            if ($::verbose)
            {

                #  give results
                my $rsp;
                $rsp->{data}->[0] = "The following objects were removed:";
                xCAT::MsgUtils->message("I", $rsp, $::callback);

                my $n = 1;
                foreach my $o (sort(keys %objhash))
                {
                    $rsp->{data}->[$n] = "$o";
                    $n++;
                }
                xCAT::MsgUtils->message("I", $rsp, $::callback);
            }
            else
            {
                my $rsp;
                my $nodenum = scalar(keys %objhash);
                $rsp->{data}->[0] = "$nodenum object definitions have been removed.";
                xCAT::MsgUtils->message("I", $rsp, $::callback);
            }
            # Give a warning message to the user to remove the children of the node.
            for my $tn (keys %objhash)  {
                if ( $childrenhash{$tn} ) {
                    my $rsp;
                    $rsp->{data}->[0] =
                      "You have removed a $typehash{$tn} node, please remove these nodes belongs to it manually: $childrenhash{$tn} .";
                    xCAT::MsgUtils->message("W", $rsp, $::callback);                
                }
            }            
        }
        else
        {
            my $rsp;
            $rsp->{data}->[0] =
              "No objects have been removed from the xCAT database.";
            xCAT::MsgUtils->message("I", $rsp, $::callback);
        }
        return 0;

    }

}

#----------------------------------------------------------------------------

=head3  defmk_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

# subroutines to display the usage
sub defmk_usage
{
    my $rsp;
    $rsp->{data}->[0] =
      "\nUsage: mkdef - Create xCAT data object definitions.\n";
    $rsp->{data}->[1] = "  mkdef [-h | --help ] [-t object-types]\n";
    $rsp->{data}->[2] =
      "  mkdef [-V | --verbose] [-t object-types] [-o object-names] [-z|--stanza ]";
    $rsp->{data}->[3] =
      "      [-d | --dynamic] [-w attr==val [-w attr=~val] ...]";
    $rsp->{data}->[4] =
      "      [-f | --force] [noderange] [attr=val [attr=val...]]";
    $rsp->{data}->[5] = 
      "      [-u provmethod=<install|netboot|statelite> profile=<xxx> [osvers=value] [osarch=value]]\n";
    $rsp->{data}->[6] =
      "\nThe following data object types are supported by xCAT.\n";
    my $n = 7;

    foreach my $t (sort(keys %{xCAT::Schema::defspec}))
    {
        $rsp->{data}->[$n] = "$t";
        $n++;
    }
    $rsp->{data}->[$n] =
      "\nUse the \'-h\' option together with the \'-t\' option to";
    $n++;
    $rsp->{data}->[$n] =
      "get a list of valid attribute names for each object type.\n";
    xCAT::MsgUtils->message("I", $rsp, $::callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  defch_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub defch_usage
{
    my $rsp;
    $rsp->{data}->[0] =
      "\nUsage: chdef - Change xCAT data object definitions.\n";
    $rsp->{data}->[1] = "  chdef [-h | --help ] [-t object-types]\n";
    $rsp->{data}->[2] = "  chdef [-t object-types] [-o object-names] [-n new-name] [node]\n";
    $rsp->{data}->[3] =
      "  chdef [-V | --verbose] [-t object-types] [-o object-names] [-d | --dynamic]";
    $rsp->{data}->[4] =
      "    [-z | --stanza] [-m | --minus] [-p | --plus]";
    $rsp->{data}->[5] =
      "    [-w attr==val [-w attr=~val] ... ] [noderange] [attr=val [attr=val...]]\n";
    $rsp->{data}->[6] = 
      "    [-u [provmethod=<install|netboot|statelite>]|[profile=<xxx>]|[osvers=value]|[osarch=value]]";
    $rsp->{data}->[7] =
      "\nThe following data object types are supported by xCAT.\n";
    my $n = 8;

    foreach my $t (sort(keys %{xCAT::Schema::defspec}))
    {
        $rsp->{data}->[$n] = "$t";
        $n++;
    }
    $rsp->{data}->[$n] =
      "\nUse the \'-h\' option together with the \'-t\' option to";
    $n++;
    $rsp->{data}->[$n] =
      "get a list of valid attribute names for each object type.\n";
    xCAT::MsgUtils->message("I", $rsp, $::callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  defls_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub defls_usage
{
    my $rsp;
    $rsp->{data}->[0] = "\nUsage: lsdef - List xCAT data object definitions.\n";
    $rsp->{data}->[1] = "  lsdef [-h | --help ] [-t object-types]\n";
    $rsp->{data}->[2] =
      "  lsdef [-V | --verbose] [-t object-types] [-o object-names]";
    $rsp->{data}->[3] =
      "    [ -l | --long] [-s | --short] [-a | --all] [-z | --stanza ] [-S]";
    $rsp->{data}->[4] =
      "    [-i attr-list] [-w attr==val [-w attr=~val] ...] [noderange]\n";
    $rsp->{data}->[5] =
      "\nThe following data object types are supported by xCAT.\n";
    my $n = 6;

    foreach my $t (sort(keys %{xCAT::Schema::defspec}))
    {
        $rsp->{data}->[$n] = "$t";
        $n++;
    }
    $rsp->{data}->[$n] =
      "\nUse the \'-h\' option together with the \'-t\' option to";
    $n++;
    $rsp->{data}->[$n] =
      "get a list of valid attribute names for each object type.\n";
    xCAT::MsgUtils->message("I", $rsp, $::callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  defrm_usage

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------

sub defrm_usage
{
    my $rsp;
    $rsp->{data}->[0] =
      "\nUsage: rmdef - Remove xCAT data object definitions.\n";
    $rsp->{data}->[1] = "  rmdef [-h | --help ] [-t object-types]\n";
    $rsp->{data}->[2] =
      "  rmdef [-V | --verbose] [-t object-types] [-a | --all] [-f | --force]";
    $rsp->{data}->[3] =
      "    [-o object-names] [-w attr=val,[attr=val...] [noderange]\n";
    $rsp->{data}->[4] =
      "\nThe following data object types are supported by xCAT.\n";
    my $n = 5;

    foreach my $t (sort(keys %{xCAT::Schema::defspec}))
    {
        $rsp->{data}->[$n] = "$t";
        $n++;
    }
    $rsp->{data}->[$n] =
      "\nUse the \'-h\' option together with the \'-t\' option to";
    $n++;
    $rsp->{data}->[$n] =
      "get a list of valid attribute names for each object type.\n";
    xCAT::MsgUtils->message("I", $rsp, $::callback);
    return 0;
}

#----------------------------------------------------------------------------

=head3  initialize_variables
            Initialize the global variables

        Arguments:
        Returns:
        Globals:

        Error:

        Example:

        Comments:
=cut

#-----------------------------------------------------------------------------
sub initialize_variables
{
    %::CLIATTRS = ();
    %::FILEATTRS = ();
    %::FINALATTRS = ();
    %::objfilehash = ();
    %::WhereHash = ();
    @::AttrList = ();
    %::NicsAttrHash = ();
    @::clobjtypes = ();
    @::fileobjtypes = ();
    @::clobjnames = ();
    @::fileobjnames = ();
    @::objfilelist = ();
    @::allobjnames = ();
    @::noderange = ();
}
1;

