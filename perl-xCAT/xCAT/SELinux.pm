# IBM(c) 2026 EPL license http://www.eclipse.org/legal/epl-v10.html
package xCAT::SELinux;

use strict;
use warnings;

# selinuxfs is at /sys/fs/selinux. /selinux is the path a kernel before 2.6.37 uses.
our @ENFORCE_FILES = ('/sys/fs/selinux/enforce', '/selinux/enforce');
our $CONFIG_FILE = '/etc/selinux/config';

our @MODES = qw(enforcing permissive disabled);

# The OS families that ship SELinux and get the xCAT policy. SLES 15 and Ubuntu use AppArmor.
our $POLICY_OS = qr/^(?:rhel|rhes|rhels|centos|alma|rocky|ol|fedora|openeuler|sl\d)/i;

#-----------------------------------------------------------------------------

=head3 runtime_mode

    Descriptions:
        Reports the SELinux mode of the running system.
    Arguments:
        root - a prefix for the paths this module reads. The default is the
               empty string, which reads the real system.
    Returns:
        'enforcing'  - selinuxfs reports enforcing
        'permissive' - selinuxfs reports permissive
        'enabled'    - selinuxfs is there and the mode is not readable
        'disabled'   - selinuxfs is not there, so SELinux is off
    Example:
        my $mode = xCAT::SELinux->runtime_mode();

=cut

#-----------------------------------------------------------------------------
sub runtime_mode {
    my ($class, %args) = @_;
    my $root = defined $args{root} ? $args{root} : '';

    foreach my $path (@ENFORCE_FILES) {
        my $value = _first_line("$root$path");
        next unless defined $value;
        $value =~ s/\s+//g;
        return 'enforcing'  if $value eq '1';
        return 'permissive' if $value eq '0';
        return 'enabled';
    }

    return 'disabled';
}

#-----------------------------------------------------------------------------

=head3 config_mode

    Descriptions:
        Reports the mode that /etc/selinux/config selects for the next boot.
    Arguments:
        root - a prefix for the paths this module reads.
    Returns:
        The lower case value of the last SELINUX= line, or undef when the file
        has no such line and when the file is not there.
    Example:
        my $mode = xCAT::SELinux->config_mode();

=cut

#-----------------------------------------------------------------------------
sub config_mode {
    my ($class, %args) = @_;
    my $root = defined $args{root} ? $args{root} : '';

    my $mode;
    open(my $fh, '<', "$root$CONFIG_FILE") or return undef;
    while (my $line = <$fh>) {
        next if $line =~ /^\s*#/;
        $mode = lc($1) if $line =~ /^\s*SELINUX\s*=\s*(\S+)/;
    }
    close($fh);

    return $mode;
}

#-----------------------------------------------------------------------------

=head3 xcatconfig_action

    Descriptions:
        Decides what xcatconfig does about SELinux on this node. The answer
        asks for no change, because the SELinux policy belongs to the site.
        The caller reports the warning.
    Arguments:
        root - a prefix for the paths this module reads.
    Returns:
        A hash reference:
            mode        - the mode runtime_mode reports
            config_mode - the mode config_mode reports
            warning     - a message for the admin, or undef when SELinux is off
    Example:
        my $answer = xCAT::SELinux->xcatconfig_action();

=cut

#-----------------------------------------------------------------------------
sub xcatconfig_action {
    my ($class, %args) = @_;
    my $root = defined $args{root} ? $args{root} : '';

    my $mode = $class->runtime_mode(root => $root);
    my %answer = (
        mode        => $mode,
        config_mode => $class->config_mode(root => $root),
        warning     => undef,
    );

    return \%answer if $mode eq 'disabled';

    $answer{warning} =
      "SELINUX is $mode. xCAT does not change the SELinux mode or $CONFIG_FILE.";

    return \%answer;
}

#-----------------------------------------------------------------------------

=head3 install_default

    Descriptions:
        Decides the site.selinux value that the first install records.
        Only an enforcing management node gives enforcing. An existing
        value belongs to the admin and stays.
    Arguments:
        mode     - the value runtime_mode returns
        existing - the current site.selinux value, or undef
    Returns:
        'enforcing' or 'disabled' to write, or undef to write nothing.
    Example:
        my $value = xCAT::SELinux->install_default($mode, $existing);

=cut

#-----------------------------------------------------------------------------
sub install_default {
    my ($class, $mode, $existing) = @_;

    return undef if defined $existing && $existing =~ /\S/;
    return (defined $mode && $mode eq 'enforcing') ? 'enforcing' : 'disabled';
}

#-----------------------------------------------------------------------------

=head3 node_modes

    Descriptions:
        Resolves the SELinux mode each node gets when it is provisioned.
        The order is the noderes row of the node, the noderes rows of its
        groups, site.selinux, then disabled. A node row can enable SELinux
        when site.selinux is disabled. A node resolves to disabled when its
        OS has no xCAT SELinux policy, when its OS is not known, and when it
        is statelite.
    Arguments:
        nodes   - a reference to a list of node names
        reasons - optional hash reference. For each node that resolves to
                  disabled against its configured mode, the sub sets a message.
    Returns:
        A hash reference: node name => enforcing, permissive or disabled.
    Example:
        my $modes = xCAT::SELinux->node_modes(\@nodes, \%why);

=cut

#-----------------------------------------------------------------------------
sub node_modes {
    my ($class, $nodes, $reasons) = @_;
    $reasons = {} unless ref($reasons) eq 'HASH';

    my %modes;
    return \%modes unless $nodes && @{$nodes};

    require xCAT::Table;
    require xCAT::TableUtils;

    my $site = xCAT::TableUtils->get_site_attribute('selinux');

    my $noderes = _nodes_attribs('noderes', $nodes, ['selinux']);
    my $nodetype = _nodes_attribs('nodetype', $nodes, [ 'os', 'provmethod' ]);
    my %images;

    foreach my $node (@{$nodes}) {
        my $value = $noderes->{$node}{selinux};
        $value = $site unless defined $value && $value =~ /\S/;
        my $mode = _normalize_mode($value);
        if (!defined $mode) {
            $reasons->{$node} = "selinux value '$value' is not one of @MODES";
            $modes{$node} = 'disabled';
            next;
        }

        my ($os, $provmethod) = @{ $nodetype->{$node} }{qw(os provmethod)};
        if (defined $provmethod && $provmethod !~ /^(?:install|netboot|statelite)$/) {
            $images{$provmethod} ||= _image_attribs($provmethod);
            my $image = $images{$provmethod};
            $os = $image->{osvers} if $image->{osvers};
            $provmethod = $image->{provmethod};
        }

        if ($mode ne 'disabled') {
            if (!defined $os || $os eq '') {
                $reasons->{$node} = "SELinux $mode needs a known OS";
                $mode = 'disabled';
            } elsif ($os !~ $POLICY_OS) {
                $reasons->{$node} = "$os has no xCAT SELinux policy";
                $mode = 'disabled';
            } elsif (defined $provmethod && $provmethod eq 'statelite') {
                $reasons->{$node} = "statelite does not support SELinux $mode";
                $mode = 'disabled';
            }
        }

        $modes{$node} = $mode;
    }

    return \%modes;
}

#-----------------------------------------------------------------------------

=head3 netboot_supported

    Descriptions:
        Reports whether a stateless image of this OS can boot with SELinux on.
        No OS can, so mknetboot writes selinux=0 for every stateless node.

        A stateless root is a cpio archive unpacked into tmpfs, and cpio
        carries no SELinux label, so the root starts unlabelled. Three boots of
        an AlmaLinux 10.1 image on an enforcing node measured both ways out of
        that. A pre-pivot hook that loads the policy denies every later exec in
        the initramfs, because the initramfs root is root_t and kernel_t cannot
        execute it. A pre-pivot hook that runs setfiles and loads no policy does
        label the root, and systemd then loads the policy after switch_root,
        fails to relabel /dev and /run, and freezes with "Failed to allocate
        manager object".

        Keep this sub as the one place that answers the question. Change it when
        a stateless node is measured reaching status=booted with getenforce
        reporting Enforcing.
    Arguments:
        osver - the OS of the image, for example rhels9.6 or openeuler24.03sp3
    Returns:
        0.
    Example:
        my $ok = xCAT::SELinux->netboot_supported($osver);

=cut

#-----------------------------------------------------------------------------
sub netboot_supported {
    my ($class, $osver) = @_;

    return 0;
}

#-----------------------------------------------------------------------------

=head3 kcmdline_selinux

    Descriptions:
        Gives the kernel arguments that select the SELinux mode of a
        stateless node. One image serves every mode.
    Arguments:
        mode  - the mode node_modes resolved for the node
        osver - the OS of the image
    Returns:
        'selinux=0' for disabled and for an image that cannot label its root,
        'enforcing=0' for permissive, and the empty string for enforcing.
    Example:
        $kcmdline .= ' ' . xCAT::SELinux->kcmdline_selinux($mode, $osver);

=cut

#-----------------------------------------------------------------------------
sub kcmdline_selinux {
    my ($class, $mode, $osver) = @_;

    return 'selinux=0' unless defined $mode && $class->netboot_supported($osver);
    return '' if $mode eq 'enforcing';
    return 'enforcing=0' if $mode eq 'permissive';
    return 'selinux=0';
}

#-----------------------------------------------------------------------------

=head3 kickstart_relabel

    Descriptions:
        Gives the %post command that relabels the files the xCAT post
        scripts wrote. rpm labels what it installs; scripts that write in the
        installer chroot can leave the label of the parent directory.
    Arguments:
        mode - the mode of the node
    Returns:
        The command, or the empty string when the mode is disabled.

=cut

#-----------------------------------------------------------------------------
sub kickstart_relabel {
    my ($class, $mode) = @_;

    return '' unless defined $mode && ($mode eq 'enforcing' || $mode eq 'permissive');
    return '/usr/sbin/restorecon -RF /xcatpost /opt/xcat /etc /root /var/log'
      . ' || echo "restorecon returned $?"';
}

#-----------------------------------------------------------------------------

=head3 kickstart_mode

    Descriptions:
        Reads the SELinux mode a rendered kickstart asks anaconda for.
    Arguments:
        text - the kickstart
    Returns:
        enforcing, permissive or disabled. A kickstart with no selinux line
        gets the anaconda default, enforcing.

=cut

#-----------------------------------------------------------------------------
sub kickstart_mode {
    my ($class, $text) = @_;

    my $mode = 'enforcing';
    foreach my $line (split /\n/, (defined $text ? $text : '')) {
        next unless $line =~ /^\s*selinux\s+--(\w+)/;
        my $word = lc($1);
        $mode = $word eq 'disable' ? 'disabled' : $word;
    }

    return $mode;
}

#-----------------------------------------------------------------------------

=head3 kickstart_mismatch

    Descriptions:
        Compares the mode of a node with the mode its kickstart asks for.
        A template that hard-codes the selinux line cannot follow the node.
    Arguments:
        mode - the mode node_modes resolved for the node
        text - the rendered kickstart
    Returns:
        A warning, or undef when both agree.

=cut

#-----------------------------------------------------------------------------
sub kickstart_mismatch {
    my ($class, $mode, $text) = @_;

    my $asked = $class->kickstart_mode($text);
    return undef if !defined $mode || $mode eq $asked;
    return "SELinux mode is $mode, but the install template sets $asked. "
      . "Use selinux --#SELINUXMODE# in the template.";
}

#-----------------------------------------------------------------------------

=head3 nfs_mount_options

    Descriptions:
        Gives the mount options for a tree that a service node mounts from
        the management node. NFSv3 and NFSv4 without security_label carry no
        per-file label, so the mount gets one type for every file.
    Arguments:
        base - the options without a context
        type - the SELinux type of the tree, for example public_content_t
        mode - the runtime mode of the service node
    Returns:
        The options. The kernel refuses context= when SELinux is off, so a
        disabled node gets base unchanged.

=cut

#-----------------------------------------------------------------------------
sub nfs_mount_options {
    my ($class, $base, $type, $mode) = @_;

    return $base if !defined $mode || $mode eq 'disabled';
    return "$base,context=system_u:object_r:$type:s0";
}

sub _normalize_mode {
    my ($value) = @_;

    return 'disabled' unless defined $value;
    $value = lc($value);
    $value =~ s/^\s+|\s+$//g;
    return 'disabled' if $value eq '';
    return (grep { $_ eq $value } @MODES) ? $value : undef;
}

sub _nodes_attribs {
    my ($table, $nodes, $attrs) = @_;

    my %rows;
    my $tab = xCAT::Table->new($table) or return \%rows;
    my $all = $tab->getNodesAttribs($nodes, $attrs) || {};
    $tab->close();
    foreach my $node (keys %{$all}) {
        my $row = ref($all->{$node}) eq 'ARRAY' ? $all->{$node}[0] : undef;
        $rows{$node} = $row if ref($row) eq 'HASH';
    }

    return \%rows;
}

sub _image_attribs {
    my ($imagename) = @_;

    my $tab = xCAT::Table->new('osimage') or return {};
    my $row = $tab->getAttribs({ imagename => $imagename }, 'osvers', 'provmethod');
    $tab->close();

    return $row || {};
}

sub _first_line {
    my ($path) = @_;

    open(my $fh, '<', $path) or return undef;
    my $line = <$fh>;
    close($fh);

    return $line;
}

1;
