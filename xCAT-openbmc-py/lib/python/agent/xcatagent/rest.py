#!/usr/bin/env python
import requests
import json
import time
import urllib3
urllib3.disable_warnings()

import xcat_exception

class RestSession :

    def __init__(self, messager, debugmode) :
        self.session = requests.Session()
        self.messager = messager
        self.debugmode = debugmode

    def _print_record_log (self, node, log_string, status) :
        if self.debugmode :
            localtime = time.asctime( time.localtime(time.time()) )
            log = node + ': [openbmc_debug] ' + status + ' ' + log_string
            self.messager.info(localtime + ' ' + log)
            self.messager.syslog(log)

    def _request_log (self, method, url, headers, data):
        log_string = 'curl -k -c cjar'
        log_string += ' -X %s' % method
        for key,value in headers.items() :
            header_data = key + ": " + value 
        log_string += ' -H "' + header_data + '"'
        log_string += ' %s' % url

        if data :
            log_string += ' -d \'%s\'' % data

        return log_string

    def request (self, method, url, headers, in_data, node, status) :
        if in_data :
            data = json.dumps(in_data)
        else :
            data = ''

        if status == 'login' :
            in_data['data'][1] = 'xxxxxx'
            log_data = json.dumps(in_data)
        else :
            log_data = data

        log_string = self._request_log(method, url, headers, log_data)
        self._print_record_log(node, log_string, status)

        response = ''
        error = ''
        try :
            response = self.session.request(method, url,
                                        data=data,
                                        headers=headers,
                                        verify=False,
                                        timeout=30)
        except requests.exceptions.ConnectionError :
            error = 'Error: BMC did not respond. Validate BMC configuration and retry the command.'
        except requests.exceptions.Timeout :
            error = 'Error: Timeout to connect to server'

        if error :
            self._print_record_log(node, error, status)
            raise xcat_exception.SelfServerException(error)

        try :
            response_dict = response.json()
        except ValueError :
            error = 'Error: Received wrong format response:' + response_dict
            self._print_record_log(node, error, status)
            raise xcat_exception.SelfServerException(error)

        if response.status_code != requests.codes.ok :
            description = ''.join(response_dict['data']['description'])
            error = 'Error: [%d] %s' % (response.status_code, description)
            self._print_record_log(node, error, status)
            raise xcat_exception.SelfClientException(error)
        else :
            self._print_record_log(node, response_dict['message'], status)

        return response_dict
