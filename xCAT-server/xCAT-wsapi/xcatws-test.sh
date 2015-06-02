#! /bin/sh


# Get all the parameters
for i in $@
do
  if [ "$paramname" = "USER" ]; then
    USER=$i
    paramname=
  fi
  if [ "$paramname" = "PW" ]; then
    PW=$i
    paramname=
  fi
  if [ "$paramname" = "HOST" ]; then
    HOST=$i
    paramname=
  fi

  if [ $i = '-u' ]; then
    paramname=USER
  fi
  if [ $i = '-p' ]; then
    paramname=PW
  fi
  if [ $i = '-h' ]; then
    paramname=HOST
  fi
  if [ $i = '-c' ]; then
    cert=yes
  fi
  if [ $i = '-t' ]; then
    token=yes
  fi
 
done

# display the usage message
function usage {
  echo "Usage:"
  echo "  xcatws-test.sh -u <USER> -p <pw> [-t]"
  echo "  xcatws-test.sh -u <USER> -p <pw> -h <FQDN - Full hostname of server> [-c] [-t]"
  echo "    -u  The username of xCAT user which is used to access xCAT resource"
  echo "    -p  The userPW of username"
  echo "    <FQDN of xCAT MN>  The fully qualified hostname of xCAT management node. It can be an IP if using -k."
  echo "    -c  Check the server identity. The server certificate authentication must be enabled."
  echo "    -t  Using token authentication method."
}

if [ "$USER" = "" ] || [ "$PW" = "" ]; then
  echo "Error: Miss username or userPW"
  usage
  exit 1
fi 

if [ "$cert" = "yes" ] && [ "$HOST" = "" ]; then
  echo "Error: -c must be used with -h that user needs specify the FQDN of xCAT MN"
  usage
  exit 1
fi

if [ "$HOST" = "" ]; then
  HOST="127.0.0.1"
fi


ctype='-H Content-Type:application/json'

# Perform the REST API request
function REST {
  METHOD=$1  # it should be GET/PUT/POST/DELETE
  SRC=$2  # The resource path like /nodes/node1
  DATA=$3 # The operation data for PUT/POST/DELETE
  if [ "$DATA" != "" ]; then
      datamsg="$ctype -d $DATA"
  fi
  if [ "$cert" = "yes" ]; then
    if [ "$token" = "yes" ]; then
      CMD="curl -X $METHOD --cacert /tmp/ca-cert.pem -H X-Auth-Token:$TOKENID $datamsg https://$HOST/xcatws$SRC?pretty=1"
    else
      CMD="curl -X $METHOD --cacert /tmp/ca-cert.pem $datamsg https://$HOST/xcatws$SRC?pretty=1&userName=$USER&passwor=$PW"
    fi
  else 
    if [ "$token" = "yes" ]; then
      CMD="curl -X $METHOD -k -H X-Auth-Token:$TOKENID $datamsg https://$HOST/xcatws$SRC?pretty=1"
    else 
      CMD="curl -X $METHOD -k $datamsg https://$HOST/xcatws$SRC?pretty=1&userName=$USER&userPW=$PW"
    fi
  fi

  echo "-------------------------------------------------------------------------------"
  echo "Run: [$RESTMSG]"
  echo "  $CMD"
  echo "Output:"
  `$CMD 2>/dev/null >/tmp/xcatws-test.log`
  cat "/tmp/xcatws-test.log"
  echo ""

  ERROR=`grep "errorcode" "/tmp/xcatws-test.log"`
  if [ "$ERROR" != "" ]; then
     echo "FAILED to continue. See the error message in 'error' section."
     echo ""
     exit 2
  fi
}

function PUT {
  SRC=$1
}

# echo debug message
echo "***********************************************************"
echo "** Username: $USER"
echo "** Password: $PW"
echo "** Hostname: $HOST" 


# get the CA of server certificate
if [ "$cert" = "yes" ]; then
  rm -f /tmp/ca-cert.pem
  cd /tmp
  wget http://$HOST/install/postscripts/ca/ca-cert.pem  2>1 1>/dev/null
  echo "** Using CA /tmp/ca-cert.pem for server certificate checking" 
fi

# get a token
if [ "$token" = "yes" ]; then
  TOKENID=$(curl -X POST -k "https://$HOST/xcatws/tokens?pretty=1" -H Content-Type:application/json --data "{\"userName\":\"$USER\",\"userPW\":\"$PW\"}" 2>/dev/null | grep '"id"' | awk -F: {'print $2'} | awk -F \" {'print $2'})
  echo "** Using Token: $TOKENID to authenticate"
fi

echo "***********************************************************"
echo ""

# clean the env
rmdef -t node restapinode[1-9] 1>/dev/null 2>1
rmdef -t group restapi 1>/dev/null 2>1

# get all resources
RESTMSG="Get all available resource"
REST GET "/"

# test global conf
RESTMSG="Get all global configuration resource"
REST GET "/globalconf"

RESTMSG="Change the global configuration domain to cluster.com"
REST PUT "/globalconf/attrs/domain" '{"domain":"cluster.com"}'

RESTMSG="Get the global configuration domain"
REST GET "/globalconf/attrs/domain"

# test node create/change/list/delete
RESTMSG="Create node restapinode1"
REST POST "/nodes/restapinode1" '{"groups":"restapi","arch":"x86_64","mgt":"ipmi","netboot":"xnba"}'

RESTMSG="Display the node restapinode1"
REST GET "/nodes/restapinode1"

RESTMSG="Change the attributes for node restapinode1"
REST PUT "/nodes/restapinode1" '{"mgt":"fsp","netboot":"yaboot"}'

RESTMSG="Display the node restapinode1"
REST GET "/nodes/restapinode1"

RESTMSG="Delete node restapinode1"
REST DELETE "/nodes/restapinode1"

# test multiple nodes manipulation
RESTMSG="Create node restapinode1 and restapinode2"
REST POST "/nodes/restapinode1,restapinode2" '{"groups":"restapi","arch":"x86_64","mgt":"ipmi","netboot":"xnba"}'

RESTMSG="Display the node restapinode1 and restapinode2"
REST GET "/nodes/restapinode1,restapinode2"

RESTMSG="Change the attributes for node restapinode1 and restapinode2"
REST PUT "/nodes/restapinode1,restapinode2" '{"mgt":"hmc","netboot":"grub2"}'

RESTMSG="Display the node restapinode1 and restapinode2"
REST GET "/nodes/restapinode1,restapinode2"

RESTMSG="Display all the nodes in the cluster"
REST GET "/nodes"

# test group 
RESTMSG="Display the group restapi"
REST GET "/groups/restapi"

RESTMSG="Change attributes for group restapi"
REST PUT "/groups/restapi" '{"os":"rh7"}'

RESTMSG="Display the group restapi"
REST GET "/groups/restapi"

RESTMSG="Display the nodes in group restapi"
REST GET "/nodes/restapi"

