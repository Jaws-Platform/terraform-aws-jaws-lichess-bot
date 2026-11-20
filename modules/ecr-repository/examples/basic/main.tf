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
  source = "../../"

  name                       = "acme-chess-engine"
  keep_release_images        = 20
  expire_untagged_after_days = 7
}

output "url" {
  value = module.image.url
}
