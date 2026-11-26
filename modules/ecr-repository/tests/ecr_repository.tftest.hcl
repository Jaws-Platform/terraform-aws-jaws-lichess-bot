mock_provider "aws" {
  override_during = plan

  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:us-east-1:123456789012:repository/acme-technologies-sites"
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/acme-technologies-sites"
      registry_id    = "123456789012"
    }
  }
}

variables {
  name = "acme-technologies-sites"
}

run "repository_hardening" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.name == "acme-technologies-sites"
    error_message = "repository name must be var.name"
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "tags must be immutable so a release tag can never be moved"
  }

  assert {
    condition     = aws_ecr_repository.this.force_delete == false
    error_message = "the repository must not be force-deletable"
  }

  assert {
    condition     = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push == true
    error_message = "images must be scanned on push"
  }

  assert {
    condition     = aws_ecr_repository.this.encryption_configuration[0].encryption_type == "AES256"
    error_message = "images must be encrypted with AES256"
  }

  assert {
    condition     = aws_ecr_repository.this.tags == tomap({ Name = "acme-technologies-sites", Component = "ecr-repository" })
    error_message = "the repository must carry Name and Component tags only"
  }
}

run "lifecycle_policy_defaults" {
  command = plan

  assert {
    condition     = aws_ecr_lifecycle_policy.this.repository == "acme-technologies-sites"
    error_message = "the lifecycle policy must attach to the repository"
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.tagStatus == "untagged" &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countType == "sinceImagePushed" &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countNumber == 7
    )
    error_message = "rule 1 must expire untagged images 7 days after push by default"
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.tagStatus == "tagged" &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.tagPrefixList == ["v"] &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countType == "imageCountMoreThan" &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countNumber == 20
    )
    error_message = "rule 2 must keep the 20 newest v* images by default"
  }
}

run "lifecycle_policy_custom" {
  command = plan

  variables {
    keep_release_images        = 5
    expire_untagged_after_days = 1
    release_tag_prefixes       = ["release-"]
  }

  assert {
    condition = (
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].selection.countNumber == 1 &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.countNumber == 5 &&
      jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[1].selection.tagPrefixList == ["release-"]
    )
    error_message = "lifecycle values must come from the variables"
  }
}

run "outputs" {
  command = plan

  assert {
    condition = (
      output.arn == "arn:aws:ecr:us-east-1:123456789012:repository/acme-technologies-sites" &&
      output.url == "123456789012.dkr.ecr.us-east-1.amazonaws.com/acme-technologies-sites" &&
      output.name == "acme-technologies-sites" &&
      output.registry_id == "123456789012"
    )
    error_message = "outputs must describe the repository"
  }
}

run "rejects_uppercase_name" {
  command = plan

  variables {
    name = "Acme-Sites"
  }

  expect_failures = [var.name]
}

run "rejects_zero_keep" {
  command = plan

  variables {
    keep_release_images = 0
  }

  expect_failures = [var.keep_release_images]
}

run "a_mutable_tag_moves_and_its_image_is_kept" {
  command = plan

  variables {
    mutable_tags         = ["current"]
    release_tag_prefixes = ["sha-"]
    keep_release_images  = 10
  }

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE_WITH_EXCLUSION"
    error_message = "a mutable tag needs IMMUTABLE_WITH_EXCLUSION so every other tag stays immutable"
  }

  assert {
    condition = (
      length(aws_ecr_repository.this.image_tag_mutability_exclusion_filter) == 1 &&
      [for f in aws_ecr_repository.this.image_tag_mutability_exclusion_filter : f.filter] == ["current"] &&
      [for f in aws_ecr_repository.this.image_tag_mutability_exclusion_filter : f.filter_type] == ["WILDCARD"]
    )
    error_message = "exactly one exclusion filter, `current`, must exempt the mutable tag"
  }

  assert {
    condition = [
      for r in jsondecode(aws_ecr_lifecycle_policy.this.policy).rules : [r.rulePriority, r.selection]
      ] == [
      [1, { tagStatus = "tagged", tagPatternList = ["current"], countType = "imageCountMoreThan", countNumber = 1 }],
      [2, { tagStatus = "untagged", countType = "sinceImagePushed", countUnit = "days", countNumber = 7 }],
      [3, { tagStatus = "tagged", tagPrefixList = ["sha-"], countType = "imageCountMoreThan", countNumber = 10 }],
    ]
    error_message = "the policy must keep the `current` image first, then expire untagged, then keep the newest 10 sha- builds"
  }

  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.this.policy).rules[0].description == "Keep the image tagged current"
    error_message = "the keep rule must say which tag it keeps"
  }
}

run "no_mutable_tags_keeps_the_policy_of_0_1_4" {
  command = plan

  assert {
    condition     = aws_ecr_repository.this.image_tag_mutability == "IMMUTABLE"
    error_message = "without mutable tags every tag stays immutable"
  }

  assert {
    condition     = length(aws_ecr_repository.this.image_tag_mutability_exclusion_filter) == 0
    error_message = "without mutable tags there is no exclusion filter"
  }

  assert {
    condition     = length(jsondecode(aws_ecr_lifecycle_policy.this.policy).rules) == 2
    error_message = "without mutable tags the policy has exactly its two rules"
  }
}

run "rejects_a_mutable_tag_that_is_a_release_tag" {
  command = plan

  variables {
    mutable_tags = ["v-latest"]
  }

  expect_failures = [var.mutable_tags]
}

run "rejects_a_wildcard_mutable_tag" {
  command = plan

  variables {
    mutable_tags = ["cur*"]
  }

  expect_failures = [var.mutable_tags]
}
