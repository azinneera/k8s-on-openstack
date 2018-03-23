#!/bin/bash
artefacts_dir="kubernetes-is"
default_port=32111

while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
     #       usage
            exit
            ;;
        --KUBERNETES_MASTER | -km )
            KUBERNETES_MASTER=$VALUE
            echo $KUBERNETES_MASTER
            ;;
        --docker-username | -du )
            USERNAME=$VALUE
            echo $USERNAME
            ;;
        --docker-password | -dp )
            PASSWORD=$VALUE
            echo $PASSWORD
            ;;            
        --network-drive | -nfs )
            NFS=$VALUE
            echo $NFS
            ;;    
        --workspace | -o )
            OUTPUT=$VALUE
            echo $OUTPUT
            ;;             
        *)
            echo "ERROR: unknown parameter \"$PARAM\""
            ;;
    esac
    shift
done

export KUBERNETES_MASTER=$KUBERNETES_MASTER
echo $KUBERNETES_MASTER
env | grep "KUBERNETES_MASTER"

DOCKER_URL="dockerhub.private.wso2.com"

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
source "$script_path/base.sh"

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

kubectl create secret docker-registry registrykey --docker-server=$DOCKER_URL --docker-username=$USERNAME --docker-password=$PASSWORD --docker-email="$USERNAME@wso2.com"

# download IS 5.4.0 docker images
nodes=$(kubectl get nodes --output=jsonpath='{ $.items[*].status.addresses[?(@.type=="LegacyHostIP")].address }')
delete=($Master_IP)
nodes=( "${nodes[@]/$delete}" )

cd $script_path
echo "Loading docker images to nodes..."
for node in $nodes; do
     ssh core@$node "bash -s" < $script_path/load-docker-images.sh $NFS
done

echo "Cloning into repo kubernetes-is..."
#checkout WSO2 kubernetes-is repository
if [ -d ${artefacts_dir} ] ; then
    rm -rf ${artefacts_dir}
fi
env -i git clone https://github.com/wso2/kubernetes-is.git

#change directory to pattern-1
cd $script_path/kubernetes-is/pattern-1

#Replace NFS server IP
echo "Adding NFS server IP"
sed -i -E 's/server:\s+[0-9.]{7,15}/server: '$NFS'/g' is-nfs-persistent-volume.yaml
sed -i -E 's/image: docker.wso2.com/image: '$DOCKER_URL'/g' mysql-deployment.yaml
sed -i -E 's/image: docker.wso2.com/image: '$DOCKER_URL'/g' is-deployment.yaml

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

echo "Adding host details to /etc/hosts..."
ingress=$(kubectl get ingress --output=jsonpath='{ $.items[*].metadata.name}')
for item in $ingress; do
    address=$(kubectl get ingress $item --output=jsonpath='{ $.status.loadBalancer.ingress[*].ip}')
    hosts=$(kubectl get ingress $item --output=jsonpath='{$.spec.rules[*].host}')
    str=$address" "$hosts
    sudo sed -i "/The following lines are desirable for IPv6 capable hosts/i\\$str" /etc/hosts
done

echo 'Generating the deployment.json..'

#create deployment.json
json='{ "hosts" : ['
ingress=$(kubectl get ingress --output=jsonpath={.items[*].spec.rules[*].host})
for item in $ingress; do
         json+='{"ip" :"'$item'", "label" :"'$item'", "ports" :['
            json+='{'
            json+='"protocol" : "servlet-http",  "portNumber" :"80"},{'
            json+='"protocol" : "servlet-https",  "portNumber" :"443"'
            json+="}"
         json+="]},"
done

json=${json:0:${#json}-1}

json+="]}"
echo $json;

cat > $OUTPUT/deployment.json << EOF1
$json
EOF1
