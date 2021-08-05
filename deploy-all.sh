#!/usr/bin/env bash

letsencrypt_ca_pem_url=https://letsencrypt.org/certs/isrgrootx1.pem

function download_letsencrypt_ca() {
  curl -sl https://letsencrypt.org/certs/isrgrootx1.pem -o /tmp/letsencrypt.pem 
}

function generate_uaa_jwt_token() {
  uaa_key=/tmp/uaa_jwt.key
  uaa_pub=/tmp/uaa_jwt.pub

  rm --force $uaa_key $uaa_pub
  ssh-keygen -t rsa -b 2048 -m PEM -f $uaa_key -N ""
  openssl rsa -in $uaa_key -pubout -outform PEM -out $uaa_pub
  export CI_uaa__jwt_key="$(cat $uaa_key)"
  export CI_uaa__jwt_pub="$(cat $uaa_pub)"
}

function deploy_uaa() {
  kubectl create namespace concourse 
  uaa_config=/tmp/uaa.yml
  ytt -f ./templates/uaa-config.yml -f ./values.yml --data-values-env CI > $uaa_config
  kubectl create secret generic uaa-config --from-file=$uaa_config -n concourse
  rm $uaa_config
  ytt -f ./templates/uaa-deployment.yml -f ./values.yml | kubectl apply -n concourse -f-
  ytt -f ./templates/uaa-service.yml -f ./values.yml | kubectl apply -n concourse -f-
  ytt -f ./templates/uaa-ingress.yml -f ./values.yml | kubectl apply -n concourse -f-
}

function deploy_credhub() {
  kubectl create namespace concourse 
  ytt -f ./templates/credhub-deployment.yml -f ./values.yml | kubectl apply -n concourse -f-
  ytt -f ./templates/credhub-service.yml -f ./values.yml | kubectl apply -n concourse -f-
  ytt -f ./templates/credhub-ingress.yml -f ./values.yml | kubectl apply -n concourse -f-
}

function deploy_contour() {
  kubectl create namespace projectcontour
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update
  helm install ingress bitnami/contour -n projectcontour --version 3.3.1
  if [ $? != 0 ]; then
    echo "Failed to install Contour. Bummer"
    exit 1
  fi

  wait_for_ready_podsprojectcontour
}

function deploy_cert_manager() {
  kubectl create namespace cert-manager
  helm repo add jetstack https://charts.jetstack.io
  helm repo update
  helm install cert-manager jetstack/cert-manager --namespace cert-manager \
   --version v1.0.2 --set installCRDs=true

  if [ $? != 0 ]; then
   echo "Failed to install Cert-Manager. Bummer"
   exit 1
  fi
  
  wait_for_ready_podscert-manager
  sleep 60;
  ytt -f ./templates/cluster-issuer.yml -f ./values.yml | kubectl apply -f-
  sleep 10;
}

function deploy_concourse() {
  
  export CI_ca_cert="$(cat /tmp/letsencrypt.pem)"
  helm repo add concourse https://concourse-charts.storage.googleapis.com/
  kubectl create namespace concourse
  ytt -f ./templates/concourse-values.yml -f ./values.yml  --data-values-env CI | helm install concourse concourse/concourse -n concourse -f-

  wait_for_ready_podsconcourse
}

function wait_for_ready_pods() {

  NS=$1
  echo "Waiting for pods in $NS to become ready."
  while true; do
    STATUS=$(kubectl get pods -n $NS | egrep -v 'Running|NAME|Completed')
    if [ -z "$STATUS" ]; then
      break
    fi
  done
  echo "All pods are running."
}

function wait_for_ready_certs() {

  NS=$1
  echo "Waiting for certs in $NS to become ready."
  while true; do
    STATUS=$(kubectl get certificates -n $NS | egrep -v 'Running|NAME|Completed')
    if [ -z "$STATUS" ]; then
      break
    fi
  done
  echo "All certificates have been issued."
}

generate_uaa_jwt_token
download_letsencrypt_ca
deploy_contour
deploy_cert_manager
deploy_uaa
deploy_credhub
deploy_concourse

echo "Ingress controller Address for DNS"
kubectl describe svc ingress-contour-envoy --namespace projectcontour | grep Ingress | awk '{print $3}'
wait_for_ready_certs concourse
