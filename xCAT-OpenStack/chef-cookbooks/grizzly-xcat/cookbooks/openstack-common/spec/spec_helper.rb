require "chefspec"

::LOG_LEVEL = :fatal
::UBUNTU_OPTS = {
  :platform  => "ubuntu",
  :version   => "12.04",
  :log_level => ::LOG_LEVEL
}
::CHEFSPEC_OPTS = {
  :log_level => ::LOG_LEVEL
}
