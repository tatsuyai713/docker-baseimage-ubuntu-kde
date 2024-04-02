#!/bin/bash

PASSWORD="test"

if [ $# -ne 1 ]; then
	echo "Please select GPU. (gpu0, gpu1,..., all or none(default))"
	exit
fi

GPU=$1
GPU_OPTION="none"

if [ "gpu0" = $GPU ]; then
	GPU_OPTION="device=0"
fi
if [ "gpu1" = $GPU ]; then
	GPU_OPTION="device=1"
fi
if [ "gpu2" = $GPU ]; then
	GPU_OPTION="device=2"
fi
if [ "gpu3" = $GPU ]; then
	GPU_OPTION="device=3"
fi
if [ "all" = $GPU ]; then
	GPU_OPTION=all
fi

echo "GPU OPTION is ${GPU_OPTION}"

NAME_IMAGE="docker-baseimage-ubuntu-kde_for_${USER}"
DOCKER_NAME="docker-baseimage-ubuntu-kde_${USER}"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd $SCRIPT_DIR

if [ "$(docker ps -al | grep ${DOCKER_NAME})" ]; then
	echo "docker container already started...(GPU option is ignored.)"
	CONTAINER_ID=$(docker ps -a | grep ${DOCKER_NAME} | awk '{print $1}')
	
	rm -rf /tmp/.docker.xauth
	XAUTH=/tmp/.docker.xauth
	touch $XAUTH
	xauth_list=$(xauth nlist :0 | sed -e 's/^..../ffff/')
	if [ ! -z "$xauth_list" ]; then
		echo $xauth_list | xauth -f $XAUTH nmerge -
	fi
	chmod a+r $XAUTH

	docker start $CONTAINER_ID
	exit
fi

nohup ./launch_container.sh ${GPU_OPTION} > /tmp/nohup_${USER}.out 2>&1 &

sleep 3
echo ""
echo "_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/"
echo "_/   Please access 'https://localhost:1`id -u`'    _/"
echo "_/     or 'https://<PC IP ADDRESS>:1`id -u`'       _/"
echo "_/            RDP Port is 2`id -u`                 _/"
echo "_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/_/"
