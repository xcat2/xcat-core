# Stand-in for mock's configuration loader in the namespace build fixture.
# Without chrootuid, mock builds as the caller.
import os

MOCKCONFDIR = '/etc/mock'


def load_config(config_path, name):
    if not os.path.isfile(os.path.join(config_path, name + '.cfg')):
        raise SystemExit('no mock configuration ' + name)
    return {'chrootuid': os.getuid()}
