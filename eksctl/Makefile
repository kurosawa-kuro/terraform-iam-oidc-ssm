CLUSTER_NAME=kuro-cluster

create:
	eksctl create cluster -f eksctl/eksctl.yaml

destroy:
	eksctl delete cluster --name $(CLUSTER_NAME)

kubeconfig:
	eksctl utils write-kubeconfig --cluster $(CLUSTER_NAME)