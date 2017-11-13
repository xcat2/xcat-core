#!/bin/bash
# IBM(c) 2017 EPL license http://www.eclipse.org/legal/epl-v10.html
#(C)IBM Corp
#
if [ -z $LC_ALL ]; then
  export LC_ALL=C
fi
# Give a simple usage
if [ -z "$1" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Setup, run and clean the simulators for performance testing..."
  echo "     $0 run <simulator>"
  exit
fi

if [ -z $PERF_SIM_ADDR ]; then
  PERF_SIM_ADDR='192.168.251.251'
fi

if [ -z $PERF_SIM_MASK ]; then
  PERF_SIM_MASK='255.255.0.0'
fi

# Optional, The NIC used by simulator.
if [ -z $PERF_SIM_NIC ]; then
  PERF_SIM_NIC='eth1'
fi

#IBM_POWER_TOOLS_URL='http://public.dhe.ibm.com/software/server/POWER/Linux/yum/OSS/RHEL/7/ppc64le'
OPEN_POWER_TOOLS_URL='http://ftp.unicamp.br/pub/ppc64el/rhel/7/docker-ppc64el'
arch=`arch`
driver="$2"
if [ "$driver" != "docker" ] && [ "$driver" != "openbmc" ]; then
    echo "Error: not supported simulator type '$driver'."
    exit -1
fi

setup_docker()
{
    if [ ! -z $1 ]; then # run on MN with --mn
        echo "Prepare on management node side..."
        prefix=$(ipcalc -p $PERF_SIM_ADDR $PERF_SIM_MASK|awk -F= '{print $2}')
        ip addr add $PERF_SIM_ADDR/$prefix dev $PERF_SIM_NIC #label $PERF_SIM_NIC:100
        return
    fi

    if [[ $arch =~ 'ppc64' ]]; then
        # The URL is from OpenPOWER Linux Community
        echo "[docker] name=Docker baseurl=$OPEN_POWER_TOOLS_URL enabled=1 gpgcheck=0" | \
        awk 'BEGIN{RS=" ";ORS="\n";}{print $0}' > /etc/yum.repos.d/docker.repo
        yum repolist
        yum install -y docker-ce bridge-utils initscripts
        service docker start
        sleep 5

    else
        echo "Error: not supported platform."
    fi

    # Create the bridge network for testing, and add the physical interface inside
    #docker network ls|grep perf-net > /dev/null && docker network rm perf-net
    netaddr=$(ipcalc -n $PERF_SIM_ADDR $PERF_SIM_MASK|awk -F= '{print $2}')
    prefix=$(ipcalc -p $PERF_SIM_ADDR $PERF_SIM_MASK|awk -F= '{print $2}')
    docker network create --gateway $PERF_SIM_ADDR --subnet $netaddr/$prefix perf-net
    bruuid=$(docker network ls | awk '/perf-net/ {print $1}')
    brctl addif br-$bruuid $PERF_SIM_NIC
    brctl show br-$bruuid

    # Prepare the docker image
    [ -f /tmp/perf/Dockerfile ] && rootpath=/tmp/perf || rootpath=/opt/xcat/share/xcat/tools/autotest/testcase/performance
    docker build -t perf-alpine-ssh $rootpath
    docker images

    # run the containers
    run_docker
}

run_docker()
{
    echo "Run docker simulator for node range..."
    script=/tmp/perf/perf-docker-create.sh
    if [ -f $script ]; then
       sh -x $script
       return
    fi

    script=/opt/xcat/share/xcat/tools/autotest/result/perf-docker-create.sh
    if [ -f $script ]; then
       sh -x $script
       return
    fi
    echo "WARN: Not found the script for run docker simulator..."
}

clean_docker()
{
    if [ ! -z $1 ]; then
        echo "Cleanup on management node side..."
        prefix=$(ipcalc -p $PERF_SIM_ADDR $PERF_SIM_MASK|awk -F= '{print $2}')
        ip addr del $PERF_SIM_ADDR/$prefix dev $PERF_SIM_NIC #label $PERF_SIM_NIC:100
        return
    fi

    ids=$(docker ps -a -q)
    [ "x" = "x$ids" ] || docker rm -f $ids
    docker network ls| grep perf-net && docker network rm perf-net
    brctl show
}

setup_openbmc()
{
    ip addr flush dev $PERF_SIM_NIC
    prefix=$(ipcalc -p $PERF_SIM_ADDR $PERF_SIM_MASK|awk -F= '{print $2}')
    #ip addr flush dev $PERF_SIM_NIC
    ip addr add $PERF_SIM_ADDR/$prefix dev $PERF_SIM_NIC #label $PERF_SIM_NIC:100

    if [ ! -z $1 ]; then
        echo "Prepare on management node side..."
        return
    fi

    which yum &>/dev/null && yum install -y git || apt install -y git
    mkdir -p /tmp/perf && cd /tmp/perf && git clone https://github.com/xuweibj/openbmc_simulator
    chmod +x /tmp/perf/openbmc_simulator/simulator
    run_openbmc
}

run_openbmc()
{
    echo "Run openbmc simulator for node range..."
    script=/tmp/perf/perf-openbmc-create.sh
    if [ -f $script ]; then
       sh $script setup
       return
    fi

    script=/opt/xcat/share/xcat/tools/autotest/result/perf-openbmc-create.sh
    if [ -f $script ]; then
       sh $script setup
       return
    fi
    echo "WARN: Not found the script for run openbmc simulator..."
}

clean_openbmc()
{
    prefix=$(ipcalc -p $PERF_SIM_ADDR $PERF_SIM_MASK|awk -F= '{print $2}')
    if [ ! -z $1 ]; then
        echo "Cleanup on management node side..."
        ip addr del $PERF_SIM_ADDR/$prefix dev $PERF_SIM_NIC #label $PERF_SIM_NIC:100
        return
    fi

    echo "Cleanup openbmc simulator for node range..."

    script=/tmp/perf/perf-openbmc-create.sh
    if [ -f $script ]; then
       sh $script clean
       ip addr del $PERF_SIM_ADDR/$prefix dev $PERF_SIM_NIC #label $PERF_SIM_NIC:100
       return
    fi

    script=/opt/xcat/share/xcat/tools/autotest/result/perf-openbmc-create.sh
    if [ -f $script ]; then
       sh $script clean
       ip addr del $PERF_SIM_ADDR/$prefix dev $PERF_SIM_NIC #label $PERF_SIM_NIC:100
       return
    fi
    echo "WARN: Not found the script for run openbmc simulator..."
}


# Mail program
if [ "$1" = "setup" ]; then
    eval "setup_$driver $3"
elif [ "$1" = "clean" ]; then
    eval "clean_$driver $3"
else
    echo "Error: not supported action."
    exit -1
fi