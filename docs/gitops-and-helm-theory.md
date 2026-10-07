# GitOps & Helm — How It All Connects

This document explains how Argo CD connects to Git and how Helm dependency charts work. Useful for interviews and deep understanding of the platform.

---

## Part 1 — How Argo CD Connects to Git

### The Core Concept

> Argo CD is a **GitOps controller**. It watches a Git repository and continuously makes sure the Kubernetes cluster matches what Git says it should be.

```text
Git Repository (source of truth)
        │
        │ Argo CD watches this
        ▼
Argo CD compares:
  "What does Git say?"  vs  "What is running in EKS?"
        │
        ├── Same?     → Do nothing
        └── Different? → Sync (apply the difference)
```

---

### Step-by-Step: How Argo CD Connects to Git

#### Step 1 — Argo CD Application YAML
You define an Application resource that tells Argo CD:
- Which Git repo to watch
- Which path in that repo contains the Helm chart
- Which Kubernetes cluster to deploy to
- Which namespace to deploy into

Example from [`argocd/springboot-application.yaml`](../argocd/springboot-application.yaml):

```yaml
spec:
  source:
    repoURL: https://github.com/pravinmoreone-ux/pravin-devops-platform.git
    targetRevision: main          # watch the main branch
    path: helm/springboot         # look at this folder in the repo

  destination:
    server: https://kubernetes.default.svc   # this EKS cluster
    namespace: default                        # deploy into this namespace
```

#### Step 2 — Argo CD polls Git every 3 minutes
```text
Argo CD repo-server
      │
      │ Every 3 minutes (or on webhook):
      │ git fetch origin main
      ▼
Reads helm/springboot/Chart.yaml
Reads helm/springboot/values.yaml
Reads helm/springboot/templates/*.yaml
      │
      ▼
Renders Helm templates into Kubernetes manifests
(same as: helm template springboot helm/springboot)
      │
      ▼
Compares rendered manifests with what's running in EKS
```

#### Step 3 — Argo CD syncs the difference
```text
Git says:         image: sha-NEW123
EKS running:      image: sha-OLD456
      │
      ▼
Argo CD applies the difference:
kubectl apply -f deployment.yaml  (with new image tag)
      │
      ▼
Kubernetes does rolling update:
  - Starts new pod with sha-NEW123
  - Waits for readiness probe (/actuator/health)
  - Terminates old pod with sha-OLD456
```

#### Step 4 — Self-heal (automated=true, selfHeal=true)
```text
Someone manually changes image tag in EKS:
  kubectl set image deployment/springboot springboot=sha-MANUAL

Argo CD detects drift (Git ≠ EKS)
      │
      ▼
Automatically reverts to what Git says
      │
      ▼
Git is ALWAYS the source of truth
```

---

### The Full GitOps Loop

```text
Developer pushes code
      │
      ▼
GitHub Actions CI:
  - Builds Docker image
  - Pushes to GHCR: sha-NEW123
  - Updates helm/springboot/values.yaml:
      image:
        tag: "sha-NEW123"
  - git commit + git push
      │
      ▼
Git repo now has new image tag
      │
      ▼
Argo CD detects change (within 3 min or via webhook)
      │
      ▼
Renders Helm chart with new tag
      │
      ▼
Applies to EKS → rolling update
      │
      ▼
New version running in production
```

**Nobody ran kubectl manually. Everything went through Git.**

---

### Argo CD Sync Policy Explained

From your Application YAMLs:

```yaml
syncPolicy:
  automated:
    prune: true       # delete resources removed from Git
    selfHeal: true    # revert manual changes in cluster
    allowEmpty: false # never delete everything accidentally
  syncOptions:
    - CreateNamespace=true    # create namespace if it doesn't exist
    - ServerSideApply=true    # use server-side apply (handles large CRDs)
  retry:
    limit: 5          # retry sync up to 5 times on failure
    backoff:
      duration: 5s    # wait 5s before first retry
      factor: 2       # double wait each retry (5s, 10s, 20s, 40s, 80s)
      maxDuration: 3m # never wait more than 3 minutes
```

---

## Part 2 — How Helm Dependency Charts Work

### The Core Concept

> Your Helm chart is a **wrapper** around an upstream chart. You don't copy the upstream chart code — you declare it as a dependency and configure it with your own `values.yaml`.

---

### Structure of a Dependency Chart

Your [`helm/kube-prometheus-stack/Chart.yaml`](../helm/kube-prometheus-stack/Chart.yaml):

```yaml
apiVersion: v2
name: kube-prometheus-stack
dependencies:
  - name: kube-prometheus-stack        # upstream chart name
    version: "57.2.0"                  # exact version to use
    repository: "https://prometheus-community.github.io/helm-charts"
```

Your [`helm/kube-prometheus-stack/values.yaml`](../helm/kube-prometheus-stack/values.yaml):

```yaml
kube-prometheus-stack:       # ← must match dependency name exactly
  grafana:
    enabled: true
    persistence:
      size: 5Gi
  prometheus:
    retention: 15d
```

---

### What Happens When Argo CD Syncs

```text
Argo CD reads helm/kube-prometheus-stack/Chart.yaml
      │
      │ Sees dependency: prometheus-community/kube-prometheus-stack v57.2.0
      ▼
Downloads upstream chart from:
  https://prometheus-community.github.io/helm-charts
      │
      ▼
Merges your values.yaml ON TOP of upstream defaults:
  upstream default: grafana.persistence.size = 1Gi
  your override:    grafana.persistence.size = 5Gi
  result:           grafana.persistence.size = 5Gi
      │
      ▼
Renders all templates (Deployments, Services, ConfigMaps, CRDs)
      │
      ▼
Applies to EKS namespace: monitoring
```

---

### Why Use Dependency Charts?

| Approach | What You Manage |
|----------|----------------|
| **Copy upstream chart** | You copy 500+ files, must update manually, easy to break |
| **Dependency chart** ✅ | You manage 2 files (Chart.yaml + values.yaml), upstream handles complexity |

```text
Your repo:
  helm/kube-prometheus-stack/
    Chart.yaml    (10 lines - declares dependency + version)
    values.yaml   (100 lines - your configuration overrides)

Upstream chart (you don't store this):
  500+ template files
  CRD definitions
  RBAC rules
  ServiceMonitor configs
  Default dashboards
```

---

### Chart.lock — Reproducible Deployments

When Argo CD or you run `helm dependency update`, a `Chart.lock` file is created:

```yaml
# Chart.lock (auto-generated, commit this to Git)
dependencies:
  - name: kube-prometheus-stack
    repository: https://prometheus-community.github.io/helm-charts
    version: 57.2.0    # exact version locked
digest: sha256:abc123  # checksum of the chart
generated: "2024-01-01T00:00:00Z"
```

**Why commit Chart.lock?**
- Guarantees same chart version every deploy
- Prevents "works on my machine" issues
- Argo CD uses this to verify chart integrity

---

### Values Merging — How Overrides Work

```text
Upstream chart default values:
  grafana:
    replicas: 1
    persistence:
      enabled: false
      size: 1Gi
    adminPassword: "prom-operator"

Your values.yaml overrides:
  kube-prometheus-stack:
    grafana:
      persistence:
        enabled: true
        size: 5Gi

Final merged result:
  grafana:
    replicas: 1              ← from upstream (you didn't override)
    persistence:
      enabled: true          ← your override
      size: 5Gi              ← your override
    adminPassword: "prom-operator"  ← from upstream (you didn't override)
```

Only the values you specify are overridden. Everything else uses upstream defaults.

---

## Interview Answers (Summary)

### "How does Argo CD connect to Git?"

> *"Argo CD uses an Application custom resource that defines the Git repository URL, branch, and path to watch. Argo CD's repo-server polls Git every 3 minutes (or via webhook) to detect changes. When a change is detected, it renders the Helm chart templates and compares the output with what's running in the cluster. If there's a difference — called drift — it applies the change. With selfHeal enabled, Argo CD also reverts any manual changes made directly to the cluster, making Git the single source of truth. This means no one runs kubectl manually in production — every change goes through a Git commit."*

---

### "How do Helm dependency charts work?"

> *"A Helm dependency chart is a wrapper around an upstream community chart. Instead of copying hundreds of template files into your repo, you declare the upstream chart as a dependency in Chart.yaml with a specific version. You only maintain a values.yaml with your configuration overrides. When Argo CD syncs, it downloads the upstream chart from the Helm repository, merges your values on top of the upstream defaults, renders all the templates, and applies them to the cluster. This approach means you manage 2 files instead of 500+, and upgrading is as simple as bumping the version number in Chart.yaml."*

---

### "What is GitOps?"

> *"GitOps is an operational model where Git is the single source of truth for both application code and infrastructure configuration. Any change to the system goes through a Git commit and pull request. An automated operator — in our case Argo CD — continuously watches the Git repository and reconciles the cluster state to match what Git says. This gives you: full audit trail via Git history, easy rollback by reverting a commit, consistency between environments, and no manual kubectl commands in production."*
