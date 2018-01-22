#!/usr/bin/env python
import requests
from gevent.subprocess import Popen, PIPE
import urllib3
urllib3.disable_warnings()

import xcat_exception

class RestSession :

    def __init__(self):
        self.session = requests.Session()
        self.cookies = None

    def request (self, method, url, headers, data):
        try:
            response = self.session.request(method, url,
                                            data=data,
                                            headers=headers,
                                            verify=False,
                                            timeout=30)
        except requests.exceptions.ConnectionError:
            raise xcat_exception.SelfServerException(
                  'Error: BMC did not respond. ' \
                  'Validate BMC configuration and retry the command.')
        except requests.exceptions.Timeout:
            raise xcat_exception.SelfServerException('Error: Timeout to connect to server')

        if not self.cookies:
            self.cookies = requests.utils.dict_from_cookiejar(self.session.cookies)

        return response

    def request_upload (self, method, url, headers, files):
        request_cmd = 'curl -k -b sid=%s -H "%s" -X %s -T %s %s -s' % \
                      (self.cookies['sid'], headers, method, files, url)
        
        sub = Popen(request_cmd, stdout=PIPE, shell=True)
        response, err = sub.communicate()
 
        return response
