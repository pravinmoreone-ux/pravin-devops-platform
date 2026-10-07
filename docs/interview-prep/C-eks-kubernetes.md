# Interview Prep — C: EKS & Kubernetes

> **Purpose**: Self-learning and revision document. These are not scripted interview answers — they are explanations to help you understand concepts and remember how they work in practice.

---

## Q1. What is Kubernetes and why do we use it instead of just running containers on EC2?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the problem Kubernetes solves
- They are testing whether you can explain the "why" — not just recite what Kubernetes is

### 2. Understand the concept
Imagine you have 5 Docker containers running on an EC2 instance. If the instance crashes, your containers die. If you need to handle more traffic, you manually spin up more instances. If a container crashes, nothing restarts it. You have to manually figure out which instance has space for a new container.

Kubernetes automates all of this. It watches your containers, restarts failed ones, spreads them across multiple machines, scales them up/down, and rolls out updates without downtime.

### 3. The actual answer
Kubernetes is a container orchestration platform. You tell it what you want (e.g., "run 2 copies of this Spring Boot container") and it figures out how to make that happen and keeps it that way.

Key things Kubernetes handles automatically:
- **Self-healing**: Restarts crashed containers
- **Scaling**: Add/remove replicas based on load
- **Scheduling**: Decides which node to place each container on
- **Rolling updates**: Updates containers one by one with zero downtime
- **Service discovery**: Containers find each other by name, not IP
- **Load balancing**: Distributes traffic across multiple container replicas

Running on plain EC2 you handle all of this manually — Kubernetes automates it.

### 4. Key takeaway
- Kubernetes = automated container management at scale
- Self-heals, scales, schedules, and updates containers automatically
- You describe *what* you want (desired state), Kubernetes figures out *how* to achieve it
- EKS = AWS-managed Kubernetes (AWS runs the control plane, you run worker nodes)

---

## Q2. What is the difference between a Pod, a Deployment, and a ReplicaSet?

### 1. What is this question actually asking?
- The interviewer is testing if you understand the hierarchy of Kubernetes workload objects
- They want to know which object you interact with and which ones Kubernetes manages internally

### 2. Understand the concept
Think of it in layers. A Pod is the actual running container. A ReplicaSet ensures a certain number of Pods are always running. A Deployment manages ReplicaSets and handles rolling updates. You normally interact with Deployments — not Pods or ReplicaSets directly.

### 3. The actual answer

| Object | What it is | Who creates it |
|--------|-----------|----------------|
| **Pod** | One or more containers running together, sharing network and storage | ReplicaSet (or you directly for debugging) |
| **ReplicaSet** | Ensures N copies of a Pod are always running | Deployment |
| **Deployment** | Manages ReplicaSets, handles rolling updates and rollbacks | You (kubectl apply or Helm) |

When you update a Deployment (e.g., new image tag):
1. Deployment creates a new ReplicaSet with the new spec
2. New ReplicaSet gradually scales up (new pods)
3. Old ReplicaSet gradually scales down (old pods)
4. If something goes wrong, you roll back — Deployment switches back to old ReplicaSet

In your repo, `helm/springboot/templates/deployment.yaml` defines the Deployment for Spring Boot.

### 4. Practical commands / examples

Command:
```bash
kubectl get deployments -n default
```
Purpose: Shows all Deployments and their desired/ready/available replica counts.
What to look for: `READY 2/2` = both replicas running.

Command:
```bash
kubectl rollout history deployment/springboot-springboot
```
Purpose: Shows history of Deployment rollouts.
What to look for: Revision numbers with change causes.

Command:
```bash
kubectl rollout undo deployment/springboot-springboot
```
Purpose: Rolls back to previous Deployment revision.

### 5. Key takeaway
- Pod = running container(s) — the actual unit of execution
- ReplicaSet = ensures desired number of Pods exist — Kubernetes managed
- Deployment = rolling updates, rollbacks, version history — what you manage
- You almost never create Pods directly — always use Deployments

---

## Q3. What is a Kubernetes Service and why do Pods need it?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how traffic reaches Pods
- They are testing whether you understand why you can't just use Pod IPs directly

### 2. Understand the concept
Every Pod gets its own IP address. But Pods are temporary — they get killed and replaced frequently (deployments, restarts, scaling). When a new Pod starts, it gets a new IP. If you hardcoded the old IP anywhere, your traffic goes nowhere.

A Service gives you a stable IP and DNS name that always routes to the correct pods — even as pods come and go.

### 3. The actual answer
A Kubernetes Service is a stable network endpoint that load-balances traffic across matching Pods. It uses a **selector** to find pods by label.

Three common types:

| Type | Accessible From | Use Case |
|------|----------------|----------|
| **ClusterIP** | Inside the cluster only | Internal communication between services |
| **NodePort** | Outside cluster via node IP:port | Dev/testing (not production) |
| **LoadBalancer** | Internet via cloud load balancer | Production internet-facing services |

In your repo, `helm/springboot/templates/service.yaml` creates a `ClusterIP` service — accessible only inside EKS. To expose it externally, you'd add an Ingress with an ALB.

### 4. Practical commands / examples

Command:
```bash
kubectl get services -n default
```
Purpose: Lists all Services, their type, cluster IP, and ports.
What to look for: `ClusterIP` with a stable IP — this doesn't change even when pods restart.

Command:
```bash
kubectl port-forward svc/springboot-springboot 8080:8080
```
Purpose: Temporarily forwards local port 8080 to the Kubernetes service — for local testing without an ingress.

### 5. Key takeaway
- Service = stable network endpoint in front of ephemeral Pods
- Uses label selectors to find pods — automatically updates as pods come and go
- ClusterIP = internal only, LoadBalancer = internet-facing
- DNS: `<service-name>.<namespace>.svc.cluster.local` resolves to the Service ClusterIP

---

## Q4. What is a Namespace in Kubernetes and why do you use multiple namespaces?

### 1. What is this question actually asking?
- The interviewer is checking if you understand resource isolation and organisation in Kubernetes
- They want to know if you can explain when and why to separate namespaces

### 2. Understand the concept
A namespace is a logical partition inside a Kubernetes cluster. Resources in one namespace are isolated from resources in another. It is like folders in a filesystem — the files exist in the same system, but are organized and can have different permissions.

### 3. The actual answer
Namespaces provide:
- **Organisation**: Group related resources (e.g., `monitoring` for Prometheus/Grafana)
- **Isolation**: RBAC and NetworkPolicy can be scoped per namespace
- **Resource quotas**: Limit CPU/memory per namespace
- **Avoiding name collisions**: Two teams can have a `springboot` Service in different namespaces

In your repo:
| Namespace | Contents |
|-----------|---------|
| `default` | Spring Boot application |
| `argocd` | Argo CD |
| `monitoring` | Prometheus, Grafana, Alertmanager |
| `logging` | Loki, Promtail |
| `tracing` | Tempo |
| `observability` | OpenTelemetry Collector |

Argo CD creates namespaces automatically via `CreateNamespace=true` in sync options.

### 4. Practical commands / examples

Command:
```bash
kubectl get pods --all-namespaces
```
Purpose: Shows all pods across all namespaces.
What to look for: Check pods in monitoring, logging, tracing are Running.

Command:
```bash
kubectl get all -n monitoring
```
Purpose: Shows all resources in the monitoring namespace.

### 5. Key takeaway
- Namespace = logical partition for organising cluster resources
- Resources in different namespaces can still communicate (unless NetworkPolicy blocks them)
- RBAC, resource quotas, and NetworkPolicy are scoped per namespace
- `default` namespace is fine for learning — use dedicated namespaces in production

---

## Q5. What is Amazon EKS and what does AWS manage vs what do you manage?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the managed vs self-managed boundary in EKS
- They are checking whether you know what you're responsible for when using EKS

### 2. Understand the concept
Running Kubernetes yourself means managing the control plane (API server, etcd, scheduler, controller manager) — which is complex, requires HA setup, and needs ongoing updates. EKS offloads this to AWS. You focus on worker nodes and applications.

### 3. The actual answer

| AWS Manages (EKS Control Plane) | You Manage |
|---------------------------------|-----------|
| Kubernetes API server | Worker nodes (EC2 instances) |
| etcd (cluster state database) | Node OS patching |
| Controller Manager | Kubernetes workloads (Deployments, Services, etc.) |
| Scheduler | RBAC and access control |
| Control plane HA (multi-AZ) | Cluster add-ons (CoreDNS, VPC CNI, kube-proxy) |
| Control plane upgrades (you initiate) | Pod security, resource limits |
| Control plane logging to CloudWatch | Storage (EBS volumes, EFS) |

In your repo, the EKS cluster is private-only (`endpoint_public_access = false`). You access it through the jump server using `kubectl` after running `aws eks update-kubeconfig`.

### 4. Key takeaway
- EKS = AWS manages the control plane, you manage worker nodes and workloads
- Control plane is multi-AZ automatically — highly available
- You still need to patch/update worker nodes (managed node groups can do rolling updates)
- Private endpoint = EKS API not exposed to internet — must access via jump server or VPN

---

## Q6. What is a managed node group in EKS?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the different ways to run worker nodes in EKS
- They are checking if you know the operational benefits of managed node groups

### 2. Understand the concept
EKS worker nodes are EC2 instances that run your pods. You can manage these yourself (self-managed nodes) or let AWS manage them (managed node groups). With managed node groups, AWS handles provisioning, updating, and replacing nodes.

### 3. The actual answer
A managed node group is a group of EC2 instances that:
- Are automatically provisioned and registered with the EKS cluster
- Use an AWS-managed Auto Scaling Group
- Support automated, rolling node upgrades (AWS drains pods before replacing a node)
- Use EC2 instances managed by AWS — you don't SSH in to configure them

In your repo (`terraform/eks_node_group.tf`):
```hcl
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  instance_types  = ["t3.small"]
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 3
  }
}
```

Scaling up/down changes `desired_size`. Kubernetes cluster autoscaler can do this automatically based on pod resource requests.

### 4. Practical commands / examples

Command:
```bash
kubectl get nodes
```
Purpose: Shows all worker nodes and their status.
What to look for: `Ready` status. `NotReady` means the node has a problem.

Command:
```bash
kubectl describe node <node-name>
```
Purpose: Shows detailed information about a node — allocatable CPU/memory, running pods, conditions.
What to look for: Conditions section, Allocated resources section.

### 5. Key takeaway
- Managed node group = AWS manages EC2 provisioning and rolling updates
- You still choose instance type, size, and scaling config
- Nodes in private subnets — not directly accessible from internet
- For production: use managed node groups + Cluster Autoscaler for automatic scaling

---

## Q7. What is the role of KMS encryption in EKS and what does it encrypt?

### 1. What is this question actually asking?
- The interviewer is testing your security awareness in Kubernetes
- They want to know specifically what gets encrypted and why it matters

### 2. Understand the concept
Kubernetes stores all cluster state in a database called etcd — including Kubernetes Secrets (which hold passwords, tokens, certificates). By default, Secrets are only base64-encoded, not encrypted. Anyone with access to etcd can read all your secrets. KMS encryption adds a real encryption layer on top.

### 3. The actual answer
In your repo (`terraform/eks.tf`):
```hcl
encryption_config {
  provider {
    key_arn = aws_kms_key.eks.arn
  }
  resources = ["secrets"]
}
```

This enables **envelope encryption** for Kubernetes Secrets:
1. Kubernetes generates a data encryption key (DEK)
2. Uses KMS to encrypt the DEK with your CMK (Customer Master Key)
3. Stores the encrypted DEK alongside the encrypted Secret in etcd

Even if someone gets direct access to etcd data, they cannot read Secrets without the KMS key.

Your KMS key also has `enable_key_rotation = true` — AWS automatically rotates the key annually.

### 4. Practical commands / examples

Command:
```bash
kubectl create secret generic db-password --from-literal=password=mysecret
kubectl get secret db-password -o yaml
```
Purpose: Creates a secret and views it — the value will appear base64 encoded in the YAML, but it's encrypted at rest in etcd.

### 5. Key takeaway
- EKS Secrets are encrypted at rest using KMS (envelope encryption)
- Without KMS, Secrets are only base64-encoded in etcd — easily decoded
- KMS key rotation enabled — automatic annual rotation
- Encrypting secrets is a security baseline requirement for production clusters

---

## Q8. What is a Kubernetes ConfigMap and how is it different from a Secret?

### 1. What is this question actually asking?
- Simple comparison question about configuration management in Kubernetes
- The interviewer wants to know if you know when to use each

### 2. Understand the concept
Applications need configuration — database URLs, feature flags, environment names. In Kubernetes, you don't hardcode these in the container image. You store them separately and inject them at runtime.

ConfigMaps store plain, non-sensitive configuration. Secrets store sensitive data like passwords and tokens.

### 3. The actual answer

| | ConfigMap | Secret |
|--|-----------|--------|
| Purpose | Non-sensitive config | Sensitive data (passwords, tokens, certs) |
| Storage | Plain text in etcd | Base64 + encrypted at rest (with KMS) |
| Used for | App config, env vars, config files | DB passwords, API keys, TLS certs |
| Access control | RBAC | RBAC (more restrictive) |

Both can be injected into pods as:
- Environment variables
- Volume mounts (files)

In your repo, Spring Boot's `application.yml` is embedded in the container image. For environment-specific config (like OTel endpoint), you'd use a ConfigMap.

### 4. Practical commands / examples

```yaml
# ConfigMap example
apiVersion: v1
kind: ConfigMap
metadata:
  name: springboot-config
data:
  OTEL_EXPORTER_ENDPOINT: "http://otel-collector:4317"
  LOG_LEVEL: "INFO"
```

Command:
```bash
kubectl get configmap -n default
kubectl describe configmap springboot-config
```

### 5. Key takeaway
- ConfigMap = plain config (non-sensitive)
- Secret = sensitive data (encrypted at rest with KMS in your cluster)
- Never put passwords or API keys in ConfigMaps — they are not encrypted
- Both injected as env vars or volume-mounted files

---

## Q9. What is a Kubernetes Liveness Probe and Readiness Probe?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how Kubernetes monitors pod health
- Common follow-up: "What's the difference between liveness and readiness?"

### 2. Understand the concept
Kubernetes doesn't know whether the application inside a pod is actually working. The container might be running but your Spring Boot app could be in a deadlock. Health probes let Kubernetes ask the application: "Are you alive? Are you ready for traffic?"

### 3. The actual answer

| Probe | Question asked | Failure action |
|-------|---------------|----------------|
| **Liveness** | Is the app alive? Should it be restarted? | Kill and restart the pod |
| **Readiness** | Is the app ready to receive traffic? | Remove pod from Service endpoints (no traffic sent) |
| **Startup** | Has the app finished starting up? | Blocks liveness/readiness until it passes |

In your repo (`helm/springboot/templates/deployment.yaml`):
```yaml
readinessProbe:
  httpGet:
    path: /actuator/health
    port: http
  initialDelaySeconds: 10   # wait 10s before first check
  periodSeconds: 10          # check every 10s

livenessProbe:
  httpGet:
    path: /actuator/health
    port: http
  initialDelaySeconds: 30   # Spring Boot needs ~30s to start
  periodSeconds: 20
```

Spring Boot Actuator's `/actuator/health` returns `{"status":"UP"}` when healthy.

**Key scenario**: During a rolling deployment, new pods are only added to the Service (receive traffic) after readiness probe passes. Old pods keep receiving traffic until the new ones are ready. This ensures zero-downtime deployments.

### 4. Practical commands / examples

Command:
```bash
kubectl describe pod <pod-name> -n default
```
Purpose: Shows probe configuration and recent probe failures.
What to look for: `Liveness: http-get`, `Readiness: http-get`, and any `Unhealthy` events.

### 5. Key takeaway
- Liveness probe = "should this pod be restarted?" — failure = pod restart
- Readiness probe = "should this pod receive traffic?" — failure = removed from load balancer
- Always set `initialDelaySeconds` to give your app time to start before probing
- Spring Boot Actuator `/actuator/health` is the standard probe endpoint

---

## Q10. What is a Kubernetes SecurityContext and what security controls does it provide?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand container-level security hardening in Kubernetes
- They are checking whether you applied security consciously — not just copied YAML

### 2. Understand the concept
By default, a container in Kubernetes might run as root, be able to escalate privileges, and have full access to the host filesystem. The SecurityContext lets you restrict these behaviors — similar to how you wouldn't give every employee in a company admin access to every system.

### 3. The actual answer
In your repo, the Spring Boot Deployment has:

```yaml
securityContext:
  runAsNonRoot: true              # container must not run as root (UID 0)
  allowPrivilegeEscalation: false # process cannot gain more privileges than parent
  readOnlyRootFilesystem: true    # container filesystem is read-only
  capabilities:
    drop:
      - ALL                       # remove all Linux kernel capabilities
```

What each setting prevents:

| Setting | What it prevents |
|---------|-----------------|
| `runAsNonRoot: true` | Container running as root (UID 0) — reduces blast radius of container escape |
| `allowPrivilegeEscalation: false` | `sudo`, `setuid` binaries gaining extra privileges |
| `readOnlyRootFilesystem: true` | Writing malware or modifying files in the container |
| `capabilities: drop: ALL` | Raw network access, kernel module loading, system time changes, etc. |

The read-only filesystem needs a writable `/tmp` — in your repo, an `emptyDir` volume with `medium: Memory` is mounted at `/tmp`. Memory-backed means it's RAM, not disk — faster and doesn't persist after pod restart.

### 4. Key takeaway
- SecurityContext restricts what a container process can do
- `runAsNonRoot` + `readOnlyRootFilesystem` + `drop ALL` is the production baseline
- `allowPrivilegeEscalation: false` prevents sudo-style privilege escalation
- Always provide a writable `/tmp` if using `readOnlyRootFilesystem` — use `emptyDir`

---

## Q11. What is a Kubernetes NetworkPolicy and what does your default-deny policy do?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of pod-level network security
- They want to know what your NetworkPolicy does and why you have it

### 2. Understand the concept
By default in Kubernetes, every pod can talk to every other pod — regardless of namespace. A compromised Spring Boot pod could potentially reach your Prometheus database or make calls to other services. NetworkPolicy lets you define firewall rules at the pod level.

### 3. The actual answer
In your repo (`helm/springboot/templates/networkpolicy.yaml`):

```yaml
spec:
  podSelector:
    matchLabels:
      app: springboot
  policyTypes:
    - Ingress    # only controls inbound traffic
```

This is a **default-deny ingress** policy. Because it specifies `policyTypes: [Ingress]` but has no `ingress` rules, it denies ALL inbound traffic to Spring Boot pods.

This means nothing can reach Spring Boot pods unless you explicitly add an ingress rule allowing it (e.g., from an ALB ingress or another service).

> **Note**: NetworkPolicy is enforced by the CNI plugin (AWS VPC CNI in EKS). If the CNI doesn't support NetworkPolicy, the rules are silently ignored. For EKS, you need either Calico or enable Network Policy support in VPC CNI.

### 4. Practical commands / examples

Command:
```bash
kubectl get networkpolicy -n default
```
Purpose: Lists NetworkPolicies in the default namespace.
What to look for: Policy name, pod selector, and policy types.

### 5. Key takeaway
- NetworkPolicy = firewall rules at the pod level
- Default-deny = block all traffic, then explicitly allow what's needed
- Without NetworkPolicy, all pods can communicate freely
- NetworkPolicy requires a supporting CNI plugin (VPC CNI with network policy enabled, or Calico)

---

## Q12. What is a PodDisruptionBudget (PDB) and why do you have one?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand availability during maintenance operations
- They are checking whether you know what disruptions PDB protects against

### 2. Understand the concept
Kubernetes sometimes needs to evict (gracefully stop) pods — during node upgrades, scaling down, or cluster maintenance. Without a PDB, Kubernetes could evict all your pods at once, causing downtime. PDB tells Kubernetes: "Never take down more than this many pods at once."

### 3. The actual answer
In your repo (`helm/springboot/templates/pdb.yaml`):

```yaml
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: springboot
```

`minAvailable: 1` means: "At least 1 Spring Boot pod must always be available during voluntary disruptions."

With 2 replicas (`replicaCount: 2`):
- Node upgrade starts → Kubernetes tries to evict all pods on that node
- PDB says: at least 1 must be available
- Kubernetes evicts 1 pod (1 still running) ✅
- Waits for replacement pod to be Running + Ready
- Then evicts the second pod ✅
- No downtime

**Voluntary vs involuntary disruptions**:
- PDB only applies to voluntary disruptions (node drain, rolling update)
- Does NOT protect against involuntary disruptions (node crash, OOM kill)

### 4. Key takeaway
- PDB = minimum availability guarantee during maintenance
- `minAvailable: 1` with 2 replicas = rolling node upgrades with zero downtime
- Only applies to voluntary disruptions (drains, rollouts) — not hardware failures
- Always pair PDB with `replicaCount >= 2` — PDB with 1 replica blocks all node drains

---

## Q13. What is Topology Spread Constraints and why does your deployment use it?

### 1. What is this question actually asking?
- The interviewer is testing if you understand pod scheduling and high availability
- They want to know why you don't just let Kubernetes place pods however it likes

### 2. Understand the concept
By default, Kubernetes tries to spread pods across nodes but doesn't guarantee even distribution. Both your Spring Boot pods could end up on the same node — if that node dies, both pods die at once. Topology Spread Constraints enforce how pods are distributed.

### 3. The actual answer
In your repo:

```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: springboot
```

What this means:
- `topologyKey: kubernetes.io/hostname` = spread across different nodes (by hostname)
- `maxSkew: 1` = the difference in pod count between any two nodes can be at most 1
- `whenUnsatisfiable: DoNotSchedule` = if constraint can't be satisfied, don't schedule (don't violate the rule)

With 2 replicas and 2 nodes: 1 pod per node. If one node fails, 1 pod (50%) still running.

Without this: both pods could be on node-1. Node-1 fails → 100% downtime.

### 4. Key takeaway
- Topology spread = forces even pod distribution across nodes/AZs
- `maxSkew: 1` = at most 1 pod difference between nodes
- Works with `topologyKey: kubernetes.io/hostname` (per node) or `topology.kubernetes.io/zone` (per AZ)
- Pair with PDB for full availability protection

---

## Q14. What is `automountServiceAccountToken: false` and why is it set?

### 1. What is this question actually asking?
- The interviewer is checking if you understand Kubernetes service account security
- They want to know what risk you're mitigating

### 2. Understand the concept
Every Kubernetes pod automatically gets a Service Account token mounted inside it. This token can be used to call the Kubernetes API — to list pods, read secrets, modify deployments. If your Spring Boot application is compromised, an attacker could use this token to attack the cluster itself.

### 3. The actual answer
By default, Kubernetes mounts a service account token at `/var/run/secrets/kubernetes.io/serviceaccount/token` inside every pod. This token has permissions to call the Kubernetes API.

Your Spring Boot app doesn't need to call the Kubernetes API — it's just a REST service. So in your repo:

```yaml
spec:
  automountServiceAccountToken: false
```

This removes the token from the pod entirely. If the pod is compromised, the attacker gets no Kubernetes API access.

This follows the **principle of least privilege** — give components only the permissions they actually need.

### 4. Key takeaway
- Service account tokens allow pods to call the Kubernetes API
- Most application pods don't need Kubernetes API access
- `automountServiceAccountToken: false` removes the token — reduces blast radius
- Only enable service account tokens for pods that genuinely need them (Argo CD, OTel Collector, etc.)

---

## Q15. What is the difference between resource requests and resource limits in Kubernetes?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how Kubernetes manages CPU and memory
- Common follow-up: "What happens when a pod exceeds its memory limit?"

### 2. Understand the concept
If you don't tell Kubernetes how much CPU and memory a pod needs, it will either not schedule it (if resources are tight) or let it consume all resources on a node — starving other pods. Requests and limits give Kubernetes the information it needs to schedule and protect resources.

### 3. The actual answer

| | Requests | Limits |
|--|---------|--------|
| Purpose | How much the pod needs (scheduling) | Maximum the pod can use |
| Scheduling | Kubernetes uses requests to find a node with enough capacity | Not used for scheduling |
| CPU exceed | Pod gets throttled (slowed down) | Pod gets throttled |
| Memory exceed | - | Pod is killed (OOMKilled) and restarted |

In your repo:
```yaml
resources:
  requests:
    cpu: "100m"      # 0.1 CPU cores reserved
    memory: "256Mi"  # 256MB reserved for scheduling
  limits:
    cpu: "500m"      # max 0.5 CPU cores
    memory: "512Mi"  # max 512MB — exceeded = OOMKilled
```

`100m` = 100 millicores = 0.1 of one CPU core.

### 4. Practical commands / examples

Command:
```bash
kubectl top pods -n default
```
Purpose: Shows current CPU and memory usage per pod.
What to look for: Usage close to limits = risk of throttling (CPU) or OOMKill (memory).

Command:
```bash
kubectl describe pod <pod-name> | grep -A5 "OOMKilled"
```
Purpose: Check if a pod was recently killed for exceeding memory limit.

### 5. Key takeaway
- Requests = minimum guaranteed resources (used for scheduling)
- Limits = maximum allowed (CPU throttled, memory = OOMKilled if exceeded)
- Always set both — no limits = pod can consume entire node
- `OOMKilled` exit code = container exceeded memory limit

---

## Q16. What is `kubectl` and what are the most important commands you use daily?

### 1. What is this question actually asking?
- Simple practical question — the interviewer wants to see if you're hands-on with Kubernetes
- They are checking your day-to-day operational knowledge

### 2. Understand the concept
`kubectl` is the command-line tool for interacting with Kubernetes clusters. Every operation — viewing pods, deploying applications, reading logs, debugging — goes through `kubectl`.

### 3. The actual answer

**Viewing resources:**
```bash
kubectl get pods -n <namespace>              # list pods
kubectl get pods -n <namespace> -o wide      # with node name and IPs
kubectl get all -n <namespace>               # pods, services, deployments, replicasets
kubectl describe pod <pod-name> -n <ns>      # detailed info + events
```

**Logs:**
```bash
kubectl logs <pod-name> -n <namespace>         # current logs
kubectl logs <pod-name> -n <namespace> -f      # follow (tail -f)
kubectl logs <pod-name> -n <namespace> --previous  # logs from crashed container
```

**Debugging:**
```bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh   # shell into pod
kubectl port-forward svc/<service> 8080:8080            # access service locally
kubectl describe node <node-name>                        # node resource usage
kubectl top pods -n <namespace>                          # CPU/memory usage
```

**Cluster state:**
```bash
kubectl get nodes                            # worker nodes
kubectl get namespaces                       # all namespaces
kubectl get events -n <namespace>            # recent events (errors, warnings)
```

### 4. Key takeaway
- `get` = list resources, `describe` = detailed view + events, `logs` = container output
- `-n <namespace>` = always specify namespace, otherwise defaults to `default`
- `kubectl events` is underused but very useful — shows warnings and errors
- `--previous` flag on logs = critical for debugging CrashLoopBackOff

---

## Q17. What is a rolling update in Kubernetes and how does it work?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand zero-downtime deployments
- They are checking if you know how Kubernetes updates pods without service interruption

### 2. Understand the concept
If you shut down all pods and then start new ones, there's a gap where your service is unavailable — downtime. A rolling update avoids this by replacing pods one at a time: start one new pod, wait for it to be ready, then stop one old pod. Repeat until all pods are updated.

### 3. The actual answer
When you update a Deployment (e.g., new image tag in `values.yaml`), Kubernetes performs a rolling update:

```text
Start: 2 old pods running (v1)

Step 1: Start 1 new pod (v2)
        Wait for readiness probe to pass (/actuator/health → UP)
        Now: 2 old + 1 new running

Step 2: Terminate 1 old pod (v1)
        Now: 1 old + 1 new running

Step 3: Start another new pod (v2)
        Wait for readiness probe

Step 4: Terminate last old pod
        Now: 2 new pods (v2) running

Result: Zero downtime, always at least 1 pod serving traffic
```

Controlled by `strategy.rollingUpdate`:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0    # never go below desired replica count
    maxSurge: 1          # allow 1 extra pod during update
```

Your Helm chart uses the default (25% maxUnavailable, 25% maxSurge).

### 4. Key takeaway
- Rolling update = one pod at a time replacement, zero downtime
- Readiness probe gates traffic — new pod only receives traffic when healthy
- PDB ensures minimum availability is respected during rolling updates
- If something goes wrong: `kubectl rollout undo deployment/<name>` reverts immediately

---

## Q18. What is etcd in Kubernetes and why is it important?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the Kubernetes control plane architecture
- They are testing whether you know what happens if etcd fails

### 2. Understand the concept
Kubernetes needs to store the state of the entire cluster somewhere — what pods should be running, what services exist, what ConfigMaps have, who is allowed to do what. This state is stored in etcd — a highly consistent distributed key-value database.

Think of etcd as Kubernetes' brain. If etcd is lost, Kubernetes loses all knowledge of what should be running.

### 3. The actual answer
etcd stores:
- All Kubernetes object definitions (Pods, Deployments, Services, Secrets, ConfigMaps)
- Cluster state (which pods are running on which nodes)
- RBAC rules
- All custom resource definitions

Key characteristics:
- **Consistent**: All reads return the latest write (strong consistency)
- **Distributed**: Runs as a cluster (usually 3 or 5 nodes) for HA
- **Sensitive**: Contains all Secrets — must be encrypted (your KMS config does this)
- **Must be backed up**: Loss of etcd = loss of entire cluster state

In EKS, AWS manages etcd — you don't access it directly. AWS handles backups, HA, and encryption.

### 4. Key takeaway
- etcd = Kubernetes' state database — everything Kubernetes knows is stored here
- AWS manages etcd in EKS — you don't touch it
- Your KMS encryption applies to Secrets stored in etcd
- In self-managed Kubernetes, etcd backup is critical — losing it = losing the cluster

---

## Q19. What is the EKS private endpoint setting and why did you enable it?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand EKS API access patterns and the security rationale
- They are checking whether you made this choice deliberately

### 2. Understand the concept
The EKS Kubernetes API server is what `kubectl` talks to. By default, it's accessible from the internet (with authentication). Setting `endpoint_public_access = false` means only resources inside the VPC can reach it — not the open internet.

### 3. The actual answer
In your repo (`terraform/eks.tf`):
```hcl
vpc_config {
  endpoint_private_access = true
  endpoint_public_access  = false
}
```

With `endpoint_public_access = false`:
- The Kubernetes API is only reachable from within the VPC
- External attackers cannot even reach the API to attempt authentication
- You access it via the jump server (which is in the VPC)

The workflow:
```text
Your laptop → SSH → Jump Server (in VPC) → kubectl → EKS Private API Endpoint
```

After `terraform apply`, you run on the jump server:
```bash
aws eks update-kubeconfig --region ap-south-1 --name pravin-devops-platform-eks
kubectl get nodes
```

### 4. Key takeaway
- Private endpoint = EKS API not exposed to internet (reduces attack surface significantly)
- Access via jump server or VPN — not from public internet
- Even if authentication is strong, removing internet exposure is defense-in-depth
- GitHub Actions accesses EKS through Terraform only (no kubectl in CI for this setup)

---

## Q20. What happens when a pod enters CrashLoopBackOff state?

### 1. What is this question actually asking?
- Classic Kubernetes troubleshooting question
- The interviewer wants to see your diagnostic reasoning — not just "check the logs"

### 2. Understand the concept
CrashLoopBackOff means a container keeps starting, crashing immediately, and Kubernetes keeps trying to restart it. The "backoff" part means Kubernetes waits progressively longer between restart attempts (10s, 20s, 40s, 80s, up to 5 minutes) to avoid thrashing.

### 3. The actual answer
Troubleshoot in this order:

**Step 1 — Check pod logs (most likely cause)**
```bash
kubectl logs <pod-name> -n <namespace> --previous
```
The `--previous` flag gets logs from the crashed container (not the current attempt).
What to look for: Exception stack trace, startup errors, config errors.

**Step 2 — Describe the pod for exit code**
```bash
kubectl describe pod <pod-name> -n <namespace>
```
What to look for:
- Exit code `1` = application error (check logs)
- Exit code `137` = OOMKilled (out of memory — increase memory limit)
- Exit code `143` = terminated by SIGTERM (graceful shutdown issue)

**Step 3 — Common causes**
| Cause | Symptom | Fix |
|-------|---------|-----|
| Application startup failure | Exception in logs | Fix app config (wrong DB URL, missing env var) |
| OOMKilled | Exit code 137 | Increase memory limit |
| Missing config/secret | `NullPointerException` | Check ConfigMap/Secret is mounted |
| Wrong image | `ImagePullBackOff` first | Fix image tag |
| Liveness probe too aggressive | Killed before app starts | Increase `initialDelaySeconds` |
| Read-only filesystem + writing to `/` | Permission denied | Ensure writable emptyDir volumes |

### 4. Practical commands / examples

Command:
```bash
kubectl logs <pod> -n <ns> --previous
```
Purpose: Logs from the crashed container instance.

Command:
```bash
kubectl describe pod <pod> -n <ns>
```
Purpose: Shows exit codes, events, and probe status.
What to look for: `Last State: Terminated`, `Exit Code`, `Reason: OOMKilled`.

### 5. Key takeaway
- CrashLoopBackOff = container crashes immediately after starting, repeatedly
- `--previous` flag on logs = critical — gets logs from the crashed instance
- Exit code 137 = OOMKilled (memory issue), exit code 1 = app error
- Backoff delay is Kubernetes protecting the cluster — don't fight it, fix the root cause

---

## Q21. What is the difference between kubectl apply and kubectl create?

### 1. What is this question actually asking?
- Simple but important practical question
- The interviewer is checking if you know declarative vs imperative Kubernetes management

### 2. Understand the concept
There are two ways to manage Kubernetes resources: tell it exactly what to do step by step (imperative), or describe the desired end state and let Kubernetes figure it out (declarative). `create` is imperative. `apply` is declarative.

### 3. The actual answer

| | `kubectl create` | `kubectl apply` |
|--|----------------|----------------|
| Style | Imperative | Declarative |
| Resource exists? | Fails with error | Updates it |
| Resource doesn't exist? | Creates it | Creates it |
| Track changes? | No | Yes (stores last-applied config) |
| Use in CI/CD? | No | Yes |

`kubectl apply` is idempotent — run it 10 times with the same YAML, result is the same. This is why Argo CD uses `apply` under the hood — it can safely re-apply on every sync.

`kubectl create` fails if the resource already exists — not suitable for CI/CD or GitOps.

### 4. Key takeaway
- `apply` = declarative, idempotent, use for everything in CI/CD and GitOps
- `create` = imperative, fails if resource exists, use only for one-off manual operations
- Argo CD uses server-side apply (`ServerSideApply=true` in your sync options)
- Always use `apply` in automation — never `create`
