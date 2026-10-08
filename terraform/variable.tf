variable "app_ecr_repo" {
  type        = set(string)
  description = "1 repo for each 9 service"
  default     = ["eks-project1-lab/api-gateway", "eks-project1-lab/dashboard-api", "eks-project1-lab/inventory-service", "eks-project1-lab/notification-service", "eks-project1-lab/order-service", "eks-project1-lab/payment-service", "eks-project1-lab/scheduler", "eks-project1-lab/shipping-service", "eks-project1-lab/worker"]

}


variable "region" {
  type    = string
  default = "us-east-1"

}

#variable "domain" {
# type    = string
#default = "ecommerce.example.invalid"

#}

#variable "aws_eks_cluster" {
# type = string
#}

#variable "aws_eks_cluster_eks_cluster_certificate_authority_data" {
# type = string

#}

#variable "aws_eks_cluster_eks_cluster_endpoint" {
# type = string

#}

#variable "ip_address" {
# type    = string
#default = "REPLACE_WITH_YOUR_PUBLIC_IP/32"

#}

variable "aws_key_arn" {
  default = null
  type    = string

}

variable "aws_key_ecr_arn" {
  default = null
  type    = string

}

variable "cloudwatch_key_arn" {
  default = null
  type    = string

}

variable "aws_account_id" {
  type    = string
  default = "425959969184"

}

variable "eks_role_arn" {
  type = string

}

variable "flow_log_role_arn" {
  default = null
  type    = string

}

variable "aws_iam_role_node_group_role_arn" {
  type = string

}

variable "database_url" {
  default = null
  type    = string

}

variable "route53_zone_id" {
  default     = null
  type        = string
  description = "Your Route 53 hosted zone ID; required before DNS controllers can be used."
}

variable "postgres_secret_arn" {
  default     = null
  type        = string
  description = "Actual ARN of your existing eks/postgres Secrets Manager secret."
}

variable "create_iam_resources" {
  type    = bool
  default = true
}
variable "install_platform_helm" {
  type    = bool
  default = true
  validation {
    condition     = !var.install_platform_helm || var.create_iam_resources
    error_message = "Original Helm platform requires the original IRSA modules. Install the lab platform separately."
  }
}
variable "enable_flow_logs" {
  type    = bool
  default = true
}
variable "node_desired_size" {
  type    = number
  default = 5
}
variable "node_min_size" {
  type    = number
  default = 5
}
variable "node_max_size" {
  type    = number
  default = 5
}
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}
