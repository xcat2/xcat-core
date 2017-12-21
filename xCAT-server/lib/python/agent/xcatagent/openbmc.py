from xcatagent import base
import gevent


class OpenBMCManager(base.BaseManager):
    def __init__(self, messager, cwd, nodes):
        super(OpenBMCManager, self).__init__(messager, cwd)
        self.nodes = nodes

    def rpower(self, nodeinfo, args):
        driver = OpenBMCDriver(self.messager)
        lst = [gevent.spawn(driver.rpower, node, nodeinfo[node],
                            args) for node in self.nodes]
        gevent.joinall(lst)


class OpenBMCDriver(base.BaseDriver):
    def __init__(self, messager):
        super(OpenBMCDriver, self).__init__(messager)

    def rpower(self, node, info, args):
        if node == 'node1':
            self.messager
            gevent.sleep(3)
        self.messager.info(
            "%s: rpower called info=%s args=%s" % (node, info, args))
