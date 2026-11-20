# terraform-aws-jaws-lichess-bot

[![Terraform Registry](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fregistry.terraform.io%2Fv1%2Fmodules%2Fjaws-platform%2Fjaws-lichess-bot%2Faws&query=%24.version&prefix=v&label=registry&logo=terraform&color=7B42BC)](https://registry.terraform.io/modules/jaws-platform/jaws-lichess-bot/aws/latest)
[![GitHub release](https://img.shields.io/github/v/release/jaws-platform/terraform-aws-jaws-lichess-bot?label=release)](https://github.com/jaws-platform/terraform-aws-jaws-lichess-bot/releases/latest)
[![CI](https://github.com/jaws-platform/terraform-aws-jaws-lichess-bot/actions/workflows/ci.yml/badge.svg?event=pull_request)](https://github.com/jaws-platform/terraform-aws-jaws-lichess-bot/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/jaws-platform/terraform-aws-jaws-lichess-bot/blob/main/LICENSE)

A [Lichess bot](https://github.com/lichess-bot-devs/lichess-bot) on one small
EC2 instance: a private ECR repository for its image, and an instance that
runs one image tag and moves to the next one **without interrupting a game**.
Nothing in it is specific to chess: it runs any single long-lived container
that only makes outbound connections.

It is deliberately small and cheap: one instance, no load balancer, no auto
scaling and no ingress. It is one of the
[Jaws](https://github.com/jwallace145/jaws) module families, and has no
dependency on Jaws: the network, the records bucket and everything else are
plain inputs.

## What it creates

```text
    docker push          ssm put-parameter               ssm send-command
    <url>:<tag>           desired-version        container-reconcile-async
         │                       │                               │
         ▼                       ▼                               │
 ┌────────────────┐   ┌──────────────────────┐                   │
 │ ECR repository │   │ SSM parameters       │                   │
 │ <prefix>       │   │ /<name_root>/        │                   │
 └───────┬────────┘   │   <project>/bot/*    │                   │
         │ pull       └──────────▲───────────┘                   │
         │                       │ read, write                   │
 ┌───────▼───────────────────────▼───────────────────────────────▼───────┐
 │ EC2 instance <prefix>-bot: a public subnet, a public IP, no ingress   │
 │                                                                       │
 │   reconciler ──► Docker: the `app` container, one image tag at a time │
 │   records sync, every 10 minutes                                      │
 └───────┬──────────────────────────────────────────┬────────────────────┘
         │ logs                                     │ finished games
         ▼                                          ▼
 CloudWatch log group                       S3 bucket (yours, optional)
 /<name_root>/<project>/bot
```

`<prefix>` is `<name_root>-<project>`. The module creates the repository, the
instance with its role and its security group, and the log group; a
`schedule` adds three EventBridge Scheduler schedules and the role they run
as. The three arrows at the top are a deploy, which is not Terraform's job
(see "Deploying a release" below). The parameters are created by the first
deploy and by the instance.

On the instance, a **reconciler** converges the container to the desired tag.
It pulls the new image and reads the secrets before it touches anything, sends
the running container one stop signal and waits as long as it takes for it to
exit (lichess-bot finishes its game first), then starts the new tag and rolls
back to the previous one if it does not become healthy. An optional
**schedule** (EventBridge Scheduler, no Lambda) starts the instance, drains it
the same graceful way and stops it, on the same hours every day, every weekday
or every weekend.

## Modules

| Module | Creates |
|---|---|
| [root](https://registry.terraform.io/modules/jaws-platform/jaws-lichess-bot/aws/latest) | The whole picture above in one call: `ecr-repository`, unless `image_repository` names an existing one, and `container-instance` running a tag from it. |
| [`ecr-repository`](https://registry.terraform.io/modules/jaws-platform/jaws-lichess-bot/aws/latest/submodules/ecr-repository) | A private ECR repository for one image: immutable tags, scan on push, AES256, and a lifecycle policy that keeps the newest release images and expires untagged ones. Works for any image. |
| [`container-instance`](https://registry.terraform.io/modules/jaws-platform/jaws-lichess-bot/aws/latest/submodules/container-instance) | One EC2 instance (IMDSv2 only, an encrypted root volume, no SSH key) that runs one image tag from ECR, with the reconciler, the optional schedule, an instance role, a security group without ingress rules, a CloudWatch log group and the shipping of game records to S3. |

## Usage

A bot that runs all the time, in a VPC from
[`jaws-network`](https://registry.terraform.io/modules/jaws-platform/jaws-network/aws/latest):

```hcl
module "network" {
  source  = "jaws-platform/jaws-network/aws"
  version = "~> 0.1"

  name = "acme-chess-engine"
}

module "bot" {
  source  = "jaws-platform/jaws-lichess-bot/aws"
  version = "0.1.1" # x-release-please-version

  name_root = "acme"
  project   = "chess-engine"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0]

  # A SecureString parameter you create yourself, outside Terraform.
  secret_parameters = { LICHESS_TOKEN = "/acme/chess-engine/lichess-token" }
}
```

That creates the repository `acme-chess-engine`, the instance
`acme-chess-engine-bot` and the log group `/acme/chess-engine/bot`.

A pinned image, a health check, game records shipped to a
[`private-bucket`](https://registry.terraform.io/modules/jaws-platform/jaws-foundation/aws/latest/submodules/private-bucket),
and running hours:

```hcl
module "records" {
  source  = "jaws-platform/jaws-foundation/aws//modules/private-bucket"
  version = "~> 0.1"

  name = "acme-chess-engine-records"
}

module "bot" {
  source  = "jaws-platform/jaws-lichess-bot/aws"
  version = "0.1.1" # x-release-please-version

  name_root = "acme"
  project   = "chess-engine"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0]
  ami_id    = "ami-0123456789abcdef0" # a pinned Amazon Linux 2023 image

  secret_parameters     = { LICHESS_TOKEN = "/acme/chess-engine/lichess-token" }
  container_environment = { ENGINE_HASH_MB = "128" }
  bot_name              = "chess-engine-bot"
  health_log_pattern    = "awaiting challenges"

  records_bucket_name    = module.records.name
  records_container_path = "/opt/lichess-bot/game_records"

  # 08:00 to 20:00 UTC every day, instead of all the time.
  schedule = { days = "daily", start = "08:00", stop = "20:00" }
}
```

An image that already lives in another repository, in the same region:

```hcl
module "bot" {
  source  = "jaws-platform/jaws-lichess-bot/aws"
  version = "0.1.1" # x-release-please-version

  name_root = "acme"
  project   = "chess-engine"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_ids[0]

  image_repository = {
    url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/acme-engines"
    arn = "arn:aws:ecr:us-east-1:123456789012:repository/acme-engines"
  }
}
```

Each submodule can also be used on its own, for example `ecr-repository` for
an image that has nothing to do with a bot:

```hcl
module "image" {
  source  = "jaws-platform/jaws-lichess-bot/aws//modules/ecr-repository"
  version = "0.1.1" # x-release-please-version

  name = "acme-tools"
}
```

Use the submodules directly to choose the names, or to set what the root
module leaves at its default: `stop_signal` (`SIGINT`), `stop_poll_seconds`
(15), `drain_minutes` (60, the time a scheduled drain gets before the hard
stop), `root_volume_gb` (16), `release_tag_prefixes` (`v`) and the `component`
tags.

## Deploying a release

Terraform never decides which image tag runs. A deploy does, in three steps,
with the values the outputs `image_repository_url`, `parameter_names` and
`instance_id` give it:

```sh
# 1. Push the image. Tags are immutable, so every release needs a new one.
aws ecr get-login-password | docker login --username AWS --password-stdin 123456789012.dkr.ecr.us-east-1.amazonaws.com
docker push 123456789012.dkr.ecr.us-east-1.amazonaws.com/acme-chess-engine:v1.4.0

# 2. Say which tag should run.
aws ssm put-parameter --name /acme/chess-engine/bot/desired-version \
  --type String --overwrite --value v1.4.0

# 3. Ask the instance to converge. The command returns at once; the swap
#    itself waits for the game in progress to end.
aws ssm send-command --document-name AWS-RunShellScript \
  --instance-ids i-0123456789abcdef0 \
  --parameters 'commands=["/usr/local/bin/container-reconcile-async"]'

# Follow it: ok, waiting:<tag>, rolling-back:<reason> or failed:<reason>.
aws ssm get-parameter --name /acme/chess-engine/bot/status \
  --query Parameter.Value --output text
```

A new instance runs nothing until `desired-version` is first written. After
that, every boot converges to it on its own, so a replaced or restarted
instance comes back on the right tag, and a deploy made while a scheduled
instance is stopped takes effect at its next start.

The IAM side of a release from GitHub Actions is in the
[`jaws-ci`](https://registry.terraform.io/modules/jaws-platform/jaws-ci/aws/latest)
family. Its `container/release` policy (from
[`ci-policies`](https://registry.terraform.io/modules/jaws-platform/jaws-ci/aws/latest/submodules/ci-policies),
attached by
[`ci-release-role`](https://registry.terraform.io/modules/jaws-platform/jaws-ci/aws/latest/submodules/ci-release-role))
allows the steps above for one project: it can read no secret and change no
infrastructure. Its `container/read`, `container/manage` and
`container/schedule` policies let a plan or apply role manage what this
module creates. All four are scoped to the names the root module uses, to a
records bucket named `<name_root>-<project>-records`, and to instances whose
`Project` tag is the project.

## Examples

- [`basic`](https://github.com/jaws-platform/terraform-aws-jaws-lichess-bot/tree/main/examples/basic):
  a VPC, the repository and a bot that runs all the time.
- [`records-and-schedule`](https://github.com/jaws-platform/terraform-aws-jaws-lichess-bot/tree/main/examples/records-and-schedule):
  a pinned arm64 image, a records bucket, a health check and daily running
  hours.

## Cost

| | Per month, us-east-1 |
|---|---|
| The instance, one `t3.micro` by default | its on-demand price, for the hours it runs |
| Its public IPv4 address, at $0.005 per hour while it runs | about $3.65 when it runs all the time |
| Its 16 GB gp3 root volume, whether it runs or not | about $1.28 |
| Images in ECR, logs in CloudWatch, game records in S3 | by size; small for one bot |

There is no load balancer, no NAT gateway and nothing else with a standing
charge. A `schedule` stops the instance outside its hours: the instance and
its address are then billed for those hours only, the volume all the time.
CPU credits are `standard`, so a busy engine on a burstable instance is
slowed to its baseline instead of running up charges for extra credits. The
figures are approximate list prices at the time of writing; the
[AWS pricing pages](https://aws.amazon.com/pricing/) are the reference.

## What to know before using it

- **`us-east-1` is the only supported region.** The two modules read the
  region from the provider and name none, but they have only been run there,
  and [`jaws-network`](https://registry.terraform.io/modules/jaws-platform/jaws-network/aws/latest)
  accepts only `us-east-1` zones.
- **One instance, no failover.** There is one instance in one availability
  zone, with no load balancer and no auto scaling group. While it is down,
  stopped or being replaced, the bot is offline.
- **Outbound only.** The security group has no ingress rule and there is no
  SSH key: operators get a shell through Session Manager. The instance sits in
  a public subnet with a public IPv4 address, which changes at every start.
- **Replacing the instance ends the game in progress.** A new `ami_id` and
  any change to what the instance is set up with at boot (the names of the
  secrets, the environment, the records and health inputs, the repository)
  replace it, and a new `instance_type` restarts or replaces it (the plan says
  which). So can a new
  version of this module, when it changes the scripts on the instance. Read
  the plan, and apply such changes while the bot is idle. Changing the
  schedule, the log retention or the repository's lifecycle leaves the
  instance alone.
- **Pin `ami_id`.** Without a pin the instance follows the latest Amazon
  Linux 2023 image, and every new release shows up in the next plan as a
  replacement.
- **Secrets are yours to create.** Each one is an SSM SecureString parameter
  under `/<name_root>/<project>/` (and outside its `bot/` path, which a
  release can write), encrypted with the account's default `aws/ssm` key and
  created outside Terraform, so its value never reaches the state. The
  instance role may read exactly the ones in `secret_parameters`.
- **The records bucket is not created here.** Pass the name of an existing
  one. The instance can only add objects under `records_prefix`: it cannot
  read them back or delete them.
- **An existing repository** has to be in the instance's region, which is
  where the instance logs in to ECR. One in another account also needs a
  repository policy that lets the instance role pull.
- **The created repository is not deleted while it holds images**
  (`force_delete = false`): a `terraform destroy` fails on it until they are
  removed.
- **The names are derived**: the repository is `<name_root>-<project>` and
  the instance, its role, instance profile and security group are
  `<name_root>-<project>-bot`, which must fit in 48 characters. Use the
  submodules directly for other names.
- **Providers are never configured here.** The caller configures `aws`.
- **Tags.** Every resource gets `Name` and `Component` from the module. Every
  other tag comes from the caller's provider `default_tags`; the modules take
  no tag map. The `jaws-ci` policies recognise the project's instance by a
  `Project` tag equal to `project`, so set one there if you use them.

The submodule READMEs have the details: every step of a rollout, the layout
and the schema of the game records, and how the schedule is validated.

## Development

See [CONTRIBUTING.md](https://github.com/jaws-platform/terraform-aws-jaws-lichess-bot/blob/main/CONTRIBUTING.md)
for local setup, the commit and pull request rules, CI, and how releases work.
`scripts/check.sh` runs everything CI runs, with no AWS credentials.

## Root module reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| image | ./modules/ecr-repository | n/a |
| instance | ./modules/container-instance | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name\_root | Prefix of every name and path, in kebab-case: usually the organisation, for example `acme`. The repository is `<name_root>-<project>`, the instance `<name_root>-<project>-bot`, and the parameters and logs live under `/<name_root>/<project>/bot`. | `string` | n/a | yes |
| project | Project in kebab-case, for example `chess-engine`. The policies of `jaws-platform/jaws-ci/aws` recognise the instance by a `Project` tag with this value, so give the provider's `default_tags` one if a role from that family deploys to it. | `string` | n/a | yes |
| subnet\_id | Public subnet of the instance, for example an element of output `public_subnet_ids` of `jaws-platform/jaws-network/aws`. The instance gets a public IPv4 address for egress and has no ingress rule. | `string` | n/a | yes |
| vpc\_id | VPC of the instance's security group, for example output `vpc_id` of `jaws-platform/jaws-network/aws`. | `string` | n/a | yes |
| ami\_id | Amazon Linux 2023 image of the instance, matching `architecture`. Pin it, so the instance is replaced only when you change the pin. Null follows the latest image, which replaces the instance (and ends the game in progress) whenever Amazon publishes one. | `string` | `null` | no |
| architecture | CPU architecture of the instance's image: `x86_64` or `arm64`. The container image must be built for the same one. | `string` | `"x86_64"` | no |
| bot\_name | Name of the account the container plays as (the Lichess bot user), recorded with every game record. | `string` | `""` | no |
| container\_environment | Plain environment variables for the container. Values must not contain whitespace or quotes. | `map(string)` | `{}` | no |
| expire\_untagged\_after\_days | Untagged images in the created repository (for example layers left behind by a failed push) expire this many days after being pushed. Unused with `image_repository`. | `number` | `7` | no |
| health\_log\_pattern | Text a new container must log within `health_seconds` to count as healthy, for example `awaiting challenges`. Without it the container only has to stay up. A tag that fails the check is rolled back to the previous one. | `string` | `""` | no |
| health\_seconds | Seconds a new container has to prove it is healthy before it is rolled back, from 10 to 600. | `number` | `90` | no |
| image\_repository | An existing ECR repository to run images from, instead of creating one: its `url` (`<account>.dkr.ecr.<region>.amazonaws.com/<name>`) and its `arn`. It must be in the instance's region. Null creates the repository `<name_root>-<project>`. | <pre>object({<br/>    url = string<br/>    arn = string<br/>  })</pre> | `null` | no |
| instance\_type | EC2 instance type. It must match `architecture`: `t3` for `x86_64`, `t4g` for `arm64`. | `string` | `"t3.micro"` | no |
| keep\_release\_images | How many `v*`-tagged images the created repository keeps. Older ones expire. Unused with `image_repository`. | `number` | `20` | no |
| log\_retention\_days | Retention of the container's CloudWatch log group, in days: one of the values CloudWatch allows. | `number` | `30` | no |
| records\_bucket\_name | Existing bucket that finished game records are shipped to, for example output `name` of `jaws-platform/jaws-foundation/aws//modules/private-bucket`. The instance may add objects under `records_prefix` and nothing else. Null ships no records. | `string` | `null` | no |
| records\_container\_path | Absolute path inside the container where it writes one `.pgn` file per game, for example `/opt/lichess-bot/game_records`. Required with `records_bucket_name`. | `string` | `null` | no |
| records\_prefix | Key prefix of the game records in the bucket: lowercase path segments ending in `/`. | `string` | `"records/"` | no |
| schedule | When the instance runs, in UTC: `days` is `daily`, `weekdays` or `weekends`, and `start` and `stop` are `HH:MM` on a quarter hour of the same day, 4 to 20 hours apart, with `stop` at 22:45 at the latest. At `stop` the container is asked to finish (a bot ends its game) and the instance powers off; 60 minutes later it is stopped regardless. Null runs it all the time. | <pre>object({<br/>    days  = string<br/>    start = string<br/>    stop  = string<br/>  })</pre> | `null` | no |
| secret\_parameters | Environment variables the container gets from SSM SecureString parameters: variable name to parameter name, for example `{ LICHESS_TOKEN = "/acme/chess-engine/lichess-token" }`. Each must live under `/<name_root>/<project>/` and outside `/<name_root>/<project>/bot/`. Create the parameters yourself, out of band; the instance may read exactly these. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| ami\_id | Image the instance runs: the pinned `ami_id`, or the latest Amazon Linux 2023 image when nothing is pinned. |
| image\_repository\_arn | ARN of the same repository, for the IAM policy of whatever pushes to it. |
| image\_repository\_name | Name of the repository created here, `<name_root>-<project>`. Null with `image_repository`. |
| image\_repository\_url | URL of the repository the instance pulls from (`<account>.dkr.ecr.<region>.amazonaws.com/<name>`): the one created here, or `image_repository.url`. A release is `docker push <url>:<tag>`. |
| instance\_arn | ARN of the instance. |
| instance\_id | ID of the instance, for Run Command (the deploy) and Session Manager (`aws ssm start-session --target`). |
| log\_group\_arn | ARN of the log group. |
| log\_group\_name | CloudWatch log group the container logs to, `/<name_root>/<project>/bot`. |
| parameter\_names | The parameters a deploy and the instance share: `desired_version` (the image tag to run, written by a deploy), `running_version` and `status` (written by the instance) and `last_sync` (written by the records sync). |
| parameter\_prefix | SSM path of the parameters a deploy and the instance share, `/<name_root>/<project>/bot`, for the IAM policy of whatever deploys. |
| public\_ip | Public IPv4 address of the instance. It is for egress only (nothing listens) and changes whenever the instance is started or replaced. |
| records\_uri | S3 URI the game records are shipped under. Null without `records_bucket_name`. |
| role\_arn | ARN of the instance role. |
| role\_name | Name of the instance role, `<name_root>-<project>-bot`, for attaching a policy of your own. |
| schedule | The names of the start, drain and stop schedules (EventBridge Scheduler, default group) and the UTC cron expression of each. Null without `schedule`. |
| security\_group\_id | ID of the instance's security group, which has no ingress rule. |
<!-- END_TF_DOCS -->

## License

[MIT](https://github.com/jaws-platform/terraform-aws-jaws-lichess-bot/blob/main/LICENSE)
