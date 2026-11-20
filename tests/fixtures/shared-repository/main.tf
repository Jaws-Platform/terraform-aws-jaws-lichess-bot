# Test fixture: the root module running images from a repository that the same
# configuration creates. The repository's URL and ARN are unknown until it is
# applied, and the root module must still plan.

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

module "shared" {
  source = "../../../modules/ecr-repository"

  name = "acme-engines"
}

module "bot" {
  source = "../../../"

  name_root = "acme"
  project   = "chess-engine"
  vpc_id    = "vpc-0123456789abcdef0"
  subnet_id = "subnet-0123456789abcdef0"

  image_repository = {
    url = module.shared.url
    arn = module.shared.arn
  }
}

output "image_repository_name" {
  description = "Name of the repository the root module created: null, because it was given one."
  value       = module.bot.image_repository_name
}

output "role_name" {
  description = "Name of the instance role, which shows the instance is planned."
  value       = module.bot.role_name
}
