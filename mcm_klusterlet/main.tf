## Generate unique ID for temporary work directory on docker host
resource "random_string" "random-dir" {
  length  = 8
  special = false
}


## Set up local variables to be used
locals {
  work_dir             = "mcm${random_string.random-dir.result}"
  kubeconfig_file      = "${local.work_dir}/target_cluster_kubeconfig.yaml}"
  certificate_file     = "${local.work_dir}/target_cluster_certificate.pem}"
}

resource "local_file" "create_kubeconfig_file" {
  count      = "${length(var.cluster_config) > 0 ? 1 : 0}"
  content    = "${base64decode(var.cluster_config)}"
  filename   = "${local.kubeconfig_file}"
}

resource "local_file" "create_certificate_file" {
  count      = "${length(var.cluster_certificate_authority) > 0 ? 1 : 0}"
  content    = "${var.cluster_certificate_authority}"
  filename   = "${local.certificate_file}"
}

resource "null_resource" "manage-cluster" {
  provisioner "local-exec" {
    command = "chmod 755 ${path.module}/scripts/manage_target_cluster.sh && ${path.module}/scripts/manage_target_cluster.sh -ac import -ct ${var.cluster_type} -wd ${local.work_dir}"
    environment {
      ## Required
      CLUSTER_NAME                = "${var.cluster_name}"
      ICP_URL                     = "${var.icp_url}"
      ICP_ADMIN_USER              = "${var.icp_admin_user}"
      ICP_ADMIN_PASSWORD          = "${var.icp_admin_password}"

      ## Cluster details
      CLUSTER_NAMESPACE           = "${var.cluster_namespace}"
      CLUSTER_CONFIG_FILE         = "${local.kubeconfig_file}"
      CLUSTER_ENDPOINT            = "${var.cluster_endpoint}"
      CLUSTER_USER                = "${var.cluster_user}"
      CLUSTER_TOKEN               = "${var.cluster_token}"

      ## IKS
      CLUSTER_CA_CERTIFICATE_FILE = "${local.certificate_file}"
      ## GKE
      SERVICE_ACCOUNT_CREDENTIALS = "${var.service_account_credentials}"
      ## EKS
      ACCESS_KEY_ID               = "${var.access_key_id}"
      SECRET_ACCESS_KEY           = "${var.secret_access_key}"
      CLUSTER_REGION              = "${var.cluster_region}"

      ## Private docker registry
      IMAGE_REGISTRY              = "${var.image_registry}"
      IMAGE_SUFFIX                = "${var.image_suffix}"
      IMAGE_VERSION               = "${var.image_version}"
      DOCKER_USER                 = "${var.docker_user}"
      DOCKER_PASSWORD             = "${var.docker_password}"
    }
  }
  
  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 755 ${path.module}/scripts/manage_target_cluster.sh && ${path.module}/scripts/manage_target_cluster.sh -ac remove -ct ${var.cluster_type} -wd ${local.work_dir}"
    environment {
      ## Required
      CLUSTER_NAME                = "${var.cluster_name}"
      ICP_URL                     = "${var.icp_url}"
      ICP_ADMIN_USER              = "${var.icp_admin_user}"
      ICP_ADMIN_PASSWORD          = "${var.icp_admin_password}"
    }
  }
}