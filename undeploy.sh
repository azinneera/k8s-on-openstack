#!/bin/bash
# ------------------------------------------------------------------------
#
# Copyright 2016 WSO2, Inc. (http://wso2.com)
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
# limitations under the License

# ------------------------------------------------------------------------
prgdir=$(dirname "$0")
script_path=$(cd "$prgdir"; pwd)

cd $script_path/kubernetes-is/pattern-1
#Undeploy Nginx Ingress service:

kubectl delete -f is-ingress.yaml
kubectl delete -f nginx-ingress-controller.yaml
kubectl delete -f nginx-default-backend.yaml

#Undeploy WSO2 Identity Server service:

kubectl delete -f is-deployment.yaml
kubectl delete -f is-nfs-volume-claim.yaml
kubectl delete -f is-service.yaml

#Undeploy MySQL service:

kubectl delete -f mysql-deployment.yaml
kubectl delete -f mysql-service.yaml

#Delete configuration maps:

kubectl delete configmap is-conf
kubectl delete configmap is-conf-datasources
kubectl delete configmap is-conf-identity
kubectl delete configmap is-conf-axis2
kubectl delete configmap is-conf-tomcat

#Delete NFS persistent volume:

kubectl delete -f is-nfs-persistent-volume.yaml
