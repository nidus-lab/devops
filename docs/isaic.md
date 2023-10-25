# Getting Dynamic MIG Setup

https://towardsdatascience.com/dynamic-mig-partitioning-in-kubernetes-89db6cdde7a3

# K8s not starting after restart

```bash
sudo swapoff -a && sudo sed -i '/swap/d' /etc/fstab
```