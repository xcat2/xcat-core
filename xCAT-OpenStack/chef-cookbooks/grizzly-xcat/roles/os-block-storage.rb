name "os-block-storage"
description "Configures OpenStack block storage, configured by attributes."
run_list(
  "role[os-base]",
  "role[os-block-storage-api]",
  "role[os-block-storage-scheduler]",
  "role[os-block-storage-volume]",
  )
