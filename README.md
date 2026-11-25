# End-to-End DevOps Project: Jenkins → Docker → ECR → EKS → Prometheus/Grafana

A Python (Flask) web app shipped through a full CI/CD pipeline on AWS.

```
GitHub push ──webhook──► Jenkins
                           ├─ Unit tests (pytest + coverage)
                           ├─ SonarQube analysis + Quality Gate
                           ├─ Docker build
                           ├─ Trivy scan (fs + image, fails on HIGH/CRITICAL)
                           ├─ Push versioned image to Amazon ECR   (main branch)
                           └─ Deploy to Amazon EKS (rolling update, auto-rollback)
                                         │
                       Prometheus + Grafana + Alertmanager
                       (CPU, memory, pod restarts, app health alerts)
```

## Repo layout

| Path | What it is |
|---|---|
| `app/main.py` | Flask app: `/`, `/health`, `/ready`, `/api/add`, `/metrics` |
| `tests/` | pytest unit tests |
| `Dockerfile` | Multi-stage, non-root, gunicorn image |
| `Jenkinsfile` | Declarative CI/CD pipeline |
| `sonar-project.properties` | SonarQube config |
| `jenkins/` | Jenkins (with docker, aws, kubectl, trivy, sonar-scanner) + SonarQube via docker compose |
| `terraform/` | VPC, ECR repo, EKS cluster + node group |
| `k8s/` | Namespace, Deployment (RollingUpdate), LoadBalancer Service, HPA, PDB |
| `monitoring/` | kube-prometheus-stack values, ServiceMonitor, alert rules, Grafana dashboard |
| `scripts/` | `install-monitoring.sh`, `destroy.sh` |

## Prerequisites

AWS account + IAM user with admin (for Terraform; Jenkins itself uses an IAM role) · AWS CLI v2 · Terraform ≥ 1.6 · kubectl · Helm 3 · Docker · a GitHub repo.

> **Cost warning:** EKS control plane (~$0.10/h), 2× t3.medium nodes, a NAT gateway and 2 load balancers cost roughly **$6–8/day**. Run `scripts/destroy.sh` when done.

## 1. Run locally

```bash
python -m venv .venv && . .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements-dev.txt
pytest
docker build -t devops-python-app .
docker run -p 8080:8080 devops-python-app            # http://localhost:8080
```

## 2. Create AWS infrastructure

```bash
aws configure                                       # region ap-south-1
cd terraform
cp terraform.tfvars.example terraform.tfvars        # set jenkins_iam_user_arn
terraform init
terraform apply                                     # ~15 min
$(terraform output -raw kubeconfig_command)
kubectl get nodes
```

## 3. Install monitoring

```bash
export GRAFANA_PASSWORD='choose-a-strong-one'
bash scripts/install-monitoring.sh
```
Prints the Grafana URL. Dashboard **"DevOps App - Overview"** loads automatically. Alerts: `AppHighCPU`, `AppHighMemory`, `AppPodRestarting`, `AppDown`, `AppNoAvailableReplicas`, `AppHigh5xxRate` (see Prometheus → Alerts; add a Slack/email receiver in `monitoring/prometheus-values.yaml`).

## 4. Start Jenkins + SonarQube

Terraform (`terraform/jenkins.tf`) creates a t3.large Ubuntu EC2 server in the VPC's public subnet. It is fully automatic — no manual setup wizard:

- **IAM role** on the instance gives Jenkins ECR push + EKS deploy rights (no stored AWS keys). An EKS access entry maps the role into the cluster.
- **Security group**: port 8080 only from GitHub's webhook IPs and `admin_cidr`; port 9000 (SonarQube) only from `admin_cidr`. No SSH — use SSM Session Manager.
- **Boot script** (`terraform/jenkins-userdata.sh.tftpl`) installs Docker, clones this repo, starts SonarQube, sets its admin password, creates an analysis token and the Jenkins webhook, then starts Jenkins.
- **JCasC** (`jenkins/casc/jenkins.yaml`) creates the `admin` user, the `sonarqube` server config and the `devops-python-app` pipeline job with the GitHub push trigger.
- Admin passwords are random and stored in SSM Parameter Store:

```bash
aws ssm get-parameter --with-decryption --name /devops-python-app/jenkins/admin-password --query Parameter.Value --output text
aws ssm get-parameter --with-decryption --name /devops-python-app/sonarqube/admin-password --query Parameter.Value --output text
terraform -chdir=terraform output jenkins_url
```

If your home IP changes, update `admin_cidr` in `terraform/terraform.tfvars` and run `terraform apply`. Boot log on the server: `/var/log/ci-bootstrap.log`.

## 5. GitHub webhook

Repo → *Settings → Webhooks → Add*: Payload URL `http://<jenkins-host>:8080/github-webhook/`, content type `application/json`, event *Just the push event*.

Now every `git push` runs the pipeline. On `main` it pushes `<account>.dkr.ecr.ap-south-1.amazonaws.com/devops-python-app:<build>-<sha>` and deploys. The live URL is printed at the end of the build, or:

```bash
kubectl -n devops-app get svc devops-app
```

## Rolling updates & rollback

- `maxSurge: 1`, `maxUnavailable: 0` → zero downtime; readiness probe gates traffic.
- `progressDeadlineSeconds: 120` + Jenkins `kubectl rollout status --timeout=180s`; on failure Jenkins runs `kubectl rollout undo` and fails the build.
- Manual: `kubectl -n devops-app rollout history deployment/devops-app` / `rollout undo --to-revision=N`.

## Tear down

```bash
bash scripts/destroy.sh
```
