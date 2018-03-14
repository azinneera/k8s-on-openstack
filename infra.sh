#!/bin/bash

# Log Message should be parsed $1
log(){
    TIME=`date`
    echo "$TIME : $1"
    return
}

function usage()
{
    echo "
    This script will spawn a Kubernetes cluster with configuration values provided in terraform.tfvars file you can provide these values to
    the script itself

    Usage bash infra.sh --node-count=3 --network=your-network.....

    Following are the expected input parameters. all of these are optional

    !=========================== Following Paramters are read from terraform.tfvars file if not passed to the script ========================!

    --node-count   | -nc     : Number of vms that will be spawned for the kubernes cluster
    --network      | -net    : Network ip pool name
    --image-name   | -img    : This image will be used as the base image for kubernets cluster
    --image-flavor | -img-fl : The openstack image size Ex:m1.medium,m1.large etc.
    --key-pair     | -k      : The key pair that will be used to access the spawned instance. this key pair shoudl be pre configured
    --output-dir   | -o      : kubernetes master will be written to a file in this path

    !====================== Following paramters are not needed if openrc.sh is executed beforehand ==========================================!

    --openstack-auth-url    | -os-url      : OpenStack URL
    --openstack-tenant-id   | -os-tenant   : Tenant id for OpenStack
    --openstack-tenant-name | -os-tenant   : Tenant name for Openstack
    --openstack-username    | -os-username : Openstack username for login
    --openstack-password    | -os-password : Openstack password for login
    --openstack-region      | -os-region   : The cluster will be created in this region.
    "
}

dir=$(cd -P -- "$(dirname -- "$0")" && pwd -P)
cd $dir

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
        ;;
        --node-count | -nc )
            NODE_COUNT=$VALUE
            echo $NODE_COUNT
        ;;
        --network | -net )
            NETWORK=$VALUE
            echo $NETWORK
        ;;
        --image-name | -img )
            IMAGE=$VALUE
            echo $IMAGE
        ;;
        --image-flavor | -img-fl )
            FLAVOR=$VALUE
            echo $FLAVOR
        ;;
        --key-pair | -k )
            KEYPAIR=$VALUE
            echo $KEYPAIR
        ;;
        --output-dir | -o )
            OUTPUT=$VALUE
            echo $OUTPUT
        ;;
        --openstack-auth-url | -os-url )
            OS_AUTH_URL_INPUT=$VALUE
            echo $OS_AUTH_URL_INPUT
        ;;
        --openstack-tenant-id | -os-id )
            OS_TENANT_ID_INPUT=$VALUE
            echo $OS_TENANT_ID_INPUT
        ;;
        --openstack-tenant-name | -os-tenant )
            OS_TENANT_NAME_INPUT=$VALUE
            echo $OS_TENANT_NAME_INPUT
        ;;
        --openstack-username | -os-username )
            OS_USERNAME_INPUT=$VALUE
            echo $OS_USERNAME_INPUT
        ;;
        --openstack-password | -os-password )
            OS_PASSWORD_INPUT=$VALUE
            echo $OS_PASSWORD_INPUT
        ;;
        --openstack-region | -os-region )
            OS_REGION_INPUT=$VALUE
            echo $OS_REGION_INPUT
        ;;
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            usage
        ;;
    esac
    shift
done

#edit terraform.tfvars to arguments
sed -i "s/node-count=\"[0-9]*\"/node-count=\"$NODE_COUNT\"/g" terraform.tfvars
sed -i "s/internal-ip-pool=\"[a-z_A-Z]*\"/internal-ip-pool=\"$NETWORK\"/g" terraform.tfvars
sed -i "s/image-name=\".*\"/image-name=\"$IMAGE\"/g" terraform.tfvars
sed -i "s/image-flavor=\".*\"/image-flavor=\"$FLAVOR\"/g" terraform.tfvars
sed -i "s/key-pair=\".*\"/key-pair=\"$KEYPAIR\"/g" terraform.tfvars
#Replace the output path of output file
sed -i "s|k8s.properties|$OUTPUT\/k8s.properties|g" 01-create-inventory.tf

#set environment varibale for openstack
export OS_AUTH_URL=$OS_AUTH_URL_INPUT

# With the addition of Keystone we have standardized on the term **tenant**
# as the entity that owns the resources.
export OS_TENANT_ID=$OS_TENANT_ID_INPUT
export OS_TENANT_NAME="$OS_TENANT_NAME_INPUT"

# In addition to the owning entity (tenant), openstack stores the entity
# performing the action as the **user**.
export OS_USERNAME="$OS_USERNAME_INPUT"

# With Keystone you pass the keystone password.
#echo "Please enter your OpenStack Password: "
#read -sr OS_PASSWORD_INPUT
export OS_PASSWORD="$OS_PASSWORD_INPUT"

# If your configuration has multiple regions, we set that information here.
# OS_REGION_NAME is optional and only valid in certain environments.
export OS_REGION_NAME="$OS_REGION_INPUT"
# Don't leave a blank variable, unset it if it was empty
if [ -z "$OS_REGION_NAME" ]; then unset OS_REGION_NAME; fi

prgdir=$(dirname "$0")
script_path=$(cd "$prgdir"; pwd)

log "===The Jenkins Main Script Logs===="
log "Checking the Environment variables;"
if [ -z $OS_TENANT_ID ]; then
    log "OS_TENANT_ID is not set as a environment variable"
    exit 1;
fi

if [ -z $OS_TENANT_NAME ]; then
    log "OS_TENANT_ID is not set as a environment variable"
    exit 1;
fi

if [ -z $OS_USERNAME ]; then
    log "OS_TENANT_ID is not set as a environment variable"
    exit 1;
fi

if [ -z $OS_PASSWORD ]; then
    log "OS_TENANT_ID is not set as a environment variable"
    exit 1;
fi

# Seems script is not picking TERRA_HOME from the system, hence as a workaroubd setting the path
TERRA_HOME=/etc/terraform
export PATH=$TERRA_HOME:$PATH

# Trigering the Ansible Scripts to do the kubernetes cluster
source $script_path/cluster-create.sh

log "Successfully Finished Execution..."
