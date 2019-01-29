#!/usr/bin/env bash

set -e
export HISTFILE="/home/bartek/.zsh_history_demo_thanos_2019"

minikube start --cache-images --vm-driver=kvm2 -p us1 --kubernetes-version="v1.13.2" \
    --memory=4096 \
    --extra-config=kubelet.authentication-token-webhook=true \
    --extra-config=kubelet.authorization-mode=Webhook \
    --extra-config=scheduler.address=0.0.0.0 \
    --extra-config=controller-manager.address=0.0.0.0

minikube start --cache-images --vm-driver=kvm2 -p eu1 --kubernetes-version="v1.13.2" \
    --memory=4096 \
    --extra-config=kubelet.authentication-token-webhook=true \
    --extra-config=kubelet.authorization-mode=Webhook \
    --extra-config=scheduler.address=0.0.0.0 \
    --extra-config=controller-manager.address=0.0.0.0

kubectl config use-context eu1
kubectl apply -f manifests/alertmanager.yaml

sleep 2s

ALERTMANAGER_URL=$(minikube -p eu1 service alertmanager --format="{{.IP}}:{{.Port}}")
echo "ALERTMANAGER_URL=${ALERTMANAGER_URL}"
if [[ -z "${ALERTMANAGER_URL}" ]]; then
    echo "minikube returns empty result for ALERTMANAGER_URL"
    exit 1
fi

cat manifests/prometheus.yaml | sed "s#%%ALERTMANAGER_URL%%#${ALERTMANAGER_URL}#g" | sed "s#%%CLUSTER%%#eu1#g" | kubectl apply -f -
kubectl apply -f manifests/prometheus-rules.yaml
kubectl apply -f manifests/kube-state-metrics.yaml

kubectl config use-context us1
cat manifests/prometheus.yaml | sed "s#%%ALERTMANAGER_URL%%#${ALERTMANAGER_URL}#g" | sed "s#%%CLUSTER%%#us1#g" | kubectl apply -f -
kubectl apply -f manifests/prometheus-rules.yaml
kubectl apply -f manifests/kube-state-metrics.yaml

sleep 1s

kubectl config use-context eu1
PROM_US1_URL=$(minikube -p us1 service prometheus --url)
echo "PROM_US1_URL=${PROM_US1_URL}"
sed "s#%%PROM_US1_URL%%#${PROM_US1_URL}#g" manifests/grafana.yaml | kubectl apply -f -

# Issues.
# - not synced time on minikube?
# - loadbalancer type not possible. It works with minikube tunnel, but it works only for single cluster.
#  NodePort needs to be used.
# - mounting config at prometheus.yml does not work - default one overwrites.
# - kubectl exec -it prometheus-0 -- /bin/kill -SIGHUP 1
# kube sched and controller metrics - descoping: # Hacks to make kube-scheduler and kube-controller-manager metrics available:
#---
#apiVersion: v1
#kind: Service
#metadata:
#  namespace: kube-system
#  name: kube-scheduler-monitoring
#  labels:
#    app: kube-scheduler
#spec:
#  selector:
#    component: kube-scheduler
#  type: ClusterIP
#  clusterIP: None
#  ports:
#    - name: http
#      port: 10251
#      targetPort: 10251
#      protocol: TCP
#---
#apiVersion: v1
#kind: Service
#metadata:
#  namespace: kube-system
#  name: kube-controller-manager-monitoring
#  labels:
#    app: kube-controller-manager
#spec:
#  selector:
#    app: kube-controller-manager
#  type: ClusterIP
#  clusterIP: None
#  ports:
#    - name: http
#      port: 10252
#      targetPort: 10252
#      protocol: TCP
# - alertmanager URL service is not ready?
# -  E0129 12:41:52.352178    6295 start.go:243] Error parsing version semver:  Version string empty
#