# Interview Prep — E: Docker & Containers

> **Purpose**: Self-learning and revision document. These are not scripted interview answers — they are explanations to help you understand concepts and remember how they work in practice.

---

## Q1. What is Docker and what problem does it solve?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the "works on my machine" problem
- They are testing whether you can explain containers vs virtual machines clearly

### 2. Understand the concept
Before containers, deploying an application meant: install the right version of Java, configure the right environment variables, install the right OS libraries, set up the correct directory structure — on every server. If your laptop has Java 17 but the server has Java 11, the app might behave differently or fail entirely. Docker solves this by packaging the application AND everything it needs into a single, portable unit.

### 3. The actual answer
Docker is a platform for building, packaging, and running containers. A container includes the application code, runtime (JRE), libraries, and configuration — everything needed to run. It runs identically on any machine that has Docker installed.

Key differences from virtual machines:

| | Virtual Machine | Container |
|--|----------------|-----------|
| Includes | Full OS + kernel | App + libraries only (shares host kernel) |
| Size | GBs | MBs |
| Startup time | Minutes | Seconds |
| Isolation | Full hardware virtualisation | Process-level isolation |
| Use case | Full OS environment | Application packaging |

### 4. Key takeaway
- Container = app + dependencies packaged together, runs identically everywhere
- Containers share the host OS kernel — lighter than VMs
- Solves "works on my machine" — same image runs in dev, CI, and production
- Docker is the most widely used container runtime

---

## Q2. What is a Dockerfile and how does each instruction work?

### 1. What is this question actually asking?
- The interviewer wants to know if you can read and write a Dockerfile
- They are checking if you understand what each instruction does

### 2. Understand the concept
A Dockerfile is a recipe for building a Docker image. Each instruction creates a layer in the image. You start from a base image and add your application on top.

### 3. The actual answer
Your `apps/springboot/Dockerfile`:

```dockerfile
FROM eclipse-temurin:21-jre-alpine
```
`FROM` = base image. Everything starts from here. Alpine = minimal Linux (~5MB vs ~200MB for full Ubuntu).

```dockerfile
WORKDIR /app
```
`WORKDIR` = sets the working directory inside the container. All subsequent commands run from here. Creates the directory if it doesn't exist.

```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
```
`RUN` = executes a command during image build (not at runtime). Creates a non-root user for security.

```dockerfile
COPY target/devops-demo-0.0.1-SNAPSHOT.jar app.jar
```
`COPY` = copies files from your local machine into the image. The JAR built by Maven is copied in.

```dockerfile
RUN chown appuser:appgroup app.jar
```
`RUN` = changes file ownership so the non-root user can read the JAR.

```dockerfile
USER appuser
```
`USER` = all subsequent commands (including `ENTRYPOINT`) run as this user, not root.

```dockerfile
EXPOSE 8080
```
`EXPOSE` = documents that the container listens on port 8080. Informational only — doesn't actually open a port.

```dockerfile
ENTRYPOINT ["java", "-jar", "app.jar"]
```
`ENTRYPOINT` = the command that runs when the container starts. Exec form (JSON array) is preferred over shell form.

### 4. Key takeaway
- `FROM` → base image, `RUN` → build-time command, `COPY` → add files
- `WORKDIR` → sets working directory, `USER` → sets runtime user
- `EXPOSE` → documentation only, `ENTRYPOINT` → container startup command
- Order matters — Docker caches layers, put rarely-changing instructions first

---

## Q3. What are Docker layers and how does caching work?

### 1. What is this question actually asking?
- The interviewer is testing if you understand Docker's layer system and how to optimize build speed
- They want to know if you understand layer caching invalidation

### 2. Understand the concept
Every instruction in a Dockerfile creates a layer — a snapshot of the filesystem changes. Docker caches these layers. On rebuild, if a layer hasn't changed, Docker reuses the cached version instead of re-running that instruction. This makes rebuilds fast.

### 3. The actual answer
Layer caching rules:
- If an instruction changes → that layer and ALL subsequent layers are rebuilt (cache invalidated)
- If an instruction is the same AND its inputs haven't changed → use cached layer

Order matters for caching. In a Maven project:

**Bad order (slow builds)**:
```dockerfile
COPY . .           # copies everything — any file change invalidates this
RUN mvn package   # rebuilds every time even if only README changed
```

**Good order (fast builds)**:
```dockerfile
COPY pom.xml .          # only pom.xml — rarely changes
RUN mvn dependency:go-offline  # downloads dependencies — cached until pom.xml changes
COPY src/ src/          # source code — changes often but dependencies already cached
RUN mvn package         # only recompiles, no re-download
```

Your current Dockerfile copies a pre-built JAR (`COPY target/devops-demo-...jar`) — Maven runs in CI before Docker build, so this layer only changes when the JAR changes.

### 4. Practical commands / examples

Command:
```bash
docker build --no-cache -t myapp .
```
Purpose: Forces rebuild of all layers — ignores cache.
What to look for: Useful when you suspect stale cached layers are causing issues.

### 5. Key takeaway
- Each Dockerfile instruction = one layer
- Layer cache invalidated if instruction or its inputs change
- Put rarely-changing instructions FIRST (base image, dependencies)
- Put frequently-changing instructions LAST (application code)
- `COPY . .` early = slow builds — always copy only what the next step needs

---

## Q4. What is the difference between CMD and ENTRYPOINT?

### 1. What is this question actually asking?
- Common Docker interview question
- The interviewer wants to know if you understand how container startup commands work

### 2. Understand the concept
Both define what runs when the container starts. The difference is in how they interact with arguments passed to `docker run` and how easily they can be overridden.

### 3. The actual answer

| | `ENTRYPOINT` | `CMD` |
|--|-------------|-------|
| Purpose | Defines the executable | Defines default arguments |
| Override | `docker run --entrypoint` | `docker run <image> <new_cmd>` |
| Combined | `ENTRYPOINT` + `CMD` = executable + default args | |

**ENTRYPOINT only** (your Dockerfile):
```dockerfile
ENTRYPOINT ["java", "-jar", "app.jar"]
```
Running: `docker run myapp` → runs `java -jar app.jar`
Running: `docker run myapp --spring.profiles.active=prod` → runs `java -jar app.jar --spring.profiles.active=prod`

**CMD only**:
```dockerfile
CMD ["java", "-jar", "app.jar"]
```
Running: `docker run myapp` → runs `java -jar app.jar`
Running: `docker run myapp /bin/sh` → runs `/bin/sh` (CMD completely replaced)

**Both together**:
```dockerfile
ENTRYPOINT ["java", "-jar"]
CMD ["app.jar"]
```
Running: `docker run myapp` → `java -jar app.jar`
Running: `docker run myapp other.jar` → `java -jar other.jar` (CMD replaced, ENTRYPOINT kept)

**Exec form** (`["java", "-jar", "app.jar"]`) vs **shell form** (`java -jar app.jar`):
- Exec form: process runs directly, receives SIGTERM for graceful shutdown
- Shell form: process runs inside `/bin/sh -c` — SIGTERM goes to shell, not your app

Always use exec form for ENTRYPOINT in production — ensures graceful shutdown.

### 4. Key takeaway
- `ENTRYPOINT` = the executable (hard to change at runtime)
- `CMD` = default arguments (easily overridden)
- Use ENTRYPOINT for the main application process
- Always use exec form `["cmd", "arg"]` — not shell form `cmd arg`
- Exec form = proper signal handling (SIGTERM → graceful shutdown)

---

## Q5. What is a multi-stage Dockerfile and when would you use it?

### 1. What is this question actually asking?
- The interviewer wants to know if you know how to keep production images small and secure
- They are testing whether you know how to separate build tools from runtime image

### 2. Understand the concept
To build a Java application, you need Maven + JDK + all build tooling. But to run it, you only need the JRE. If you build and run in the same image, the final image contains Maven, JDK, source code, build artifacts — all unnecessary at runtime and increasing attack surface.

Multi-stage builds solve this: build in one image, copy only the output to a clean runtime image.

### 3. The actual answer
A multi-stage Dockerfile has multiple `FROM` instructions. Each stage can copy files from previous stages.

Example for your Spring Boot app (you currently build JAR in CI, not in Docker):
```dockerfile
# Stage 1: Build
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /build
COPY pom.xml .
RUN mvn dependency:go-offline           # cache dependencies
COPY src/ src/
RUN mvn clean package -DskipTests       # build JAR

# Stage 2: Runtime
FROM eclipse-temurin:21-jre-alpine      # no JDK, no Maven, no source code
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /build/target/devops-demo-*.jar app.jar
RUN chown appuser:appgroup app.jar
USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

Result:
- Build stage: ~500MB (JDK + Maven + source)
- Final image: ~150MB (JRE + JAR only)
- No build tools, no source code, no test dependencies in production image

### 4. Key takeaway
- Multi-stage = separate build environment from runtime image
- Final image contains only what's needed to run — smaller and more secure
- `COPY --from=<stage>` copies files from a previous stage
- Your current approach: build JAR in CI (Maven), copy into Docker — same result as multi-stage

---

## Q6. Why does your Dockerfile use `eclipse-temurin:21-jre-alpine` as the base image?

### 1. What is this question actually asking?
- The interviewer wants to know if you made a conscious, justified choice of base image
- They are testing your awareness of image size and security

### 2. Understand the concept
Every base image choice is a tradeoff between:
- **Size**: Smaller = faster pulls, less storage, less attack surface
- **Security**: Minimal images have fewer packages = fewer CVEs
- **Compatibility**: Some apps need specific OS libraries

### 3. The actual answer
Breaking down `eclipse-temurin:21-jre-alpine`:

| Part | Meaning | Why chosen |
|------|---------|-----------|
| `eclipse-temurin` | Adoptium JRE distribution — well-maintained, production-grade | Trusted, actively maintained by Eclipse Foundation |
| `21` | Java 21 (LTS) | Long-term support, matches `pom.xml` Java version |
| `jre` | Java Runtime only (not JDK) | No compiler tools needed at runtime — smaller |
| `alpine` | Alpine Linux base (~5MB) | Minimal OS — smaller image, fewer CVEs |

Alternative comparison:
| Image | Size |
|-------|------|
| `eclipse-temurin:21-jdk` | ~450MB |
| `eclipse-temurin:21-jre` | ~280MB |
| `eclipse-temurin:21-jre-alpine` | ~150MB |

Previously your Dockerfile used `eclipse-temurin:21-jre` — it was changed to Alpine during security improvements.

> **Note**: Alpine uses musl libc instead of glibc. Some Java libraries behave differently. For Spring Boot, Alpine works fine.

### 4. Key takeaway
- Use `jre` not `jdk` — runtime doesn't need the compiler
- Use `alpine` variant — minimal Linux, smaller size, fewer CVEs
- Always use specific version tags (`21`) not `latest` — reproducible builds
- Trivy scans the base image — Alpine has significantly fewer CVEs than full Ubuntu/Debian

---

## Q7. Why does your Dockerfile create a non-root user and what risk does it mitigate?

### 1. What is this question actually asking?
- Security-focused question
- The interviewer wants to hear the specific risk you're mitigating — not just "security best practice"

### 2. Understand the concept
By default, Docker containers run as `root` (UID 0). If an attacker exploits a vulnerability in your application, they get root access inside the container. With container escape vulnerabilities, a container root can potentially become host root. Running as a non-root user significantly limits this risk.

### 3. The actual answer
In your Dockerfile:
```dockerfile
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
# -S = system account (no login shell, no home directory)
COPY target/devops-demo-0.0.1-SNAPSHOT.jar app.jar
RUN chown appuser:appgroup app.jar
USER appuser
```

What this prevents:
- **Container escape escalation**: Attacker gets non-root shell — harder to escalate to host root
- **File system modifications**: Non-root can't write to `/etc`, `/bin`, `/usr`
- **Privilege escalation**: Can't install new tools or modify system files

This also aligns with Kubernetes `securityContext.runAsNonRoot: true` — if the container tries to run as root, Kubernetes rejects it before it even starts.

### 4. Key takeaway
- Default Docker containers run as root — security risk
- Non-root user = reduced blast radius if container is compromised
- `adduser -S` = system user (no login shell, no password)
- `chown` the JAR file so the non-root user can read it
- Works with K8s `runAsNonRoot: true` security context

---

## Q8. What is GHCR (GitHub Container Registry) and why use it instead of Docker Hub?

### 1. What is this question actually asking?
- The interviewer wants to know your registry choice and reasoning
- They are checking if you understand authentication and access control

### 2. Understand the concept
A container registry is where you store and distribute Docker images — like a repository for code, but for containers. Docker Hub is the public default. GHCR is GitHub's own registry. The choice affects authentication, access control, costs, and integration.

### 3. The actual answer
In your repo, images are pushed to GHCR:
```
ghcr.io/pravinmoreone-ux/pravin-devops-platform/springboot:sha-xxx
```

Why GHCR over Docker Hub:

| Factor | GHCR | Docker Hub |
|--------|------|------------|
| Authentication | `GITHUB_TOKEN` (automatic in Actions) | Separate account + token |
| Integration | Native GitHub — same auth, same visibility | Separate service |
| Private repos | Free for GitHub users | Paid plan required |
| Rate limits | Higher limits for GitHub Actions | 100 pulls/hour unauthenticated |
| Access control | GitHub team/org permissions | Separate access management |

The `GITHUB_TOKEN` in GitHub Actions automatically has permission to push to GHCR for the same repository — no separate credential setup needed.

### 4. Practical commands / examples

```yaml
# Login to GHCR (in CI)
- uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}

# Pull image locally
docker pull ghcr.io/pravinmoreone-ux/pravin-devops-platform/springboot:sha-xxx
```

### 5. Key takeaway
- GHCR = GitHub's container registry — tightly integrated with GitHub Actions
- No separate credentials needed — `GITHUB_TOKEN` handles authentication automatically
- Better access control for private images — uses GitHub team/org permissions
- Image URL format: `ghcr.io/<owner>/<repo>/<image>:<tag>`

---

## Q9. What is image tagging and why does your pipeline use `sha-<GIT_SHA>` instead of `latest`?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of image immutability and traceability
- They want to know the specific problems with using `latest`

### 2. Understand the concept
A Docker image tag is a label that points to a specific image version. `latest` is just a tag — it's not special. The problem is `latest` is mutable — today's `latest` and yesterday's `latest` are different images. If something breaks, you can't easily roll back to "the version we had yesterday."

### 3. The actual answer
Problems with `latest`:
- **Not reproducible**: `docker pull myapp:latest` gets a different image each time
- **No traceability**: You can't tell which code is in `latest`
- **Rollback impossible**: If you push a bad `latest`, the previous `latest` is gone
- **Cache confusion**: Docker may use a cached `latest` that's actually old

Your pipeline uses `sha-<GITHUB_SHA>`:
```bash
tag = "sha-${GITHUB_SHA}"
# e.g. sha-9bb2f6e5117a5197fdb6b233e0634e6ddbaec444
```

Benefits:
- **Immutable**: `sha-9bb2f6e5` always refers to exactly that Git commit's build
- **Traceable**: Given the image tag, you know exactly which commit it came from
- **Safe rollback**: Previous images are never overwritten — just update the tag in `values.yaml`
- **Audit trail**: Git history + image history are linked

### 4. Key takeaway
- Never use `latest` in production — it's mutable and untraceable
- Git SHA tags = immutable, traceable, supports rollback
- Rollback = change `tag:` in `values.yaml` to previous SHA → commit → Argo CD deploys old version
- Other good tag strategies: semantic versions (`v1.2.3`), date-based (`20240101-abc1234`)

---

## Q10. What is the difference between `docker build`, `docker run`, and `docker push`?

### 1. What is this question actually asking?
- Basic practical question about the Docker workflow
- The interviewer is checking your hands-on familiarity

### 2. Understand the concept
Building, running, and pushing are three separate operations in Docker's workflow. You build an image from a Dockerfile, run it as a container, and push it to a registry so others (or your Kubernetes cluster) can pull and run it.

### 3. The actual answer

| Command | What it does |
|---------|-------------|
| `docker build` | Reads `Dockerfile`, executes instructions, creates image locally |
| `docker run` | Creates and starts a container from an image |
| `docker push` | Uploads a local image to a registry (GHCR, Docker Hub) |
| `docker pull` | Downloads an image from a registry |

```bash
# Build image and tag it
docker build -t ghcr.io/pravinmoreone-ux/pravin-devops-platform/springboot:sha-abc123 .

# Run locally for testing
docker run -p 8080:8080 ghcr.io/.../springboot:sha-abc123

# Push to GHCR
docker push ghcr.io/.../springboot:sha-abc123

# Pull on another machine
docker pull ghcr.io/.../springboot:sha-abc123
```

### 4. Practical commands / examples

Command:
```bash
docker images
```
Purpose: Lists all locally stored images.
What to look for: Image name, tag, size, creation date.

Command:
```bash
docker ps
```
Purpose: Lists running containers.

Command:
```bash
docker logs <container-id>
```
Purpose: Shows container stdout/stderr logs.

### 5. Key takeaway
- Build → stored locally as an image
- Run → image becomes a running container
- Push → image available in registry for Kubernetes/others to pull
- Containers are ephemeral — stopping them loses any data not in a volume

---

## Q11. What happens inside a container when it starts — from `docker run` to application serving traffic?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the container lifecycle
- They are testing deeper knowledge beyond basic commands

### 2. Understand the concept
When you run a container, Docker sets up an isolated environment and runs your ENTRYPOINT. Understanding this chain helps debug startup failures.

### 3. The actual answer
Step by step for your Spring Boot container:

```text
1. docker run / Kubernetes creates pod
       │
       ▼
2. Docker pulls image from GHCR (if not cached)
       │
       ▼
3. Docker creates container:
   - New network namespace (isolated networking)
   - New filesystem (copy-on-write layer on top of image layers)
   - Mount volumes (/tmp as emptyDir)
   - Set environment variables
   - Apply resource limits (CPU, memory cgroups)
       │
       ▼
4. Run ENTRYPOINT: ["java", "-jar", "app.jar"]
   - Process starts as non-root user (appuser)
   - JVM initialises
   - Spring Boot loads ApplicationContext
   - Beans created, autoconfiguration runs
   - Embedded Tomcat starts on port 8080
       │
       ▼
5. Kubernetes readiness probe fires after 10s:
   GET /actuator/health → {"status":"UP"}
       │
       ▼
6. Pod added to Service endpoints
   → Traffic starts flowing to pod
```

### 4. Key takeaway
- Container = isolated process with its own network, filesystem, and resource limits
- ENTRYPOINT is PID 1 in the container — must handle SIGTERM for graceful shutdown
- Readiness probe gates traffic — pod receives traffic only after health check passes
- JVM startup takes a few seconds — `initialDelaySeconds: 10` gives it time

---

## Q12. What is `docker exec` and when would you use it?

### 1. What is this question actually asking?
- Practical debugging question
- The interviewer wants to know how you debug running containers

### 2. Understand the concept
Sometimes a container is running but misbehaving. You need to look inside — check files, run commands, inspect the environment. `docker exec` lets you run a command inside a running container without stopping it.

### 3. The actual answer
`docker exec` executes a command inside a running container:

```bash
# Interactive shell inside running container
docker exec -it <container-id> /bin/sh

# Check environment variables
docker exec <container-id> env

# Check what's in /tmp
docker exec <container-id> ls -la /tmp

# Check if app.jar exists
docker exec <container-id> ls -la /app/
```

In Kubernetes, the equivalent is:
```bash
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh
```

> **Note**: Your container uses Alpine Linux — use `/bin/sh` not `/bin/bash` (bash is not installed in Alpine by default).

> **Limitation**: Your container has `readOnlyRootFilesystem: true` — you can't create files, but you can still read and run commands.

### 4. Practical commands / examples

Command:
```bash
kubectl exec -it <pod-name> -n default -- /bin/sh
```
Purpose: Open interactive shell inside the Spring Boot pod.
What to look for: Environment variables, file permissions, network connectivity.

Command:
```bash
kubectl exec <pod-name> -- wget -qO- http://localhost:8080/actuator/health
```
Purpose: Test the health endpoint from inside the pod.

### 5. Key takeaway
- `docker exec -it <id> /bin/sh` = shell access to running container
- Kubernetes equivalent: `kubectl exec -it <pod> -- /bin/sh`
- Alpine containers: use `/bin/sh` not `/bin/bash`
- Useful for checking env vars, file permissions, and network connectivity from inside

---

## Q13. What is a Docker volume and how is it different from a bind mount?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand persistent data in containers
- They are checking if you know the difference between named volumes and host mounts

### 2. Understand the concept
Container filesystems are temporary — when a container is deleted, all data inside is lost. If your application writes logs, uploads files, or stores a database, you need persistent storage outside the container. Volumes solve this.

### 3. The actual answer

| | Docker Volume | Bind Mount |
|--|-------------|-----------|
| Storage location | Managed by Docker (`/var/lib/docker/volumes/`) | Specific path on host (`/home/user/data`) |
| Managed by | Docker | You (manually) |
| Portability | Portable — works same on any Docker host | Host-specific path |
| Use case | Databases, persistent app data | Development (mount source code) |

In Kubernetes, your app uses an `emptyDir` volume for `/tmp`:
```yaml
volumes:
  - name: tmp
    emptyDir:
      medium: Memory   # RAM-backed, not disk
```

`emptyDir` is tied to the pod's lifetime — deleted when pod is deleted. Used here for `/tmp` because the root filesystem is read-only, but the app needs to write temporary files.

### 4. Key takeaway
- Docker volumes = persistent storage outside container lifecycle
- Bind mounts = mount a host directory into container (dev workflow)
- `emptyDir` in Kubernetes = temporary volume for pod lifetime (deleted on pod restart)
- For databases in Kubernetes: use PersistentVolumeClaim (PVC) with EBS

---

## Q14. What is Podman and how is it different from Docker?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand Docker alternatives
- Relevant because you have Podman installed locally

### 2. Understand the concept
Docker requires a daemon (background service) running as root. This has security implications — the Docker daemon has root access to the host. Podman runs containers without a daemon and without root — each container runs as a regular user process.

### 3. The actual answer
Key differences:

| | Docker | Podman |
|--|--------|--------|
| Daemon | Requires `dockerd` daemon | Daemonless |
| Root required? | Daemon runs as root | Fully rootless (containers run as your user) |
| CLI compatibility | `docker` CLI | `podman` CLI — mostly identical commands |
| Compose | `docker-compose` | `podman-compose` or `podman play kube` |
| Used by | Most platforms | RHEL/Fedora/IBM environments |

For your use case:
```bash
# Commands are the same
podman build -t springboot:local .
podman run -p 8080:8080 springboot:local
```

In GitHub Actions CI (Ubuntu runners), Docker is used — not Podman. Podman is on your Windows machine for local testing.

Your jump server Ansible role installs Podman (`dnf install podman`) instead of Docker — because Amazon Linux 2023 uses Podman by default.

### 4. Key takeaway
- Podman = daemonless, rootless Docker alternative
- CLI commands are nearly identical — replace `docker` with `podman`
- More secure by default — no root daemon
- Used in RHEL/Fedora/Amazon Linux environments
- GitHub Actions runners use Docker — your local machine uses Podman

---

## Q15. What is the `.dockerignore` file and why should you have one?

### 1. What is this question actually asking?
- Small but important question about Docker build context
- The interviewer is checking if you know how to speed up builds and avoid leaking sensitive files

### 2. Understand the concept
When you run `docker build`, Docker sends the entire build context (your project directory) to the Docker daemon. Without a `.dockerignore`, it sends EVERYTHING — node_modules, `.git`, compiled binaries, test reports, IDE files. This makes builds slow and can accidentally include sensitive files.

### 3. The actual answer
`.dockerignore` tells Docker which files to exclude from the build context — similar to `.gitignore` but for Docker builds.

For your Spring Boot project, a good `.dockerignore`:
```text
.git/
.github/
docs/
target/test-classes/
target/surefire-reports/
target/site/
*.md
.idea/
.vscode/
```

Your current Dockerfile copies the pre-built JAR:
```dockerfile
COPY target/devops-demo-0.0.1-SNAPSHOT.jar app.jar
```

Only the JAR needs to be in the build context. Everything else in `target/` (test classes, reports, raw classes) is wasted transfer.

### 4. Key takeaway
- `.dockerignore` = exclude files from build context
- Smaller build context = faster builds, less network transfer to Docker daemon
- Never include `.git/`, `node_modules/`, IDE files, or secrets in build context
- Missing `.dockerignore` can accidentally include sensitive files in the image

---

## Q16. How does container networking work — how do containers talk to each other?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand container-to-container communication
- This is relevant for understanding how your Spring Boot app talks to the OTel Collector

### 2. Understand the concept
Each container gets its own network stack. By default, containers on the same Docker host can be on the same network and communicate by container name. In Kubernetes, every pod gets its own IP and DNS name.

### 3. The actual answer
**In Docker (local)**:
```bash
# Create network
docker network create myapp

# Run containers on same network
docker run -d --network myapp --name springboot myapp:latest
docker run -d --network myapp --name postgres postgres:15

# springboot can reach postgres by name
# jdbc:postgresql://postgres:5432/mydb
```

**In Kubernetes (your setup)**:
Every pod gets a real VPC IP (from EKS VPC CNI).
Services provide stable DNS names:
```
opentelemetry-collector.observability.svc.cluster.local:4317
                 │                │         │          │
           service name      namespace  svc.cluster.local  port
```

Your Spring Boot `application.yml`:
```yaml
otel:
  exporter:
    otlp:
      endpoint: http://opentelemetry-collector.observability.svc.cluster.local:4317
```

Spring Boot sends OTel data to the Collector using the Kubernetes DNS name — it works because both run in the same cluster.

### 4. Key takeaway
- Docker: containers on same network communicate by container name
- Kubernetes: every service gets DNS: `<service>.<namespace>.svc.cluster.local`
- Pods communicate via Services — not directly by pod IP (pods are ephemeral)
- EKS VPC CNI: pods get real VPC IP addresses — can communicate across nodes

---

## Q17. What is image scanning and what does Trivy check in your container image?

### 1. What is this question actually asking?
- The interviewer wants to know your container security practices
- They are checking if you understand what CVE scanning does

### 2. Understand the concept
Every base image (Alpine, Ubuntu, JRE) contains OS packages with known vulnerabilities. Your application dependencies (Spring Boot, Jackson, Tomcat) may also have CVEs. Trivy scans all of these and tells you which vulnerabilities exist, their severity, and how to fix them.

### 3. The actual answer
In your Spring Boot CI:
```yaml
- name: Trivy Container Security Scan
  run: |
    trivy image \
      --severity HIGH,CRITICAL \
      --exit-code 1 \
      "${IMAGE_NAME}:${{ steps.image.outputs.tag }}"
```

What Trivy scans in your image:
1. **OS packages**: Alpine Linux packages with known CVEs (from NVD, RedHat advisories)
2. **Java dependencies**: Packages in your JAR's classpath (Spring Boot, Tomcat, Jackson, etc.)
3. **License issues**: Identifies license types of all packages

`--exit-code 1` = pipeline fails if HIGH or CRITICAL CVEs found. This blocks the image from being pushed to GHCR and deployed to EKS.

How to fix Trivy findings:
- **Base image CVE**: Update to newer Alpine/JRE version (`eclipse-temurin:21-jre-alpine` → pull latest patch)
- **Java dependency CVE**: Update `pom.xml` dependency version
- **False positive / accepted risk**: Add to `.trivyignore` with documented justification

### 4. Key takeaway
- Trivy scans OS packages + Java dependencies for known CVEs
- Blocks push if HIGH/CRITICAL found — prevents vulnerable images reaching EKS
- Fix by updating base image version or Java dependency versions
- Run locally: `trivy image eclipse-temurin:21-jre-alpine` to check current CVEs

---

## Q18. What is the difference between a container image and a container?

### 1. What is this question actually asking?
- Simple foundational question
- The interviewer is checking basic conceptual clarity

### 2. Understand the concept
The difference is like a class vs an instance in object-oriented programming. The image is the template. The container is the running instance created from that template.

### 3. The actual answer

| | Image | Container |
|--|-------|-----------|
| What it is | Read-only template with layers | Running instance of an image |
| State | Static — doesn't change | Has a writable layer, running processes |
| Stored | Registry (GHCR) or local | Host machine memory/disk |
| Multiple instances | One image → many containers | Each container independent |
| Lifecycle | Build once, push, pull | Start, stop, delete |

Analogy:
- Image = cookie cutter (template)
- Container = the actual cookie (instance)

You can run 10 containers from the same image simultaneously. Each has its own writable filesystem layer on top of the shared read-only image layers.

### 4. Key takeaway
- Image = static, read-only template stored in registry
- Container = running instance of an image, temporary
- Multiple containers can run from same image simultaneously
- Deleting a container doesn't affect the image — you can create new containers from it

---

## Q19. What is the `EXPOSE` instruction and does it actually open a port?

### 1. What is this question actually asking?
- Common misconception question
- The interviewer is testing whether you know `EXPOSE` is just documentation

### 2. Understand the concept
Many people think `EXPOSE` in a Dockerfile opens a port on the host. It doesn't. It's documentation — telling users and orchestration systems which port the application listens on.

### 3. The actual answer
`EXPOSE 8080` in your Dockerfile:
- Does NOT open port 8080 on the host
- Does NOT make the app accessible from outside the container
- Is metadata — tells Docker/Kubernetes "this container listens on 8080"

To actually expose a port when running locally:
```bash
docker run -p 8080:8080 springboot:local
#               │    │
#          host:8080  container:8080
```

In Kubernetes, the Service definition does the actual port mapping:
```yaml
spec:
  ports:
    - port: 8080        # Service port
      targetPort: 8080  # Container port (reads EXPOSE as hint)
```

Kubernetes uses the `containerPort` in the Pod spec and `targetPort` in the Service — `EXPOSE` is just informational.

### 4. Key takeaway
- `EXPOSE` = documentation only — does NOT open ports
- Actual port exposure: `-p` flag in `docker run`, or Service `targetPort` in Kubernetes
- Still useful: tools like `docker-compose` and Kubernetes use it as a hint
- Common mistake: writing `EXPOSE` and expecting the port to be accessible

---

## Q20. What is a read-only root filesystem (`readOnlyRootFilesystem: true`) and why does your app need a `/tmp` volume?

### 1. What is this question actually asking?
- Security-specific question about your Kubernetes configuration
- The interviewer wants to understand both the security control and the practical workaround

### 2. Understand the concept
Normally, a container process can write files anywhere inside the container. An attacker who compromises the container could write scripts, modify binaries, or install tools. `readOnlyRootFilesystem: true` prevents any writes to the container filesystem — the attacker has a read-only environment.

But the application itself might need to write temporary files — which is a problem.

### 3. The actual answer
In your Kubernetes deployment:
```yaml
securityContext:
  readOnlyRootFilesystem: true

volumeMounts:
  - name: tmp
    mountPath: /tmp

volumes:
  - name: tmp
    emptyDir:
      medium: Memory   # RAM-backed
```

Why Spring Boot needs `/tmp`:
- JVM writes temporary files to `/tmp` during startup (native library extraction, temp class files)
- Tomcat may write to `/tmp`
- Without writable `/tmp`, the JVM may fail to start or crash

The `emptyDir` volume with `medium: Memory` provides:
- Writable `/tmp` for the application
- RAM-backed — faster than disk, no I/O
- Automatically deleted when pod is deleted — no sensitive data persistence

Security benefit: root filesystem is read-only, but `/tmp` is sandboxed — writes go to RAM, not the container image layers.

### 4. Key takeaway
- `readOnlyRootFilesystem: true` = prevents writing to container filesystem
- Limits attacker's ability to persist malicious code or tools
- JVM needs writable `/tmp` — provide via `emptyDir` volume
- `medium: Memory` = RAM-backed temp storage — faster and ephemeral
- This pattern is production security standard for Kubernetes workloads

---

## Q21. How do you reduce Docker image size and why does it matter?

### 1. What is this question actually asking?
- The interviewer wants to know your image optimization knowledge
- They are checking whether you understand the practical impact of image size

### 2. Understand the concept
Large images take longer to pull (slow pod startup), consume more storage in the registry, have more packages (more CVEs), and use more bandwidth. Optimizing image size has real operational and security benefits.

### 3. The actual answer
Techniques to reduce image size:

**1. Choose minimal base image**
```dockerfile
# Before: 280MB
FROM eclipse-temurin:21-jre

# After: 150MB
FROM eclipse-temurin:21-jre-alpine
```

**2. Use multi-stage builds** (don't include build tools in final image)

**3. Combine RUN commands** (fewer layers)
```dockerfile
# Bad: 3 layers
RUN apt-get update
RUN apt-get install -y curl
RUN rm -rf /var/lib/apt/lists/*

# Good: 1 layer
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*
```

**4. Clean up in the same layer**
Package manager caches must be deleted in the SAME `RUN` command — otherwise the cache is still in the layer even if deleted later.

**5. Use `.dockerignore`** to exclude unnecessary files from build context.

**6. Don't install unnecessary packages**
`-y --no-install-recommends` in apt, only install what the app actually needs.

Why it matters:
- Kubernetes pod startup time: Pull 150MB vs 450MB = faster scaling
- Registry storage costs
- Fewer packages = fewer CVEs = less Trivy noise
- CI build time: smaller push/pull = faster pipeline

### 4. Key takeaway
- Alpine base = biggest single win for Java images (100MB+ reduction)
- Multi-stage builds = exclude build tools from final image
- Combine `RUN` + cleanup in same layer — not separate layers
- Smaller image = faster pulls, less storage, fewer CVEs, faster CI
