# eks-dash-tf-mvp

This is intended to be a quick start guide using the current best practices setting up a dual subnet vpc with a eks cluster running a secured dashboard.

Goals

* dual subnet public/private, direct *lb -> pod networking
* use terraform + helm where possible
* use existing target groups with [aws load balancer controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest) + [pod readiness gate](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/pod_readiness_gate/)
* deploy dash + oauth2 proxy

Assumptions

* tf, kubectl, helm, awscli are installed and awscli is configured.
* provide variables required by `variables.var` file.

To Run

```sh
terraform init
terraform apply -var-file=variables.var
```

/*
Setup Local dev info -  This info provides a kubeconfig and related information for connecting to the eks cluster locally.

```sh
aws configure
aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name)
```


// TODO: helm repo add eks https://aws.github.io/eks-charts && kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
// TODO: if there is an issue - tf state rm 'module.eks.kubernetes_config_map.aws_auth[0]'
