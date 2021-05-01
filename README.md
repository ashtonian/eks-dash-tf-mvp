# eks-dash-tf-mvp

This is intended to be a quick start guide using the current best practices setting up a dual subnet vpc with a eks cluster running a secured dashboard.

Goals

* dual subnet public/private, direct *lb -> pod networking
* use terraform + helm where possible
* use existing target groups with [aws load balancer controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest) + [pod readiness gate](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/deploy/pod_readiness_gate/)
* deploy dash + oauth2 proxy

Current State

* The custom record target group binding reports success in terraform execution but the aws-load-balancer-controller logs that it cannot find the service/port. The expected behavior is that the target group have a new pending target ip (the pods) that eventually reports healthy.

Assumptions

* tf, kubectl, helm, awscli are installed and awscli is configured.
* provide variables required by `variables.var` file.

To Run

```sh
terraform init
terraform apply
```

Resources

* [my tf-k8-aws-lb fork](https://github.com/Ashtonian/terraform-kubernetes-aws-load-balancer-controller)
* [original tf-k8-aws-lb-ingress repo issue](https://github.com/iplabs/terraform-kubernetes-alb-ingress-controller/pull/13)
* [aws-load-balancer-controller docs.aws](https://docs.aws.amazon.com/eks/latest/userguide/aws-load-balancer-controller.html)
* [aws-load-balancer-controller](https://github.com/aws/eks-charts/tree/master/stable/aws-load-balancer-controller)
* [enable-docker-bridge-network.md](https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/docs/enable-docker-bridge-network.md)
* [Internal error occurred: failed calling webhook 'mtargetgroupbinding.elbv2.k8s.aws' #1591](https://github.com/kubernetes-sigs/aws-load-balancer-controller/issues/1591)

Notes

* sometimes tf destroy doesn't work and you have to do it by hand and then run ```tf state rm 'module.eks.kubernetes_config_map.aws_auth[0]'```
* Setup Local dev info -  This info provides a kubeconfig and related information for connecting to the eks cluster locally from the tf output.
```sh
aws configure
aws eks --region $(terraform output -raw region) update-kubeconfig --name $(terraform output -raw cluster_name)
```

vNext

* [tf-kube-alpha(new)](https://github.com/hashicorp/terraform-provider-kubernetes-alpha)