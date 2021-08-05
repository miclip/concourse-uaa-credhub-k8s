#!/usr/bin/env bash

helm delete ingress -n projectcontour
helm delete cert-manager -n cert-manager
helm delete concourse -n concourse
kubectl delete namespace concourse
kubectl delete namespace cert-manager
kubectl delete namespace projectcontour
