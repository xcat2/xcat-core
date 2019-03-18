# -*- encoding: utf-8 -*-
from __future__ import print_function
import json
import sys
import os
import threading
import fcntl
import traceback
from gevent import socket
from gevent.server import StreamServer
from gevent.lock import BoundedSemaphore
from common import utils
from xcatagent import base as xcat_manager

MSG_TYPE = 'message'
DB_TYPE  = 'db'
#LOCK_FILE = '/var/lock/xcat/agent.lock'


class XCATMessager(utils.Messager):
    def __init__(self, sock):
        self.sock = sock
        self.sem = BoundedSemaphore(1)

    def _send(self, d):
        buf = json.dumps(d)
        self.sem.acquire()
        self.sock.sendall(utils.int2bytes(len(buf)) + buf.encode('utf-8'))
        self.sem.release()

    def info(self, msg):
        d = {'type': MSG_TYPE, 'msg': {'type': 'info', 'data': msg}}
        self._send(d)

    def warn(self, msg):
        d = {'type': MSG_TYPE, 'msg': {'type': 'warning', 'data': msg}}
        self._send(d)

    def error(self,  msg, node=''):
        d = {'type': MSG_TYPE, 'msg': {'type': 'error', 'node': node, 'data': msg}}
        self._send(d)

    def syslog(self, msg):
        d = {'type': MSG_TYPE, 'msg': {'type': 'syslog', 'data': msg}}
        self._send(d)

    def info_with_host(self, msg):
        d = {'type': MSG_TYPE, 'msg': {'type': 'info_with_host', 'data': msg}}
        self._send(d)

    def update_node_attributes(self, attribute, node, data):
        d = {'type': DB_TYPE, 'attribute': {'name': attribute, 'method': 'set', 'type': 'node', 'node': node, 'value': data}}
        self._send(d)


class Server(object):
    def __init__(self, address, standalone=True, lockfile=None):
        try:
            os.unlink(address)
        except OSError:
            if os.path.exists(address):
                raise
        self.address = address
        self.standalone = standalone
        self.lockfile = lockfile
        self.server = StreamServer(self._serve(), self._handle)

    def _serve(self):
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(self.address)
        listener.listen(1)
        return listener

    def _handle(self, sock, address):
        try:
            messager = XCATMessager(sock)
            buf = sock.recv(4)
            sz = utils.bytes2int(buf)
            buf = utils.recv_all(sock, sz)
            req = json.loads(buf)
            if not 'command' in req:
                messager.error("Could not find command")
                return
            if not 'module' in req:
                messager.error("Please specify the request module")
                return
            if not 'cwd' in req:
                messager.error("Please specify the cwd parameter")
                return
            manager_func = xcat_manager.BaseManager.get_manager_func(
                req['module'])
            if manager_func is None:
                messager.error("Could not find manager for %s" % req['module'])
                return
            nodes = req.get("nodes", None)
            manager = manager_func(messager, req['cwd'], nodes, req['envs'])
            if not hasattr(manager, req['command']):
                messager.error("command %s is not supported" % req['command'])
            func = getattr(manager, req['command'])
            # translate unicode string to normal string to avoid docopt error
            new_args=[]
            if req['args']:
                for a in req['args']:
                    new_args.append(str(a))
            # call the function in the specified manager
            func(req['nodeinfo'], new_args)
            # after the method returns, the request should be handled
            # completely, close the socket for client
            if not self.standalone:
                sock.close()
                self.server.stop()
                os._exit(0)
        except ImportError:
            messager.error("OpenBMC management is using a Python framework and some dependency libraries could not be imported.")
            print(traceback.format_exc(), file=sys.stderr)
            self.server.stop()
            os._exit(1)
        except Exception:
            print(traceback.format_exc(), file=sys.stderr)
            self.server.stop()
            os._exit(1)

    def keep_peer_alive(self):
        def acquire():
            fd = open(self.lockfile, "r+")
            fcntl.flock(fd.fileno(), fcntl.LOCK_EX)
            # if reach here, parent process may exit
            print("xcat process exit unexpectedly.", file=sys.stderr)
            self.server.stop()
            os._exit(1)

        t = threading.Thread(target=acquire)
        t.start()

    def start(self):
        if not self.standalone:
            self.keep_peer_alive()
        self.server.serve_forever()
