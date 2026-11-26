# Basic: a bot that runs all the time

The smallest whole deployment:

- a VPC with public subnets only, from
  [`jaws-network`](https://registry.terraform.io/modules/Jaws-Platform/jaws-network/aws/latest);
- the ECR repository `acme-chess-engine`;
- the instance `acme-chess-engine-bot`, a `t3.micro` that runs all the time,
  with no ingress rule and no SSH key.

The bot's token is the SSM SecureString parameter
`/acme/chess-engine/lichess-token`. Create it yourself before the first
deploy; Terraform never sees its value:

```sh
aws ssm put-parameter --name /acme/chess-engine/lichess-token --type SecureString --value <token>
```

The instance follows the latest Amazon Linux 2023 image here, so a new
release of it replaces the instance. Pin `ami_id`, as the
[`records-and-schedule`](https://github.com/Jaws-Platform/terraform-aws-jaws-lichess-bot/tree/main/examples/records-and-schedule)
example does, before a game matters.

```sh
terraform init
terraform plan
```

Nothing runs on the instance until the first deploy writes an image tag to
the `desired_version` parameter: see
[Deploying a release](https://github.com/Jaws-Platform/terraform-aws-jaws-lichess-bot#deploying-a-release).

In your own configuration, replace the relative `source` with the registry
address, and the VPC's git source with its registry address:

```hcl
module "network" {
  source  = "Jaws-Platform/jaws-network/aws"
  version = "~> 0.1"

  name = "acme-chess-engine"
}

module "bot" {
  source  = "Jaws-Platform/jaws-lichess-bot/aws"
  version = "0.2.0" # x-release-please-version

  name_root = "acme"
  project   = "chess-engine"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0]

  secret_parameters = { LICHESS_TOKEN = "/acme/chess-engine/lichess-token" }
}
```
