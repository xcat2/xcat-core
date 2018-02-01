import struct
import sys
import inspect
import logging


def int2bytes(num):
    return struct.pack('i', num)


def bytes2int(buf):
    return struct.unpack('i', buf)[0]


def get_classes(module_name):
    ret = []
    for name, obj in inspect.getmembers(sys.modules[module_name]):
        if inspect.isclass(obj):
            ret.append(obj)

    return ret


def class_func(module_name, class_name):
    func = getattr(sys.modules[module_name], class_name)
    return func


def recv_all(sock, size):
    recv_size = 4096
    buf_size = 0
    buf_parts = []
    while buf_size < size:
        tmp_size = recv_size
        left_size = size - buf_size
        if left_size < recv_size:
            tmp_size = left_size
        buf_part = sock.recv(tmp_size)
        buf_parts.append(buf_part)
        buf_size += len(buf_part)
    buf = ''.join(buf_parts)
    return buf


def update2Ddict(updata_dict, key_a, key_b, value):
    if key_a in updata_dict:
        updata_dict[key_a].update({key_b: value})
    else: 
        updata_dict.update({key_a: {key_b: value}})

class Messager(object):
    def __init__(self, name=None):
        self.logger = logging.getLogger(name or 'xcatagent')

    def info(self, msg):
        self.logger.info(msg)

    def warn(self, msg):
        self.logger.warn(msg)

    def error(self, msg):
        self.logger.error(msg)

    def syslog(self, msg):
        pass

    def update_node_attributes(self, attribute, node, data):
        pass
