variable "name" {
  description = "Repository name, for example `acme-chess-engine`. Also the value of its `Name` tag."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]+(?:[._-][a-z0-9]+)*(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)*$", var.name)) && length(var.name) <= 256
    error_message = "name must be a valid ECR repository name: lowercase letters, digits and single `.`, `_`, `-` or `/` separators, at most 256 characters."
  }
}

variable "keep_release_images" {
  description = "How many images tagged with one of `release_tag_prefixes` to keep. Older ones expire."
  type        = number
  default     = 20

  validation {
    condition     = var.keep_release_images >= 1 && floor(var.keep_release_images) == var.keep_release_images
    error_message = "keep_release_images must be a positive integer."
  }
}

variable "expire_untagged_after_days" {
  description = "Untagged images (for example layers left behind by a failed push) expire this many days after being pushed."
  type        = number
  default     = 7

  validation {
    condition     = var.expire_untagged_after_days >= 1 && floor(var.expire_untagged_after_days) == var.expire_untagged_after_days
    error_message = "expire_untagged_after_days must be a positive integer."
  }
}

variable "release_tag_prefixes" {
  description = "Tag prefixes that identify release images, which `keep_release_images` applies to. Defaults to `v`, for tags like `v1.2.3`."
  type        = list(string)
  default     = ["v"]

  validation {
    condition     = length(var.release_tag_prefixes) > 0 && alltrue([for p in var.release_tag_prefixes : length(p) > 0])
    error_message = "release_tag_prefixes must contain at least one non-empty prefix."
  }
}

variable "mutable_tags" {
  description = "Tags that may move from image to image, such as `current` for the build that is live. Every other tag stays immutable, and the lifecycle never expires the image a mutable tag names."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.mutable_tags) <= 5
    error_message = "mutable_tags can hold at most 5 tags, ECR's limit on exclusion filters."
  }

  validation {
    condition     = alltrue([for t in var.mutable_tags : can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", t))])
    error_message = "Each mutable tag must be a plain tag of at most 128 characters, starting with a letter, digit or underscore and holding only letters, digits, `_`, `.` and `-`; a wildcard such as `cur*` is not allowed."
  }

  validation {
    condition     = alltrue([for t in var.mutable_tags : alltrue([for p in var.release_tag_prefixes : !startswith(t, p)])])
    error_message = "No mutable tag may start with one of release_tag_prefixes, because release tags never move. Rename the tag or change release_tag_prefixes."
  }
}

variable "component" {
  description = "Value of the `Component` tag on the repository."
  type        = string
  default     = "ecr-repository"

  validation {
    condition     = length(var.component) > 0
    error_message = "component must not be empty."
  }
}
