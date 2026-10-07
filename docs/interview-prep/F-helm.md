# Interview Prep — F: Helm

> **Purpose**: Self-learning and revision document. These are not scripted interview answers — they are explanations to help you understand concepts and remember how they work in practice.

---

## Q1. What is Helm and what problem does it solve?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand why Helm exists — not just what it is
- They are testing whether you understand the complexity of managing raw Kubernetes YAML

### 2. Understand the concept
Deploying an application to Kubernetes requires many YAML files: Deployment, Service, ConfigMap, Secret, NetworkPolicy, PodDisruptionBudget, HorizontalPodAutoscaler, etc. For one environment this is manageable. But if you need dev, staging, and production environments — each with slightly different values (replica count, image tag, resource limits) — you'd need to maintain separate YAML files for each, or use complex `sed` commands to change values. Helm packages all these files together and lets you change values through a single `values.yaml` file.

### 3. The actual answer
Helm is a package manager for Kubernetes. It bundles Kubernetes manifests into a **chart** — a collection of templates and default values. You install a chart with custom values and Helm renders the templates and applies them to Kubernetes.

Key problems Helm solves:
- **Templating**: Reuse the same manifests across environments with different values
- **Packaging**: All related Kubernetes resources in one unit
- **Versioning**: Charts are versioned — rollback to previous version with one command
- **Dependency management**: Charts can declare dependencies on other charts
- **Release management**: Track what's deployed, when, with what values

### 4. Practical commands / examples

Command:
```bash
helm install springboot helm/springboot -n default
```
Purpose: Installs the Spring Boot chart as a release named "springboot" in the default namespace.

Command:
```bash
helm upgrade springboot helm/springboot -n default
```
Purpose: Upgrades an existing release with new chart version or values.

Command:
```bash
helm list -n default
```
Purpose: Lists all Helm releases in the default namespace.
What to look for: Release name, chart version, status (deployed/failed), last deployed time.

### 5. Key takeaway
- Helm = package manager for Kubernetes (like apt for Ubuntu or npm for Node.js)
- Chart = package of Kubernetes manifests + templates + default values
- Release = an installed instance of a chart
- Solves: templating, versioning, rollback, dependency management

---

## Q2. What is the structure of a Helm chart?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand what files go in a chart and why
- They are checking your hands-on familiarity with Helm chart anatomy

### 2. Understand the concept
A Helm chart is a directory with a specific structure. Knowing this structure helps you read, write, and debug charts confidently.

### 3. The actual answer
Your `helm/springboot/` chart structure:
```text
helm/springboot/
├── Chart.yaml          # Chart metadata (name, version, description)
├── values.yaml         # Default values (overridable at install/upgrade)
└── templates/
    ├── deployment.yaml     # Kubernetes Deployment template
    ├── service.yaml        # Kubernetes Service template
    ├── networkpolicy.yaml  # NetworkPolicy template
    └── pdb.yaml            # PodDisruptionBudget template
```

| File/Directory | Purpose |
|----------------|---------|
| `Chart.yaml` | Metadata: chart name, version, description, type, dependencies |
| `values.yaml` | Default values referenced in templates via `{{ .Values.xxx }}` |
| `templates/` | Kubernetes YAML templates with Go template syntax |
| `templates/NOTES.txt` | (optional) Post-install instructions printed to user |
| `charts/` | (optional) Downloaded dependency charts stored here |
| `Chart.lock` | (optional) Locked versions of dependencies |

### 4. Practical commands / examples

Command:
```bash
helm template springboot helm/springboot
```
Purpose: Renders all templates locally without installing — shows the final Kubernetes YAML.
What to look for: The rendered YAML for Deployment, Service, NetworkPolicy, PDB.

Command:
```bash
helm lint helm/springboot
```
Purpose: Validates chart syntax and structure.
What to look for: `1 chart(s) linted, 0 chart(s) failed` = all good.

### 5. Key takeaway
- `Chart.yaml` = metadata, `values.yaml` = defaults, `templates/` = Kubernetes manifests
- `helm template` = render without installing — essential for debugging
- `helm lint` = validate chart structure — runs in your Helm CI workflow
- Templates use Go template syntax: `{{ .Values.xxx }}`, `{{ .Release.Name }}`

---

## Q3. What is `Chart.yaml` and what does each field mean?

### 1. What is this question actually asking?
- The interviewer is checking if you can explain the chart metadata file
- They want to know the difference between `version` and `appVersion`

### 2. Understand the concept
`Chart.yaml` is the identity card of your chart. It tells Helm what the chart is called, what version it is, what application it packages, and optionally what other charts it depends on.

### 3. The actual answer
Your `helm/springboot/Chart.yaml`:
```yaml
apiVersion: v2          # Helm 3 charts use v2
name: springboot        # Chart name — used in release names
description: Helm chart for the DevOps Platform Spring Boot application
type: application       # application (deployed) vs library (shared helpers)
version: 0.1.0          # Chart version — increment when chart changes
appVersion: "0.0.1"     # Version of the packaged application (informational)
```

Important distinction:
- `version` = the Helm chart version — increment when you change the chart templates
- `appVersion` = the application version — informational, Helm doesn't use it for logic

For dependency charts (`helm/kube-prometheus-stack/Chart.yaml`):
```yaml
dependencies:
  - name: kube-prometheus-stack
    version: "57.2.0"
    repository: "https://prometheus-community.github.io/helm-charts"
```

This declares the upstream chart as a dependency — Helm downloads it when you run `helm dependency update`.

### 4. Key takeaway
- `version` = chart version (semantic versioning) — change when chart templates change
- `appVersion` = application version — informational, used in labels/annotations
- `dependencies` = upstream charts this chart wraps
- `type: application` = deployable chart (vs `library` = shared templates only)

---

## Q4. What is `values.yaml` and how does template rendering work?

### 1. What is this question actually asking?
- The interviewer wants to know the relationship between `values.yaml` and templates
- They are testing whether you understand Go template syntax in Helm

### 2. Understand the concept
`values.yaml` stores the default configuration for your chart. Templates reference values using `{{ .Values.xxx }}`. When Helm renders the chart, it substitutes these references with the actual values — producing plain Kubernetes YAML.

### 3. The actual answer
Your `helm/springboot/values.yaml`:
```yaml
replicaCount: 2

image:
  repository: ghcr.io/pravinmoreone-ux/pravin-devops-platform/springboot
  tag: "sha-9bb2f6e5117a5197fdb6b233e0634e6ddbaec444"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 8080

containerPort: 8080
```

Referenced in `templates/deployment.yaml`:
```yaml
spec:
  replicas: {{ .Values.replicaCount }}          # → 2
  template:
    spec:
      containers:
        - image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          # → ghcr.io/.../springboot:sha-xxx
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.containerPort }}  # → 8080
```

**Built-in objects** available in templates:
| Object | Example | Value |
|--------|---------|-------|
| `.Values` | `{{ .Values.replicaCount }}` | From values.yaml |
| `.Release.Name` | `{{ .Release.Name }}` | Release name (e.g., "springboot") |
| `.Release.Namespace` | `{{ .Release.Namespace }}` | Namespace (e.g., "default") |
| `.Chart.Name` | `{{ .Chart.Name }}` | Chart name |
| `.Chart.Version` | `{{ .Chart.Version }}` | Chart version |

### 4. Practical commands / examples

Command:
```bash
helm template springboot helm/springboot --set image.tag=sha-newvalue
```
Purpose: Render templates with a specific override — without installing.
What to look for: Verify the new tag appears in the Deployment YAML.

Command:
```bash
helm install springboot helm/springboot --set replicaCount=3
```
Purpose: Override a value at install time without changing values.yaml.

### 5. Key takeaway
- `values.yaml` = defaults, referenced via `{{ .Values.xxx }}` in templates
- `.Release.Name` etc. = built-in Helm objects available in every template
- Values are merged: `values.yaml` defaults < `--values file` < `--set` flags
- `helm template --set` = test overrides without installing

---

## Q5. What is the difference between `helm install` and `helm upgrade`?

### 1. What is this question actually asking?
- Simple but important operational question
- The interviewer wants to know if you understand how Helm manages the lifecycle of a release

### 2. Understand the concept
`install` creates a new release. `upgrade` updates an existing one. If you run `install` on an already-installed chart, it fails. If you run `upgrade` on a chart that doesn't exist, it fails. `upgrade --install` handles both cases — the safest option for automation.

### 3. The actual answer

| Command | Behavior | Fails if |
|---------|---------|---------|
| `helm install` | Creates new release | Release already exists |
| `helm upgrade` | Updates existing release | Release doesn't exist |
| `helm upgrade --install` | Creates or updates | Never (idempotent) |

In CI/CD and GitOps, always use `upgrade --install`:
```bash
helm upgrade --install springboot helm/springboot \
  -n default \
  --create-namespace \
  --wait \
  --timeout 5m
```

`--wait` = Helm waits until all pods are Ready before marking upgrade as successful.
`--timeout` = fail if not ready within this time.

In your repo, Argo CD handles this automatically — it uses `helm upgrade --install` under the hood when syncing.

### 4. Key takeaway
- `install` = first time only
- `upgrade` = update existing (fails if not installed)
- `upgrade --install` = idempotent — always use this in automation/CI
- `--wait` = Helm waits for pods to be ready — use for reliable deployments

---

## Q6. What is a Helm release and how do you manage its lifecycle?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand Helm's release tracking mechanism
- They are testing whether you know how Helm remembers what's deployed

### 2. Understand the concept
A Helm release is a named, tracked installation of a chart. Helm stores release information (including all rendered Kubernetes manifests and values used) as a Kubernetes Secret in the namespace. This is how Helm knows what version is deployed, what values were used, and how to roll back.

### 3. The actual answer
Helm stores release history as Kubernetes Secrets:
```bash
kubectl get secrets -n default | grep helm
# sh.helm.release.v1.springboot.v1
# sh.helm.release.v1.springboot.v2
```

Each upgrade creates a new versioned secret. Helm keeps up to 10 revisions by default.

Lifecycle commands:
```bash
# Install
helm install springboot helm/springboot -n default

# Check status
helm status springboot -n default

# Upgrade (new values or chart)
helm upgrade springboot helm/springboot -n default

# View history
helm history springboot -n default

# Rollback to revision 1
helm rollback springboot 1 -n default

# Uninstall (removes all K8s resources + release secrets)
helm uninstall springboot -n default
```

### 4. Practical commands / examples

Command:
```bash
helm history springboot -n default
```
Purpose: Shows all revisions of the release with chart version, status, and description.
What to look for: `STATUS: deployed` on the latest revision, `STATUS: superseded` on older ones.

Command:
```bash
helm rollback springboot 1 -n default
```
Purpose: Rolls back to revision 1 — restores the Kubernetes resources from that revision.

> **Warning**: `helm uninstall` deletes ALL Kubernetes resources that were created by the chart — Deployments, Services, PVCs, etc. For stateful apps, this can cause data loss.

### 5. Key takeaway
- Helm release = named tracked installation stored as K8s Secrets
- Each upgrade = new revision stored in history
- `helm rollback <name> <revision>` = instant rollback to any previous state
- `helm uninstall` = removes all chart resources — careful with stateful apps

---

## Q7. What is the difference between `helm template` and `helm install --dry-run`?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the two ways to preview rendered output
- They are checking if you know the subtle but important difference

### 2. Understand the concept
Both commands render templates without actually applying resources. The difference is whether Helm communicates with the Kubernetes cluster during rendering.

### 3. The actual answer

| | `helm template` | `helm install --dry-run` |
|--|----------------|------------------------|
| Connects to K8s? | No | Yes |
| Server validation? | No | Yes (validates against API server) |
| Requires kubeconfig? | No | Yes |
| Use case | Offline rendering, CI checks | Pre-deploy validation |
| Fails on invalid K8s API? | No | Yes |

```bash
# Works without cluster access
helm template springboot helm/springboot

# Validates against live cluster (needs kubectl context)
helm install springboot helm/springboot --dry-run
```

`helm template` is what your Helm CI workflow uses:
```yaml
- name: Helm template
  run: helm template springboot helm/springboot
```

It runs without needing AWS credentials or a real EKS cluster — pure offline validation.

### 4. Key takeaway
- `helm template` = offline rendering, no K8s needed — use in CI
- `helm install --dry-run` = server-side validation, needs live cluster
- Both show rendered YAML without applying
- Your CI uses `helm template` (no cluster needed in CI) + `helm lint` (syntax check)

---

## Q8. How do you pass values to a Helm chart and what is the order of precedence?

### 1. What is this question actually asking?
- The interviewer wants to know all the ways to supply values to Helm
- They are checking if you understand which value wins when multiple sources conflict

### 2. Understand the concept
When Helm renders a chart, it merges values from multiple sources. If the same key appears in multiple sources, the higher-priority source wins.

### 3. The actual answer
Priority order (lowest to highest):

| Priority | Source | Example |
|----------|--------|---------|
| 1 (lowest) | `values.yaml` in chart | `replicaCount: 2` |
| 2 | Parent chart's `values.yaml` | For dependency charts |
| 3 | `-f` or `--values` flag | `helm install -f prod-values.yaml` |
| 4 (highest) | `--set` flag | `helm install --set replicaCount=5` |

```bash
# values.yaml has replicaCount: 2
# prod-values.yaml has replicaCount: 3
# --set has replicaCount: 5

helm install springboot helm/springboot \
  -f prod-values.yaml \
  --set replicaCount=5
# Result: replicaCount = 5 (--set wins)
```

In your repo, Argo CD passes values via:
```yaml
source:
  helm:
    valueFiles:
      - values.yaml   # equivalent to -f values.yaml
```

For dependency charts (`kube-prometheus-stack`), values are namespaced:
```yaml
# values.yaml for wrapper chart
kube-prometheus-stack:    # ← must match dependency name
  grafana:
    enabled: true
```

### 4. Key takeaway
- Priority: `values.yaml` < `-f file` < `--set`
- `--set` always wins — use for quick overrides, not permanent config
- For dependency charts, values must be nested under the dependency name
- Argo CD passes `valueFiles` — equivalent to `-f values.yaml`

---

## Q9. What is a Helm hook and when would you use one?

### 1. What is this question actually asking?
- The interviewer is testing deeper Helm knowledge
- They want to know if you can run tasks at specific points in the release lifecycle

### 2. Understand the concept
Sometimes you need to run a task at a specific point during a Helm operation — for example, run a database migration before upgrading the application, or send a Slack notification after a successful deploy. Helm hooks let you run Kubernetes Jobs or Pods at defined lifecycle points.

### 3. The actual answer
Hooks are defined with a special annotation in a template:

```yaml
# templates/db-migration.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    "helm.sh/hook": pre-upgrade          # run before upgrade
    "helm.sh/hook-weight": "-5"          # order (lower = earlier)
    "helm.sh/hook-delete-policy": hook-succeeded  # delete job after success
spec:
  template:
    spec:
      containers:
        - name: migrate
          image: myapp:latest
          command: ["./migrate.sh"]
```

Common hook events:
| Hook | When it runs |
|------|-------------|
| `pre-install` | Before resources are created on install |
| `post-install` | After all resources are created on install |
| `pre-upgrade` | Before upgrade (database migrations) |
| `post-upgrade` | After upgrade |
| `pre-delete` | Before uninstall |
| `post-delete` | After uninstall |

Your repo doesn't use hooks currently. They'd be needed if Spring Boot required database schema migrations before each deployment.

### 4. Key takeaway
- Hooks = run K8s Jobs at specific Helm lifecycle events
- Common use: database migrations (`pre-upgrade`), smoke tests (`post-install`)
- `hook-delete-policy: hook-succeeded` = clean up job after success
- Hook weights control order when multiple hooks run at same event

---

## Q10. What is `helm lint` and what does it check?

### 1. What is this question actually asking?
- Simple question about chart validation
- The interviewer is checking if you understand the Helm CI quality gate

### 2. Understand the concept
`helm lint` examines a chart for common errors — missing required fields, invalid YAML, template syntax errors, and Helm best practice violations. It's the first quality gate in your Helm CI workflow.

### 3. The actual answer
`helm lint` checks:
- `Chart.yaml` has required fields (name, version, apiVersion)
- Template files are valid YAML after rendering with default values
- Go template syntax is valid (`{{ .Values.xxx }}` references exist)
- Best practices (e.g., chart has at least one template)
- Kubernetes manifest structure is reasonable

In your Helm CI workflow:
```yaml
- name: Helm lint
  run: helm lint helm/springboot
```

Output levels:
- `[INFO]` = informational
- `[WARNING]` = potential issue, not a failure
- `[ERROR]` = failure — lint exits with code 1

After lint, `helm template` renders the full output — a second check that templates produce valid YAML.

### 4. Practical commands / examples

Command:
```bash
helm lint helm/springboot --strict
```
Purpose: Treat warnings as errors — stricter validation.
What to look for: `1 chart(s) linted, 0 chart(s) failed`

Command:
```bash
helm lint helm/springboot --set image.tag=sha-test
```
Purpose: Lint with a specific value override — useful to test non-default paths.

### 5. Key takeaway
- `helm lint` = validates chart structure and template syntax
- `helm template` = renders full output — validates template logic
- Both run in your Helm CI workflow for every change to `helm/**`
- `--strict` = treat warnings as errors (more rigorous CI)

---

## Q11. What is a Helm dependency and how does it work in your observability charts?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how your observability charts work
- They are testing whether you know the difference between wrapping an upstream chart vs copying it

### 2. Understand the concept
Your `helm/kube-prometheus-stack/` directory is very small — just `Chart.yaml` and `values.yaml`. It doesn't contain any Kubernetes YAML templates. That's because it's a wrapper chart — it declares the upstream `kube-prometheus-stack` chart as a dependency and provides your custom configuration values.

### 3. The actual answer
Dependency workflow:

**Step 1** — Declare in `Chart.yaml`:
```yaml
dependencies:
  - name: kube-prometheus-stack
    version: "57.2.0"
    repository: "https://prometheus-community.github.io/helm-charts"
```

**Step 2** — Download dependency:
```bash
helm dependency update helm/kube-prometheus-stack
# Downloads chart to helm/kube-prometheus-stack/charts/
# Creates Chart.lock with exact version + checksum
```

**Step 3** — Configure via `values.yaml`:
```yaml
# Your values.yaml (wrapper level)
kube-prometheus-stack:         # must match dependency name
  grafana:
    persistence:
      size: 5Gi               # override upstream default of 1Gi
```

**Step 4** — Argo CD syncs:
- Reads `Chart.yaml` + `Chart.lock`
- Downloads dependency from Helm repo
- Merges your values on top of upstream defaults
- Renders all templates
- Applies to EKS

Why this approach:
- You don't manage 500+ upstream template files
- Upgrading Prometheus: change `version: "57.2.0"` → `version: "58.0.0"` in `Chart.yaml`
- Only your 2 files change — clean Git diff

### 4. Practical commands / examples

Command:
```bash
helm dependency update helm/kube-prometheus-stack
```
Purpose: Downloads dependency charts into `charts/` directory and creates `Chart.lock`.
What to look for: `charts/kube-prometheus-stack-57.2.0.tgz` created.

Command:
```bash
helm dependency list helm/kube-prometheus-stack
```
Purpose: Shows dependency status.
What to look for: `ok` status means dependency is available locally.

### 5. Key takeaway
- Dependency chart = wrapper pattern — declare + configure upstream chart
- `helm dependency update` = downloads upstream chart into `charts/` directory
- `Chart.lock` = locks exact version + checksum — commit to Git for reproducibility
- Values namespaced under dependency name: `kube-prometheus-stack: grafana: ...`

---

## Q12. What is the `Release.Name` built-in and how does it appear in your chart?

### 1. What is this question actually asking?
- The interviewer is checking if you understand Helm built-in objects
- They want to know how Helm avoids naming conflicts between releases

### 2. Understand the concept
If you install the same chart twice in the same namespace (e.g., two Spring Boot apps), their Kubernetes resources would have the same names and conflict. `Release.Name` is automatically injected by Helm — using it in resource names makes them unique per release.

### 3. The actual answer
In your `helm/springboot/templates/deployment.yaml`:
```yaml
metadata:
  name: {{ .Release.Name }}-springboot
```

When installed as release `springboot`:
- `{{ .Release.Name }}` = `springboot`
- Resource name = `springboot-springboot`

Available Release built-ins:
| Object | Value |
|--------|-------|
| `{{ .Release.Name }}` | Release name (e.g., "springboot") |
| `{{ .Release.Namespace }}` | Namespace (e.g., "default") |
| `{{ .Release.IsInstall }}` | `true` on first install |
| `{{ .Release.IsUpgrade }}` | `true` on upgrade |
| `{{ .Release.Revision }}` | Revision number (1, 2, 3...) |

### 4. Practical commands / examples

Command:
```bash
helm install myapp helm/springboot -n default
```
Result: Creates resource named `myapp-springboot` (Release.Name = "myapp")

Command:
```bash
helm install otherapp helm/springboot -n default
```
Result: Creates resource named `otherapp-springboot` — no conflict with "myapp-springboot"

### 5. Key takeaway
- `{{ .Release.Name }}` = name used when installing the chart
- Using it in resource names prevents conflicts when same chart installed multiple times
- Also used in labels and selectors for resource grouping
- In your Argo CD Application: `releaseName: springboot` sets the Release.Name

---

## Q13. What is `helm rollback` and when would you use it?

### 1. What is this question actually asking?
- The interviewer wants to know how you recover from a bad deployment using Helm
- They are testing your rollback strategy knowledge

### 2. Understand the concept
After a failed upgrade — new pods crashing, health checks failing, application errors — you need to quickly revert to the last known good state. Helm stores the history of all previous releases and can restore any of them with one command.

### 3. The actual answer
```bash
# See release history
helm history springboot -n default
# REVISION  STATUS     CHART              APP VERSION  DESCRIPTION
# 1         superseded springboot-0.1.0   0.0.1        Install complete
# 2         deployed   springboot-0.1.0   0.0.1        Upgrade complete

# Rollback to revision 1
helm rollback springboot 1 -n default
```

What happens during rollback:
1. Helm retrieves the Kubernetes manifests from revision 1 (stored in the secret)
2. Applies them to the cluster — effectively an upgrade to the old version
3. Kubernetes performs a rolling update back to the old pods
4. Old pods (revision 1) come up, new pods (revision 2) go down

**In your GitOps setup**, Helm rollback is less common — you'd instead:
1. `git revert` the bad commit in `values.yaml` (or change the image tag back)
2. Push to main
3. Argo CD syncs the old values back

This is preferred because Git history remains the source of truth.

### 4. Practical commands / examples

Command:
```bash
helm rollback springboot 0 -n default
```
Purpose: `0` = rollback to previous revision (one step back).

Command:
```bash
helm rollback springboot 1 --wait -n default
```
Purpose: Rollback and wait for pods to be Ready before returning.

### 5. Key takeaway
- `helm rollback <release> <revision>` = restore previous release state
- Helm stores complete manifest history — can rollback to any revision
- In GitOps: prefer `git revert` + push → Argo CD reconciles (keeps Git as source of truth)
- `helm rollback` is useful for emergency situations outside GitOps flow

---

## Q14. What are Helm named templates (helpers) and when would you use them?

### 1. What is this question actually asking?
- The interviewer is testing advanced Helm knowledge
- They want to know if you understand how to avoid repeating YAML blocks

### 2. Understand the concept
If you have the same labels applied to every Kubernetes resource in your chart (common labels like `app.kubernetes.io/name`, `app.kubernetes.io/version`), you'd normally copy-paste them into every template. Named templates (defined in `_helpers.tpl`) let you define this once and call it anywhere.

### 3. The actual answer
Named templates are defined in `templates/_helpers.tpl` (the leading underscore means Helm won't render it as a Kubernetes manifest):

```yaml
# templates/_helpers.tpl
{{- define "springboot.labels" -}}
app.kubernetes.io/name: springboot
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

Used in any template:
```yaml
# templates/deployment.yaml
metadata:
  labels:
    {{- include "springboot.labels" . | indent 4 }}
```

`include` calls the named template and passes `.` (current context) so it has access to `.Values`, `.Release`, etc.

Your current charts don't use `_helpers.tpl` — the labels are hardcoded (`app: springboot`). For production charts with many resources, helpers are standard.

### 4. Key takeaway
- Named templates = DRY for repeated YAML blocks (labels, selectors, annotations)
- Defined in `templates/_helpers.tpl` (underscore = not rendered as K8s manifest)
- Called with `{{ include "name" . }}` — `.` passes the current Helm context
- Standard practice: define common labels once in helpers, include in all templates

---

## Q15. What is `helm get values` and when is it useful for debugging?

### 1. What is this question actually asking?
- The interviewer wants to know if you know how to inspect deployed Helm releases
- They are checking your debugging workflow

### 2. Understand the concept
After deploying with Helm, you might want to verify: "What values did Helm use for this release?" Maybe someone did `helm upgrade --set replicaCount=5` and you want to see all the current effective values without looking at every file.

### 3. The actual answer
```bash
# Show user-supplied values for current release
helm get values springboot -n default

# Show all values (user + defaults merged)
helm get values springboot -n default --all

# Show values for specific revision
helm get values springboot -n default --revision 1
```

Other useful `helm get` commands:
```bash
# Show rendered Kubernetes manifests for current release
helm get manifest springboot -n default

# Show all info (values + manifest + hooks)
helm get all springboot -n default

# Show release notes (NOTES.txt output)
helm get notes springboot -n default
```

**Debugging scenario**: Pod has wrong image tag. Check what Helm used:
```bash
helm get values springboot -n default --all | grep tag
# image.tag: sha-old123

# Check what's in values.yaml
cat helm/springboot/values.yaml | grep tag
# tag: "sha-new456"

# Conclusion: Helm release wasn't updated with new values
# Fix: helm upgrade springboot helm/springboot -n default
```

### 4. Key takeaway
- `helm get values` = shows values used in deployed release
- `--all` flag = includes chart defaults, not just user overrides
- `helm get manifest` = shows rendered Kubernetes YAML for current release
- Essential for debugging "why is this not what I expected"

---

## Q16. What is the difference between `helm uninstall` and `kubectl delete`?

### 1. What is this question actually asking?
- The interviewer is testing if you understand Helm's tracking vs manual deletion
- They want to know what happens to Helm's release history when you delete resources manually

### 2. Understand the concept
Helm tracks all resources it creates. If you delete a Kubernetes resource with `kubectl delete`, Helm doesn't know about it — the resource is still in Helm's stored state. The next time Argo CD or Helm syncs, it will recreate the deleted resource.

### 3. The actual answer

| | `helm uninstall` | `kubectl delete` |
|--|-----------------|-----------------|
| Removes K8s resources | Yes | Yes |
| Removes Helm release history | Yes | No |
| Helm knows it's gone | Yes | No |
| Effect in GitOps | Clean removal | Argo CD recreates it on next sync |

In GitOps with Argo CD (`prune: true`), the correct way to remove a resource:
1. Remove it from the Helm chart templates
2. Commit + push
3. Argo CD detects it's no longer in Git
4. Argo CD prunes (deletes) it from the cluster

Do NOT `kubectl delete` resources managed by Argo CD — they'll be recreated immediately.

`helm uninstall` is used to remove an entire release — all resources + Helm history. Only use when you want to completely stop managing an application with Helm.

### 4. Key takeaway
- `helm uninstall` = clean removal (K8s resources + Helm history)
- `kubectl delete` = only removes K8s resource — Helm/Argo CD will recreate it
- In GitOps: remove from chart → commit → Argo CD prunes automatically
- Never `kubectl delete` resources managed by Argo CD — it fights back

---

## Q17. How does Argo CD use Helm under the hood?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the integration between Argo CD and Helm
- They are checking whether you understand what Argo CD actually does when it syncs a Helm Application

### 2. Understand the concept
Argo CD supports Helm natively. When you point an Argo CD Application at a Helm chart directory, Argo CD runs Helm commands to render the templates and then applies the resulting Kubernetes manifests. It doesn't use `helm install/upgrade` — it uses Helm as a template engine only.

### 3. The actual answer
When Argo CD syncs a Helm Application:

```text
1. Argo CD repo-server clones the Git repo
       │
       ▼
2. Reads Application spec:
   path: helm/springboot
   helm:
     releaseName: springboot
     valueFiles: [values.yaml]
       │
       ▼
3. Runs: helm template springboot helm/springboot -f values.yaml
   (equivalent — renders all templates to Kubernetes YAML)
       │
       ▼
4. Compares rendered YAML with live cluster state
       │
       ▼
5. Applies diff using kubectl apply (or server-side apply)
       │
       ▼
6. Kubernetes resources updated
```

**Important**: Argo CD does NOT create a Helm release secret. Resources are tracked by Argo CD, not Helm. So `helm list` will NOT show Argo CD-managed releases. `helm rollback` won't work — use Argo CD UI or `git revert` instead.

This is by design — Argo CD is the release manager, not Helm.

### 4. Key takeaway
- Argo CD uses Helm as a template engine (renders YAML), not as a deployment tool
- `helm list` won't show Argo CD-managed releases — Argo CD manages them directly
- `helm rollback` won't work — use Argo CD sync to previous Git commit instead
- `ServerSideApply=true` in your sync options = uses server-side apply for better conflict handling

---

## Q18. What happens if you run `helm upgrade` on a chart managed by Argo CD?

### 1. What is this question actually asking?
- The interviewer is testing if you understand the conflict between manual Helm and GitOps
- They want to see if you know what Argo CD does when it detects drift

### 2. Understand the concept
Argo CD continuously reconciles the cluster with Git. If you manually run `helm upgrade` to change something, Argo CD will detect the drift and revert the change on the next sync — effectively undoing your manual change.

### 3. The actual answer
What happens:
```text
1. Argo CD manages springboot release
       │
2. You run: helm upgrade springboot helm/springboot --set replicaCount=5
       │
3. Cluster now has 5 replicas
       │
4. Git still has replicaCount: 2 in values.yaml
       │
5. Argo CD syncs (within 3 minutes or on next push)
       │
6. Argo CD detects: cluster (5 replicas) ≠ Git (2 replicas)
       │
7. Argo CD applies Git state → reverts to 2 replicas
```

This is exactly the behavior you WANT in GitOps — Git is the source of truth, all changes must go through Git.

**Correct way to change replica count in GitOps**:
1. Edit `helm/springboot/values.yaml`: `replicaCount: 5`
2. `git commit -m "Scale Spring Boot to 5 replicas"`
3. `git push`
4. Argo CD syncs → 5 replicas

### 4. Key takeaway
- Manual `helm upgrade` on Argo CD-managed releases = changes reverted on next sync
- All changes must go through Git — not direct cluster modifications
- This is a feature, not a bug — ensures Git is always the source of truth
- Argo CD `selfHeal: true` = actively reverts manual changes immediately

---

## Q19. What is a Helm values override file and how would you use it for multiple environments?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand environment-specific Helm configuration
- They are checking if you know how to manage dev vs prod differences

### 2. Understand the concept
Your `values.yaml` has defaults. For production, you might want more replicas, higher resource limits, and a different image tag. Instead of changing the defaults, you create environment-specific override files.

### 3. The actual answer
Structure for multiple environments:
```text
helm/springboot/
├── Chart.yaml
├── values.yaml              # defaults (dev)
├── values-staging.yaml      # staging overrides
└── values-prod.yaml         # production overrides
```

```yaml
# values-prod.yaml
replicaCount: 5

resources:
  requests:
    cpu: "500m"
    memory: "512Mi"
  limits:
    cpu: "2000m"
    memory: "1Gi"
```

Deploy to production:
```bash
helm upgrade --install springboot helm/springboot \
  -f values.yaml \
  -f values-prod.yaml    # overrides prod values on top
```

In Argo CD Application for production:
```yaml
source:
  helm:
    valueFiles:
      - values.yaml
      - values-prod.yaml
```

Your current repo has a single `values.yaml` — suitable for a single environment. Adding `values-prod.yaml` is the pattern for multi-environment GitOps.

### 4. Key takeaway
- Multiple value files layered: base `values.yaml` + environment-specific override
- `-f prod-values.yaml` overrides on top of defaults
- Argo CD supports multiple `valueFiles` in the Application spec
- Keep environment-specific files minimal — only override what differs from defaults

---

## Q20. What is `helm test` and how would you add a smoke test to your chart?

### 1. What is this question actually asking?
- The interviewer is testing your knowledge of post-deploy validation
- They want to know if you can verify a deployment worked correctly

### 2. Understand the concept
After a Helm deployment, you want to verify the application is actually working — not just that pods are running. `helm test` runs a Kubernetes Job (or Pod) defined in the chart with the `helm.sh/hook: test` annotation. The job runs a quick smoke test and returns pass or fail.

### 3. The actual answer
Add a test to your Spring Boot chart:

```yaml
# templates/tests/test-hello.yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ .Release.Name }}-test-hello"
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  containers:
    - name: curl
      image: curlimages/curl:latest
      command:
        - curl
        - -f
        - "http://{{ .Release.Name }}-springboot:{{ .Values.service.port }}/actuator/health"
  restartPolicy: Never
```

Run the test:
```bash
helm test springboot -n default
```

The curl command hits `/actuator/health`. If it returns HTTP 200, the test passes. If not, Helm reports test failure.

In CI/CD, you'd run this after `helm upgrade` to verify the deployment succeeded.

### 4. Key takeaway
- `helm test` = runs post-deploy smoke tests defined in chart
- Test pods have `helm.sh/hook: test` annotation
- `hook-delete-policy: hook-succeeded` = clean up after passing test
- Useful in CI/CD as a deployment verification step after `helm upgrade`

---

## Q21. What is the `helm show` command and how do you inspect an upstream chart before using it?

### 1. What is this question actually asking?
- The interviewer is checking if you know how to explore upstream charts before using them
- They want to see if you understand how to find configurable values in dependency charts

### 2. Understand the concept
When you add a dependency chart (like kube-prometheus-stack), you need to know what values it supports so you can configure it correctly. You can't just guess — you need to see the upstream chart's defaults and documentation.

### 3. The actual answer
```bash
# Add the repo first
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Show chart information (description, version, readme)
helm show chart prometheus-community/kube-prometheus-stack

# Show ALL default values (what you can override)
helm show values prometheus-community/kube-prometheus-stack

# Show README (usage documentation)
helm show readme prometheus-community/kube-prometheus-stack

# Pipe to file for reference
helm show values prometheus-community/kube-prometheus-stack > upstream-defaults.yaml
```

Workflow when adding a new dependency:
1. `helm show values <chart>` → understand what values are available
2. Copy only the values you want to override into your `values.yaml`
3. Test with `helm template`
4. Commit and deploy

`helm show values` for `kube-prometheus-stack` outputs thousands of lines — you only need to include the values you're changing from defaults. Everything else uses upstream defaults automatically.

### 4. Key takeaway
- `helm show values` = see all configurable values for an upstream chart
- Only override what you need — upstream defaults handle the rest
- `helm show chart` = metadata, `helm show readme` = documentation
- Essential first step before writing your `values.yaml` for a dependency chart
