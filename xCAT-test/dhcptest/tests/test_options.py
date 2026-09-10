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


if __name__ == "__main__":
    unittest.main()
