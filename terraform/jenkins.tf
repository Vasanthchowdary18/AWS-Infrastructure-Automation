# ---------------- Jenkins + SonarQube CI server (EC2) ----------------
# Runs jenkins/docker-compose.yml on an Ubuntu instance. AWS access comes from the
# instance's IAM role (no static keys). Admin access via SSM Session Manager (no SSH).

data "http" "github_meta" {
  url             = "https://api.github.com/meta"
  request_headers = { Accept = "application/json", User-Agent = "terraform" }
}

locals {
  # GitHub webhook source IPs (IPv4 only)
  github_hook_cidrs = [for c in jsondecode(data.http.github_meta.response_body).hooks : c if !strcontains(c, ":")]
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

# ---------- secrets (stored encrypted in SSM Parameter Store) ----------
resource "random_password" "jenkins_admin" {
  length           = 20
  override_special = "-_"
}

resource "random_password" "sonar_admin" {
  length           = 20
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
  override_special = "-_"
}

resource "aws_ssm_parameter" "jenkins_admin" {
  name  = "/${var.project}/jenkins/admin-password"
  type  = "SecureString"
  value = random_password.jenkins_admin.result
}

resource "aws_ssm_parameter" "sonar_admin" {
  name  = "/${var.project}/sonarqube/admin-password"
  type  = "SecureString"
  value = random_password.sonar_admin.result
}

# ---------- IAM role for the Jenkins server ----------
resource "aws_iam_role" "jenkins" {
  name = "${var.project}-jenkins"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "jenkins" {
  name = "ci-permissions"
  role = aws_iam_role.jenkins.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrLogin"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
          "ecr:InitiateLayerUpload", "ecr:UploadLayerPart", "ecr:CompleteLayerUpload",
          "ecr:PutImage", "ecr:DescribeImages", "ecr:DescribeRepositories"
        ]
        Resource = aws_ecr_repository.app.arn
      },
      {
        Sid      = "EksDescribe"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = module.eks.cluster_arn
      },
      {
        Sid      = "ReadOwnSecrets"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = [aws_ssm_parameter.jenkins_admin.arn, aws_ssm_parameter.sonar_admin.arn]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project}-jenkins"
  role = aws_iam_role.jenkins.name
}

# Let the Jenkins role deploy to the EKS cluster
resource "aws_eks_access_entry" "jenkins" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.jenkins.arn
}

resource "aws_eks_access_policy_association" "jenkins" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.jenkins.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope {
    type = "cluster"
  }
  depends_on = [aws_eks_access_entry.jenkins]
}

# ---------- network ----------
resource "aws_security_group" "jenkins" {
  name        = "${var.project}-jenkins"
  description = "Jenkins and SonarQube"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Jenkins UI + webhook (GitHub hooks and admin)"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = concat(local.github_hook_cidrs, [var.admin_cidr])
  }

  ingress {
    description = "SonarQube UI (admin only)"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- instance ----------
resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.jenkins_instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2          # lets the Jenkins container use the instance role
  }

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = templatefile("${path.module}/jenkins-userdata.sh.tftpl", {
    region         = var.region
    repo_url       = var.repo_url
    jenkins_param  = aws_ssm_parameter.jenkins_admin.name
    sonar_param    = aws_ssm_parameter.sonar_admin.name
  })
  user_data_replace_on_change = true

  tags = { Name = "${var.project}-jenkins" }

  depends_on = [aws_eks_access_policy_association.jenkins]
}
