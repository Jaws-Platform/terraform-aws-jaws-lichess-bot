variable "name_root" {
  description = "Prefix of every name and path, in kebab-case: usually the organisation, for example `acme`. The repository is `<name_root>-<project>`, the instance `<name_root>-<project>-bot`, and the parameters and logs live under `/<name_root>/<project>/bot`."
  type        = string
}

variable "project" {
  description = "Project in kebab-case, for example `chess-engine`. The policies of `Jaws-Platform/jaws-ci/aws` recognise the instance by a `Project` tag with this value, so give the provider's `default_tags` one if a role from that family deploys to it."
  type        = string

  validation {
    condition     = length(var.name_root) + length(var.project) <= 43
    error_message = "name_root and project must be at most 43 characters together, so that the instance name `<name_root>-<project>-bot` fits its 48-character limit."
  }
}

variable "vpc_id" {
  description = "VPC of the instance's security group, for example output `vpc_id` of `Jaws-Platform/jaws-network/aws`."
  type        = string
}

variable "subnet_id" {
  description = "Public subnet of the instance, for example an element of output `public_subnet_ids` of `Jaws-Platform/jaws-network/aws`. The instance gets a public IPv4 address for egress and has no ingress rule."
  type        = string
}

variable "image_repository" {
  description = "An existing ECR repository to run images from, instead of creating one: its `url` (`<account>.dkr.ecr.<region>.amazonaws.com/<name>`) and its `arn`. It must be in the instance's region. Null creates the repository `<name_root>-<project>`."
  type = object({
    url = string
    arn = string
  })
  default = null
}

variable "keep_release_images" {
  description = "How many `v*`-tagged images the created repository keeps. Older ones expire. Unused with `image_repository`."
  type        = number
  default     = 20
}

variable "expire_untagged_after_days" {
  description = "Untagged images in the created repository (for example layers left behind by a failed push) expire this many days after being pushed. Unused with `image_repository`."
  type        = number
  default     = 7
}

variable "instance_type" {
  description = "EC2 instance type. It must match `architecture`: `t3` for `x86_64`, `t4g` for `arm64`."
  type        = string
  default     = "t3.micro"
}

variable "architecture" {
  description = "CPU architecture of the instance's image: `x86_64` or `arm64`. The container image must be built for the same one."
  type        = string
  default     = "x86_64"
}

variable "ami_id" {
  description = "Amazon Linux 2023 image of the instance, matching `architecture`. Pin it, so the instance is replaced only when you change the pin. Null follows the latest image, which replaces the instance (and ends the game in progress) whenever Amazon publishes one."
  type        = string
  default     = null
}

variable "secret_parameters" {
  description = "Environment variables the container gets from SSM SecureString parameters: variable name to parameter name, for example `{ LICHESS_TOKEN = \"/acme/chess-engine/lichess-token\" }`. Each must live under `/<name_root>/<project>/` and outside `/<name_root>/<project>/bot/`. Create the parameters yourself, out of band; the instance may read exactly these."
  type        = map(string)
  default     = {}
}

variable "container_environment" {
  description = "Plain environment variables for the container. Values must not contain whitespace or quotes."
  type        = map(string)
  default     = {}
}

variable "bot_name" {
  description = "Name of the account the container plays as (the Lichess bot user), recorded with every game record."
  type        = string
  default     = ""
}

variable "records_bucket_name" {
  description = "Existing bucket that finished game records are shipped to, for example output `name` of `Jaws-Platform/jaws-foundation/aws//modules/private-bucket`. The instance may add objects under `records_prefix` and nothing else. Null ships no records."
  type        = string
  default     = null
}

variable "records_container_path" {
  description = "Absolute path inside the container where it writes one `.pgn` file per game, for example `/opt/lichess-bot/game_records`. Required with `records_bucket_name`."
  type        = string
  default     = null
}

variable "records_prefix" {
  description = "Key prefix of the game records in the bucket: lowercase path segments ending in `/`."
  type        = string
  default     = "records/"
}

variable "health_log_pattern" {
  description = "Text a new container must log within `health_seconds` to count as healthy, for example `awaiting challenges`. Without it the container only has to stay up. A tag that fails the check is rolled back to the previous one."
  type        = string
  default     = ""
}

variable "health_seconds" {
  description = "Seconds a new container has to prove it is healthy before it is rolled back, from 10 to 600."
  type        = number
  default     = 90
}

variable "log_retention_days" {
  description = "Retention of the container's CloudWatch log group, in days: one of the values CloudWatch allows."
  type        = number
  default     = 30
}

variable "schedule" {
  description = "When the instance runs, in UTC: `days` is `daily`, `weekdays` or `weekends`, and `start` and `stop` are `HH:MM` on a quarter hour of the same day, 4 to 20 hours apart, with `stop` at 22:45 at the latest. At `stop` the container is asked to finish (a bot ends its game) and the instance powers off; 60 minutes later it is stopped regardless. Null runs it all the time."
  type = object({
    days  = string
    start = string
    stop  = string
  })
  default = null
}
