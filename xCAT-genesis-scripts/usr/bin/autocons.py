import os
import struct
import termios

addrtoname = {
    0x3f8: '/dev/ttyS0',
    0x2f8: '/dev/ttyS1',
    0x3e8: '/dev/ttyS2',
    0x2e8: '/dev/ttyS3',
}
speedmap = {
    0: None,
    3: 9600,
    4: 19200,
    6: 57600,
    7: 115200,
}

termiobaud = {
    9600: termios.B9600,
    19200: termios.B19200,
    57600: termios.B57600,
    115200: termios.B115200,
}

def do_serial_config():
    if 'console=ttyS' in open('/proc/cmdline').read():
        return None # Do not do autoconsole if manually configured
    spcr = open("/sys/firmware/acpi/tables/SPCR", "rb")
    spcr = bytearray(spcr.read())
    if spcr[8] != 2 or spcr[36] != 0 or spcr[40] != 1:
        return None
    address = struct.unpack('<Q', spcr[44:52])[0]
    tty = None
    try:
        tty = addrtoname[address]
    except KeyError:
        return None
    retval = { 'tty': tty }
    try:
        retval['speed'] = speedmap[spcr[58]]
    except KeyError:
        return None
    if retval['speed']:
        ttyf = os.open(tty, os.O_RDWR | os.O_NOCTTY)
        currattr = termios.tcgetattr(ttyf)
        currattr[4:6] = [0, termiobaud[retval['speed']]]
        termios.tcsetattr(ttyf, termios.TCSANOW, currattr)
    return retval


if __name__ == '__main__':
    serialinfo = do_serial_config()
    if serialinfo:
        os.execl(
            '/bin/setsid', 'setsid', 'sh', '-c',
            'exec screen -x console <> {0} >&0 2>&1'.format(serialinfo['tty']))

