#!/usr/bin/env python3
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

from gevent.subprocess import Popen, PIPE
import requests
import urllib3
urllib3.disable_warnings()
from requests.auth import AuthBase

from . import exceptions as xcat_exception

class RestSession(object):

    def __init__(self, auth=None):
        self.session = requests.Session()
        self.cookies = None
        # If userid and password were passed in, use them for basic authorization
        # This is required to connect to BMC with OP940 level, ignored for lower OP levels
        self.auth = auth

    def request(self, method, url, headers, data=None, timeout=30):

        try:
            response = self.session.request(method, url,
                                            data=data,
                                            headers=headers,
                                            auth=self.auth,
                                            verify=False,
                                            timeout=timeout)
        except requests.exceptions.ConnectionError as e:
            # Extract real reason for the exception and host/port from ConnectionError message
            # to extract the data needed.
            e = str(e)
            causing_error = "n/a"
            host_and_port = "n/a"
            if "]" in e:
                causing_error_part1 = e.split("]")[1]
                causing_error       = causing_error_part1.split("'")[0]
                causing_error       = causing_error.strip()
                host_and_port = self.extract_server_and_port(e, "STRING")

            if "Connection aborted." in e:
                causing_error = "Connection reset by peer"
                host_and_port = self.extract_server_and_port(url, "URL")

            if "connect timeout=" in e:
                causing_error = "timeout"
                host_and_port = self.extract_server_and_port(e, "STRING")

            message = 'Failed to connect to server.'
            # message = '\n\n--> {0} \n\n'.format(e.message[0])
            raise xcat_exception.SelfServerException(message, '({0})'.format(causing_error), host_and_port)

        except requests.exceptions.Timeout as e:
            e = str(e)
            causing_error = "timeout"
            host_and_port = self.extract_server_and_port(e, "STRING")

            message = 'Timeout to connect to server'
            raise xcat_exception.SelfServerException(message, '({0})'.format(causing_error), host_and_port)

        if not self.cookies:
            self.cookies = requests.utils.dict_from_cookiejar(self.session.cookies)

        if not self.auth and 'X-Auth-Token' in response.headers:
            self.auth = XTokenAuth(response.headers['X-Auth-Token'])

        return response

    def extract_server_and_port(self, message_string, format="STRING"):
        # Extract hostip and port number from ConnectionError message
        # If format="STRING" look for host='IP' and port=xxxx pattern
        # If format="URL"    look for https://IP/login pattern
        if format == "STRING":
            start   = "host='"
            end     = "',"
            host_ip = message_string[message_string.find(start)+len(start):message_string.find(end)]
            start   = "port="
            end     = "):"
            port = message_string[message_string.find(start)+len(start):message_string.find(end)]
            host_and_port = host_ip + ":" + port
        elif format == "URL":
            start   = "https://"
            end     = "/login"
            host_ip = message_string[message_string.find(start)+len(start):message_string.find(end)]
            host_and_port = host_ip
        else:
            host_and_port = "n/a"

        return host_and_port


    def request_download(self, method, url, headers, file_path, using_curl=True):

        if using_curl:
            response = self._download_by_curl(method, url, headers, file_path)
        else:
            response = self.session.request('GET', url, headers=headers)
            file_handle = open(file_path, "wb")
            for chunk in response.iter_content(chunk_size=1024):
                if chunk:
                    file_handle.write(chunk)

        return response

    def _download_by_curl(self, method, url, headers, file_path):

        header_str = ' '.join([ "%s: %s" % (k, v) for k,v in headers.items() ])
        request_cmd = 'curl -J -k -b sid=%s -H "%s" -X %s -o %s %s -s' % \
                      (self.cookies['sid'], header_str, method, file_path, url)

        sub = Popen(request_cmd, stdout=PIPE, shell=True)
        response, err = sub.communicate()
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
            error = 'Did not receive response from server after ' \
                    'running command \'%s\'' % request_cmd
            raise SelfServerException(error)

        return response

class XTokenAuth(AuthBase):

    def __init__(self,authToken):

        self.authToken=authToken

    def __call__(self, auth):
        auth.headers['X-Auth-Token']=self.authToken
        return(auth)
