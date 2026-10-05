
# Pravin DevOps Platform

A production-style DevOps and GitOps practice platform built on AWS, Terraform, Ansible, GitHub Actions, Docker, GHCR, Kubernetes, Helm, and Argo CD.

## Architecture

```text
Developer
   |
   | Git Push
   v
GitHub
   |
   +----------------------+
   | GitHub Actions       |
   |----------------------|
   | Terraform CI         |
   | Trivy Security Scan  |
   | Maven Test / Build   |
   | Docker Build         |
   | Helm Validation      |
   | Ansible Validation   |
   +----------+-----------+
              |
              v
             GHCR
              |
              | Immutable image
              | sha-<Git SHA>
              v
           Argo CD
              |
              v
             EKS
```

## AWS Infrastructure

Terraform provisions:

- VPC
- Public and private subnets
- Internet Gateway
- NAT Gateways
- Route tables
- Security Groups
- Jump Server EC2
- Private Application EC2
- EKS cluster
- EKS managed node group
- IAM roles
- KMS encryption

### Network Architecture

```text
Internet
   |
   v
Jump Server
Public Subnet
   |
   | SSH
   v
Private Application EC2

Private Subnets
   |
   +--> EKS Control Plane
   |
   +--> EKS Worker Nodes
```

The EKS Kubernetes API is configured for private access.

## Security

Security hardening includes:

- IMDSv2 required on EC2
- Encrypted EBS volumes
- KMS encryption for Kubernetes secrets
- Restricted SSH access
- Private application server
- Private EKS worker nodes
- Non-root Kubernetes containers
- Disabled privilege escalation
- Read-only container filesystem
- Linux capabilities dropped
- Memory-backed `/tmp`
- Resource requests and limits
- ServiceAccount token automount disabled
- Kubernetes NetworkPolicy
- PodDisruptionBudget
- Topology spread constraints
- Trivy security scanning
- Terraform security quality gates

## CI/CD

GitHub Actions performs automated validation and build stages.

### Terraform CI

- Terraform format check
- Terraform initialization
- Terraform validation
- Trivy Terraform security scan

### Spring Boot CI

- Maven build
- Unit tests
- Docker image build
- GHCR authentication
- Image push

Container images use Git SHA-based tags instead of mutable `latest` tags.

Example:

```text
ghcr.io/pravinmoreone-ux/pravin-devops-platform/springboot:sha-<GIT_SHA>
```

### Helm CI

- Helm lint
- Helm template validation

## Kubernetes

The Spring Boot Helm chart includes:

- Deployment
- Service
- Health probes
- Resource requests and limits
- SecurityContext
- NetworkPolicy
- PodDisruptionBudget
- Topology spread constraints

## GitOps

Argo CD continuously reconciles the Kubernetes state from Git.

```text
Git
 |
 v
Helm Chart
 |
 v
Argo CD
 |
 v
EKS
```

Argo CD is configured for:

- Automated synchronization
- Self-healing
- Pruning of removed resources

## Repository Structure

```text
.
├── .github/
│   └── workflows/
│
├── ansible/
│   ├── inventory/
│   ├── playbooks/
│   └── roles/
│
├── apps/
│   └── springboot/
│
├── argocd/
│
├── helm/
│   └── springboot/
│
├── policies/
│
├── terraform/
│
├── .trivyignore
└── README.md
```

## Technology Stack

| Area | Technology |
|---|---|
| Cloud | AWS |
| Infrastructure as Code | Terraform |
| Configuration Management | Ansible |
| CI | GitHub Actions |
| Containerization | Docker |
| Container Registry | GitHub Container Registry |
| Orchestration | Kubernetes / Amazon EKS |
| Packaging | Helm |
| GitOps | Argo CD |
| Security Scanning | Trivy |
| Application | Spring Boot |
| Policy as Code | OPA |

## Deployment Flow

```text
Code Commit
     |
     v
GitHub Actions
     |
     +--> Test
     |
     +--> Security Scan
     |
     +--> Docker Build
     |
     v
GHCR
     |
     v
Immutable Image
     |
     v
Helm
     |
     v
Argo CD
     |
     v
Amazon EKS
```

## Current Project Goals

This project demonstrates practical knowledge of:

- Infrastructure as Code
- AWS networking
- Terraform
- Ansible
- CI/CD
- Containerization
- Kubernetes
- Helm
- GitOps
- Security scanning
- Kubernetes security hardening
- High availability
- Observability
- Policy as Code

## Author

Pravin More

