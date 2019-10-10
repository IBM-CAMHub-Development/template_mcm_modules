variable "cluster_type" {
  description = "Type of the kubernetes cluster to be targeted (e.g. icp, ocp, iks, aks, gke, eks)"
}

variable "icp_url" {
  description = "URL, including port, for ICP server hosting the MCM hub cluster"
}

variable "icp_admin_user" {
  description = "User name for connecting to the ICP server"
}

variable "icp_admin_password" {
  description = "Password for connecting to the ICP server"
}

variable "cluster_name" {
  description = "Name of the kubernetes cluster"
  default = ""
}

variable "cluster_namespace" {
  description = "Namespace on the hub cluster into which the target cluster will be imported"
  default = ""
}

variable "cluster_config" {
  description = "kubeconfig file for kubernetes cluster"
  default = ""
}

variable "cluster_endpoint" {
  description = "URL for the kubernetes cluster endpoint"
  default = ""
}

variable "cluster_user" {
  description = "Username for accessing the kubernetes cluster"
  default = ""
}

variable "cluster_token" {
  description = "Token for authenticating with the kubernetes cluster"
  default = ""
}


variable "cluster_certificate_authority" {
  description = "Certificate for authenticating with kubernetes cluster"
  default = ""
}

variable "cluster_region" {
  description = "The region in which the EKS cluster is deployed"
  default = ""
}

variable "service_account_credentials" {
  description = "Credentials for service account"
  default = ""
}

variable "access_key_id" {
  description = "Access key ID for authorizing with cloud and/or cluster"
  default = ""
}

variable "secret_access_key" {
  description = "Password/secret key for authorizing with cloud and/or cluster"
  default = ""
}


variable "image_registry" {
  description = "URL for private docker registry from which klusterlet images will be pulled"
  default = ""
}

variable "image_suffix" {
  description = "Suffix (e.g. platform type) to be appended to image name"
  default = ""
}

variable "image_version" {
  description = "Version (tag) of the MCM image to be pulled"
  default = ""
}

variable "docker_user" {
  description = "Username for authenticating with the private docker registry"
  default = ""
}

variable "docker_password" {
  description = "Password for authenticating with the private docker registry"
  default = ""
}
