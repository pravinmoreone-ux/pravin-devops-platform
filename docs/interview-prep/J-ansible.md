# Ansible Interview Prep — Level 2 DevOps

---

## Q1: What is Ansible and how does it differ from other configuration management tools?

### What is this question actually asking?
- Core understanding of Ansible's architecture (agentless, push-based)
- How it compares to Chef, Puppet, SaltStack (agent-based, pull-based)
- Why "agentless" matters for operations

### Understand the concept
Ansible is a configuration management and automation tool. Unlike Chef or Puppet which require an agent installed on every managed node, Ansible connects over SSH (or WinRM for Windows) and pushes modules to run. No daemon, no database, no master server — just your control machine and SSH access.

**Analogy**: Chef/Puppet = hiring a full-time caretaker for each house. Ansible = you visiting each house with a checklist and doing the work yourself.

### The actual answer
- **Agentless**: No software on target nodes, only Python (standard on Linux)
- **Push model**: Control machine initiates; no polling interval
- **Declarative YAML**: Playbooks describe desired state
- **Idempotent modules**: Re-running produces same result
- **Inventory-based**: Static or dynamic lists of hosts/groups

### Practical commands / examples
```bash
# Test connectivity
ansible all -m ping -i inventory.yml

# Run ad-hoc command
ansible webservers -m shell -a "systemctl status nginx" -i inventory.yml

# Run playbook
ansible-playbook -i inventory.yml site.yml --check  # dry-run
ansible-playbook -i inventory.yml site.yml          # actual run
```
**What to look for**: `SUCCESS` vs `CHANGED` vs `FAILED` in output; `ok:` count in play recap.

### Key takeaway
- Agentless = less infrastructure, easier bootstrap, works on network devices
- Push model = immediate execution, no waiting for agent poll
- Idempotency = safe to re-run; only changes what needs changing

---

## Q2: Explain Ansible inventory — static vs dynamic, groups, variables.

### What is this question actually asking?
- How to organize target hosts
- Where to put host/group variables
- Dynamic inventory for cloud (AWS EC2, Azure, GCP)

### Understand the concept
Inventory tells Ansible *what* to manage. Static = YAML/INI file you maintain. Dynamic = script/plugin that queries cloud APIs at runtime. Groups let you target "webservers" or "databases" instead of individual IPs. Variables attached to hosts/groups customize behavior per environment.

### The actual answer
**Static inventory** (`inventory.yml`):
```yaml
all:
  children:
    webservers:
      hosts:
        web1:
          ansible_host: 10.0.1.10
          http_port: 8080
        web2:
          ansible_host: 10.0.1.11
    databases:
      hosts:
        db1:
          ansible_host: 10.0.2.10
  vars:
    ansible_user: ec2-user
    ansible_ssh_private_key_file: ~/.ssh/id_rsa
```

**Dynamic inventory** (`aws_ec2.yml` plugin):
```yaml
plugin: aws_ec2
regions:
  - us-east-1
filters:
  tag:Environment: production
keyed_groups:
  - prefix: tag
    key: Role
```

### Practical commands / examples
```bash
# List all hosts
ansible-inventory -i inventory.yml --list

# List hosts in group
ansible-inventory -i inventory.yml --list | jq '.webservers.hosts'

# Test dynamic inventory
ansible-inventory -i aws_ec2.yml --list
```
**What to look for**: JSON output structure; `ansible_host` vs `ansible_connection`; group hierarchy.

### Key takeaway
- Static = simple, version-controlled, good for fixed infra
- Dynamic = auto-discovers cloud resources, no manual updates
- Group vars = DRY principle; host vars = overrides
- `ansible-inventory --list` is your debugging friend

---

## Q3: What are Ansible modules? Name 10 commonly used ones and their purpose.

### What is this question actually asking?
- Modules are the units of work in Ansible
- Knowledge of breadth across: files, packages, services, cloud, users, etc.
- Understanding that modules are idempotent

### Understand the concept
Modules are reusable, standalone scripts that Ansible executes on target nodes. Each does one thing: install a package, copy a file, manage a service. You don't write shell commands — you call modules with parameters. Ansible ships with 3000+ modules; collections add more.

### The actual answer
| Module | Purpose |
|--------|---------|
| `copy` | Copy files from control to target |
| `template` | Render Jinja2 templates to target |
| `file` | Manage files/dirs/symlinks/permissions |
| `package` / `apt` / `yum` / `dnf` | Install/remove packages |
| `service` / `systemd` | Start/stop/enable services |
| `user` / `group` | Manage local accounts |
| `command` / `shell` | Run arbitrary commands (last resort) |
| `git` | Clone/pull repositories |
| `cron` | Manage cron jobs |
| `setup` | Gather facts (runs automatically) |

### Practical commands / examples
```bash
# View module docs
ansible-doc copy
ansible-doc -l | grep -i aws    # list AWS modules

# Ad-hoc usage
ansible web -m copy -a "src=local.conf dest=/etc/nginx/nginx.conf" -b
```
**What to look for**: `ansible-doc` shows parameters, examples, return values; prefer modules over `command`/`shell`.

### Key takeaway
- Modules = idempotent, documented, handle edge cases
- Use `package` (generic) over `apt`/`yum` for portability
- `command`/`shell` bypass idempotency — avoid unless necessary
- `setup` module runs automatically; facts available as `ansible_facts`

---

## Q4: Explain Ansible playbooks — structure, plays, tasks, handlers.

### What is this question actually asking?
- Playbook YAML structure
- Difference between play and task
- When handlers run (notify)

### Understand the concept
A **playbook** is a YAML file containing one or more **plays**. A **play** maps a group of hosts to a set of **tasks**. A **task** calls a module. A **handler** is a special task that runs *only* when notified by another task — typically for service restarts after config changes.

### The actual answer
```yaml
---
- name: Configure webservers          # Play 1
  hosts: webservers
  become: yes                         # sudo
  vars:
    nginx_version: "1.24"
  tasks:
    - name: Install nginx
      package:
        name: "nginx={{ nginx_version }}"
        state: present
      notify: Restart nginx           # triggers handler

    - name: Deploy nginx config
      template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      notify: Restart nginx

  handlers:
    - name: Restart nginx
      service:
        name: nginx
        state: restarted
```

### Practical commands / examples
```bash
# Syntax check
ansible-playbook site.yml --syntax-check

# Dry-run (check mode)
ansible-playbook site.yml --check

# Run with verbose output
ansible-playbook site.yml -vvv

# Run specific tags
ansible-playbook site.yml --tags "nginx,config"
```
**What to look for**: `PLAY [Configure webservers]`, `TASK [Install nginx]`, `RUNNING HANDLER [Restart nginx]` in output; handlers run at end of play, once per play.

### Key takeaway
- Play = host group + tasks + vars; Task = module call
- Handlers = deferred execution; deduplicated (multiple notifies = one run)
- `notify` must match handler `name` exactly
- Handlers run *after* all tasks in a play complete

---

## Q5: What are Ansible roles? How do you structure and use them?

### What is this question actually asking?
- Role directory structure (tasks, handlers, vars, templates, files, meta, defaults)
- Reusability and sharing via Ansible Galaxy
- `role` keyword vs `include_role`

### Understand the concept
Roles package related automation into a portable, reusable unit. Instead of one giant playbook, you split into roles: `nginx`, `postgresql`, `monitoring`. Each role has a standard directory layout. Roles can have dependencies (`meta/main.yml`) and default variables (`defaults/main.yml`).

### The actual answer
**Directory structure**:
```
roles/
  nginx/
    tasks/
      main.yml          # main task list
      install.yml       # included by main.yml
      config.yml
    handlers/
      main.yml
    templates/
      nginx.conf.j2
    files/
      ssl.crt
    vars/
      main.yml          # high-priority vars (hard to override)
    defaults/
      main.yml          # low-priority defaults (easy to override)
    meta/
      main.yml          # dependencies, galaxy info
    README.md
```

**Using a role in playbook**:
```yaml
- hosts: webservers
  roles:
    - role: nginx
      vars:
        nginx_port: 8080      # overrides defaults/main.yml
```

### Practical commands / examples
```bash
# Create role skeleton
ansible-galaxy role init nginx

# Install from Galaxy
ansible-galaxy install geerlingguy.nginx

# List installed roles
ansible-galaxy list
```
**What to look for**: `defaults/main.yml` = overrideable; `vars/main.yml` = wins over playbook vars; role dependencies auto-installed.

### Key takeaway
- Roles = DRY, shareable, testable units
- `defaults/` for defaults, `vars/` for constants
- `meta/main.yml` declares dependencies (e.g., `role: common` before `nginx`)
- Galaxy = community roles; vet before production use

---

## Q6: How does Ansible handle variable precedence? Explain the hierarchy.

### What is this question actually asking?
- Where variables can be defined (15+ levels)
- Which wins when same variable defined in multiple places
- Practical impact on role reusability

### Understand the concept
Ansible loads variables from many sources. The **last one loaded wins** (highest precedence). This lets you set defaults in roles, override per-environment, and force specific values at runtime. Knowing the order prevents "why is my variable not changing?" debugging.

### The actual answer
**Precedence (lowest → highest)**:
1. Role defaults (`defaults/main.yml`)
2. Inventory file/group vars
3. Inventory host vars
4. Playbook `vars:` section
5. Playbook `vars_files:`
6. Role `vars/main.yml`
7. Block vars (in tasks)
8. Task vars (inline)
9. `include_vars` / `set_fact`
10. Registered variables
11. Facts (`ansible_facts`)
12. Play `vars_prompt`
13. `--extra-vars` / `-e` (CLI) — **highest**

**Also**: `host_vars/` and `group_vars/` directories in inventory or playbook dir.

### Practical commands / examples
```bash
# Override at runtime (highest precedence)
ansible-playbook site.yml -e "nginx_version=1.25.0 environment=staging"

# Debug variable value
ansible-playbook site.yml -e "ansible_debug_var=nginx_version"

# Show all variables for a host
ansible web1 -m debug -a "var=hostvars[inventory_hostname]" -i inventory.yml
```
**What to look for**: `-e` always wins; role `defaults` lose to inventory; `vars` beats `defaults`.

### Key takeaway
- `-e` (extra vars) = ultimate override, use for CI/CD injection
- Role `defaults/main.yml` = safe defaults users can override
- Inventory `group_vars/all` = site-wide settings
- `set_fact` in tasks = runtime computed values

---

## Q7: What are Ansible facts? How do you use custom facts?

### What is this question actually asking?
- Automatic system discovery (`setup` module)
- Accessing facts in templates/tasks (`ansible_distribution`, `ansible_memtotal_mb`)
- Custom facts for application-specific data

### Understand the concept
Facts are system properties Ansible gathers automatically before running tasks (via `setup` module). They include OS, network, disks, CPU, memory, environment variables. You reference them as `ansible_facts['distribution']` or simply `ansible_distribution`. Custom facts let you inject your own data — either via `/etc/ansible/facts.d/` on target or `set_fact` in playbook.

### The actual answer
**Common built-in facts**:
- `ansible_distribution` — Ubuntu, CentOS, Amazon
- `ansible_distribution_version` — "20.04", "7.9"
- `ansible_architecture` — x86_64, aarch64
- `ansible_memtotal_mb` — total RAM in MB
- `ansible_processor_vcpus` — CPU count
- `ansible_default_ipv4.address` — primary IP
- `ansible_env.HOME` — home directory

**Custom facts** (`/etc/ansible/facts.d/app.fact`):
```ini
[general]
app_version=2.3.1
deploy_path=/opt/myapp
```
Accessed as `ansible_local.general.app_version`.

### Practical commands / examples
```bash
# See all facts for a host
ansible web1 -m setup -i inventory.yml

# Filter facts
ansible web1 -m setup -a "filter=ansible_distribution*" -i inventory.yml

# Use in task
- name: Install package per OS
  package:
    name: "{{ 'httpd' if ansible_distribution == 'RedHat' else 'nginx' }}"
    state: present
```
**What to look for**: `setup` runs automatically; `gather_facts: no` disables it for speed; `ansible_local` namespace for custom facts.

### Key takeaway
- Facts = free system inventory; use for conditionals
- Custom facts = bridge between infra and app config
- `ansible_local` = custom facts from target's `/etc/ansible/facts.d/`
- `set_fact` creates temporary facts within playbook run

---

## Q8: Explain Ansible conditionals (`when`), loops (`loop`), and task control.

### What is this question actually asking?
- Conditional execution based on facts/variables
- Iterating over lists/dicts
- `register`, `until`, `retries`, `failed_when`, `changed_when`

### Understand the concept
Tasks don't always run the same way. `when` skips tasks based on conditions. `loop` repeats a task for each item. `register` captures output for later use. `until`/`retries` implements polling/retry logic. `changed_when`/`failed_when` lets you define what "success" means for non-idempotent commands.

### The actual answer
**Conditionals**:
```yaml
- name: Install nginx on Debian
  package:
    name: nginx
    state: present
  when: ansible_distribution == "Debian" or ansible_distribution == "Ubuntu"
```

**Loops**:
```yaml
- name: Create multiple users
  user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    state: present
  loop:
    - { name: "alice", groups: "wheel" }
    - { name: "bob", groups: "docker" }
```

**Task control**:
```yaml
- name: Wait for service to be ready
  uri:
    url: "http://localhost:8080/health"
    return_content: yes
  register: health
  until: health.status == 200
  retries: 10
  delay: 5
  changed_when: false
```

### Practical commands / examples
```bash
# Debug registered variable
- debug:
    var: health
```
**What to look for**: `when` uses Jinja2 expressions; `loop` replaces deprecated `with_items`; `register` stores module result; `changed_when: false` prevents "changed" status.

### Key takeaway
- `when` = skip task; `loop` = repeat task
- `register` + `until` = wait-for-pattern
- `changed_when`/`failed_when` = control idempotency reporting
- `loop_control:` with `label:` improves output readability

---

## Q9: What is Ansible Vault? How do you encrypt/decrypt/edit secrets?

### What is this question actually asking?
- Encrypting sensitive data (passwords, keys, tokens)
- Workflow: create, edit, view, decrypt
- Integration with playbooks and CI/CD

### Understand the concept
Ansible Vault encrypts files or variables using AES256. You provide a password (or password file) to encrypt/decrypt. Encrypted files can live in git safely. At runtime, Ansible decrypts transparently when you pass `--ask-vault-pass` or `--vault-password-file`.

### The actual answer
**File-level encryption**:
```bash
# Create encrypted file
ansible-vault create secrets.yml

# Edit existing encrypted file
ansible-vault edit secrets.yml

# Encrypt existing file
ansible-vault encrypt secrets.yml

# Decrypt to stdout
ansible-vault decrypt secrets.yml

# View without decrypting to disk
ansible-vault view secrets.yml
```

**Variable-level encryption** (inline in vars file):
```yaml
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  663864396532363363313837343733...
```

**Runtime usage**:
```bash
ansible-playbook site.yml --ask-vault-pass
ansible-playbook site.yml --vault-password-file ~/.vault_pass
```

### Practical commands / examples
```bash
# Rekey (change password)
ansible-vault rekey secrets.yml

# Encrypt string for inline use
ansible-vault encrypt_string "supersecret" --name "api_key"
```
**What to look for**: `$ANSIBLE_VAULT` header; `--vault-id` for multiple passwords; vault password file must be `chmod 600`.

### Key takeaway
- Vault = encrypt at rest, decrypt at runtime
- File-level = entire YAML encrypted; variable-level = only sensitive values
- Never commit vault password; inject via CI/CD secret store
- `encrypt_string` useful for adding single secrets to existing files

---

## Q10: How do you test Ansible code? Molecule, ansible-lint, check mode.

### What is this question actually asking?
- Linting for syntax/best practices
- Unit/integration testing with Molecule
- Check mode (dry-run) limitations

### Understand the concept
Testing Ansible has layers: static analysis (`ansible-lint`), syntax check (`--syntax-check`), dry-run (`--check`), and full integration tests against real/containers (Molecule). Molecule creates test instances, applies role, verifies with tests, destroys — supports Docker, Podman, Vagrant, cloud.

### The actual answer
**Static analysis**:
```bash
ansible-lint site.yml
ansible-lint roles/nginx/
```

**Syntax + dry-run**:
```bash
ansible-playbook site.yml --syntax-check
ansible-playbook site.yml --check --diff
```

**Molecule** (`molecule.yml`):
```yaml
driver:
  name: docker
platforms:
  - name: ubuntu2204
    image: ubuntu:22.04
    pre_build_image: true
provisioner:
  name: ansible
verifier:
  name: ansible
```

**Molecule commands**:
```bash
molecule test           # full cycle: create → converge → verify → destroy
molecule converge       # apply role
molecule verify         # run tests
molecule destroy        # cleanup
```

### Practical commands / examples
```bash
# Run lint on specific role
ansible-lint -v roles/nginx/

# Molecule with custom scenario
molecule test -s ubuntu2204
```
**What to look for**: `ansible-lint` rules (deprecated modules, `command` vs module); Molecule `verify.yml` uses `assert` module for tests.

### Key takeaway
- `ansible-lint` catches style/issues before runtime
- `--check` mode simulates; doesn't catch all errors (e.g., service start fails)
- Molecule = true integration test in ephemeral environments
- CI pipeline: `lint` → `syntax-check` → `molecule test`

---

## Q11: Explain Ansible collections — what they are, how to use, and create.

### What is this question actually asking?
- Collections vs roles (namespaced, versioned, distributable)
- `galaxy.yml`, `requirements.yml`
- Using `collections:` in playbook

### Understand the concept
Collections are the modern packaging format for Ansible content (roles, modules, plugins, modules). They replaced monolithic "Ansible core" modules. A collection lives under a namespace (e.g., `community.general`, `amazon.aws`). You declare dependencies in `requirements.yml` and install via `ansible-galaxy collection install`.

### The actual answer
**Directory structure**:
```
my_namespace/
  my_collection/
    galaxy.yml              # metadata
    plugins/
      modules/              # custom modules
      lookup/               # lookup plugins
      filter/               # Jinja2 filters
    roles/                  # roles inside collection
    docs/                   # documentation
    tests/                  # integration tests
```

**galaxy.yml**:
```yaml
namespace: my_namespace
name: my_collection
version: 1.0.0
readme: README.md
authors:
  - "Your Name"
dependencies:
  community.general: ">=5.0.0"
  ansible.posix: ">=1.3.0"
```

**requirements.yml** (project-level):
```yaml
collections:
  - name: community.general
    version: ">=5.0.0"
  - name: amazon.aws
    source: https://galaxy.ansible.com
```

**Install**:
```bash
ansible-galaxy collection install -r requirements.yml
```

**Use in playbook**:
```yaml
- hosts: all
  collections:
    - community.general
    - amazon.aws
  tasks:
    - name: Use module from collection
      community.general.docker_container:
        name: myapp
        image: nginx
```

### Practical commands / examples
```bash
# Initialize collection skeleton
ansible-galaxy collection init my_namespace.my_collection

# Build collection tarball
ansible-galaxy collection build

# Publish to Galaxy
ansible-galaxy collection publish my_namespace-my_collection-1.0.0.tar.gz
```
**What to look for**: `galaxy.yml` = metadata; `requirements.yml` = lockfile for reproducibility; `collections:` keyword in playbook enables short names.

### Key takeaway
- Collections = versioned, namespaced, shareable packages
- `requirements.yml` pins versions for reproducible builds
- Core modules moved to collections (e.g., `amazon.aws.ec2_instance`)
- Galaxy = public registry; can host private Galaxy server

---

## Q12: How does Ansible delegate tasks? `delegate_to`, `run_once`, `local_action`.

### What is this question actually asking?
- Running a task on a different host than the play target
- Common patterns: load balancer drain, API calls, local facts
- `run_once` for single-execution across all hosts

### Understand the concept
Sometimes a task must run on a specific host (e.g., API call to load balancer, database migration on primary DB) while the play targets many hosts. `delegate_to` redirects that task. `run_once` ensures it runs only once (on first host in batch). `local_action` is shorthand for `delegate_to: localhost`.

### The actual answer
**delegate_to**:
```yaml
- name: Remove server from load balancer
  uri:
    url: "https://lb-api.example.com/remove/{{ inventory_hostname }}"
    method: POST
  delegate_to: localhost           # runs on control machine
  run_once: true                   # only once per play
```

**local_action** (shorthand):
```yaml
- name: Create DNS record
  local_action:
    module: community.general.route53
    zone: example.com
    record: "{{ inventory_hostname }}"
    type: A
    value: "{{ ansible_default_ipv4.address }}"
```

**run_once with delegate_to**:
```yaml
- name: Run DB migration on primary
  command: "/opt/app/migrate.sh"
  delegate_to: "{{ groups['db_primary'][0] }}"
  run_once: true
```

### Practical commands / examples
```bash
# Test delegation
ansible-playbook site.yml --check -v
# Look for "delegated to: localhost" in task output
```
**What to look for**: `delegated to:` in verbose output; `run_once` + `delegate_to` = runs on delegated host once; `local_action` implies `delegate_to: localhost`.

### Key takeaway
- `delegate_to` = redirect task execution target
- `run_once` = execute once per play (not per host)
- `local_action` = syntactic sugar for `delegate_to: localhost`
- Common use: LB drain/add, DNS, API calls, DB migrations, fetching facts from one host for others

---

## Q13: What are Ansible callback plugins? How to use `yaml`, `json`, `timer`, `profile_tasks`?

### What is this question actually asking?
- Customizing Ansible output format
- Built-in callbacks for CI/CD integration
- Enabling via `ansible.cfg` or environment

### Understand the concept
Callback plugins control what Ansible prints to stdout/stderr during playbook runs. Default is `default` (human-readable). `yaml`/`json` = machine-parseable for CI. `timer` = shows playbook duration. `profile_tasks` = shows slowest tasks. You can enable multiple at once.

### The actual answer
**Enable in `ansible.cfg`**:
```ini
[defaults]
callback_whitelist = timer, profile_tasks, yaml
stdout_callback = yaml
```

**Or via environment**:
```bash
export ANSIBLE_STDOUT_CALLBACK=yaml
export ANSIBLE_CALLBACK_WHITELIST=timer,profile_tasks
ansible-playbook site.yml
```

**Common built-in callbacks**:
| Plugin | Purpose |
|--------|---------|
| `default` | Human-readable (default) |
| `yaml` | YAML output, good for logging |
| `json` | JSON output, CI/CD parsing |
| `timer` | Total playbook runtime summary |
| `profile_tasks` | Top 10 slowest tasks |
| `junit` | JUnit XML for test reporting |
| `slack` / `hipchat` / `mattermost` | Chat notifications |

### Practical commands / examples
```bash
# One-off with timer + profile
ANSIBLE_STDOUT_CALLBACK=default ANSIBLE_CALLBACK_WHITELIST=timer,profile_tasks ansible-playbook site.yml

# JSON for CI parsing
ANSIBLE_STDOUT_CALLBACK=json ansible-playbook site.yml > run.json
```
**What to look for**: `profile_tasks` output shows `Time` column; `timer` shows `Playbook run took X seconds`.

### Key takeaway
- `stdout_callback` = main output format (one only)
- `callback_whitelist` = additional callbacks (multiple)
- `profile_tasks` essential for optimization
- `json`/`yaml` for programmatic consumption in pipelines

---

## Q14: Explain Ansible `include_tasks`, `import_tasks`, `include_role`, `import_role` — differences.

### What is this question actually asking?
- Dynamic vs static inclusion
- When each is processed (parse time vs runtime)
- Variable scoping implications

### Understand the concept
`import_*` = static, processed at playbook parse time. `include_*` = dynamic, processed at runtime. Static = variables must be known at parse time; loops not allowed. Dynamic = can use variables from previous tasks, works with loops, but can't use `notify` to handlers in parent play.

### The actual answer
| Keyword | Type | When processed | Loops allowed | Notify handlers |
|---------|------|----------------|---------------|-----------------|
| `import_tasks` | Static | Parse time | No | Yes |
| `include_tasks` | Dynamic | Runtime | Yes | No* |
| `import_role` | Static | Parse time | No | Yes |
| `include_role` | Dynamic | Runtime | Yes | No* |

*Can notify handlers defined *within* the included file.

**Examples**:
```yaml
# Static - vars must exist at parse time
- import_tasks: tasks/install.yml
  vars:
    pkg_version: "1.2.3"

# Dynamic - can use registered vars
- name: Get version from API
  uri:
    url: "https://api.example.com/version"
  register: version_resp

- include_tasks: tasks/install.yml
  vars:
    pkg_version: "{{ version_resp.json.version }}"
```

### Practical commands / examples
```bash
# Test parse-time vs runtime
ansible-playbook site.yml --syntax-check
# import_* errors caught here; include_* errors only at runtime
```
**What to look for**: Syntax check validates `import_*`; `include_*` with undefined vars fails at runtime.

### Key takeaway
- `import_*` = static, faster, parse-time validation, no loops
- `include_*` = dynamic, flexible, runtime vars, loop-friendly
- Default to `import_*` for known structure; `include_*` when you need dynamic behavior
- Handlers: `import_*` can notify parent handlers; `include_*` cannot

---

## Q15: How do you manage Windows hosts with Ansible? WinRM, modules, limitations.

### What is this question actually asking?
- Connection plugin: WinRM vs SSH
- Windows-specific modules (`win_*`)
- Authentication (Kerberos, NTLM, CredSSP)
- PowerShell vs raw modules

### Understand the concept
Ansible manages Windows via WinRM (Windows Remote Management) over HTTP/HTTPS, not SSH. Requires WinRM listener configured on target. Uses PowerShell under the hood. Modules prefixed `win_` (e.g., `win_service`, `win_reboot`, `win_chocolatey`). Limitations: no `become` (UAC), some Linux modules don't work, file paths use backslashes.

### The actual answer
**Inventory for Windows**:
```yaml
windows:
  hosts:
    web01:
      ansible_host: 10.0.1.20
      ansible_user: Administrator
      ansible_password: "{{ vault_win_pass }}"
      ansible_connection: winrm
      ansible_winrm_transport: ntlm
      ansible_winrm_server_cert_validation: ignore
```

**Common Windows modules**:
- `win_service` — manage services
- `win_reboot` — reboot and wait
- `win_chocolatey` — install packages via Chocolatey
- `win_shell` / `win_powershell` — run commands
- `win_file` / `win_copy` / `win_template` — file ops
- `win_regedit` — registry

**Playbook example**:
```yaml
- hosts: windows
  tasks:
    - name: Install nginx via Chocolatey
      win_chocolatey:
        name: nginx
        state: present

    - name: Start nginx service
      win_service:
        name: nginx
        state: started
        start_mode: auto
```

### Practical commands / examples
```bash
# Test WinRM connectivity
ansible windows -m win_ping -i inventory.yml

# Run PowerShell command
ansible windows -m win_shell -a "Get-Service nginx" -i inventory.yml
```
**What to look for**: `win_ping` succeeds = WinRM works; `ansible_connection: winrm` required; certificate validation often disabled in dev.

### Key takeaway
- WinRM = Windows equivalent of SSH; port 5985 (HTTP) / 5986 (HTTPS)
- `win_*` modules = native PowerShell, idempotent
- No `become` — run as admin user directly
- CredSSP required for "double hop" (accessing network shares from remote session)
- Prefer `win_shell` over `raw` for PowerShell

---

## Q16: What is Ansible `ansible.cfg`? Key settings for production.

### What is this question actually asking?
- Configuration file precedence (environment > cwd > home > /etc)
- Performance tuning (forks, pipelining, fact caching)
- Security settings (host key checking, vault)

### Understand the concept
`ansible.cfg` controls Ansible behavior: connection defaults, inventory location, privilege escalation, output format, performance knobs. Ansible searches multiple locations in order; first match wins. Production needs tuning for speed (forks, pipelining, fact caching) and security (host key checking, no world-readable vault files).

### The actual answer
**Precedence (highest → lowest)**:
1. `ANSIBLE_CONFIG` env var
2. `./ansible.cfg` (current directory)
3. `~/.ansible.cfg` (home)
4. `/etc/ansible/ansible.cfg` (system)

**Production-relevant settings**:
```ini
[defaults]
inventory = ./inventory.yml
host_key_checking = True              # security
retry_files_enabled = False           # no .retry files
forks = 20                            # parallelism
pipelining = True                     # SSH pipelining (speed)
fact_caching = jsonfile               # cache facts
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400          # 24h
gathering = smart                     # implicit fact gathering
stdout_callback = yaml
callback_whitelist = timer, profile_tasks

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=yes
control_path = ~/.ansible/cp/%%h-%%p-%%r
pipelining = True

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
```

### Practical commands / examples
```bash
# View effective config
ansible-config dump | grep -E "forks|pipelining|fact_caching"

# Validate config
ansible-config view
```
**What to look for**: `forks` = parallel hosts; `pipelining` reduces SSH round-trips; `fact_caching` avoids re-gathering facts.

### Key takeaway
- `ansible.cfg` in project root = version-controlled, team-shared
- `forks` + `pipelining` = biggest speed gains
- Fact caching = essential for large inventories
- `host_key_checking = True` = prevents MITM; manage known_hosts properly

---

## Q17: How do you handle secrets in CI/CD with Ansible? Vault, GitHub Secrets, external vaults.

### What is this question actually asking?
- Vault password injection in pipelines
- Avoiding secrets in logs
- Integration with HashiCorp Vault, AWS Secrets Manager, Azure Key Vault

### Understand the concept
Secrets management in CI/CD: vault password must be provided to `ansible-playbook` without appearing in logs. Options: GitHub Actions secrets → env var → `--vault-password-file` (temp file), or lookup plugins that fetch from external vault at runtime. Never hardcode vault password in repo or CI config.

### The actual answer
**GitHub Actions pattern**:
```yaml
# .github/workflows/ansible.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Set up Vault password
        run: |
          echo "${{ secrets.ANSIBLE_VAULT_PASSWORD }}" > /tmp/vault_pass
          chmod 600 /tmp/vault_pass
      - name: Run playbook
        run: ansible-playbook site.yml --vault-password-file /tmp/vault_pass
        env:
          ANSIBLE_CONFIG: ./ansible.cfg
```

**External vault lookup** (HashiCorp Vault):
```yaml
- name: Get DB password from Vault
  set_fact:
    db_password: "{{ lookup('community.hashi_vault.hashi_vault', 'secret=secret/data/db:password token={{ vault_token }} url=https://vault.example.com') }}"
```

**AWS Secrets Manager**:
```yaml
- name: Get API key
  set_fact:
    api_key: "{{ lookup('amazon.aws.aws_secret', 'prod/api-key', region='us-east-1') }}"
```

### Practical commands / examples
```bash
# Test vault decryption locally
ansible-playbook site.yml --vault-password-file ~/.vault_pass

# Encrypt string for CI variable
ansible-vault encrypt_string "prod-password" --name "db_password" --vault-password-file ~/.vault_pass
```
**What to look for**: Temp file cleaned up after; `no_log: true` on tasks that output secrets; external vault = no vault password needed in CI.

### Key takeaway
- Never commit vault password; inject via CI secret store
- Temp file + `chmod 600` → `--vault-password-file`
- External vaults (HashiCorp, AWS, Azure) = no local vault file needed
- `no_log: true` prevents secret leakage in task output
- Rotate vault password periodically; rekey files

---

## Q18: Explain Ansible `strategy`: linear, free, debug, host_pinned.

### What is this question actually asking?
- How Ansible executes tasks across hosts
- Default behavior vs alternatives
- When to use each strategy

### Understand the concept
Strategy controls task execution flow across hosts. `linear` (default) = finish task 1 on all hosts, then task 2 on all hosts. `free` = each host runs all tasks independently, as fast as possible. `debug` = interactive debugger on failure. `host_pinned` = for rolling updates with serial batches.

### The actual answer
| Strategy | Behavior | Use case |
|----------|----------|----------|
| `linear` | Task 1 all hosts → Task 2 all hosts | Default, ordered operations |
| `free` | Each host runs all tasks at own pace | Independent hosts, speed |
| `debug` | Pause on failure, interactive CLI | Troubleshooting |
| `host_pinned` | Pinned to host pattern, used with `serial` | Rolling updates |

**Usage**:
```yaml
- hosts: all
  strategy: free
  tasks:
    - name: Long running task
      command: sleep 300
```

```yaml
- hosts: webservers
  strategy: linear
  serial: 2              # 2 at a time
  tasks:
    - name: Rolling restart
      service:
        name: nginx
        state: restarted
```

### Practical commands / examples
```bash
# Debug strategy - drops to interactive prompt on failure
ansible-playbook site.yml --strategy=debug

# Free strategy for independent hosts
ansible-playbook site.yml --strategy=free
```
**What to look for**: `free` = tasks complete out of order across hosts; `linear` = predictable order; `serial` works with any strategy.

### Key takeaway
- `linear` = safe default, easier to reason about
- `free` = faster for independent tasks, but output is interleaved
- `debug` = powerful for troubleshooting failed tasks
- `host_pinned` + `serial` = controlled rolling deployments

---

## Q19: What are Ansible lookup plugins? Common examples and use cases.

### What is this question actually asking?
- Fetching external data at runtime (files, env, APIs, vaults)
- `lookup()` vs `query()` syntax
- Templating vs task-time evaluation

### Understand the concept
Lookup plugins pull data from external sources during playbook execution. They run on the **control machine**, not target hosts. Used in `vars`, `tasks`, `templates`. `lookup()` returns first match (string); `query()` returns list (for loops). Common: `file`, `env`, `pipe`, `template`, `hashi_vault`, `aws_secret`, `k8s`.

### The actual answer
**Common lookups**:
| Plugin | Purpose |
|--------|---------|
| `file` | Read local file content |
| `env` | Read environment variable |
| `pipe` | Run local command, capture stdout |
| `template` | Render Jinja2 template locally |
| `password` | Generate random password |
| `hashi_vault` | Fetch from HashiCorp Vault |
| `aws_secret` | Fetch from AWS Secrets Manager |
| `k8s` | Query Kubernetes API |
| `dig` | DNS lookup |
| `url` | HTTP GET, return content |

**Syntax**:
```yaml
# lookup() - returns string
- set_fact:
    ssh_key: "{{ lookup('file', '~/.ssh/id_rsa.pub') }}"

# query() - returns list (for loop)
- name: Create users from list
  user:
    name: "{{ item }}"
    state: present
  loop: "{{ query('fileglob', 'users/*.yml') }}"
```

### Practical commands / examples
```bash
# Test lookup in ad-hoc
ansible localhost -m debug -a "msg={{ lookup('env', 'HOME') }}"

# Test query
ansible localhost -m debug -a "var=query('fileglob', '*.yml')"
```
**What to look for**: Lookups run on controller; `query()` always returns list; `password` lookup stores generated password in `~/.ansible/tmp/` for idempotency.

### Key takeaway
- Lookups = control machine only; not on target hosts
- `lookup()` = scalar; `query()` = list (preferred for loops)
- `pipe` = arbitrary local command (use sparingly)
- External vault lookups = secrets never touch disk in plaintext

---

## Q20: How do you optimize Ansible performance for large inventories?

### What is this question actually asking?
- Forks, pipelining, fact caching
- Mitogen acceleration
- Reducing task overhead, async, select_attr

### Understand the concept
Default Ansible is slow at scale: SSH connection per task, fact gathering per host, sequential task execution. Optimizations: increase parallelism (`forks`), enable SSH pipelining, cache facts, use Mitogen (streamlines module execution), limit fact gathering, use `async` for long tasks, filter hosts early.

### The actual answer
**Configuration tweaks** (`ansible.cfg`):
```ini
[defaults]
forks = 50                          # parallel hosts (CPU/network bound)
pipelining = True                   # single SSH connection per host
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400
gathering = smart                   # only gather when needed

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=300s
control_path = ~/.ansible/cp/%%h-%%p-%%r
```

**Playbook-level**:
```yaml
- hosts: all
  gather_facts: no                  # skip if not needed
  tasks:
    - name: Long task async
      command: /opt/deploy.sh
      async: 3600                   # max seconds
      poll: 0                       # fire-and-forget
    - name: Wait for async
      async_status:
        jid: "{{ deploy.ansible_job_id }}"
      register: result
      until: result.finished
      retries: 30
```

**Mitogen** (external, significant speedup):
```bash
pip install mitogen
# In ansible.cfg:
[defaults]
strategy_plugins = /usr/local/lib/python3.x/site-packages/mitogen/ansible/strategy
strategy = mitogen_linear
```

### Practical commands / examples
```bash
# Benchmark
time ansible-playbook site.yml

# With Mitogen
time ansible-playbook site.yml -e "ansible_strategy=mitogen_linear"
```
**What to look for**: `forks` > CPU cores (I/O bound); `pipelining` requires `require_tty=False` on sudo; Mitogen can 2-5x speedup.

### Key takeaway
- `forks` + `pipelining` = baseline speedup (no code changes)
- Fact caching = avoids repeated `setup` module
- `gather_facts: no` when facts unused
- `async`/`poll` for long-running operations
- Mitogen = drop-in replacement for linear strategy, huge gains

---

## Q21: How do you troubleshoot Ansible failures? Verbosity, debug module, strategies.

### What is this question actually asking?
- Verbosity levels (-v, -vv, -vvv, -vvvv)
- `debug` module for variable inspection
- `--step`, `--start-at-task`, `--strategy=debug`
- Common failure patterns

### Understand the concept
Troubleshooting = seeing what Ansible sees. Verbosity controls output detail. `debug` module prints variables. `--step` confirms each task. `--start-at-task` resumes from failure. `--strategy=debug` drops interactive prompt on failure. Common issues: SSH auth, Python missing, module not found, variable undefined, idempotency false positives.

### The actual answer
**Verbosity levels**:
```bash
ansible-playbook site.yml -v        # task results
ansible-playbook site.yml -vv       # + task parameters
ansible-playbook site.yml -vvv      # + connection info (SSH)
ansible-playbook site.yml -vvvv     # + full SSH debug
```

**Debug module**:
```yaml
- name: Show all variables
  debug:
    var: hostvars[inventory_hostname]

- name: Show specific fact
  debug:
    msg: "IP is {{ ansible_default_ipv4.address }}"
    verbosity: 2                    # only shows with -vv
```

**Troubleshooting flags**:
```bash
# Step through each task (y/n/c)
ansible-playbook site.yml --step

# Resume from specific task
ansible-playbook site.yml --start-at-task="Install nginx"

# Debug strategy - interactive on failure
ansible-playbook site.yml --strategy=debug

# Check mode + diff
ansible-playbook site.yml --check --diff
```

### Practical commands / examples
```bash
# Test single host with max verbosity
ansible-playbook site.yml -l web1 -vvvv

# Show facts for one host
ansible web1 -m setup -i inventory.yml | head -50
```
**What to look for**: `-vvv` shows SSH connection details; `debug` with `verbosity` controls noise; `--step` = manual approval per task.

### Key takeaway
- Start with `-v`, escalate to `-vvv` for connection issues
- `debug` module = `print()` for Ansible; use `verbosity` to control
- `--start-at-task` saves time on long playbooks
- `--strategy=debug` = interactive REPL at failure point
- Common fix: `ansible_python_interpreter` for Python path issues

---

## Q22: What is Ansible Galaxy? Roles vs Collections, publishing, CI.

### What is this question actually asking?
- Galaxy as public registry
- Role vs Collection packaging
- `galaxy.yml`, `meta/main.yml`, GitHub Actions for publishing

### Understand the concept
Ansible Galaxy is the community hub for sharing roles and collections. Roles = legacy format (single role). Collections = modern, namespaced, versioned, can contain multiple roles + modules + plugins. Publishing: build tarball → `ansible-galaxy collection publish` with API token. CI can automate lint → test → publish on tag.

### The actual answer
**Role (legacy)**:
```
roles/nginx/
  meta/main.yml        # galaxy_info, dependencies
```

**Collection (modern)**:
```
my_namespace/my_collection/
  galaxy.yml           # metadata
  roles/
    nginx/
    postgresql/
  plugins/
    modules/
```

**Publishing**:
```bash
# Build collection
ansible-galaxy collection build

# Publish (requires API token)
ansible-galaxy collection publish my_namespace-my_collection-1.0.0.tar.gz -p <token>
```

**GitHub Actions CI**:
```yaml
name: Publish Collection
on:
  release:
    types: [published]
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: pip install ansible-core
      - name: Build collection
        run: ansible-galaxy collection build
      - name: Publish to Galaxy
        run: ansible-galaxy collection publish *.tar.gz -p ${{ secrets.GALAXY_API_KEY }}
```

### Practical commands / examples
```bash
# Search Galaxy
ansible-galaxy search nginx --author geerlingguy

# Install specific version
ansible-galaxy collection install community.general:5.4.0

# List installed
ansible-galaxy collection list
```
**What to look for**: `galaxy.yml` = collection metadata; `meta/main.yml` = role metadata; namespace must be unique on Galaxy.

### Key takeaway
- Galaxy = central registry for Ansible content
- Collections > Roles (versioning, namespacing, multi-content)
- `requirements.yml` pins versions for reproducibility
- CI/CD: lint → molecule test → publish on GitHub release
- Private Galaxy server option for enterprise

---

## Q23: Explain Ansible `block`, `rescue`, `always` for error handling.

### What is this question actually asking?
- Structured error handling (try/catch/finally)
- `block` groups tasks; `rescue` runs on failure; `always` runs always
- Variable scope and `failed` status

### Understand the concept
`block`/`rescue`/`always` mirrors try/catch/finally. Tasks in `block` run normally. If any task fails, `rescue` tasks run (can recover). `always` tasks run regardless (cleanup). The play continues after `rescue` unless `rescue` also fails. Useful for: rollback, notifications, cleanup, fallback logic.

### The actual answer
```yaml
- name: Deploy with rollback
  block:
    - name: Backup current version
      command: cp /opt/app /opt/app.backup
      register: backup

    - name: Deploy new version
      unarchive:
        src: app.tar.gz
        dest: /opt/app

    - name: Run health check
      uri:
        url: http://localhost:8080/health
        status_code: 200
  rescue:
    - name: Rollback on failure
      command: mv /opt/app.backup /opt/app
      when: backup.changed

    - name: Send failure alert
      community.general.slack:
        token: "{{ slack_token }}"
        msg: "Deployment failed on {{ inventory_hostname }}"
  always:
    - name: Cleanup temp files
      file:
        path: /tmp/app-deploy
        state: absent
```

**Key behaviors**:
- `rescue` sees `ansible_failed_task`, `ansible_failed_result`
- `always` runs even if `rescue` fails
- Block failure = play continues (unless `rescue` fails)

### Practical commands / examples
```bash
# Test failure handling
ansible-playbook site.yml --check
```
**What to look for**: `rescue` tasks only run on block failure; `always` always runs; use `when: ansible_failed_task.name == "Deploy new version"` for specific handling.

### Key takeaway
- `block`/`rescue`/`always` = structured error handling
- `rescue` = recovery/notification; `always` = cleanup
- Play continues after successful `rescue`
- Can nest blocks for granular control

---

## Q24: How do you manage network devices with Ansible? `network_cli`, `netconf`, platform modules.

### What is this question actually asking?
- Connection plugins for network gear (Cisco, Juniper, Arista)
- Platform-specific modules (`ios_config`, `junos_config`)
- Idempotency challenges with CLI parsing

### Understand the concept
Network devices don't run Python agents. Ansible connects via `network_cli` (SSH + CLI scraping) or `netconf` (structured API). Uses platform-specific modules: `cisco.ios.ios_config`, `juniper.junos.junos_config`, `arista.eos.eos_config`. Modules handle idempotency by parsing running config. Requires `ansible_network_os` in inventory.

### The actual answer
**Inventory for network device**:
```yaml
switches:
  hosts:
    core-sw1:
      ansible_host: 10.0.10.1
      ansible_user: admin
      ansible_password: "{{ vault_net_pass }}"
      ansible_connection: network_cli
      ansible_network_os: cisco.ios.ios
      ansible_become: yes
      ansible_become_method: enable
      ansible_become_password: "{{ vault_enable_pass }}"
```

**Common tasks**:
```yaml
- name: Configure VLAN
  cisco.ios.ios_vlans:
    config:
      - vlan_id: 100
        name: servers
        state: active
    state: merged

- name: Backup running config
  cisco.ios.ios_config:
    backup: yes
  register: backup

- name: Save backup locally
  copy:
    content: "{{ backup.backup_content }}"
    dest: "backups/{{ inventory_hostname }}-{{ ansible_date_time.iso8601 }}.cfg"
  delegate_to: localhost
  run_once: true
```

### Practical commands / examples
```bash
# Test connectivity
ansible switches -m ping -i inventory.yml

# Get facts
ansible switches -m cisco.ios.ios_facts -i inventory.yml
```
**What to look for**: `ansible_network_os` must match collection (e.g., `cisco.ios.ios`); `ansible_become: yes` + `enable` for privileged commands; `backup: yes` returns config in `backup_content`.

### Key takeaway
- `network_cli` = SSH + CLI (most common); `netconf` = XML/JSON API
- Platform modules = idempotent config management
- `delegate_to: localhost` for saving backups locally
- Collections: `cisco.ios`, `juniper.junos`, `arista.eos`, `vyos.vyos`
- No Python on target = modules run on controller, send commands

---

## Q25: What are Ansible filters? Custom filters, common Jinja2 filters, practical examples.

### What is this question actually asking?
- Jinja2 filters for data transformation in templates/vars
- Ansible-specific filters (`to_yaml`, `to_json`, `regex_replace`, `selectattr`)
- Writing custom filter plugins

### Understand the concept
Filters transform data in Jinja2 expressions: `{{ variable | filter }}`. Ansible bundles many filters beyond standard Jinja2: type conversion, list/dict manipulation, networking, file operations. Custom filters are Python functions in `filter_plugins/` directory, auto-loaded.

### The actual answer
**Common Ansible filters**:
| Filter | Purpose |
|--------|---------|
| `to_yaml` / `to_json` | Serialize data structure |
| `from_yaml` / `from_json` | Parse string to data |
| `regex_replace` | Regex search/replace |
| `regex_search` / `regex_findall` | Regex extract |
| `selectattr` / `rejectattr` | Filter list of dicts by attribute |
| `map` | Extract attribute from list |
| `unique` | Deduplicate list |
| `sort` | Sort list |
| `default` | Default value if undefined |
| `mandatory` | Error if undefined |
| `ipaddr` / `ipv4` / `ipv6` | IP address manipulation |
| `hash` | Hash string (md5, sha256) |
| `b64encode` / `b64decode` | Base64 |

**Examples**:
```yaml
# List of dicts → list of names
- set_fact:
    usernames: "{{ users | map(attribute='name') | list }}"

# Filter by attribute
- set_fact:
    admins: "{{ users | selectattr('role', 'equalto', 'admin') | list }}"

# IP manipulation
- set_fact:
    network: "{{ ansible_default_ipv4.address | ipaddr('network') }}"
    netmask: "{{ ansible_default_ipv4.address | ipaddr('netmask') }}"

# Default with fallback
- set_fact:
    port: "{{ app_port | default(8080) }}"
```

**Custom filter plugin** (`filter_plugins/my_filters.py`):
```python
def to_upper(text):
    return text.upper()

class FilterModule:
    def filters(self):
        return {'to_upper': to_upper}
```
Usage: `{{ "hello" | to_upper }}` → `"HELLO"`

### Practical commands / examples
```bash
# Test filter in ad-hoc
ansible localhost -m debug -a "msg={{ ['a','b','a'] | unique }}"
```
**What to look for**: Filters chain left-to-right; `map`/`selectattr` return generators → wrap with `| list`; custom filters in `filter_plugins/` auto-discovered.

### Key takeaway
- Filters = data transformation in templates/vars
- Ansible adds 50+ filters beyond Jinja2
- `selectattr`/`map` = powerful list-of-dicts manipulation
- Custom filters = Python functions in `filter_plugins/`
- `default` prevents "undefined variable" errors

---

## Q26: How do you implement rolling updates with Ansible? `serial`, `max_fail_percentage`, `run_once`.

### What is this question actually asking?
- Control batch size for updates
- Stop deployment if too many failures
- Coordinate tasks that run once (LB drain, DB migration)

### Understand the concept
Rolling updates = update subset of hosts at a time, verify, continue. `serial` controls batch size (number or percentage). `max_fail_percentage` aborts if failure rate exceeded. `run_once` + `delegate_to` coordinates singleton tasks (load balancer, database). `pre_tasks`/`post_tasks` for per-batch hooks.

### The actual answer
```yaml
- hosts: webservers
  serial: 2                         # 2 hosts at a time
  max_fail_percentage: 30           # abort if >30% fail
  pre_tasks:
    - name: Remove from load balancer
      uri:
        url: "https://lb.example.com/drain/{{ inventory_hostname }}"
        method: POST
      delegate_to: localhost
      run_once: true                # runs once per batch
  tasks:
    - name: Deploy application
      unarchive:
        src: app.tar.gz
        dest: /opt/app
    - name: Restart service
      service:
        name: myapp
        state: restarted
  post_tasks:
    - name: Add back to load balancer
      uri:
        url: "https://lb.example.com/add/{{ inventory_hostname }}"
        method: POST
      delegate_to: localhost
      run_once: true
```

**Serial options**:
```yaml
serial: 3                           # 3 hosts per batch
serial: "30%"                       # 30% of hosts per batch
serial:
  - 1                               # first batch: 1
  - 2                               # second: 2
  - "50%"                           # rest: 50%
```

### Practical commands / examples
```bash
# Limit to specific batch for testing
ansible-playbook site.yml --limit "webservers[0]"  # first host only
```
**What to look for**: `run_once` runs once per *batch* (not whole play); `max_fail_percentage` evaluated per batch; `pre_tasks`/`post_tasks` run per batch.

### Key takeaway
- `serial` = batch size; `max_fail_percentage` = safety valve
- `run_once` + `delegate_to` = singleton operations per batch
- `pre_tasks`/`post_tasks` = per-batch hooks (LB drain/add)
- Test with `--limit` to verify single batch

---

## Q27: What is the difference between `changed_when`, `failed_when`, `ignore_errors`?

### What is this question actually asking?
- Controlling task result reporting
- Custom success/failure conditions
- When to use each

### Understand the concept
Ansible tasks report `ok`, `changed`, or `failed`. By default, modules determine this. Sometimes you need to override: a command that always returns 0 but you want to detect changes, or a command that returns non-0 but isn't a real failure. `changed_when`/`failed_when` evaluate Jinja2 expressions on the registered result. `ignore_errors: yes` lets play continue despite failure.

### The actual answer
**changed_when** — control "changed" status:
```yaml
- name: Run custom script
  command: /opt/scripts/deploy.sh
  register: deploy
  changed_when: "'DEPLOYED' in deploy.stdout"
  failed_when: "'ERROR' in deploy.stdout"
```

**failed_when** — control "failed" status:
```yaml
- name: Check service (returns 1 if down)
  command: systemctl is-active nginx
  register: svc
  failed_when: svc.rc not in [0, 3]   # 3 = inactive, not failure
```

**ignore_errors** — continue play regardless:
```yaml
- name: Optional cleanup
  command: rm -f /tmp/old.log
  ignore_errors: yes
```

### Practical commands / examples
```bash
# See registered variable structure
- debug:
    var: deploy
```
**What to look for**: `changed_when`/`failed_when` use result keys (`stdout`, `stderr`, `rc`, `msg`); `ignore_errors` suppresses failure but task still shows `FAILED` in recap.

### Key takeaway
- `changed_when` = define what "change" means for non-idempotent tasks
- `failed_when` = suppress false failures (e.g., grep returns 1)
- `ignore_errors` = play continues; use sparingly (hides real issues)
- Always `register` result first, then reference in condition

---

## Q28: How do you use Ansible with Docker? `docker_container`, `docker_image`, `community.docker` collection.

### What is this question actually asking?
- Managing containers via Ansible (not Dockerfile)
- `community.docker` collection modules
- Difference from Kubernetes/Helm

### Understand the concept
Ansible can manage Docker containers on target hosts using `community.docker` collection. Modules: `docker_image` (pull/build), `docker_container` (run/stop/remove), `docker_network`, `docker_volume`. Useful for: single-host deployments, CI/CD staging, managing Docker on VMs. Not a replacement for orchestration (Kubernetes/Swarm).

### The actual answer
**Requirements**:
```yaml
# requirements.yml
collections:
  - name: community.docker
```

**Playbook**:
```yaml
- hosts: docker_hosts
  tasks:
    - name: Pull image
      community.docker.docker_image:
        name: nginx
        tag: "1.25"
        source: pull

    - name: Run container
      community.docker.docker_container:
        name: web
        image: "nginx:1.25"
        state: started
        restart_policy: always
        ports:
          - "80:80"
        volumes:
          - "/host/path:/container/path"
        env:
          NGINX_PORT: 80
        labels:
          app: web
          env: prod

    - name: Create network
      community.docker.docker_network:
        name: app_net
        driver: bridge
```

**Build image from Dockerfile**:
```yaml
- name: Build image
  community.docker.docker_image:
    name: myapp
    tag: "{{ version }}"
    build:
      path: /path/to/dockerfile
      pull: yes
```

### Practical commands / examples
```bash
# Test module
ansible docker_host -m community.docker.docker_container -a "name=test image=alpine command=sleep 3600" -b
```
**What to look for**: `state: started/stopped/absent`; `recreate: yes` forces recreate on config change; `docker_image` with `build` requires Docker daemon on target.

### Key takeaway
- `community.docker` = official collection for Docker modules
- Target host needs Docker daemon + Python `docker` SDK (`pip install docker`)
- `docker_container` = manages container lifecycle
- Not for multi-host orchestration; use Kubernetes for that
- `labels` = metadata for querying/cleanup

---

## Q29: Explain Ansible `tags` — filtering execution, `--tags`, `--skip-tags`, tag inheritance.

### What is this question actually asking?
- Selective playbook execution
- Tag syntax on plays, tasks, roles, blocks
- `--list-tags`, `--list-tasks`

### Understand the concept
Tags label tasks/plays/roles for selective execution. `--tags` runs only tagged tasks; `--skip-tags` excludes them. Tags inherit: play tags apply to all tasks; role tags apply to role tasks; block tags apply to block tasks. Special tags: `always`, `never`, `tagged`, `untagged`, `all`.

### The actual answer
**Tagging examples**:
```yaml
- hosts: all
  tags: [deploy]                    # play-level tag
  tasks:
    - name: Install packages
      package:
        name: nginx
        state: present
      tags: [install, packages]     # task tags

    - name: Configure nginx
      template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      tags: [config, nginx]

  roles:
    - role: monitoring
      tags: [monitoring]            # role tag applies to all role tasks
```

**Execution**:
```bash
# Run only tasks tagged 'config'
ansible-playbook site.yml --tags config

# Run tasks tagged 'install' OR 'config'
ansible-playbook site.yml --tags "install,config"

# Skip 'monitoring' tasks
ansible-playbook site.yml --skip-tags monitoring

# List all tags
ansible-playbook site.yml --list-tags

# List tasks with tags
ansible-playbook site.yml --list-tasks
```

**Special tags**:
- `always` — always runs (unless `--skip-tags always`)
- `never` — only runs when explicitly requested (`--tags never`)
- `tagged` — runs any tagged task
- `untagged` — runs only untagged tasks
- `all` — runs everything (default)

### Practical commands / examples
```bash
# Dry-run with tags
ansible-playbook site.yml --tags config --check
```
**What to look for**: Tag inheritance = play tags + task tags combine; `--list-tags` shows all available tags; `--tags` without value = error.

### Key takeaway
- Tags = selective execution for large playbooks
- Inheritance: play → role → block → task
- `always`/`never` = special control tags
- `--list-tags`/`--list-tasks` = discoverability

---

## Q30: What are Ansible best practices for large-scale production use?

### What is this question actually asking?
- Project structure (roles, inventories, group_vars)
- Version control, CI/CD, testing
- Security, performance, maintainability

### Understand the concept
Large-scale Ansible needs structure: separate inventories per environment, group_vars for site-wide settings, roles for reusability, collections for distribution. CI/CD: lint → test → deploy. Security: Vault for secrets, host key checking, least-privilege become. Performance: forks, pipelining, fact caching, Mitogen. Documentation: README per role, example playbooks.

### The actual answer
**Recommended project layout**:
```
ansible/
├── ansible.cfg
├── inventories/
│   ├── production/
│   │   ├── hosts.yml
│   │   ├── group_vars/
│   │   │   ├── all.yml
│   │   │   ├── webservers.yml
│   │   │   └── databases.yml
│   │   └── host_vars/
│   └── staging/
│       └── ...
├── roles/
│   ├── common/
│   ├── nginx/
│   └── postgresql/
├── collections/
│   └── requirements.yml
├── playbooks/
│   ├── site.yml
│   ├── webservers.yml
│   └── databases.yml
├── library/                        # custom modules
├── filter_plugins/                 # custom filters
├── module_utils/                   # shared module code
└── docs/
```

**CI/CD pipeline**:
```yaml
# .github/workflows/ansible.yml
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ansible-lint playbooks/
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: molecule test -s ubuntu2204
  deploy:
    needs: [lint, test]
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ansible-playbook -i inventories/production playbooks/site.yml
```

**Key practices**:
1. **Inventories per env** — never mix prod/staging hosts
2. **Group vars for config** — `group_vars/all.yml` for site-wide, `group_vars/webservers.yml` for role-specific
3. **Vault per env** — `inventories/production/vault.yml` encrypted
4. **Roles + collections** — reusable, testable units
5. **Molecule tests** — every role has integration tests
6. **ansible-lint** — enforced in CI
7. **Mitogen** — enable for speed
8. **Documentation** — README per role with examples

### Practical commands / examples
```bash
# Run against specific inventory
ansible-playbook -i inventories/production playbooks/site.yml

# Limit to single host for testing
ansible-playbook -i inventories/production playbooks/site.yml -l web1
```
**What to look for**: Clean separation of concerns; env-specific vars in inventories; roles tested independently; CI gates before deploy.

### Key takeaway
- Structure = inventories/env + group_vars + roles + playbooks
- Vault per environment; never commit unencrypted secrets
- CI: lint → molecule test → deploy
- Mitogen + fact caching + forks = production performance
- Document roles with README + examples

---