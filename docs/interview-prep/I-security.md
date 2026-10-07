# Interview Prep — I: Security

> **Purpose**: Self-learning and revision document. These are not scripted interview answers — they are explanations to help you understand concepts and remember how they work in practice.

---

## Q1. What is the principle of least privilege and how do you apply it in this platform?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the foundational security principle
- They want to see specific, concrete examples from your repo — not a generic definition

### 2. Understand the concept
Least privilege means: give each component exactly the permissions it needs to do its job — nothing more. If a database user only needs to read, don't give it write access. If a CI pipeline only needs to create EC2 instances, don't give it access to billing or RDS.

### 3. The actual answer
Least privilege applied across your platform:

| Component | What it needs | What you gave it |
|-----------|--------------|-----------------|
| **GitHub Actions IAM role** | Create/manage EC2, EKS, KMS, IAM, VPC | Custom inline policy with only those actions (replaced AdministratorAccess) |
| **EKS cluster IAM role** | Manage EKS infrastructure | `AmazonEKSClusterPolicy` only |
| **EKS node IAM role** | Pull images, join cluster, VPC networking | `AmazonEKSWorkerNodePolicy` + `AmazonEKS_CNI_Policy` + `AmazonEC2ContainerRegistryReadOnly` |
| **Spring Boot pod** | Serve HTTP traffic | No Kubernetes API access (`automountServiceAccountToken: false`) |
| **Container user** | Run the JAR | Non-root system user (`appuser`) with no shell |
| **Container capabilities** | None needed | `drop: ALL` |

GitHub OIDC trust policy also scopes access:
```hcl
"token.actions.githubusercontent.com:sub" = "repo:pravinmoreone-ux/pravin-devops-platform:ref:refs/heads/main"
```
Only the `main` branch of that specific repo can assume the role — not any GitHub Actions job.

### 4. Key takeaway
- Least privilege = minimum permissions needed, nothing more
- Applied at: IAM roles (AWS), container capabilities (K8s), service accounts (K8s), OIDC trust (CI)
- Think about it in layers: cloud account → Kubernetes → container → process → network
- Reduces blast radius: if component is compromised, damage is limited to its permissions

---

## Q2. What is IAM OIDC and why is it more secure than using AWS access keys in CI/CD?

### 1. What is this question actually asking?
- The interviewer is specifically asking about the keyless authentication pattern
- They want to understand the specific security improvement over static credentials

### 2. Understand the concept
Static AWS access keys are a fixed username/password for AWS. If they're leaked (CI logs, GitHub history, code), an attacker has permanent access until you manually revoke and rotate them. OIDC-based authentication issues short-lived tokens — even if intercepted, they expire in an hour.

### 3. The actual answer
Security comparison:

| | Static AWS Access Keys | OIDC Federated Identity |
|--|----------------------|------------------------|
| Stored where | GitHub Secrets (long-lived) | Nowhere — generated per-run |
| Lifetime | Until manually revoked | ~1 hour |
| If leaked | Permanent access | Useless after expiry |
| Audit trail | All requests look the same | Includes GitHub run ID, repo, branch |
| Rotation | Manual (often forgotten) | Automatic (new token each run) |
| Scope | Account-wide | Scoped to specific repo + branch |

How OIDC works in your setup:
1. GitHub generates a signed JWT for the job (`id-token: write` permission)
2. The JWT contains: repo name, branch, run ID — signed by GitHub's OIDC provider
3. GitHub Actions calls AWS STS `AssumeRoleWithWebIdentity` with this JWT
4. AWS verifies the JWT signature against GitHub's OIDC public keys
5. AWS checks the `sub` claim matches your trust policy condition
6. AWS returns temporary credentials (valid ~1 hour)
7. Workflow uses these credentials
8. Job finishes → credentials expire

Even if an attacker captures the token mid-run, it expires in under an hour and is scoped only to that specific role (not your entire AWS account).

### 4. Key takeaway
- OIDC = no long-lived secrets stored anywhere in CI
- Temporary credentials expire after ~1 hour — minimal blast radius
- JWT contains job context — full audit trail in CloudTrail
- Trust policy scoped to specific repo + branch — not all of GitHub
- This is the AWS-recommended pattern for CI/CD authentication

---

## Q3. What is IMDSv2 and why is it enforced on your EC2 instances?

### 1. What is this question actually asking?
- The interviewer is testing your knowledge of EC2 metadata security
- They want to know what specific attack IMDSv2 prevents

### 2. Understand the concept
EC2 Instance Metadata Service (IMDS) is a local service that EC2 instances can query to get information about themselves — including IAM role credentials. Any process on the instance (including a compromised web app) can make a simple HTTP call to `http://169.254.169.254/latest/meta-data/iam/...` and get the instance's IAM credentials.

IMDSv1 was vulnerable to Server-Side Request Forgery (SSRF) attacks — if an attacker could trick your web app into making an HTTP request to that address, they could steal the IAM credentials. IMDSv2 requires a session token obtained via a PUT request first, which SSRF attacks can't replicate.

### 3. The actual answer
In your Terraform:
```hcl
metadata_options {
  http_tokens = "required"   # IMDSv2 required
}
```

**IMDSv1 attack scenario**:
1. Web app has SSRF vulnerability
2. Attacker tricks app: `GET http://169.254.169.254/latest/meta-data/iam/security-credentials/my-role`
3. App makes the request (it's just an HTTP GET)
4. Attacker gets IAM credentials
5. Attacker can now act as the EC2 instance's IAM role

**IMDSv2 protection**:
1. Must first call: `PUT http://169.254.169.254/latest/api/token` with a `TTL-Seconds` header
2. Get a session token
3. Use that token in subsequent requests
4. SSRF attacks can't do PUT requests (typically exploit GET-based redirect vulnerabilities)

With `http_tokens = "required"`, IMDSv1 is completely disabled — all metadata requests must use the session token flow.

### 4. Key takeaway
- IMDS = EC2 local metadata service that provides IAM credentials to instance
- IMDSv1 = vulnerable to SSRF (simple HTTP GET steals credentials)
- IMDSv2 = requires PUT + session token first (blocks SSRF attacks)
- `http_tokens = "required"` = IMDSv2 enforced, IMDSv1 completely disabled
- Also set in Trivy policy check — enforced by both OPA and Trivy IaC scan

---

## Q4. What is KMS encryption for Kubernetes secrets and what does it protect against?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand what etcd encryption protects
- They want to know the specific threat model — not just "it's more secure"

### 2. Understand the concept
Kubernetes stores all cluster state (including Secrets) in etcd. By default, Secrets in etcd are only base64-encoded — which is not encryption. Anyone with access to the etcd datastore (or an etcd backup) can read all Secrets. KMS encryption adds real encryption so etcd data is unreadable without the KMS key.

### 3. The actual answer
What it protects against:
1. **Direct etcd access**: If someone accesses the etcd database files (on the control plane node), Secrets are encrypted — unreadable without the KMS key
2. **Backup theft**: etcd backups contain encrypted data — stolen backup is useless without KMS access
3. **Cloud provider insider**: Even AWS staff with access to the underlying storage can't read your Secrets

How envelope encryption works:
```text
1. Kubernetes generates a Data Encryption Key (DEK) for each Secret
2. Encrypts the Secret value with the DEK using AES-256
3. Calls KMS to encrypt the DEK with your Customer Master Key (CMK)
4. Stores: encrypted Secret value + encrypted DEK in etcd

To read:
1. Retrieve encrypted DEK from etcd
2. Call KMS to decrypt the DEK (requires IAM permission to use KMS key)
3. Use decrypted DEK to decrypt the Secret value
```

Access control: Only the EKS cluster role has `kms:CreateGrant` + `kms:DescribeKey` permissions — not your developers, not GitHub Actions.

Your KMS key also has `enable_key_rotation = true` — AWS automatically rotates the key annually.

### 4. Key takeaway
- Without KMS: Secrets in etcd are base64 (trivially decoded)
- With KMS: Secrets encrypted with AES-256, key managed by KMS
- Protects against: etcd backup theft, direct datastore access, insider threats
- Key rotation enabled — annual automatic rotation without service interruption

---

## Q5. What is Trivy and what are the differences between its scan modes?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the full scope of what Trivy scans
- They are checking if you know more than just container scanning

### 2. Understand the concept
Trivy is a comprehensive security scanner by Aqua Security. It was initially a container image scanner but now scans multiple targets: images, filesystems, Git repos, IaC files, Kubernetes configs, and more. In your repo, you use two modes: IaC scanning (Terraform) and container image scanning.

### 3. The actual answer
Trivy scan types:

| Mode | Command | What it scans |
|------|---------|---------------|
| Container image | `trivy image nginx:latest` | OS packages + language packages in image |
| Filesystem | `trivy fs /app` | Files on local filesystem |
| Config (IaC) | `trivy config terraform/` | Terraform, Kubernetes YAML, Dockerfile misconfigs |
| Repository | `trivy repo https://github.com/...` | Git repo (code + config + images) |
| Kubernetes | `trivy k8s cluster` | Running cluster resources |
| SBOM | `trivy sbom app.jar` | Software Bill of Materials |

In your pipeline:

**IaC scan** (Terraform CI):
```bash
trivy config . --severity HIGH,CRITICAL --exit-code 1 --ignorefile ../.trivyignore
```
Checks: unencrypted EBS, public S3, open security groups, missing IMDSv2, etc.

**Container scan** (Spring Boot CI):
```bash
trivy image --severity HIGH,CRITICAL --exit-code 1 "${IMAGE_NAME}:${TAG}"
```
Checks: CVEs in Alpine packages, CVEs in Java dependencies (Spring Boot, Tomcat, Jackson).

Trivy uses databases from:
- NVD (National Vulnerability Database)
- RedHat Security Advisories
- GitHub Advisory Database
- OSV (Open Source Vulnerabilities)

### 4. Key takeaway
- Trivy = multi-target security scanner (images, IaC, filesystems, K8s)
- Your repo uses two modes: `trivy config` (IaC) + `trivy image` (container)
- `--exit-code 1` = pipeline fails on findings → security quality gate
- `.trivyignore` = suppress known acceptable findings with documented justification

---

## Q6. What is OPA (Open Policy Agent) and what is Rego?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand policy-as-code and where OPA fits
- They are testing whether you know the difference between OPA the engine and Rego the language

### 2. Understand the concept
OPA is a general-purpose policy engine. You give it data (like a Terraform plan, a Kubernetes admission request, or an API request body) and rules written in Rego, and it tells you: allow or deny? Pass or fail? What violations exist?

### 3. The actual answer
**OPA** is the engine — a general-purpose policy evaluator. It takes:
- Input: JSON data to evaluate (your `tfplan.json`)
- Policy: Rules written in Rego
- Returns: policy decision (deny messages, allow/deny)

**Rego** is the declarative policy language. Example from your repo:
```rego
package terraform.security

deny[msg] {
  resource := input.resource_changes[_]    # iterate over all resources
  resource.type == "aws_instance"          # find EC2 instances
  resource.change.after.metadata_options.http_tokens != "required"  # check IMDSv2
  msg := sprintf("EC2 '%s' must require IMDSv2", [resource.address])  # violation message
}
```

How it reads:
- "For each resource change in input"
- "If it's an aws_instance"
- "AND its http_tokens is not 'required'"
- "THEN add this message to the deny set"

OPA integrations:
| Use case | What OPA evaluates |
|----------|-------------------|
| Terraform (your repo) | Terraform plan JSON |
| Kubernetes admission | Pod/Deployment specs (via OPA Gatekeeper) |
| API authorization | API request + user identity |
| CI/CD gates | Build artifacts, config files |

### 4. Key takeaway
- OPA = general-purpose policy engine (not Kubernetes-specific)
- Rego = declarative language for writing policies
- Input data + Rego rules = policy decision
- In your repo: Terraform plan JSON → OPA → allow/deny based on security rules
- Rego is logic-based: rules build on rules, no imperative control flow

---

## Q7. What is the difference between Trivy and OPA in your pipeline?

### 1. What is this question actually asking?
- The interviewer wants to know if you can explain why you use both — what gap each fills
- They are testing whether you understand the complementary nature of the two tools

### 2. Understand the concept
Trivy and OPA both scan your infrastructure code, but they serve different purposes. Trivy catches known misconfigurations from a pre-built database. OPA enforces your organization's specific business rules that no pre-built tool would know about.

### 3. The actual answer

| | Trivy | OPA |
|--|-------|-----|
| Rule source | Pre-built database (AWS best practices, CIS benchmarks) | Your custom Rego rules |
| Flexibility | Fixed rules (you suppress, not customize) | Fully customizable |
| Effort | Zero setup for base rules | Must write rules yourself |
| Examples | "EBS not encrypted", "SG open to internet" | "Only t3.small/medium/large allowed", "All resources must have Project tag" |
| Updates | Auto-updated from security databases | You update when requirements change |

They complement each other:
- Trivy: "Is this configuration known to be insecure by the security community?"
- OPA: "Does this configuration comply with our internal policies?"

Example: Trivy would flag an unencrypted EBS (known AWS bad practice). OPA would flag an unapproved instance type (your organization's policy — Trivy doesn't know your approved list).

Both run in your Terraform CI pipeline — both must pass for deployment to proceed.

### 4. Key takeaway
- Trivy = pre-built security database rules (zero setup, community maintained)
- OPA = custom business rules (requires writing Rego, fully flexible)
- Trivy catches: known insecure configs, CVEs, CIS benchmark violations
- OPA enforces: organizational policies, approved resource types, naming conventions
- Both needed: Trivy for known bad, OPA for your-specific requirements

---

## Q8. What is a security group's rule using `security_groups` instead of `cidr_blocks`?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of security group referencing
- They want to know the advantage of referencing a security group vs hardcoding an IP

### 2. Understand the concept
In your app server's security group, SSH is allowed not from an IP address but from the jump server's security group. This is a more flexible and maintainable approach than hardcoding IPs — if the jump server's IP changes (e.g., it's replaced), the rule still works because it references the security group, not the IP.

### 3. The actual answer
Your `security_groups.tf`:
```hcl
resource "aws_security_group" "app" {
  ingress {
    description     = "SSH from jump server"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.jump.id]  # reference SG, not IP
  }
}
```

vs CIDR-based:
```hcl
ingress {
  cidr_blocks = ["10.40.1.15/32"]  # hardcoded IP — breaks if jump server changes
}
```

Benefits of security group referencing:
- **Dynamic**: Works for any instance in the jump SG — IP doesn't matter
- **Automatic**: New jump servers joining the SG immediately get access
- **Auditable**: "What can reach app server?" → "Only instances in jump-sg"
- **No IP management**: No need to update rules when jump server is replaced

### 4. Key takeaway
- Reference security groups instead of IPs for internal traffic
- More resilient: IP changes don't require rule updates
- More readable: "allow from jump-sg" is clearer than an IP address
- Use CIDR blocks only for external IPs (your admin IP for SSH)

---

## Q9. What is the `readOnlyRootFilesystem` security context and what does it prevent?

### 1. What is this question actually asking?
- The interviewer wants to know the specific threat that read-only root filesystem mitigates
- They are checking whether you applied this consciously

### 2. Understand the concept
If a container runs with a writable root filesystem (default), a compromised application could write scripts to `/tmp`, install tools like `curl` or `nc`, modify configuration files, or create backdoors. Making the root filesystem read-only eliminates this attack vector — the container's filesystem is immutable at runtime.

### 3. The actual answer
In your deployment:
```yaml
securityContext:
  readOnlyRootFilesystem: true
```

What this prevents:
- Writing malicious scripts to `/tmp`, `/var`, `/etc`
- Installing attacker tools (`curl`, `wget`, `python`)
- Modifying application configuration files
- Tampering with the JVM classpath

What the app still needs:
- **`/tmp`**: JVM writes native libraries and temp files here → solved with `emptyDir` volume
- **Nothing else**: Spring Boot jar runs in memory, reads from `/app/app.jar`

```yaml
volumeMounts:
  - name: tmp
    mountPath: /tmp

volumes:
  - name: tmp
    emptyDir:
      medium: Memory   # RAM-backed, faster, no persistence
```

Combined with `capabilities: drop: ALL`, the container has minimum filesystem and kernel access.

### 4. Key takeaway
- Read-only root filesystem = container can't write files to its own filesystem
- Attacker can't install tools, write scripts, or create backdoors
- JVM needs writable `/tmp` → solve with emptyDir volume
- `medium: Memory` = RAM-backed temp storage (faster, no disk I/O, ephemeral)
- This is the production Kubernetes security standard for application containers

---

## Q10. What is `allowPrivilegeEscalation: false` and what does `setuid` have to do with it?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the specific mechanism of privilege escalation
- They are testing deeper Linux security knowledge

### 2. Understand the concept
In Linux, certain programs have a special bit set (setuid) that lets them run as a different user than who launched them. For example, `passwd` runs as root even when launched by a normal user — it needs root to modify `/etc/shadow`. If your container has such binaries and `allowPrivilegeEscalation` is enabled, a compromised process could exploit them to gain root access.

### 3. The actual answer
`allowPrivilegeEscalation: false` prevents:
- Child processes from gaining more privileges than their parent process
- `setuid`/`setgid` binaries from being used to escalate to root
- `sudo` from working inside the container (even if installed)

Technically implemented as: sets `no_new_privs` flag on the process, which prevents privilege escalation through any mechanism.

Combined effect with your other security contexts:
```yaml
runAsNonRoot: true                # starts as non-root
allowPrivilegeEscalation: false   # can't escalate to root
readOnlyRootFilesystem: true      # can't install new tools
capabilities:
  drop: [ALL]                     # no kernel capabilities
```

This creates defense-in-depth: even if an attacker exploits a Spring Boot vulnerability, they're stuck as a non-root user with no capabilities, no way to escalate, and a read-only filesystem.

### 4. Key takeaway
- `allowPrivilegeEscalation: false` = process can't gain more permissions than it started with
- Prevents `setuid` exploitation, `sudo` usage, any privilege escalation mechanism
- Implemented via Linux `no_new_privs` flag
- Combined with `runAsNonRoot` + `readOnlyRootFilesystem` + `drop ALL` = comprehensive container hardening

---

## Q11. What are Linux capabilities and why do you `drop: ALL` in your containers?

### 1. What is this question actually asking?
- The interviewer is testing your knowledge of Linux security model
- They want to know what capabilities are and why removing them matters

### 2. Understand the concept
In Linux, root access is not a single binary privilege — it's divided into ~40 individual capabilities. A process can have some capabilities without being fully root. Capabilities include things like: bind to ports below 1024 (`NET_BIND_SERVICE`), load kernel modules (`SYS_MODULE`), change network configuration (`NET_ADMIN`), set system time (`SYS_TIME`).

By default, Docker containers get a small set of capabilities. `drop: ALL` removes even these.

### 3. The actual answer
In your deployment:
```yaml
capabilities:
  drop:
    - ALL
```

What capabilities you're removing:

| Capability | What it allows |
|-----------|---------------|
| `NET_RAW` | Raw network access (packet sniffing, ARP spoofing) |
| `NET_BIND_SERVICE` | Bind to ports < 1024 |
| `SYS_PTRACE` | Debug/trace other processes |
| `AUDIT_WRITE` | Write to kernel audit log |
| `KILL` | Send signals to arbitrary processes |
| `MKNOD` | Create device files |
| and 30+ others | ... |

Your Spring Boot app runs on port 8080 (>1024) — doesn't need `NET_BIND_SERVICE`.
It doesn't monitor other processes — doesn't need `SYS_PTRACE`.
It doesn't need raw network access — doesn't need `NET_RAW`.

`drop: ALL` removes all capabilities — the container process has only the standard POSIX permissions of the user it runs as (non-root appuser).

If you needed a capability: add it explicitly with `add: [NET_BIND_SERVICE]` — principle of least privilege.

### 4. Key takeaway
- Linux capabilities = granular root-level privileges (40 individual capabilities)
- Default Docker containers have a subset of capabilities
- `drop: ALL` = remove all capabilities — minimum privilege
- Spring Boot needs none of them — it's a JVM app on port 8080
- Add capabilities explicitly only when needed: `capabilities: add: [SPECIFIC_CAP]`

---

## Q12. What is a Kubernetes NetworkPolicy and what does your default-deny do?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand pod-level network isolation
- They are testing the practical implementation of network segmentation in Kubernetes

### 2. Understand the concept
By default, all pods in Kubernetes can communicate with all other pods across all namespaces — there's no network isolation. If your Spring Boot pod is compromised, it could reach the Prometheus database, the Loki backend, or even other services in completely different namespaces. NetworkPolicy lets you define what traffic is allowed.

### 3. The actual answer
Your `networkpolicy.yaml`:
```yaml
spec:
  podSelector:
    matchLabels:
      app: springboot
  policyTypes:
    - Ingress   # only controls inbound traffic to springboot pods
                # no ingress rules = deny all inbound
```

This is a **default-deny** for ingress: because `policyTypes` includes `Ingress` but there are no `ingress:` rules, ALL inbound traffic to Spring Boot pods is blocked.

To allow traffic (e.g., from a load balancer or frontend):
```yaml
spec:
  podSelector:
    matchLabels:
      app: springboot
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx    # only from ingress controller namespace
      ports:
        - port: 8080
```

**Important limitation**: NetworkPolicy requires the CNI plugin to enforce it. AWS VPC CNI supports NetworkPolicy but it needs to be enabled. Without a supporting CNI (or with it disabled), NetworkPolicy rules are silently ignored.

### 4. Key takeaway
- NetworkPolicy = pod-level firewall (ingress + egress rules)
- No NetworkPolicy = all pods can reach all pods (default open)
- Default-deny ingress: specify `policyTypes: [Ingress]` with no rules → blocks all inbound
- Requires CNI support (VPC CNI with network policy enabled, or Calico)
- Start with default-deny, then explicitly allow what's needed

---

## Q13. What is the `PodDisruptionBudget` and how does it relate to security/availability?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand PDB as both an availability and a DoS-prevention tool
- They are checking whether you can explain the relationship between availability and security

### 2. Understand the concept
PDB is primarily an availability tool — it prevents Kubernetes from taking down too many pods at once during maintenance. But it also has a security angle: without a PDB, a node drain (intentional or malicious) could take your entire application offline simultaneously.

### 3. The actual answer
Your `pdb.yaml`:
```yaml
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: springboot
```

Protection provided:
1. **Node upgrades**: Kubernetes node rolling upgrades drain pods one by one — PDB ensures 1 stays up
2. **Voluntary evictions**: `kubectl drain node` respects PDB — won't evict past minimum
3. **Availability during incidents**: Prevents accidental full-service takedown

What PDB does NOT protect against:
- **Node failure** (hardware crash) — that's a Kubernetes self-healing/HA concern
- **Involuntary disruptions** — if a node dies, pods on it die regardless of PDB

Combined with topology spread constraints:
```yaml
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
```

Pods on different nodes → if one node is drained, the other pod is on a separate node and keeps running → PDB's `minAvailable: 1` is satisfied.

### 4. Key takeaway
- PDB = minimum pod availability guarantee during voluntary disruptions
- `minAvailable: 1` with 2 replicas = rolling node drains always leave 1 pod running
- Requires replicas on different nodes (topology spread) to be effective
- PDB only protects against voluntary disruptions (drains) — not hardware failures

---

## Q14. What is a `.trivyignore` file and when is it acceptable to suppress findings?

### 1. What is this question actually asking?
- The interviewer is testing your security judgment — not just whether you know the file exists
- They want to know if you understand that suppressions need justification

### 2. Understand the concept
Not every Trivy finding is something you can immediately fix or something that poses a real risk in your context. Accepted risk — when you understand the risk, have mitigations in place, and consciously decide not to fix it — needs to be documented. Suppressing without documentation is dangerous because future engineers won't know why.

### 3. The actual answer
Your `.trivyignore`:
```text
# AWS-0104: Unrestricted egress is intentionally allowed for the jump and private app servers.
# Jump server requires outbound AWS/GitHub/tooling access.
# App server requires outbound access through NAT for package updates and dependencies.
# Production hardening: replace broad egress with VPC endpoints and controlled egress/proxy.
AWS-0104
```

Good practices for suppressions:
1. **Document why**: Explain the business/technical reason
2. **Note the risk**: What could go wrong if this is exploited?
3. **State the mitigation**: What reduces the risk in your current setup?
4. **Plan to fix**: How will you address this in production?
5. **Review regularly**: Suppressions should be reviewed periodically

Bad suppression:
```text
# AWS-0104
```
No explanation — future engineers don't know if this was intentional or forgotten.

When suppression is acceptable:
- False positive (tool incorrectly flags something safe)
- Known limitation with documented production mitigation plan
- Test environment only (not production)
- Risk formally accepted by security team

### 4. Key takeaway
- `.trivyignore` = suppress specific Trivy findings by CVE/check ID
- Always document WHY you're suppressing — future you (and teammates) need to know
- Suppression ≠ ignoring the issue — it's formally accepting the risk with documented justification
- Review suppressions regularly — accepted risks change over time

---

## Q15. What is the `automountServiceAccountToken: false` setting and what threat does it mitigate?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand Kubernetes lateral movement attacks
- They are testing your awareness of the cluster API as an attack surface

### 2. Understand the concept
Every Kubernetes pod automatically receives a service account token inside it — even if the application never uses it. This token can make API calls to the Kubernetes API server. If an attacker compromises a pod, they can use this token to query the cluster, list secrets, potentially escalate to other namespaces, or even modify deployments.

### 3. The actual answer
Without `automountServiceAccountToken: false`:
- Token mounted at: `/var/run/secrets/kubernetes.io/serviceaccount/token`
- Default service account token has some permissions to read cluster state
- A compromised pod can: list pods, read configmaps, potentially enumerate secrets

With `automountServiceAccountToken: false`:
- No token mounted — the file doesn't exist
- Even if attacker gets shell in the pod, they have no Kubernetes API access

In your deployment:
```yaml
spec:
  automountServiceAccountToken: false
```

Your Spring Boot app is a REST service — it never needs to call the Kubernetes API. Disabling auto-mount is zero-impact on functionality, significant security improvement.

When you DO need a service account token:
- Argo CD: reads Git repos, manages K8s resources — needs API access
- Prometheus: scrapes pod annotations, service discovery — needs API access
- OTel Collector: enriches data with K8s metadata — needs read access

For these, create a specific ServiceAccount with only the needed RBAC permissions and enable token mounting only for those deployments.

### 4. Key takeaway
- Service account tokens enable pods to call the Kubernetes API
- Mounted by default — even if app doesn't use it
- Attacker in pod can use token for cluster reconnaissance and lateral movement
- `automountServiceAccountToken: false` = no token = no API access from compromised pod
- Enable tokens only for pods that genuinely need cluster API access (Argo CD, Prometheus, etc.)

---

## Q16. What is the shared responsibility model for EKS security?

### 1. What is this question actually asking?
- The interviewer wants to know if you can clearly articulate what AWS secures vs what you're responsible for
- This is a common enterprise security interview question

### 2. Understand the concept
EKS is a managed Kubernetes service. AWS manages the control plane. You manage everything on top of it. The line between AWS's responsibility and yours is clearly defined — misunderstanding this leads to security gaps.

### 3. The actual answer

**AWS is responsible for (EKS control plane)**:
- Physical infrastructure (servers, networking)
- EKS control plane HA and resilience
- Kubernetes API server security patches
- etcd encryption and backup
- Control plane audit logging to CloudWatch
- Kubernetes version patch management (you trigger upgrades, AWS patches)

**You are responsible for (data plane + configuration)**:
- Worker node OS security patches
- IAM roles and permissions for nodes and pods
- Security groups on nodes and pods
- NetworkPolicy configuration
- Pod security context (runAsNonRoot, capabilities, etc.)
- Secrets management (KMS encryption config = your choice)
- Container image security (Trivy scanning)
- RBAC for cluster access
- Kubernetes add-ons (CoreDNS, VPC CNI, kube-proxy updates)
- Application-level security (your Spring Boot code)

Your repo addresses many of these: private endpoint, KMS encryption, non-root pods, NetworkPolicy, security contexts, Trivy scanning, OPA policies.

### 4. Key takeaway
- AWS = control plane (API server, etcd, scheduler) — their security boundary
- You = everything else (worker nodes, pods, IAM, network policies, applications)
- "EKS is secure" means the control plane is secure — your workloads still need hardening
- Shared responsibility means neither party can fully substitute for the other's role

---

## Q17. What is RBAC in Kubernetes and how does it work?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand Kubernetes access control
- They are testing whether you know the Role/ClusterRole and Binding model

### 2. Understand the concept
Without RBAC, every user and service account that can reach the Kubernetes API has the same access — they can read/write anything. RBAC (Role-Based Access Control) defines who can do what to which resources. It's the fundamental authorization system for Kubernetes.

### 3. The actual answer
RBAC has four core objects:

| Object | Scope | Purpose |
|--------|-------|---------|
| `Role` | Namespace | Defines permissions within one namespace |
| `ClusterRole` | Cluster-wide | Defines permissions across all namespaces |
| `RoleBinding` | Namespace | Binds a Role to a user/SA in a namespace |
| `ClusterRoleBinding` | Cluster-wide | Binds a ClusterRole to a user/SA cluster-wide |

Example:
```yaml
# Allow read-only access to pods in default namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: default
rules:
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: default
subjects:
  - kind: ServiceAccount
    name: monitoring-sa
    namespace: monitoring
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

Prometheus needs to list pods across all namespaces for service discovery → uses `ClusterRole`.
Your Spring Boot app needs nothing → `automountServiceAccountToken: false`.

### 4. Key takeaway
- RBAC = who can do what to which K8s resources
- Role (namespace-scoped) + Binding = most common pattern
- ServiceAccount = identity for pods (like IAM role for EC2)
- Least privilege: give each service account only verbs it needs on only the resources it uses
- Check permissions: `kubectl auth can-i list pods --as system:serviceaccount:default:springboot`

---

## Q18. What is SonarCloud SAST and what class of vulnerabilities does it detect?

### 1. What is this question actually asking?
- The interviewer wants to know what SAST is and how it differs from runtime security
- They are testing your understanding of static code analysis

### 2. Understand the concept
SAST (Static Application Security Testing) analyzes source code without running it. It finds code patterns that are known to be insecure — like using `String.format()` with user input in a SQL query (SQL injection), or catching exceptions and swallowing them silently.

### 3. The actual answer
SonarCloud SAST detects:

| Category | Example |
|----------|---------|
| **Injection** | SQL injection, command injection, LDAP injection |
| **XSS** | Unsanitized user input written to HTTP response |
| **Hardcoded credentials** | `String password = "admin123"` in code |
| **Insecure randomness** | Using `Random` instead of `SecureRandom` for tokens |
| **Null dereference** | Likely NPE paths |
| **Resource leaks** | Unclosed streams, connections |
| **Insecure deserialization** | Reading untrusted serialized data |
| **Weak cryptography** | MD5, SHA1 for security purposes |

In your pipeline:
```yaml
- name: SonarCloud SAST
  run: mvn -B org.sonarsource.scanner.maven:sonar-maven-plugin:sonar
       -Dsonar.qualitygate.wait=true
```

`qualitygate.wait=true` = the pipeline blocks until SonarCloud analysis is complete and the quality gate verdict is returned. If new vulnerabilities are introduced, the pipeline fails before building the Docker image.

SonarCloud also measures code coverage from JaCoCo — ensuring new code has adequate test coverage.

### 4. Key takeaway
- SAST = find security issues in source code without running it
- SonarCloud detects: injection, XSS, hardcoded secrets, weak crypto, null dereferences
- Runs after tests (JaCoCo data available) — before Docker build
- Quality gate blocks pipeline if new vulnerabilities introduced
- Complements Trivy: SonarCloud = application code, Trivy = dependencies + IaC

---

## Q19. What is the difference between authentication and authorization?

### 1. What is this question actually asking?
- The interviewer is asking a foundational security concept question
- They are testing whether you can apply these concepts to the systems in your repo

### 2. Understand the concept
These are two separate steps in access control that are often confused. Authentication is proving identity. Authorization is determining what that identity is allowed to do.

### 3. The actual answer
**Authentication (AuthN)**: "Who are you?"
- Proves identity
- Examples: username/password, SSH key, OIDC token, AWS access key

**Authorization (AuthZ)**: "What are you allowed to do?"
- Determines permissions for a verified identity
- Examples: IAM policies, RBAC rules, security group rules, NetworkPolicy

Applied in your platform:

| System | Authentication | Authorization |
|--------|---------------|---------------|
| AWS (GitHub Actions) | OIDC JWT token verifies GitHub identity | IAM role policy defines allowed actions |
| EKS | `aws eks get-token` (AWS STS auth) | RBAC defines what kubectl commands allowed |
| GHCR | `GITHUB_TOKEN` verifies GitHub identity | Package write permission in workflow |
| Jump server | SSH key (proves you have the key) | Security group (only admin IP can reach port 22) |

Note: A security group controls access to a resource but does NOT authenticate — anyone reaching port 22 still needs SSH key auth.

### 4. Key takeaway
- Authentication = prove identity ("I am Pravin")
- Authorization = check permissions ("Pravin can do X but not Y")
- Both must be in place — authentication without authorization = everyone can do anything
- In AWS: IAM = both (identity via keys/OIDC, permissions via policies)
- In Kubernetes: kubeconfig/token = authentication, RBAC = authorization

---

## Q20. What would you check first if you suspected unauthorized access to your AWS account?

### 1. What is this question actually asking?
- This is a security incident response question
- The interviewer wants to see systematic thinking under pressure

### 2. Understand the concept
Unauthorized access investigation requires systematic evidence gathering. You need to know: what was accessed, from where, when, and what was done. AWS provides several services for this.

### 3. The actual answer
Investigation order:

**Step 1 — CloudTrail (primary audit log)**
```bash
# Find recent API calls by unknown identity
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=ConsoleLogin \
  --start-time 2024-01-01

# Check for suspicious API calls
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=iam.amazonaws.com
```
What to look for: Unusual IAM operations, new user creation, policy changes, calls from unexpected IPs.

**Step 2 — IAM Credential Report**
```bash
aws iam generate-credential-report
aws iam get-credential-report
```
What to look for: Access keys last used, passwords last changed.

**Step 3 — AWS GuardDuty findings** (if enabled)
Automated threat detection — shows: unusual API calls, compromised credentials, crypto mining, port scanning.

**Step 4 — EC2 Security Group audit**
Were any inbound rules changed to open unexpected ports?

**Step 5 — S3 bucket policies and ACLs**
Were any buckets made public?

**Immediate containment**:
- Revoke suspicious IAM credentials
- Rotate all access keys
- Enable MFA
- Isolate affected EC2 instances (change SG to deny all)

### 4. Key takeaway
- CloudTrail = first stop for AWS API audit logs (all API calls logged)
- GuardDuty = automated threat detection (if enabled)
- Incident response: Detect → Contain → Investigate → Eradicate → Recover
- Prevention: least privilege IAM, no root account usage, MFA everywhere, no long-lived keys

---

## Q21. What is defense-in-depth and how is it implemented in your platform?

### 1. What is this question actually asking?
- The interviewer wants to know if you think about security holistically
- They are checking whether you understand layered security

### 2. Understand the concept
Defense-in-depth means having multiple, independent layers of security. No single security control is perfect — each can be bypassed or fail. Multiple layers mean an attacker must overcome multiple independent barriers. If one fails, others remain.

### 3. The actual answer
Your platform has security at every layer:

```text
Layer 1: Network
  - Private subnets (EKS nodes not reachable from internet)
  - Security groups (restrict inbound/outbound per resource)
  - NAT Gateway (outbound only for private resources)
  - EKS private endpoint (API not exposed to internet)

Layer 2: Identity & Access
  - OIDC (no static credentials in CI)
  - Least-privilege IAM roles
  - IMDSv2 (prevents credential theft from EC2)
  - GitHub OIDC scoped to specific repo + branch

Layer 3: Infrastructure Configuration
  - OPA policies (block non-compliant infra at plan time)
  - Trivy IaC scan (block known misconfigs at plan time)
  - KMS encryption for EKS secrets
  - Encrypted EBS volumes

Layer 4: Container & Application
  - Non-root container user
  - Read-only root filesystem
  - Dropped all capabilities
  - No service account token
  - NetworkPolicy default-deny

Layer 5: Supply Chain
  - Immutable image tags (SHA-based)
  - Trivy container scan (block CVEs before push)
  - SonarCloud SAST (block code vulnerabilities)
  - Pinned Action versions in workflows
```

An attacker would need to: bypass network controls → compromise an identity → exploit a container → escape the container → pivot within the cluster → exfiltrate data. Each layer requires separate exploitation.

### 4. Key takeaway
- Defense-in-depth = multiple independent security layers
- No single layer is perfect — all can fail
- Your platform has security at: network, identity, infrastructure, container, supply chain
- Each layer adds cost and friction — balance security with usability
- When one layer fails, others continue to protect
