#!/usr/bin/env python3
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
import requests

from hwctl import redfish_client as rf
from common.utils import Messager
from common.exceptions import SelfClientException, SelfServerException

DATA_DIR = os.path.dirname(os.path.realpath(__file__)) + '/../json_data'
logging.basicConfig(level=logging.DEBUG)
REDFISH_URL = '/redfish/v1'

class TestRedfishClient(object):

    nodeinfo_dict = {'bmc': 'testbmc', 'bmcip': '10.0.0.1', 'username': 'username', 'password': 'password'}
    log = logging.getLogger('TestRedfishClient')
    rf_rest = rf.RedfishRest(name='testnode', nodeinfo=nodeinfo_dict, messager=Messager(),
                             debugmode=True, verbose=False)
    headers = {'Content-Type': 'application/json'}
    with open("%s/redfish_v1_rsp.json" % DATA_DIR,'r') as load_f:
        rf_v1 = json.load(load_f)
    chassis_url = rf_v1['Chassis']['@odata.id']
    manager_url = rf_v1['Managers']['@odata.id']
    systems_url = rf_v1['Systems']['@odata.id']
    session_url = rf_v1['Links']['Sessions']['@odata.id']

    def test__init__(self):
        assert self.rf_rest.name == 'testnode'
        assert self.rf_rest.bmc == 'testbmc'
        assert self.rf_rest.bmcip == '10.0.0.1'
        assert self.rf_rest.username == 'username'
        assert self.rf_rest.password == 'password'
        assert isinstance(self.rf_rest.messager, Messager)
        assert self.rf_rest.verbose == True
        assert self.rf_rest.root_url == 'https://10.0.0.1'

    def test__print_record_log(self):
        self.rf_rest._print_record_log("test__print_record_log", "test")
        assert self.rf_rest.messager.info
        assert time.asctime

    def test__print_error_log(self):
        self.rf_rest._print_record_log("test__print_error_log", "test")
        assert self.rf_rest._print_record_log

    def test__log_request(self):
        self.rf_rest._print_record_log = mock.Mock(return_value=True)
        login_data = json.dumps({ "UserName": self.rf_rest.username, "Password": self.rf_rest.password })
        msg_data = login_data.replace('"Password": "%s"' % self.rf_rest.password, '"Password": "xxxxxx"') 
        test_data = json.dumps({ "Test": True })
        login_msg = 'curl -k -X POST -H "Content-Type: application/json" https://10.0.0.1%s -d \'%s\' -v' % (self.session_url, msg_data)
        test_data_msg = 'curl -k -X POST -H "Content-Type: application/json" -H "X-Auth-Token: xxxxxx" https://10.0.0.1/redfish/v1/Managers -d \'%s\' -v' % test_data
        get_msg = 'curl -k -X GET -H "Content-Type: application/json" -H "X-Auth-Token: xxxxxx" https://10.0.0.1/redfish/v1/Managers'
        assert self.rf_rest._log_request('POST', self.rf_rest.root_url + self.session_url, self.headers, data=login_data, cmd='login') == login_msg
        assert self.rf_rest._log_request('POST', self.rf_rest.root_url + self.manager_url, self.headers, data=test_data, cmd='test__log_request') == test_data_msg
        assert self.rf_rest._log_request('GET', self.rf_rest.root_url + self.manager_url, self.headers, cmd='test__log_request') == get_msg

    def test_handle_response_not_ok(self):
        test_rsp = requests.Response()
        test_rsp.status_code = 401
        with open("%s/login_no_auth_rsp.json" % DATA_DIR,'r') as load_f: 
            test_rsp._content = json.dumps(json.load(load_f))
        with pytest.raises(SelfClientException) as excinfo:
            data = self.rf_rest.handle_response(test_rsp, cmd='test_handle_response_not_ok')
        assert excinfo.type == SelfClientException
        assert 'the service received an authorization error unauthorized' in str(excinfo.value)

    def test_handle_response_no_auth(self):
        test_rsp = requests.Response()
        test_rsp.status_code = 201
        test_rsp.headers = {}
        with open("%s/login_rsp.json" % DATA_DIR,'r') as load_f:
            test_rsp._content = json.dumps(json.load(load_f))
        with pytest.raises(SelfServerException) as excinfo:
            data = self.rf_rest.handle_response(test_rsp, cmd='login')
        assert excinfo.type == SelfServerException
        assert 'Login Failed: Did not get Session Token from response' in str(excinfo.value)

    def test_handle_response_name(self):
        test_rsp = requests.Response()
        test_rsp.status_code = 200
        test_rsp.headers = {'X-Auth-Token': 'abcdefghijklmn'}
        with open("%s/login_rsp.json" % DATA_DIR,'r') as load_f:
            file_data = json.load(load_f)
            test_rsp._content = json.dumps(file_data)
        data = self.rf_rest.handle_response(test_rsp, cmd='get_information')
        assert data == file_data

    def test_handle_response_error(self):
        test_rsp = requests.Response()
        test_rsp.status_code = 200
        test_rsp.headers = {'X-Auth-Token': 'abcdefghijklmn'}
        with open("%s/with_error_rsp.json" % DATA_DIR,'r') as load_f:
            file_data = json.load(load_f)
            test_rsp._content = json.dumps(file_data)
        data = self.rf_rest.handle_response(test_rsp, cmd='get_information') 
        assert data == file_data

    def test_request_login_connect_failed(self):
        login_data = { "UserName": self.rf_rest.username, "Password": self.rf_rest.password }
        self.rf_rest.session.request = mock.Mock(side_effect=SelfServerException('Login to BMC failed: Can\'t connect to'))
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest.request('POST', self.session_url, headers=self.headers, payload=login_data, cmd='login')
        assert excinfo.type == SelfServerException
        assert 'Login to BMC failed: Can\'t connect to' in str(excinfo.value)

    def test_request_connect_failed(self):
        self.rf_rest.session.request = mock.Mock(side_effect=SelfServerException('BMC did not respond. Validate BMC configuration and retry the command.'))
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest.request('GET', self.manager_url, headers=self.headers)
        assert excinfo.type == SelfServerException
        assert 'BMC did not respond. Validate BMC configuration and retry the command.' in str(excinfo.value)

    def test_request_value_error(self):
        self.rf_rest.session.request = mock.Mock(return_value='Mock return value for value error')
        self.rf_rest.handle_response = mock.Mock(side_effect=ValueError())
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest.request('GET', self.manager_url, headers=self.headers)
        assert excinfo.type == SelfServerException
        assert 'Received wrong format response:' in str(excinfo.value)

    def test_request_login_success(self):
        login_data = json.dumps({ "UserName": self.rf_rest.username, "Password": self.rf_rest.password })
        with open("%s/login_rsp.json" % DATA_DIR,'r') as load_f:
            response = json.load(load_f)
        self.rf_rest.session.request = mock.Mock(return_value=None)
        self.rf_rest.handle_response = mock.Mock(return_value=response)
        data = self.rf_rest.request('POST', self.session_url, headers=self.headers, payload=login_data, cmd='login')
        assert self.rf_rest.session.request
        assert data == response

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

    def test__get_members(self):
        resp_data = {"Members": [ {"@odata.id": self.manager_url + "/BMC"} ] }
        self.rf_rest.request = mock.Mock(return_value=resp_data)
        members = self.rf_rest._get_members(self.manager_url)
        assert members == [ {"@odata.id": self.manager_url + "/BMC"} ]

    def test__get_members_keyerror(self):
        self.rf_rest.request = mock.Mock(return_value={"key": "value"})
        with pytest.raises(SelfServerException) as excinfo:
            members = self.rf_rest._get_members(self.manager_url)
        assert excinfo.type == SelfServerException
        assert 'Get KeyError' in str(excinfo.value)

    def test_get_bmc_state(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.manager_url + "/BMC"} ])
        with open("%s/manager_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=rsp)
        assert self.rf_rest.get_bmc_state() == "On"

    def test_get_bmc_state_keyerror(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.manager_url + "/BMC"} ])
        self.rf_rest.request = mock.Mock(return_value={"powerState": "Off"})
        with pytest.raises(SelfServerException) as excinfo:
            resp_data = self.rf_rest.get_bmc_state()
        assert excinfo.type == SelfServerException
        assert 'Get KeyError' in str(excinfo.value)

    def test_get_chassis_power_state(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.chassis_url + '/MotherBoard'} ])
        with open("%s/chassis_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=rsp)
        assert self.rf_rest.get_chassis_power_state() == 'On'

    def test_get_chassis_power_state_keyerror(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.chassis_url + '/MotherBoard'} ])
        self.rf_rest.request = mock.Mock(return_value={"Powerstate": "On"})
        with pytest.raises(SelfServerException) as excinfo:
            resp_data = self.rf_rest.get_chassis_power_state()
        assert excinfo.type == SelfServerException
        assert 'Get KeyError' in str(excinfo.value)

    def test_get_systems_power_state(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.systems_url + '/Computer'} ])
        with open("%s/systems_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=rsp)
        assert self.rf_rest.get_systems_power_state() == 'On'

    def test_get_systems_power_state_keyerror(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.systems_url + '/Computer'} ])
        self.rf_rest.request = mock.Mock(return_value={"powerstate": "On"})
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest.get_systems_power_state()
        assert excinfo.type == SelfServerException
        assert 'Get KeyError' in str(excinfo.value)

    def test__get_bmc_actions(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.manager_url + '/BMC'} ])
        with open("%s/manager_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        with open("%s/bmc_action_rsp.json" % DATA_DIR,'r') as load_f:
            actioninfo = json.load(load_f)
        self.rf_rest.request = mock.Mock(side_effect=[rsp, actioninfo])
        reset_string = '#Manager.Reset'
        assert self.rf_rest._get_bmc_actions() == (rsp['Actions'][reset_string]['target'], actioninfo['Parameters'][0]['AllowableValues']) 

    def test__get_bmc_actions_v123(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.manager_url + '/BMC'} ])
        with open("%s/manager_rsp_v123.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=rsp)
        reset_string = '#Manager.Reset'
        assert self.rf_rest._get_bmc_actions() == (rsp['Actions'][reset_string]['target'], rsp['Actions'][reset_string]['ResetType@Redfish.AllowableValues'])

    def test__get_bmc_actions_keyerror(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.manager_url + '/BMC'} ])
        with open("%s/manager_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=rsp)
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest._get_bmc_actions()
        assert excinfo.type == SelfServerException
        assert 'Get KeyError' in str(excinfo.value)

    def test_reboot_bmc(self):
        with open("%s/manager_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest._get_bmc_actions = mock.Mock(return_value=(rsp['Actions']['#Manager.Reset']['target'], ['ForceRestart']))
        self.rf_rest.request = mock.Mock(return_value=None)
        assert self.rf_rest.reboot_bmc() == None
        assert self.rf_rest.request

    def test_reboot_bmc_unsupported(self):
        self.rf_rest._get_bmc_actions = mock.Mock(return_value=(self.manager_url + '/BMC/Reset', ['forcerestart']))
        with pytest.raises(SelfClientException) as excinfo:
            self.rf_rest.reboot_bmc()
        assert excinfo.type == SelfClientException
        assert 'Unsupported option:' in str(excinfo.value)

    def test__get_power_actions(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.systems_url + '/Computer'} ])
        with open("%s/systems_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        with open("%s/system_action_rsp.json" % DATA_DIR,'r') as load_f:
            actioninfo = json.load(load_f)
        self.rf_rest.request = mock.Mock(side_effect=[rsp, actioninfo])
        reset_string = '#ComputerSystem.Reset'
        assert self.rf_rest._get_power_actions() == (rsp['Actions'][reset_string]['target'], actioninfo['Parameters'][0]['AllowableValues'])

    def test__get_power_actions_v123(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.systems_url + '/Computer'} ])
        with open("%s/systems_rsp_v123.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=rsp)
        reset_string = '#ComputerSystem.Reset'
        assert self.rf_rest._get_power_actions() == (rsp['Actions'][reset_string]['target'], rsp['Actions'][reset_string]['ResetType@Redfish.AllowableValues'])

    def test__get_power_actions_keyerror(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.systems_url + '/Computer'} ])
        with open("%s/systems_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=rsp)
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest._get_power_actions()
        assert excinfo.type == SelfServerException
        assert 'Get KeyError' in str(excinfo.value)

    def test_set_power_state(self):
        with open("%s/systems_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        with open("%s/system_action_rsp.json" % DATA_DIR,'r') as load_f:
            actioninfo = json.load(load_f)
        reset_string = '#ComputerSystem.Reset'
        self.rf_rest._get_power_actions = mock.Mock(return_value=(rsp['Actions'][reset_string]['target'], actioninfo['Parameters'][0]['AllowableValues']))
        self.rf_rest.request = mock.Mock(return_value=None)
        assert self.rf_rest.set_power_state('on') == None
        assert self.rf_rest.request

    def test_set_power_state_unsupported(self):
        self.rf_rest._get_power_actions = mock.Mock(return_value=(self.systems_url + '/Computer/Reset', ['ForceRestart', 'ForceOff']))
        with pytest.raises(SelfClientException) as excinfo:
            self.rf_rest.set_power_state('on')
        assert excinfo.type == SelfClientException
        assert 'Unsupported option:' in str(excinfo.value)
        
    def test_get_boot_state(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.systems_url + '/Computer'} ])
        with open("%s/systems_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=rsp)
        assert self.rf_rest.get_boot_state() == "boot override inactive"
        rsp['Boot']['BootSourceOverrideTarget'] = 'Pxe'
        self.rf_rest.request = mock.Mock(return_value=rsp)
        assert self.rf_rest.get_boot_state() == 'Network'
        rsp['Boot']['BootSourceOverrideEnabled'] = 'Disabled'
        self.rf_rest.request = mock.Mock(return_value=rsp)
        assert self.rf_rest.get_boot_state() == "boot override inactive"

    def test_get_boot_state_keyerror(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.systems_url + '/Computer'} ])
        with open("%s/systems_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        del rsp['Boot']['BootSourceOverrideEnabled']
        self.rf_rest.request = mock.Mock(return_value=rsp)
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest.get_boot_state()
        assert excinfo.type == SelfServerException
        assert 'Get KeyError' in str(excinfo.value)

    def test__get_boot_actions(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.systems_url + '/Computer'} ])
        with open("%s/systems_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest.request = mock.Mock(return_value=rsp)
        assert self.rf_rest._get_boot_actions() == (self.systems_url + '/Computer', rsp['Boot']['BootSourceOverrideTarget@Redfish.AllowableValues'])

    def test__get_boot_actions_keyerror(self):
        self.rf_rest._get_members = mock.Mock(return_value=[ {"@odata.id": self.systems_url + '/Computer'} ])
        with open("%s/systems_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        del rsp['Boot']['BootSourceOverrideTarget@Redfish.AllowableValues']
        self.rf_rest.request = mock.Mock(return_value=rsp)
        with pytest.raises(SelfServerException) as excinfo:
            self.rf_rest._get_boot_actions()
        assert excinfo.type == SelfServerException
        assert 'Get KeyError' in str(excinfo.value)

    def test_set_boot_state(self):
        with open("%s/systems_rsp.json" % DATA_DIR,'r') as load_f:
            rsp = json.load(load_f)
        self.rf_rest._get_boot_actions = mock.Mock(return_value=(self.systems_url + '/Computer', rsp['Boot']['BootSourceOverrideTarget@Redfish.AllowableValues']))
        self.rf_rest.request = mock.Mock(return_value=None)
        assert self.rf_rest.set_boot_state(False, 'def') == None
        assert self.rf_rest.request
        assert self.rf_rest.set_boot_state(True, 'cd') == None
        assert self.rf_rest.request

    def test_set_boot_state_unsupported(self):
        allow_values = ['cd','def']
        self.rf_rest._get_boot_actions = mock.Mock(return_value=(self.systems_url + '/Computer', allow_values))
        with pytest.raises(SelfClientException) as excinfo:
            self.rf_rest.set_boot_state(False, 'hd')
        assert excinfo.type == SelfClientException
        assert 'Unsupported option:' in str(excinfo.value)

def test_init_no_bmcip():
    nodeinfo_dict = {'bmc': 'testbmc', 'username': 'username', 'password': 'password'}
    rf_rest_new = rf.RedfishRest(name='testnode', nodeinfo=nodeinfo_dict, messager=Messager(),
                                 debugmode=True, verbose=False)

    assert rf_rest_new.bmcip == 'testnode' 
