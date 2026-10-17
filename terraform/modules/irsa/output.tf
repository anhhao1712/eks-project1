output "karpeneter_module" {
    value = module.karpenter
  
}

output "module_karpenter_queue_name" {
    value = module.karpenter.queue_name
  
}

output "ebs_csi_controller_role_arn" {
    value = aws_iam_role.ebs_csi_controller.arn
  
}

