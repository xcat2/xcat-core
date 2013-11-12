## v0.5.6:

* [COOK-2124] - enforcing recipe fails if selinux is disabled

## v0.5.4:

* [COOK-1277] - disabled recipe fails on systems w/o selinux installed

## v0.5.2:

* [COOK-789] - fix dangling commas causing syntax error on some rubies

## v0.5.0:

* [COOK-678] - add the selinux cookbook to the repository
* Use main selinux config file (/etc/selinux/config)
* Use getenforce instead of selinuxenabled for enforcing and permissive
