/*==== Variables used across all modules ======*/
locals {
  vpc_cidr             = "10.0.0.0/16"
  environment          = "qa"
  public_subnet_cidrs  = ["10.0.10.0/24", "10.0.11.0/24", "10.0.12.0/24"]
  private_subnet_cidrs = ["10.0.60.0/24", "10.0.61.0/24", "10.0.62.0/24"]
  availability_zones   = ["us-east-2a", "us-east-2b", "us-east-2c"]
  cluster_name         = "${var.environment}-${var.name}-eks-cluster"
  region               = "us-east-2" // TODO: sync with provider or use same root var
  # max_size = 1
  # min_size = 1
  # desired_capacity = 1
  # instance_type = "t2.micro"
  # ecs_aws_ami = "ami-0254e5972ebcd132c"
  // TODO: merge target groups
  target_groups = [
    {
      # name_prefix      = "pref-"
      name             = module.kubernetes_dashboard.kubernetes_dashboard_service_name
      backend_protocol = "HTTP"
      backend_port     = 8443 // TODO: 8443 or 443?
      target_type      = "ip"
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/dashboard/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 6
      }
    }
  ]
  target_groups2 = [
    {
      # name_prefix      = "pref-"
      name             = module.kubernetes_dashboard.kubernetes_dashboard_service_name
      backend_protocol = "HTTP"
      backend_port     = 8443
      target_type      = "ip"
      target_group_arn = module.alb.target_group_arns[0]
      health_check = {
        enabled             = true
        interval            = 30
        path                = "/dashboard/"
        port                = "traffic-port"
        healthy_threshold   = 3
        unhealthy_threshold = 3
        timeout             = 6
      }
    }
  ]
}

variable "environment" {
  default = "tmp"
}

variable "name" {
  default = "eks-mvp"
}

/* Setup vpc pub/private network model */
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = var.name
  cidr = local.vpc_cidr

  azs             = local.availability_zones
  private_subnets = local.private_subnet_cidrs
  public_subnets  = local.public_subnet_cidrs

  enable_nat_gateway = true
  enable_vpn_gateway = true

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }
  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  tags = {
    Terraform   = "true"
    Environment = "dev"
  }
}

/* Create security groups */
// TODO: these are not correct
resource "aws_security_group" "main-node" {
  name        = "terraform-eks-main-node"
  description = "Security group for all nodes in the cluster"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group_rule" "main-node-open-all" {
  type              = "ingress"
  description       = "Allow node to communicate with each other"
  security_group_id = aws_security_group.main-node.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  ipv6_cidr_blocks  = ["::/0"]
}

/*Setup intial empty EKS cluster*/
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = local.cluster_name
  cluster_version = "1.19"
  subnets         = module.vpc.private_subnets
  enable_irsa     = true
  tags = {
    Environment = var.environment
  }

  vpc_id = module.vpc.vpc_id

  workers_group_defaults = {
    root_volume_type     = "gp2"
    bootstrap_extra_args = "--enable-docker-bridge true" // TODO: not sure if this is needed/ can this be moved to workers_group_defaults?
  }

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = "t3.small"
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = 1
      additional_security_group_ids = [aws_security_group.main-node.id]
      bootstrap_extra_args          = "--enable-docker-bridge true" // TODO: not sure if this is needed/ can this be moved to workers_group_defaults?
    },
    {
      name                          = "worker-group-2"
      instance_type                 = "t3.medium"
      additional_userdata           = "echo foo bar"
      additional_security_group_ids = [aws_security_group.main-node.id]
      asg_desired_capacity          = 1
      bootstrap_extra_args          = "--enable-docker-bridge true" // TODO: not sure if this is needed/ can this be moved to workers_group_defaults?
    },
  ]

  # worker_additional_security_group_ids = [aws_security_group.all_worker_mgmt.id]
  # map_roles                            = var.map_roles
  # map_users                            = var.map_users
  # map_accounts                         = var.map_accounts
}

output "cluster_id" {
  description = "EKS cluster ID."
  value       = module.eks.cluster_id
}

output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.cluster_endpoint
}

output "cluster_security_group_id" {
  description = "Security group ids attached to the cluster control plane."
  value       = module.eks.cluster_security_group_id
}

output "kubectl_config" {
  description = "kubectl config as generated by the module."
  value       = module.eks.kubeconfig
}

output "config_map_aws_auth" {
  description = "A kubernetes configuration to authenticate to this EKS cluster."
  value       = module.eks.config_map_aws_auth
}

output "cluster_name" {
  description = "Kubernetes Cluster Name"
  value       = local.cluster_name
}

output "region" {
  description = "AWS region"
  value       = local.region
}

output "kubeconfig-certificate-authority-data" {
  value = data.aws_eks_cluster.cluster.certificate_authority[0].data
}



/* Setup kuberenetes provider for use in tf */
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  depends_on = [data.aws_eks_cluster.cluster]
  name       = module.eks.cluster_id
}


provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  # load_config_file       = false
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
    # load_config_file       = false
  }
}

module "alb-ingress-controller" {
  // source = "github.com/GSA/terraform-kubernetes-aws-load-balancer-controller"
  // source = "../../../../Projects/terraform-kubernetes-aws-load-balancer-controller"
  source = "github.com/ashtonian/terraform-kubernetes-aws-load-balancer-controller"
  providers = {
    kubernetes = kubernetes,
    helm       = helm
  }

  k8s_cluster_type = "eks"
  k8s_namespace    = "kube-system"

  aws_region_name           = local.region
  k8s_cluster_name          = data.aws_eks_cluster.cluster.name
  alb_controller_depends_on = [module.alb.target_group_arns]
  target_groups             = local.target_groups2 //module.alb.target_group_arns
  enable_host_networking    = true
}

module "alb" {
  source = "terraform-aws-modules/alb/aws"

  name = "my-alb"

  load_balancer_type = "application"

  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.main-node.id]

  target_groups = local.target_groups

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Environment = "Test"
  }
}

module "kubernetes_dashboard" {
  source                          = "cookielab/dashboard/kubernetes"
  version                         = "0.9.0"
  kubernetes_deployment_image_tag = "v2.2.0"
  kubernetes_namespace_create     = false
  kubernetes_namespace            = "kube-system"
  kubernetes_dashboard_csrf       = "imaterriblecsrf"
  # kubernetes_resources_labels =
}
