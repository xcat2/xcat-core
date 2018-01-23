#!/usr/bin/env python
import requests
import json
import time

import rest
import xcat_exception

class OpenBMCRest:

    def __init__(self, name, messager, debugmode):
        self.session = rest.RestSession()
        self.name = name
        self.messager = messager
        self.debugmode = debugmode

    def _print_record_log (self, log_string, status):
        if self.debugmode :
            localtime = time.asctime( time.localtime(time.time()) )
            log = self.name + ': [openbmc_debug] ' + status + ' ' + log_string
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


    def _response_check (self, response, response_dict, status):
        if response.status_code != requests.codes.ok:
            description = ''.join(response_dict['data']['description'])
            error = 'Error: [%d] %s' % (response.status_code, description)
            self._print_record_log(error, status)
            code = response.status_code
            raise xcat_exception.SelfClientException(error, code)
        else:
            self._print_record_log(response_dict['message'], status)

    def request (self, method, url, headers, in_data, status):
        data = log_data = ''

        if in_data:
            data = json.dumps(in_data)
            log_data = data
            if status == 'login':
                in_data['data'][1] = 'xxxxxx'
                log_data = json.dumps(in_data)

        log_string = self._request_log(method, url, headers, log_data, '')
        self._print_record_log(log_string, status)

        try:
            response = self.session.request(method, url, headers, data)
        except xcat_exception.SelfServerException as e:
            self._print_record_log(e.message, status)
            raise xcat_exception.SelfServerException(e.message)

        try:
            response_dict = response.json()
        except ValueError:
            error = 'Error: Received wrong format response: %s' % response
            self._print_record_log(error, status)
            raise xcat_exception.SelfServerException(error)

        self._response_check(response, response_dict, status)

        return response_dict


    def request_upload (self, method, url, headers, files, status):
        for key,value in headers.items():
            header_data = key + ': ' + value
        request_cmd_log = 'curl -k -c cjar -b cjar -H "%s" -X %s -T %s %s -s' \
                          % (header_data, method, files, url)
        log_string = self._request_log(method, url, headers, '', files)
        self._print_record_log(log_string, status)

        response = self.session.request_upload(method, url, header_data, files)

        if not response:
            error = 'Error: Did not receive response from OpenBMC after ' \
                    'running command form \'%s\'' % request_cmd_log
            raise xcat_exception.SelfServerException(error)

        try:
            response_dict = json.loads(response)
        except ValueError:
            error = 'Error: Received wrong format response: %s: %s' % \
                    (request_cmd_log, response)
            self._print_record_log(error, status)
            raise xcat_exception.SelfServerException(error) 

        if response_dict['message'] != '200 OK':
            error = 'Error: Failed to upload update file %s : %s-%s' % \
                    (files, response_dict['message'], \
                    ''.join(response_dict['data']['description']))
            self._print_record_log(error, status)
            raise xcat_exception.SelfClientException(error, code) 

        self._print_record_log(response_dict['message'], status) 

        return
