# DESCRIPTION

Chef cookbook to install [Etsy's
StatsD](https://github.com/etsy/statsd) daemon. Supports the new
pluggable backend modules.

# REQUIREMENTS

Depends on the cookbooks:

 * git
 * nodejs

# ATTRIBUTES

## Basic attributes

 * `repo`: Location of statsd repo (defaults to Etsy's).
 * `log_file`: Where to log output (defaults to:
    `/var/log/statsd.log`).
 * `flush_interval_msecs`: Flush interval in msecs (default 10000).
 * `port`: Port to listen for UDP stats (default 8125).

## Graphite settings

 * `graphite_enabled`: Enable the built-in Graphite backend (default true).
 * `graphite_port`: Port to talk to Graphite on (default 2003).
 * `graphite_host`: Host name of Graphite server (default localhost).

## Adding backends

Set the attribute `backends` to a hash of statsd NPM module
backends. The hash key is the name of the NPM module, while the hash
value is the version of the NPM module to install (or null for latest
version).

For example, to use version 0.0.1 of [statsd-librato-backend][]:

    attrs[:statsd][:backends] = { 'statsd-librato-backend' => '0.0.1' }

To use the latest version of statsd-librato-backend:

    attrs[:statsd][:backends] = { 'statsd-librato-backend' => nil }

The cookbook will install each backend module under the statsd
directory and add it to the list of backends loaded in the
configuration file.

### Extra backend configuration

Set the attribute `extra_config` to any additional configuration
options that should be included in the StatsD configuration file.

For example, to set your email and token for the
[statsd-librato-backend][] backend module, use the following:

```js
    attrs[:statsd][:extra_config] => {
      'librato' => {
        'email' => 'myemail@example.com',
        'token' => '1234567890ABCDEF'
      }
    }
```

# USAGE


[statsd-librato-backend]: https://github.com/librato/statsd-librato-backend
