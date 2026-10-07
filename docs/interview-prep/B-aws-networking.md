# Interview Prep — B: AWS Networking

> **Purpose**: Self-learning and revision document. These are not scripted interview answers — they are explanations to help you understand concepts and remember how they work in practice.

---

## Q1. What is a VPC and why do you need one?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand the fundamental AWS networking isolation concept
- They are checking whether you understand why VPCs exist — not just what they are

### 2. Understand the concept
By default, if you launch EC2 instances in AWS, they could potentially talk to each other and to the internet without restriction. A VPC (Virtual Private Cloud) is your own isolated, private network inside AWS. You define the IP address range, control what can communicate with what, and decide what reaches the internet.

Think of it as building your own private office building inside a shared skyscraper. You control the rooms, doors, and access — even though the building is shared.

### 3. The actual answer
A VPC is a logically isolated network within AWS. Every resource you create (EC2, EKS, RDS) lives inside a VPC. You define:
- **CIDR block**: the IP address range for the entire VPC (e.g., `10.40.0.0/16` — gives you 65,536 IPs)
- **Subnets**: subdivisions of the VPC for different tiers
- **Route tables**: rules for where traffic goes
- **Security groups**: firewall rules per resource
- **Internet Gateway / NAT Gateway**: controlled internet access

In your repo, `terraform/vpc.tf` creates a VPC with CIDR `10.40.0.0/16`.

### 4. Practical commands / examples

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}
```

`enable_dns_support` and `enable_dns_hostnames` are needed for EKS and many AWS services to resolve DNS names within the VPC.

### 5. Key takeaway
- VPC = your isolated private network inside AWS
- Every EC2, EKS, RDS must live in a VPC
- You control IP ranges, routing, and access
- AWS creates a default VPC per region — never use the default VPC for production

---

## Q2. What is the difference between a public subnet and a private subnet?

### 1. What is this question actually asking?
- The interviewer is testing if you understand the fundamental concept of network tiering
- They want to know how you decide which resources go where

### 2. Understand the concept
Not everything should be accessible from the internet. Your database should never be reachable from outside — only your application should talk to it. Subnets let you separate resources into tiers: some facing the internet (public), some completely internal (private).

### 3. The actual answer
The difference is in the **route table**:

| | Public Subnet | Private Subnet |
|--|-------------|----------------|
| Route to internet | Via Internet Gateway (IGW) | Via NAT Gateway (outbound only) |
| Resources can receive inbound traffic from internet | Yes (if SG allows) | No |
| Used for | Load balancers, jump servers, NAT Gateways | EC2 app servers, EKS nodes, databases |

In your repo:
- **Public subnets** (`10.40.1.0/24`, `10.40.3.0/24`): Jump server, NAT Gateways
- **Private subnets** (`10.40.2.0/24`, `10.40.4.0/24`): App server, EKS worker nodes

EKS worker nodes are in private subnets — they can reach the internet via NAT (to pull images, call AWS APIs) but cannot be reached from the internet directly.

### 4. Practical commands / examples

```hcl
# Public subnet - tagged so resources and EKS know it's public
resource "aws_subnet" "public_a" {
  cidr_block              = "10.40.1.0/24"
  map_public_ip_on_launch = false  # don't auto-assign public IPs
  tags = { Tier = "public" }
}

# Private subnet - no route to IGW in its route table
resource "aws_subnet" "private_a" {
  cidr_block = "10.40.2.0/24"
  tags = { Tier = "private" }
}
```

### 5. Key takeaway
- Public subnet = has route to Internet Gateway = can receive inbound internet traffic
- Private subnet = no route to IGW = not directly reachable from internet
- Private resources can still reach internet via NAT Gateway (outbound only)
- Always put databases, app servers, and Kubernetes nodes in private subnets

---

## Q3. What is an Internet Gateway (IGW) and what is its purpose?

### 1. What is this question actually asking?
- Simple question about internet connectivity for a VPC
- Follow-up may be: "Can a private subnet use an Internet Gateway?"

### 2. Understand the concept
By default, a VPC is completely isolated — nothing gets in or out. An Internet Gateway is the door between your VPC and the public internet. Without it, not even your public subnet resources can reach the internet.

### 3. The actual answer
An Internet Gateway (IGW) is attached to a VPC and enables two things:
1. Resources in public subnets can receive inbound traffic from the internet
2. Resources in public subnets can make outbound requests to the internet

For a subnet to be "public," its route table must have a route pointing to the IGW:
```text
0.0.0.0/0  →  igw-xxxxxxxxx
```

Private subnets do NOT have this route — that's what makes them private.

One IGW per VPC. It scales automatically — no bandwidth limits or availability concerns.

### 4. Practical commands / examples

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}
```

### 5. Key takeaway
- IGW = the door between your VPC and the internet
- One IGW per VPC — attach it to the VPC, then add a route in the public route table
- Without IGW, VPC is completely isolated
- Private subnets never route through IGW — only public subnets do

---

## Q4. What is a NAT Gateway and why do private subnets need it?

### 1. What is this question actually asking?
- The interviewer wants to know how private resources access the internet securely
- Common follow-up: "What is the difference between NAT Gateway and Internet Gateway?"

### 2. Understand the concept
Your EKS worker nodes are in private subnets — they can't receive inbound traffic from the internet (good, for security). But they still need to reach the internet to:
- Pull Docker images from GHCR
- Call AWS APIs (EKS, ECR, S3)
- Download OS package updates

A NAT Gateway sits in a public subnet and acts as a proxy. Private resources send outbound traffic through the NAT Gateway → out to the internet. Return traffic comes back to the NAT Gateway → forwarded back to the private resource. Inbound connections from the internet are impossible — the NAT only allows outbound.

### 3. The actual answer

| | Internet Gateway | NAT Gateway |
|--|----------------|-------------|
| Direction | Both inbound + outbound | Outbound only |
| Subnet | Attached to public subnet route tables | Lives in public subnet, used by private subnets |
| Cost | Free | ~$0.045/hour + data transfer charges |
| High availability | Managed by AWS | 1 per AZ (you create multiple) |

In your repo, you have two NAT Gateways (one per AZ) for high availability:
- `aws_nat_gateway.nat_a` in `public_a` → used by `private_a`
- `aws_nat_gateway.nat_b` in `public_b` → used by `private_b`

Private subnet route tables point to their respective NAT Gateway:
```text
0.0.0.0/0  →  nat-gateway-a  (for private_a)
0.0.0.0/0  →  nat-gateway-b  (for private_b)
```

### 4. Practical commands / examples

```hcl
resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id   # Elastic IP (public IP for the NAT)
  subnet_id     = aws_subnet.public_a.id  # must be in PUBLIC subnet
}

resource "aws_route" "private_a_internet" {
  route_table_id         = aws_route_table.private_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat_a.id
}
```

### 5. Key takeaway
- NAT Gateway = outbound-only internet access for private subnet resources
- Lives in PUBLIC subnet — private subnets route through it
- One NAT Gateway per AZ for high availability (if one AZ fails, other AZ's NAT still works)
- NAT Gateway has a cost — unlike IGW. For dev/learning, one NAT Gateway is enough

---

## Q5. What is an Elastic IP (EIP) and why does a NAT Gateway need one?

### 1. What is this question actually asking?
- Simple question about static public IP addresses in AWS
- The interviewer checks if you understand why NAT Gateways need EIPs

### 2. Understand the concept
When an EC2 instance is stopped and started, its public IP changes. An Elastic IP is a static public IP address that you own — it doesn't change even if you stop/restart the instance or replace the NAT Gateway.

### 3. The actual answer
A NAT Gateway needs a public IP address so that when private subnet resources make outbound requests, those requests appear to come from a known, stable IP. This matters for:
- Whitelisting your IPs in external firewalls or API rate limits
- Stability — if the NAT Gateway is replaced (e.g., failure), the EIP is reassigned to the new one, so external systems see the same source IP

In your repo, each NAT Gateway gets its own EIP:
```hcl
resource "aws_eip" "nat_a" {
  domain = "vpc"
}
```

> **Cost note**: Elastic IPs are free when attached to a running resource. You are charged ~$0.005/hour for EIPs that are allocated but NOT attached (e.g., if you stop the NAT Gateway but don't release the EIP).

### 4. Key takeaway
- EIP = static public IP address that you control
- NAT Gateways require an EIP so their outbound traffic has a stable source IP
- EIPs are free when in use, charged when idle
- Always release EIPs when deleting infrastructure to avoid unnecessary charges

---

## Q6. What is a Route Table and how does routing work in a VPC?

### 1. What is this question actually asking?
- The interviewer is checking if you understand how traffic is directed within a VPC
- They want to know if you understand the relationship between subnets and route tables

### 2. Understand the concept
When a packet of data leaves an EC2 instance, the VPC needs to decide where to send it. This decision is made using a route table — a set of rules that say "traffic destined for this IP range should go to this next hop."

Every subnet must be associated with exactly one route table. The route table determines whether the subnet is effectively public or private.

### 3. The actual answer
A route table contains route entries:

| Destination | Target | Meaning |
|------------|--------|---------|
| `10.40.0.0/16` | `local` | Traffic within the VPC stays within the VPC |
| `0.0.0.0/0` | `igw-xxx` | All other traffic goes to Internet Gateway (public subnet) |
| `0.0.0.0/0` | `nat-xxx` | All other traffic goes to NAT Gateway (private subnet) |

Routes are matched most-specific first. `10.40.0.0/16` (specific) matches before `0.0.0.0/0` (default).

In your repo:
- `aws_route_table.public` has a route to IGW → makes public_a and public_b actually public
- `aws_route_table.private_a` has a route to NAT Gateway A → private_a stays private but can reach internet
- `aws_route_table.private_b` has a route to NAT Gateway B → same for private_b

### 4. Practical commands / examples

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

# Associate public_a subnet with this route table
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
```

### 5. Key takeaway
- Route table = traffic direction rules for a subnet
- Every subnet must be associated with one route table
- "Public subnet" = route table has `0.0.0.0/0 → IGW`
- "Private subnet" = route table has `0.0.0.0/0 → NAT Gateway` (or no default route)
- Local route (`10.40.0.0/16 → local`) is always present automatically

---

## Q7. What is a Security Group and how is it different from a Network ACL?

### 1. What is this question actually asking?
- The interviewer is testing if you understand the two layers of network security in AWS
- They want to know the practical difference and when you use each

### 2. Understand the concept
AWS has two layers of network filtering. Security groups work at the resource level (per EC2 instance, per RDS, per EKS node). Network ACLs work at the subnet level (all traffic in/out of an entire subnet). Most day-to-day security is done with security groups.

### 3. The actual answer

| | Security Group | Network ACL |
|--|--------------|-------------|
| Level | Resource (EC2, RDS, EKS) | Subnet |
| State | Stateful | Stateless |
| Default | Deny all inbound, allow all outbound | Allow all |
| Rules | Allow rules only | Allow and Deny rules |
| Rule evaluation | All rules evaluated | Rules evaluated in number order |

**Stateful** (Security Groups): If you allow inbound port 22, the response traffic is automatically allowed — you don't need an outbound rule for it.

**Stateless** (Network ACLs): You must explicitly allow both inbound AND outbound traffic for every connection.

In your repo, security groups are used (in `terraform/security_groups.tf`):
- `jump-sg`: allows SSH from admin IP, allows all outbound
- `app-sg`: allows SSH from jump server security group only, allows all outbound

### 4. Practical commands / examples

```hcl
resource "aws_security_group" "jump" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["183.87.191.105/32"]  # admin IP only
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"           # all protocols
    cidr_blocks = ["0.0.0.0/0"] # all outbound
  }
}
```

### 5. Key takeaway
- Security groups = stateful firewall at the resource level (most commonly used)
- Network ACLs = stateless firewall at the subnet level (additional layer)
- Security groups: allow-only rules, stateful (return traffic automatic)
- Network ACLs: allow + deny rules, stateless (must allow both directions)
- For most use cases, security groups alone are sufficient

---

## Q8. What is the difference between inbound and outbound rules in a security group?

### 1. What is this question actually asking?
- Simple question checking understanding of traffic direction in security groups

### 2. Understand the concept
Traffic into a resource (someone connecting to it) = inbound. Traffic from a resource going out to something else = outbound. Security groups let you control both directions independently.

### 3. The actual answer

**Inbound rules**: Control what traffic can reach the resource
- Example: Allow SSH (port 22) from admin IP
- Example: Allow HTTP (port 8080) from the load balancer security group

**Outbound rules**: Control what traffic the resource can send out
- Default: Allow all outbound (which is why your EC2 can reach the internet)
- Restricting outbound is useful for compliance environments

Because security groups are **stateful**: if an inbound connection is allowed, the response automatically flows back — you don't need a matching outbound rule for it.

In your repo, both security groups allow all outbound (`0.0.0.0/0`) — this is why they're flagged by Trivy (AWS-0104) and suppressed with justification in `.trivyignore`.

### 4. Key takeaway
- Inbound = traffic coming into the resource
- Outbound = traffic going out from the resource
- Security groups are stateful — response traffic is automatic
- Restrict outbound for high-security environments (databases, compliance workloads)

---

## Q9. What is a CIDR block and how do you read it?

### 1. What is this question actually asking?
- The interviewer is checking if you can read and reason about IP address ranges
- Common follow-up: "How many IP addresses does a /24 give you?"

### 2. Understand the concept
CIDR (Classless Inter-Domain Routing) notation is a compact way to represent a range of IP addresses. The number after the slash tells you how many bits are fixed (the network part) — the rest are available for hosts.

### 3. The actual answer
Format: `IP_ADDRESS/PREFIX_LENGTH`

The prefix length determines how many IP addresses are in the range:

| CIDR | Total IPs | Usable IPs | Typical Use |
|------|-----------|-----------|-------------|
| `/16` | 65,536 | 65,531 | VPC |
| `/24` | 256 | 251 | Subnet |
| `/28` | 16 | 11 | Small subnet |
| `/32` | 1 | 1 | Single IP (e.g., admin IP in SG rule) |

Formula: **2^(32 - prefix)** = total IPs. AWS reserves 5 IPs per subnet (first 4 + last 1).

Your repo uses:
- `10.40.0.0/16` for the VPC (65,536 IPs)
- `10.40.1.0/24` for each subnet (256 IPs, 251 usable)

### 4. Key takeaway
- Lower the prefix number = larger the range = more IPs
- `/16` for VPC, `/24` for subnets is a common pattern
- `/32` = single IP (used in security group rules to restrict to one IP)
- AWS reserves 5 IPs per subnet: network address, VPC router, DNS, future use, broadcast

---

## Q10. Why do you have two NAT Gateways in two AZs instead of one?

### 1. What is this question actually asking?
- The interviewer is testing your understanding of high availability and AZ-level failure
- They want to see if you think about failure scenarios when designing networks

### 2. Understand the concept
AWS Availability Zones are physically separate data centres within a region. If one AZ has a power failure or network issue, the other AZs are unaffected. If all your private subnet traffic routes through a single NAT Gateway in one AZ, and that AZ goes down — all your private resources lose internet access.

### 3. The actual answer
In your repo, you have:
- `nat_a` in `public_a` (ap-south-1a) → used by `private_a`
- `nat_b` in `public_b` (ap-south-1b) → used by `private_b`

This means:
- EKS nodes in `private_a` (ap-south-1a) use `nat_a`
- EKS nodes in `private_b` (ap-south-1b) use `nat_b`
- If ap-south-1a goes down, nodes in ap-south-1b still have internet via `nat_b`

**Trade-off**: Two NAT Gateways cost roughly double (~$0.09/hour total vs $0.045/hour). For dev/learning, one NAT Gateway is fine. For production workloads, two (one per AZ) is standard.

### 4. Key takeaway
- One NAT Gateway per AZ = high availability for outbound traffic
- If you use one NAT in AZ-a and AZ-a fails → all private resources lose internet
- Cost vs availability trade-off: 1 NAT (cheap) vs 2 NATs (resilient)
- For learning: use 1 NAT. For production: use one per AZ

---

## Q11. What is a Bastion Host (Jump Server) and why do you need one?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand secure access patterns to private infrastructure
- They are checking whether you know why you don't expose private servers directly to the internet

### 2. Understand the concept
Your application servers and EKS nodes are in private subnets — they can't be reached from the internet. But you still need to SSH into them for administration. The solution is a bastion host (also called a jump server): a single, hardened EC2 instance in the public subnet that you SSH into first, then SSH from there to private resources.

One door into your network, and you watch that door carefully.

### 3. The actual answer
In your repo:
- Jump server is in `public_a` with a public IP
- Security group allows SSH only from your admin IP (`183.87.191.105/32`)
- App server security group allows SSH only from the jump server's security group

Access pattern:
```text
Your laptop → SSH → Jump Server (public IP) → SSH → App Server (private IP)
                    (port 22, admin IP only)    (port 22, jump SG only)
```

This means:
- Only one entry point to your network (easier to monitor/audit)
- App server is never directly exposed to the internet
- If you want to revoke all access, you remove the jump server's SG rule

### 4. Practical commands / examples

Command:
```bash
# SSH to jump server
ssh -i ~/.ssh/linux-ec2-lab-key.pem ec2-user@<jump_public_ip>

# From jump server, SSH to app server
ssh -i ~/.ssh/linux-ec2-lab-key.pem ec2-user@<app_private_ip>

# Or use SSH proxy jump in one command
ssh -J ec2-user@<jump_ip> ec2-user@<app_private_ip> -i ~/.ssh/key.pem
```

Purpose: `-J` flag (ProxyJump) tells SSH to tunnel through the jump server in one command.

### 5. Key takeaway
- Jump server = single controlled entry point to private infrastructure
- Reduces attack surface — only one public IP to secure
- Security group on jump server restricts SSH to known admin IPs only
- Modern alternative: AWS Systems Manager Session Manager (no open port 22 needed)

---

## Q12. What is VPC peering and when would you use it?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand cross-VPC networking
- They may follow up with: "What are the limitations of VPC peering?"

### 2. Understand the concept
By default, two VPCs cannot communicate with each other — even in the same AWS account. VPC peering creates a direct network connection between two VPCs so their resources can communicate using private IP addresses.

### 3. The actual answer
VPC peering is a networking connection between two VPCs that allows traffic to flow between them using private IPs (no internet involved).

Common use cases:
- Connecting a dev VPC to a shared services VPC (monitoring, logging)
- Multi-account setups where prod and tooling accounts need to communicate
- Connecting microservices in separate VPCs

**Limitations**:
- Non-transitive: If VPC-A peers with VPC-B, and VPC-B peers with VPC-C, VPC-A cannot reach VPC-C through B
- CIDR blocks must not overlap
- Requires route table updates in both VPCs

**Modern alternative**: AWS Transit Gateway — hub and spoke model, supports transitive routing.

### 4. Key takeaway
- VPC peering = private network connection between two VPCs
- Non-transitive — no chaining (A→B→C doesn't work)
- CIDRs must not overlap — plan IP ranges carefully
- For many VPCs, use Transit Gateway instead of many peering connections

---

## Q13. What are VPC endpoints and why would you use them?

### 1. What is this question actually asking?
- The interviewer is testing if you understand private connectivity to AWS services
- They want to know if you've thought about traffic leaving your VPC to reach AWS services

### 2. Understand the concept
When your EC2 instance calls the S3 API or the EKS API, by default that traffic goes out through your NAT Gateway → public internet → AWS service endpoint. This costs money (NAT Gateway data transfer charges) and the traffic briefly touches the public internet.

VPC endpoints create a private connection from your VPC directly to AWS services — the traffic never leaves the AWS network.

### 3. The actual answer
There are two types:

**Gateway endpoints** (free, for S3 and DynamoDB):
```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.main.id
  service_name = "com.amazonaws.ap-south-1.s3"
  route_table_ids = [aws_route_table.private_a.id]
}
```

**Interface endpoints** (cost ~$0.01/hour, for most other AWS services):
Creates an ENI in your subnet with a private IP pointing to the service.

For EKS, interface endpoints for `ec2`, `ecr.api`, `ecr.dkr`, `s3`, `sts` let nodes pull images and call APIs without going through NAT Gateway — reducing cost and keeping traffic private.

In your repo, `.trivyignore` suppresses `AWS-0104` (unrestricted egress) with a note: "Production hardening: replace with VPC endpoints." This is the intended improvement.

### 4. Key takeaway
- VPC endpoints = private connection to AWS services (no internet, no NAT)
- Reduces NAT Gateway data transfer costs
- Keeps traffic within AWS network (better security)
- Two types: Gateway (S3, DynamoDB — free) and Interface (everything else — small hourly cost)

---

## Q14. What is the difference between ap-south-1a, ap-south-1b (Availability Zones)?

### 1. What is this question actually asking?
- The interviewer is checking if you understand the physical infrastructure concept behind AZs
- They want to know how you use AZs for high availability

### 2. Understand the concept
An AWS Region is a geographic area (ap-south-1 = Mumbai, India). Within each region, AWS operates multiple physically separate data centres. These are called Availability Zones. They have independent power, cooling, and networking — if one fails, the others keep running.

### 3. The actual answer
In ap-south-1 (Mumbai), there are 3 AZs: ap-south-1a, ap-south-1b, ap-south-1c.

In your repo, you use 2 AZs for high availability:
- Resources in ap-south-1a (public_a, private_a)
- Resources in ap-south-1b (public_b, private_b)

This means:
- EKS worker nodes spread across 2 AZs — if ap-south-1a goes down, nodes in ap-south-1b keep running
- NAT Gateways in both AZs — private resources in each AZ use their local NAT
- PodDisruptionBudget ensures at least 1 Spring Boot pod stays running during node failures

**Important**: AZ names are per-account. Your `ap-south-1a` might be a different physical building than someone else's `ap-south-1a` — AWS randomizes this to spread load.

### 4. Key takeaway
- AZ = physically separate data centre within a region
- Deploy across multiple AZs for high availability (survive one AZ failure)
- Subnets are AZ-specific — each subnet lives in exactly one AZ
- Your repo uses 2 AZs — minimum for production, 3 AZs is ideal

---

## Q15. What is DNS in a VPC and why is it important for EKS?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand how name resolution works inside a VPC
- They are checking if you know why `enable_dns_support` and `enable_dns_hostnames` matter

### 2. Understand the concept
IP addresses are hard to remember and change. DNS (Domain Name System) maps names to IPs. Inside a VPC, AWS provides a built-in DNS resolver so resources can find each other by name — and Kubernetes relies on this heavily.

### 3. The actual answer
When you enable DNS in your VPC:
- `enable_dns_support = true`: Enables the AWS-provided DNS resolver at `10.40.0.2` (VPC CIDR base + 2)
- `enable_dns_hostnames = true`: Gives EC2 instances DNS hostnames (like `ip-10-40-2-x.ap-south-1.compute.internal`)

EKS depends on both:
- Worker nodes need DNS to resolve AWS API endpoints (EKS, ECR, S3)
- Kubernetes CoreDNS provides in-cluster DNS for services (`springboot.default.svc.cluster.local`)
- AWS VPC DNS is the upstream resolver for CoreDNS

Without DNS working correctly, EKS nodes fail to join the cluster and pods can't resolve service names.

### 4. Key takeaway
- Always enable `dns_support` and `dns_hostnames` in VPCs used by EKS
- AWS provides DNS at VPC_CIDR+2 (e.g., `10.40.0.2`)
- EKS CoreDNS provides Kubernetes service DNS (`service.namespace.svc.cluster.local`)
- DNS failures are a common root cause of EKS node join issues

---

## Q16. What happens to network traffic between two EC2 instances in the same VPC?

### 1. What is this question actually asking?
- The interviewer wants to know if you understand intra-VPC routing
- They are testing whether you know traffic stays private and doesn't hit the internet

### 2. Understand the concept
Traffic between resources in the same VPC is handled by the VPC's local routing — it never leaves the AWS network and never goes through any internet gateway or NAT. The local route (`10.40.0.0/16 → local`) in every route table handles this.

### 3. The actual answer
When your jump server (10.40.1.x) SSH's to the app server (10.40.2.x):
1. Jump server sends packet to `10.40.2.x`
2. Route table: `10.40.0.0/16 → local` matches (more specific than `0.0.0.0/0`)
3. Packet routes internally within VPC
4. Security group on app server: allows SSH from jump server's security group ✅
5. Connection established — traffic stays entirely within AWS

The key controls are:
- Route table (does traffic routing)
- Security group (allows/denies the connection)

### 4. Key takeaway
- Intra-VPC traffic never leaves AWS — uses the implicit `local` route
- Security groups still apply — even internal traffic must be allowed
- No NAT or IGW involved for VPC-internal traffic
- Subnets within same VPC can communicate if security groups allow it

---

## Q17. What is an Elastic Network Interface (ENI)?

### 1. What is this question actually asking?
- The interviewer is checking if you understand what gives an EC2 instance its network identity
- May follow up with: "Can you move an ENI between instances?"

### 2. Understand the concept
Every EC2 instance needs a network card — a way to send and receive network traffic. In AWS, this virtual network card is called an ENI (Elastic Network Interface). Each ENI has a private IP, optional public IP, and is associated with security groups.

### 3. The actual answer
An ENI is a virtual network card that:
- Has a private IP address (from the subnet CIDR)
- Optionally has a public IP or Elastic IP
- Is associated with one or more security groups
- Lives in a specific subnet (and therefore AZ)

Every EC2 instance gets a primary ENI automatically. You can attach additional ENIs for multi-homing (connecting to multiple subnets).

ENIs can be detached from one instance and attached to another — useful for failover scenarios where you move an IP to a replacement instance.

EKS worker nodes get additional ENIs for pod networking (AWS VPC CNI plugin assigns pod IPs from the node's ENI).

### 4. Key takeaway
- ENI = virtual network card for EC2 instances
- Primary ENI created automatically with EC2 instance
- Security groups are attached to ENIs, not instances directly
- EKS VPC CNI uses ENIs to assign real VPC IPs to pods

---

## Q18. Why are EKS worker nodes in private subnets and not public subnets?

### 1. What is this question actually asking?
- The interviewer wants to see if you applied security best practices consciously — not by accident
- They want to hear the reasoning, not just "because it's secure"

### 2. Understand the concept
EKS worker nodes run your application pods. There is no reason for the internet to initiate connections directly to your nodes. Users reach your applications through a load balancer — which can be in a public subnet. The nodes themselves should be completely internal.

### 3. The actual answer
Worker nodes are in private subnets because:

1. **No inbound internet access**: Pods don't need to receive direct connections from the internet — load balancers in public subnets do that
2. **Reduced attack surface**: A compromised pod can't be directly reached from the internet (attacker would need to compromise the load balancer first)
3. **EKS API security**: EKS control plane API is private-only — accessible from within the VPC only, not from the internet
4. **Compliance**: Most security standards (PCI-DSS, HIPAA) require application servers in private subnets

Nodes still need outbound internet for:
- Pulling Docker images from GHCR
- Calling AWS APIs (EKS, EC2, ECR)
- Package updates

This is handled by the NAT Gateway.

### 4. Key takeaway
- Worker nodes in private subnets = no direct internet exposure
- Internet traffic reaches pods through load balancers (in public subnets)
- Nodes use NAT Gateway for outbound-only internet access
- EKS API (`endpoint_public_access = false`) means even the K8s API is private

---

## Q19. What is the AWS Shared Responsibility Model for networking?

### 1. What is this question actually asking?
- The interviewer wants to see if you understand what AWS manages vs what you are responsible for
- Common in security-focused interviews

### 2. Understand the concept
AWS manages the physical infrastructure — the data centres, physical network cables, hardware. You manage everything you configure on top of it — your VPC, security groups, route tables, and what runs inside your instances.

### 3. The actual answer

| AWS Responsible For | You Responsible For |
|--------------------|-------------------|
| Physical network hardware | VPC design and configuration |
| Physical data centre security | Security group rules |
| Hypervisor network isolation | Route table configuration |
| Physical separation between customers | IAM permissions for network changes |
| DDoS protection (AWS Shield Standard) | NACLs and firewall rules |
| Global backbone network | Patching OS on EC2 instances |

In short: AWS secures the infrastructure. You secure what you put on it.

### 4. Key takeaway
- AWS = physical infrastructure and hypervisor
- You = everything inside the VPC (routing, firewall rules, IAM, OS patches)
- Misconfigured security groups, public subnets, or open ports = your responsibility
- AWS Shield Standard provides basic DDoS protection automatically (free)

---

## Q20. How does traffic flow when a user accesses your Spring Boot application?

### 1. What is this question actually asking?
- The interviewer wants to see if you can trace the complete network path end-to-end
- This tests whether all your networking knowledge connects into a coherent picture

### 2. Understand the concept
This is an end-to-end question. It covers every networking component working together. It is one of the best questions to verify your understanding because you need to know all the pieces and how they connect.

### 3. The actual answer
Full traffic flow (without load balancer, using port-forward for now):

```text
User's browser
      │ HTTPS request to Spring Boot
      ▼
Internet
      │
      ▼
Internet Gateway (igw attached to VPC)
      │ Traffic enters VPC
      ▼
Public Subnet (if using load balancer or port-forward)
      │
      ▼
[Kubernetes Service - ClusterIP]
      │ Routes to pod
      ▼
Pod running Spring Boot (private subnet, EKS worker node)
  IP: 10.40.2.x
  Port: 8080
      │
      ▼
Spring Boot processes request
      │
      ▼
Response follows same path back
```

For production, an Application Load Balancer (ALB) sits in the public subnet and forwards to the Kubernetes service. This is not yet implemented in this repo — it would require an Ingress resource and the AWS Load Balancer Controller.

### 4. Key takeaway
- Traffic: Internet → IGW → Public subnet → Load Balancer → Private subnet → Pod
- Users never directly reach worker nodes — always through a load balancer
- The return path is symmetric — security groups are stateful so return traffic is automatic
- This repo uses port-forward for local access (no ALB yet)

---

## Q21. What would you check if an EC2 instance cannot reach the internet?

### 1. What is this question actually asking?
- This is a troubleshooting question testing your systematic diagnostic approach
- The interviewer wants to see if you know all the layers that can block connectivity

### 2. Understand the concept
Network connectivity problems in AWS always come from one of several layers: routing, security groups, NACLs, IGW/NAT, or the instance itself. The key is to check each layer systematically — not guess randomly.

### 3. The actual answer
Troubleshoot in this order:

**Step 1 — Is it a public or private instance?**
- Public instance should have a public IP and an IGW route
- Private instance should route through a NAT Gateway

**Step 2 — Check the route table**
```text
Does the subnet's route table have 0.0.0.0/0 → IGW (public) or NAT (private)?
If missing → instance cannot reach internet regardless of security group
```

**Step 3 — Check the security group outbound rules**
```text
Does the security group allow outbound traffic?
Default: all outbound allowed
If restricted: check if the destination port/IP is allowed
```

**Step 4 — Check NACLs**
```text
Does the subnet's NACL allow outbound traffic AND inbound response traffic?
NACLs are stateless — both directions must be allowed explicitly
```

**Step 5 — Check IGW/NAT Gateway**
```text
Public: Is the IGW attached to the VPC?
Private: Is the NAT Gateway in ACTIVE state? Is it in a PUBLIC subnet?
```

**Step 6 — Check instance-level**
```text
Is the OS firewall (iptables/firewalld) blocking traffic?
Is the application binding to the correct interface?
```

### 4. Practical commands / examples

Command:
```bash
# From inside the EC2 instance
curl -I https://google.com
```
Purpose: Quick test of outbound internet connectivity.

Command:
```bash
# Check route table from AWS CLI
aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=subnet-xxx"
```
Purpose: Verify the route table has a default route to IGW or NAT.

### 5. Key takeaway
- Troubleshoot in layers: Route table → Security group → NACL → IGW/NAT → OS
- Route table is the most common culprit (missing default route)
- NACLs are stateless — often forgotten when adding new ports
- Security groups are stateful — only inbound rule needed for response traffic
