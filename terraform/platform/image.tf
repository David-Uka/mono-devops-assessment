# Requirement 3: build the image and push it to ECR from Terraform.
# The build context is hashed so a code change (and only a code change)
# produces a new image; the tag is the git sha supplied by CI.
locals {
  build_context_hash = sha256(join("", [
    for f in sort(concat(
      tolist(fileset(var.source_path, "src/**")),
      ["package.json", "package-lock.json", "tsconfig.json", "Dockerfile"]
    )) : filesha256("${var.source_path}/${f}")
  ]))
}

resource "docker_image" "api" {
  name = local.image_name

  build {
    context    = var.source_path
    dockerfile = "Dockerfile"
    platform   = "linux/amd64"
    labels = {
      "org.opencontainers.image.revision" = var.image_tag
      "org.opencontainers.image.source"   = "github"
    }
  }

  triggers = {
    context_hash = local.build_context_hash
    tag          = var.image_tag
  }
}

resource "docker_registry_image" "api" {
  name          = docker_image.api.name
  keep_remotely = true # ECR lifecycle policy prunes old tags, not terraform destroy

  triggers = {
    image_id = docker_image.api.image_id
  }
}
