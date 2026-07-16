use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::DHCP::Backend;

is( xCAT::DHCP::Backend->normalize(undef), 'auto', 'undefined backend defaults to auto' );
is( xCAT::DHCP::Backend->normalize(' ISC '), 'isc', 'backend values are trimmed and lowercased' );
is( xCAT::DHCP::Backend->normalize('kea'), 'kea', 'kea is valid' );
is( xCAT::DHCP::Backend->normalize('bogus'), undef, 'invalid backend is rejected' );

is(
    xCAT::DHCP::Backend->default_backend( platform => 'el9', os => 'rhel9', os_name => 'rhel', version => 9 ),
    'isc',
    'EL9 defaults to ISC'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => 'el10', os => 'rhel10', os_name => 'rhel', version => 10 ),
    'kea',
    'EL10 defaults to Kea by platform'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => 'el11', os => 'rhel11', os_name => 'rhel', version => 11 ),
    'kea',
    'EL releases newer than EL10 default to Kea by platform'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'rocky10', os_name => 'rocky', version => 10 ),
    'kea',
    'EL10 derivatives default to Kea by osver'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'alma11', os_name => 'alma', version => 11 ),
    'kea',
    'EL derivatives newer than EL10 default to Kea by osver'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'ubuntu22.04', os_name => 'ubuntu', version => '22.04' ),
    'kea',
    'Ubuntu 22.04 defaults to Kea'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'ubuntu22.04.5', os_name => 'ubuntu', version => '22.04.5' ),
    'kea',
    'Ubuntu 22.04 point releases default to Kea'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'ubuntu20.04', os_name => 'ubuntu', version => '20.04' ),
    'isc',
    'Ubuntu 20.04 defaults to ISC'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'ubuntu24.04', os_name => 'ubuntu', version => '24.04' ),
    'kea',
    'Ubuntu 24.04 defaults to Kea'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'ubuntu24.04', os_name => 'ubuntu', version => '24.04.4' ),
    'kea',
    'Ubuntu 24.04 point releases default to Kea'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'ubuntu24.04', os_name => 'ubuntu', version => '24' ),
    'isc',
    'Ubuntu major-only version is not treated as a date-based release'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'ubuntu24.10', os_name => 'ubuntu', version => '24.10' ),
    'kea',
    'Ubuntu releases newer than 24.04 default to Kea'
);

is(
    xCAT::DHCP::Backend->default_backend( platform => '', os => 'ubuntu26.04', os_name => 'ubuntu', version => '26.04' ),
    'kea',
    'Ubuntu LTS releases newer than 24.04 default to Kea'
);

is(
    xCAT::DHCP::Backend->default_backend(
        platform => '',
        os       => 'sles12',
        os_name  => 'sles',
        version  => 12
    ),
    'isc',
    'SLES 12 defaults to ISC'
);

is(
    xCAT::DHCP::Backend->default_backend(
        platform => '',
        os       => 'sles15',
        os_name  => 'sles',
        version  => 15
    ),
    'isc',
    'SLES 15 defaults to ISC'
);

is(
    xCAT::DHCP::Backend->default_backend(
        platform => '',
        os       => 'opensuse-leap15',
        os_name  => 'opensuse-leap',
        version  => 15
    ),
    'isc',
    'openSUSE Leap 15 defaults to ISC'
);

is(
    xCAT::DHCP::Backend->choose( requested => 'isc', os => 'rhel10', platform => 'el10' )->{name},
    'isc',
    'explicit ISC override wins on EL10'
);

is(
    xCAT::DHCP::Backend->choose( requested => 'kea', os => 'rhel9', platform => 'el9' )->{name},
    'kea',
    'explicit Kea override wins on EL9'
);

is(
    xCAT::DHCP::Backend->choose( requested => 'auto', os => 'rhel9', platform => 'el9' )->{name},
    'isc',
    'auto selects ISC on EL9'
);

is(
    xCAT::DHCP::Backend->choose( requested => 'auto', os => 'rhel10', platform => 'el10' )->{name},
    'kea',
    'auto selects Kea on EL10'
);

is(
    xCAT::DHCP::Backend->choose( requested => 'auto', os => 'ubuntu24.04', os_name => 'ubuntu', version => '24.04' )->{name},
    'kea',
    'auto selects Kea on Ubuntu 24.04'
);

is(
    xCAT::DHCP::Backend->choose( requested => 'auto', os => 'ubuntu22.04', os_name => 'ubuntu', version => '22.04' )->{name},
    'kea',
    'auto selects Kea on Ubuntu 22.04'
);

like(
    xCAT::DHCP::Backend->choose( requested => 'invalid' )->{error},
    qr/Invalid site\.dhcpbackend/,
    'invalid explicit backend returns a clear error'
);

like(
    xCAT::DHCP::Backend->choose(
        requested       => 'kea',
        check_available => 1,
        available       => { kea => 0 },
    )->{error},
    qr/not available/,
    'unavailable forced backend returns a clear error'
);

is(
    xCAT::DHCP::Backend->choose(
        requested       => 'kea',
        check_available => 1,
        available       => { kea => 1 },
    )->{name},
    'kea',
    'forced Kea succeeds when available'
);

done_testing();
