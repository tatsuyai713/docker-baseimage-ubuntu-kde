#!/bin/bash

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
cd $SCRIPT_DIR
./launch_container.sh delete
