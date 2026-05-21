terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Pull EKS cluster details so the helm/kubernetes providers can authenticate
# without depending on a local kubeconfig. Works for both paths:
#   - BYO  → reads the existing cluster (eks_cluster_name set)
#   - new  → reads the cluster created by aws_eks_cluster.main (depends_on
#            ensures the data source refreshes after the cluster is up)
data "aws_eks_cluster" "this" {
  name       = local.cluster_name
  depends_on = [aws_eks_cluster.main]
}

data "aws_eks_cluster_auth" "this" {
  name       = local.cluster_name
  depends_on = [aws_eks_cluster.main]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
