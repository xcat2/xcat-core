import unittest

import helper                                    # noqa: F401  (sets sys.path)

from dhcptest_lib import options
from dhcptest_lib.errors import ConfigError


class OptionNames(unittest.TestCase):

    def test_resolves_numbers_names_and_prefixed_forms(self):
        self.assertEqual(options.option_code(54), 54)
        self.assertEqual(options.option_code("54"), 54)
        self.assertEqual(options.option_code("0x36"), 54)
        self.assertEqual(options.option_code("server_id"), 54)
        self.assertEqual(options.option_code("server-id"), 54)
        self.assertEqual(options.option_code("option:server_id"), 54)

    def test_rejects_nonsense(self):
        self.assertRaises(ConfigError, options.option_code, "not_an_option")
        self.assertRaises(ConfigError, options.option_code, "256")

    def test_message_type_round_trip(self):
        self.assertEqual(options.msgtype_code("offer"), 2)
        self.assertEqual(options.msgtype_name(2), "OFFER")
        self.assertEqual(options.msgtype_name(99), "TYPE-99")


class ClientFqdn(unittest.TestCase):
    """Option 81, RFC 4702: who names the node, and who updates DNS."""

    def test_a_bare_name_is_sent_with_no_flags(self):
        self.assertEqual(options.encode_fqdn("node01"),
                         b"\x00\x00\x00node01")

    def test_flags_are_taken_from_the_prefix(self):
        self.assertEqual(options.encode_fqdn("S:node01")[0], 0x01)
        self.assertEqual(options.encode_fqdn("N:node01")[0], 0x08)
        self.assertEqual(options.encode_fqdn("SO:node01")[0], 0x03)

    def test_a_name_with_a_colon_is_not_read_as_flags(self):
        # The prefix is flags only when every character before the colon is a
        # flag letter. Otherwise a name is a name.
        flags, name = options.decode_fqdn(options.encode_fqdn("host:1"))
        self.assertEqual((flags, name), (0, "host:1"))

    def test_a_prefix_that_is_not_all_flag_letters_is_part_of_the_name(self):
        # There is no way to tell a typo'd flag from a name that holds a colon,
        # so the rule is mechanical: flags only when every character before the
        # first colon is one. A mistyped flag then sends a name no server
        # answers with, which fails the step rather than passing it quietly.
        flags, name = options.decode_fqdn(options.encode_fqdn("SX:node01"))
        self.assertEqual((flags, name), (0, "SX:node01"))

    def test_an_unknown_flag_letter_is_refused_when_it_is_read_as_flags(self):
        self.assertRaises(ConfigError, options.fqdn_flag_bits, "SX")

    def test_the_e_flag_sends_the_name_in_wire_format(self):
        raw = options.encode_fqdn("SE:node01.cluster.local")
        self.assertEqual(raw[0], 0x05)
        self.assertEqual(raw[3:], b"\x06node01\x07cluster\x05local\x00")
        self.assertEqual(options.decode_fqdn(raw),
                         (0x05, "node01.cluster.local"))

    def test_the_option_decodes_to_the_name_a_scenario_asserts_on(self):
        # The flags are reached through `fqdn_flags`, so the option itself is
        # the name and `option:81 == node01` reads as it should.
        raw = b"\x03\x00\x00node01.cluster.local."
        self.assertEqual(options.decode_value(81, raw),
                         "node01.cluster.local.")

    def test_flag_letters_round_trip(self):
        self.assertEqual(options.fqdn_flag_letters(0x03), "SO")
        self.assertEqual(options.fqdn_flag_letters(0), "-")
        self.assertEqual(options.fqdn_flag_bits("so"), 0x03)

    def test_a_truncated_option_is_left_as_hex(self):
        self.assertIsNone(options.decode_fqdn(b"\x03\x00"))
        self.assertEqual(options.decode_value(81, b"\x03\x00"), "03:00")


class OptionArea(unittest.TestCase):

    def test_pack_then_unpack(self):
        blob = options.pack_options([(53, b"\x02"), (54, b"\x0a\x00\x00\x01")])
        self.assertTrue(blob.endswith(b"\xff"))
        found = options.unpack_options(blob)
        self.assertEqual(found[53], b"\x02")
        self.assertEqual(found[54], b"\x0a\x00\x00\x01")

    def test_unpack_tolerates_magic_padding_and_missing_end(self):
        blob = options.MAGIC + b"\x00\x00" + bytes([53, 1, 5])
        self.assertEqual(options.unpack_options(blob), {53: b"\x05"})

    def test_unpack_concatenates_a_split_option(self):
        # RFC 3396: a long option may arrive as several instances.
        blob = bytes([60, 2]) + b"PX" + bytes([60, 7]) + b"EClient"
        self.assertEqual(options.unpack_options(blob)[60], b"PXEClient")

    def test_decode_value_types(self):
        self.assertEqual(options.decode_value(1, b"\xff\xff\xff\x00"),
                         "255.255.255.0")
        self.assertEqual(options.decode_value(51, b"\x00\x00\xa8\xc0"), 43200)
        self.assertEqual(options.decode_value(93, b"\x00\x0b"), 11)
        self.assertEqual(options.decode_value(60, b"PXEClient"), "PXEClient")
        self.assertEqual(options.decode_value(55, b"\x01\x03\x06"), [1, 3, 6])
        # An address-list option is a list even when it holds one address:
        # option 3 arriving as raw hex was a real bug.
        self.assertEqual(options.decode_value(3, b"\x0a\x63\x00\x01"),
                         ["10.99.0.1"])
        self.assertEqual(
            options.decode_value(6, b"\x0a\x00\x00\x01\x0a\x00\x00\x02"),
            ["10.0.0.1", "10.0.0.2"])
        self.assertEqual(options.decode_value(175, b"\xab\xcd"), "ab:cd")


class NameLists(unittest.TestCase):
    """Option 119, the domain search list: RFC 1035 labels, RFC 3397 pointers."""

    def test_uncompressed_names(self):
        raw = (b"\x03foo\x03com\x00" b"\x03bar\x03com\x00")
        self.assertEqual(options.decode_value(119, raw), ["foo.com", "bar.com"])

    def test_a_compression_pointer_is_followed(self):
        # "bar.com" written as the label "bar" plus a pointer to the "com" at
        # offset 4 -- which is what a server that compresses actually sends.
        raw = b"\x03foo\x03com\x00" + b"\x03bar" + b"\xc0\x04"
        self.assertEqual(options.decode_value(119, raw), ["foo.com", "bar.com"])

    def test_a_pointer_loop_falls_back_to_hex_instead_of_hanging(self):
        raw = b"\x03foo" + b"\xc0\x00"
        self.assertEqual(options.decode_value(119, raw), "03:66:6f:6f:c0:00")

    def test_a_truncated_name_falls_back_to_hex(self):
        raw = b"\x09foo"
        self.assertEqual(options.decode_value(119, raw), "09:66:6f:6f")


class _FakeBootp(object):
    """Enough of a BOOTP layer for `decode`, without needing scapy."""

    def __init__(self, option_area):
        self.payload = option_area
        self.xid = 0x1234
        self.yiaddr = "10.0.0.2"
        self.siaddr = "10.0.0.1"
        self.ciaddr = "0.0.0.0"
        self.giaddr = "0.0.0.0"
        self.chaddr = b"\x02\x00\x11\x22\x33\x44" + b"\x00" * 10
        self.file = b"pxelinux.0" + b"\x00" * 118
        self.sname = b"\x00" * 64
        self.secs = 0
        self.flags = 0

    def __getitem__(self, _layer):
        return self


class MessageTypeOfAReply(unittest.TestCase):

    def _reply(self, option_area):
        return options.decode(_FakeBootp(option_area))

    def test_a_dhcp_reply_is_named_by_option_53(self):
        reply = self._reply(options.pack_options([(53, b"\x02")]))
        self.assertEqual(reply.msgtype, "OFFER")

    def test_a_reply_with_no_option_53_is_plain_bootp(self):
        # Hardware predating DHCP sends a BOOTREQUEST with no option 53, and
        # the answer carries none either. Reporting that as a missing message
        # type would read as a malformed packet rather than as BOOTP working,
        # and there would be nothing for a step to assert on.
        reply = self._reply(options.MAGIC + b"\xff")
        self.assertEqual(reply.msgtype, "BOOTREPLY")
        self.assertEqual(reply.bootfile(), "pxelinux.0")


if __name__ == "__main__":
    unittest.main()
