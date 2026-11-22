# ecr-repository

Part of [`Jaws-Platform/jaws-lichess-bot/aws`](https://registry.terraform.io/modules/Jaws-Platform/jaws-lichess-bot/aws/latest) · [Registry](https://registry.terraform.io/modules/Jaws-Platform/jaws-lichess-bot/aws/latest/submodules/ecr-repository) · [Source](https://github.com/Jaws-Platform/terraform-aws-jaws-lichess-bot/tree/main/modules/ecr-repository)

A private ECR repository for one image, set up for release images:

- `IMMUTABLE` tags: a release tag can never be moved to another image, so
  the tag a consumer pins is the image it gets.
- Scan on push and AES256 encryption.
- `force_delete = false`: a repository that still holds images cannot be
  destroyed by accident.
- A lifecycle policy that expires untagged images `expire_untagged_after_days`
  after they are pushed (layers left behind by a failed push) and keeps only
  the `keep_release_images` newest images tagged with one of
  `release_tag_prefixes` (`v` by default, for `v1.2.3`).
- Tagged `Name = <name>` and `Component = <component>`.

The module grants nobody access: that is for the IAM policies of whatever
pulls and pushes. In the [`jaws-ci`](https://registry.terraform.io/modules/Jaws-Platform/jaws-ci/aws/latest)
family, the `ecr/pull` and `ecr/push` policies of
[`ci-policies`](https://registry.terraform.io/modules/Jaws-Platform/jaws-ci/aws/latest/submodules/ci-policies)
take this module's `arn`, `container/release` pushes to a repository named
`<name_root>-<project>`, and `foundation/manage` and `container/manage` let a
CI role create the repository itself.

## Usage

```hcl
module "image" {
  source  = "Jaws-Platform/jaws-lichess-bot/aws//modules/ecr-repository"
  version = "0.1.3" # x-release-please-version

  name                       = "acme-chess-engine"
  keep_release_images        = 20
  expire_untagged_after_days = 7
}
```

Its `url` and `arn` outputs are what
[`container-instance`](https://registry.terraform.io/modules/Jaws-Platform/jaws-lichess-bot/aws/latest/submodules/container-instance)
takes as `image_repository_url` and `image_repository_arn`. The
[root module](https://registry.terraform.io/modules/Jaws-Platform/jaws-lichess-bot/aws/latest)
creates the repository and the instance in one call.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| terraform | >= 1.11 |
| aws | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| aws | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| name | Repository name, for example `acme-chess-engine`. Also the value of its `Name` tag. | `string` | n/a | yes |
| component | Value of the `Component` tag on the repository. | `string` | `"ecr-repository"` | no |
| expire\_untagged\_after\_days | Untagged images (for example layers left behind by a failed push) expire this many days after being pushed. | `number` | `7` | no |
| keep\_release\_images | How many images tagged with one of `release_tag_prefixes` to keep. Older ones expire. | `number` | `20` | no |
| release\_tag\_prefixes | Tag prefixes that identify release images, which `keep_release_images` applies to. Defaults to `v`, for tags like `v1.2.3`. | `list(string)` | <pre>[<br/>  "v"<br/>]</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| arn | Repository ARN, for IAM policies: `image_repository_arn` of `container-instance`, or `policy_inputs.ecr.repository_arn` of the role modules of `Jaws-Platform/jaws-ci/aws`. |
| name | Repository name. |
| registry\_id | Registry (account) ID the repository belongs to. |
| url | Repository URL (`<account>.dkr.ecr.<region>.amazonaws.com/<name>`), for `docker push` and `docker pull`. |
<!-- END_TF_DOCS -->
