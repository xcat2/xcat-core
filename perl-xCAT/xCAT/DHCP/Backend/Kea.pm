package xCAT::DHCP::Backend::Kea;

use strict;
use warnings;

use JSON;
use File::Basename;
use File::Path qw/make_path/;
use Math::BigInt;
use xCAT::DHCP::Range;
use xCAT::NetworkUtils;

my %KEA_SERVICE_CANDIDATES = (
    'kea-dhcp4'      => [ 'kea-dhcp4',      'kea-dhcp4-server' ],
    'kea-dhcp6'      => [ 'kea-dhcp6',      'kea-dhcp6-server' ],
    'kea-dhcp-ddns'  => [ 'kea-dhcp-ddns',  'kea-dhcp-ddns-server' ],
    'kea-ctrl-agent' => [ 'kea-ctrl-agent' ],
);

sub new {
    my ( $class, %args ) = @_;
    return bless \%args, $class;
}

sub name {
    return 'kea';
}

sub implemented {
    return 1;
}

sub dhcp4_config_file {
    my ($self) = @_;
    return $self->{dhcp4_config_file} || '/etc/kea/kea-dhcp4.conf';
}

sub dhcp6_config_file {
    my ($self) = @_;
    return $self->{dhcp6_config_file} || '/etc/kea/kea-dhcp6.conf';
}

sub ctrl_agent_config_file {
    my ($self) = @_;
    return $self->{ctrl_agent_config_file} || '/etc/kea/kea-ctrl-agent.conf';
}

sub ddns_config_file {
    my ($self) = @_;
    return $self->{ddns_config_file} || '/etc/kea/kea-dhcp-ddns.conf';
}

sub render_dhcp4_config {
    my ( $self, $intent ) = @_;

    $intent ||= {};

    my %dhcp4 = (
        'interfaces-config' => {
            interfaces => $intent->{interfaces} || [],
        },
        'lease-database' => _first_defined( $intent->{'lease-database'}, $intent->{lease_database} ) || {
            type => 'memfile',
            name => '/var/lib/kea/kea-leases4.csv',
        },
        'valid-lifetime'           => _integer( _first_defined( $intent->{'valid-lifetime'}, $intent->{valid_lifetime}, 43200 ) ),
        'reservations-in-subnet'   => _json_bool( _first_defined( $intent->{'reservations-in-subnet'},   $intent->{reservations_in_subnet},   1 ) ),
        'reservations-out-of-pool' => _json_bool( _first_defined( $intent->{'reservations-out-of-pool'}, $intent->{reservations_out_of_pool}, 1 ) ),
        'match-client-id'          => _json_bool( _first_defined( $intent->{'match-client-id'},          $intent->{match_client_id},          0 ) ),
        subnet4                    => [ map { $self->_render_subnet4($_) } @{ _first_defined( $intent->{subnet4}, $intent->{subnets}, [] ) } ],
    );

    $dhcp4{'control-socket'}  = $intent->{'control-socket'}  if $intent->{'control-socket'};
    $dhcp4{'hooks-libraries'} = $intent->{'hooks-libraries'} if $intent->{'hooks-libraries'};
    $dhcp4{'option-def'} = $intent->{'option-def'} if $intent->{'option-def'};
    $dhcp4{'client-classes'} = [ map { $self->_render_client_class($_) } @{ $intent->{'client-classes'} } ] if $intent->{'client-classes'};
    $dhcp4{'option-data'}    = $intent->{'option-data'} if $intent->{'option-data'};
    $dhcp4{'dhcp-ddns'}      = $intent->{'dhcp-ddns'}   if $intent->{'dhcp-ddns'};
    foreach my $field (qw/ddns-send-updates ddns-override-no-update ddns-override-client-update ddns-qualifying-suffix ddns-update-on-renew/) {
        $dhcp4{$field} = $intent->{$field} if exists $intent->{$field};
    }

    return JSON->new->canonical->pretty->encode( { Dhcp4 => \%dhcp4 } );
}

sub render_dhcp6_config {
    my ( $self, $intent ) = @_;

    $intent ||= {};

    my %dhcp6 = (
        'interfaces-config' => {
            interfaces => $intent->{interfaces} || [],
        },
        'lease-database' => _first_defined( $intent->{'lease-database'}, $intent->{lease_database} ) || {
            type => 'memfile',
            name => '/var/lib/kea/kea-leases6.csv',
        },
        'preferred-lifetime' => _integer( _first_defined( $intent->{'preferred-lifetime'}, $intent->{preferred_lifetime}, 43200 ) ),
        'valid-lifetime'     => _integer( _first_defined( $intent->{'valid-lifetime'},     $intent->{valid_lifetime},     43200 ) ),
        'host-reservation-identifiers' => _first_defined( $intent->{'host-reservation-identifiers'}, [ 'duid', 'hw-address' ] ),
        subnet6              => [ map { $self->_render_subnet6($_) } @{ _first_defined( $intent->{subnet6}, $intent->{subnets}, [] ) } ],
    );

    $dhcp6{'control-socket'}  = $intent->{'control-socket'}  if $intent->{'control-socket'};
    $dhcp6{'hooks-libraries'} = $intent->{'hooks-libraries'} if $intent->{'hooks-libraries'};
    $dhcp6{'option-data'}     = $intent->{'option-data'}     if $intent->{'option-data'};
    $dhcp6{'dhcp-ddns'}       = $intent->{'dhcp-ddns'}       if $intent->{'dhcp-ddns'};
    foreach my $field (qw/ddns-send-updates ddns-override-no-update ddns-override-client-update ddns-qualifying-suffix ddns-update-on-renew/) {
        $dhcp6{$field} = $intent->{$field} if exists $intent->{$field};
    }

    return JSON->new->canonical->pretty->encode( { Dhcp6 => \%dhcp6 } );
}

sub render_ddns_config {
    my ( $self, $intent ) = @_;

    $intent ||= {};
    my $forward_domains = $intent->{forward_domains};
    $forward_domains = $intent->{'forward-ddns'}{'ddns-domains'}
      if !defined($forward_domains) && ref( $intent->{'forward-ddns'} ) eq 'HASH';
    $forward_domains ||= [];
    my $reverse_domains = $intent->{reverse_domains};
    $reverse_domains = $intent->{'reverse-ddns'}{'ddns-domains'}
      if !defined($reverse_domains) && ref( $intent->{'reverse-ddns'} ) eq 'HASH';
    $reverse_domains ||= [];

    my %ddns = (
        'ip-address'         => $intent->{'ip-address'} || '127.0.0.1',
        port                 => _integer( $intent->{port} || 53001 ),
        'dns-server-timeout' => _integer( _first_defined( $intent->{'dns-server-timeout'}, 500 ) ),
        'ncr-protocol'       => $intent->{'ncr-protocol'} || 'UDP',
        'ncr-format'         => $intent->{'ncr-format'} || 'JSON',
        'tsig-keys'          => $intent->{'tsig-keys'} || [],
        'forward-ddns'       => {
            'ddns-domains' => $forward_domains,
        },
        'reverse-ddns' => {
            'ddns-domains' => $reverse_domains,
        },
    );

    $ddns{'control-sockets'} = $intent->{'control-sockets'} if $intent->{'control-sockets'};

    return JSON->new->canonical->pretty->encode( { DhcpDdns => \%ddns } );
}

sub render_ctrl_agent_config {
    my ( $self, $intent ) = @_;

    $intent ||= {};

    my %sockets = (
        dhcp4 => {
            'socket-type' => 'unix',
            'socket-name' => $intent->{'dhcp4-socket'} || $self->_kea_control_socket('kea4-ctrl-socket'),
        },
    );
    if ( $intent->{dhcp6} || $intent->{'dhcp6-socket'} ) {
        $sockets{dhcp6} = {
            'socket-type' => 'unix',
            'socket-name' => $intent->{'dhcp6-socket'} || $self->_kea_control_socket('kea6-ctrl-socket'),
        };
    }
    if ( $intent->{ddns} || $intent->{'ddns-socket'} ) {
        $sockets{d2} = {
            'socket-type' => 'unix',
            'socket-name' => $intent->{'ddns-socket'} || $self->_kea_control_socket('kea-ddns-ctrl-socket'),
        };
    }

    my $agent = {
        'http-host'       => $intent->{'http-host'} || '127.0.0.1',
        'http-port'       => _integer( $intent->{'http-port'} || 8000 ),
        'control-sockets' => \%sockets,
    };
    $agent->{authentication} = $intent->{authentication} if $intent->{authentication};

    my $config = {
        'Control-agent' => $agent,
    };

    return JSON->new->canonical->pretty->encode($config);
}

sub host_cmds_hook_path {
    my ( $self, @extra_paths ) = @_;

    my @default_paths = exists $self->{host_cmds_hook_paths}
      ? @{ $self->{host_cmds_hook_paths} || [] }
      : (
        '/usr/lib64/kea/hooks/libdhcp_host_cmds.so',
        '/usr/lib/kea/hooks/libdhcp_host_cmds.so',
        '/usr/local/lib/kea/hooks/libdhcp_host_cmds.so',
        glob('/usr/lib/*/kea/hooks/libdhcp_host_cmds.so'),
      );

    foreach my $path (
        @extra_paths,
        @default_paths,
      )
    {
        return $path if defined($path) && -e $path;
    }

    return;
}

sub load_dhcp4_config {
    my ( $self, $path ) = @_;

    $path ||= $self->dhcp4_config_file();
    return { Dhcp4 => { subnet4 => [] } } unless -e $path;

    open( my $fh, '<', $path ) or return { error => "Unable to read $path: $!" };
    local $/;
    my $content = <$fh>;
    close($fh);

    my $json = eval { _decode_kea_json($content) };
    return { error => "Unable to parse $path as JSON: $@" } if $@;

    $json->{Dhcp4}{subnet4} ||= [];
    return $json;
}

sub load_dhcp6_config {
    my ( $self, $path ) = @_;

    $path ||= $self->dhcp6_config_file();
    return { Dhcp6 => { subnet6 => [] } } unless -e $path;

    open( my $fh, '<', $path ) or return { error => "Unable to read $path: $!" };
    local $/;
    my $content = <$fh>;
    close($fh);

    my $json = eval { _decode_kea_json($content) };
    return { error => "Unable to parse $path as JSON: $@" } if $@;

    $json->{Dhcp6}{subnet6} ||= [];
    return $json;
}

sub write_dhcp4_config {
    my ( $self, $intent, %opts ) = @_;

    return $self->write_dhcp4_json( $self->render_dhcp4_config($intent), %opts );
}

sub write_dhcp6_config {
    my ( $self, $intent, %opts ) = @_;

    return $self->write_dhcp6_json( $self->render_dhcp6_config($intent), %opts );
}

sub write_ddns_config {
    my ( $self, $intent, %opts ) = @_;

    return $self->write_ddns_json( $self->render_ddns_config($intent), %opts );
}

sub write_dhcp4_json {
    my ( $self, $json, %opts ) = @_;

    $opts{path} ||= $self->dhcp4_config_file();
    $opts{validator} ||= sub { $self->validate_dhcp4_config(@_) };
    return $self->_write_json_file( $json, %opts );
}

sub write_dhcp6_json {
    my ( $self, $json, %opts ) = @_;

    $opts{path} ||= $self->dhcp6_config_file();
    $opts{validator} ||= sub { $self->validate_dhcp6_config(@_) };
    return $self->_write_json_file( $json, %opts );
}

sub write_ddns_json {
    my ( $self, $json, %opts ) = @_;

    $opts{path} ||= $self->ddns_config_file();
    $opts{validator} ||= sub { $self->validate_ddns_config(@_) };
    return $self->_write_json_file( $json, %opts );
}

sub _write_json_file {
    my ( $self, $json, %opts ) = @_;

    my $path = $opts{path};
    my $dir  = dirname($path);
    make_path($dir) unless -d $dir;

    my $tmp = "$path.xcat.$$";
    open( my $fh, '>', $tmp ) or return { error => "Unable to write $tmp: $!" };
    print $fh $json;
    close($fh) or return { error => "Unable to close $tmp: $!" };
    my $permissions = _set_config_permissions($tmp);
    if ( $permissions->{error} ) {
        unlink $tmp;
        return $permissions;
    }

    if ( !$opts{skip_validate} ) {
        my $validation = $opts{validator}->($tmp);
        if ( $validation->{error} ) {
            unlink $tmp;
            return $validation;
        }
    }

    my $backup;
    if ( $opts{backup_existing} && -e $path ) {
        $backup = "$path.xcatbak";
        rename( $path, $backup ) or do {
            unlink $tmp;
            return { error => "Unable to back up $path to $backup: $!" };
        };
    }

    unless ( rename( $tmp, $path ) ) {
        my $rename_error = $!;
        rename( $backup, $path ) if $backup && -e $backup;
        unlink $tmp;
        return { error => "Unable to replace $path: $rename_error" };
    }

    return { path => $path, backup => $backup };
}

sub encode_config {
    my ( $self, $config ) = @_;
    return JSON->new->canonical->pretty->encode($config);
}

sub _decode_kea_json {
    my ($content) = @_;

    # Kea accepts JSON with C/C++ comments and trailing commas. JSON->relaxed
    # is backend-dependent, so normalize these Kea extensions explicitly before
    # handing the content to the strict decoder.
    return decode_json( _strip_json_trailing_commas( _strip_json_comments($content) ) );
}

sub _strip_json_comments {
    my ($content) = @_;

    my $out = '';
    my $in_string = 0;
    my $escaped = 0;
    my $length = length($content);

    for ( my $idx = 0; $idx < $length; $idx++ ) {
        my $char = substr( $content, $idx, 1 );
        my $next = $idx + 1 < $length ? substr( $content, $idx + 1, 1 ) : '';

        if ($in_string) {
            $out .= $char;
            if ($escaped) {
                $escaped = 0;
            } elsif ($char eq '\\') {
                $escaped = 1;
            } elsif ($char eq '"') {
                $in_string = 0;
            }
            next;
        }

        if ($char eq '"') {
            $in_string = 1;
            $out .= $char;
            next;
        }

        if ($char eq '/' && $next eq '/') {
            $idx += 2;
            $idx++ while $idx < $length && substr( $content, $idx, 1 ) !~ /\n/;
            $out .= "\n" if $idx < $length;
            next;
        }

        if ($char eq '/' && $next eq '*') {
            $idx += 2;
            while ( $idx < $length - 1 && substr( $content, $idx, 2 ) ne '*/' ) {
                $out .= "\n" if substr( $content, $idx, 1 ) eq "\n";
                $idx++;
            }
            $idx++ if $idx < $length;
            next;
        }

        $out .= $char;
    }

    return $out;
}

sub _strip_json_trailing_commas {
    my ($content) = @_;

    my $out = '';
    my $in_string = 0;
    my $escaped = 0;
    my $length = length($content);

    for ( my $idx = 0; $idx < $length; $idx++ ) {
        my $char = substr( $content, $idx, 1 );

        if ($in_string) {
            $out .= $char;
            if ($escaped) {
                $escaped = 0;
            } elsif ($char eq '\\') {
                $escaped = 1;
            } elsif ($char eq '"') {
                $in_string = 0;
            }
            next;
        }

        if ($char eq '"') {
            $in_string = 1;
            $out .= $char;
            next;
        }

        if ($char eq ',') {
            my $lookahead = $idx + 1;
            $lookahead++ while $lookahead < $length && substr( $content, $lookahead, 1 ) =~ /\s/;
            my $next = $lookahead < $length ? substr( $content, $lookahead, 1 ) : '';
            next if $next eq '}' || $next eq ']';
        }

        $out .= $char;
    }

    return $out;
}

sub write_ctrl_agent_config {
    my ( $self, $intent, %opts ) = @_;

    $opts{path} ||= $self->ctrl_agent_config_file();
    $opts{validator} ||= sub { $self->validate_ctrl_agent_config(@_) };
    return $self->_write_json_file( $self->render_ctrl_agent_config($intent), %opts );
}

sub validate_dhcp4_config {
    my ( $self, $path ) = @_;

    return $self->_validate_config_with( 'kea-dhcp4', 'Kea DHCPv4', $path );
}

sub validate_dhcp6_config {
    my ( $self, $path ) = @_;

    return $self->_validate_config_with( 'kea-dhcp6', 'Kea DHCPv6', $path );
}

sub validate_ddns_config {
    my ( $self, $path ) = @_;

    return $self->_validate_config_with( 'kea-dhcp-ddns', 'Kea DHCP-DDNS', $path );
}

sub validate_ctrl_agent_config {
    my ( $self, $path ) = @_;

    return $self->_validate_config_with( 'kea-ctrl-agent', 'Kea Control Agent', $path );
}

sub _validate_config_with {
    my ( $self, $command, $label, $path ) = @_;

    my $kea = _command_path($command);
    return { error => "Unable to validate $label configuration: $command was not found." } unless $kea;

    my $prefix = '';
    if ( $> == 0 ) {
        my $kea_user = _kea_user();
        my $runuser  = _command_path('runuser');
        # Validate as the daemon user when possible so root does not hide
        # packaged Kea runtime-directory or config-readability failures.
        $prefix = _shell_quote($runuser) . ' -u ' . _shell_quote($kea_user) . ' -- '
          if $kea_user && $runuser;
    }

    my $cmd = $prefix . _shell_quote($kea) . " -t " . _shell_quote($path) . " 2>&1";
    my $output = `$cmd`;
    my $rc = $? >> 8;
    return { error => "$label configuration validation failed: $output" } if $rc != 0;

    return { output => $output };
}

sub restart_services {
    my ( $self, %opts ) = @_;

    require xCAT::Utils;

    my @services;
    push @services, 'kea-dhcp-ddns'   if $opts{ddns};
    push @services, 'kea-dhcp4';
    push @services, 'kea-dhcp6'       if $opts{ipv6};
    push @services, 'kea-ctrl-agent'  if $opts{ctrl_agent};

    my @units;
    foreach my $service (@services) {
        my $unit = $self->_kea_service($service);
        push @units, $unit;
        if ( $opts{enable} ) {
            my $enable_ret = xCAT::Utils->enableservice($unit);
            return { error => "Failed to enable $unit." } if $enable_ret != 0;
        }
        my $ret;
        if ( xCAT::Utils->checkservicestatus($unit) == 0 ) {
            # Already running: reload the config (SIGHUP) instead of a full restart.
            # Kea reconfigures from the regenerated config file on SIGHUP, and -- unlike
            # restart -- this does not count against systemd's start-rate limit
            # (StartLimitBurst=5/10s on EL). A burst of makedhcp calls (e.g. the
            # makedhcp_remote_network test loop, or rapid provisioning) would otherwise
            # trip that limit and fail with "Failed to restart kea-dhcp4".
            xCAT::Utils->runcmd("systemctl reload $unit", -1);
            $ret = $::RUNCMD_RC;
        }
        if ( !defined($ret) || $ret != 0 ) {
            # Not running (first start) or reload failed: clear any start-limit latch,
            # then do a full restart.
            xCAT::Utils->runcmd("systemctl reset-failed $unit", -1);
            $ret = xCAT::Utils->restartservice($unit);
        }
        return { error => "Failed to restart $unit." } if $ret != 0;
    }

    return { services => \@units };
}

sub check_services {
    my ( $self, %opts ) = @_;

    require xCAT::Utils;

    my @services = ('kea-dhcp4');
    push @services, 'kea-dhcp6' if $opts{ipv6};

    my @units;
    foreach my $service (@services) {
        my $unit = $self->_kea_service($service);
        push @units, $unit;
        my $ret = xCAT::Utils->checkservicestatus($unit);
        return { error => "$unit is not running. Please start the Kea DHCP service." } if $ret != 0;
    }

    return { services => \@units };
}

sub upsert_reservations {
    my ( $self, $config, $reservations ) = @_;

    foreach my $reservation (@$reservations) {
        $self->delete_reservations($config, $reservation);
        my $subnet = _find_subnet_by_id( $config, $reservation->{'subnet-id'} );
        next unless $subnet;
        $subnet->{reservations} ||= [];
        $subnet->{reservations} = [
            grep { !_reservation_matches( $_, $reservation ) } @{ $subnet->{reservations} }
        ];

        my %stored = %$reservation;
        delete $stored{'subnet-id'};
        push @{ $subnet->{reservations} }, \%stored;
    }

    return $config;
}

sub delete_reservations {
    my ( $self, $config, $match ) = @_;

    my @deleted;
    foreach my $subnet ( _subnets_for_config($config) ) {
        my @kept;
        foreach my $reservation ( @{ $subnet->{reservations} || [] } ) {
            if ( _reservation_matches( $reservation, $match ) ) {
                push @deleted, { %$reservation, 'subnet-id' => $subnet->{id} };
            } else {
                push @kept, $reservation;
            }
        }
        $subnet->{reservations} = \@kept;
    }

    return \@deleted;
}

sub query_reservations {
    my ( $self, $config, $match ) = @_;

    my @found;
    foreach my $subnet ( _subnets_for_config($config) ) {
        foreach my $reservation ( @{ $subnet->{reservations} || [] } ) {
            if ( _reservation_matches( $reservation, $match ) ) {
                push @found, { %$reservation, 'subnet-id' => $subnet->{id}, subnet => $subnet->{subnet} };
            }
        }
    }

    return \@found;
}

sub subnet_id_for_ip {
    my ( $self, $config, $ip ) = @_;

    return unless defined($ip) && $ip ne '';
    my $ip_number = xCAT::NetworkUtils::getipaddr( $ip, GetNumber => 1 );
    return unless defined($ip_number);
    my $bits = $ip =~ /:/ ? 128 : 32;

    foreach my $subnet ( _subnets_for_config($config) ) {
        next unless $subnet->{subnet} && $subnet->{subnet} =~ m{^([^/]+)/(\d+)$};
        my ( $network, $prefix ) = ( $1, $2 );
        next if ( $network =~ /:/ ? 128 : 32 ) != $bits;
        my $network_number = xCAT::NetworkUtils::getipaddr( $network, GetNumber => 1 );
        next unless defined($network_number);

        my $mask = Math::BigInt->new( "0b" . ( "1" x $prefix ) . ( "0" x ( $bits - $prefix ) ) );
        return $subnet->{id} if ( $ip_number & $mask ) == ( $network_number & $mask );
    }

    return;
}

sub control_agent_url {
    my ( $self, %opts ) = @_;

    my $host = $opts{host} || $self->{control_agent_host} || '127.0.0.1';
    my $port = $opts{port} || $self->{control_agent_port} || 8000;
    return "http://$host:$port/";
}

sub control_agent_command {
    my ( $self, $command, $arguments, %opts ) = @_;

    my $payload = {
        command   => $command,
        arguments => $arguments || {},
    };
    $payload->{service} = $opts{service} if $opts{service};

    if ( $self->{control_agent_handler} ) {
        return $self->{control_agent_handler}->($payload, \%opts);
    }

    eval { require HTTP::Tiny; };
    return { error => "Unable to use Kea Control Agent: HTTP::Tiny is not installed." } if $@;

    my $response = HTTP::Tiny->new( timeout => $opts{timeout} || 10 )->post(
        $opts{url} || $self->control_agent_url(%opts),
        {
            headers => {
                'Content-Type' => 'application/json',
            },
            content => $self->encode_config($payload),
        }
    );

    return { error => "Kea Control Agent request failed: $response->{reason}" } unless $response->{success};

    my $decoded = eval { decode_json( $response->{content} ) };
    return { error => "Unable to parse Kea Control Agent response: $@" } if $@;

    return $self->_normalize_control_agent_response($decoded);
}

sub live_upsert_reservations {
    my ( $self, $reservations, %opts ) = @_;

    my $service = $opts{service} || ['dhcp4'];
    foreach my $reservation (@$reservations) {
        my $delete = $self->_live_delete_reservation($reservation, service => $service, ignore_not_found => 1);
        return $delete if $delete->{error};

        my %stored = %$reservation;
        my $result = $self->control_agent_command(
            'reservation-add',
            {
                reservation        => \%stored,
                'operation-target' => 'memory',
            },
            service => $service,
        );
        return $result if $result->{error};
    }

    return { ok => 1 };
}

sub live_delete_reservations {
    my ( $self, $reservations, %opts ) = @_;

    my $service = $opts{service} || ['dhcp4'];
    foreach my $reservation (@$reservations) {
        my $result = $self->_live_delete_reservation($reservation, service => $service, ignore_not_found => 1);
        return $result if $result->{error};
    }

    return { ok => 1 };
}

sub _live_delete_reservation {
    my ( $self, $reservation, %opts ) = @_;

    return { ok => 1 } unless defined $reservation->{'subnet-id'};

    my %arguments = (
        'subnet-id'        => $reservation->{'subnet-id'},
        'operation-target' => 'memory',
    );
    if ( $reservation->{'hw-address'} ) {
        $arguments{'identifier-type'} = 'hw-address';
        $arguments{identifier} = $reservation->{'hw-address'};
    } elsif ( $reservation->{duid} ) {
        $arguments{'identifier-type'} = 'duid';
        $arguments{identifier} = $reservation->{duid};
    } elsif ( $reservation->{'ip-address'} ) {
        $arguments{'ip-address'} = $reservation->{'ip-address'};
    } elsif ( ref( $reservation->{'ip-addresses'} ) eq 'ARRAY' && @{ $reservation->{'ip-addresses'} } ) {
        $arguments{'ip-address'} = $reservation->{'ip-addresses'}[0];
    } else {
        return { ok => 1 };
    }

    my $result = $self->control_agent_command(
        'reservation-del',
        \%arguments,
        service => $opts{service} || ['dhcp4'],
    );
    return { ok => 1 } if $opts{ignore_not_found} && _control_agent_not_found($result);
    return $result if $result->{error};
    return { ok => 1 };
}

sub _render_subnet4 {
    my ( $self, $subnet ) = @_;

    my %rendered = (
        id     => _integer( $subnet->{id} ),
        subnet => $subnet->{subnet},
    );

    $rendered{interface}        = $subnet->{interface} if defined $subnet->{interface};
    $rendered{'next-server'}    = _first_defined( $subnet->{'next-server'},    $subnet->{next_server} );
    $rendered{'boot-file-name'} = _first_defined( $subnet->{'boot-file-name'}, $subnet->{boot_file_name} );
    $rendered{'option-data'} = _first_defined( $subnet->{'option-data'}, $subnet->{option_data} );
    my $additional_classes = _first_defined(
        $subnet->{additional_client_classes},
        $subnet->{'evaluate-additional-classes'},
        $subnet->{evaluate_additional_classes},
        $subnet->{'require-client-classes'},
        $subnet->{require_client_classes},
    );
    $rendered{ $self->_additional_class_list_field() } = $additional_classes if defined $additional_classes;
    $rendered{reservations} = $subnet->{reservations} if $subnet->{reservations};
    delete $rendered{'next-server'}    unless defined $rendered{'next-server'};
    delete $rendered{'boot-file-name'} unless defined $rendered{'boot-file-name'};
    delete $rendered{'option-data'}    unless defined $rendered{'option-data'};

    if ( $subnet->{pools} ) {
        $rendered{pools} = $subnet->{pools};
    } elsif ( $subnet->{dynamicrange} ) {
        $rendered{pools} = [ xCAT::DHCP::Range->kea_pools( $subnet->{dynamicrange} ) ];
    } else {
        $rendered{pools} = [];
    }

    return \%rendered;
}

sub _render_client_class {
    my ( $self, $client_class ) = @_;

    my %rendered = %$client_class;
    my $additional_only = _first_defined(
        $client_class->{additional_only},
        $client_class->{'only-in-additional-list'},
        $client_class->{only_in_additional_list},
        $client_class->{'only-if-required'},
        $client_class->{only_if_required},
    );

    delete @rendered{qw/additional_only only_in_additional_list only_if_required/};
    delete $rendered{'only-in-additional-list'};
    delete $rendered{'only-if-required'};
    $rendered{ $self->_additional_class_flag_field() } = $additional_only if defined $additional_only;

    return \%rendered;
}

sub _render_subnet6 {
    my ( $self, $subnet ) = @_;

    my %rendered = (
        id     => _integer( $subnet->{id} ),
        subnet => $subnet->{subnet},
    );

    $rendered{interface}     = $subnet->{interface} if defined $subnet->{interface};
    $rendered{'option-data'} = _first_defined( $subnet->{'option-data'}, $subnet->{option_data} );
    $rendered{reservations}  = $subnet->{reservations} if $subnet->{reservations};
    delete $rendered{'option-data'} unless defined $rendered{'option-data'};

    if ( $subnet->{pools} ) {
        $rendered{pools} = $subnet->{pools};
    } elsif ( $subnet->{dynamicrange} ) {
        $rendered{pools} = [ xCAT::DHCP::Range->kea_pools( $subnet->{dynamicrange} ) ];
    } else {
        $rendered{pools} = [];
    }

    return \%rendered;
}

sub _find_subnet_by_id {
    my ( $config, $subnet_id ) = @_;

    return unless defined($subnet_id);
    foreach my $subnet ( _subnets_for_config($config) ) {
        return $subnet if defined( $subnet->{id} ) && $subnet->{id} == $subnet_id;
    }

    return;
}

sub _subnets_for_config {
    my ($config) = @_;

    return @{ $config->{Dhcp4}{subnet4} || [] } if $config->{Dhcp4};
    return @{ $config->{Dhcp6}{subnet6} || [] } if $config->{Dhcp6};
    return;
}

sub _reservation_matches {
    my ( $reservation, $match ) = @_;

    foreach my $field ( 'hostname', 'hw-address', 'duid', 'ip-address' ) {
        next unless defined $match->{$field} && $match->{$field} ne '';
        return 1 if defined $reservation->{$field} && lc( $reservation->{$field} ) eq lc( $match->{$field} );
    }
    if ( defined $match->{'ip-address'} && ref( $reservation->{'ip-addresses'} ) eq 'ARRAY' ) {
        foreach my $ip ( @{ $reservation->{'ip-addresses'} } ) {
            return 1 if lc($ip) eq lc( $match->{'ip-address'} );
        }
    }

    return 0;
}

sub _normalize_control_agent_response {
    my ( $self, $decoded ) = @_;

    my $item = ref($decoded) eq 'ARRAY' ? $decoded->[0] : $decoded;
    return { error => 'Kea Control Agent response was empty.' } unless ref($item) eq 'HASH';

    return {
        ok       => defined( $item->{result} ) && $item->{result} == 0 ? 1 : 0,
        result   => $item->{result},
        text     => $item->{text},
        response => $decoded,
        error    => defined( $item->{result} ) && $item->{result} == 0 ? undef : ( $item->{text} || 'Kea Control Agent command failed.' ),
    };
}

sub _control_agent_not_found {
    my ($result) = @_;

    return 0 unless $result && $result->{error};
    return 1 if defined( $result->{result} ) && $result->{result} == 3;
    return 1 if defined( $result->{text} ) && $result->{text} =~ /not\s+(?:deleted|found)/i;
    return 0;
}

sub _additional_class_flag_field {
    my ($self) = @_;

    return $self->_use_modern_additional_class_syntax() ? 'only-in-additional-list' : 'only-if-required';
}

sub _additional_class_list_field {
    my ($self) = @_;

    return $self->_use_modern_additional_class_syntax() ? 'evaluate-additional-classes' : 'require-client-classes';
}

sub _use_modern_additional_class_syntax {
    my ($self) = @_;

    return 1 if $self->{additional_class_syntax} && $self->{additional_class_syntax} eq 'modern';
    return 0 if $self->{additional_class_syntax} && $self->{additional_class_syntax} eq 'legacy';

    my $version = $self->kea_version();
    return _version_at_least( $version, '2.7.4' );
}

sub kea_version {
    my ($self) = @_;

    return $self->{kea_version} if defined $self->{kea_version};
    return $self->{_detected_kea_version} if defined $self->{_detected_kea_version};

    my $command = $self->{kea_dhcp4_command} || _command_path('kea-dhcp4');
    return unless $command;

    my $output = '';
    if ( open( my $version_fh, '-|', $command, '-V' ) ) {
        local $/;
        $output = <$version_fh> || '';
        close($version_fh);
    }

    if ( $output =~ /(\d+(?:\.\d+){1,2})/ ) {
        $self->{_detected_kea_version} = $1;
    }

    return $self->{_detected_kea_version};
}

sub _first_defined {
    my @values = @_;
    foreach my $value (@values) {
        return $value if defined $value;
    }

    return;
}

sub _version_at_least {
    my ( $version, $minimum ) = @_;

    return 0 unless defined($version) && $version =~ /^\d+(?:\.\d+)*/;

    my @version_parts = split /\./, $version;
    my @minimum_parts = split /\./, $minimum;
    my $max = @version_parts > @minimum_parts ? @version_parts : @minimum_parts;

    for my $idx ( 0 .. $max - 1 ) {
        my $left  = $version_parts[$idx]  || 0;
        my $right = $minimum_parts[$idx] || 0;
        return 1 if $left > $right;
        return 0 if $left < $right;
    }

    return 1;
}

sub _integer {
    my ($value) = @_;

    return $value unless defined($value) && $value =~ /^\d+$/;
    return 0 + $value;
}

sub _json_bool {
    my ($value) = @_;

    return $value if ref($value) eq 'JSON::PP::Boolean' || ref($value) eq 'JSON::Boolean';
    return $value ? JSON::true : JSON::false;
}

sub _set_config_permissions {
    my ($path) = @_;

    if ($> != 0) {
        chmod 0644, $path or return { error => "Unable to set $path permissions to 0644: $!" };
        return { ok => 1 };
    }

    my ( $group, $gid ) = _kea_group();
    if ( defined($gid) ) {
        chown 0, $gid, $path or return { error => "Unable to set $path ownership to root:$group: $!" };
        chmod 0640, $path or return { error => "Unable to set $path permissions to 0640: $!" };
    } else {
        chmod 0644, $path or return { error => "Unable to set $path permissions to 0644: $!" };
    }

    return { ok => 1 };
}

sub _kea_group {
    foreach my $group ( 'kea', '_kea' ) {
        my @entry = getgrnam($group);
        return ( $entry[0], $entry[2] ) if @entry;
    }

    return;
}

sub _kea_user {
    foreach my $user ( 'kea', '_kea' ) {
        my @entry = getpwnam($user);
        return $entry[0] if @entry;
    }

    return;
}

sub _kea_service {
    my ( $self, $service ) = @_;

    # Kea service names are package-specific, not strictly distribution-specific.
    # Prefer the unit that is actually installed so derivatives, backports, and
    # locally rebuilt packages do not need a distro/version decision tree here.
    foreach my $candidate ( @{ $KEA_SERVICE_CANDIDATES{$service} || [$service] } ) {
        return $candidate if $self->_service_available($candidate);
    }

    return $service;
}

sub _service_available {
    my ( $self, $service ) = @_;

    my $unit = "$service.service";
    foreach my $dir ( @{ $self->{service_unit_dirs} || _systemd_unit_dirs() } ) {
        return 1 if -e "$dir/$unit";
    }

    return 1 if -x "/etc/init.d/$service";

    return 0;
}

sub _systemd_unit_dirs {
    return [
        '/etc/systemd/system',
        '/run/systemd/system',
        '/usr/lib/systemd/system',
        '/lib/systemd/system',
    ];
}

sub _kea_socket_dir {
    my ($self) = @_;

    return $self->{kea_socket_dir} if defined $self->{kea_socket_dir};

    # Kea validates Control Agent sockets against its packaged runtime
    # directory, and newer packages reject /var/run/kea even when it resolves
    # to /run/kea. Keep the legacy path as the unknown-state fallback for
    # older Kea builds that validate before the runtime directory exists.
    foreach my $dir ( @{ $self->{kea_socket_dirs} || [ '/run/kea', '/var/run/kea' ] } ) {
        return $dir if -d $dir;
    }

    return '/var/run/kea';
}

sub _kea_control_socket {
    my ( $self, $socket_name ) = @_;

    return $self->_kea_socket_dir() . "/$socket_name";
}

sub _command_path {
    my ($command) = @_;

    foreach my $dir ( split /:/, $ENV{PATH} || '' ) {
        next unless $dir;
        my $path = "$dir/$command";
        return $path if -x $path;
    }

    foreach my $path ( "/usr/sbin/$command", "/usr/bin/$command", "/sbin/$command", "/bin/$command" ) {
        return $path if -x $path;
    }

    return;
}

sub _shell_quote {
    my ($value) = @_;

    $value =~ s/'/'\\''/g;
    return "'$value'";
}

1;
