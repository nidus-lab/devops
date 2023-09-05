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
wget -O- -q https://raw.githubusercontent.com/nidus-lab/devops/main/k8s/manifests/certs.yaml \
| envsubst \
| kubectl apply -f -
```