#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

from __future__ import print_function
import gevent
import sys
import traceback

class BaseCommand(object):

    def _validate(self, op, *args, **kw):
        if hasattr(self, 'validate_%s' % op):
            return getattr(self, 'validate_%s' % op)(self, *args, **kw)

    def _pre(self, op, *args, **kw):
        if hasattr(self, 'pre_%s' % op):
            return getattr(self, 'pre_%s' % op)(self, *args, **kw)

    def _execute(self, op, *args, **kw):
        if hasattr(self, '%s' % op):
            return getattr(self, '%s' % op)(self, *args, **kw)

    def _post(self, op, *args, **kw):
        if hasattr(self, 'post_%s' % op):
            return getattr(self, 'post_%s' % op)(self, *args, **kw)

    def run(self, op, *args, **kwargs):
        #print 'op=%s, args=%s, kwargs=%s' % (op, args, kwargs)
        try:
            self._validate(op, *args, **kwargs)
            self._pre(op, *args, **kwargs)
            self._execute(op, *args, **kwargs)
            self._post(op, *args, **kwargs)
        except Exception as e:
            # TODO: put e into log
            print(traceback.format_exc(), file=sys.stderr)
            return None

        return self.result()

    def result(self):
        """Assume the result will be set by *_<op>"""
        return True

class ParallelNodesCommand(BaseCommand):

    def __init__(self, inventory, callback=None, **kwargs):
        """
        inventory: {'node1': {k1:v1, k2:v2, ...}, 'node2': ...}
        """
        self.inventory = inventory
        self.callback = callback
        self.cwd = kwargs.get('cwd')
        self.debugmode = kwargs.get('debugmode')
        self.verbose = kwargs.get('verbose')

    def _execute_in_parallel(self, op, *args, **kw):
        if not hasattr(self, '%s' % op):
            return

        assert self.inventory and type(self.inventory) is dict
        func = getattr(self, '%s' % op)
        if len(self.inventory) == 1:
            node = list(self.inventory.keys())[0]
            func(*args, node=node, nodeinfo=self.inventory[node], **kw)
            return

        pool_size = 1000 # Get it from kw later
        gevent_pool = gevent.pool.Pool(pool_size)

        for node in self.inventory.keys():
            try:
                gevent_pool.add( gevent.spawn(func, *args, node=node, nodeinfo=self.inventory[node], **kw))
            except Exception as e:
                error = '%s: Internel Error occured in gevent' % node
                #print(traceback.format_exc(), file=sys.stderr)
                self.callback.error(error)

        gevent_pool.join()

    def run(self, op, *args, **kwargs):
        #print 'op=%s, args=%s, kwargs=%s' % (op, args, kwargs)
        try:
            self._validate(op, *args, **kwargs)
            self._pre(op, *args, **kwargs)
            self._execute_in_parallel(op, *args, **kwargs)
            self._post(op, *args, **kwargs)
        except Exception as e:
            # TODO: put e into log
            print(traceback.format_exc(), file=sys.stderr)
            return None

        return self.result()
