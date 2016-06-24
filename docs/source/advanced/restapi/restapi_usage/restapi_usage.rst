The Resource Categories
=======================

The API lets you query, change, and manage the resources in following categories:

  * Token Resources
  * Node Resources
  * Osimage Resources
  * Network Resources
  * Policy Resources
  * Group Resources
  * Global Configuration Resources
  * Service Resources
  * Table Resources


The Authentication Methods for REST API
=======================================

xCAT REST API supports two ways to authenticate the access user: user account (username + password) and access token (acquired by username + password).

User Account
------------

Follow the steps in :doc:`WEB Service Setup </advanced/restapi/restapi_setup/index>`, you can create an account for yourself. Then use that username and password to access the https server.

The general format of the URL used in the REST API call is: ::

    https://<FQDN of xCAT MN>/xcatws/<resource>?userName=<user>&userPW=<pw>&<parameters>

where:

  * **FQDN of xCAT MN**: the hostname of the xCAT management node. It also can be the IP of xCAT MN if you don't want to enable the web server certificate
  * **resource**: one of the xCAT resources listed above
  * **user**: the userid that the operation should be run on behalf of. See the previous section on how to add/authorize a userid.
  * **pw**: the password of the userid (can be the salted version from /etc/shadow)

Example: ::

    curl -X GET --cacert /root/ca-cert.pem 'https://<FQDN of xCAT MN>/xcatws/nodes?userName=root&userPW=cluster'

Access Token
------------

xCAT also supports the use the Access Token to replace the using of username+password in every access. Before accessing any resource, you need get a token with your account (username+password) ::

    # curl -X POST --cacert /root/ca-cert.pem \
        'https://<FQDN of xCAT MN>/xcatws/tokens?pretty=1' -H Content-Type:application/json --data \
        '{"userName":"root","userPW":"cluster"}'
     {
        "token":{
          "id":"5cabd675-bc2e-4318-b1d6-831fd1f32f97",
          "expire":"2014-3-10 9:56:12"
        }
     }

Then in the subsequent REST API access, the token can be used to replace the user account (username+password)  ::

    curl -X GET --cacert /root/ca-cert.pem -H X-Auth-Token:5cabd675-bc2e-4318-b1d6-831fd1f32f97 'https://<FQDN of xCAT MN>/xcatws/<resource>?<parameters>

The validity of token is 24 hours. If an old token has expired, you will get a 'Authentication failure' error. Then you need reacquire a token with your account.


The Common Parameters for Resource URI
======================================

xCAT REST API supports several common parameters in the resource URI to enable specific output:

* **pretty=1** \- It is used to format the json output for easier viewing on the screen. ::

    https://<xCAT MN>/xcatws/nodes?pretty=1

* **debug=1** \- It is used to display more debug messages for a REST API request. ::

    https://<xCAT MN>/xcatws/nodes?debug=1

* **xcoll=1** \- It is used to specify that the output should be grouped with the values of objects. ::

    GET https://<xCAT MN>/xcatws/nodes/node1,node2,node3/power?xcoll=1
     {
       "node2":{
         "power":"off"
       },
       "node1,node3":{
         "power":"on"
       }
     }

``Note:`` All the above parameters can be used together like following: ::

    https://<xCAT MN>/xcatws/nodes?pretty=1&debug=1


The Output of REST API request
==============================

xCAT REST API only supports the [JSON](http://www.json.org/) formatted output.

When an Error occurs during the operation
-----------------------------------------

(i.e. there's error/errorcode in the output of xcat xml response):

When error happens, for all the GET/PUT/POST/DELETE methods, the output will only include 'error' and 'errorcode' properties: ::

    {
       error:[
           msg1,
           msg2,
           ...
       ],
       errorcode:error_number
    }

When NO Error occurs during the operation
-----------------------------------------

(i.e. there's no error/errorcode in the output of xcat xml response):

For the GET method
``````````````````

If the output can be grouped by the object (resource) name, and the information being returned are attributes of the object, then use the object name as the hash key and make the value be a hash of its attributes/values: ::

    {
      object1: {
         a1: v1,
         a2: v2,
         ...
      },
      object2: {
         a1: v1,
         a2: v2,
         ...
      },
    }

If the output can be grouped by the object (resource) name, but the information being returned is **not** attributes of the object, then use the object name as the hash key and make the value be an array of strings: ::

    {
      object1: [
         msg1,
         msg2,
         ...
      ],
      object2: [
         msg1,
         msg2
         ...
      ],
    }

An example of this case is the output of reventlog: ::

    {
      "node1": [
         "09/07/2013 10:05:02 Event Logging Disabled, Log Area Reset/Cleared (SEL Fullness)",
         ...
      ],
    }

If the output is not object related, put all the output in a list (array): ::

    [
       msg1,
       msg2,
       ...
    ]

For the PUT/DELETE methods
``````````````````````````

There will be no output for operations that succeeded. (We made this decision because the output for them not formatted, and no program will read it if xcat indicates the operation has succeeded.)

For POST methods
````````````````

Since POST methods can either be creates or general actions, there is not much consistency. In the case of a create, the rule is the same as PUT/DELETE (no output if successful). For actions that have output that matters (e.g. nodeshell, filesyncing, sw, postscript), the rules are like the GET method.


Testing the API
===============

Normally you will make REST API calls from your code. You can use any language that has REST API bindings (most modern languages do).

An Example of How to Use xCAT REST API from PERL
------------------------------------------------

Refer to the file /opt/xcat/ws/xcatws-test.pl: ::

    ./xcatws-test.pl -m GET -u "https://127.0.0.1/xcatws/nodes?userName=root&userPW=cluster"

An Example Script of How to Use curl to Test Your xCAT REST API Service
-----------------------------------------------------------------------

It can be used as an example script to access and control xCAT resources. From the output message, you also could get the idea of how to access xCAT resources. ::

    /opt/xcat/ws/xcatws-test.sh
    ./xcatws-test.sh -u root -p cluster
    ./xcatws-test.sh -u root -p cluster -h <FQDN of xCAT MN>
    ./xcatws-test.sh -u root -p cluster -h <FQDN of xCAT MN> -c
    ./xcatws-test.sh -u root -p cluster -h <FQDN of xCAT MN> -t
    ./xcatws-test.sh -u root -p cluster -h <FQDN of xCAT MN> -c -t

But for exploration and experimentation, you can make API calls from your browser or using the **curl** command.

To make an API call from your browser, uses the desired URL from this document. To simplify the test step, all the examples for the resources uses 'curl -k' to use insecure http connection and use the 'username+password' to authenticate the user. ::

    curl -X GET -k 'https://myserver/xcatws/nodes?userName=xxx&userPW=xxx&pretty=1'

Examples of making an API call using curl
-----------------------------------------

* **To query resources:** ::

    curl -X GET -k 'https://xcatmnhost/xcatws/nodes?userName=xxx&userPW=xxx&pretty=1'

* **To change attributes of resources:** ::

    curl -X PUT -k 'https://xcatmnhost/xcatws/nodes/{noderange}?userName=xxx&userPW=xxx' \
       -H Content-Type:application/json --data '{"room":"hi","unit":"7"}'

* **To run an operation on a resource:** ::

    curl -X POST -k 'https://xcatmnhost/xcatws/nodes/{noderange}?userName=xxx&userPW=xxx' \
       -H Content-Type:application/json --data '{"groups":"wstest"}'

* **To delete a resource:** ::

    curl -X DELETE -k 'https://xcatmnhost/xcatws/nodes/{noderange}?userName=xxx&userPW=xxx'


Web Service Status Codes
========================

Here are the HTTP defined status codes that the Web Service can return:

  * 401 Unauthorized
  * 403 Forbidden
  * 404 Not Found
  * 405 Method Not Allowed
  * 406 Not Acceptable
  * 408 Request Timeout
  * 417 Expectation Failed
  * 418 I'm a teapot
  * 503 Service Unavailable
  * 200 OK
  * 201 Created

References
==========

  * REST: http://en.wikipedia.org/wiki/Representational_State_Transfer
  * REST: http://rest.elkstein.org/2008/02/what-is-rest.html
  * HTTP Status codes: http://www.w3.org/Protocols/rfc2616/rfc2616-sec10.html
  * HTTP Request Methods: http://tools.ietf.org/html/rfc2616#section-9.1
  * HTTP Request Tool: http://soft-net.net/SendHTTPTool.aspx (haven't tried it yet)
  * HTTP PATCH: http://tools.ietf.org/html/rfc5789
  * HTTP BASIC Security: http://httpd.apache.org/docs/2.2/mod/mod_auth_basic.html
  * Asynchronous Rest: http://www.infoq.com/news/2009/07/AsynchronousRest
  * General JSON: http://www.json.org/
  * JSON wrapping: http://search.cpan.org/~makamaka/JSON-2.27/lib/JSON.pm
  * Apache CGI: http://httpd.apache.org/docs/2.2/howto/cgi.html
  * Perl CGI: http://perldoc.perl.org/CGI.html

