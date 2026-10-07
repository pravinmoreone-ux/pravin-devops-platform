# Interview Prep — A: Terraform & Infrastructure as Code

> **Purpose**: Self-learning and revision document. These are not scripted interview answers — they are explanations to help you understand concepts and remember how they work in practice.

---

## Q1. What is Terraform and why do we use it instead of clicking in the AWS console?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the problem that IaC solves.
- They are testing whether you can explain the "why" — not just "what Terraform is."

### 2. Understand the concept
When you click in the AWS console to create a VPC, an EC2 instance, or an EKS cluster, you are doing it manually. This works once, but:
- You cannot reproduce it exactly next time
- There is no history of what you did or why
- If someone else changes something in the console, you won't know
- Doing the same thing across dev, staging, and production is error-prone

Terraform solves this by letting you describe your infrastructure in code files (`.tf`). You write what you want, Terraform figures out how to create it, and the code lives in Git — giving you version control, history, and repeatability.

### 3. The actual answer
Terraform is an Infrastructure as Code tool. You describe AWS resources (VPCs, EC2, EKS, IAM roles, etc.) in `.tf` files using a language called HCL (HashiCorp Configuration Language). When you run `terraform apply`, Terraform reads those files and creates, updates, or deletes resources in AWS to match what you described.

Key reasons to use it over the console:
- **Reproducible**: Run the same code and get the same infrastructure every time
- **Version controlled**: All changes tracked in Git with who changed what and why
- **Auditable**: `terraform plan` shows you exactly what will change before it happens
- **Consistent across environments**: Same code for dev, staging, production (with different variable values)

### 4. Practical commands / examples

Command:
```bash
terraform plan
```
Purpose: Shows what Terraform will create, change, or destroy — without doing anything yet.
What to look for: `+ create`, `~ update`, `- destroy` symbols next to each resource.

Command:
```bash
terraform apply
```
Purpose: Actually creates/updates/destroys resources in AWS.
What to look for: Each resource being created with its ID. Final line: `Apply complete! Resources: X added, Y changed, Z destroyed.`

### 5. Key takeaway
- Terraform replaces manual console clicking with repeatable, version-controlled code
- `plan` = preview, `apply` = execute
- Infrastructure described in `.tf` files using HCL
- Changes are tracked in Git — full audit trail

---

## Q2. What is Terraform state and why is it important?

### 1. What is this question actually asking?
- The interviewer is testing whether you understand how Terraform tracks what it has already created
- They want to know if you understand what happens when state gets out of sync or is lost

### 2. Understand the concept
When Terraform creates a resource (say, an EC2 instance), it needs to remember that it created it. Otherwise, the next time you run `terraform apply`, it won't know whether to create a new one or update the existing one.

Terraform solves this with a **state file** (`terraform.tfstate`). This file maps each resource in your `.tf` code to the real resource ID in AWS. Think of it as Terraform's memory.

### 3. The actual answer
Terraform state is a JSON file that stores the current state of all resources Terraform manages. It contains the real AWS resource IDs, attributes, and dependencies.

Without state:
- Terraform doesn't know what already exists
- It would try to create everything again on every `apply`

With state:
- Terraform compares your code with the state file
- Only changes the difference (create new resources, update changed ones, delete removed ones)

**Important**: In this repo, state is stored locally in `terraform/terraform.tfstate`. For production, you should use a remote backend (S3 + DynamoDB) so the team shares the same state and it doesn't get lost.

### 4. Practical commands / examples

Command:
```bash
terraform state list
```
Purpose: Lists all resources Terraform is tracking in the state file.
What to look for: Resource addresses like `aws_vpc.main`, `aws_eks_cluster.main`.

Command:
```bash
terraform state show aws_vpc.main
```
Purpose: Shows the full details of a specific resource in state.
What to look for: The actual AWS resource ID, CIDR block, and all attributes.

### 5. Key takeaway
- State file = Terraform's memory of what it created
- Without state, Terraform cannot manage existing resources
- Local state is fine for learning; production should use S3 remote backend
- Never delete the state file — you will lose track of all managed resources

---

## Q3. What is the difference between terraform plan and terraform apply?

### 1. What is this question actually asking?
- Simple question checking if you know the Terraform workflow
- They may follow up with: "When would you run plan without apply?"

### 2. Understand the concept
Think of it like a GPS giving you turn-by-turn directions before you start driving. `plan` shows you the route. `apply` actually drives the car.

### 3. The actual answer

| Command | What it does | Touches AWS? |
|---------|-------------|-------------|
| `terraform plan` | Reads your code + state, calculates what needs to change, shows a preview | No |
| `terraform apply` | Runs the plan and makes the actual changes in AWS | Yes |

`plan` is safe to run at any time. It is read-only.
`apply` creates/updates/destroys real resources and can cost money.

In CI/CD (like your `terraform-ci.yml`), `plan` runs on every PR so reviewers can see what will change before merging. `apply` only runs after merge to `main`.

### 4. Practical commands / examples

Command:
```bash
terraform plan -out=tfplan
```
Purpose: Saves the plan to a file so `apply` uses exactly what was reviewed.
What to look for: The plan summary at the bottom: `Plan: X to add, Y to change, Z to destroy.`

Command:
```bash
terraform apply tfplan
```
Purpose: Applies the saved plan file — guarantees exactly what was reviewed gets applied.

### 5. Key takeaway
- `plan` = preview, safe, no changes made
- `apply` = execute, real AWS changes
- Always review plan output before applying
- Save plan to file in CI/CD for consistency between plan and apply steps

---

## Q4. What is a Terraform remote backend and why do you need it?

### 1. What is this question actually asking?
- The interviewer is checking if you understand the limitations of local state
- They want to know if you understand team collaboration and state locking

### 2. Understand the concept
By default, Terraform stores the state file on your local laptop. This works fine alone, but causes problems when a team uses Terraform:
- Two people run `apply` at the same time → state gets corrupted
- Someone's laptop dies → state file is lost → Terraform loses track of all AWS resources
- You can't see what a colleague changed

A remote backend stores the state file in a shared, central location (S3) and uses a lock (DynamoDB) to prevent two people from running `apply` simultaneously.

### 3. The actual answer
A remote backend moves the `terraform.tfstate` file from your local machine to a shared storage location. The most common AWS setup is:
- **S3 bucket**: stores the state file
- **DynamoDB table**: provides state locking (prevents concurrent applies)

This means:
- All team members share the same state
- Only one person can run `apply` at a time (locking)
- State is backed up and versioned in S3

In this repo, state is currently local. For production, you would add this to `versions.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "pravin-devops-platform-tfstate"
    key            = "terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "pravin-devops-platform-tflock"
    encrypt        = true
  }
}
```

### 4. Practical commands / examples

Command:
```bash
terraform init
```
Purpose: After adding a backend config, `init` migrates local state to S3.
What to look for: `Successfully configured the backend "s3"! Terraform will automatically use this backend unless the backend configuration changes.`

### 5. Key takeaway
- Local state = fine for solo learning, dangerous for teams
- Remote backend (S3 + DynamoDB) = shared state + locking
- State locking prevents two people corrupting state by running apply simultaneously
- Always encrypt state in S3 — it contains sensitive resource data

---

## Q5. What is terraform import and when would you use it?

### 1. What is this question actually asking?
- The interviewer wants to know how you handle resources that already exist in AWS but are not in Terraform state
- This is a common real-world scenario when a team starts using Terraform on existing infrastructure

### 2. Understand the concept
Imagine someone created an S3 bucket in the AWS console 6 months ago. Now you want to manage it with Terraform. If you write code for it and run `apply`, Terraform will try to create a new bucket (or fail if the name is taken). You need to tell Terraform: "This resource already exists — add it to your state file without creating it."

That is what `terraform import` does.

### 3. The actual answer
`terraform import` reads an existing AWS resource and adds it to the Terraform state file without creating or destroying anything. You still need to write the matching `.tf` code manually first.

Steps:
1. Write the `.tf` code describing the resource
2. Run `terraform import <resource_address> <aws_resource_id>`
3. Terraform adds it to state
4. Run `terraform plan` — should show no changes if your code matches reality

### 4. Practical commands / examples

Command:
```bash
terraform import aws_vpc.main vpc-0a1b2c3d4e5f
```
Purpose: Tells Terraform that `aws_vpc.main` in your code corresponds to `vpc-0a1b2c3d4e5f` in AWS.
What to look for: `Import successful! The resources that were imported are shown above.`

Command:
```bash
terraform plan
```
Purpose: Run after import to check if your `.tf` code matches the real resource.
What to look for: `No changes` = your code matches. Any changes shown = your code doesn't fully match the imported resource.

### 5. Key takeaway
- `import` = add existing AWS resource to Terraform state
- You must write the `.tf` code first — import only updates state, not code
- After import, run `plan` to verify your code matches the real resource
- Common use case: adopting existing infrastructure into Terraform management

---

## Q6. What happens if someone manually changes an AWS resource that Terraform manages?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of **drift** — when reality diverges from your code
- They want to know how Terraform detects and handles this situation

### 2. Understand the concept
Imagine Terraform created a security group that allows SSH from one IP. Someone logs into the AWS console and adds another IP. Now your Terraform code says one thing, but AWS has something different. This gap between code and reality is called **drift**.

### 3. The actual answer
When drift happens, the next `terraform plan` will show the difference. For example:

```text
~ aws_security_group.jump
  ~ ingress:
    + {cidr_blocks: ["203.0.113.0/32"], ...}  # added manually in console
```

Terraform will propose to **remove** the manually added rule (to bring reality back in line with code).

This is why Git + Terraform is the source of truth. Manual console changes should be avoided — they get overwritten on the next `apply`.

In your repo, Argo CD has a similar concept (`selfHeal`) for Kubernetes — it automatically reverts manual `kubectl` changes.

### 4. Practical commands / examples

Command:
```bash
terraform plan -refresh-only
```
Purpose: Refreshes the state file from the real AWS state without making any code changes. Shows you what has drifted.
What to look for: Any resources shown as changed = drift detected.

Command:
```bash
terraform apply -refresh-only
```
Purpose: Updates the state file to match current AWS reality (accepts the drift into state without reverting it).

> **Warning**: `terraform apply` (without -refresh-only) will revert the manual changes back to what your code says. This could delete things someone added manually.

### 5. Key takeaway
- Drift = gap between Terraform code and real AWS state
- `terraform plan` always detects drift and shows what needs to change
- Manual console changes will be reverted on next `apply`
- Use `-refresh-only` to inspect drift without reverting it

---

## Q7. What are Terraform variables and how do you pass values to them?

### 1. What is this question actually asking?
- The interviewer is checking if you understand how to make Terraform reusable across environments
- They want to know the different ways to pass variable values

### 2. Understand the concept
If you hardcode values like `"ap-south-1"` or `"t3.small"` directly in your `.tf` files, you cannot reuse the same code for different environments or regions. Variables let you define a placeholder and fill in the value separately.

### 3. The actual answer
Variables are declared in `variables.tf` with a name, type, description, and optional default. Values are passed in multiple ways:

| Method | Example | Priority |
|--------|---------|----------|
| Default in `variables.tf` | `default = "ap-south-1"` | Lowest |
| `terraform.tfvars` file | `aws_region = "us-east-1"` | Medium |
| `-var` flag | `terraform apply -var="aws_region=us-east-1"` | High |
| Environment variable | `export TF_VAR_aws_region=us-east-1` | High |
| `-var-file` flag | `terraform apply -var-file=prod.tfvars` | High |

In your repo, `terraform/variables.tf` declares all variables with sensible defaults, and `terraform.tfvars` overrides specific values.

### 4. Practical commands / examples

```hcl
# variables.tf
variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

# terraform.tfvars
aws_region = "us-east-1"

# Reference in code
provider "aws" {
  region = var.aws_region
}
```

### 5. Key takeaway
- Variables make Terraform code reusable across environments
- `terraform.tfvars` is the most common way to supply values
- Never commit sensitive values (passwords, keys) in `.tfvars` files — use environment variables or secrets manager
- `var.` prefix is used to reference variables in code

---

## Q8. What are Terraform outputs and when would you use them?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how to extract information from Terraform after a resource is created
- Common follow-up: "How do you pass outputs between modules?"

### 2. Understand the concept
After Terraform creates a VPC, you need its ID to create subnets inside it. After creating an EKS cluster, you need its endpoint to configure `kubectl`. Outputs let you expose these values so they can be displayed, used by other Terraform configurations, or read by CI/CD scripts.

### 3. The actual answer
Outputs are declared in `outputs.tf`. After `terraform apply`, they are printed on screen and stored in state so other configurations can read them.

In your repo, `terraform/outputs.tf` exports values like:
- `jump_public_ip` — so you know which IP to SSH to
- `eks_cluster_name` — so Ansible or CI/CD can reference it
- `eks_cluster_endpoint` — for kubectl configuration

### 4. Practical commands / examples

```hcl
# outputs.tf
output "jump_public_ip" {
  description = "Jump server public IP"
  value       = aws_instance.jump.public_ip
}
```

Command:
```bash
terraform output jump_public_ip
```
Purpose: Reads a specific output value after apply.
What to look for: The actual IP address printed.

Command:
```bash
terraform output -json
```
Purpose: Gets all outputs in JSON format — useful for scripting.

### 5. Key takeaway
- Outputs expose resource attributes after `apply`
- Used to pass values between configurations, display to users, or feed into scripts
- Stored in state — can be read later without re-running apply
- Sensitive outputs should use `sensitive = true` to hide values from console output

---

## Q9. What is the Terraform dependency graph and how does Terraform know the order to create resources?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how Terraform handles resource creation order automatically
- They are testing whether you understand explicit vs implicit dependencies

### 2. Understand the concept
Some resources must be created before others. You cannot create a subnet before the VPC exists. You cannot create an EC2 instance before the security group exists. Terraform figures out this order automatically by building a dependency graph.

### 3. The actual answer
Terraform builds a directed acyclic graph (DAG) of all resources. It figures out dependencies in two ways:

**Implicit dependencies** — when you reference one resource inside another:
```hcl
resource "aws_subnet" "public_a" {
  vpc_id = aws_vpc.main.id   # Terraform sees this reference
}                             # and knows: create VPC before subnet
```

**Explicit dependencies** — when you use `depends_on`:
```hcl
resource "aws_eks_cluster" "main" {
  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}
```

Terraform creates independent resources in parallel and waits for dependencies to complete first.

### 4. Practical commands / examples

Command:
```bash
terraform graph | dot -Tsvg > graph.svg
```
Purpose: Generates a visual dependency graph of your resources.
What to look for: Arrows showing which resource depends on which.

### 5. Key takeaway
- Terraform automatically determines creation order via dependency graph
- Referencing `resource_type.name.attribute` creates an implicit dependency
- Use `depends_on` only when there is no natural reference between resources
- Independent resources are created in parallel — speeds up `apply`

---

## Q10. What is the difference between terraform destroy and removing a resource from code?

### 1. What is this question actually asking?
- The interviewer is testing whether you understand how Terraform handles resource deletion
- They want to know if you know the difference between destroying everything vs removing one resource

### 2. Understand the concept
There are two ways to delete a resource with Terraform. One deletes everything. The other deletes just what you removed from code. They are very different.

### 3. The actual answer

| Action | What happens |
|--------|-------------|
| `terraform destroy` | Destroys ALL resources Terraform manages — the entire infrastructure |
| Remove resource from `.tf` code + `terraform apply` | Destroys only that specific resource |

**Removing from code + apply** is the correct way to delete individual resources in normal operations.

**`terraform destroy`** is used when you want to tear down an entire environment (e.g., after a demo or to save costs).

> **Warning**: `terraform destroy` is irreversible. It will delete your EKS cluster, EC2 instances, VPC, and all data. Always confirm before running.

### 4. Practical commands / examples

Command:
```bash
terraform destroy -target=aws_instance.jump
```
Purpose: Destroys only the jump server EC2 instance, not everything else.
What to look for: Confirmation prompt. Type `yes` to confirm.

> **Warning**: `-target` flag is for emergencies only. It can leave state inconsistent if the resource has dependents.

### 5. Key takeaway
- `terraform destroy` = destroy everything (use for full teardown)
- Remove from code + `apply` = delete specific resources (normal workflow)
- Always run `plan` before `destroy` to see what will be deleted
- `destroy` is irreversible — data on EBS volumes, RDS databases, etc. will be gone

---

## Q11. What is terraform fmt and why does it matter in CI/CD?

### 1. What is this question actually asking?
- Simple question about code formatting and automation
- May lead to: "What happens if fmt check fails in your pipeline?"

### 2. Understand the concept
HCL has a standard formatting style — indentation, spacing, alignment of `=` signs. `terraform fmt` automatically reformats your code to match this standard. In CI/CD, `terraform fmt -check` verifies the formatting without changing files — and fails the pipeline if the formatting is wrong.

### 3. The actual answer
`terraform fmt` enforces consistent formatting across all `.tf` files. In your `terraform-ci.yml`, it runs as the first step so poorly formatted code fails fast before wasting time on init, validate, or plan.

Why it matters:
- Consistent code style across team members
- Easier code reviews (no formatting noise in diffs)
- Fails early in the pipeline — fast feedback

### 4. Practical commands / examples

Command:
```bash
terraform fmt -recursive
```
Purpose: Formats all `.tf` files in the current directory and subdirectories.
What to look for: No output = everything was already formatted. File names printed = those files were reformatted.

Command:
```bash
terraform fmt -check -recursive
```
Purpose: Checks formatting without changing files. Exits with code 1 if any file needs formatting (used in CI).
What to look for: Exit code 0 = all formatted. Exit code 1 = formatting needed (pipeline fails).

### 5. Key takeaway
- `terraform fmt` = auto-formatter for HCL files
- `fmt -check` = verify formatting in CI without changing files
- Always run `terraform fmt` before committing
- Most IDEs have a Terraform extension that auto-formats on save

---

## Q12. What is terraform validate and what does it check?

### 1. What is this question actually asking?
- The interviewer wants to know the difference between syntax checking and actual cloud validation
- Common follow-up: "Does validate check if the AMI ID exists in AWS?"

### 2. Understand the concept
`terraform validate` checks that your HCL code is syntactically correct and internally consistent. It does NOT connect to AWS — it cannot check whether a resource actually exists, whether your AMI ID is valid, or whether you have permission to create a resource.

### 3. The actual answer
`terraform validate` checks:
- HCL syntax is valid (no typos, missing brackets)
- Required arguments are provided
- Variable references are correct
- Resource types exist in the provider

It does NOT check:
- Whether the AWS account has permission to create the resource
- Whether an AMI ID, key pair name, or subnet ID actually exists
- Whether resource limits or quotas are exceeded

These are only caught at `terraform plan` or `terraform apply`.

### 4. Practical commands / examples

Command:
```bash
terraform validate
```
Purpose: Validates HCL syntax and configuration correctness.
What to look for: `Success! The configuration is valid.` = all good. Error messages with file and line number = fix those.

### 5. Key takeaway
- `validate` = syntax and logical consistency check, no AWS calls
- Does not validate if real AWS resources (AMIs, key pairs) exist
- Fast to run — good first gate in CI/CD
- `fmt → validate → plan` is the standard CI order

---

## Q13. What is the Terraform lock file (.terraform.lock.hcl) and should it be committed to Git?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand provider version locking
- They are checking if you follow good practices around reproducibility

### 2. Understand the concept
When you run `terraform init`, Terraform downloads provider plugins (like the AWS provider). Without a lock file, it might download a different version tomorrow than it did today — which could cause unexpected behavior.

The lock file records the exact version and checksum of every provider that was downloaded. It is like a `package-lock.json` in Node.js or a `Pipfile.lock` in Python.

### 3. The actual answer
`.terraform.lock.hcl` is automatically created/updated by `terraform init`. It records:
- The exact provider version selected
- Checksums to verify the provider binary wasn't tampered with

**Yes, commit it to Git.** This ensures:
- Everyone on the team uses the exact same provider version
- CI/CD uses the same version as local development
- Provider upgrades are explicit (run `terraform init -upgrade` to update the lock file)

### 4. Practical commands / examples

Command:
```bash
terraform init -upgrade
```
Purpose: Updates the lock file to the latest allowed provider versions (within your version constraints).
What to look for: Updated version numbers in `.terraform.lock.hcl`.

### 5. Key takeaway
- Lock file pins exact provider versions for reproducibility
- Always commit `.terraform.lock.hcl` to Git
- Update it explicitly with `terraform init -upgrade` when you want newer providers
- The `.terraform/` directory (cached providers) should NOT be committed — it's in `.gitignore`

---

## Q14. What are Terraform modules and why would you use them?

### 1. What is this question actually asking?
- The interviewer is checking if you understand code reuse and organisation in Terraform
- Common follow-up: "Have you written a module? What did it do?"

### 2. Understand the concept
Imagine you need to create the same VPC setup in 3 different AWS accounts. Without modules, you copy-paste the same 100 lines of code 3 times. A module lets you write it once and call it 3 times with different inputs.

A module is just a folder of `.tf` files that accepts inputs (variables) and produces outputs.

### 3. The actual answer
A Terraform module is a reusable package of Terraform code. Every Terraform project already has a root module (the main directory). Child modules are called from the root using a `module` block.

Modules help with:
- **Reuse**: Write once, use many times
- **Abstraction**: Hide complexity — a "vpc" module caller doesn't need to know about subnets, route tables, etc.
- **Consistency**: Same pattern enforced across environments

In your current repo, all resources are in the root module. For a larger project, you would extract VPC, EKS, EC2 into separate modules.

### 4. Practical commands / examples

```hcl
# Calling a VPC module
module "vpc" {
  source      = "./modules/vpc"    # local module
  cidr_block  = "10.40.0.0/16"
  environment = var.environment
}

# Or from Terraform Registry
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"
  cluster_name = "my-cluster"
}
```

### 5. Key takeaway
- Modules = reusable, parameterized Terraform code packages
- Root module = your main `.tf` files; child modules = folders called with `module` block
- Use modules to avoid copy-pasting and enforce consistency
- Terraform Registry has pre-built community modules (e.g., `terraform-aws-modules/eks`)

---

## Q15. What is the difference between count and for_each in Terraform?

### 1. What is this question actually asking?
- The interviewer is testing if you know how to create multiple similar resources dynamically
- They may ask about the pitfalls of each approach

### 2. Understand the concept
Sometimes you need to create the same type of resource multiple times — like 3 subnets or 5 IAM users. Instead of writing 5 separate resource blocks, you can use `count` or `for_each` to loop.

The difference is how they identify each resource:
- `count` uses index numbers (0, 1, 2...)
- `for_each` uses keys from a map or set (names, IDs)

### 3. The actual answer

**count**: Creates N copies of a resource, identified by index.
```hcl
resource "aws_instance" "web" {
  count         = 3
  ami           = "ami-xxx"
  instance_type = "t3.small"
}
# Creates: aws_instance.web[0], aws_instance.web[1], aws_instance.web[2]
```

**Problem with count**: If you remove index 1, Terraform renumbers [2] to [1] — causing unintended destroy/recreate.

**for_each**: Creates one resource per key in a map/set, identified by key name.
```hcl
resource "aws_instance" "web" {
  for_each      = toset(["web-a", "web-b", "web-c"])
  ami           = "ami-xxx"
  instance_type = "t3.small"
}
# Creates: aws_instance.web["web-a"], aws_instance.web["web-b"], aws_instance.web["web-c"]
```

**Advantage**: Removing "web-b" only destroys that instance — others are unaffected.

**Rule of thumb**: Use `count` for simple toggles (0 or 1). Use `for_each` when creating multiple named resources.

### 4. Practical commands / examples

Command:
```bash
terraform state list
```
Purpose: See how Terraform named the resources after apply.
What to look for: `aws_instance.web[0]` (count) vs `aws_instance.web["web-a"]` (for_each)

### 5. Key takeaway
- `count` = indexed (0, 1, 2) — prone to cascading destroy on removal
- `for_each` = key-based (name) — safer, more explicit
- Prefer `for_each` for production resources
- `count = 0` is a common pattern for conditionally creating a resource

---

## Q16. What is terraform taint and terraform untaint? (deprecated — what replaced it?)

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how to force-recreate a resource
- They may also be testing whether you know `taint` was deprecated in Terraform 0.15.2

### 2. Understand the concept
Sometimes a resource gets into a broken state — an EC2 instance that's running but not responding, or a Kubernetes cluster that partially failed. You want Terraform to destroy and recreate it on the next `apply`, but the resource still exists in state as "healthy."

`taint` marked a resource for forced recreation. It was replaced by `-replace` flag.

### 3. The actual answer
`terraform taint` (deprecated since v0.15.2) marked a resource in state so it would be destroyed and recreated on the next `apply`.

The replacement is the `-replace` flag directly on `plan` or `apply`:

```bash
terraform apply -replace="aws_instance.jump"
```

This is cleaner — it shows the replacement in the plan output and applies it in one step.

### 4. Practical commands / examples

Command:
```bash
terraform apply -replace="aws_instance.jump"
```
Purpose: Forces Terraform to destroy and recreate the jump server EC2 instance.
What to look for: `-/+ aws_instance.jump (tainted)` in the plan output.

> **Warning**: This destroys the resource first. Any data on the instance will be lost unless stored on a separate EBS volume or backed up.

### 5. Key takeaway
- `terraform taint` is deprecated — use `terraform apply -replace` instead
- Useful when a resource is in a broken state but still exists
- Shows up in plan as `-/+` (destroy then create)
- Never use on stateful resources (RDS, EBS) without understanding data loss risk

---

## Q17. How does Terraform handle sensitive values like passwords and API keys?

### 1. What is this question actually asking?
- The interviewer is testing your security awareness within Terraform
- They want to know how you prevent secrets from appearing in logs, plan output, or state

### 2. Understand the concept
Terraform code is stored in Git. Plan output is shown in CI/CD logs. State files contain all resource attributes. If you put a database password or API key in your code, it will appear in all three places — which is a serious security risk.

### 3. The actual answer
Terraform has several mechanisms for handling sensitive values:

**1. Sensitive variables** — mark a variable as sensitive so it's hidden from plan output:
```hcl
variable "db_password" {
  type      = string
  sensitive = true
}
```

**2. Sensitive outputs** — hides output value from terminal:
```hcl
output "db_password" {
  value     = aws_db_instance.main.password
  sensitive = true
}
```

**3. Environment variables** — pass secrets without putting them in files:
```bash
export TF_VAR_db_password="mysecretpassword"
terraform apply
```

**4. AWS Secrets Manager / SSM Parameter Store** — read secrets at runtime:
```hcl
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "prod/db/password"
}
```

**Important**: Even with `sensitive = true`, the value is still stored in plain text in the state file. The state file must be encrypted (S3 with SSE + KMS) and access-controlled.

### 4. Practical commands / examples

Command:
```bash
terraform output -json | jq
```
Purpose: Check output values — sensitive values will show as `(sensitive value)`.

### 5. Key takeaway
- Never hardcode secrets in `.tf` files or `.tfvars` committed to Git
- Use `sensitive = true` to hide from plan/output display
- State file still contains the value — encrypt it with KMS in S3
- Best practice: read secrets from AWS Secrets Manager at runtime

---

## Q18. What is the difference between a data source and a resource in Terraform?

### 1. What is this question actually asking?
- The interviewer is checking if you understand the difference between creating vs reading existing infrastructure
- Common follow-up: "Give me an example of when you'd use a data source."

### 2. Understand the concept
A **resource** tells Terraform to create something. A **data source** tells Terraform to read something that already exists — without creating or managing it.

### 3. The actual answer

| | Resource | Data Source |
|--|---------|-------------|
| Keyword | `resource` | `data` |
| Action | Creates/manages | Reads existing |
| In state? | Yes | No |
| Destroys on `destroy`? | Yes | No |
| Example | Create an EC2 instance | Read the latest Amazon Linux AMI ID |

In your repo, `terraform/jump_server.tf` uses a data source to find the latest Amazon Linux 2023 AMI:

```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}
```

This reads the current latest AMI from AWS. If you used a hardcoded AMI ID, it could become outdated or not exist in a different region.

### 4. Practical commands / examples

```hcl
# Data source: read existing VPC
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["my-existing-vpc"]
  }
}

# Resource: create subnet in that existing VPC
resource "aws_subnet" "new" {
  vpc_id     = data.aws_vpc.existing.id
  cidr_block = "10.0.1.0/24"
}
```

### 5. Key takeaway
- `resource` = Terraform creates and manages it
- `data` = Terraform reads existing information, does not create or destroy
- Data sources are useful for: AMI IDs, existing VPCs, account IDs, Route53 zones
- Data sources are not stored in state — they're queried fresh each `plan`

---

## Q19. What is OPA (Open Policy Agent) and how does it work with Terraform?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand policy-as-code and how to enforce rules on infrastructure
- They are testing whether you know how OPA fits into the CI/CD pipeline

### 2. Understand the concept
Imagine you have a rule: "No EC2 instance in this company can be larger than t3.large." You could tell every developer verbally, write it in a document, or hope code reviews catch it. Or you can enforce it automatically in the CI/CD pipeline — so the pipeline fails if someone tries to create a c5.4xlarge instance.

OPA is a policy engine. You write rules in a language called Rego, and OPA evaluates data against those rules and returns a decision (allow/deny).

### 3. The actual answer
In your repo, OPA runs in the Terraform CI pipeline:

1. Terraform runs `terraform plan -out=tfplan`
2. `terraform show -json tfplan > tfplan.json` converts the plan to JSON
3. OPA reads `tfplan.json` and evaluates it against your `.rego` policy files
4. If any deny rule triggers, the pipeline fails

Your `policy/terraform/security.rego` has 12 deny rules covering:
- Only approved EC2 instance types
- EBS encryption required
- IMDSv2 required
- No 0.0.0.0/0 on sensitive ports
- EKS private endpoint required
- KMS key rotation required
- etc.

OPA catches these issues before any resource is created in AWS.

### 4. Practical commands / examples

Command:
```bash
opa eval \
  --format=json \
  -d policy/terraform/security.rego \
  -i terraform/tfplan.json \
  "data.terraform.security.deny"
```
Purpose: Evaluates the Terraform plan against your security policy.
What to look for: Empty array `[]` = no violations. Array with strings = policy violation messages.

```rego
# Example rule in security.rego
deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_instance"
  resource.change.after.metadata_options.http_tokens != "required"
  msg := sprintf("EC2 instance '%s' must require IMDSv2", [resource.address])
}
```

### 5. Key takeaway
- OPA = policy engine that evaluates data against rules written in Rego
- In Terraform CI: plan → JSON → OPA evaluates → fail if deny rules trigger
- Catches infrastructure misconfigurations before resources are created
- Policy code lives in `policy/terraform/` — versioned in Git alongside infrastructure code

---

## Q20. What is Trivy and what does it scan in a Terraform context?

### 1. What is this question actually asking?
- The interviewer wants to know how you scan IaC for misconfigurations
- They may ask: "What is the difference between OPA and Trivy for Terraform?"

### 2. Understand the concept
Trivy is a security scanner made by Aqua Security. It can scan container images, file systems, Git repos, and — relevant here — Terraform configuration files for known misconfigurations.

The key difference from OPA: Trivy uses a built-in library of known misconfiguration rules (like AWS security best practices). OPA uses custom rules you write yourself. Both complement each other.

### 3. The actual answer
In your repo, Trivy scans the `terraform/` directory:

```yaml
# From terraform-ci.yml
- name: Trivy Terraform Security Scan
  run: trivy config . --severity HIGH,CRITICAL --exit-code 1 --ignorefile ../.trivyignore
```

What Trivy checks in Terraform:
- Security groups open to the internet
- Unencrypted S3 buckets, EBS volumes
- Public RDS instances
- Missing CloudTrail logging
- No MFA on root account (if detectable)
- IMDSv1 enabled on EC2

`--exit-code 1` means the pipeline fails on HIGH or CRITICAL findings.

`.trivyignore` suppresses known acceptable exceptions — in your repo, `AWS-0104` (unrestricted egress) is suppressed with a documented justification.

### 4. Practical commands / examples

Command:
```bash
trivy config terraform/ --severity HIGH,CRITICAL
```
Purpose: Scans all `.tf` files for HIGH and CRITICAL misconfigurations.
What to look for: Each finding shows: Check ID, Severity, Resource, Description, and how to fix it.

Command:
```bash
trivy config terraform/ --severity HIGH,CRITICAL --ignorefile .trivyignore
```
Purpose: Same scan but suppresses known accepted exceptions.

### 5. Key takeaway
- Trivy scans Terraform code for known misconfiguration patterns (pre-built rules)
- OPA enforces your custom business rules — both complement each other
- `--exit-code 1` makes the pipeline fail on findings — acts as a quality gate
- Document suppressed findings in `.trivyignore` with justification
- Trivy also scans container images (your Spring Boot image is scanned too)

---

## Q21. How do you manage multiple environments (dev, staging, prod) in Terraform?

### 1. What is this question actually asking?
- The interviewer wants to know how you handle environment-specific configuration in Terraform
- They are checking if you know the tradeoffs between different approaches

### 2. Understand the concept
You want the same infrastructure in dev and prod — same VPC structure, same EKS setup — but with different sizes, different CIDR blocks, or different retention periods. The challenge is doing this without duplicating your code.

### 3. The actual answer
There are three common approaches:

**1. Separate `.tfvars` files per environment**
```bash
terraform apply -var-file=dev.tfvars
terraform apply -var-file=prod.tfvars
```
Simple. Same code, different values. Works well for small projects.

**2. Terraform Workspaces**
```bash
terraform workspace new dev
terraform workspace new prod
terraform workspace select dev
terraform apply
```
Each workspace has its own state file. Code is the same; `terraform.workspace` variable lets you switch values based on environment.

**3. Separate directories per environment**
```text
environments/
  dev/
    main.tf   (calls modules)
    dev.tfvars
  prod/
    main.tf   (same modules, different values)
    prod.tfvars
```
Most explicit and safest for production. Changes to prod require editing prod directory specifically.

In your repo, a single environment (dev) is used with defaults in `variables.tf` and overrides in `terraform.tfvars`.

### 4. Key takeaway
- Small projects: separate `.tfvars` files per environment
- Medium projects: Terraform workspaces
- Large/production projects: separate directories per environment (safest isolation)
- Never share state between environments — dev changes must not affect prod state
