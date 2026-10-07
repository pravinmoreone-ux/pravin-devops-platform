# Interview Prep — G: Argo CD & GitOps

> **Purpose**: Self-learning and revision document. These are not scripted interview answers — they are explanations to help you understand concepts and remember how they work in practice.

---

## Q1. What is GitOps and how is it different from traditional CI/CD?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the philosophy behind GitOps — not just the tools
- They are testing whether you can explain the source-of-truth model

### 2. Understand the concept
Traditional CI/CD: code is pushed → pipeline runs → pipeline directly deploys to the cluster using `kubectl apply` or `helm upgrade`. The pipeline has credentials to modify the cluster. The cluster state might diverge from what's in Git if someone manually changes something.

GitOps flips this model: the cluster continuously watches Git and pulls the desired state from it. The cluster reconciles itself to match Git. Nobody needs direct write access to the cluster in normal operations.

### 3. The actual answer
Core GitOps principles:
1. **Git is the source of truth**: Everything deployed is described in Git — no undocumented changes
2. **Declarative**: You describe desired state, not imperative steps
3. **Pull model**: The cluster pulls from Git (not pipeline pushing to cluster)
4. **Reconciliation**: Continuous automated process ensures cluster matches Git

Traditional CI/CD vs GitOps:

| | Traditional CI/CD | GitOps |
|--|-------------------|--------|
| Deployment method | Pipeline pushes to cluster | Cluster pulls from Git |
| Cluster credentials | Stored in CI/CD (push model) | Cluster has no outbound credentials |
| Drift detection | Manual | Continuous, automatic |
| Rollback | Re-run old pipeline | `git revert` |
| Audit trail | CI logs | Git history |

In your repo: GitHub Actions builds and pushes the image, then updates `values.yaml` in Git. Argo CD (running inside the cluster) detects the Git change and reconciles the cluster. GitHub Actions never directly touches the cluster.

### 4. Key takeaway
- GitOps = Git as source of truth + cluster continuously reconciles to match Git
- Pull model: cluster watches Git (not pipeline pushing to cluster)
- Drift detected and auto-healed continuously
- Rollback = `git revert` — instant, auditable, no re-running pipelines

---

## Q2. What is Argo CD and what problem does it solve?

### 1. What is this question actually asking?
- The interviewer wants to know if you can explain Argo CD's role clearly
- They are testing whether you understand what it does beyond "it deploys things"

### 2. Understand the concept
Without a GitOps operator, someone has to apply Kubernetes manifests manually or through a CI/CD pipeline. If the cluster drifts from the desired state (manual changes, failed deployments), there's no automatic recovery. Argo CD automates the reconciliation loop — continuously comparing Git with the cluster and fixing differences.

### 3. The actual answer
Argo CD is a GitOps continuous delivery tool for Kubernetes. It:
- Watches one or more Git repositories
- Compares the cluster's current state against the Git-defined desired state
- Automatically applies changes when Git changes (automated sync)
- Reverts manual cluster modifications (self-heal)
- Provides a UI and CLI to visualize and manage deployments

In your repo, Argo CD manages 5 applications:
- `springboot` — Spring Boot app
- `kube-prometheus-stack` — Prometheus + Grafana
- `loki` — log aggregation
- `tempo` — distributed tracing
- `opentelemetry-collector` — telemetry pipeline

Argo CD is installed via Terraform (`terraform/argocd.tf`) using the Helm provider — so even Argo CD's installation is automated and tracked in Git.

### 4. Key takeaway
- Argo CD = GitOps operator that continuously reconciles cluster with Git
- Runs INSIDE the cluster — no external credentials needed to reach the cluster
- Manages multiple applications, each pointing to a different Git path/chart
- Provides UI (port-forward `argocd-server` on 8080) for visualization

---

## Q3. What is an Argo CD Application resource?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the core Argo CD custom resource
- They are checking whether you can explain each field in your Application YAML

### 2. Understand the concept
An Argo CD Application is a Kubernetes Custom Resource (CRD) that tells Argo CD: "Watch this Git repo path and deploy it to this namespace in this cluster." It's the configuration that connects Git → cluster.

### 3. The actual answer
Your `argocd/springboot-application.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application             # Argo CD CRD
metadata:
  name: springboot            # Name shown in Argo CD UI
  namespace: argocd           # Must be in argocd namespace
  finalizers:
    - resources-finalizer.argocd.argoproj.io  # Delete app resources when Application deleted

spec:
  project: default            # Argo CD project (RBAC grouping)

  source:
    repoURL: https://github.com/pravinmoreone-ux/pravin-devops-platform.git
    targetRevision: main      # Branch/tag/commit to watch
    path: helm/springboot     # Directory in repo to use

  destination:
    server: https://kubernetes.default.svc   # This cluster (in-cluster)
    namespace: default        # Deploy to this namespace

  syncPolicy:
    automated:
      prune: true             # Delete resources removed from Git
      selfHeal: true          # Revert manual cluster changes
    syncOptions:
      - CreateNamespace=true  # Create namespace if it doesn't exist
      - ServerSideApply=true  # Use server-side apply
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

Key fields:
| Field | Purpose |
|-------|---------|
| `source.path` | Directory in repo to watch |
| `targetRevision` | Branch/tag — `main` = always latest |
| `destination.namespace` | Where to deploy |
| `automated.prune` | Remove K8s resources when deleted from Git |
| `automated.selfHeal` | Revert manual cluster changes |
| `finalizers` | When Application CRD is deleted, delete all managed K8s resources too |

### 4. Key takeaway
- Application CRD = the connection between Git path and Kubernetes namespace
- Must live in `argocd` namespace
- `prune: true` = GitOps cleanup (removed resources don't linger)
- `selfHeal: true` = Git is enforced as source of truth (manual changes reverted)

---

## Q4. What is the difference between Argo CD sync states: OutOfSync, Synced, and Unknown?

### 1. What is this question actually asking?
- The interviewer wants to know if you can read and interpret the Argo CD application states
- They are checking your operational awareness

### 2. Understand the concept
Argo CD constantly compares the desired state (Git) with the actual state (cluster). The sync status tells you whether they match.

### 3. The actual answer

| Sync Status | Meaning |
|------------|---------|
| **Synced** | Cluster matches Git — desired state achieved |
| **OutOfSync** | Cluster differs from Git — needs reconciliation |
| **Unknown** | Argo CD can't determine sync status (often a connectivity/permission issue) |

Health Status (separate from sync):
| Health Status | Meaning |
|--------------|---------|
| **Healthy** | All resources are working correctly |
| **Progressing** | Resources are being created/updated |
| **Degraded** | Something is wrong (pod crashed, deployment failed) |
| **Suspended** | Application sync is paused |
| **Missing** | Expected resources don't exist in cluster |

An application can be:
- `Synced + Healthy` = everything is good ✅
- `Synced + Degraded` = in sync with Git, but the app itself is unhealthy (crash loop)
- `OutOfSync + Healthy` = cluster runs old version but it's working (needs sync)
- `OutOfSync + Degraded` = bad state — sync and fix needed

### 4. Practical commands / examples

Command:
```bash
kubectl get applications -n argocd
```
Purpose: Lists all Applications with sync and health status.
What to look for: `SYNC STATUS: Synced` and `HEALTH STATUS: Healthy`.

Command:
```bash
kubectl describe application springboot -n argocd
```
Purpose: Detailed view — shows last sync time, error messages, resource list.

### 5. Key takeaway
- Sync status = does cluster match Git?
- Health status = is the deployed application working?
- Both can differ — you can be Synced but Degraded (app crashed but in sync with Git)
- Healthy + Synced = target state for all production applications

---

## Q5. What does `prune: true` do in Argo CD and why is it important?

### 1. What is this question actually asking?
- The interviewer is testing whether you understand what happens to orphaned resources
- They want to know if you've thought about the full GitOps lifecycle

### 2. Understand the concept
If you remove a Kubernetes resource from your Helm chart (e.g., delete a Service you no longer need), Argo CD without pruning would NOT delete it from the cluster. The resource would remain orphaned — running but not managed. Over time, this leads to cluster clutter and potential conflicts.

### 3. The actual answer
With `prune: true`:
- Argo CD detects resources in the cluster that are no longer in Git
- During sync, it DELETES those orphaned resources

Without `prune: true`:
- Removed resources stay in the cluster forever
- Cluster accumulates "ghost" resources from old deployments
- Security risk: orphaned Services, Secrets, RBAC rules still exist

Scenario:
```text
Before: helm/springboot/templates/ has deployment.yaml + service.yaml
        Both deployed to cluster

You delete: templates/service.yaml (no longer needed)
Commit + push

Argo CD syncs:
  prune: false → service still runs in cluster (not deleted)
  prune: true  → service deleted from cluster ✅
```

> **Caution**: `prune: true` with `allowEmpty: false` (your config) prevents accidentally deleting everything if the chart renders empty (safety net).

### 4. Key takeaway
- `prune: true` = resources removed from Git are deleted from cluster
- Without pruning, old resources linger = cluster drift accumulates
- `allowEmpty: false` = safety net — prevents pruning everything if chart renders nothing
- In GitOps: removal from Git = removal from cluster — clean and predictable

---

## Q6. What does `selfHeal: true` do and what is it protecting against?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of drift correction
- They want to know specifically what `selfHeal` reverts

### 2. Understand the concept
Even with automated sync, someone could manually run `kubectl edit deployment/springboot` and change the replica count. Without self-healing, this change would persist until the next Git commit triggers a sync. With self-healing, Argo CD detects the drift and reverts the manual change immediately — making Git the enforced source of truth.

### 3. The actual answer
`selfHeal: true` means Argo CD:
- Continuously compares live cluster state with Git (not just on Git changes)
- If any difference is detected (even without a new Git commit), syncs immediately
- Effectively: manual `kubectl edit/patch/delete` changes are reverted within ~3 minutes

What it protects against:
- Accidental manual changes (`kubectl scale --replicas=0` by mistake)
- Configuration drift over time
- Emergency changes that weren't reverted after the emergency
- Security bypasses (someone manually adding privileges)

What `selfHeal` does NOT do:
- Protect against crashes/restarts (that's pod restart policy)
- Protect against node failures (that's Kubernetes scheduling)
- Prevent the change — it just reverts it after detecting it

### 4. Key takeaway
- `selfHeal: true` = continuous drift correction, not just on Git push
- Reverts manual cluster changes back to Git state within minutes
- Makes Git the enforced source of truth — not just a recommendation
- Critical for compliance: ensures what's running always matches what's reviewed

---

## Q7. How does Argo CD detect changes in Git?

### 1. What is this question actually asking?
- The interviewer wants to know the mechanics of Git polling and webhooks in Argo CD
- They are checking if you know how quickly changes are detected

### 2. Understand the concept
Argo CD doesn't sit and watch every Git push in real-time. By default, it polls the Git repository on a schedule. For faster response, you can configure a webhook from GitHub to notify Argo CD immediately when a push happens.

### 3. The actual answer
Two mechanisms:

**1. Polling (default):**
- Argo CD polls Git repositories every 3 minutes
- Fetches latest commit, compares with last known state
- If changed → triggers reconciliation
- Maximum lag: 3 minutes from Git push to sync start

**2. Webhooks (faster):**
- GitHub sends an HTTP POST to Argo CD on every push
- Argo CD immediately checks for changes
- Lag: seconds (not minutes)
- Requires: Argo CD webhook endpoint accessible from GitHub (or GitHub Actions notifies)

In your repo, polling is the default (no webhook configured). For production, setting up a webhook from GitHub is recommended so Helm values changes from CI are picked up immediately.

How to trigger manual sync:
```bash
# Force immediate sync
argocd app sync springboot

# Or via kubectl
kubectl patch application springboot -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

### 4. Key takeaway
- Default: Argo CD polls Git every 3 minutes
- Webhooks = immediate detection (GitHub → Argo CD HTTP notification)
- Manual sync: `argocd app sync <name>` or Argo CD UI → Sync button
- For your pipeline: 3-minute poll lag after Helm values commit is acceptable for dev

---

## Q8. What is an Argo CD project and why do you use `default`?

### 1. What is this question actually asking?
- The interviewer is testing deeper Argo CD knowledge
- They want to know if you understand Argo CD's RBAC model

### 2. Understand the concept
An Argo CD project (AppProject) groups applications and applies RBAC policies to them — which Git repos are allowed as sources, which clusters/namespaces are allowed as destinations, and which Kubernetes resources can be deployed. The `default` project allows everything.

### 3. The actual answer
The `default` project has no restrictions:
- Any Git repository can be used as a source
- Any namespace can be used as a destination
- All Kubernetes resource types allowed

Custom projects restrict these:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
spec:
  sourceRepos:
    - "https://github.com/pravinmoreone-ux/pravin-devops-platform.git"
  destinations:
    - namespace: "default"
      server: "https://kubernetes.default.svc"
  clusterResourceWhitelist:
    - group: "apps"
      kind: "Deployment"
```

For a single-team, single-cluster setup (your repo), `default` is appropriate. For enterprise setups with multiple teams sharing a cluster, custom projects enforce isolation.

### 4. Key takeaway
- Argo CD project = RBAC container for applications
- `default` project = unrestricted (fine for single-team learning)
- Custom projects restrict: source repos, destination namespaces, allowed resource types
- Production multi-tenant clusters should use custom projects per team

---

## Q9. What is the Argo CD app of apps pattern?

### 1. What is this question actually asking?
- The interviewer is testing advanced GitOps knowledge
- They want to know if you understand how to bootstrap an entire cluster from Git

### 2. Understand the concept
In your repo, you apply Argo CD Application YAMLs using `kubectl_manifest` resources in Terraform. An alternative approach is the "app of apps" pattern — one Argo CD Application manages a directory of other Argo CD Application YAMLs. This way, even the Application definitions are managed by Argo CD itself.

### 3. The actual answer
App of apps structure:
```text
argocd/
├── root-app.yaml          ← "app of apps" — Argo CD watches this directory
├── springboot-application.yaml
├── kube-prometheus-stack-application.yaml
├── loki-application.yaml
├── tempo-application.yaml
└── opentelemetry-collector-application.yaml
```

Root application:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
spec:
  source:
    path: argocd/           # watch the argocd/ directory
  destination:
    namespace: argocd       # apply Application CRDs here
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

When Argo CD syncs `root-app`, it applies all the other Application YAMLs — creating those applications. Each child application then manages its own namespace.

**Your current approach**: Terraform applies Application YAMLs via `kubectl_manifest` — simpler, works well for your setup.

**App of apps**: Fully self-managed — once Argo CD is running and `root-app` is created, it bootstraps everything else from Git. No Terraform needed for application management.

### 4. Key takeaway
- App of apps = one Argo CD Application manages other Application definitions
- Fully GitOps — even Application CRDs are tracked in Git
- Add a new app by adding its YAML to the `argocd/` directory — no manual `kubectl apply`
- Your repo uses Terraform for Application creation — simpler for a learning platform

---

## Q10. What is Argo CD's reconciliation loop?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how Argo CD continuously operates
- They are testing your understanding of the controller pattern

### 2. Understand the concept
Argo CD runs a control loop — a continuous process that checks "what should be running" vs "what is running" and corrects any difference. This is the same pattern Kubernetes itself uses internally (Kubernetes controllers also run reconciliation loops).

### 3. The actual answer
Argo CD's reconciliation loop:

```text
┌─────────────────────────────────────────────────────┐
│                    Every ~3 minutes                  │
│                (or immediately on webhook)           │
│                                                      │
│  1. Fetch latest commit from Git repo               │
│        │                                             │
│  2. Render Helm chart with values.yaml              │
│     → produces desired Kubernetes manifests          │
│        │                                             │
│  3. Query live cluster state                        │
│     → what's actually deployed now                   │
│        │                                             │
│  4. Diff: desired vs actual                         │
│     → list of differences                            │
│        │                                             │
│  5. If differences found AND sync policy is          │
│     automated:                                       │
│     → Apply diff (create/update/delete resources)   │
│        │                                             │
│  6. Report status: Synced/OutOfSync, Healthy/Degraded│
└─────────────────────────────────────────────────────┘
```

This loop runs continuously for all managed applications simultaneously.

### 4. Key takeaway
- Reconciliation loop = continuous comparison and correction
- Runs every ~3 minutes (or on webhook/manual trigger)
- Same pattern as Kubernetes controllers — declarative + continuous
- App health status updated after each reconciliation cycle

---

## Q11. What is Argo CD Image Updater and how does it differ from your current approach?

### 1. What is this question actually asking?
- The interviewer is testing your awareness of alternative GitOps image update patterns
- They want to see if you know the trade-offs between different approaches

### 2. Understand the concept
In your current setup, the CI pipeline updates `values.yaml` with the new image tag and commits to Git. Argo CD Image Updater is an alternative — it watches a container registry for new image tags and automatically updates the Argo CD Application (and optionally commits to Git) without needing CI to do it.

### 3. The actual answer

| Approach | Your current | Argo CD Image Updater |
|----------|-------------|----------------------|
| Who updates image tag | CI pipeline (GitHub Actions) | Argo CD Image Updater |
| Updates Git? | Yes (commits to repo) | Optional (write-back to Git) |
| Requires CI changes? | No | No |
| Tag strategy | Any (SHA, semver) | Regex/semver matching |
| Complexity | Simple | Requires Image Updater installation |

Your approach is simpler and more transparent — Git always shows the exact tag deployed. Image Updater is useful when:
- You don't control the CI pipeline
- Images come from third-party registries
- You want automatic updates to latest patch versions

For your platform, the current approach (CI commits tag → Argo CD syncs) is the recommended GitOps pattern.

### 4. Key takeaway
- Your approach: CI commits new image tag to Git → Argo CD syncs
- Image Updater: watches registry for new tags → updates Argo CD application
- Your approach = more transparent, Git always shows what's deployed
- Image Updater = useful for third-party images or when CI doesn't update Git

---

## Q12. How do you roll back with Argo CD?

### 1. What is this question actually asking?
- The interviewer wants to know your rollback strategy in a GitOps environment
- They are checking if you understand why `helm rollback` doesn't work with Argo CD

### 2. Understand the concept
In traditional deployments, you rollback by running a command against the cluster. In GitOps, the cluster state is driven by Git — so rolling back means reverting the Git commit that caused the problem.

### 3. The actual answer
Two approaches:

**Option 1 — Git revert (preferred):**
```bash
# Revert the last commit (the bad image tag update)
git revert HEAD
git push origin main

# Argo CD detects the revert commit
# Syncs the old image tag back to the cluster
# Kubernetes performs rolling update back to old pods
```

**Option 2 — Argo CD rollback to previous sync:**
```bash
# Using argocd CLI
argocd app rollback springboot

# This reverts to the previous sync, even without a Git revert
# BUT: Argo CD will re-sync to latest Git on next cycle
# So you must also fix Git to prevent re-applying the bad commit
```

**Option 3 — Directly update values.yaml:**
```bash
# Change tag back to working version
# Edit helm/springboot/values.yaml
# Change: tag: "sha-bad123" → tag: "sha-good456"
git commit -m "Rollback Spring Boot to sha-good456"
git push
# Argo CD syncs the old tag
```

Git revert is cleanest — it creates an audit trail showing a rollback happened, and Git stays as source of truth.

### 4. Key takeaway
- GitOps rollback = `git revert` (or update tag in values.yaml) → Argo CD syncs
- `argocd app rollback` works but Argo CD will re-sync to Git shortly after
- `helm rollback` does NOT work — Argo CD doesn't use Helm release tracking
- Git revert = cleanest rollback with full audit trail

---

## Q13. What is `ServerSideApply` in Argo CD and why do you use it?

### 1. What is this question actually asking?
- The interviewer is testing your knowledge of advanced Kubernetes apply modes
- They want to know why you chose server-side apply over client-side apply

### 2. Understand the concept
Kubernetes `kubectl apply` has two modes: client-side apply (the traditional way) and server-side apply (newer). With large or complex resources (like Prometheus CRDs), client-side apply can have conflicts or fail to track field ownership correctly. Server-side apply solves these issues.

### 3. The actual answer
In your Application YAMLs:
```yaml
syncOptions:
  - ServerSideApply=true
```

| | Client-Side Apply | Server-Side Apply |
|--|------------------|------------------|
| Who tracks field ownership | kubectl (stored in annotation) | Kubernetes API server |
| Large resources | Can hit annotation size limits | Handles large resources correctly |
| Conflicts | Last-write-wins | Explicit ownership model |
| CRD management | Can fail on large CRDs | Required for CRDs (kube-prometheus-stack) |

For kube-prometheus-stack, Server-Side Apply is required because Prometheus CRDs are very large — they exceed kubectl's annotation size limit with client-side apply.

### 4. Key takeaway
- ServerSideApply = Kubernetes API server tracks field ownership
- Required for large CRDs (Prometheus, cert-manager, etc.)
- Prevents annotation size limit issues with complex charts
- Recommended for all Argo CD applications in modern clusters

---

## Q14. What is the Argo CD UI and what can you do with it?

### 1. What is this question actually asking?
- The interviewer wants to know if you've used the Argo CD interface operationally
- They are checking your hands-on familiarity

### 2. Understand the concept
The Argo CD web UI provides a visual representation of all your applications, their sync status, health status, and the Kubernetes resources they manage. It lets you trigger syncs, view diffs, inspect logs, and manage applications without using the CLI.

### 3. The actual answer
Access the UI:
```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Open: http://localhost:8080
# Username: admin
# Password: kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
```

What you can do in the UI:
| Action | How |
|--------|-----|
| View all apps and status | Main dashboard |
| See resource tree | Click app → tree view of all K8s resources |
| View diff (OutOfSync) | Click app → Diff tab |
| Trigger manual sync | Click Sync button |
| View sync history | Click History tab |
| Rollback | History → Click revision → Rollback |
| View pod logs | Resource tree → Pod → Logs |
| Delete application | App → Delete |
| Disable auto-sync | App → Disable Auto-Sync |

The resource tree is especially useful — it shows the hierarchical relationship of all Kubernetes resources (Deployment → ReplicaSet → Pods) with health indicators.

### 4. Key takeaway
- UI accessible via port-forward on `argocd-server` service
- Resource tree = visual view of all managed Kubernetes resources
- Diff view = see exactly what would change before syncing
- History = view all past syncs with timestamps and Git commits

---

## Q15. What is an Argo CD sync wave and why would you use it?

### 1. What is this question actually asking?
- The interviewer is testing advanced Argo CD knowledge about deployment ordering
- They want to know how you control the order resources are created

### 2. Understand the concept
When Argo CD syncs an application with many resources, some resources must be created before others. A database must exist before the application starts. A namespace must exist before you deploy into it. Sync waves control the order — lower wave numbers deploy first.

### 3. The actual answer
Sync waves are set via annotations:

```yaml
# Create namespace first (wave -1)
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  annotations:
    argocd.argoproj.io/sync-wave: "-1"

---
# Then create the Deployment (wave 0, default)
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

---
# Finally run a smoke test (wave 1)
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

Default wave = 0. Resources in the same wave deploy in parallel. Argo CD waits for all resources in wave N to be healthy before starting wave N+1.

Your repo uses `CreateNamespace=true` sync option instead of explicitly managing namespaces — simpler for your use case.

### 4. Key takeaway
- Sync waves = control deployment order across resources
- Lower number = deployed first (negative numbers before 0)
- Same wave = deployed in parallel
- Use for: namespace before workload, CRDs before CRs, database before application

---

## Q16. How does Argo CD handle secrets — and what's the limitation?

### 1. What is this question actually asking?
- The interviewer is testing your awareness of the GitOps secrets challenge
- This is a common pain point they want to see if you've thought about

### 2. Understand the concept
GitOps requires everything to be in Git. But you can't put Kubernetes Secrets in Git in plain text — they'd be readable by anyone with repo access (and history can't be deleted). This creates a fundamental tension: GitOps wants everything in Git, but secrets shouldn't be in Git.

### 3. The actual answer
Argo CD itself does not encrypt or manage secrets. It applies whatever YAML is in Git. The community has developed several solutions:

**Option 1 — Sealed Secrets (Bitnami)**:
- Encrypts Secret values with a cluster-specific key
- Encrypted `SealedSecret` YAML is safe to commit to Git
- Controller in cluster decrypts it back to a regular K8s Secret

**Option 2 — External Secrets Operator**:
- `ExternalSecret` CRD in Git references secrets stored in AWS Secrets Manager/Parameter Store
- Operator fetches the real value from AWS and creates a K8s Secret
- Git only contains the reference (not the value)

**Option 3 — Argo CD Vault Plugin (AVP)**:
- Argo CD uses a plugin to replace placeholder values with secrets from HashiCorp Vault
- YAML in Git has `<path:secret/data/myapp#password>` placeholders

**Option 4 — SOPS** (Simple and Secure):
- Encrypts YAML/JSON files with KMS/PGP keys
- Encrypted files are committed to Git
- Decrypted at sync time by Argo CD with SOPS plugin

For your repo, Grafana's admin password is currently empty in `values.yaml` — the production approach would use External Secrets with AWS Secrets Manager.

### 4. Key takeaway
- Argo CD has no built-in secret management — it applies whatever is in Git
- Never commit plain Kubernetes Secrets to Git
- Common solutions: Sealed Secrets, External Secrets Operator, SOPS, Vault
- External Secrets + AWS Secrets Manager = recommended for your AWS-based platform

---

## Q17. What is `argocd app diff` and when do you use it?

### 1. What is this question actually asking?
- The interviewer is checking your operational debugging workflow with Argo CD
- They want to know how you investigate OutOfSync applications

### 2. Understand the concept
When an application is OutOfSync, you want to see exactly what's different — what Argo CD wants to apply — before triggering a sync. `argocd app diff` shows this diff like a `git diff` but between Git's desired state and the live cluster.

### 3. The actual answer
```bash
# Show diff for springboot application
argocd app diff springboot

# Example output:
# === apps/Deployment springboot/springboot-springboot ===
# 15c15
# <         image: ghcr.io/.../springboot:sha-old123
# ---
# >         image: ghcr.io/.../springboot:sha-new456
```

Use cases:
- Before syncing: "What exactly will change?"
- Debugging OutOfSync: "Why is this showing as changed?"
- Validating no-op: "This should show no diff after my change"

In the Argo CD UI, the same information is in the application's "Diff" tab — shows a side-by-side comparison of desired vs live state.

### 4. Practical commands / examples

Command:
```bash
argocd app diff springboot --local helm/springboot
```
Purpose: Compare local chart (not yet committed) against live cluster — useful for testing changes before committing.

### 5. Key takeaway
- `argocd app diff` = shows exactly what Argo CD will change on next sync
- Available in UI (Diff tab) and CLI
- Use before syncing to verify the expected change
- `--local` flag = diff against local files (not yet in Git) — useful for testing

---

## Q18. What is the difference between Argo CD and Flux?

### 1. What is this question actually asking?
- The interviewer is testing your awareness of the GitOps landscape
- They want to know if you understand the alternatives and trade-offs

### 2. Understand the concept
Argo CD and Flux are both GitOps tools for Kubernetes — they do similar things. Knowing the differences shows you've thought beyond just "using the tool" to understanding the ecosystem.

### 3. The actual answer

| | Argo CD | Flux |
|--|---------|------|
| Architecture | Single controller with web UI | Multiple specialized controllers |
| UI | Rich built-in web UI | No built-in UI (use Weave GitOps) |
| Multi-cluster | Yes (built-in) | Yes (built-in) |
| Helm support | Native | Native (HelmRelease CRD) |
| Kustomize support | Native | Native |
| Secret management | Plugin-based | SOPS built-in |
| CNCF graduated | Yes | Yes |
| Learning curve | Moderate (UI helps) | Steeper (no UI) |
| Notification system | Built-in | Built-in |

Both are CNCF graduated projects and production-ready. Argo CD is more popular for its UI and multi-cluster support. Flux is preferred in setups that want pure CRD-based configuration without a UI.

For your platform, Argo CD is the right choice — the UI makes it easier to visualize and learn.

### 4. Key takeaway
- Argo CD = rich UI, established, widely used, good for learning and visualization
- Flux = CRD-driven, no built-in UI, built-in SOPS, preferred in some enterprise setups
- Both are production-grade CNCF graduated projects
- For your platform: Argo CD is the better learning choice due to its UI

---

## Q19. What does `CreateNamespace=true` do in Argo CD sync options?

### 1. What is this question actually asking?
- Small but important detail question about your Application configuration
- The interviewer is checking if you understand all the sync options you've set

### 2. Understand the concept
By default, if an Argo CD Application is configured to deploy to a namespace that doesn't exist, the sync fails. `CreateNamespace=true` tells Argo CD to create the namespace automatically before deploying.

### 3. The actual answer
In your observability Applications:
```yaml
syncOptions:
  - CreateNamespace=true
```

Without this: `namespace: monitoring` must already exist → manual `kubectl create namespace monitoring` required before first sync.

With this: Argo CD creates `monitoring` namespace on first sync → fully automated, no manual steps.

This is what allows `terraform apply` to be a single command that:
1. Creates EKS
2. Installs Argo CD
3. Applies Application YAMLs
4. Argo CD creates all namespaces and deploys everything

No manual namespace creation needed.

One consideration: if you delete the Argo CD Application, with `finalizers` set, Argo CD deletes the namespace and all resources in it. Ensure PersistentVolumeClaims (Prometheus, Loki data) are backed up before deleting applications in production.

### 4. Key takeaway
- `CreateNamespace=true` = Argo CD creates namespace if it doesn't exist
- Enables fully automated deployment from `terraform apply` → all apps running
- Without it: namespaces must exist before first sync
- Useful for fresh cluster bootstrap — no manual prerequisites

---

## Q20. How do you know what resources Argo CD is managing for an application?

### 1. What is this question actually asking?
- Practical operational question
- The interviewer wants to see if you can inspect deployed resources

### 2. Understand the concept
When Argo CD deploys a Helm chart, it creates many Kubernetes resources — Deployments, Services, ConfigMaps, CRDs, RBAC, etc. You need to be able to list and inspect all of these to understand what's running and debug issues.

### 3. The actual answer
Multiple ways to see managed resources:

**Argo CD UI:**
- Click on the application → resource tree view
- Shows all resources with health indicators (green ✅, yellow ⚠️, red ❌)
- Hierarchical: Application → Deployment → ReplicaSet → Pods

**CLI:**
```bash
# List all resources managed by the application
argocd app resources springboot

# Get detailed resource tree
argocd app resource-tree springboot
```

**kubectl (look for Argo CD labels):**
```bash
# Resources created by Argo CD have this label
kubectl get all -n default -l "app.kubernetes.io/managed-by=Helm"

# Or find by Argo CD tracking label
kubectl get all -n default -l "argocd.argoproj.io/app-name=springboot"
```

**Argo CD resource health:**
```bash
argocd app get springboot
# Shows: sync status, health, list of resources with status
```

### 4. Practical commands / examples

Command:
```bash
argocd app get springboot
```
Purpose: Full status of an application — sync, health, resource list.
What to look for: Resource list at bottom showing each K8s object and its health.

### 5. Key takeaway
- UI resource tree = best visual overview of all managed resources
- `argocd app get` = CLI equivalent with resource list
- Resources labeled with `app.kubernetes.io/managed-by=Helm` via Helm
- Use this when debugging: "Is this resource managed by Argo CD or manual?"

---

## Q21. What is Argo CD's finalizer and what happens when you delete an Application?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of Application lifecycle and cleanup
- They want to know if you understand the risk of deleting an Application

### 2. Understand the concept
Normally, deleting a Kubernetes custom resource (like an Argo CD Application) only deletes that resource — it doesn't delete what it created. Without a finalizer, deleting an Argo CD Application would leave all the Kubernetes resources it deployed orphaned in the cluster.

### 3. The actual answer
In your Application YAMLs:
```yaml
metadata:
  finalizers:
    - resources-finalizer.argocd.argoproj.io
```

With this finalizer:
1. You delete the Application CRD
2. Argo CD's controller intercepts the deletion
3. First deletes ALL managed Kubernetes resources (Deployment, Service, PVC, etc.)
4. Then allows the Application CRD itself to be deleted

Without this finalizer:
1. Application CRD is deleted immediately
2. All managed K8s resources stay in the cluster as orphans
3. Namespace and its contents remain

> **Warning**: Deleting an Application with finalizer in production deletes everything managed by it — including PersistentVolumeClaims (Prometheus data, Loki data, Grafana dashboards). This data is gone. Always back up before deleting Applications managing stateful workloads.

To delete Application without deleting managed resources:
```bash
# Remove finalizer first, then delete
kubectl patch application springboot -n argocd \
  --type json \
  -p '[{"op":"remove","path":"/metadata/finalizers"}]'

kubectl delete application springboot -n argocd
```

### 4. Key takeaway
- Finalizer = cleanup hook — Argo CD deletes all managed resources before removing Application
- Without finalizer: orphaned K8s resources remain after Application deletion
- With finalizer: deleting Application = deleting all deployed resources (cascading delete)
- Production: always remove finalizer before deleting Applications with stateful storage
