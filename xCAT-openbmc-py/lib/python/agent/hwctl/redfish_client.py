#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

import os
import requests
import json
import time
from requests.auth import AuthBase

from common import utils, rest
from common.exceptions import SelfClientException, SelfServerException

import logging
logger = logging.getLogger('xcatagent')

HTTP_PROTOCOL = "https://"
PROJECT_URL = "/redfish/v1"

SESSION_URL = PROJECT_URL + "/SessionService/Sessions"

class RedfishRest(object):

    headers = {'Content-Type': 'application/json'}

    def __init__(self, name, **kwargs):

        self.name = name
        self.username = None
        self.password = None

        if 'nodeinfo' in kwargs:
            for key, value in kwargs['nodeinfo'].items():
                setattr(self, key, value)
        if not hasattr(self, 'bmcip'):
            self.bmcip = self.name

        self.verbose = kwargs.get('debugmode')
        self.messager = kwargs.get('messager')

        self.session = rest.RestSession()
        self.auth = None
        self.root_url = HTTP_PROTOCOL + self.bmcip

    def _print_record_log (self, msg, cmd, error_flag=False):

        if self.verbose or error_flag:
            localtime = time.asctime( time.localtime(time.time()) )
            log = self.name + ': [redfish_debug] ' + cmd + ' ' + msg
            if self.verbose:
                self.messager.info(localtime + ' ' + log)
            logger.debug(log)

    def _print_error_log (self, msg, cmd):

        self._print_record_log(msg, cmd, True)

    def _log_request (self, method, url, headers, data=None, files=None, file_path=None, cmd=''):

        header_str = ' '.join([ "%s: %s" % (k, v) for k,v in headers.items() ])
        msg = 'curl -k -X %s -H \"%s\" ' % (method, header_str)

        if cmd != 'login':
            msg += '-H \"X-Auth-Token: xxxxxx\" '

        if data:
            if cmd == 'login':
                data = data.replace('"Password": "%s"' % self.password, '"Password": "xxxxxx"')
                data = '-d \'%s\'' % data  
            msg += '%s %s -v' % (url, data)
        else:
            msg += url

        self._print_record_log(msg, cmd)
        return msg

    def request (self, method, resource, headers=None, payload=None, timeout=30, cmd=''):

        httpheaders = headers or RedfishRest.headers
        url = resource
        if not url.startswith(HTTP_PROTOCOL):
            url = self.root_url + resource

        data = None
        if payload:
            data=json.dumps(payload)

        self._log_request(method, url, httpheaders, data=data, cmd=cmd)

        try:
            response = self.session.request(method, url, authType=self.auth, headers=httpheaders, data=data, timeout=timeout)
            return self.handle_response(response, cmd=cmd)
        except SelfServerException as e:
            if cmd == 'login':
                e.message = "Login to BMC failed: Can't connect to {0} {1}.".format(e.host_and_port, e.detail_msg)
            else:
                e.message = 'BMC did not respond. ' \
                            'Validate BMC configuration and retry the command.'
            self._print_error_log(e.message, cmd)
            raise
        except ValueError:
            error = 'Received wrong format response: %s' % response
            self._print_error_log(error, cmd)
            raise SelfServerException(error)

    def handle_response (self, resp, cmd=''):

        data = resp.json()
        code = resp.status_code

        if code != requests.codes.ok and code != requests.codes.created:

            description = ''.join(data['error']['@Message.ExtendedInfo'][0]['Message'])
            error = '[%d] %s' % (code, description)
            self._print_error_log(error, cmd)
            raise SelfClientException(error, code)

        if cmd == 'login' and not 'X-Auth-Token' in resp.headers:
            raise SelfServerException('Login Failed: Did not get Session Token from response')

        if not self.auth:
            self.auth = RedfishAuth(resp.headers['X-Auth-Token'])

        self._print_record_log('%s %s' % (code, data['Name']), cmd)
        return data

    def login(self):

        payload = { "UserName": self.username, "Password": self.password }
        self.request('POST', SESSION_URL, payload=payload, timeout=20, cmd='login') 

class RedfishAuth(AuthBase):

    def __init__(self,authToken):

        self.authToken=authToken

    def __call__(self, auth):
        auth.headers['X-Auth-Token']=self.authToken
        return(auth)
