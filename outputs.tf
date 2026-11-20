output "image_repository_url" {
  description = "URL of the repository the instance pulls from (`<account>.dkr.ecr.<region>.amazonaws.com/<name>`): the one created here, or `image_repository.url`. A release is `docker push <url>:<tag>`."
  value       = var.image_repository == null ? module.image[0].url : var.image_repository.url
}

output "image_repository_arn" {
  description = "ARN of the same repository, for the IAM policy of whatever pushes to it."
  value       = var.image_repository == null ? module.image[0].arn : var.image_repository.arn
}

output "image_repository_name" {
  description = "Name of the repository created here, `<name_root>-<project>`. Null with `image_repository`."
  value       = one(module.image[*].name)
}

output "instance_id" {
  description = "ID of the instance, for Run Command (the deploy) and Session Manager (`aws ssm start-session --target`)."
  value       = module.instance.instance_id
}

output "instance_arn" {
  description = "ARN of the instance."
  value       = module.instance.instance_arn
}

output "ami_id" {
  description = "Image the instance runs: the pinned `ami_id`, or the latest Amazon Linux 2023 image when nothing is pinned."
  value       = module.instance.ami_id
}

output "public_ip" {
  description = "Public IPv4 address of the instance. It is for egress only (nothing listens) and changes whenever the instance is started or replaced."
  value       = module.instance.public_ip
}

output "security_group_id" {
  description = "ID of the instance's security group, which has no ingress rule."
  value       = module.instance.security_group_id
}

output "role_arn" {
  description = "ARN of the instance role."
  value       = module.instance.role_arn
}

output "role_name" {
  description = "Name of the instance role, `<name_root>-<project>-bot`, for attaching a policy of your own."
  value       = module.instance.role_name
}

output "log_group_name" {
  description = "CloudWatch log group the container logs to, `/<name_root>/<project>/bot`."
  value       = module.instance.log_group_name
}

output "log_group_arn" {
  description = "ARN of the log group."
  value       = module.instance.log_group_arn
}

output "parameter_prefix" {
  description = "SSM path of the parameters a deploy and the instance share, `/<name_root>/<project>/bot`, for the IAM policy of whatever deploys."
  value       = module.instance.parameter_prefix
}

output "parameter_names" {
  description = "The parameters a deploy and the instance share: `desired_version` (the image tag to run, written by a deploy), `running_version` and `status` (written by the instance) and `last_sync` (written by the records sync)."
  value       = module.instance.parameter_names
}

output "records_uri" {
  description = "S3 URI the game records are shipped under. Null without `records_bucket_name`."
  value       = module.instance.records_uri
}

output "schedule" {
  description = "The names of the start, drain and stop schedules (EventBridge Scheduler, default group) and the UTC cron expression of each. Null without `schedule`."
  value       = module.instance.schedule
}
