# Infrastructure stage: use existing LabRole; application resources are managed by Argo CD.
region                           = "us-east-1"
aws_account_id                   = "425959969184"
eks_role_arn                     = "arn:aws:iam::425959969184:role/LabRole"
aws_iam_role_node_group_role_arn = "arn:aws:iam::425959969184:role/LabRole"
create_iam_resources             = false
install_platform_helm            = false
enable_flow_logs                 = false
force_delete_ecr                 = true
# Three nodes accommodate the current Pod count; original author used five.
node_desired_size   = 3
node_min_size       = 2
node_max_size       = 3
node_instance_types = ["t3.medium"]
