# cloud-sec-gateway

A self-hosted WireGuard VPN gateway on AWS, provisioned with Terraform, running in a minimal Docker container, with a small S3 + Lambda pipeline for collecting and logging tunnel telemetry.

The idea wasn't just "spin up a VPN" — I wanted to set it up the way you'd actually want it running in production: no SSH exposed to the internet, a locked-down security group, infra defined as code instead of clicked together, and some basic observability on the tunnel.

---

## Architecture

```
                     ┌─────────────────────────┐
                     │        AWS VPC           │
                     │   (10.0.0.0/16)          │
                     │                          │
   Internet ── IGW ──┤  Public Subnet (x3 AZs)  │
     (UDP 51820)     │        │                  │
                     │   ┌────▼─────────────┐    │
                     │   │  EC2 t3.micro    │    │
                     │   │  Ubuntu 24.04    │    │
                     │   │  Docker:         │    │
                     │   │   WireGuard      │    │
                     │   │   container      │    │
                     │   └────┬─────────────┘    │
                     │        │ SSM (no SSH)      │
                     └────────┼──────────────────┘
                              │
                     telemetry_collector.py
                     (wg show → JSON → S3)
                              │
                              ▼
                     S3 bucket (wireguard-telemetry)
                              │  ObjectCreated event
                              ▼
                     wireguard-monitor.PY (Lambda)
                     → reads file → logs to CloudWatch
```

---

## Infrastructure (Terraform)

The AWS side is defined in Terraform instead of being set up by hand in the console:

- **Networking** — a VPC (`10.0.0.0/16`), an Internet Gateway, and public subnets across three Availability Zones, with a single route table handling traffic out.
- **Locked-down security group** — this is probably the main security decision here: no inbound SSH or HTTP at all. The only inbound rule is WireGuard's UDP port. Outbound is limited to HTTPS, HTTP (for installing packages), and DNS, instead of just leaving everything open.
- **SSM instead of SSH** — I connect to the instance through AWS Systems Manager Session Manager, using an IAM role attached at boot. That means no SSH key to manage or accidentally leak, and no port 22 open to the internet.
- **A few EC2 hardening basics** — IMDSv2 is required (`http_tokens = "required"`), the root volume is encrypted, and the AMI is resolved dynamically from Canonical's official Ubuntu 24.04 image instead of being pinned to something that could go stale.
- **Region locked to `us-east-1`** — there's a validation rule on the `aws_region` variable for this, mostly just to keep things inside the AWS free tier and avoid deploying somewhere by accident.

**Outputs** give you the instance ID (for `aws ssm start-session --target <id>`), the instance's public IP (for your WireGuard client config), and the VPC ID.

## Containerized Gateway (Docker)

WireGuard runs in its own small container instead of being installed straight on the host:

- **Base image**: `alpine:3.20` — smaller footprint than a general-purpose distro.
- **Packages**: `wireguard-tools`, `iptables`, `iproute2` — just what's needed to bring up and route the tunnel.
- The container starts with `wg-quick up wg0` and stays alive with `tail -f /dev/null`.
- Compose gives it only the capabilities it actually needs — `NET_ADMIN` and `SYS_MODULE` — plus access to `/dev/net/tun`, and runs in `network_mode: host` since WireGuard needs direct access to the host's network stack. Config lives in a mounted `./wireguard_config` volume so it's never baked into the image.

## Telemetry Pipeline (Python + S3 + Lambda)

The monitoring side is a small event-driven pipeline rather than a full monitoring service:

- **`telemetry_collector.py`** runs `wg show wg0 dump` to grab live tunnel stats, wraps it in a timestamped JSON payload, and uploads it to an S3 bucket (`logs/status_<timestamp>.json`).
- **`wireguard-monitor.PY`** is actually an **AWS Lambda function**, not something running on the server — it fires off the S3 `ObjectCreated` event whenever a new telemetry file lands in the bucket, reads the file, and logs the contents to **CloudWatch Logs**. So there's a running record of tunnel activity without needing a monitoring box up 24/7.

Right now this is just logging, not alerting — if the tunnel drops, nothing pages anyone yet. That'd be the natural next thing to add (see below).

---

## Security Notes

- **No SSH.** The security group has zero inbound TCP rules; all admin access goes through SSM, authenticated via IAM instead of a key pair sitting on someone's laptop.
- **Secrets stay out of git.** WireGuard keys and client configs (`wg0.conf`, client `.conf` files, private keys) are excluded via `.gitignore`.
- **Git history got cleaned up.** Early on I accidentally committed some secret files before `.gitignore` was actually in place. Once I caught it, I used [`git-filter-repo`](https://github.com/newren/git-filter-repo) to remove `wg0.conf`, `mac_client.conf`, and private keys from the entire commit history (not just delete them going forward), and rotated the affected keys.

  > If you clone or fork this, generate your own WireGuard keypair — don't reuse anything from the project's history, even after the cleanup.

---

## Project Structure

```
cloud-sec-gateway/
├── main.tf              # VPC, subnets, security group, IAM/SSM, EC2 instance
├── variables.tf         # Region, environment, CIDR, AZs, WireGuard port
├── outputs.tf           # instance_id, instance_public_ip, vpc_id
├── providers.tf         # Terraform + AWS provider config
├── Dockerfile           # Minimal Alpine WireGuard image
├── docker-compose.yml   # WireGuard service definition
├── telemetry_collector.py   # Pulls `wg show` stats → uploads to S3
├── wireguard-monitor.PY     # Lambda: S3 → CloudWatch Logs
└── .gitignore
```

---

## Deployment

### 1. Provision AWS infrastructure

```bash
terraform init
terraform plan
terraform apply
```

This creates the VPC, subnets, security group, IAM/SSM role, and the EC2 instance. `aws_region` is locked to `us-east-1`.

### 2. Connect to the instance (no SSH)

```bash
aws ssm start-session --target $(terraform output -raw instance_id)
```

### 3. Configure WireGuard

Drop your server config/keys into `./wireguard_config` on the instance (this folder is git-ignored, so keys never touch version control).

### 4. Launch the gateway container

```bash
docker compose up -d --build
```

### 5. Set up telemetry (optional)

- Make your own S3 bucket and update the bucket name in `telemetry_collector.py` (it currently points at `wireguard-telemetry-vanij`).
- Deploy `wireguard-monitor.PY` as a Lambda function with an S3 trigger on that bucket's `ObjectCreated` events.
- Run `telemetry_collector.py` on a schedule (cron works fine) to push periodic `wg show` snapshots.

---

## Trade-offs / Notes to self

- **SSM over SSH** — cuts out an entire attack surface (no open port 22, no keys to manage), but means you need the AWS CLI/console to connect instead of a plain SSH client.
- **Lambda + S3 for telemetry instead of a monitoring server** — no box to keep patched and running 24/7, but it's passive logging for now, not alerting.
- **Region locked to `us-east-1`** — keeps this inside free-tier limits while I was building it, at the cost of flexibility if I ever wanted to deploy elsewhere.
- **`network_mode: host`** — simplest way to get WireGuard routing working right in Docker, but it does give up some of the isolation containers normally provide.

## Still want to add

- Actual alerting instead of just CloudWatch logs (dropped handshake should trigger a notification, not just a log line)
- Stop hardcoding the S3 bucket name in the script
- A `terraform.tfvars.example` so the required variables aren't a guessing game