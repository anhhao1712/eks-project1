terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    bucket       = "eks-project1-tfstate-241533156847"
    key          = "eks-project1/terraform/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
