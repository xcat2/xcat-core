case platform_family
when 'debian', 'rhel'
  default['sysctl']['conf_dir'] = '/etc/sysctl.d'
else
  default['sysctl']['conf_dir'] = nil
end
default['sysctl']['params'] = {}
default['sysctl']['allow_sysctl_conf'] = false
