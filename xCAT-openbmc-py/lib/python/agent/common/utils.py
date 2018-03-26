#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#
import struct
import sys
import inspect
import re
import logging
from logging.handlers import SysLogHandler

XCAT_LOG_FMT = logging.Formatter("%(asctime)s %(levelname)s " +
                                 "%(name)s %(process)d " +
                                 "(%(filename)s:%(lineno)d) "+
                                 "%(message)s")
XCAT_LOG_FMT.datefmt = '%Y-%m-%d %H:%M:%S'

def getxCATLog(name=None):
    xl = logging.getLogger(name)
    xl.fmt = XCAT_LOG_FMT
    return xl

def enableSyslog(name='xcat'):
    h = SysLogHandler(address='/dev/log', facility=SysLogHandler.LOG_LOCAL4)
    h.setFormatter(logging.Formatter('%s: ' % name + '%(levelname)s %(message)s'))
    logging.getLogger('xcatagent').addHandler(h)

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

def emb_numbers(string):
    re_digits = re.compile(r'(\d+)')
    pieces = re_digits.split(string)
    pieces[1::2] = map(int,pieces[1::2])
    return pieces

def sort_string_with_numbers(origin_list):
    new_list = [(emb_numbers(string),string) for string in origin_list]
    new_list.sort()
    return [string for __,string in new_list]

class Messager(object):
    def __init__(self, name=None):
        self.logger = logging.getLogger(name or 'xcatagent')

    def info(self, msg):
        self.logger.info(msg)

    def warn(self, msg):
        self.logger.warn(msg)

    def error(self, msg, node=''):
        if node:
            self.logger.error('%s: Error: %s' % (node, msg))
        else:
            self.logger.error('Error: %s' % msg)

    def syslog(self, msg):
        pass

    def update_node_attributes(self, attribute, node, data):
        pass
