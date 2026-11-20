locals {
  # Modules take no tag map. Every resource inherits these through the
  # provider's default_tags, and each module adds `Component` (and `Name`).
  tags = {
    Organization = "acme"
    Project      = "chess-engine"
    Environment  = "prod"
    Repository   = "acme/chess-engine"
    ManagedBy    = "terraform"
    Owner        = "platform-team"
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = local.tags
  }
}

module "image" {
  source = "../../../ecr-repository"

  name = "acme-chess-engine"
}

module "network" {
  source = "git::https://github.com/Jaws-Platform/terraform-aws-jaws-network.git//modules/vpc?ref=v0.1.0"

  name = "acme-chess-engine"
}

module "records" {
  source = "git::https://github.com/Jaws-Platform/terraform-aws-jaws-foundation.git//modules/private-bucket?ref=v0.1.0"

  name = "acme-chess-engine-records"
}

module "bot" {
  source = "../../"

  name_root            = "acme"
  name                 = "acme-chess-engine-bot"
  project              = "chess-engine"
  image_repository_url = module.image.url
  image_repository_arn = module.image.arn
  vpc_id               = module.network.vpc_id
  subnet_id            = module.network.public_subnet_ids[0]

  secret_parameters = {
    LICHESS_TOKEN = "/acme/chess-engine/lichess-token"
  }
  container_environment = {
    ENGINE_HASH_MB          = "128"
    ENGINE_MOVE_OVERHEAD_MS = "500"
  }
  bot_name = "chess-engine-bot"

  records_bucket_name    = module.records.name
  records_container_path = "/opt/lichess-bot/game_records"
  health_log_pattern     = "awaiting challenges"

  schedule = { days = "daily", start = "08:00", stop = "20:00" }
}

output "instance_id" {
  value = module.bot.instance_id
}

output "parameter_names" {
  value = module.bot.parameter_names
}
