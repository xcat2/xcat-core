name "os-object-storage"
description "OpenStack object storage roll-up role"
run_list(
  "role[os-base]",
  "role[os-object-storage-setup]",
  "role[os-object-storage-management]",
  "role[os-object-storage-proxy]",
  "role[os-object-storage-object]",
  "role[os-object-storage-container]",
  "role[os-object-storage-account]"
  )
