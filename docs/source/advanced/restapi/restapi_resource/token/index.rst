Token Resources
===============

The URI list which can be used to create tokens for account .

/tokens
-------

POST - Create a token.
``````````````````````

**Returns:**

* An array of all the global configuration list.

**Example:** 

Aquire a token for user 'root'. :: 


    curl -X POST -k 'https://127.0.0.1/xcatws/tokens?userName=root&userPW=cluster&pretty=1' \
       -H Content-Type:application/json --data '{"userName":"root","userPW":"cluster"}'
    {
       "token":{
          "id":"a6e89b59-2b23-429a-b3fe-d16807dd19eb",
          "expire":"2014-3-8 14:55:0"
       }
    }

