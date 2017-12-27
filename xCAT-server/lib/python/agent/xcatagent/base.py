from xcatagent import utils
import gevent

MODULE_MAP = {"openbmc": "OpenBMCManager"}


class BaseManager(object):
    def __init__(self, messager, cwd):
        self.messager = messager
        self.cwd = cwd

    @classmethod
    def get_manager_func(self, name):
        module_name = 'xcatagent.%s' % name
        try:
            __import__(module_name)
        except ImportError:
            return None

        class_name = MODULE_MAP[name]
        return utils.class_func(module_name, class_name)

    def process_nodes_worker(self, name, classname, nodes, nodeinfo, command, args):
        
        glist = []
        module_name = 'xcatagent.%s' % name
        obj_func = utils.class_func(module_name, classname)

        for node in nodes:
            obj = obj_func(self.messager, node, nodeinfo[node])
            if not hasattr(obj, command):
                self.messager.error('%s: command %s is not supported for %s' % (node, command, classname))
            func = getattr(obj, command)
            try:
                glist.append( gevent.spawn(func, args) )
            except Exception:
                error = '%s: Internel Error occured in gevent' % node
                self.messager.error(error)

        gevent.joinall(glist)


class BaseDriver(object):
    def __init__(self, messager):
        self.messager = messager
