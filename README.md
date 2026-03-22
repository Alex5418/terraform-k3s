# terraform-k3s

A production-inspired infrastructure project that provisions a multi-node K3s Kubernetes cluster on AWS using Terraform, with a full observability stack and CI/CD pipeline.

## Architecture Overview

```
GitHub Actions (CI/CD)
    └── terraform plan (on PR)
    └── terraform apply (on merge to main)
            │
            ▼
    Terraform (IaC)
    ├── modules/vpc        → VPC, Subnet, IGW, Route Table
    ├── modules/security   → Security Groups
    └── modules/compute    → EC2 Instances (K3s server + agent)
            │
            ▼
    AWS Infrastructure
    ├── VPC (10.0.0.0/16)
    │   ├── Public Subnet (10.0.1.0/24) — us-east-1a
    │   ├── Internet Gateway
    │   └── Route Table (0.0.0.0/0 → IGW)
    ├── Security Group
    │   ├── Port 22   — SSH
    │   ├── Port 6443 — K3s API Server
    │   ├── Port 3000 — Grafana
    │   └── Self      — Inter-node communication
    └── EC2 Instances
        ├── K3s Server (t3.medium)
        └── K3s Agent  (t3.micro)
                │
                ▼
        K3s Cluster
        └── monitoring namespace
            ├── Prometheus
            ├── Grafana
            └── Alertmanager
```

## Key Design Decisions

**K3s on EC2 over EKS**
EKS control plane costs ~$73/month with no Free Tier. K3s on EC2 demonstrates deeper infrastructure knowledge — VPC wiring, security groups, user-data bootstrapping — skills that EKS abstracts away.

**Modular Terraform**
Infrastructure is split into three reusable modules (`vpc`, `security`, `compute`), following the same encapsulation principle as functions — same template, different variables, different environments.

**Remote State**
`terraform.tfstate` is stored in S3 with DynamoDB locking, preventing concurrent modifications in team environments.

**Resource-constrained Helm deployment**
kube-prometheus-stack is deployed with a custom `values.yaml` to limit memory and CPU usage, fitting within a t3.medium instance — a realistic constraint common in cost-conscious production environments.

## Prerequisites

- AWS account with IAM user credentials configured
- Terraform installed
- kubectl installed
- Helm installed
- SSH key pair created in AWS (`test-keypair`)

## Quick Start

```bash
# Clone the repo
git clone https://github.com/Alex5418/terraform-k3s.git
cd terraform-k3s

# Initialize Terraform (downloads AWS provider, connects to S3 backend)
terraform init

# Preview changes
terraform plan

# Deploy infrastructure
terraform apply
```

After apply completes, the server's public IP is printed as output:

```
Outputs:
server_ip = "x.x.x.x"
```

## Deploying the Observability Stack

SSH into the server and install K3s:

```bash
ssh -i ~/.ssh/your-key.pem ec2-user@<server_ip>
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true sh -
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
```

Install Helm and deploy the monitoring stack:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring-values.yaml
```

Access Grafana:

```bash
kubectl --namespace monitoring port-forward svc/monitoring-grafana 3000:80 --address 0.0.0.0
# Open http://<server_ip>:3000 in your browser
# Default credentials: admin / prom-operator
```

## Adding an Agent Node

After the server is running, SSH into the agent node and join the cluster:

```bash
# On the server — get the token
sudo cat /var/lib/rancher/k3s/server/node-token

# On the agent
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true \
  K3S_URL=https://<server_private_ip>:6443 \
  K3S_TOKEN=<token> sh -
```

Verify from the server:

```bash
sudo kubectl get nodes
```

## CI/CD Pipeline

GitHub Actions workflow (`.github/workflows/terraform.yml`):

| Event | Action |
|-------|--------|
| Pull Request → main | `terraform plan` (preview changes) |
| Push → main | `terraform apply` (deploy changes) |

Required GitHub Secrets:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

## Terraform State

Remote state is stored in S3 with DynamoDB locking:

```hcl
backend "s3" {
  bucket         = "terraform-state-bucket"
  key            = "k3s-cluster/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "terraform-state-lock"
  encrypt        = true
}
```

## Cost Estimate

| Resource | Cost |
|----------|------|
| t3.medium (server) | ~$0.04/hr |
| t3.micro (agent) | ~$0.01/hr |
| S3 + DynamoDB | ~$0.00 (minimal usage) |
| **3 hrs/day for 3 weeks** | **~$10-15 total** |

> **Important:** Always run `terraform destroy` when done to avoid unnecessary charges.

## Teardown

```bash
terraform destroy
```

This removes all AWS resources managed by Terraform.

## What I'd Do Differently at Scale

- **Use EKS** for a managed control plane in production — operational overhead of self-managed K3s doesn't make sense at scale
- **Automate agent node joining** via S3 token passing instead of manual SSH
- **Use Terraform workspaces** or Terragrunt for dev/staging/prod environment separation
- **Add an Ingress controller** (e.g. Traefik, nginx) with a proper domain name instead of port-forwarding
- **Enable IRSA** (IAM Roles for Service Accounts) instead of storing AWS credentials as secrets
