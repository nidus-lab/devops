# Coder Setup

This guide will walk you through setting up a coder instance on your kubernetes cluster.

## Ensure Cert Manager is installed and setup

You can get help with this from https://github.com/Sharpz7/Sharpz7/tree/main/docs/kubernetes.md

Note that the Env Vars will be

```bash
export DOMAIN=nidus.mcaq.me
export DOMAIN_NAME=nidus
export EMAIL=adam.mcarthur62@gmail.com
```

## ISAIC Fixes

```bash
sudo mkdir /sys/fs/cgroup/systemd
sudo mount -t cgroup -o none,name=systemd cgroup /sys/fs/cgroup/systemd

sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy

sudo hostnamectl set-hostname sub.domain.com

# Changes in file /etc/hosts
127.0.1.1 sub.domain.com sub

external.ip.xx.xx sub.domain.com sub

# After creation
kubectl annotate node isaic.mcaq.me --overwrite flannel.alpha.coreos.com/public-ip=129.128.215.164
```

And you only need to install one set of certs. I.e

```bash
wget -O- -q https://raw.githubusercontent.com/nidus-lab/devops/main/k8s/manifests/certs.yml \
| envsubst \
| kubectl apply -f -
```

## Setting up Github and Git Auth

You can get help with this from https://github.com/Sharpz7/Sharpz7/tree/main/docs/kubernetes.md

## Installing Coder

Again, you can follow https://github.com/Sharpz7/Sharpz7/tree/main/docs/kubernetes.md, but change the value you install
to the one in this repo. I.e

```bash
wget -O- -q https://raw.githubusercontent.com/nidus-lab/devops/main/k8s/helm-values/coder.yml \
| envsubst \
| helm install coder coder-v2/coder --namespace coder --values -
```

And upgrade with

```bash
helm repo update
wget -O- -q https://raw.githubusercontent.com/nidus-lab/devops/main/k8s/helm-values/coder.yml \
| envsubst \
| helm upgrade coder coder-v2/coder --namespace coder --values -
```

# Using GCP Templates

## Giving Permissions

Exec into K8s Pod and run code from https://cloud.google.com/sdk/docs/install#linux

```bash
apk add python3
curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-444.0.0-linux-x86_64.tar.gz
tar -xf google-cloud-cli-444.0.0-linux-x86_64.tar.gz
./google-cloud-sdk/install.sh

# Login and Back.
gcloud auth application-default login
```

## Creating the Template

```bash
coder template create --variable project_id=nidus-397516
```