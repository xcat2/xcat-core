package xCAT_plugin::freebsdrepo;

use strict;
use warnings;
use Getopt::Long ();
use xCAT::Table;
use xCAT::TableUtils;

sub handled_commands {
    return { freebsdrepo => 'freebsdrepo' };
}

sub _image_row {
    my ($table, $name, $fields) = @_;
    my $handle = xCAT::Table->new($table, -create => 0, -autocommit => 1);
    die "Cannot open $table for image $name\n" unless $handle;
    my @rows;
    my $read = eval { @rows = $handle->getAttribs({ imagename => $name }, $fields); 1; };
    my $error = $@;
    my $closed = eval { $handle->close(); 1; };
    die $error unless $read;
    die $@ unless $closed;
    @rows = () if @rows == 1 && !defined($rows[0]);
    die "Missing $table row for image $name\n" unless @rows;
    die "Duplicate $table rows for image $name\n" unless @rows == 1;
    my $row = $rows[0];
    die "Invalid $table row for image $name\n" if ref($row) ne 'HASH'
      || !defined($row->{imagename}) || ref($row->{imagename}) || $row->{imagename} ne $name;
    die "Disabled $table row for image $name\n" if defined($row->{disable})
      && (ref($row->{disable}) || $row->{disable} =~ /\A(?:yes|1)\z/ix);
    return $row;
}

sub _plan_image {
    my ($name, $diagnostics) = @_;
    die "Invalid image name\n" if !defined($name) || ref($name)
      || $name !~ /\A[A-Za-z0-9][A-Za-z0-9_.-]{0,246}\z/x;
    my $osimage = _image_row('osimage', $name,
        [qw(imagename imagetype osname osvers osarch provmethod disable)]);
    my $freebsdimage = _image_row('freebsdimage', $name,
        [qw(imagename imageversion bootdir pkgdir pkglist otherpkgdir otherpkglist disable)]);
    my ($policy_path) = xCAT::TableUtils->get_site_attribute('freebsdimportpolicy');
    my $policy = xCAT::FreeBSDRepoImport::load_import_policy($policy_path);
    my $options = xCAT::FreeBSDRepoImport::package_plan_options($policy);
    my $installroot = xCAT::TableUtils->getInstallDir();
    require xCAT::FreeBSDPackagePlan;
    return xCAT::FreeBSDPackagePlan::publish_image(installroot => $installroot,
        image => { %$osimage, %$freebsdimage }, %$options,
        defined($diagnostics) ? (diagnostics => $diagnostics) : ());
}

sub _arguments {
    my ($args, $usage) = @_;
    my (@profiles, @errors);
    my ($help, $nonoverwrite, $diagnostics) = (0, 0, 0);
    my $parsed;
    {
        local $SIG{__WARN__} = sub { push @errors, @_ };
        my $parser = Getopt::Long::Parser->new(config => [qw(default permute no_auto_abbrev no_ignore_case)]);
        $parsed = $parser->getoptionsfromarray($args,
            'policy=s@' => \@profiles, 'w' => \$nonoverwrite, 'h|help' => \$help,
            'diagnostics' => \$diagnostics);
    }
    die "Invalid freebsdrepo arguments: @errors\n$usage\n"
      if !$parsed || ($help ? @$args > 1 : @$args != 1);
    return (\@profiles, $nonoverwrite, $help, $diagnostics);
}

sub _run_action {
    my ($action, $args, $profiles, $nonoverwrite, $diagnostics) = @_;
    require xCAT::FreeBSDRepoImport;
    if ($action eq 'inspect') {
        die "Repository inspection does not accept --policy or -w\n" if @$profiles || $nonoverwrite;
        my $tree = xCAT::FreeBSDRepo::snapshot_tree($args->[0]);
        return ["TREE_DIGEST:$tree->{digest}\nBYTES:$tree->{bytes}\n"];
    }
    if ($action eq 'plan') {
        die "Package planning does not accept --policy or -w\n" if @$profiles || $nonoverwrite;
        my $publication = _plan_image($args->[0], $diagnostics);
        return ["Package plan: $publication->{path}", "SHA256:$publication->{digest}"];
    }
    die "Repository import requires exactly one --policy profile\n" unless @$profiles == 1;
    my ($policy_path) = xCAT::TableUtils->get_site_attribute('freebsdimportpolicy');
    die "site.freebsdimportpolicy is not set\n"
      if !defined($policy_path) || (!ref($policy_path) && $policy_path eq '');
    my $policy = xCAT::FreeBSDRepoImport::load_import_policy($policy_path);
    my $options = xCAT::FreeBSDRepoImport::repository_import_options($policy, $profiles->[0]);
    my $publication = xCAT::FreeBSDRepoImport::import_repository($args->[0],
        xCAT::TableUtils->getInstallDir(), %$options, nonoverwrite => $nonoverwrite);
    my $message = $publication->{reused}
      ? "Verified existing FreeBSD repository at $publication->{path}"
      : "Imported FreeBSD repository to $publication->{path}";
    return [$message, "Repository: $publication->{path}/repository"];
}

sub _diagnostic_authority {
    my ($request, $action) = @_;
    die "Diagnostics require the plan action\n" unless $action eq 'plan';
    my $auth = $request->{_xcat_authname};
    die "Package diagnostics require authenticated root\n" if ref($auth) ne 'ARRAY'
      || @$auth != 1 || !defined($auth->[0]) || ref($auth->[0]) || $auth->[0] ne 'root';
    return;
}

sub process_request {
    my ($request, $callback) = @_;
    return unless $request->{command}->[0] eq 'freebsdrepo';
    my @args = @{$request->{arg} || []};
    my $usage = "Usage: freebsdrepo inspect /absolute/tree\n"
      . "       freebsdrepo import /absolute/tree --policy profile [-w]\n"
      . '       freebsdrepo plan osimage [--diagnostics]';
    if (@args == 1 && ($args[0] eq '-h' || $args[0] eq '--help')) {
        $callback->({ data => ["$usage\n"] });
        return;
    }
    my $diagnostics;
    my $ok = eval {
        my $action = shift @args;
        die "$usage\n" unless defined($action) && ($action eq 'inspect' || $action eq 'import' || $action eq 'plan');
        my ($profiles, $nonoverwrite, $help, $detailed) = _arguments(\@args, $usage);
        if ($help) {
            $callback->({ data => ["$usage\n"] });
            return 1;
        }
        _diagnostic_authority($request, $action) if $detailed;
        my $data = _run_action($action, \@args, $profiles, $nonoverwrite, $detailed ? \$diagnostics : undef);
        $callback->({ data => $data });
        1;
    };
    unless ($ok) {
        my $response = { error => [$@ || 'FreeBSD repository command failed'], errorcode => [1] };
        $response->{data} = ["DIAGNOSTICS:$diagnostics"] if defined($diagnostics);
        $callback->($response);
    }
    return;
}

1;
