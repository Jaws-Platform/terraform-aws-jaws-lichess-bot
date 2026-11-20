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

# The instance's image is resolved from a pinned name, so a new Amazon Linux
# release does not replace the instance in the middle of a game. Deprecated
# images are included so that the pin keeps resolving.
data "aws_ami" "bot" {
  owners             = ["amazon"]
  include_deprecated = true
  most_recent        = false

  filter {
    name   = "name"
    values = ["al2023-ami-2023.12.20261026.1-kernel-6.18-arm64"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

module "network" {
  source = "git::https://github.com/Jaws-Platform/terraform-aws-jaws-network.git?ref=v0.1.0"

  name = "acme-chess-engine"
}

# A versioned, private bucket that outlives the bot: it is never destroyed
# with the stack.
module "records" {
  source = "git::https://github.com/Jaws-Platform/terraform-aws-jaws-foundation.git//modules/private-bucket?ref=v0.1.0"

  name = "acme-chess-engine-records"
}

# An arm64 bot (the container image must be built for arm64 too) that plays
# from 08:00 to 20:00 UTC every day and ships every finished game to the
# records bucket.
module "bot" {
  source = "../../"

  name_root = "acme"
  project   = "chess-engine"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0]

  architecture  = "arm64"
  instance_type = "t4g.small"
  ami_id        = data.aws_ami.bot.id

  # Created out of band: `aws ssm put-parameter --type SecureString`.
  secret_parameters = {
    LICHESS_TOKEN = "/acme/chess-engine/lichess-token"
  }
  container_environment = {
    ENGINE_HASH_MB          = "128"
    ENGINE_MOVE_OVERHEAD_MS = "500"
  }
  bot_name = "chess-engine-bot"

  # A new tag must log this within 90 seconds, or the previous one is restored.
  health_log_pattern = "awaiting challenges"

  records_bucket_name    = module.records.name
  records_container_path = "/opt/lichess-bot/game_records"

  schedule           = { days = "daily", start = "08:00", stop = "20:00" }
  log_retention_days = 90
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

output "records_uri" {
  description = "Where the finished games are shipped."
  value       = module.bot.records_uri
}

output "schedule" {
  description = "The start, drain and stop schedules."
  value       = module.bot.schedule
}
