#!/bin/bash
# ------------------------------------------------------------------------
#
# Copyright 2018 WSO2, Inc. (http://wso2.com)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# ------------------------------------------------------------------------

export KUBERNETES_MASTER=$1
artefacts_dir="kubernetes-is"
default_port=32111

# Log Message should be parsed $1
log(){
 TIME=`date`
 #echo "$TIME : $1" >> "$LOG_FILE_LOCATION"
 echo "$TIME : $1"
 return
}

temp=${1#*//}
Master_IP=${temp%:*}
prgdir=$(dirname "$0")
script_path=$(cd "$prgdir"; pwd)
source "base.sh"

while getopts :h FLAG; do
    case $FLAG in
        h)
            showUsageAndExitDefault
            ;;
        \?)
            showUsageAndExitDefault
            ;;
    esac
done

validateKubeCtlConfig

# download IS 5.4.0 docker images
nodes=$(kubectl get nodes --output=jsonpath='{ $.items[*].status.addresses[?(@.type=="LegacyHostIP")].address }')
delete=($Master_IP)
nodes=( "${nodes[@]/$delete}" )

echo "Loading docker images to nodes..."
for node in $nodes; do
     ssh core@$node "bash -s" < load-docker-images.sh $2
done

echo "Cloning into repo kubernetes-is..."
#checkout WSO2 kubernetes-is repository
if [ -d ${artefacts_dir} ] ; then
    rm -rf ${artefacts_dir}
fi
env -i git clone https://github.com/wso2/kubernetes-is.git

#change directory to pattern-1
cd kubernetes-is/pattern-1

#Replace NFS server IP
echo "Adding NFS server IP"
sed -i -E 's/server:\s+[0-9.]{7,15}/server: '$2'/g' is-nfs-persistent-volume.yaml
sed -i -E 's/image: docker.wso2.com/image: '$3'/g' mysql-deployment.yaml
sed -i -E 's/image: docker.wso2.com/image: '$3'/g' is-deployment.yaml

#1-Create NFS persistent volume
echo "Creating NFS persistent volume..."
kubectl create -f is-nfs-persistent-volume.yaml

#2-Create configuration maps:
echo "Creating configuration maps..."
kubectl create configmap is-conf --from-file=conf/is/conf/
kubectl create configmap is-conf-datasources --from-file=conf/is/conf/datasources/
kubectl create configmap is-conf-identity --from-file=conf/is/conf/identity/
kubectl create configmap is-conf-axis2 --from-file=conf/is/conf/axis2/
kubectl create configmap is-conf-tomcat --from-file=conf/is/conf/tomcat/

#3-Deploy and run MySQL service:
echo "Deploying and running MySQL service..."
kubectl create -f mysql-service.yaml
kubectl create -f mysql-deployment.yaml

# Waiting for mysql-db to run. Current loop timer is 100*50 Sec.
for number in {1..100}
do
echo $(date)" Waiting for mysql to start!"
 if [ "Running" == "$(kubectl get po | grep mysql | awk '{print $3}')" ]
 then
  break
 fi
sleep 3
done

sleep 30

#4-Deploy and run WSO2 Identity Server service:
echo "Deploying and running WSO2 Identity Server service..."
kubectl create -f is-service.yaml
kubectl create -f is-nfs-volume-claim.yaml
kubectl create -f is-deployment.yaml

#5-Deploy and run Nginx Ingress service:
echo "Deploy and run Nginx Ingress service"
kubectl create -f nginx-default-backend.yaml
kubectl create -f nginx-ingress-controller.yaml
kubectl create -f is-ingress.yaml

#6-Scale up using kubectl scale:

#Default deployment runs two replicas (or pods) of WSO2 Identity server. To scale this deployment into 
#any <n> number of container replicas, upon your requirement, simply run following kubectl command on the terminal. Assuming your current working directory is KUBERNETES_HOME/pattern-1

#kubectl scale --replicas=<n> -f is-deployment.yaml

sleep 30

echo 'Generating the deployment.json..'
default "${default_port}"
pods=$(kubectl get pods --output=jsonpath={.items..metadata.name})
json='{ "hosts" : ['
for pod in $pods; do
         hostip=$(kubectl get pods "$pod" --output=jsonpath={.status.hostIP})
         echo $hostip
         lable=$(kubectl get pods "$pod" --output=jsonpath={.metadata.labels.name})
         echo $lable
         servicedata=$(kubectl describe svc "$lable")
         echo $servicedata
         json+='{"ip" :"'$hostip'", "label" :"'$lable'", "ports" :['
         declare -a dataarray=($servicedata)
         let count=0
         for data in ${dataarray[@]}  ; do
            if [ "$data" = "NodePort:" ]; then
            IFS='/' read -a myarray <<< "${dataarray[$count+2]}"
            json+='{'
            json+='"protocol" :"'${dataarray[$count+1]}'",  "portNumber" :"'${myarray[0]}'"'
            json+="},"
            fi

         ((count+=1))
         done
         i=$((${#json}-1))
         lastChr=${json:$i:1}

         if [ "$lastChr" = "," ]; then
         json=${json:0:${#json}-1}
         fi

         json+="]},"

done
json=${json:0:${#json}-1}

json+="]}"
echo $json;

cat > $script_path/deployment.json << EOF1
$json
EOF1
