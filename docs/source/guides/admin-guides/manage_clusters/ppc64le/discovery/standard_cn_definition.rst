Verify node definition
----------------------

The following is an example of the server node definition after hardware discovery::

  # lsdef cn1
  Object name: cn1
      arch=ppc64
      bmc=50.0.100.1
      cons=ipmi
      cpucount=192
      cputype=POWER8E (raw), altivec supported
      groups=powerLE,all
      installnic=mac
      ip=10.0.101.1
      mac=6c:ae:8b:02:12:50
      memory=65118MB
      mgt=ipmi
      mtm=8247-22L
      netboot=petitboot
      postbootscripts=otherpkgs
      postscripts=syslog,remoteshell,syncfiles
      primarynic=mac
      serial=10112CA
      supportedarchs=ppc64
