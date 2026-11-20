mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      region = "us-east-1"
    }
  }

  # The latest Amazon Linux 2023 image, which the instance follows when no
  # image is pinned.
  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }

  # The instance module validates the repository's URL and ARN, so the mocked
  # repository has to return well-formed ones.
  mock_resource "aws_ecr_repository" {
    defaults = {
      arn            = "arn:aws:ecr:us-east-1:123456789012:repository/acme-chess-engine"
      repository_url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/acme-chess-engine"
      registry_id    = "123456789012"
    }
  }

  mock_resource "aws_instance" {
    defaults = {
      id  = "i-0123456789abcdef0"
      arn = "arn:aws:ec2:us-east-1:123456789012:instance/i-0123456789abcdef0"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/acme-chess-engine-bot"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/acme/chess-engine/bot"
    }
  }
}

variables {
  name_root = "acme"
  project   = "chess-engine"
  vpc_id    = "vpc-0123456789abcdef0"
  subnet_id = "subnet-0123456789abcdef0"
}

run "a_repository_and_an_instance_by_default" {
  command = apply

  assert {
    condition     = length(module.image) == 1 && module.image[0].name == "acme-chess-engine"
    error_message = "the defaults must create one repository named <name_root>-<project>"
  }

  assert {
    condition = (
      output.image_repository_url == module.image[0].url &&
      output.image_repository_arn == module.image[0].arn &&
      output.image_repository_name == "acme-chess-engine"
    )
    error_message = "the repository outputs must describe the created repository"
  }

  assert {
    condition     = output.image_repository_url == "123456789012.dkr.ecr.us-east-1.amazonaws.com/acme-chess-engine"
    error_message = "image_repository_url must be the URL images are pushed to"
  }

  assert {
    condition     = output.role_name == "acme-chess-engine-bot"
    error_message = "the instance, and so its role, must be named <name_root>-<project>-bot"
  }

  assert {
    condition = (
      output.log_group_name == "/acme/chess-engine/bot" &&
      output.parameter_prefix == "/acme/chess-engine/bot"
    )
    error_message = "logs and parameters must live under /<name_root>/<project>/bot"
  }

  assert {
    condition = output.parameter_names == {
      desired_version = "/acme/chess-engine/bot/desired-version"
      running_version = "/acme/chess-engine/bot/running-version"
      status          = "/acme/chess-engine/bot/status"
      last_sync       = "/acme/chess-engine/bot/last-sync"
    }
    error_message = "parameter_names must name the four parameters a deploy and the instance share"
  }

  assert {
    condition = (
      output.instance_id == module.instance.instance_id &&
      output.instance_arn == module.instance.instance_arn &&
      output.public_ip == module.instance.public_ip &&
      output.security_group_id == module.instance.security_group_id &&
      output.role_arn == module.instance.role_arn &&
      output.log_group_arn == module.instance.log_group_arn
    )
    error_message = "the instance outputs must be the container-instance module's outputs"
  }

  assert {
    condition     = output.instance_id == "i-0123456789abcdef0" && output.security_group_id != null && output.role_arn != null
    error_message = "the instance outputs must be set"
  }

  assert {
    condition     = output.ami_id == "ami-0123456789abcdef0"
    error_message = "without ami_id the instance must follow the latest Amazon Linux 2023 image"
  }

  assert {
    condition     = output.records_uri == null && output.schedule == null
    error_message = "the defaults must ship no records and set no schedule"
  }
}

run "an_existing_repository" {
  command = apply

  variables {
    image_repository = {
      url = "123456789012.dkr.ecr.us-east-1.amazonaws.com/acme-engines"
      arn = "arn:aws:ecr:us-east-1:123456789012:repository/acme-engines"
    }
  }

  assert {
    condition     = length(module.image) == 0
    error_message = "image_repository must not create a repository"
  }

  assert {
    condition = (
      output.image_repository_url == "123456789012.dkr.ecr.us-east-1.amazonaws.com/acme-engines" &&
      output.image_repository_arn == "arn:aws:ecr:us-east-1:123456789012:repository/acme-engines"
    )
    error_message = "the repository outputs must describe the given repository"
  }

  assert {
    condition     = output.image_repository_name == null
    error_message = "image_repository_name is only for a repository created here"
  }

  assert {
    condition     = output.instance_id == module.instance.instance_id && output.role_name == "acme-chess-engine-bot"
    error_message = "the instance must be the same with an existing repository"
  }
}

# A shared repository often comes from the same configuration, so its URL and
# ARN are unknown until it is applied. Whether to create a repository must not
# depend on them: the fixture passes such a repository to the root module.
run "an_existing_repository_not_yet_created" {
  command = plan

  module {
    source = "./tests/fixtures/shared-repository"
  }

  assert {
    condition     = output.image_repository_name == null && output.role_name == "acme-chess-engine-bot"
    error_message = "an image_repository whose values are not known yet must still plan, with the instance and no second repository"
  }
}

run "secrets_and_environment" {
  command = apply

  variables {
    secret_parameters     = { LICHESS_TOKEN = "/acme/chess-engine/lichess-token" }
    container_environment = { ENGINE_HASH_MB = "128" }
    bot_name              = "chess-engine-bot"
    health_log_pattern    = "awaiting challenges"
    health_seconds        = 120
    log_retention_days    = 90
  }

  # The instance module accepts a secret only under /<name_root>/<project>/,
  # so this run fails unless both reach it.
  assert {
    condition     = output.parameter_prefix == "/acme/chess-engine/bot"
    error_message = "name_root and project must reach the instance module"
  }
}

run "records_shipped_to_a_bucket" {
  command = apply

  variables {
    records_bucket_name    = "acme-chess-engine-records"
    records_container_path = "/opt/lichess-bot/game_records"
  }

  assert {
    condition     = output.records_uri == "s3://acme-chess-engine-records/records/"
    error_message = "records_bucket_name must ship records under the default prefix"
  }
}

run "records_under_another_prefix" {
  command = apply

  variables {
    records_bucket_name    = "acme-data"
    records_container_path = "/opt/lichess-bot/game_records"
    records_prefix         = "chess-engine/games/"
  }

  assert {
    condition     = output.records_uri == "s3://acme-data/chess-engine/games/"
    error_message = "records_prefix must be passed through"
  }
}

run "a_daily_schedule" {
  command = apply

  variables {
    schedule = { days = "daily", start = "08:00", stop = "20:00" }
  }

  assert {
    condition = output.schedule == {
      start = { name = "acme-chess-engine-bot-start", expression = "cron(0 8 * * ? *)" }
      drain = { name = "acme-chess-engine-bot-drain", expression = "cron(0 20 * * ? *)" }
      stop  = { name = "acme-chess-engine-bot-stop", expression = "cron(0 21 * * ? *)" }
    }
    error_message = "schedule must start at start, drain at stop and stop 60 minutes later, every day"
  }
}

run "the_latest_stop_the_description_promises" {
  command = plan

  variables {
    schedule = { days = "weekdays", start = "08:00", stop = "22:45" }
  }

  assert {
    condition     = output.schedule.stop.expression == "cron(45 23 ? * MON-FRI *)"
    error_message = "a stop at 22:45 must be accepted, with the hard stop at 23:45"
  }
}

run "a_pinned_arm64_instance" {
  command = apply

  variables {
    architecture  = "arm64"
    instance_type = "t4g.small"
    ami_id        = "ami-0fedcba9876543210"
  }

  assert {
    condition     = output.ami_id == "ami-0fedcba9876543210"
    error_message = "ami_id must pin the image of the instance"
  }
}

run "repository_lifecycle_is_passed_through" {
  command = plan

  variables {
    keep_release_images        = 5
    expire_untagged_after_days = 1
  }

  assert {
    condition     = length(module.image) == 1
    error_message = "the lifecycle inputs must still plan one repository"
  }
}

run "the_longest_names_that_fit" {
  command = plan

  variables {
    name_root = "acme-technologies"
    project   = "a-project-name-of-26-chars"
  }

  assert {
    condition     = output.role_name == "acme-technologies-a-project-name-of-26-chars-bot" && length(output.role_name) == 48
    error_message = "43 characters of name_root and project make a 48-character instance name, which must be accepted"
  }
}

run "rejects_names_too_long_for_the_instance" {
  command = plan

  variables {
    name_root = "acme-technologies"
    project   = "a-project-name-with-27-char"
  }

  expect_failures = [var.project]
}
