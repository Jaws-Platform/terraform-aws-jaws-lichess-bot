provider "aws" {
  region = "us-east-1"

  # The modules take no tag map. Every resource inherits these, and each
  # module adds `Component` and `Name`. `Project` equals the module's
  # `project`: the jaws-ci policies recognise the bot's instance by it.
  default_tags {
    tags = {
      Project     = "chess-engine"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}

# A VPC with public subnets only. The instance gets a public address for
# egress, and its security group has no ingress rule.
module "network" {
  source = "git::https://github.com/jaws-platform/terraform-aws-jaws-network.git?ref=v0.1.0"

  name = "acme-chess-engine"
}

# The repository `acme-chess-engine` and the instance `acme-chess-engine-bot`,
# running all the time on a t3.micro that follows the latest Amazon Linux 2023
# image. Nothing runs on it until the first deploy.
module "bot" {
  source = "../../"

  name_root = "acme"
  project   = "chess-engine"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0]

  # Created out of band: `aws ssm put-parameter --type SecureString`.
  secret_parameters = {
    LICHESS_TOKEN = "/acme/chess-engine/lichess-token"
  }
}

output "image_repository_url" {
  description = "Where a release pushes its image."
  value       = module.bot.image_repository_url
}

output "instance_id" {
  description = "The instance a deploy sends its command to."
  value       = module.bot.instance_id
}

output "parameter_names" {
  description = "The parameters a deploy writes and follows."
  value       = module.bot.parameter_names
}
