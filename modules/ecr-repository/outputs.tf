output "arn" {
  description = "Repository ARN, for IAM policies: `image_repository_arn` of `container-instance`, or `policy_inputs.ecr.repository_arn` of the role modules of `jwallace145/jaws-ci/aws`."
  value       = aws_ecr_repository.this.arn
}

output "url" {
  description = "Repository URL (`<account>.dkr.ecr.<region>.amazonaws.com/<name>`), for `docker push` and `docker pull`."
  value       = aws_ecr_repository.this.repository_url
}

output "name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "Registry (account) ID the repository belongs to."
  value       = aws_ecr_repository.this.registry_id
}
