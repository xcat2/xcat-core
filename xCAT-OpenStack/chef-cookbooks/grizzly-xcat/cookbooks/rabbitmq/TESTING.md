This cookbook includes support for running tests via Test Kitchen (1.0). This has some requirements.

1. You must be using the Git repository, rather than the downloaded cookbook from the Chef Community Site.
2. You must have Vagrant 1.1 installed.
3. You must have a "sane" Ruby 1.9.3 environment.

Once the above requirements are met, install the additional requirements:

Install the berkshelf plugin for vagrant, and berkshelf to your local Ruby environment.

    vagrant plugin install vagrant-berkshelf
    gem install berkshelf

Install Test Kitchen 1.0 (unreleased yet, use the alpha / prerelease version).

    gem install test-kitchen --pre

Install the Vagrant driver for Test Kitchen.

    gem install kitchen-vagrant

Once the above are installed, you should be able to run Test Kitchen:

    kitchen list
    kitchen test

This cookbook has the following Test-Kitchen coverage:

| Test Coverage  | Ubuntu 10.04  | Ubuntu 12.04 | Ubuntu 13.04 | Centos 5.9 | Centos 6.4 | Fedora 18 | Debian 7.1 | SmartOS 13.1 | OmniOS r151002 |
| -------------- |:-------------:|:------------:|:------------:|:----------:|:----------:|:---------:|:----------:|:------------:|:--------------:|
| default        | **Y**         | **Y**        | **Y**        | **Y**      | **Y**      | **Y**     | **N**      | **N**        | **N**          |
| default-esl    | **Y**         | **Y**        | **Y**        | **N**      | **Y**      | **N**     | **N**      | **N**        | **N**          |
| upstart        | **Y**         | **Y**        | **Y**        | **N**      | **N**      | **N**     | **N**      | **N**        | **N**          |
| distro-version | **N**         | **Y**        | **Y**        | **N**      | **Y**      | **N**     | **N**      | **N**        | **N**          |
| mgmt_console   | **Y**         | **Y**        | **Y**        | **Y**      | **Y**      | **Y**     | **N**      | **N**        | **N**          |
| cook-2151-3489 | **Y**         | **Y**        | **Y**        | **Y**      | **Y**      | **Y**     | **N**      | **N**        | **N**          |
| cook-2705      | **Y**         | **Y**        | **Y**        | **Y**      | **Y**      | **Y**     | **N**      | **N**        | **N**          |
| lwrps-default  | **Y**         | **Y**        | **Y**        | **Y**      | **Y**      | **Y**     | **N**      | **N**        | **N**          |
| lwrps-distro   | **N**         | **N**        | **Y**        | **N**      | **N**      | **N**     | **N**      | **N**        | **N**          |
