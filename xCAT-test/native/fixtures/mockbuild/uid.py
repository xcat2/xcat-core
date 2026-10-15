# Stand-in for mock's uid manager. The namespace has no sudo caller to drop to.
class _UidManager:
    def run_in_subprocess_without_privileges(self, func, *args):
        return func(*args)


def setup_uid_manager():
    return _UidManager()
