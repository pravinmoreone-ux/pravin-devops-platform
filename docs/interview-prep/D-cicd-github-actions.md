# Interview Prep — D: CI/CD & GitHub Actions

> **Purpose**: Self-learning and revision document. These are not scripted interview answers — they are explanations to help you understand concepts and remember how they work in practice.

---

## Q1. What is CI/CD and what problem does it solve?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the fundamental problem CI/CD solves
- They are checking whether you can explain it beyond just "automated testing and deployment"

### 2. Understand the concept
Before CI/CD, teams would write code for weeks, then try to merge everything together — and spend days fixing conflicts. Deployments were manual, infrequent, and terrifying events that required weekends and rollback plans. Bugs were found weeks after they were written.

CI/CD breaks this cycle by integrating and deploying code continuously — catching problems early, reducing risk, and making releases routine rather than rare.

### 3. The actual answer
**CI (Continuous Integration)**: Every code change is automatically built and tested. Problems are caught within minutes of being introduced, not weeks later.

**CD (Continuous Delivery/Deployment)**:
- **Delivery**: Code is always in a deployable state — a human presses a button to deploy
- **Deployment**: Deployment happens automatically after CI passes (your repo does this for `main` branch)

What your pipeline does:
- **Test**: Maven runs unit tests
- **Scan**: SonarCloud SAST, Trivy container scan, OPA policy checks
- **Build**: Docker image built and tagged with Git SHA
- **Push**: Immutable image pushed to GHCR
- **Deploy**: Helm values updated → Argo CD syncs → EKS rolls out

### 4. Key takeaway
- CI = automate build + test on every commit → catch bugs early
- CD = automate delivery/deployment → reduce release risk and frequency of manual work
- Your pipeline does both — code on `main` automatically flows to EKS via Argo CD
- Small, frequent releases are less risky than large, infrequent ones

---

## Q2. What is GitHub Actions and how does it work?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how GitHub Actions works at a conceptual level
- They are testing whether you know the core components: workflows, jobs, steps, runners

### 2. Understand the concept
GitHub Actions is a CI/CD platform built into GitHub. Instead of running a separate Jenkins or CircleCI server, your pipelines run inside GitHub on machines GitHub provides (or your own). Pipelines are defined as YAML files in `.github/workflows/`.

### 3. The actual answer
Core concepts:

| Concept | What it is |
|---------|-----------|
| **Workflow** | A YAML file in `.github/workflows/` — the entire pipeline definition |
| **Event** | What triggers the workflow (push, pull_request, schedule, manual) |
| **Job** | A group of steps that runs on the same machine |
| **Step** | One task in a job (run a command or use an Action) |
| **Runner** | The machine that executes jobs (`ubuntu-latest` = GitHub-hosted VM) |
| **Action** | A reusable unit (e.g., `actions/checkout@v4`, `hashicorp/setup-terraform@v3`) |

In your repo, you have 4 workflows, each triggered by specific path changes:
```yaml
on:
  push:
    branches: [main]
    paths: ["terraform/**"]   # only runs when terraform files change
```

This path filtering means only relevant workflows run — not all 4 on every commit.

### 4. Practical commands / examples

```yaml
# Basic workflow structure
name: My Pipeline
on:
  push:
    branches: [main]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Hello World"
```

### 5. Key takeaway
- Workflow = YAML file in `.github/workflows/`
- Jobs run in parallel by default — use `needs:` to create dependencies
- Steps run sequentially within a job
- `ubuntu-latest` runners are fresh VMs — nothing persists between workflow runs
- Path filters = only trigger when relevant files change (reduces wasted CI runs)

---

## Q3. What is the difference between a push event and a pull_request event in GitHub Actions?

### 1. What is this question actually asking?
- The interviewer is checking if you understand the difference in trigger context and what's safe to do in each
- They want to know if you understand why certain steps (like deployment) only run on push to main

### 2. Understand the concept
A pull request event fires when someone opens/updates a PR. A push event fires when a commit lands on a branch. The key difference: a PR hasn't been reviewed and merged yet — you shouldn't deploy untrusted code. Push to `main` means code has been reviewed and merged — safe to deploy.

### 3. The actual answer
In your workflows, two types of triggers exist:

```yaml
on:
  pull_request:                    # runs on PR open/update
    paths: ["terraform/**"]
  push:
    branches: [main]               # runs when merged to main
    paths: ["terraform/**"]
```

What runs on each:

| Step | PR | Push to main |
|------|-----|-------------|
| fmt, validate, lint | ✅ | ✅ |
| Security scans (Trivy, OPA) | ✅ | ✅ |
| Build Docker image | ✅ | ✅ |
| Terraform plan | ❌ | ✅ (needs AWS creds) |
| Push Docker image to GHCR | ❌ | ✅ |
| Update Helm values | ❌ | ✅ |

Deployment steps are guarded:
```yaml
- name: Push Docker image
  if: github.event_name == 'push' && github.ref == 'refs/heads/main'
```

### 4. Key takeaway
- PR trigger = validate/test only — never deploy
- Push to main = validate + deploy (code has been reviewed and merged)
- Use `if:` conditionals to gate deployment steps
- This pattern ensures only reviewed, merged code gets deployed

---

## Q4. What is OIDC authentication in GitHub Actions and why is it better than using AWS access keys?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of secure CI/CD credential management
- This is a security-focused question — they want to know if you eliminated static credentials

### 2. Understand the concept
The old way: store AWS Access Key ID and Secret Key in GitHub Secrets. Problems: keys don't expire, if GitHub is compromised all keys are exposed, someone might accidentally log the key, and you must rotate keys manually.

The new way: OpenID Connect (OIDC). GitHub Actions proves its identity to AWS using a short-lived, signed token. AWS verifies the token and issues a temporary credential. No long-lived secrets stored anywhere.

### 3. The actual answer
How OIDC works in your pipeline:

```text
GitHub Actions job starts
      │
      ▼
GitHub generates a signed JWT token:
  {
    "iss": "https://token.actions.githubusercontent.com",
    "sub": "repo:pravinmoreone-ux/pravin-devops-platform:ref:refs/heads/main",
    "aud": "sts.amazonaws.com"
  }
      │
      ▼
GitHub Actions sends token to AWS STS:
  AssumeRoleWithWebIdentity
      │
      ▼
AWS verifies:
  1. Token signed by GitHub? ✅ (via OIDC provider)
  2. Audience = sts.amazonaws.com? ✅
  3. Subject matches condition in IAM role? ✅
      │
      ▼
AWS returns temporary credentials (valid ~1 hour)
      │
      ▼
Terraform/AWS CLI use temporary credentials for this job
      │
      ▼
Job finishes → credentials expire automatically
```

In your repo (`terraform/github_oidc.tf`), the IAM role's trust policy checks:
```hcl
"token.actions.githubusercontent.com:sub" = "repo:pravinmoreone-ux/pravin-devops-platform:ref:refs/heads/main"
```

Only this specific repo's `main` branch can assume the role.

### 4. Practical commands / examples

```yaml
# In workflow
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::263824391433:role/pravin-devops-platform-github-actions
    aws-region: ap-south-1
```

No secrets needed — the OIDC token is handled automatically.

### 5. Key takeaway
- OIDC = no long-lived AWS secrets stored in GitHub
- GitHub proves identity via signed JWT → AWS issues temporary credentials
- Credentials expire after ~1 hour — limiting blast radius
- IAM role condition scopes access to specific repo + branch — not all of GitHub

---

## Q5. What is path filtering in GitHub Actions and why is it important?

### 1. What is this question actually asking?
- Simple question about workflow efficiency
- The interviewer wants to know if you know how to avoid unnecessary pipeline runs

### 2. Understand the concept
Without path filtering, every single commit — even a README change — would trigger all your CI workflows. Terraform CI would run when you change Spring Boot code. Spring Boot CI would run when you change Ansible files. This wastes CI minutes and creates noise.

### 3. The actual answer
Path filtering (`paths:`) limits workflow triggers to only when relevant files change:

```yaml
on:
  push:
    paths:
      - "terraform/**"           # only when terraform files change
      - "policy/terraform/**"    # or policy files
      - ".github/workflows/terraform-ci.yml"  # or the workflow itself
```

Scenarios:
| Change | Terraform CI | Spring Boot CI | Helm CI | Ansible CI |
|--------|-------------|----------------|---------|------------|
| Edit `terraform/vpc.tf` | ✅ runs | ❌ skipped | ❌ skipped | ❌ skipped |
| Edit `apps/springboot/HelloController.java` | ❌ | ✅ | ❌ | ❌ |
| Edit `helm/springboot/values.yaml` | ❌ | ❌ | ✅ | ❌ |
| Edit `README.md` | ❌ | ❌ | ❌ | ❌ |

Including the workflow file itself in paths ensures changes to the workflow trigger it (so you can test workflow changes).

### 4. Key takeaway
- Path filtering = only trigger workflows when relevant files change
- Saves CI minutes and reduces noise
- Always include the workflow file itself in the paths list
- Without path filtering, every commit runs every workflow

---

## Q6. What are GitHub Actions secrets and how are they different from environment variables?

### 1. What is this question actually asking?
- The interviewer is checking if you understand secure credential handling in CI/CD
- They want to know how secrets are protected vs plain environment variables

### 2. Understand the concept
An environment variable in a workflow is just a value you set — anyone can see it in the workflow YAML. A secret is stored encrypted in GitHub and injected at runtime — it's masked in logs and never exposed in the YAML file.

### 3. The actual answer

| | Env Variable | GitHub Secret |
|--|-------------|---------------|
| Defined in | Workflow YAML (`env:`) | GitHub repo Settings → Secrets |
| Visible in YAML? | Yes | No (referenced as `${{ secrets.NAME }}`) |
| Masked in logs? | No | Yes — appears as `***` |
| Use case | Non-sensitive config | API keys, tokens, passwords |

In your repo:
- `SONAR_TOKEN` is stored as a GitHub secret — used for SonarCloud authentication
- `GITHUB_TOKEN` is auto-generated per run — no manual setup needed for GHCR

```yaml
- name: SonarCloud SAST
  env:
    SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
```

### 4. Key takeaway
- Secrets = encrypted at rest, masked in logs, referenced via `${{ secrets.NAME }}`
- `GITHUB_TOKEN` is automatically provided — no setup needed for most GitHub operations
- Never put sensitive values in `env:` in workflow YAML — they're visible in the file
- Secrets can be scoped to repository, environment, or organization

---

## Q7. What is `actions/checkout@v4` and why is it always the first step?

### 1. What is this question actually asking?
- Simple but foundational question
- The interviewer is checking if you understand that runners start empty

### 2. Understand the concept
A GitHub Actions runner is a fresh virtual machine. It has no knowledge of your repository — no code files, no git history. The `checkout` action clones your repository onto the runner so the rest of the steps can access your code.

### 3. The actual answer
`actions/checkout@v4` clones the repository to the runner's working directory. Without it, the runner has no code to work with.

Important options:
```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0   # fetch full git history (needed for SonarCloud, GitVersion)
```

Your Spring Boot CI uses `fetch-depth: 0` because SonarCloud needs full git history to do accurate blame analysis and detect new vs old issues.

Default `fetch-depth: 1` = shallow clone (only latest commit) — faster, but no history.

### 4. Key takeaway
- Runners start empty — `checkout` is always first to get your code
- `fetch-depth: 0` = full history (needed for SonarCloud, semantic versioning)
- `fetch-depth: 1` (default) = shallow clone, faster for simple builds
- Always pin to a specific version (`@v4` not `@latest`) for stability

---

## Q8. How does the Spring Boot CI pipeline build and push a Docker image?

### 1. What is this question actually asking?
- The interviewer wants to trace through your actual pipeline end-to-end
- They are checking if you understand the image tagging strategy and GHCR authentication

### 2. Understand the concept
Building a Docker image in CI requires: checking out code, building the JAR, building the image, authenticating to a registry, and pushing. Each step depends on the previous one.

### 3. The actual answer
Your `springboot-ci.yml` pipeline:

```text
Step 1: Checkout code (fetch-depth: 0)
      │
Step 2: Setup Java 21 (Temurin + Maven cache)
      │
Step 3: mvn clean verify
        → runs unit tests
        → generates JAR in target/
        → generates JaCoCo coverage report
      │
Step 4: SonarCloud SAST
        → analyzes source code
        → quality gate must pass
      │
Step 5: Generate image tag
        tag = "sha-${GITHUB_SHA}"
        e.g. sha-9bb2f6e5117a5197fdb6b233e0634e6ddbaec444
      │
Step 6: docker build -t ghcr.io/.../springboot:sha-xxx .
        → uses apps/springboot/Dockerfile
        → copies target/devops-demo-0.0.1-SNAPSHOT.jar
      │
Step 7: Trivy container scan
        → scans the built image for CVEs
        → fails on HIGH/CRITICAL
      │
Step 8: (main only) Login to GHCR with GITHUB_TOKEN
      │
Step 9: (main only) docker push ghcr.io/.../springboot:sha-xxx
      │
Step 10: (main only) Update helm/springboot/values.yaml
         sed replaces tag value
         git commit + push
         → triggers Argo CD
```

### 4. Key takeaway
- JAR is built first (Maven), then Docker image is built from the JAR
- Image tag = `sha-<GITHUB_SHA>` — immutable, traceable, never reuses tags
- Trivy scans the image BEFORE pushing — blocks vulnerable images
- GHCR push only happens on `main` — PR builds test without polluting the registry

---

## Q9. What is a GitHub Actions matrix and when would you use it?

### 1. What is this question actually asking?
- The interviewer is checking if you know how to run the same job with different configurations
- Common use case: testing across multiple versions or platforms

### 2. Understand the concept
Sometimes you want to run the same job multiple times with different values — test on Java 17 and Java 21, or test on Ubuntu and Windows. Instead of duplicating the job, you define a matrix of values and GitHub Actions runs one job per combination.

### 3. The actual answer
A matrix strategy creates a job for each combination of values:

```yaml
jobs:
  test:
    strategy:
      matrix:
        java: [17, 21]
        os: [ubuntu-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/setup-java@v5
        with:
          java-version: ${{ matrix.java }}
      - run: mvn test
```

This runs 4 jobs: Java 17 + Ubuntu, Java 17 + Windows, Java 21 + Ubuntu, Java 21 + Windows — in parallel.

Your repo doesn't use matrix currently (single Java 21 target), but it's useful for:
- Multi-version compatibility testing
- Multi-OS builds
- Multi-region Terraform deployments

### 4. Key takeaway
- Matrix = run same job with different variable values, in parallel
- Reduces duplication vs copy-pasting jobs
- `fail-fast: false` — don't cancel other matrix jobs if one fails (useful for seeing all failures)
- Your repo uses single values — matrix would be added for multi-version testing

---

## Q10. How does your CI pipeline automatically update the Helm chart with the new image tag?

### 1. What is this question actually asking?
- The interviewer wants to understand the GitOps feedback loop
- They are checking whether you understand how the CI → Git → Argo CD chain works

### 2. Understand the concept
For GitOps to work, the Git repository must always reflect what should be deployed. After building a new Docker image, the Helm chart's `values.yaml` must be updated with the new image tag — committed back to Git — so Argo CD can pick it up.

### 3. The actual answer
After pushing the image to GHCR, your pipeline:

```yaml
- name: Update Helm image tag
  run: |
    # Replace the tag line in values.yaml
    sed -i -E 's/^  tag: ".*"/  tag: "${{ steps.image.outputs.tag }}"/' \
      ../../helm/springboot/values.yaml

    # Check if anything changed
    if git diff --quiet -- ../../helm/springboot/values.yaml; then
      echo "Tag already up to date"
      exit 0
    fi

    # Commit and push the change
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git add ../../helm/springboot/values.yaml
    git commit -m "Update Spring Boot image to ${{ steps.image.outputs.tag }}"
    git push
```

What happens next:
1. `git push` adds a new commit to `main`
2. Argo CD detects the new commit (polls every 3 min)
3. Argo CD renders Helm chart with new `tag` value
4. Argo CD applies the updated Deployment to EKS
5. EKS performs rolling update with new image

### 4. Key takeaway
- `sed` replaces the image tag in `values.yaml` automatically
- `git diff --quiet` check prevents empty commits (if tag didn't change)
- `github-actions[bot]` identity is used for the commit
- This commit triggers Argo CD — closing the GitOps loop
- Requires `contents: write` permission in the workflow

---

## Q11. What is SonarCloud and what does it check in your pipeline?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand SAST (Static Application Security Testing)
- They are checking what value SonarCloud adds beyond unit tests

### 2. Understand the concept
Unit tests check that your code does what you expect. SonarCloud checks the quality and security of your code itself — looking for bugs, vulnerabilities, code smells, and measuring test coverage. It finds issues that tests don't catch: potential null pointer exceptions, SQL injection patterns, hardcoded credentials, duplicated code.

### 3. The actual answer
SonarCloud performs Static Application Security Testing (SAST):

| Check | What it finds |
|-------|--------------|
| **Bugs** | Code likely to cause runtime errors |
| **Vulnerabilities** | Security weaknesses (e.g., OWASP Top 10) |
| **Code smells** | Maintainability issues (complex methods, dead code) |
| **Coverage** | % of code covered by unit tests (from JaCoCo) |
| **Duplications** | Repeated code blocks |
| **Quality Gate** | Pass/fail threshold — your pipeline uses `qualitygate.wait=true` |

In your pipeline:
```yaml
- name: SonarCloud SAST
  run: mvn -B org.sonarsource.scanner.maven:sonar-maven-plugin:sonar
       -Dsonar.organization=pravinmoreone-ux
       -Dsonar.projectKey=pravinmoreone-ux_pravin-devops-platform
       -Dsonar.qualitygate.wait=true
```

`qualitygate.wait=true` — the pipeline waits for SonarCloud to analyse and blocks if the quality gate fails. This prevents deploying code with new security vulnerabilities.

### 4. Key takeaway
- SonarCloud = SAST — finds code quality + security issues statically (without running code)
- Integrates with JaCoCo for code coverage measurement
- Quality gate must pass — blocks deployment if new vulnerabilities introduced
- Complements Trivy (infrastructure/container) — together they cover code + container security

---

## Q12. What is the difference between `run:` and `uses:` in a GitHub Actions step?

### 1. What is this question actually asking?
- Simple question about step types in GitHub Actions

### 2. Understand the concept
A step in GitHub Actions can either run a shell command (`run:`) or use a pre-built Action (`uses:`). Actions are reusable, packaged steps published to the GitHub Marketplace.

### 3. The actual answer

| | `run:` | `uses:` |
|--|--------|--------|
| What it does | Runs a shell command | Uses a pre-built Action |
| Example | `run: terraform fmt -check` | `uses: actions/checkout@v4` |
| Flexibility | Full shell flexibility | Structured, reusable |
| Versioned? | No | Yes (`@v4`, `@main`, `@sha`) |

```yaml
steps:
  # Using an Action
  - uses: actions/checkout@v4

  # Running a shell command
  - run: mvn clean verify

  # Multi-line shell
  - run: |
      terraform init
      terraform validate
```

Best practice: Always pin Actions to a specific version (`@v4`) or commit SHA — not `@latest` or `@main`. This prevents supply chain attacks where a malicious update to an Action could compromise your pipeline.

### 4. Key takeaway
- `run:` = shell command, flexible, no versioning
- `uses:` = reusable Action, versioned, community-maintained
- Always pin `uses:` to a specific version (`@v4` not `@main`)
- For security-critical Actions, pin to full commit SHA: `uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683`

---

## Q13. What does `permissions:` do in a GitHub Actions workflow?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of least-privilege in CI/CD
- They want to know what risks you're mitigating with permission scoping

### 2. Understand the concept
By default, GitHub Actions has broad permissions — it can read and write to your repository, packages, issues, and more. The `permissions:` block restricts what the workflow can actually do. This limits blast radius if a step in the workflow is compromised (e.g., a malicious Action).

### 3. The actual answer
In your workflows:

```yaml
# terraform-ci.yml
permissions:
  id-token: write    # needed for OIDC token generation (AWS auth)
  contents: read     # needed to checkout code

# springboot-ci.yml
permissions:
  contents: write    # needed to commit Helm values update
  packages: write    # needed to push to GHCR
```

What each permission controls:

| Permission | What it allows |
|-----------|---------------|
| `contents: read` | Checkout code |
| `contents: write` | Push commits (Helm values update) |
| `packages: write` | Push to GHCR |
| `id-token: write` | Request OIDC token for AWS authentication |

Without `id-token: write`, the OIDC auth step would fail — GitHub can't generate the token.

### 4. Key takeaway
- `permissions:` = least-privilege for the workflow's `GITHUB_TOKEN`
- Restrict to only what the workflow actually needs
- `id-token: write` is required for OIDC → AWS auth
- `packages: write` is required for GHCR push
- Omitting `permissions:` = broad default permissions (security risk)

---

## Q14. What is a GitHub Actions artifact and when would you use it?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how to pass files between jobs
- They want to see if you know when artifacts are needed

### 2. Understand the concept
Each GitHub Actions job runs on a separate, fresh machine. By default, files created in Job 1 are not available in Job 2. Artifacts are a way to upload files from one job and download them in another (or keep them after the workflow finishes for debugging).

### 3. The actual answer
Common use cases:
- Upload test results/JaCoCo reports for download after the run
- Pass a built JAR or Docker image metadata between jobs
- Store Terraform plan for review before apply (audit trail)

In your repo, the Terraform plan file (`tfplan`) is created and used within the same job — no artifact upload needed. But in a more advanced setup, you'd:
1. Job 1: `terraform plan -out=tfplan` → upload artifact
2. Job 2 (manual approval): download artifact → `terraform apply tfplan`

```yaml
- name: Upload Terraform Plan
  uses: actions/upload-artifact@v4
  with:
    name: tfplan
    path: terraform/tfplan
    retention-days: 5

- name: Download Terraform Plan
  uses: actions/download-artifact@v4
  with:
    name: tfplan
```

### 4. Key takeaway
- Artifacts = share files between jobs or preserve for post-run inspection
- Jobs run on separate machines — files don't persist between jobs without artifacts
- Set `retention-days` to control how long artifacts are kept (storage cost)
- For small files passed between jobs in same workflow, use `outputs:` instead

---

## Q15. What happens when a GitHub Actions workflow fails? How do you debug it?

### 1. What is this question actually asking?
- Practical troubleshooting question
- The interviewer wants to see your debugging process — not just "check the logs"

### 2. Understand the concept
When a step fails, the workflow stops at that step (by default), marks the job as failed, and sends a notification. You need to look at the logs to understand what went wrong.

### 3. The actual answer
Debugging process:

**Step 1 — Find the failing step**
Open GitHub → Actions → Failed run → Click the red ✗ job → Expand the failing step.

**Step 2 — Read the error message**
The last few lines of the failed step usually contain the actual error.

**Step 3 — Common failure categories**

| Failure | Likely cause |
|---------|-------------|
| `terraform fmt -check` fails | Poorly formatted `.tf` file — run `terraform fmt` locally |
| `terraform validate` fails | Syntax error or missing variable reference |
| OPA policy violation | Resource violates a security rule — check OPA output |
| Trivy HIGH/CRITICAL | CVE in base image or Terraform config — fix or suppress |
| SonarCloud quality gate fail | New bug/vulnerability in code — check SonarCloud dashboard |
| `docker push` denied | Wrong permissions or registry URL |
| `git push` fails | Branch protection blocking force push, or merge conflict |

**Step 4 — Re-run failed jobs**
GitHub Actions → Re-run failed jobs (saves time, doesn't re-run already passing steps).

**Step 5 — Enable debug logging**
Set secret `ACTIONS_RUNNER_DEBUG=true` and `ACTIONS_STEP_DEBUG=true` for verbose output.

### 4. Key takeaway
- Open the failing step in the Actions UI — the error is usually right there
- `--previous` flag for container logs, failing step for CI logs
- Re-run failed jobs to retry without re-running everything
- Enable debug secrets for verbose output when standard logs aren't enough

---

## Q16. What is `continue-on-error` and when should you use it?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand step-level error handling in workflows

### 2. Understand the concept
By default, if any step fails, the job stops and all subsequent steps are skipped. `continue-on-error: true` lets the job continue even if a step fails. This is useful for non-critical steps where failure shouldn't block the pipeline.

### 3. The actual answer
```yaml
- name: Optional security scan
  continue-on-error: true
  run: optional-scanner --check
```

When to use:
- Notifications (Slack/email) — failure to notify shouldn't block deployment
- Non-blocking scans or reports — you want to collect the data but not fail the build
- Experimental steps — testing new tools without blocking the pipeline

When NOT to use:
- Security gates (Trivy, OPA) — failures should block
- Tests — failing tests should block deployment
- Build steps — failed build shouldn't proceed to push

In your repo, all security gates use default behavior (`continue-on-error` not set = fails on error). This is correct — security violations should block the pipeline.

### 4. Key takeaway
- `continue-on-error: true` = step failure doesn't fail the job
- Use for optional/non-critical steps only
- Never use for security gates, tests, or critical build steps
- The step still shows as failed (orange) — just doesn't block subsequent steps

---

## Q17. What is a reusable workflow in GitHub Actions?

### 1. What is this question actually asking?
- The interviewer wants to know if you're aware of DRY (Don't Repeat Yourself) patterns in CI/CD
- They are checking if you know how to share pipeline logic across multiple workflows

### 2. Understand the concept
If you have 5 microservices that all need the same CI steps (test → scan → build → push), you'd normally copy-paste the same YAML 5 times. Reusable workflows let you define the logic once and call it from multiple workflows — like a function call.

### 3. The actual answer
A reusable workflow is a workflow file that can be called by other workflows using `workflow_call` trigger:

```yaml
# .github/workflows/docker-build.yml (reusable)
on:
  workflow_call:
    inputs:
      image_name:
        required: true
        type: string
    secrets:
      GITHUB_TOKEN:
        required: true

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: docker build -t ${{ inputs.image_name }} .
```

```yaml
# .github/workflows/springboot-ci.yml (caller)
jobs:
  build:
    uses: ./.github/workflows/docker-build.yml
    with:
      image_name: ghcr.io/myorg/springboot
    secrets: inherit
```

Your repo doesn't use reusable workflows currently (one service, one workflow). For multiple services, reusable workflows eliminate duplication.

### 4. Key takeaway
- Reusable workflows = DRY pipelines for multiple services with similar CI steps
- Called via `uses: ./.github/workflows/reusable.yml` with `workflow_call` trigger
- Inputs = parameters passed to the workflow
- `secrets: inherit` = pass all secrets from caller to reusable workflow

---

## Q18. What does `fetch-depth: 0` do in actions/checkout and why does Spring Boot CI need it?

### 1. What is this question actually asking?
- Specific question about a setting in your actual pipeline
- The interviewer wants to know if you understand why full git history is needed

### 2. Understand the concept
By default, `actions/checkout` does a shallow clone — only the latest commit. This is faster. But some tools need the full git history to work correctly.

### 3. The actual answer
```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0   # fetch full history
```

Your Spring Boot CI needs `fetch-depth: 0` because:
1. **SonarCloud**: Needs full git history to:
   - Identify which commits introduced which issues
   - Blame analysis (which author introduced a bug)
   - Accurately calculate new vs existing issues in the quality gate
   - Without full history, SonarCloud may report all issues as "new" and fail the quality gate

2. **Git operations**: The last step commits and pushes Helm values update — needs the full branch state.

`fetch-depth: 1` (default): Only the latest commit. Faster, no history.
`fetch-depth: 0`: Full history. Slower to clone but needed for SonarCloud.

### 4. Key takeaway
- `fetch-depth: 0` = full git history clone
- Required by SonarCloud for accurate issue tracking
- Default `fetch-depth: 1` = shallow clone (faster for simple builds)
- Terraform CI uses default (no `fetch-depth`) — it doesn't need history

---

## Q19. How would you add a manual approval step before deploying to production?

### 1. What is this question actually asking?
- The interviewer wants to know if you can implement CD with a human gate
- They are checking if you know GitHub Environments and protection rules

### 2. Understand the concept
Continuous Deployment automatically deploys every merge to `main`. But for production, you might want a human to review the Terraform plan or verify the staging environment first before approving the production deployment.

### 3. The actual answer
GitHub Actions supports manual approval via **Environments** with protection rules:

**Step 1 — Create Environment in GitHub**
Repository → Settings → Environments → New environment: `production`
→ Add required reviewers (your account)
→ Enable "Required reviewers" (1 approval needed)

**Step 2 — Reference the environment in the job**
```yaml
jobs:
  deploy:
    environment: production   # triggers approval gate
    runs-on: ubuntu-latest
    steps:
      - run: terraform apply tfplan
```

When the workflow reaches this job, GitHub pauses and sends an email/notification to required reviewers. The job only runs after someone approves.

For your Terraform workflow, a proper production pipeline would be:
```text
Job 1 (plan) → runs automatically
Job 2 (approval gate) → waits for human approval
Job 3 (apply) → runs after approval
```

### 4. Key takeaway
- GitHub Environments + required reviewers = manual approval gate
- Job pauses until a designated reviewer approves in GitHub UI
- Can also add wait timers (e.g., wait 1 hour before auto-proceed)
- Good pattern: auto-deploy to dev/staging, manual approval for production

---

## Q20. What is the purpose of the `working-directory` default in your Terraform workflow?

### 1. What is this question actually asking?
- Small detail question — the interviewer is checking if you understand how working directories work in multi-directory repos

### 2. Understand the concept
Your repo has multiple directories: `terraform/`, `apps/springboot/`, `helm/`, etc. When a step runs a command, it runs from the root of the repository by default. If your Terraform commands need to run from inside `terraform/`, you'd need to `cd terraform` before every command — or set a default working directory.

### 3. The actual answer
In your Terraform CI workflow:
```yaml
defaults:
  run:
    working-directory: terraform
```

This means every `run:` step in the job automatically runs from the `terraform/` directory — as if you had `cd terraform` at the start. Without this:
```yaml
# Without defaults - verbose
- run: cd terraform && terraform fmt -check
- run: cd terraform && terraform init -backend=false
- run: cd terraform && terraform validate
```

With defaults:
```yaml
# With defaults - clean
- run: terraform fmt -check
- run: terraform init -backend=false
- run: terraform validate
```

Similarly, Spring Boot CI sets `working-directory: apps/springboot` so Maven commands run from the Spring Boot directory.

### 4. Key takeaway
- `defaults.run.working-directory` = sets default directory for all `run:` steps in the job
- Avoids repeating `cd <dir>` before every command
- Useful in monorepos where different jobs work in different directories
- Override per-step with `working-directory: <path>` if one step needs a different directory

---

## Q21. What is `[skip ci]` in a commit message and how does it work?

### 1. What is this question actually asking?
- Simple question about controlling CI triggers
- The interviewer wants to know if you understand when to skip CI runs

### 2. Understand the concept
Sometimes you make commits that don't need CI — updating a README, adding a comment, or (in your case) the automated Helm values update made by `github-actions[bot]`. Running the full pipeline on these commits wastes time and CI minutes.

### 3. The actual answer
Adding `[skip ci]` anywhere in the commit message tells GitHub Actions to skip all workflow runs for that commit:

```bash
git commit -m "Update README typo [skip ci]"
git commit -m "Update Spring Boot image to sha-xxx [skip ci]"
```

**Important for your repo**: When `github-actions[bot]` commits the Helm values update, you DON'T want to skip CI — you want Argo CD to pick up the change. But you also don't want the Spring Boot CI to re-run (which would rebuild the same image and loop). Currently your pipeline relies on the path filter — the bot's commit only changes `helm/springboot/values.yaml`, which triggers Helm CI (lint only) but not Spring Boot CI.

Other ways to skip:
```yaml
# Skip specific workflow
if: "!contains(github.event.head_commit.message, '[skip ci]')"
```

### 4. Key takeaway
- `[skip ci]` in commit message = no workflows triggered for that commit
- Useful for docs, README changes, automated bot commits
- Alternatively, use path filters to naturally exclude irrelevant workflows
- Don't overuse — you want security and quality gates to run on real code changes
