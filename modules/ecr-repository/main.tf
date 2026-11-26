resource "aws_ecr_repository" "this" {
  name = var.name

  # Release tags are exact versions; a tag can never be moved to another image.
  # Only the tags in var.mutable_tags are exempt, and they may move.
  image_tag_mutability = length(var.mutable_tags) > 0 ? "IMMUTABLE_WITH_EXCLUSION" : "IMMUTABLE"

  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = toset(var.mutable_tags)

    content {
      filter      = image_tag_mutability_exclusion_filter.value
      filter_type = "WILDCARD"
    }
  }

  # A repository that still holds images cannot be destroyed by accident.
  force_delete = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name      = var.name
    Component = var.component
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = concat(
      # A tag sits on one image, so these rules expire nothing. They come first
      # because ECR evaluates rules by priority and an image that a higher
      # priority rule matches is never expired by a lower one.
      [
        for i, tag in var.mutable_tags : {
          rulePriority = i + 1
          description  = "Keep the image tagged ${tag}"
          selection = {
            tagStatus      = "tagged"
            tagPatternList = [tag]
            countType      = "imageCountMoreThan"
            countNumber    = 1
          }
          action = {
            type = "expire"
          }
        }
      ],
      [
        {
          rulePriority = length(var.mutable_tags) + 1
          description  = "Expire untagged images ${var.expire_untagged_after_days} days after they are pushed"
          selection = {
            tagStatus   = "untagged"
            countType   = "sinceImagePushed"
            countUnit   = "days"
            countNumber = var.expire_untagged_after_days
          }
          action = {
            type = "expire"
          }
        },
        {
          rulePriority = length(var.mutable_tags) + 2
          description  = "Keep the ${var.keep_release_images} newest release images"
          selection = {
            tagStatus     = "tagged"
            tagPrefixList = var.release_tag_prefixes
            countType     = "imageCountMoreThan"
            countNumber   = var.keep_release_images
          }
          action = {
            type = "expire"
          }
        },
      ],
    )
  })
}
