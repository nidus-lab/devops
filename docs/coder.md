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

./google-cloud-sdk/bin/gcloud auth login
```

## Creating the Template

```bash
coder template create -v project_id=nidus-397516
```