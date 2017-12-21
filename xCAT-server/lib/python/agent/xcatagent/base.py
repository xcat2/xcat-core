from xcatagent import utils

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


class BaseDriver(object):
    def __init__(self, messager):
        self.messager = messager
