#!/usr/bin/env python
import requests
import json
import time
from gevent.subprocess import Popen, PIPE
import urllib3
urllib3.disable_warnings()

import xcat_exception

class RestSession :

    def __init__(self, messager, debugmode):
        self.session = requests.Session()
        self.cookies = None
        self.messager = messager
        self.debugmode = debugmode

    def _print_record_log (self, node, log_string, status):
        if self.debugmode :
            localtime = time.asctime( time.localtime(time.time()) )
            log = node + ': [openbmc_debug] ' + status + ' ' + log_string
            self.messager.info(localtime + ' ' + log)
            self.messager.syslog(log)

    def _request_log (self, method, url, headers, data, files):
        log_string = 'curl -k -c cjar -b cjar'
        log_string += ' -X %s' % method
        for key,value in headers.items():
            header_data = key + ": " + value 
        log_string += ' -H "' + header_data + '"'
        log_string += ' %s' % url

        if data:
            log_string += ' -d \'%s\'' % data
        if files:
            log_string += ' -T \'%s\'' % files

        return log_string


    def _response_check (self, response, response_dict, node, status):
        if response.status_code != requests.codes.ok:
            description = ''.join(response_dict['data']['description'])
            error = 'Error: [%d] %s' % (response.status_code, description)
            self._print_record_log(node, error, status)
            code = response.status_code
            raise xcat_exception.SelfClientException(error, code)
        else:
            self._print_record_log(node, response_dict['message'], status)

        if status == 'login':
            self.cookies = requests.utils.dict_from_cookiejar(self.session.cookies)


    def request (self, method, url, headers, in_data, node, status):
        data = log_data = ''

        if in_data:
            data = json.dumps(in_data)
            log_data = data
            if status == 'login':
                in_data['data'][1] = 'xxxxxx'
                log_data = json.dumps(in_data)

        log_string = self._request_log(method, url, headers, log_data, '')
        self._print_record_log(node, log_string, status)

        response = ''
        error = ''
        try:
            response = self.session.request(method, url,
                                            data=data,
                                            headers=headers,
                                            verify=False,
                                            timeout=30)
        except requests.exceptions.ConnectionError:
            error = 'Error: BMC did not respond. ' \
                    'Validate BMC configuration and retry the command.'
        except requests.exceptions.Timeout:
            error = 'Error: Timeout to connect to server'

        if error:
            self._print_record_log(node, error, status)
            raise xcat_exception.SelfServerException(error)

        try:
            response_dict = response.json()
        except ValueError:
            error = 'Error: Received wrong format response: %s' % response
            self._print_record_log(node, error, status)
            raise xcat_exception.SelfServerException(error)

        self._response_check(response, response_dict, node, status)

        return response_dict


    def request_upload_curl (self, method, url, headers, files, node, status):
        for key,value in headers.items():
            header_data = key + ': ' + value
        request_cmd = 'curl -k -b sid=%s -H "%s" -X %s -T %s %s -s' % \
                      (self.cookies['sid'], header_data, method, files, url)
        request_cmd_log = 'curl -k -c cjar -b cjar -H "%s" -X %s -T %s %s -s' \
                          % (header_data, method, files, url)
        
        log_string = self._request_log(method, url, headers, '', files)
        self._print_record_log(node, log_string, status)

        sub = Popen(request_cmd, stdout=PIPE, shell=True)
        response, err = sub.communicate()
 
        if not response:
            error = 'Error: Did not receive response from OpenBMC after ' \
                    'running command form \'%s\'' % request_cmd_log
            raise xcat_exception.SelfServerException(error)

        try:
            response_dict = json.loads(response)
        except ValueError:
            error = 'Error: Received wrong format response: %s: %s' % \
                    (request_cmd_log, response)
            self._print_record_log(node, error, status)
            raise xcat_exception.SelfServerException(error) 

        if response_dict['message'] != '200 OK':
            error = 'Error: Failed to upload update file %s : %s-%s' % \
                    (files, response_dict['message'], \
                    ''.join(response_dict['data']['description']))
            self._print_record_log(node, error, status)
            raise xcat_exception.SelfClientException(error, code) 

        self._print_record_log(node, response_dict['message'], status) 

        return
