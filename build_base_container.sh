#!/bin/bash

NAME_IMAGE="docker-baseimage-ubuntu-kde"
echo "Build Base Container"

docker build -f common.dockerfile -t ghcr.io/tatsuyai713/${NAME_IMAGE}:v0.01 .
docker push ghcr.io/tatsuyai713/${NAME_IMAGE}:v0.01