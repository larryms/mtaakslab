#
group=mtakubelab
region=WestUS2

az group create -n $group -l $region


az aks get-versions -l $region -o table

az aks create -g $group -n aks-cluster -l $region \
--node-count 3 --node-vm-size Standard_DS2_v2 \
--kubernetes-version 1.11.8 --verbose  

kubectl cluster-info
kubectl get nodes
kubectl get all -n kube-system

kubectl create clusterrolebinding kubernetes-dashboard \
--clusterrole=cluster-admin \
--serviceaccount=kube-system:kubernetes-dashboard
az aks browse -g $group -n aks-cluster

# Lab 2
ACR_NAME="lncmta032719"
az acr create -n $ACR_NAME -g $group -l $region --sku Standard --admin-enabled true

# lncmta032719.azurecr.io
ACR_PWD=`az acr credential show -n $ACR_NAME -g $group --query "passwords[0].value" -o tsv`

kubectl create secret docker-registry acr-auth --docker-server $ACR_NAME.azurecr.io \
  --docker-username $ACR_NAME --docker-password $ACR_PWD --docker-email ignore@dummy.com

az acr build --registry $ACR_NAME -g $group --file node/data-api/Dockerfile \
    --image smilr/data-api https://github.com/benc-uk/smilr.git
az acr build --registry $ACR_NAME -g $group --file node/frontend/Dockerfile \
    --image smilr/frontend https://github.com/benc-uk/smilr.git
az acr repository list -g $group --name $ACR_NAME -o table

# Lab 3
mkdir kube-lab
cd kube-lab

kubectl apply -f mongo.deploy.yaml
kubectl get all
kubectl describe pod -l app=mongodb
kubectl get pod -l app=mongodb -o=jsonpath='{.items[0].status.podIP}{"\n"}'
#  10.240.1.2

kubectl apply -f data-api.deploy.yaml
kubectl logs -l app=data-api

#
kubectl get pods
kubectl port-forward data-api-754f96bc59-vckfn 8080:4000

# part 4
kubectl apply -f mongo.svc.yaml
kubectl apply -f data-api.deploy.yaml

kubectl apply -f data-api.svc.yaml

kubectl get service
# 52.247.200.40   
curl http://52.247.200.40/api/info

# Lab 5
cat >frontend.svc.yaml <<EOF
kind: Service
apiVersion: v1
metadata:
  name: frontend-svc
spec:
  type: LoadBalancer
  ports:
  - protocol: TCP
    port: 80
    targetPort: 3000
  selector:
    app: frontend
EOF

kubectl apply -f frontend.svc.yaml
# 13.66.168.104 

cat >frontend.deploy.yaml <<EOF
kind: Deployment
apiVersion: apps/v1
metadata:
  name: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: frontend-pod
        image: lncmta032719.azurecr.io/smilr/frontend
        ports:
        - containerPort: 3000
        env:
        - name: API_ENDPOINT
          value: http://52.247.200.40/api
      imagePullSecrets:
      - name: acr-auth
EOF

kubectl apply -f frontend.deploy.yaml

#
kubectl get pods -l app=data-api
kubectl exec -it {pod_name} bash

# lab 6
kubectl scale --replicas=3 deploy/data-api

kubectl scale --replicas=3 deploy/frontend
kubectl get pods -o wide -l app=frontend


#
cat >mongo.stateful.yaml <<EOF
kind: StatefulSet
apiVersion: apps/v1
metadata:
  name: mongodb
spec:
  serviceName: mongodb
  replicas: 1
  selector:
    matchLabels:
      app: mongodb
  template:
    metadata:
      labels:
        app: mongodb
    spec:
      containers:
      - name: mongodb-pod
        image: mongo:3.4-jessie
        ports:
        - containerPort: 27017
        volumeMounts:
          - name: mongo-vol
            mountPath: /data/db
  volumeClaimTemplates:
    - metadata:
        name: mongo-vol
      spec:
        accessModes: [ "ReadWriteOnce" ]
        storageClassName: default
        resources:
          requests:
            storage: 500M 
EOF

kubectl delete -f mongo.deploy.yaml
kubectl apply -f mongo.stateful.yaml
kubectl get pvc
kubectl get pv
kubectl get pods -l app=mongodb -o wide