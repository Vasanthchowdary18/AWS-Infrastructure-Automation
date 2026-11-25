variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "devops-python-app"
}

variable "cluster_name" {
  type    = string
  default = "devops-eks"
}

variable "cluster_version" {
  type    = string
  default = "1.36"
}

variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "ecr_repo_name" {
  type    = string
  default = "devops-python-app"
}

variable "jenkins_iam_user_arn" {
  description = "ARN of the IAM user/role Jenkins uses, granted cluster-admin on EKS. Leave empty to skip."
  type        = string
  default     = ""
}
