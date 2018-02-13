#!/bin/bash
current_loc=$(pwd)
nodes=('wso2is-mysql-kubernetes-5.7.tar' 'wso2is-kubernetes-5.4.0.tar');

sudo mkdir -p mount
sudo mount $1:/exports/is-docker $current_loc/mount
sudo mkdir -p $current_loc/docker_images

for i in "${nodes[@]}"
do
     sudo docker load -i $current_loc/mount/$i
done





