#!/usr/bin/perl -w
# IBM(c) 2007 EPL license http://www.eclipse.org/legal/epl-v10.html
# #(C)IBM Corp
package imgutils;

use strict;
use warnings "all";

use File::Basename;
use File::Find;
use File::Path;
use Cwd qw(realpath);
use xCAT::SvrUtils;

sub el_major_version {
    my $version = shift;

    return if !defined($version);

    my ($os_family, $os_major) = xCAT::SvrUtils::parseosver($version);
    return
      if !defined($os_family)
      || $os_family !~ /^(?:rhels?|rhelc|rhelhpc|centos(?:-stream)?|rocky|alma(?:linux)?|ol)$/;

    return $os_major if length($os_major);
    return;
}

sub rpm_installroot_command {
    my ( $osver, $rootimg_dir, $non_interactive, $dnf_available ) = @_;
    $non_interactive ||= "";
    $dnf_available = -x "/usr/bin/dnf" unless defined($dnf_available);
    my $majorrel = el_major_version($osver);
    my $pkgmgr = "yum";

    # EL8 and newer are dnf-native. Keep yum as the fallback for legacy
    # systems and minimal environments that still provide only yum.
    if (defined($majorrel) && $majorrel > 7 && $dnf_available) {
        $pkgmgr = "dnf";
    }

    my $cmd = "$pkgmgr $non_interactive -c /tmp/genimage.$$.yum.conf --installroot=$rootimg_dir/ --disablerepo=* ";
    if (defined($majorrel) && $majorrel > 7) {
        $cmd .= "--releasever=" . $majorrel . " ";
        $cmd .= "--setopt=module_platform_id=platform:el" . $majorrel . " ";
    }

    return $cmd;
}

sub varsubinline{
    my $line=shift;
    my $refvardict=shift;

    my @varsinline= $line =~ /\$\{?(\w+)\}?/g;
    my @unresolvedvars;
    foreach my $var(@varsinline){
        if(exists $refvardict->{$var}){
            $line=~ s/\$\{$var\}/$refvardict->{$var}/g;
            $line=~ s/\$$var/$refvardict->{$var}/g;
        }else{
            push @unresolvedvars,$var;
        }
    }

    return $line;
}

sub _profile_lookup_osbase_list {
    my $osver = shift;

    # OS version on s390x can contain 'sp', e.g. sles11sp1
    # If OS version contains 'sp', get the index of 'sp' instead of '.'
    if ($osver =~ /sles/ && $osver =~ /sp/) {
        my $dotpos = rindex($osver, "sp");
        return (substr($osver, 0, $dotpos));
    }

    return grep { $_ ne $osver } xCAT::SvrUtils::get_os_search_list($osver);
}

sub get_profile_def_filename {
    my $osver   = shift;
    my $profile = shift;
    my $arch    = shift;

    my $tmp_base = shift;
    my $base     = realpath($tmp_base);    #get the full path
    if (!$base) { $base = $tmp_base; }

    my $ext = shift;

    my @osbase = _profile_lookup_osbase_list($osver);
    my $fallbackos;
    if ($osver =~ /^leap15/) {
        $fallbackos = "sle15";
    }
    if (-r "$base/$profile.$osver.$arch.$ext") {
        return "$base/$profile.$osver.$arch.$ext";
    }
    foreach my $osbase (@osbase) {
        if (-r "$base/$profile.$osbase.$arch.$ext") {
            return "$base/$profile.$osbase.$arch.$ext";
        }
    }
    if ($fallbackos && -r "$base/$profile.$fallbackos.$arch.$ext") {
        return "$base/$profile.$fallbackos.$arch.$ext";
    } elsif (-r "$base/$profile.$arch.$ext") {
        return "$base/$profile.$arch.$ext";
    } elsif (-r "$base/$profile.$osver.$ext") {
        return "$base/$profile.$osver.$ext";
    }
    foreach my $osbase (@osbase) {
        if (-r "$base/$profile.$osbase.$ext") {
            return "$base/$profile.$osbase.$ext";
        }
    }
    if ($fallbackos && -r "$base/$profile.$fallbackos.$ext") {
        return "$base/$profile.$fallbackos.$ext";
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

    $file=varsubinline($file,\%ENV);
    unless ($file =~ /^\//) {
        $file = $idir . "/" . $file;
    }

    open(INCLUDE, $file) ||
      return "#INCLUDEBAD:cannot open $file#";

    while (<INCLUDE>) {
        chomp($_);
        s/\s+$//;    #remove trailing spaces
        next if /^\s*$/;    #-- skip empty lines
        next
          if (/^\s*#/
            && !/^\s*#INCLUDE:[^#^\n]+#/
            && !/^\s*#NEW_INSTALL_LIST#/
            && !/^\s*#ENV:[^#^\n]+#/);    #-- skip comments
        push(@text, $_);
    }

    close(INCLUDE);

    return join(',', @text);
}

sub get_package_names {
    my $plist_file_list = shift;
    my %pkgnames        = ();

    my @plist_file_names = split ',', $plist_file_list;
    foreach my $plist_file_name (@plist_file_names) {

        # this variable needs to be cleaned when loop the pkglist files
        my @tmp_array = ();

        if ($plist_file_name && -r $plist_file_name) {
            my $pkgfile;
            open($pkgfile, "<", "$plist_file_name");
            while (<$pkgfile>) {
                chomp;
                s/\s+$//;    #remove trailing white spaces
                next if /^\s*$/;    #-- skip empty lines
                next
                  if (/^\s*#/
                    && !/^\s*#INCLUDE:[^#^\n]+#/
                    && !/^\s*#NEW_INSTALL_LIST#/
                    && !/^\s*#ENV:[^#^\n]+#/);    #-- skip comments
                push(@tmp_array, $_);
            }
            close($pkgfile);

            if (@tmp_array > 0) {
                my $pkgtext = join(',', @tmp_array);

                #handle the #INLCUDE# tag recursively
                my $idir         = dirname($plist_file_name);
                my $doneincludes = 0;
                while (not $doneincludes) {
                    $doneincludes = 1;
                    if ($pkgtext =~ /#INCLUDE:[^#^\n]+#/) {
                        $doneincludes = 0;
                        $pkgtext =~ s/#INCLUDE:([^#^\n]+)#/include_file($1,$idir)/eg;
                    }
                }
                #print "\n\npkgtext=$pkgtext\n\n";
                my @tmp = split(',', $pkgtext);
                my $pass = 1;
                foreach (@tmp) {
                    my $idir;
                    if (/^--/) {
                        $idir = "POST_REMOVE"; #line starts with -- means the package should be removed after otherpkgs are installed
                        s/^--//;
                    } elsif (/^-/) {
                        $idir = "PRE_REMOVE"; #line starts with single - means the package should be removed before otherpkgs are installed
                        s/^-//;
                    } elsif (/^#NEW_INSTALL_LIST#/) {
                        $pass++;
                        next;
                    } elsif (/^#ENV:([^#^\n]+)#/) {
                        my $pa  = $pkgnames{$pass}{ENVLIST};
                        my $env = $1;
                        if (exists($pkgnames{$pass}{ENVLIST})) {
                            push(@$pa, $env);
                        } else {
                            $pkgnames{$pass}{ENVLIST} = [$env];
                        }
                        next;
                    } elsif (/^#INCLUDEBAD:([^#^\n]+)#/) {
                        my $pa   = $pkgnames{$pass}{INCLUDEBAD};
                        my $file = $1;
                        if (exists($pkgnames{$pass}{INCLUDEBAD})) {
                            push(@$pa, $file);
                        } else {
                            $pkgnames{$pass}{INCLUDEBAD} = [$file];
                        }
                        next;
                    } elsif (/^#/) {

                        # ignore all other comment lines
                        next;
                    } else {
                        $idir = dirname($_);
                    }
                    my $fn = basename($_);
                    if (exists($pkgnames{$pass}{$idir})) {
                        my $pa = $pkgnames{$pass}{$idir};
                        push(@$pa, $fn);
                    } else {
                        $pkgnames{$pass}{$idir} = [$fn];
                    }

                }
            }
        }
    }
    return %pkgnames;
}

sub default_net_drivers {
    my ( $family, $arch ) = @_;

    my %drivers = (
        rh => {
            x86    => [qw(tg3 bnx2 bnx2x e1000 e1000e igb mlx_en mlx5_core virtio_net be2net)],
            x86_64 => [qw(tg3 bnx2 bnx2x e1000 e1000e igb mlx_en mlx5_core virtio_net be2net)],
            aarch64 => [qw(tg3 bnx2 bnx2x e1000e igb mlx_en mlx5_core virtio_net)],
            ppc64   => [qw(e1000 e1000e igb ibmveth ehea)],
            s390x   => [qw(qdio ccwgroup)],
        },
        sles => {
            x86    => [qw(tg3 bnx2 bnx2x e1000 e1000e virtio_net virtio_balloon igb mlx4_en mlx5_core be2net)],
            x86_64 => [qw(tg3 bnx2 bnx2x e1000 e1000e virtio_net virtio_balloon igb mlx4_en mlx5_core be2net)],
            ppc64   => [qw(tg3 e1000 e1000e igb ibmveth ehea be2net)],
            s390x   => [qw(qdio ccwgroup qeth qeth_l2 qeth_l3)],
        },
        ubuntu => {
            x86    => [qw(tg3 bnx2 bnx2x e1000 e1000e igb mlx_en mlx5_core virtio_net overlay)],
            x86_64 => [qw(tg3 bnx2 bnx2x e1000 e1000e igb mlx_en mlx5_core virtio_net overlay)],
            ppc64el => [qw(tg3 bnx2 bnx2x e1000 e1000e igb ibmveth ehea mlx_en mlx4_en mlx5_core virtio_net overlay)],
            ppc64   => [qw(e1000 e1000e igb ibmveth ehea)],
            s390x   => [qw(qdio ccwgroup)],
        },
    );

    return () if !exists($drivers{$family}) || !exists($drivers{$family}{$arch});
    return @{ $drivers{$family}{$arch} };
}

sub _kernel_module_name {
    my $path = shift;
    my $name = basename($path);

    $name =~ s/\.ko(?:\.(?:gz|xz|zst))?$//x;
    $name =~ tr/-/_/;
    return $name;
}

sub target_kernel_module_availability {
    my ( $rootimg_dir, $kernelver, @modules ) = @_;
    my %requested = map { _kernel_module_name($_) => 1 } @modules;
    my %available = map { $_ => 0 } keys %requested;
    my $module_root = "$rootimg_dir/lib/modules/$kernelver";

    my $modules_dep = "$module_root/modules.dep";
    if (open(my $dep_fh, '<', $modules_dep)) {
        while (my $line = <$dep_fh>) {
            my ($path) = split /:/x, $line, 2;
            my $name = _kernel_module_name($path);
            if ($requested{$name} && -f "$module_root/$path") {
                $available{$name} = 1;
            }
        }
        close($dep_fh);
    }

    my $modules_builtin = "$module_root/modules.builtin";
    if (open(my $builtin_fh, '<', $modules_builtin)) {
        while (my $path = <$builtin_fh>) {
            chomp($path);
            my $name = _kernel_module_name($path);
            $available{$name} = 1 if $requested{$name};
        }
        close($builtin_fh);
    }

    if (-d $module_root && grep { !$available{$_} } keys %requested) {
        find(
            {
                no_chdir => 1,
                wanted   => sub {
                    return if !-f $File::Find::name;
                    return if $File::Find::name !~ /\.ko(?:\.(?:gz|xz|zst))?$/x;
                    my $name = _kernel_module_name($File::Find::name);
                    $available{$name} = 1 if $requested{$name};
                },
            },
            $module_root,
        );
    }

    return %available;
}

sub resolve_mellanox_default_net_drivers {
    my ( $rootimg_dir, $kernelver, $requested_drivers, @default_drivers ) = @_;
    my @drivers;
    my %seen;
    my $has_mellanox_defaults = grep {
        _kernel_module_name($_) =~ /^mlx(?:_en|4_en|5_core)$/x
    } @default_drivers;
    my $has_mellanox_drivers = $has_mellanox_defaults || grep {
        _kernel_module_name($_) =~ /^mlx(?:_en|4_en|5_core)$/x
    } @{$requested_drivers};
    if (!$has_mellanox_drivers) {
        return grep { !$seen{$_}++ } (@{$requested_drivers}, @default_drivers);
    }

    my %available = target_kernel_module_availability(
        $rootimg_dir,
        $kernelver,
        qw(mlx_en mlx4_en mlx5_core mlx4_ib mlx5_ib ib_ipoib),
    );

    # Keep unavailable explicit requests, except for the historical mlx4 alias.
    foreach my $driver (@{$requested_drivers}) {
        my $name = _kernel_module_name($driver);
        if ($name eq 'mlx_en'
            && !$available{'mlx_en'}
            && $available{'mlx4_en'})
        {
            $driver =~ s/mlx_en/mlx4_en/;
        }
        push @drivers, $driver;
    }

    foreach my $driver (@default_drivers) {
        my $name = _kernel_module_name($driver);
        if ($name eq 'mlx_en') {
            if (!$available{'mlx_en'}) {
                next if !$available{'mlx4_en'};
                $driver =~ s/mlx_en/mlx4_en/;
            }
        } elsif ($name eq 'mlx4_en' || $name eq 'mlx5_core') {
            next if !$available{$name};
        }
        push @drivers, $driver;
    }

    if ($has_mellanox_defaults) {
        my @mellanox_ib_drivers = grep { $available{$_} } qw(mlx4_ib mlx5_ib);
        push @drivers, map { "$_.ko" } @mellanox_ib_drivers;
        if (@mellanox_ib_drivers && $available{'ib_ipoib'}) {
            push @drivers, 'ib_ipoib.ko';
        }
    }

    return grep { !$seen{$_}++ } @drivers;
}

1;
