output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "sonarqube_url" {
  value = "http://${aws_instance.jenkins.public_ip}:9000"
}

output "jenkins_webhook_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080/github-webhook/"
}

output "jenkins_instance_id" {
  value = aws_instance.jenkins.id
}
