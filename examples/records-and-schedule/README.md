# Records and a schedule

A bot set up the way one runs for real:

- an arm64 `t4g.small` whose Amazon Linux 2023 image is resolved from a
  pinned name, so the instance is replaced only when the name changes;
- running hours: started at 08:00 UTC every day, asked to finish its game
  and power off at 20:00, and stopped regardless at 21:00;
- every finished game shipped to a
  [`private-bucket`](https://registry.terraform.io/modules/Jaws-Platform/jaws-foundation/aws/latest/submodules/private-bucket)
  under `records/`, as a `.pgn` file and a `.json` sidecar;
- a health check: a new image tag must log `awaiting challenges` within 90
  seconds, or the previous tag is started again;
- engine settings passed to the container as plain environment variables,
  and 90 days of logs.

The container image has to be built for arm64 as well. The records bucket
outlives the stack: it has `prevent_destroy`, so a `terraform destroy` does
not remove it or the games in it.

```sh
terraform init
terraform plan
```

In your own configuration, replace the relative `source` with the registry
address, and the git sources with theirs:

```hcl
module "network" {
  source  = "Jaws-Platform/jaws-network/aws"
  version = "~> 0.1"

  name = "acme-chess-engine"
}

module "records" {
  source  = "Jaws-Platform/jaws-foundation/aws//modules/private-bucket"
  version = "~> 0.1"

  name = "acme-chess-engine-records"
}

module "bot" {
  source  = "Jaws-Platform/jaws-lichess-bot/aws"
  version = "0.1.2" # x-release-please-version

  name_root = "acme"
  project   = "chess-engine"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0]

  architecture  = "arm64"
  instance_type = "t4g.small"
  ami_id        = data.aws_ami.bot.id

  secret_parameters     = { LICHESS_TOKEN = "/acme/chess-engine/lichess-token" }
  container_environment = { ENGINE_HASH_MB = "128", ENGINE_MOVE_OVERHEAD_MS = "500" }
  bot_name              = "chess-engine-bot"
  health_log_pattern    = "awaiting challenges"

  records_bucket_name    = module.records.name
  records_container_path = "/opt/lichess-bot/game_records"

  schedule           = { days = "daily", start = "08:00", stop = "20:00" }
  log_retention_days = 90
}
```
