import fcntl
import os
import signal
import struct
import subprocess
import termios
import time

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
    retval['connected'] = bool(struct.unpack('<I', fcntl.ioctl(
        ttyf, termios.TIOCMGET, '\x00\x00\x00\x00'))[0] & termios.TIOCM_CAR)
    os.close(ttyf)
    return retval

def is_connected(tty):
    ttyf = os.open(tty, os.O_RDWR | os.O_NOCTTY)
    retval = bool(struct.unpack('<I', fcntl.ioctl(
        ttyf, termios.TIOCMGET, '\x00\x00\x00\x00'))[0] & termios.TIOCM_CAR)
    os.close(ttyf)
    return retval


if __name__ == '__main__':
    serialinfo = do_serial_config()
    if serialinfo:
        running = False
        while True:
            if running and running.poll() is not None:
                running = False
            if running and not is_connected(serialinfo['tty']):
                try:
                    running.terminate()
                    running.wait()
                except Exception:
                    pass
                time.sleep(0.5)
                running = subprocess.Popen(['/bin/sh', '-c',  'exec screen -x console <> {0} >&0 2>&1'.format(serialinfo['tty'])])
                time.sleep(0.5)
                try:
                    running.terminate()
                    running.wait()
                except Exception:
                    pass
                running = False
            elif not running and is_connected(serialinfo['tty']):
                running = subprocess.Popen(['/bin/sh', '-c',  'exec screen -x console <> {0} >&0 2>&1'.format(serialinfo['tty'])])
            time.sleep(0.5)
