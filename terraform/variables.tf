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

variable "repo_url" {
  description = "Public GitHub repo Jenkins builds"
  type        = string
  default     = "https://github.com/Vasanthchowdary18/AWS-Infrastructure-Automation.git"
}

variable "jenkins_instance_type" {
  type    = string
  default = "t3.large"
}

variable "admin_cidr" {
  description = "Your public IP in CIDR form (x.x.x.x/32) allowed to open Jenkins and SonarQube"
  type        = string
}
