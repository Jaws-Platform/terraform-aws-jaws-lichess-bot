# Root module: a Lichess bot, or any single long-lived container that only
# makes outbound connections, on one EC2 instance.
#
#   image     a private ECR repository, `<name_root>-<project>`; not created
#             when `image_repository` names an existing one
#   instance  one EC2 instance, `<name_root>-<project>-bot`, that runs one image
#             tag from the repository: its role, security group, log group,
#             on-instance reconciler, records sync and optional schedule
#
# It only wires the two submodules together. Each can be used on its own, and
# both keep their own input validation.
#
# Which tag runs is never a Terraform input: a deploy writes it to the
# `desired_version` parameter and asks the instance to converge (see
# `parameter_names`), so an apply never changes what is running.

locals {
  # The repository is named `<prefix>` and everything else `<prefix>-*`, which
  # is also what the `container/*` policies of Jaws-Platform/jaws-ci/aws are
  # scoped to.
  prefix = "${var.name_root}-${var.project}"
}

module "image" {
  source = "./modules/ecr-repository"
  count  = var.image_repository == null ? 1 : 0

  name                       = local.prefix
  keep_release_images        = var.keep_release_images
  expire_untagged_after_days = var.expire_untagged_after_days
}

module "instance" {
  source = "./modules/container-instance"

  name      = "${local.prefix}-bot"
  name_root = var.name_root
  project   = var.project

  image_repository_url = var.image_repository == null ? module.image[0].url : var.image_repository.url
  image_repository_arn = var.image_repository == null ? module.image[0].arn : var.image_repository.arn

  vpc_id        = var.vpc_id
  subnet_id     = var.subnet_id
  instance_type = var.instance_type
  architecture  = var.architecture
  ami_id        = var.ami_id

  secret_parameters     = var.secret_parameters
  container_environment = var.container_environment
  bot_name              = var.bot_name

  records_bucket_name    = var.records_bucket_name
  records_container_path = var.records_container_path
  records_prefix         = var.records_prefix

  health_log_pattern = var.health_log_pattern
  health_seconds     = var.health_seconds
  log_retention_days = var.log_retention_days
  schedule           = var.schedule
}
