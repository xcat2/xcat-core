#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

from gevent.subprocess import Popen, PIPE
import requests
import urllib3
urllib3.disable_warnings()

import exceptions as xcat_exception

class RestSession(object):

    def __init__(self):
        self.session = requests.Session()
        self.cookies = None

    def request(self, method, url, headers, data=None, timeout=30):

        try:
            response = self.session.request(method, url,
                                            data=data,
                                            headers=headers,
                                            verify=False,
                                            timeout=timeout)
        except requests.exceptions.ConnectionError:
            raise xcat_exception.SelfServerException('Error: Failed to connect to server.')

        except requests.exceptions.Timeout:
            raise xcat_exception.SelfServerException('Error: Timeout to connect to server')

        if not self.cookies:
            self.cookies = requests.utils.dict_from_cookiejar(self.session.cookies)

        return response

    def request_upload(self, method, url, headers, files, using_curl=True):
        if using_curl:
            return self._upload_by_curl(method, url, headers, files)

    def _upload_by_curl(self, method, url, headers, files):

        header_str = ' '.join([ "%s: %s" % (k, v) for k,v in headers.items() ])
        request_cmd = 'curl -k -b sid=%s -H "%s" -X %s -T %s %s -s' % \
                      (self.cookies['sid'], header_str, method, files, url)

        sub = Popen(request_cmd, stdout=PIPE, shell=True)
        response, err = sub.communicate()

        if not response:
            error = 'Error: Did not receive response from server after ' \
                    'running command \'%s\'' % request_cmd
            raise SelfServerException(error)

        return response
