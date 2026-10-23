locals {
  oidc_issuer = replace(var.aws_eks_cluster_eks_cluster_identity_oidc_issuer, "https://", "")
}

module "cert_manager_irsa_role" {
  #checkov:skip=CKV_AWS_1:
  version = "5.60.0"
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                     = "eks-project1-cert-manager"
  attach_cert_manager_policy    = true
  cert_manager_hosted_zone_arns = ["arn:aws:route53:::hostedzone/*"]

  oidc_providers = {
    eks = {
      provider_arn               = var.aws_iam_openid_connect_provider_arn
      namespace_service_accounts = ["cert-manager:cert-manager"]
    }
  }

}

module "karpenter" {
  #checkov:skip=CKV_AWS_1:
  source = "terraform-aws-modules/eks/aws//modules/karpenter"
  region = var.region


  cluster_name = var.aws_eks_cluster
  node_iam_role_name = "eks-project1-karpenter"

  # Attach additional IAM policies to the Karpenter node IAM role
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

module "external-dns" {
  #checkov:skip=CKV_AWS_1:
  version = "5.60.0"
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"


  role_name                     = "eks-project1-external-dns"
  attach_external_dns_policy    = true
  external_dns_hosted_zone_arns = ["arn:aws:route53:::hostedzone/*"]

  oidc_providers = {
    eks = {
      provider_arn               = var.aws_iam_openid_connect_provider_arn
      namespace_service_accounts = ["external-dns:external-dns"]
    }
  }

}

module "aws-load-balancer-controller" {
  #checkov:skip=CKV_AWS_1:
  version = "5.0.1"
  source = "lablabs/eks-load-balancer-controller/aws"


  cluster_name = var.aws_eks_cluster

  cluster_identity_oidc_issuer = var.aws_eks_cluster_eks_cluster_identity_oidc_issuer

  cluster_identity_oidc_issuer_arn = var.aws_iam_openid_connect_provider_arn

  service_account_name      = "aws-load-balancer-controller"
  service_account_namespace = "aws-load-balancer-controller"

  enabled = true

  irsa_role_name_prefix = "eks-project1-lbc"

  values = file("helm-values/aws-load-balancer-controller.yaml")

  settings = {
    "vpcId" = var.aws_vpc_id
  }

}

resource "aws_iam_role" "ebs_csi_controller" {
  name = "eks-project1-AmazonEKS_EBS_CSI_DriverRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Federated = var.aws_iam_openid_connect_provider_arn
        }

        Action = "sts:AssumeRoleWithWebIdentity"

        Condition = {
          StringEquals = {
            "${replace(var.eks_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"

            "${replace(var.eks_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "AmazonEBSCSIDriverPolicy" {
  role       = aws_iam_role.ebs_csi_controller.name
  policy_arn =  "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role" "worker_iam_role" {
  name = "eks-project1-worker-iam-role"

  assume_role_policy = jsonencode({
   Version = "2012-10-17"

   Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"

        Principal = {
          Federated =  var.aws_iam_openid_connect_provider_arn
        }

        Condition = {
          StringEquals = {
        "${local.oidc_issuer}:sub" = "system:serviceaccount:application-namespace:worker-service-account"
        "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
      },
        }
      }
    ]

  }
  )
}


data "aws_iam_policy_document" "worker_iam_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:SendMessage"
    ]


    resources = ["arn:aws:sqs:us-east-1:241533156847:eks_sqs"]
  }

}

resource "aws_iam_policy" "worker_iam_policy" {
  name   = "eks-project1-worker-iam-policy"
  policy = data.aws_iam_policy_document.worker_iam_policy_document.json
}


resource "aws_iam_role_policy_attachment" "Worker_iam_policy_attachment" {
  role       = aws_iam_role.worker_iam_role.name
  policy_arn = aws_iam_policy.worker_iam_policy.arn
}



resource "aws_iam_role" "order_iam_role" {
  name = "eks-project1-order-iam-role"

  assume_role_policy = jsonencode({
   Version = "2012-10-17"

   Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"

        Principal = {
          Federated =  var.aws_iam_openid_connect_provider_arn
        }

        Condition = {
          StringEquals = {
        "${local.oidc_issuer}:sub" = "system:serviceaccount:application-namespace:order-service-service-account"
        "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
      },
        }
      }
    ]

  }
  )
}

data "aws_iam_policy_document" "order_iam_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:SendMessage"
    ]


    resources = ["arn:aws:sqs:us-east-1:241533156847:eks_sqs"]
  }

}

resource "aws_iam_policy" "order_iam_policy" {
  name   = "eks-project1-order-iam-policy"
  policy = data.aws_iam_policy_document.order_iam_policy_document.json
}

resource "aws_iam_role_policy_attachment" "order_iam_policy_attachment" {
  role       = aws_iam_role.order_iam_role.name
  policy_arn = aws_iam_policy.order_iam_policy.arn
}

resource "aws_iam_role" "shipping_iam_role" {
  name = "eks-project1-shipping-iam-role"

  assume_role_policy = jsonencode({
   Version = "2012-10-17"

   Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"

        Principal = {
          Federated =  var.aws_iam_openid_connect_provider_arn
        }

        Condition = {
          StringEquals = {
        "${local.oidc_issuer}:sub" = "system:serviceaccount:application-namespace:shipping-service-service-account"
        "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
      },
        }
      }
    ]

  }
  )
}

data "aws_iam_policy_document" "shipping_iam_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:SendMessage"
    ]


    resources = ["arn:aws:sqs:us-east-1:241533156847:eks_sqs"]
  }

}

resource "aws_iam_policy" "shipping_iam_policy" {
  name   = "eks-project1-shipping-iam-policy"
  policy = data.aws_iam_policy_document.shipping_iam_policy_document.json
}

resource "aws_iam_role_policy_attachment" "shipping_iam_policy_attachment" {
  role       = aws_iam_role.shipping_iam_role.name
  policy_arn = aws_iam_policy.shipping_iam_policy.arn
}

resource "aws_iam_role" "payment_iam_role" {
  name = "eks-project1-payment-iam-role"

  assume_role_policy = jsonencode({
   Version = "2012-10-17"

   Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"

        Principal = {
          Federated =  var.aws_iam_openid_connect_provider_arn
        }

        Condition = {
          StringEquals = {
        "${local.oidc_issuer}:sub" = "system:serviceaccount:application-namespace:payment-service-service-account"
        "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
      },
        }
      }
    ]

  }
  )
}

data "aws_iam_policy_document" "payment_iam_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:SendMessage"
    ]


    resources = ["arn:aws:sqs:us-east-1:241533156847:eks_sqs"]
  }

}

resource "aws_iam_policy" "payment_iam_policy" {
  name   = "eks-project1-payment-iam-policy"
  policy = data.aws_iam_policy_document.payment_iam_policy_document.json
}

resource "aws_iam_role_policy_attachment" "payment_iam_policy_attachment" {
  role       = aws_iam_role.payment_iam_role.name
  policy_arn = aws_iam_policy.payment_iam_policy.arn
}

resource "aws_iam_role" "postgres_iam_role" {
  name = "eks-project1-postgres-role"

  assume_role_policy = jsonencode({
   Version = "2012-10-17"

   Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"

        Principal = {
          Federated =  var.aws_iam_openid_connect_provider_arn
        }

        Condition = {
          StringEquals = {
        "${local.oidc_issuer}:sub" = "system:serviceaccount:database-ns:postgres-service-account"
        "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
      },
        }
      }
    ]

  }
  )
}

data "aws_iam_policy_document" "postgres_iam_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]


    resources = ["arn:aws:secretsmanager:us-east-1:241533156847:secret:eks/postgres-*"]
  }

}

resource "aws_iam_policy" "postgres_iam_policy" {
  name   = "eks-project1-postgres-iam-policy"
  policy = data.aws_iam_policy_document.postgres_iam_policy_document.json
}

resource "aws_iam_role_policy_attachment" "postgres_iam_policy_attachment" {
  role       = aws_iam_role.postgres_iam_role.name
  policy_arn = aws_iam_policy.postgres_iam_policy.arn
}

resource "aws_iam_role" "database_api_iam_role" {
  name = "eks-project1-database-api-role"

  assume_role_policy = jsonencode({
   Version = "2012-10-17"

   Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"

        Principal = {
          Federated =  var.aws_iam_openid_connect_provider_arn
        }

        Condition = {
          StringEquals = {
        "${local.oidc_issuer}:sub" = "system:serviceaccount:application-namespace:dashboard-api-service-account"
        "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
      },
        }
      }
    ]

  }
  )
}

data "aws_iam_policy_document" "aws_secret_iam_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]


    resources = ["arn:aws:secretsmanager:us-east-1:241533156847:secret:database_url-*"]
  }

}

resource "aws_iam_policy" "aws_secret_iam_policy" {
  name   = "eks-project1-aws-secret-iam-policy"
  policy = data.aws_iam_policy_document.aws_secret_iam_policy_document.json

}

resource "aws_iam_role_policy_attachment" "aws_secret_iam_policy_attachment" {
  role       = aws_iam_role.database_api_iam_role.name
  policy_arn = aws_iam_policy.aws_secret_iam_policy.arn
}


resource "aws_iam_role_policy_attachment" "aws_secret_iam_policy_attachments_" {
  for_each = aws_iam_role.database_service_roles

  role       = each.value.name
  policy_arn = aws_iam_policy.aws_secret_iam_policy.arn
}

locals {
  database_service_accounts = {
    inventory     = "inventory-service-service-account"
    order         = "order-service-service-account"
    payment       = "payment-service-service-account"
    scheduler     = "scheduler-service-account"
    shipping      = "shipping-service-service-account"
    notification  = "notification-service-service-account"
  }
}


resource "aws_iam_role" "database_service_roles" {
  for_each = local.database_service_accounts

  name = "eks-project1-${each.key}-database-secret-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"

      Principal = {
        Federated = var.aws_iam_openid_connect_provider_arn
      }

      Condition = {
        StringEquals = {
          "${local.oidc_issuer}:sub" = "system:serviceaccount:application-namespace:${each.value}"
          "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "services_iam_policy" {
  name   = "eks-project1-services-iam-policy"
  policy = data.aws_iam_policy_document.services_iam_policy_document.json
}

resource "aws_iam_role_policy_attachment" "services_iam_policy_attachments" {
  for_each = toset(["order", "payment", "shipping"])

  role       = aws_iam_role.database_service_roles[each.value].name
  policy_arn = aws_iam_policy.services_iam_policy.arn
}

data "aws_iam_policy_document" "services_iam_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:SendMessage"
    ]


    resources = ["arn:aws:sqs:us-east-1:241533156847:eks_sqs"]
  }

}

resource "aws_iam_role" "keda_iam_role" {
  name = "eks-project1-keda-iam-role"

  assume_role_policy = jsonencode({
   Version = "2012-10-17"

   Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"

        Principal = {
          Federated =  var.aws_iam_openid_connect_provider_arn
        }

        Condition = {
          StringEquals = {
        "${local.oidc_issuer}:sub" = "system:serviceaccount:kube-system:keda-operator"
        "${local.oidc_issuer}:aud" = "sts.amazonaws.com"
      },
        }
      }
    ]

  }
  )
}

data "aws_iam_policy_document" "keda_iam_policy_document" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:GetQueueAttributes"
    ]


    resources = ["arn:aws:sqs:us-east-1:241533156847:eks_sqs"]
  }

}

resource "aws_iam_policy" "keda_iam_policy" {
  name   = "eks-project1-keda-iam-policy"
  policy = data.aws_iam_policy_document.keda_iam_policy_document.json

}

resource "aws_iam_role_policy_attachment" "keda_iam_policy_attachment" {
  role       = aws_iam_role.keda_iam_role.name
  policy_arn = aws_iam_policy.keda_iam_policy.arn
}
