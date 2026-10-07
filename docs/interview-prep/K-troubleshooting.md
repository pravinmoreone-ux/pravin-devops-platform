# Troubleshooting Interview Prep — Level 2 DevOps

---

## Q1: A pod is stuck in `Pending` state. How do you troubleshoot?

### What is this question actually asking?
- Systematic approach to pod scheduling failures
- Understanding scheduler, resources, PVCs, node selectors
- `kubectl describe` as primary diagnostic tool

### Understand the concept
`Pending` means the pod is accepted by API server but not scheduled to a node. The scheduler hasn't found a suitable node. Common causes: insufficient resources (CPU/memory), PVC not bound, node selector/affinity mismatch, taints/tolerations, scheduler not running.

### The actual answer
**Step-by-step**:
1. `kubectl describe pod <pod> -n <ns>` — check `Events` section for scheduler messages
2. `kubectl get nodes` — are nodes `Ready`? Any `SchedulingDisabled`?
3. `kubectl describe node <node>` — check `Allocatable` vs `Allocated` resources
4. If PVC: `kubectl get pvc -n <ns>` — status `Bound`? `kubectl describe pvc`
5. Check pod spec: `nodeSelector`, `affinity`, `tolerations`
6. `kubectl get events -n <ns> --sort-by='.lastTimestamp'` — cluster-wide events

**Common scheduler messages**:
- `0/3 nodes are available: 3 Insufficient cpu` — request > capacity
- `pod has unbound immediate PersistentVolumeClaims` — PVC issue
- `node(s) didn't match node selector` — label mismatch
- `node(s) had taint {..} that the pod didn't tolerate` — taint/toleration

### Practical commands / examples
```bash
# Full pod description
kubectl describe pod myapp-7d4b8c9f6-xyz -n production

# Node resources
kubectl describe node ip-10-0-1-50.ec2.internal

# PVC status
kubectl get pvc -n production
kubectl describe pvc myapp-data -n production

# All events sorted
kubectl get events -n production --sort-by='.lastTimestamp' | tail -20
```
**What to look for**: `Events` in `describe pod` is the #1 source; `Allocatable` vs `Requests/Limits` on nodes; PVC `STATUS` column.

### Key takeaway
- `kubectl describe pod` → `Events` = start here always
- Resource requests > node capacity = most common cause
- PVC must be `Bound` before pod schedules
- Node labels/taints must match pod selectors/tolerations

---

## Q2: A pod is in `CrashLoopBackOff`. How do you debug?

### What is this question actually asking?
- Container restart loop diagnosis
- Logs, exit codes, probe failures, OOM kills
- Difference between app crash vs probe failure

### Understand the concept
`CrashLoopBackOff` means container starts, exits, Kubernetes restarts it (with exponential backoff), repeats. Could be: app crash (bug, config), OOM kill (memory limit), liveness probe failure, missing dependency, permission error.

### The actual answer
**Step-by-step**:
1. `kubectl logs <pod> -n <ns> --previous` — logs from *previous* (crashed) container
2. `kubectl describe pod <pod> -n <ns>` — check `State: Waiting: Reason: CrashLoopBackOff`, `Last State: Terminated: Exit Code`, `OOMKilled`
3. Check probes: `livenessProbe`/`readinessProbe` in pod spec
4. `kubectl exec <pod> -n <ns> -- <command>` — if briefly running, debug inside
5. Check events: `kubectl get events -n <ns>`

**Exit codes**:
- `137` = SIGKILL (OOM or `docker kill`)
- `143` = SIGTERM (graceful shutdown)
- `1` = general app error
- `126` = command not executable
- `127` = command not found

### Practical commands / examples
```bash
# Previous container logs (critical!)
kubectl logs myapp-7d4b8c9f6-xyz -n production --previous

# Describe for exit code + OOM
kubectl describe pod myapp-7d4b8c9f6-xyz -n production

# If pod runs briefly, exec in
kubectl exec -it myapp-7d4b8c9f6-xyz -n production -- sh

# Check probe config
kubectl get pod myapp-7d4b8c9f6-xyz -n production -o yaml | grep -A 10 livenessProbe
```
**What to look for**: `Exit Code` in `describe`; `OOMKilled: true` = memory limit; `--previous` logs = actual crash output.

### Key takeaway
- `--previous` flag = essential for crash logs
- Exit code 137 = OOM (check `limits.memory`)
- Liveness probe failure = app not ready on path/port
- Increase `initialDelaySeconds` if app starts slow

---

## Q3: A Service shows no endpoints. Why?

### What is this question actually asking?
- Service → Pod label selector matching
- Endpoint controller logic
- Pod readiness vs service selection

### Understand the concept
A Service load-balances to Pods matching its `selector`. Endpoints are created by the Endpoints controller when Pods match the selector AND are `Ready` (pass readiness probe). No endpoints = selector mismatch, pods not ready, or wrong namespace.

### The actual answer
**Checklist**:
1. `kubectl get svc <svc> -n <ns> -o yaml` — check `spec.selector`
2. `kubectl get pods -n <ns> --show-labels` — do pod labels match selector exactly?
3. `kubectl get endpoints <svc> -n <ns>` — should list pod IPs
4. `kubectl describe pod <pod> -n <ns>` — check `Ready` condition (readiness probe)
4. Pod must be in *same namespace* as Service (unless using `ExternalName`)

### Practical commands / examples
```bash
# Service selector
kubectl get svc myapp -n production -o yaml | grep -A 5 selector

# Pod labels
kubectl get pods -n production --show-labels | grep myapp

# Endpoints
kubectl get endpoints myapp -n production

# Endpoint details
kubectl describe endpoints myapp -n production
```
**What to look for**: Label keys/values exact match (case-sensitive); `Ready=True` on pods; endpoints list pod IPs.

### Key takeaway
- Service selector = exact label match on pods
- Pods must pass `readinessProbe` to become endpoints
- Namespace must match (Service and Pod in same ns)
- `kubectl get endpoints` confirms if controller sees pods

---

## Q4: `ImagePullBackOff` / `ErrImagePull`. How to resolve?

### What is this question actually asking?
- Image registry authentication
- Image name/tag correctness
- Network connectivity to registry

### Understand the concept
Kubelet can't pull the container image. Causes: wrong image name/tag, private registry without credentials, rate limiting (Docker Hub), registry unreachable, manifest not found (arch mismatch).

### The actual answer
**Steps**:
1. `kubectl describe pod <pod> -n <ns>` — check `Events` for exact error
2. Verify image exists: `docker pull <image>` or `crictl pull <image>` on node
3. If private registry: check `imagePullSecrets` on pod/SA; secret type `kubernetes.io/dockerconfigjson`
4. Check tag: `latest` is risky; use explicit tag/digest
5. Architecture: image must match node arch (amd64 vs arm64)

### Practical commands / examples
```bash
# Describe for error details
kubectl describe pod myapp-xyz -n production

# Check imagePullSecrets
kubectl get pod myapp-xyz -n production -o jsonpath='{.spec.imagePullSecrets}'

# Verify secret content
kubectl get secret regcred -n production -o yaml

# Test pull on node (if access)
crictl pull nginx:1.25
```
**What to look for**: `repository does not exist` = wrong name; `authentication required` = missing/incorrect secret; `manifest unknown` = tag/arch mismatch.

### Key takeaway
- `describe pod` Events = exact error message
- Private registry = `imagePullSecrets` with dockerconfigjson
- Use explicit tags, not `latest`
- Multi-arch images = Docker manifest lists; verify node arch

---

## Q5: Node is `NotReady`. How do you investigate?

### What is this question actually asking?
- Kubelet health, container runtime, network, disk pressure
- Node conditions: `Ready`, `MemoryPressure`, `DiskPressure`, `PIDPressure`
- Systemd/journalctl on node

### Understand the concept
`NotReady` means kubelet hasn't reported healthy status to API server. Node controller marks it after `--node-monitor-grace-period` (default 40s). Causes: kubelet down, container runtime (containerd/cri-o) down, CNI plugin failure, disk full, clock skew, network partition.

### The actual answer
**On control plane**:
1. `kubectl describe node <node>` — check `Conditions`: `Ready`, `MemoryPressure`, `DiskPressure`, `PIDPressure`
2. `kubectl get events --field-selector involvedObject.kind=Node` — node-level events

**On the node (SSH)**:
3. `systemctl status kubelet` — active? logs: `journalctl -u kubelet -f`
4. `systemctl status containerd` / `crio` — runtime healthy?
5. `crictl ps` — can runtime list containers?
6. `df -h /var/lib/kubelet /var/lib/containerd` — disk space
7. `free -h` — memory
8. `ip link show cni0` / `cilium` — CNI interface up?

### Practical commands / examples
```bash
# Node conditions
kubectl describe node ip-10-0-1-50.ec2.internal

# Node events
kubectl get events --field-selector involvedObject.kind=Node --sort-by='.lastTimestamp'

# On node: kubelet logs
journalctl -u kubelet -f --since "10 min ago"

# On node: disk pressure check
df -h /var/lib/kubelet /var/lib/containerd

# On node: runtime
crictl info
crictl ps
```
**What to look for**: `Ready=False` with `DiskPressure=True` = disk full; `kubelet` inactive = service down; CNI not ready = pod network broken.

### Key takeaway
- `describe node` → `Conditions` = primary diagnosis
- Disk pressure = clean `/var/lib/containerd` (crictl rmp -a) or expand volume
- Kubelet logs = root cause (CNI, runtime, certs)
- Clock skew = `timedatectl` / NTP sync required

---

## Q6: DNS resolution fails inside pods. How to debug?

### What is this question actually asking?
- CoreDNS / kube-dns troubleshooting
- Pod `resolv.conf`, ndots, search domains
- Service discovery vs external DNS

### Understand the concept
Pods use cluster DNS (CoreDNS) via `/etc/resolv.conf`. Default `ndots:5` means 5 dots = absolute, else search domains appended. Issues: CoreDNS pods down, ConfigMap misconfig, firewall blocking 53, upstream DNS timeout, `ndots` causing slow external lookups.

### The actual answer
**Steps**:
1. `kubectl get pods -n kube-system -l k8s-app=kube-dns` — CoreDNS running?
2. `kubectl exec <pod> -n <ns> -- cat /etc/resolv.conf` — check nameserver, search, ndots
3. `kubectl exec <pod> -n <ns> -- nslookup kubernetes.default` — internal resolution
4. `kubectl exec <pod> -n <ns> -- nslookup google.com` — external resolution
5. `kubectl logs -n kube-system -l k8s-app=kube-dns` — CoreDNS logs
6. Check CoreDNS ConfigMap: `kubectl get configmap coredns -n kube-system -o yaml`

### Practical commands / examples
```bash
# CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Pod DNS config
kubectl exec myapp-xyz -n production -- cat /etc/resolv.conf

# Test internal DNS
kubectl exec myapp-xyz -n production -- nslookup kubernetes.default

# Test external DNS
kubectl exec myapp-xyz -n production -- nslookup google.com

# CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# CoreDNS ConfigMap
kubectl get configmap coredns -n kube-system -o yaml
```
**What to look for**: `nameserver 10.96.0.10` (cluster IP); `search production.svc.cluster.local`; `ndots:5`; CoreDNS `ERROR` logs.

### Key takeaway
- CoreDNS = cluster DNS; must be `Running` and `Ready`
- `ndots:5` = 5 dots before trying absolute; causes delay for external
- `resolv.conf` `search` list = auto-appends for short names
- Firewall/security group must allow pod → CoreDNS (UDP/TCP 53)

---

## Q7: `kubectl` commands hang or timeout. What's wrong?

### What is this question actually asking?
- API server connectivity / performance
- Authentication / authorization delays
- etcd health, controller manager

### Understand the concept
`kubectl` talks to API server. Hangs = API server not responding, or auth webhook timeout, or etcd slow. Could also be local kubeconfig issue, proxy, or network.

### The actual answer
**Diagnosis**:
1. `kubectl version` — client vs server version skew?
2. `kubectl get --raw=/healthz` — API server health endpoint
3. `kubectl get --raw=/readyz` — API server readiness
4. Check API server logs (if access): `journalctl -u kube-apiserver`
5. Check etcd: `kubectl get componentstatuses` (deprecated) or etcdctl
6. Local: `kubectl config view` — correct cluster/context?
7. Network: `curl -k https://<api-server>:6443/healthz`

### Practical commands / examples
```bash
# API server health
kubectl get --raw=/healthz
kubectl get --raw=/readyz

# Version check
kubectl version

# Direct API call (bypass kubectl)
curl -k -H "Authorization: Bearer $(kubectl config view --raw -o jsonpath='{.users[0].user.token}')" https://<api-server>:6443/healthz

# If using proxy
kubectl proxy --port=8080 &
curl http://localhost:8080/healthz
```
**What to look for**: `/healthz` = `ok`; `/readyz` = `ok` (all controllers healthy); version skew > 1 minor = issues; etcd leader errors in API server logs.

### Key takeaway
- `/healthz` = API server process alive; `/readyz` = can serve traffic
- Version skew policy: client ±1 minor from server
- etcd slow = API server slow = all kubectl slow
- Auth webhook (OIDC, webhook token) timeout = hang on first request

---

## Q8: PersistentVolumeClaim stuck in `Pending`. How to fix?

### What is this question actually asking?
- PV provisioning: static vs dynamic
- StorageClass, provisioner, volumeBindingMode
- Access modes, capacity, topology constraints

### Understand the concept
PVC `Pending` = no matching PV available. Dynamic provisioning: StorageClass provisioner creates PV. Static: admin pre-creates PV. Issues: no StorageClass, provisioner not installed, volumeBindingMode=WaitForFirstConsumer (delays binding), zone mismatch, capacity too small.

### The actual answer
**Steps**:
1. `kubectl describe pvc <pvc> -n <ns>` — check `Events` for provisioner errors
2. `kubectl get storageclass` — is there a default? (`(default)` annotation)
3. `kubectl get sc <sc> -o yaml` — check `provisioner`, `volumeBindingMode`, `allowedTopologies`
4. `kubectl get pv` — any unbound PV matching capacity/accessMode?
5. If `WaitForFirstConsumer`: PVC binds only when pod using it schedules

### Practical commands / examples
```bash
# PVC events
kubectl describe pvc myapp-data -n production

# StorageClasses
kubectl get sc
kubectl get sc gp3 -o yaml

# PVs
kubectl get pv

# If WaitForFirstConsumer, create pod to trigger binding
kubectl run test-pod --image=nginx --overrides='{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"myapp-data"}}],"containers":[{"name":"nginx","image":"nginx","volumeMounts":[{"name":"data","mountPath":"/data"}]}]}}' -n production
```
**What to look for**: `volumeBindingMode: WaitForFirstConsumer` = normal delay; `provisioner` not found = CSI driver missing; `No volume plugin matched` = StorageClass issue.

### Key takeaway
- Dynamic = StorageClass + provisioner (CSI driver)
- `WaitForFirstConsumer` = binds at pod schedule time (zone-aware)
- Default StorageClass = `storageclass.kubernetes.io/is-default-class: "true"`
- AccessModes must match (RWO vs RWX vs ROX)

---

## Q9: Ingress returns 502 / 503. How to troubleshoot?

### What is this question actually asking?
- Ingress controller (NGINX, ALB, Traefik) → Service → Pod connectivity
- Backend health, service endpoints, annotations
- Controller logs, service port matching

### Understand the concept
Ingress controller proxies HTTP to Service. 502 = bad gateway (upstream connection failed). 503 = service unavailable (no healthy endpoints). Causes: Service has no endpoints, pod not ready, port mismatch (Ingress `servicePort` vs Service `targetPort`), controller down, annotation misconfig.

### The actual answer
**Steps**:
1. `kubectl get ingress <ing> -n <ns> -o yaml` — check rules, backend service/port
2. `kubectl get svc <svc> -n <ns>` — Service exists? ClusterIP?
3. `kubectl get endpoints <svc> -n <ns>` — endpoints present?
4. `kubectl describe pod <pod> -n <ns>` — pod `Ready`? passing readiness probe?
4. `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx` — controller logs
5. Check annotations: `nginx.ingress.kubernetes.io/rewrite-target`, `ssl-redirect`

### Practical commands / examples
```bash
# Ingress config
kubectl get ingress myapp -n production -o yaml

# Service + endpoints
kubectl get svc myapp -n production
kubectl get endpoints myapp -n production

# Pod readiness
kubectl get pods -n production -l app=myapp

# Ingress controller logs (NGINX example)
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100

# Test Service directly (bypass Ingress)
kubectl port-forward svc/myapp 8080:80 -n production &
curl localhost:8080/health
```
**What to look for**: Endpoints empty = pod selector/readiness issue; Controller logs show upstream connect errors; Port mismatch = `servicePort` in Ingress vs `port` in Service.

### Key takeaway
- 502 = Ingress can't reach backend (pod down, wrong port, network policy)
- 503 = no endpoints (Service selector mismatch, pods not ready)
- Test Service directly with `port-forward` to isolate Ingress vs backend
- Controller logs = detailed upstream error (connection refused, timeout)

---

## Q10: Pod runs but application is not accessible (connection refused / timeout).

### What is this question actually asking?
- Container port vs Service port vs Ingress port
- Pod network policy, CNI, hostPort
- Application binding to 0.0.0.0 vs 127.0.0.1

### Understand the concept
Pod IP is reachable within cluster. Service load-balances to pod IP:containerPort. If app binds to 127.0.0.1 (localhost) inside container, it's not reachable from outside. Must bind to 0.0.0.0. Also: NetworkPolicy may block ingress, CNI issues, containerPort mismatch.

### The actual answer
**Checklist**:
1. `kubectl get pod <pod> -n <ns> -o yaml` — check `containerPort` in spec
2. `kubectl exec <pod> -n <ns> -- netstat -tlnp` — what port is app listening on? (0.0.0.0:8080 vs 127.0.0.1:8080)
3. `kubectl exec <pod> -n <ns> -- curl localhost:8080/health` — works inside pod?
4. `kubectl run test --rm -i --image=curlimages/curl -- curl <pod-ip>:8080/health` — works from another pod?
5. Check NetworkPolicy: `kubectl get netpol -n <ns>`

### Practical commands / examples
```bash
# Pod spec containerPort
kubectl get pod myapp-xyz -n production -o jsonpath='{.spec.containers[0].ports}'

# Inside pod: listening address
kubectl exec myapp-xyz -n production -- netstat -tlnp

# Inside pod: local curl
kubectl exec myapp-xyz -n production -- curl -s localhost:8080/health

# From another pod: test pod IP
kubectl run test --rm -i --image=curlimages/curl -- curl -s <POD_IP>:8080/health

# NetworkPolicy
kubectl get netpol -n production -o yaml
```
**What to look for**: `netstat` shows `127.0.0.1:8080` = bind to localhost only (fix: `0.0.0.0`); `containerPort` must match app port; NetworkPolicy `ingress` rules may block.

### Key takeaway
- App **must** bind to `0.0.0.0`, not `127.0.0.1` (container localhost ≠ pod network)
- `containerPort` in pod spec = informational; Service `targetPort` must match
- Test inside pod first, then pod-to-pod, then Service
- NetworkPolicy default-deny = common cause in secured clusters

---

## Q11: Terraform `apply` fails with "Error acquiring state lock". What to do?

### What is this question actually asking?
- Terraform state locking mechanism (DynamoDB for S3 backend)
- Stale locks from crashed runs
- Force unlocking safely

### Understand the concept
Terraform locks state during write operations (plan/apply) using backend lock table (DynamoDB for S3). If previous run crashed or was killed, lock remains. `terraform force-unlock` removes it but **only use if certain no other run is active**.

### The actual answer
**Steps**:
1. Check if another CI/CD run is active (GitHub Actions, Jenkins)
2. `terraform force-unlock <LOCK_ID>` — lock ID from error message
3. If using S3+DynamoDB: verify DynamoDB table `LockID` matches
4. Never force-unlock if another team member might be running Terraform

### Practical commands / examples
```bash
# Error shows lock ID
# Error: Error acquiring the state lock: ConditionalCheckFailedException
# Lock Info:
#   ID:        a1b2c3d4-e5f6-7890-abcd-ef1234567890
#   Path:      production/terraform.tfstate
#   Operation: Apply
#   Who:       user@host
#   Version:   1.6.0
#   Created:   2024-01-15 10:30:00 UTC

# Force unlock (ONLY if sure no other run)
terraform force-unlock a1b2c3d4-e5f6-7890-abcd-ef1234567890

# Verify DynamoDB directly (if AWS access)
aws dynamodb get-item --table-name terraform-locks --key '{"LockID": {"S": "production/terraform.tfstate"}}'
```
**What to look for**: Lock `ID` in error; `Who` and `Created` = who/when; verify no active CI runs before forcing.

### Key takeaway
- State lock = prevents concurrent writes (corruption)
- Stale locks = crashed/killed Terraform process
- `force-unlock` = last resort; coordinate with team first
- DynamoDB TTL = auto-expire (default 1 hour? check config)

---

## Q12: Terraform plan shows unexpected changes (drift). How to investigate?

### What is this question actually asking?
- State vs actual infrastructure drift
- Refresh, `terraform plan -refresh-only`
- External changes (console, scripts, other tools)

### Understand the concept
Drift = real infrastructure differs from Terraform state. Causes: manual console changes, other tools (Ansible, CLI), concurrent Terraform runs, provider bugs. `terraform plan` refreshes state by default; `-refresh-only` updates state without planning.

### The actual answer
**Steps**:
1. `terraform plan -refresh-only` — updates state with current remote values, shows drift
2. `terraform state list` — resources in state
3. `terraform state show <resource>` — compare state vs actual
4. Check AWS console / CLI for actual resource config
5. Determine source: manual change? another pipeline? provider update?

### Practical commands / examples
```bash
# Refresh-only plan (shows drift without proposing changes)
terraform plan -refresh-only

# Show specific resource in state
terraform state show aws_instance.web

# Compare with actual (AWS CLI)
aws ec2 describe-instances --instance-ids i-0123456789abcdef0

# List all resources in state
terraform state list
```
**What to look for**: `plan -refresh-only` output shows `~` (update in-place) for drifted attributes; `terraform state show` = current state snapshot.

### Key takeaway
- Drift = reality ≠ state; `plan` detects it automatically
- `-refresh-only` = safe way to sync state without apply
- Find root cause: console, other IaC, shared accounts
- Prevent: restrict console access, use SCPs, single Terraform pipeline

---

## Q13: Terraform module version upgrade breaks things. How to handle?

### What is this question actually asking?
- Module versioning, registry, source constraints
- Breaking changes, changelog, testing strategy
- Pinning versions, `terraform init -upgrade`

### Understand the concept
Modules from registry (or Git) have versions. Upgrading can introduce breaking changes: renamed outputs, changed defaults, removed resources. Always pin versions (`version = "~> 5.0"`), read changelog, test in staging before prod.

### The actual answer
**Process**:
1. Check module registry for changelog / release notes
2. Update version constraint: `version = "~> 5.0"` → `version = "~> 6.0"`
3. `terraform init -upgrade` — downloads new version
4. `terraform plan` — review changes carefully
5. Test in non-prod environment
6. If breaking: either fix usage or pin to older version

### Practical commands / examples
```bash
# Upgrade module
terraform init -upgrade

# Plan with new version
terraform plan

# Show module versions
terraform version
# Or check .terraform/modules/
```
**What to look for**: Module `CHANGELOG.md` or GitHub releases; `plan` output shows destroyed/recreated resources; `init -upgrade` respects version constraints.

### Key takeaway
- Always pin module versions (`~>` for patch/minor, exact for major)
- Read changelog before upgrading
- Test in staging; `plan` shows destructive changes
- Registry modules: `source = "terraform-aws-modules/vpc/aws"` + `version`

---

## Q14: EKS cluster creation fails. Common causes and debugging.

### What is this question actually asking?
- EKS control plane + node group provisioning
- IAM roles, VPC, subnets, security groups
- CloudFormation stack events, EKS console

### Understand the concept
EKS creates control plane (managed) + node groups (EC2 ASG). Failures: IAM role missing permissions, VPC/subnet configuration (NAT, endpoints), security group rules, quota limits, Kubernetes version unsupported.

### The actual answer
**Debug steps**:
1. AWS Console → CloudFormation → stack events (eksctl/Terraform creates stacks)
2. `aws eks describe-cluster --name <name>` — cluster status, endpoint, errors
3. `aws eks describe-nodegroup --cluster-name <name> --nodegroup-name <ng>` — nodegroup status
4. Check IAM: node role has `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEKS_CNI_Policy`
5. VPC: subnets tagged `kubernetes.io/role/elb` (public) or `kubernetes.io/role/internal-elb` (private); NAT gateway for private

### Practical commands / examples
```bash
# Cluster status
aws eks describe-cluster --name my-cluster

# Nodegroup status
aws eks describe-nodegroup --cluster-name my-cluster --nodegroup-name ng-1

# CloudFormation events (if using Terraform/eksctl)
aws cloudformation describe-stack-events --stack-name eksctl-my-cluster-cluster --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'

# Node IAM role policies
aws iam list-attached-role-policies --role-name my-node-role
```
**What to look for**: CloudFormation `CREATE_FAILED` events = root cause; Nodegroup `ACTIVE` vs `CREATE_FAILED`; Subnet tags for ALB/NAT.

### Key takeaway
- Control plane = CloudFormation stack; check events
- Nodegroup = separate stack; needs correct IAM + VPC
- Private subnets = NAT gateway required for node join
- Subnet tags = critical for ALB controller, node discovery

---

## Q15: EKS nodes not joining cluster (NotReady / not appearing). How to fix?

### What is this question actually asking?
- Bootstrap script, kubelet, API server endpoint
- Security groups, VPC endpoints, IAM
- User data, launch template, node labels

### Understand the concept
EKS nodes run bootstrap script (`/etc/eks/bootstrap.sh`) on startup to join cluster. Failure = script can't reach API server, kubelet fails, or node not labeled correctly. Causes: SG blocking 443/10250, no VPC endpoint for private clusters, wrong cluster name in user data, IAM missing `eks:DescribeCluster`.

### The actual answer
**Steps**:
1. `aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names <asg>` — check instances launching?
2. SSH to node (if public) or SSM Session Manager — check `/var/log/eks-bootstrap.log`
3. `systemctl status kubelet` — running? logs: `journalctl -u kubelet`
4. Security group: node SG allows outbound 443 to control plane SG; control plane SG allows inbound 443/10250 from node SG
5. Private cluster: VPC interface endpoints for `eks`, `ecr`, `logs`, `sts`
6. User data: `bootstrap.sh` includes correct `--cluster-name` and `--apiserver-endpoint`

### Practical commands / examples
```bash
# ASG status
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names my-asg

# On node: bootstrap log
cat /var/log/eks-bootstrap.log

# On node: kubelet
journalctl -u kubelet -f

# VPC endpoints (private cluster)
aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=vpc-12345

# Security group rules
aws ec2 describe-security-groups --group-ids sg-node sg-controlplane
```
**What to look for**: Bootstrap log = "Waiting for API server" = network/IAM; kubelet cert errors = IAM/endpoint; VPC endpoints = required for private clusters.

### Key takeaway
- Bootstrap log = #1 source for node join failures
- Private clusters = VPC endpoints mandatory (EKS, ECR, CloudWatch, STS)
- SG: nodes → control plane 443; control plane → nodes 10250 (kubelet)
- IAM: node role needs `eks:DescribeCluster` for bootstrap

---

## Q16: Argo CD Application stuck in `Progressing` / `Degraded`. How to debug?

### What is this question actually asking?
- Argo CD sync status, health assessment
- Resource hooks, sync waves, finalizers
- Controller logs, resource events

### Understand the concept
Argo CD compares desired (Git) vs actual (cluster). `Progressing` = sync in progress or waiting. `Degraded` = health check failed (e.g., Deployment not available). `OutOfSync` = drift detected. Health: Deployment = available replicas; Pod = Running/Ready.

### The actual answer
**Steps**:
1. Argo CD UI → Application → **Resources** tab → click resource → **Events** / **Manifest** / **Diff**
2. `argocd app get <app>` — status, health, sync windows
3. `kubectl get <resource> -n <ns>` — actual cluster state
4. Check sync waves: `argocd app sync <app> --dry-run` — order
5. Check hooks: `preSync`/`postSync`/`syncFail` hooks blocking?
6. Controller logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller`

### Practical commands / examples
```bash
# App status
argocd app get myapp

# Sync dry-run
argocd app sync myapp --dry-run

# Controller logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100

# Resource health (example Deployment)
kubectl get deploy myapp -n production -o yaml | grep -A 10 conditions
```
**What to look for**: `Sync Status: OutOfSync` = drift; `Health Status: Degraded` = resource unhealthy; hooks with `deletePolicy: HookSucceeded` may linger.

### Key takeaway
- `Progressing` = sync running or waiting for health
- `Degraded` = resource health check failed (check resource conditions)
- Sync waves (`argocd.argoproj.io/sync-wave`) control order
- Hooks can block sync; check `preSync`/`postSync` pods

---

## Q17: Argo CD sync fails with "resource already exists" / conflict. Why?

### What is this question actually asking?
- Server-side apply, field ownership, `kubectl apply` vs Argo CD
- `Replace: true`, `Prune: true`, `Force: true`
- Concurrent edits, manual changes

### Understand the concept
Argo CD uses server-side apply (SSA) with field manager `argocd`. Conflict = another field manager (kubectl, another controller) owns fields Argo CD wants to manage. `Replace: true` forces ownership; `Force: true` deletes/recreates; `Prune: true` removes resources not in Git.

### The actual answer
**Causes & fixes**:
1. **Manual `kubectl apply`** — Argo CD loses field ownership. Fix: `argocd app sync <app> --replace --force`
2. **Another controller** (e.g., cert-manager, external-dns) — annotate resource `argocd.argoproj.io/sync-options: Replace=true`
3. **CRD conversion webhook** — may cause conflicts; check controller logs
4. **Immutable fields** — some fields can't change (e.g., Service `clusterIP`); need `Replace: true`

### Practical commands / examples
```bash
# Force sync with replace
argocd app sync myapp --replace --force --prune

# Check field managers on resource
kubectl get deploy myapp -n production -o yaml | grep -A 20 managedFields

# Annotate resource for auto-replace
kubectl annotate deploy myapp -n production argocd.argoproj.io/sync-options=Replace=true --overwrite
```
**What to look for**: `managedFields` shows `manager: argocd` vs `manager: kubectl`; `--replace` takes ownership; `--force` deletes/recreates.

### Key takeaway
- SSA field manager = `argocd`; conflicts = other managers
- `--replace` = take field ownership; `--force` = recreate
- Annotate resources managed by other controllers
- Never manually `kubectl apply` Argo CD-managed resources

---

## Q18: Helm release upgrade fails / stuck. How to recover?

### What is this question actually asking?
- Helm release status: deployed, failed, pending-upgrade, pending-rollback
- `helm rollback`, `helm uninstall`, `--force`
- Secret labels, revision history

### Understand the concept
Helm stores release state in Secrets (`sh.helm.release.v1`). Failed upgrade leaves release in `pending-upgrade` or `failed`. `pending-rollback` = rollback in progress. Recovery: `helm rollback`, or delete secret + reinstall (last resort).

### The actual answer
**Steps**:
1. `helm list -n <ns> -a` — check STATUS (`deployed`, `failed`, `pending-upgrade`)
2. `helm status <release> -n <ns>` — detailed status, notes
3. `helm history <release> -n <ns>` — revision history
4. `helm rollback <release> <revision> -n <ns>` — rollback to working revision
5. If stuck `pending-upgrade`: `helm rollback <release> 0 -n <ns>` (rollback to 0 = uninstall)
6. Last resort: delete release secret `sh.helm.release.v1.<release>.v<rev>` and reinstall

### Practical commands / examples
```bash
# List all releases (including failed)
helm list -n production -a

# Status
helm status myapp -n production

# History
helm history myapp -n production

# Rollback to previous
helm rollback myapp 1 -n production

# Rollback to 0 (uninstall) if stuck pending-upgrade
helm rollback myapp 0 -n production

# View release secret
kubectl get secret -n production -l owner=helm -o yaml
```
**What to look for**: `STATUS: failed` or `pending-upgrade`; `REVISION` numbers; `helm rollback` to known-good revision.

### Key takeaway
- Helm 3 stores state in Secrets (not ConfigMaps like v2)
- `pending-upgrade`/`pending-rollback` = stuck; rollback to 0 clears
- `helm history` shows all revisions; pick stable one
- Never manually edit release secrets unless absolutely necessary

---

## Q19: GitHub Actions workflow fails intermittently. How to debug?

### What is this question actually asking?
- Flaky tests, network issues, runner resource limits
- Caching, artifact upload/download
- Re-run vs re-run failed jobs

### Understand the concept
Intermittent failures = non-deterministic. Causes: external API rate limits, flaky integration tests, runner OOM, cache corruption, timing issues (race conditions), GitHub API throttling.

### The actual answer
**Debug approach**:
1. **Re-run failed job** — if passes, likely flaky
2. Check runner logs: `Set up job` → `Runner environment` — memory/CPU
3. Add `timeout-minutes` to jobs/steps
4. Cache: `actions/cache` — verify `restore-keys` fallback
5. Network: retry logic for external calls (npm, docker pull, AWS CLI)
6. Flaky tests: quarantine, fix root cause, don't just retry

### Practical commands / examples
```yaml
# Workflow: retry step
- name: Flaky step
  uses: nick-invision/retry@v2
  with:
    timeout_minutes: 5
    max_attempts: 3
    command: npm test

# Cache with fallback
- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: npm-${{ runner.os }}-${{ hashFiles('package-lock.json') }}
    restore-keys: |
      npm-${{ runner.os }}-

# Job timeout
jobs:
  test:
    timeout-minutes: 30
    steps: ...
```
**What to look for**: `OOMKilled` in logs = memory limit; `ETIMEDOUT` / `ENOTFOUND` = network; `Cache not found` = key mismatch.

### Key takeaway
- Re-run once to distinguish flaky vs consistent
- Runner memory: 7GB (ubuntu-latest); OOM = optimize or use larger runner
- Cache `restore-keys` = fallback for partial matches
- Retry wrapper for external dependencies; fix flaky tests properly

---

## Q20: Docker build fails in CI but works locally. Common causes?

### What is this question actually asking?
- Build context, .dockerignore, architecture differences
- Cache, BuildKit, multi-stage
- Platform (amd64 vs arm64), base image availability

### Understand the concept
Local vs CI differences: architecture (Mac M1/M2 = arm64, CI = amd64), build context size, `.dockerignore` missing, BuildKit features, base image digest pinning, network access (private registries), layer caching.

### The actual answer
**Common causes**:
1. **Architecture**: Local arm64, CI amd64 → `docker buildx build --platform linux/amd64`
2. **Build context**: Large context (node_modules, .git) → `.dockerignore`
3. **Cache**: CI fresh runner = no layer cache → `cache-from` / BuildKit cache
4. **Base image**: `latest` tag changes → pin digest `ubuntu@sha256:...`
5. **Network**: Private registry auth in CI → `--secret` / build args
6. **BuildKit**: `DOCKER_BUILDKIT=1` locally, not in CI (or vice versa)

### Practical commands / examples
```bash
# Build for specific platform
docker buildx build --platform linux/amd64 -t myapp:latest .

# Build with cache (GitHub Actions)
- uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: myapp:latest
    cache-from: type=gha
    cache-to: type=gha,mode=max

# .dockerignore example
# .dockerignore
node_modules/
.git/
*.log
.DS_Store

# Pin base image digest
FROM ubuntu@sha256:abc123...
```
**What to look for**: `exec format error` = arch mismatch; `no space left` = context too large; `pull access denied` = registry auth.

### Key takeaway
- Always build for target platform (`--platform linux/amd64`)
- `.dockerignore` = critical for build speed and correctness
- Pin base image digests for reproducibility
- BuildKit + GitHub Actions cache = fast CI builds

---

## Q21: Application high latency / timeouts in Kubernetes. Troubleshooting approach.

### What is this question actually asking?
- Four golden signals: latency, traffic, errors, saturation
- Distributed tracing, metrics, logs correlation
- Service mesh, sidecar, network hops

### Understand the concept
Latency = time from request to response. Sources: app code, DB, external API, network (CNI, Service mesh), GC pauses, thread pool exhaustion, CPU throttling. Method: trace request path, measure each hop.

### The actual answer
**Systematic approach**:
1. **Metrics** (Grafana/Prometheus): `http_request_duration_seconds` percentile (p50, p95, p99); `container_cpu_cfs_throttled_periods_total`
2. **Traces** (Tempo/Jaeger): end-to-end trace; identify slow span (DB, external, internal)
3. **Logs** (Loki): error spikes, GC logs, timeout messages
4. **Kubernetes**: `kubectl top pods` — CPU/memory; `kubectl describe pod` — throttling, OOM
5. **Network**: Service mesh (Istio/Linkerd) adds hops; CNI latency

### Practical commands / examples
```bash
# PromQL: p99 latency
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))

# PromQL: CPU throttling
rate(container_cpu_cfs_throttled_periods_total[5m])

# Pod resource usage
kubectl top pods -n production --sort-by=memory

# Trace query (Tempo)
# Use Grafana Tempo datasource: traceQL or service graph

# Check for CPU limits/throttling
kubectl get pods -n production -o yaml | grep -A 5 resources
```
**What to look for**: p99 >> p50 = tail latency; throttling > 0 = CPU limit too low; trace shows exact slow component.

### Key takeaway
- Start with metrics (RED: Rate, Errors, Duration)
- Traces = pinpoint slow hop (DB, external, internal)
- CPU throttling = common hidden latency cause
- Correlate: metrics spike + trace + logs at same timestamp

---

## Q22: Database connection pool exhaustion. How to diagnose and fix?

### What is this question actually asking?
- Connection pool sizing, leak detection
- PgBouncer, HikariCP, application config
- Idle connections, max connections, statement timeout

### Understand the concept
App opens DB connections from pool. Exhaustion = all connections in use, new requests wait/timeout. Causes: pool too small, connection leak (not returning), long-running queries, no statement timeout, too many app replicas.

### The actual answer
**Diagnosis**:
1. DB: `SHOW max_connections;` vs `SELECT count(*) FROM pg_stat_activity;` (PostgreSQL)
2. App: pool config (HikariCP: `maximumPoolSize`, `minimumIdle`, `idleTimeout`)
3. Logs: "connection pool exhausted", "timeout waiting for connection"
4. Metrics: `hikaricp_connections_active`, `hikaricp_connections_idle`

**Fixes**:
- Increase pool size (but ≤ DB `max_connections` / replicas)
- Fix leaks: `try-with-resources`, `@Transactional` boundaries
- Add `statement_timeout`, `idle_in_transaction_session_timeout`
- Use PgBouncer (transaction pooling) for high replica counts

### Practical commands / examples
```bash
# PostgreSQL: current connections
psql -c "SELECT datname, usename, state, count(*) FROM pg_stat_activity GROUP BY 1,2,3;"

# PostgreSQL: max connections
psql -c "SHOW max_connections;"

# App metrics (Prometheus)
hikaricp_connections_active
hikaricp_connections_idle
hikaricp_connections_pending

# Java: HikariCP config
# spring.datasource.hikari.maximum-pool-size=20
# spring.datasource.hikari.minimum-idle=5
# spring.datasource.hikari.idle-timeout=300000
# spring.datasource.hikari.connection-timeout=30000
```
**What to look for**: Active connections = max pool = exhaustion; `idle in transaction` = leak; `pending` threads = wait queue.

### Key takeaway
- Pool size = `max_connections` / (replicas × safety factor)
- Leaks = not closing connections; use `try-with-resources`
- Timeouts prevent stuck connections
- PgBouncer = scales connections for many replicas

---

## Q23: TLS certificate errors in cluster (Ingress, Service Mesh, mTLS). How to debug?

### What is this question actually asking?
- Cert-manager, Let's Encrypt, self-signed CA
- Certificate resources: Certificate, CertificateRequest, Order, Challenge
- mTLS: peer authentication, destination rules

### Understand the concept
TLS in Kubernetes: cert-manager automates cert issuance. Ingress TLS = secret with `tls.crt`/`tls.key`. mTLS (Istio/Linkerd) = automatic cert rotation via SPIFFE. Errors: cert expired, DNS challenge failed, CA not trusted, SAN mismatch, secret not found.

### The actual answer
**Steps**:
1. `kubectl get certificate -n <ns>` — `Ready` status? `NotReady` = check `CertificateRequest`
2. `kubectl describe certificate <cert> -n <ns>` — events: challenge, order
3. `kubectl get certificaterequest,order,challenge -n <ns>` — chain status
4. `kubectl get secret <tls-secret> -n <ns> -o yaml` — cert data, expiry
5. Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager`
6. mTLS: `istioctl x authz check <pod>` / `linkerd check`

### Practical commands / examples
```bash
# Cert-manager resources
kubectl get certificate,certificaterequest,order,challenge -n production

# Describe certificate
kubectl describe certificate myapp-tls -n production

# Secret content (check expiry)
kubectl get secret myapp-tls -n production -o yaml | grep tls.crt | head -1 | base64 -d | openssl x509 -text -noout

# Cert-manager logs
kubectl logs -n cert-manager -l app=cert-manager --tail=50

# Istio mTLS check
istioctl x authz check myapp-xyz -n production
```
**What to look for**: `Ready=False` + `Reason: ChallengeFailed` = DNS/ACME issue; cert expiry date in secret; cert-manager `ERROR` logs.

### Key takeaway
- Certificate → CertificateRequest → Order → Challenge chain
- DNS01 challenge = requires DNS provider credentials
- Secret `tls.crt` = cert + chain; `tls.key` = private key
- mTLS = mesh handles automatically; check peer auth policies

---

## Q24: CI/CD pipeline deploys wrong version / stale image. Root causes?

### What is this question actually asking?
- Image tagging strategy: semver, git SHA, latest
- Deployment manifest update mechanism (Argo CD, Helm, kubectl)
- Cache, digest vs tag, rollout verification

### Understand the concept
Stale deploy = cluster runs old image despite new build. Causes: `:latest` tag not updated (digest unchanged), Argo CD not auto-syncing, Helm values not updated, imagePullPolicy `IfNotPresent` with same tag, manifest not committed to Git.

### The actual answer
**Root causes & fixes**:
1. **`:latest` tag** — mutable; use immutable tags: `git-sha`, `semver`, `digest`
2. **Argo CD auto-sync disabled** — enable or manual sync
3. **Helm values not updated** — CI must update `image.tag` in values file / Git
4. **`imagePullPolicy: IfNotPresent`** — with same tag, node uses cached image → use `Always` or unique tags
5. **Digest pinning** — `image: repo/app@sha256:abc` guarantees exact image

### Practical commands / examples
```bash
# Check actual image digest on pod
kubectl get pod myapp-xyz -n production -o jsonpath='{.status.containerStatuses[0].imageID}'

# Argo CD sync status
argocd app get myapp

# Helm values in Git
cat helm/springboot/values.yaml | grep -A 3 image:

# Force pull
kubectl patch deploy myapp -n production -p '{"spec":{"template":{"spec":{"containers":[{"name":"myapp","imagePullPolicy":"Always"}]}}}}'
```
**What to look for**: `imageID` = digest (sha256:...); compare with built image digest; Argo CD `Sync Status` = `OutOfSync`.

### Key takeaway
- Never use `:latest` in production; use git SHA or semver
- Argo CD auto-sync = continuous deployment; manual = human gate
- `imagePullPolicy: Always` + unique tags = guaranteed fresh pull
- Digest pinning = immutable, verifiable deployments

---

## Q25: Cost spike in AWS bill. How to investigate and optimize?

### What is this question actually asking?
- Cost Explorer, CUR, tagging strategy
- EKS, EC2, EBS, NAT, S3, data transfer
- Right-sizing, spot instances, savings plans

### Understand the concept
Cost spike = unexpected usage increase. Investigation: Cost Explorer (service, linked account, tag), CUR (Athena), tagging enforcement. Optimization: compute (right-size, spot, savings plans), storage (gp3, lifecycle), network (VPC endpoints, CloudFront), idle resources.

### The actual answer
**Investigation**:
1. **Cost Explorer** — group by Service, filter by tag `Environment:production`, time range
2. **CUR + Athena** — granular: `line_item_usage_account_id`, `line_item_resource_id`, `product_region`
3. **Tagging** — enforce `Project`, `Team`, `Environment` tags on all resources
4. **EKS specific**: `kubectl top nodes` — utilization; `kubectl get pv` — unused EBS

**Optimization**:
- EC2: Right-size (Compute Optimizer), Spot (fault-tolerant), Savings Plans (steady)
- EBS: gp3 (cheaper, faster), delete unattached, snapshot lifecycle
- NAT Gateway: VPC endpoints (S3, DynamoDB, ECR) — $0.045/GB vs $0.045/hr + data
- S3: Intelligent-Tiering, lifecycle to Glacier
- EKS: Cluster Autoscaler + mixed instances policy

### Practical commands / examples
```bash
# EKS node utilization
kubectl top nodes

# Unattached EBS volumes
aws ec2 describe-volumes --filters Name=status,Values=available --query 'Volumes[*].{ID:VolumeId,Size:Size,AZ:AvailabilityZone}'

# NAT Gateway data transfer (Cost Explorer CLI)
aws ce get-cost-and-usage --time-period Start=2024-01-01,End=2024-01-31 --granularity MONTHLY --metrics BlendedCost --group-by Type=DIMENSION,Key=SERVICE

# VPC endpoints check
aws ec2 describe-vpc-endpoints --filters Name=vpc-id,Values=vpc-12345
```
**What to look for**: Low CPU% on nodes = over-provisioned; available EBS = waste; NAT Gateway data $ = VPC endpoints missing.

### Key takeaway
- Tag everything; Cost Explorer by tag = accountability
- NAT Gateway = expensive; VPC endpoints for AWS services
- gp3 > gp2 for EBS; Savings Plans > Reserved Instances (flexible)
- Cluster Autoscaler + mixed instances = automatic right-sizing

---

## Q26: Security incident: suspicious pod / crypto miner detected. Response steps?

### What is this question actually asking?
- Incident response: contain, investigate, eradicate, recover
- Runtime security (Falco, Tetragon), admission control
- Forensics: image, process, network, volumes

### Understand the concept
Crypto miner = high CPU, unknown process, outbound connections to mining pools. Response: isolate (network policy, cordon), capture evidence (image, logs, memory), analyze (image scan, process tree), remediate (remove, patch, rotate creds), improve (admission policies, runtime monitoring).

### The actual answer
**Immediate containment**:
1. `kubectl cordon <node>` — stop new pods
2. `kubectl drain <node> --ignore-daemonsets --delete-emptydir-data` — evict pods
3. NetworkPolicy: deny all egress from suspicious pod/namespace
4. Capture: `kubectl cp <pod>:/proc/<pid>/exe ./miner-binary` (if accessible)

**Investigation**:
5. Image scan: `trivy image <image>` — vulnerabilities, malware
6. Process: `kubectl exec <pod> -- ps auxf` — process tree
7. Network: `kubectl exec <pod> -- ss -tulpn` — connections
8. Check admission: OPA/Gatekeeper policies allowed this?

**Remediation**:
9. Delete pod, deployment; rotate any exposed secrets
10. Patch vulnerability; update base image
11. Deploy runtime security (Falco/Tetragon) for future detection

### Practical commands / examples
```bash
# Isolate node
kubectl cordon suspicious-node
kubectl drain suspicious-node --ignore-daemonsets --delete-emptydir-data

# NetworkPolicy deny egress
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress
  namespace: compromised-ns
spec:
  podSelector: {}
  policyTypes:
  - Egress
EOF

# Inspect pod
kubectl exec suspicious-pod -n ns -- ps auxf
kubectl exec suspicious-pod -n ns -- ss -tulpn

# Image scan
trivy image suspicious-image:tag
```
**What to look for**: High CPU + unknown binary + outbound to mining pool IPs; Falco rules trigger on `execve` of unknown binaries; image scan shows malicious layers.

### Key takeaway
- Contain first (cordon, NetworkPolicy); investigate second
- Capture forensic evidence before deleting
- Runtime security (Falco/Tetragon) = detection, not prevention
- Admission policies (OPA) = prevent deployment of unscanned images

---

## Q27: GitOps drift detected (Argo CD shows OutOfSync). How to handle?

### What is this question actually asking?
- Drift sources: manual kubectl, Helm, other controllers
- Argo CD diff, sync options, auto-heal
- Prevention: RBAC, read-only GitOps

### Understand the concept
GitOps = Git is source of truth. Drift = cluster ≠ Git. Argo CD detects via periodic comparison (default 3 min). `OutOfSync` = diff exists. Resolution: sync to Git (preferred) or update Git to match cluster (if intentional).

### The actual answer
**Process**:
1. `argocd app get <app>` — check `Sync Status: OutOfSync`
2. `argocd app diff <app>` — see exact differences
3. Determine source: manual `kubectl apply`? Helm release? Another controller?
4. **If unintentional**: `argocd app sync <app> --prune` — restore Git state
5. **If intentional**: update Git manifests to match desired state, then sync
6. Enable `autoPrune` and `selfHeal` in Application spec for auto-correction

### Practical commands / examples
```bash
# App status
argocd app get myapp

# Detailed diff
argocd app diff myapp

# Sync with prune (removes resources not in Git)
argocd app sync myapp --prune

# Enable auto-heal in Application spec
# spec:
#   syncPolicy:
#     automated:
#       prune: true
#       selfHeal: true
```
**What to look for**: `diff` shows `+`, `-`, `~` changes; `selfHeal` = auto-sync on drift; `prune` = delete orphaned resources.

### Key takeaway
- Git = source of truth; cluster should match Git
- `diff` before `sync` to understand impact
- `selfHeal` + `prune` = automatic drift correction
- Prevent drift: RBAC restrict `kubectl apply`, require PR for changes

---

## Q28: OPA Gatekeeper policy rejects valid resource. How to debug?

### What is this question actually asking?
- ConstraintTemplate, Constraint, violation messages
- Rego policy logic, input review, dry-run
- Audit vs enforcement mode

### Understand the concept
Gatekeeper = admission controller using OPA/Rego. ConstraintTemplate defines policy schema; Constraint instantiates it. Rejection = `deny` rule matched. Debug: check violation message, review Rego logic, test with `opa eval`, check audit results.

### The actual answer
**Debug steps**:
1. `kubectl get constraint <name> -o yaml` — check `status.violations`
2. `kubectl get constrainttemplate <name> -o yaml` — view Rego source
3. `opa eval -i input.json -d policy.rego "data.policy.deny"` — test locally
4. Check Gatekeeper logs: `kubectl logs -n gatekeeper-system -l control-plane=audit-controller`
5. Audit mode: violations reported but not blocked (set `enforcementAction: dryrun`)

### Practical commands / examples
```bash
# Violations
kubectl get constraint required-labels -o yaml

# ConstraintTemplate Rego
kubectl get constrainttemplate requiredlabels -o yaml | grep -A 50 rego:

# Local test with OPA
cat > input.json <<'EOF'
{"review": {"object": {"metadata": {"labels": {"env": "prod"}}}}}
EOF
opa eval -i input.json -d policy.rego "data.policy.deny"

# Gatekeeper audit logs
kubectl logs -n gatekeeper-system -l control-plane=audit-controller --tail=50
```
**What to look for**: `msg` in violation = custom message from Rego; `enforcementAction: deny` (block) vs `dryrun` (audit); Rego `input.review.object` = resource being admitted.

### Key takeaway
- Violations in Constraint `status` = what failed
- Test Rego locally with `opa eval` before deploying
- `dryrun` mode = safe testing in production
- Gatekeeper audit = periodic scan of existing resources

---

## Q29: Service mesh (Istio/Linkerd) sidecar injection fails / breaks app. Debug?

### What is this question actually asking?
- Sidecar injection: namespace label, pod annotation
- mTLS, traffic policies, resource limits
- Proxy logs, config sync, readiness

### Understand the concept
Service mesh injects sidecar proxy (Envoy) into pods. Injection: namespace label `istio-injection=enabled` or pod annotation. Failures: resource limits too low for sidecar, mTLS mode mismatch (STRICT vs PERMISSIVE), proxy config not synced, app not compatible (lifecycle, ports).

### The actual answer
**Debug steps**:
1. `kubectl get pod <pod> -n <ns> -o yaml` — check for `istio-proxy` / `linkerd-proxy` container
2. `kubectl describe pod <pod> -n <ns>` — events: injection failed?
3. Namespace label: `kubectl get ns <ns> --show-labels`
4. Proxy logs: `kubectl logs <pod> -c istio-proxy -n <ns>`
5. mTLS: `istioctl x authz check <pod>` / `linkerd check`
6. Resources: sidecar needs CPU/memory; check `resources.limits`

### Practical commands / examples
```bash
# Check sidecar injection
kubectl get pod myapp-xyz -n production -o jsonpath='{.spec.containers[*].name}'

# Namespace label
kubectl get ns production --show-labels

# Istio proxy logs
kubectl logs myapp-xyz -c istio-proxy -n production --tail=50

# Istio authz check
istioctl x authz check myapp-xyz -n production

# Linkerd check
linkerd check --proxy-pod myapp-xyz -n production

# Pod resources (sidecar needs ~100m CPU, 128Mi memory)
kubectl get pod myapp-xyz -n production -o yaml | grep -A 10 resources
```
**What to look for**: Missing sidecar = injection not enabled; Proxy logs = config fetch errors, upstream connect; `istioctl authz` = mTLS policy; Resource limits = OOMKilled sidecar.

### Key takeaway
- Injection = namespace label or pod annotation
- Sidecar consumes resources; set limits accordingly
- mTLS STRICT = all traffic encrypted; PERMISSIVE = plaintext allowed
- Proxy logs = primary debug source for mesh issues

---

## Q30: Complete system failure: API server down, etcd corrupted, cluster unreachable. Disaster recovery?

### What is this question actually asking?
- etcd backup/restore, control plane recovery
- EKS managed control plane vs self-managed
- Runbook, RTO/RPO, testing

### Understand the concept
Complete failure = control plane unavailable. EKS: AWS manages control plane; you recover worker nodes. Self-managed: etcd backup/restore critical. Disaster recovery = documented runbook, tested backups, RTO (recovery time objective), RPO (recovery point objective).

### The actual answer
**EKS (managed control plane)**:
1. AWS restores control plane automatically (multi-AZ)
2. Your responsibility: worker nodes, add-ons, applications
3. Recreate node groups: `eksctl create nodegroup` / Terraform apply
4. Argo CD sync restores applications from Git

**Self-managed (etcd backup/restore)**:
1. etcd snapshot: `etcdctl snapshot save backup.db`
2. Restore: `etcdctl snapshot restore backup.db --data-dir /var/lib/etcd`
3. Recreate static pods (kube-apiserver, controller-manager, scheduler)
4. Verify: `kubectl get nodes`, `kubectl get pods -A`

**General**:
- Runbook: step-by-step, tested quarterly
- RTO: 30 min (EKS) / 2-4 hrs (self-managed)
- RPO: etcd snapshot interval (5 min? 15 min?)
- GitOps = application recovery automatic

### Practical commands / examples
```bash
# EKS: recreate nodegroup
eksctl create nodegroup --cluster=my-cluster --name=ng-1 --instance-type=m5.large --nodes=3

# Terraform: re-apply node resources
terraform apply -target=module.eks_nodes

# Self-managed: etcd snapshot
etcdctl --endpoints=https://127.0.0.1:2379 snapshot save /backup/etcd-$(date +%F).db

# Self-managed: restore
etcdctl snapshot restore /backup/etcd-2024-01-15.db --data-dir /var/lib/etcd

# Verify cluster
kubectl get nodes -o wide
kubectl get pods -A
```
**What to look for**: EKS control plane = AWS responsibility; node group = your Terraform/eksctl; etcd snapshot = point-in-time; GitOps = app recovery.

### Key takeaway
- EKS: control plane HA managed by AWS; recover nodes + apps
- Self-managed: etcd backup/restore = critical skill
- GitOps = Argo CD reapplies desired state automatically
- Test DR runbook regularly; measure RTO/RPO

---