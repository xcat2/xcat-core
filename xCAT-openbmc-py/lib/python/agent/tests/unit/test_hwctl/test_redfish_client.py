#!/usr/bin/env python
###############################################################################
# IBM(c) 2018 EPL license http://www.eclipse.org/legal/epl-v10.html
###############################################################################
# -*- coding: utf-8 -*-
#

import pytest
import mock
import json
import os
import logging
import time

from hwctl import redfish_client as rf
from common.exceptions import SelfClientException, SelfServerException

DATA_DIR = os.path.dirname(os.path.realpath(__file__)) + '/../json_data'
logging.basicConfig(level=logging.DEBUG)

class TestRedfishClient(object):

    nodeinfo_dict = {'bmc': 'testbmc', 'bmcip': '10.0.0.1', 'username': 'username', 'password': 'password'}
    log = logging.getLogger('TestRedfishClient')
    rf_rest = rf.RedfishRest(name='testnode', nodeinfo=nodeinfo_dict, messager=log,
                             debugmode=True, verbose=True)

    def test__init__(self):
        assert self.rf_rest.name == 'testnode'
        assert self.rf_rest.bmc == 'testbmc'
        assert self.rf_rest.bmcip == '10.0.0.1'
        assert self.rf_rest.username == 'username'
        assert self.rf_rest.password == 'password'
        assert self.rf_rest.messager == self.log
        assert self.rf_rest.verbose == True
        assert self.rf_rest.root_url == 'https://10.0.0.1'

    def test_login_success(self):
        with open("%s/login_rsp.json" % DATA_DIR,'r') as load_f:
            login_rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=login_rsp) 
        assert self.rf_rest.login() == None

    def test_login_not_respond(self):
        self.rf_rest.request = mock.Mock(side_effect=SelfServerException('BMC did not respond. Validate BMC configuration and retry the command.')) 
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest.login()
        assert excinfo.type == SelfServerException
        assert 'BMC did not respond. Validate BMC configuration and retry the command.' in str(excinfo.value)

    def test_login_value_error(self):
        self.rf_rest.request = mock.Mock(side_effect=SelfServerException('Received wrong format response: xxxxxx'))
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest.login()
        assert excinfo.type == SelfServerException
        assert 'Received wrong format response:' in str(excinfo.value) 

    def test__print_record_log(self):
        self.rf_rest._print_record_log("test__print_record_log", "test")
        assert self.rf_rest.messager.info
        assert time.asctime
