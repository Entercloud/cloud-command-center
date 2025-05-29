# main.tf
provider "aws" {
  region = "us-east-1"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

# OIDC Provider for GitHub Actions
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"  # OIDC token audience
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1"  # GitHub's OIDC thumbprint
  ]
}
# IAM Role for GitHub Actions
resource "aws_iam_role" "github_actions_role" {
  name = "GitHubActionsOIDCRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            # Restrict to your GitHub org/repo
            "token.actions.githubusercontent.com:sub" = "repo:Entercloud/cloud-command-center:*"
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# exhaustive permissions  list(attach required policies)
# Enhanced IAM Role for GitHub Actions with Route53, ALB, and EKS permissions
resource "aws_iam_role" "github_actions_role" {
  name = "GitHubActionsOIDCRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringLike = {
            "token.actions.githubusercontent.com:sub" = [
              "repo:Entercloud/cloud-command-center:refs/heads/main",
              "repo:Entercloud/cloud-command-center:pull_request"
            ]
          }
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# Custom policy combining all required permissions
resource "aws_iam_policy" "backstage_deployment_policy" {
  name        = "BackstageDeploymentPolicy"
  description = "Permissions for Backstage deployment via GitHub Actions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Route53 DNS Management
      {
        Effect = "Allow"
        Action = [
          "route53:ChangeResourceRecordSets",
          "route53:ListHostedZones",
          "route53:ListResourceRecordSets"
        ]
        Resource = "arn:aws:route53:::hostedzone/Z03129551DARX4AJLUMHO"
      },
      
      # ALB Controller Permissions
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:DescribeSecurityGroups",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups"
        ]
        Resource = "*"
      },
      
      # EKS Cluster Access
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster",
          "eks:ListClusters"
        ]
        Resource = module.eks.cluster_arn
      },
      
      # ACM Certificate Management
      {
        Effect = "Allow"
        Action = [
          "acm:DescribeCertificate",
          "acm:ListCertificates"
        ]
        Resource = aws_acm_certificate.backstage.arn
      },
      
      # ECR Access for Container Images
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:GetRepositoryPolicy",
          "ecr:DescribeRepositories",
          "ecr:ListImages",
          "ecr:DescribeImages",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage"
        ]
        Resource = "*"
      }
    ]
  })
}

# Attach the custom policy
resource "aws_iam_role_policy_attachment" "backstage_deployment" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = aws_iam_policy.backstage_deployment_policy.arn
}

# Additional required policies
resource "aws_iam_role_policy_attachment" "eks_admin" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSLoadBalancerControllerIAMPolicy"
}
resource "aws_iam_role_policy_attachment" "ecr_access" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "eks_access" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}



module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 3.0"

  name = "backstage-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.0"

  cluster_name    = "backstage-cluster"
  cluster_version = "1.27"

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = 2

      instance_types = ["t3.medium"]
      capacity_type  = "SPOT"
    }
  }
}

resource "aws_acm_certificate" "backstage" {
  domain_name       = "build.entercloud.org"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "backstage" {
  zone_id = "Z03129551DARX4AJLUMHO"
  name    = "build.entercloud.org"
  type    = "A"

  alias {
    name                   = module.alb.lb_dns_name
    zone_id                = module.alb.lb_zone_id
    evaluate_target_health = true
  }
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name               = "backstage-alb"
  load_balancer_type = "application"
  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = [module.alb_sg.security_group_id]

  https_listeners = [
    {
      port               = 443
      protocol           = "HTTPS"
      certificate_arn    = aws_acm_certificate.backstage.arn
      target_group_index = 0
    }
  ]

  target_groups = [
    {
      name             = "backstage-tg"
      backend_protocol = "HTTP"
      backend_port     = 3000
      target_type      = "ip"
    }
  ]
}

module "alb_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 4.0"

  name        = "backstage-alb-sg"
  description = "Security group for Backstage ALB"
  vpc_id      = module.vpc.vpc_id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["https-443-tcp", "http-80-tcp"]
  egress_rules        = ["all-all"]
}

resource "kubernetes_namespace" "backstage" {
  metadata {
    name = "backstage"
  }
}

resource "helm_release" "backstage" {
  name       = "backstage"
  repository = "https://backstage.github.io/charts"
  chart      = "backstage"
  version    = "1.4.0"
  namespace  = kubernetes_namespace.backstage.metadata[0].name

  set {
    name  = "ingress.enabled"
    value = "true"
  }

  set {
    name  = "ingress.hosts[0].host"
    value = "build.entercloud.org"
  }

  set {
    name  = "ingress.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
    value = "ip"
  }

  values = [
    file("backstage-values.yaml")
  ]
}
