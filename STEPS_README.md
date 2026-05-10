# ShopIQ — Private LLM Customer Service Chatbot
### Complete Build & Operations Guide

> **What this is:** A customer service chatbot for an e-commerce platform where the AI model runs entirely on a VM you control inside a private Azure VNET. No customer data reaches any public cloud AI service.
>
> **Stack:** Azure VM · Ubuntu 22.04 · Ollama · Llama 3.1 8B · Python Flask · MySQL 8 · Bootstrap 5
>
> **Architecture:**
> ```
> Your Mac (Flask :5001 + MySQL :3306)
>     └── HTTP POST → Azure VM Public IP :11434
>             └── Ollama → llama3.1:8b (local inference)
> ```

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Azure CLI Login](#2-azure-cli-login)
3. [Create Resource Group](#3-create-resource-group)
4. [Create VNET and Subnet](#4-create-vnet-and-subnet)
5. [Create Network Security Group](#5-create-network-security-group)
6. [Create the Linux VM](#6-create-the-linux-vm)
7. [SSH Into the VM](#7-ssh-into-the-vm)
8. [Configure UFW Firewall on the VM](#8-configure-ufw-firewall-on-the-vm)
9. [Install System Updates and Dependencies](#9-install-system-updates-and-dependencies)
10. [Install Ollama and Pull the LLM](#10-install-ollama-and-pull-the-llm)
11. [Expose Ollama on All Interfaces](#11-expose-ollama-on-all-interfaces)
12. [Open Port 11434 in Azure NSG](#12-open-port-11434-in-azure-nsg)
13. [Test Ollama From Your Mac](#13-test-ollama-from-your-mac)
14. [MySQL Setup on Mac](#14-mysql-setup-on-mac)
15. [Deploy the Flask App on Mac](#15-deploy-the-flask-app-on-mac)
16. [Run the Application](#16-run-the-application)
17. [Adding a Second Mac](#17-adding-a-second-mac)
18. [Cost Management — Stop and Start the VM](#18-cost-management--stop-and-start-the-vm)
19. [Demo Day Scripts](#19-demo-day-scripts)
20. [Troubleshooting Reference](#20-troubleshooting-reference)

---

## 1. Prerequisites

**Why:** Before any Azure work you need the CLI installed locally, an SSH key pair for VM authentication, and your shell variables set so every subsequent command works without editing.

### On your Mac — install Azure CLI
```bash
brew update && brew install azure-cli
az --version    # confirm installation
```

### Confirm SSH key exists (or create one)
```bash
ls -la ~/.ssh/id_rsa.pub
```

If missing:
```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
```

### Set shell variables — paste once per terminal session
```bash
RG="rg-shopiq-poc"
LOCATION="eastus"
VNET="vnet-shopiq"
SUBNET="snet-shopiq"
NSG="nsg-shopiq"
VM="vm-shopiq-llm"
VM_SIZE="Standard_D4s_v3"    # 4 vCPU, 16 GB RAM — fits Llama 3.1 8B on CPU
ADMIN="azureuser"
SSH_PUB="$HOME/.ssh/id_rsa.pub"
```

> **Important:** These variables must be re-set every time you open a new terminal session. If any command fails with a missing resource error, re-paste this block first.

---

## 2. Azure CLI Login

**Why:** All `az` commands authenticate against your Azure subscription. Without logging in, every command will fail.

```bash
az login
```

This opens a browser for MFA. After completing, confirm the correct subscription is active:

```bash
az account show --query "{name:name, id:id, state:state}" -o table
```

If you have multiple subscriptions, set the correct one:
```bash
az account set --subscription "YOUR-SUBSCRIPTION-NAME-OR-ID"
```

---

## 3. Create Resource Group

**Why:** A resource group is the logical container for all Azure resources in this project. Naming it clearly means you can delete everything in one command when the PoC is done — `az group delete --name rg-shopiq-poc` removes the VM, VNET, NSG, and disk together.

```bash
az group create \
  --name     "$RG" \
  --location "$LOCATION"
```

Confirm:
```bash
az group show --name "$RG" \
  --query "{name:name, location:location, state:properties.provisioningState}" \
  -o table
```

Expected: `provisioningState = Succeeded`

---

## 4. Create VNET and Subnet

**Why:** The Virtual Network provides network isolation for the VM. All resources inside the VNET can communicate with each other privately. The subnet is the IP address range the VM will be assigned from.

```bash
az network vnet create \
  --resource-group "$RG" \
  --name           "$VNET" \
  --address-prefix 10.10.0.0/16 \
  --subnet-name    "$SUBNET" \
  --subnet-prefix  10.10.1.0/24
```

---

## 5. Create Network Security Group

**Why:** The NSG is Azure's firewall — it controls what inbound traffic can reach the VM. Without NSG rules, all ports are blocked by default. We open only SSH (port 22) from your specific IP, and later port 11434 for Ollama. This ensures the LLM endpoint is never publicly accessible to the internet.

### Create the NSG
```bash
az network nsg create \
  --resource-group "$RG" \
  --name           "$NSG"
```

### Get your IPv4 address (must be IPv4 — Azure NSG rejects IPv6)
```bash
MY_IP=$(curl -4 -s https://api.ipify.org)
echo "My IP: $MY_IP"
```

> **Critical:** Use `curl -4` to force IPv4. Without the `-4` flag, macOS may return your IPv6 address (format: `2601:...`) which Azure NSG rules reject with an `InvalidAddressPrefix` error.

### Allow SSH from your IP only
```bash
az network nsg rule create \
  --resource-group          "$RG" \
  --nsg-name                "$NSG" \
  --name                    "AllowSSH" \
  --priority                100 \
  --protocol                Tcp \
  --destination-port-ranges 22 \
  --source-address-prefixes "$MY_IP/32" \
  --access                  Allow \
  --direction               Inbound
```

### Associate NSG with the subnet
```bash
az network vnet subnet update \
  --resource-group         "$RG" \
  --vnet-name              "$VNET" \
  --name                   "$SUBNET" \
  --network-security-group "$NSG"
```

### Verify the rule was created
```bash
az network nsg rule list \
  --resource-group "$RG" \
  --nsg-name "$NSG" \
  --query "[].{Name:name, Source:sourceAddressPrefix, Port:destinationPortRange, Access:access}" \
  -o table
```

---

## 6. Create the Linux VM

**Why:** This is the compute node that will run Ollama and serve the LLM. We use `Standard_D4s_v3` (4 vCPU, 16 GB RAM) because Llama 3.1 8B quantized needs ~6 GB of RAM — this VM has enough headroom for the model plus OS processes. Key-based SSH auth is enforced — no password login.

> **Note on VM size:** New Azure subscriptions have zero quota on newer VM families (DSv5, etc.). If you get a `QuotaExceeded` error, check available quota with:
> ```bash
> az vm list-usage --location eastus -o table | grep -i "standard" | grep -v " 0 "
> ```
> Then pick a size from a family with Limit ≥ 4.

```bash
az vm create \
  --resource-group   "$RG" \
  --name             "$VM" \
  --size             "$VM_SIZE" \
  --image            Ubuntu2204 \
  --vnet-name        "$VNET" \
  --subnet           "$SUBNET" \
  --nsg              "$NSG" \
  --admin-username   "$ADMIN" \
  --ssh-key-values   "$SSH_PUB" \
  --public-ip-sku    Standard \
  --os-disk-size-gb  128 \
  --storage-sku      Premium_LRS
```

Takes ~2 minutes. When complete, capture the public IP:

```bash
VM_IP=$(az vm show \
  --resource-group "$RG" \
  --name           "$VM" \
  --show-details \
  --query publicIps -o tsv)

echo "VM IP: $VM_IP"
```

> **The public IP changes every time you deallocate and restart the VM.** Always re-run this command after starting the VM.

---

## 7. SSH Into the VM

**Why:** All VM configuration — firewall, software installation, Ollama setup — happens inside the VM over SSH. The public IP captured above is the entry point.

```bash
ssh -i ~/.ssh/id_rsa "$ADMIN@$VM_IP"
```

On first connection, type `yes` when prompted about the host fingerprint. You are now inside the VM — all commands in steps 8–11 run here.

Confirm you are on the VM:
```bash
hostname && whoami
```

Expected: hostname `vm-shopiq-llm`, user `azureuser`

---

## 8. Configure UFW Firewall on the VM

**Why:** The Azure NSG is the outer perimeter firewall. UFW is the OS-level inner firewall on the VM itself. Both layers are needed for defence in depth. The critical rule: allow SSH (port 22) **before** enabling UFW — otherwise you lock yourself out of the VM permanently.

```bash
# Allow SSH first — do this before enabling UFW
sudo ufw allow 22/tcp

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow HTTP for Nginx (reverse proxy)
sudo ufw allow 80/tcp

# Allow Ollama port so Macs can reach it directly
sudo ufw allow 11434/tcp

# Enable — type 'y' when prompted
sudo ufw enable

# Verify
sudo ufw status verbose
```

Expected output shows: `22/tcp ALLOW IN`, `80/tcp ALLOW IN`, `11434/tcp ALLOW IN`

---

## 9. Install System Updates and Dependencies

**Why:** A freshly provisioned Ubuntu VM has pending security patches. Applying them closes known CVEs before the VM is exposed to the internet. Python 3.11, Nginx, and build tools are needed for the Flask app and Ollama respectively.

```bash
sudo apt update && sudo apt upgrade -y

sudo apt install -y \
  curl wget git unzip \
  net-tools htop \
  python3.11 python3.11-venv python3-pip \
  nginx \
  build-essential

# Verify Python installed
python3.11 --version

# Start and enable Nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

---

## 10. Install Ollama and Pull the LLM

**Why:** Ollama is a single-binary LLM runtime that downloads model weights and serves them via a local REST API. The model weights (~4.7 GB) are downloaded once and stored on the VM disk. All subsequent inference runs entirely from local files — no external API calls, no data leaving the VM.

### Install Ollama
```bash
curl -fsSL https://ollama.com/install.sh | sh
```

### Pull Llama 3.1 8B (~4.7 GB — takes 3–8 minutes)
```bash
ollama pull llama3.1:8b
```

### Verify the model is registered
```bash
ollama list
```

### Test inference locally on the VM
```bash
curl -s http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"ping"}],"stream":false}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['message']['content'])"
```

Expected: a response from the model confirming it is working.

---

## 11. Expose Ollama on All Interfaces

**Why:** By default Ollama binds only to `127.0.0.1:11434` (localhost). To reach it from your Mac over the public IP, it must bind to `0.0.0.0:11434`. The Azure NSG and UFW rules ensure only your whitelisted IPs can actually connect — binding to all interfaces does not make it publicly open.

```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d

sudo tee /etc/systemd/system/ollama.service.d/override.conf << 'EOF'
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
Environment="OLLAMA_KEEP_ALIVE=30m"
EOF

sudo systemctl daemon-reload
sudo systemctl restart ollama
sudo systemctl status ollama --no-pager
```

### Verify it is bound to 0.0.0.0
```bash
ss -tlnp | grep 11434
```

Expected: `0.0.0.0:11434` — not `127.0.0.1:11434`

You can now **exit the VM SSH session** — Ollama runs as a service and persists:
```bash
exit
```

---

## 12. Open Port 11434 in Azure NSG

**Why:** The UFW firewall on the VM now allows port 11434, but the Azure NSG still blocks it at the network perimeter. We need to create an NSG rule that allows your Mac's IP to reach that port. We lock it to your specific IP — not open to the world.

Run this on your **local Mac**:

```bash
MY_IP=$(curl -4 -s https://api.ipify.org)
echo "My IP: $MY_IP"

az network nsg rule create \
  --resource-group          "$RG" \
  --nsg-name                "$NSG" \
  --name                    "AllowOllama" \
  --priority                110 \
  --protocol                Tcp \
  --destination-port-ranges 11434 \
  --source-address-prefixes "$MY_IP/32" \
  --access                  Allow \
  --direction               Inbound
```

### If you have multiple Macs, allow all their IPs in one rule
```bash
az network nsg rule update \
  --resource-group "$RG" \
  --nsg-name       "$NSG" \
  --name           "AllowOllama" \
  --source-address-prefixes "MAC1_IP/32" "MAC2_IP/32"
```

---

## 13. Test Ollama From Your Mac

**Why:** Before wiring up Flask, confirm the direct Mac → Azure VM → Ollama path works end-to-end. This isolates any network issue from any application issue.

```bash
curl -s http://$VM_IP:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"ping"}],"stream":false}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['message']['content'])"
```

Expected: a response from Llama 3.1. If this works, your private LLM is reachable from your Mac exactly like an API endpoint.

---

## 14. MySQL Setup on Mac

**Why:** The Flask app needs a local MySQL database for customer, order, and product data. The database runs locally on each Mac — no shared DB between machines. Each Mac has its own independent MySQL instance.

### Confirm MySQL is running
```bash
brew services list | grep mysql
```

If stopped:
```bash
brew services start mysql
```

### Create database and users
```bash
mysql -u root -p << 'SQL'
CREATE DATABASE IF NOT EXISTS shopiq_db
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS 'shopiq_app'@'127.0.0.1'
  IDENTIFIED BY 'Ch@ng3MeStr0ng!';
GRANT SELECT, INSERT, UPDATE
  ON shopiq_db.* TO 'shopiq_app'@'127.0.0.1';

CREATE USER IF NOT EXISTS 'shopiq_dba'@'127.0.0.1'
  IDENTIFIED BY 'DB@AdminP@ss!';
GRANT ALL PRIVILEGES
  ON shopiq_db.* TO 'shopiq_dba'@'127.0.0.1';
FLUSH PRIVILEGES;
SQL
```

> **Why two users?** `shopiq_app` is the application user with `SELECT, INSERT, UPDATE` only — no DDL privileges. `shopiq_dba` owns schema changes. This follows the principle of least privilege — a bug in the app cannot drop tables.

### Load schema and seed data
```bash
# Run from the project root directory
mysql -u shopiq_dba -p shopiq_db < 01_schema.sql
mysql -u shopiq_dba -p shopiq_db < 02_seed.sql
```

### Verify seed data
```bash
mysql -u shopiq_app -p -h 127.0.0.1 shopiq_db \
  -e "SELECT customer_id, first_name, loyalty_tier FROM customers;"
```

Expected — 5 rows:
```
+-------------+------------+--------------+
| customer_id | first_name | loyalty_tier |
+-------------+------------+--------------+
|           1 | Alice      | GOLD         |
|           2 | Bob        | SILVER       |
|           3 | Carol      | PLATINUM     |
|           4 | David      | BRONZE       |
|           5 | Eve        | SILVER       |
+-------------+------------+--------------+
```

---

## 15. Deploy the Flask App on Mac

**Why:** The Flask app is the application layer — it handles HTTP requests from the browser, queries MySQL for customer and order data, injects that data into the LLM prompt, calls Ollama on the Azure VM, and returns the response. It runs locally on each Mac.

### Create virtual environment and install dependencies
```bash
cd /path/to/azure_custom_llm

python3 -m venv .venv
source .venv/bin/activate

# Use python3 -m pip — avoids shell alias issues on macOS
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt
```

### Create the .env file

**Why:** The `.env` file holds environment-specific configuration — DB credentials and the LLM endpoint URL. It is gitignored and never committed to GitHub. Each Mac has its own `.env` pointing at the same Azure VM.

```bash
cat > .env << 'EOF'
FLASK_SECRET_KEY=dev-secret-change-me
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=shopiq_db
DB_USER=shopiq_app
DB_PASSWORD=Ch@ng3MeStr0ng!
LLM_BASE_URL=http://YOUR_VM_IP:11434/api/chat
LLM_MODEL=llama3.1:8b
EOF
```

Replace `YOUR_VM_IP` with the actual VM public IP from step 6.

Verify the file is clean — every value must be on its own line with no wrapping:
```bash
cat .env
```

### Confirm folder structure is correct

Flask requires `index.html` in a `templates/` subfolder and `chat.css` in `static/css/`. Verify:
```bash
ls templates/    # must show index.html
ls static/css/   # must show chat.css
```

If either file is in the wrong location:
```bash
mkdir -p templates static/css
mv index.html templates/     # if it's in the root
mv chat.css static/css/      # if it's in the root
```

---

## 16. Run the Application

**Why:** Port 5000 is occupied by macOS AirPlay Receiver. Running on port 5001 avoids the conflict without needing to change system settings.

```bash
source .venv/bin/activate
flask --app app run --port 5001
```

Open `http://localhost:5001` in your browser.

### End-to-end test sequence

1. Enter `alice.walker@example.com` in the Identify panel → click Look Up
   - Expected: "Welcome back, Alice Walker! 👋" — GOLD tier badge appears
2. Click "My latest order"
   - Expected: Llama reads Alice's real order from MySQL and returns the FedEx tracking number
3. Click "Laptops in stock"
   - Expected: Product data from MySQL narrated by Llama
4. Click "Refund policy"
   - Expected: Llama answers from system prompt — no DB query needed

All four tests passing confirms: MySQL reads working, Azure LLM reachable, session context maintained.

---

## 17. Adding a Second Mac

**Why:** The app is designed to run independently on each Mac — each with its own MySQL instance. Both Macs call the same Azure VM for LLM inference. The only shared resource is Ollama on the Azure VM.

### On the second Mac — clone the repo
```bash
cd ~/Development
git clone https://github.com/YOUR_USERNAME/shopiq-chatbot.git
cd shopiq-chatbot
```

### Install dependencies
```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install -r requirements.txt
```

### Set up MySQL (same steps as section 14)

### Create .env
```bash
cat > .env << 'EOF'
FLASK_SECRET_KEY=dev-secret-change-me
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=shopiq_db
DB_USER=shopiq_app
DB_PASSWORD=Ch@ng3MeStr0ng!
LLM_BASE_URL=http://YOUR_VM_IP:11434/api/chat
LLM_MODEL=llama3.1:8b
EOF
```

### Add the second Mac's IP to the NSG

**Why:** The Azure NSG AllowOllama rule only permits specific IPs. The second Mac has a different public IP and will be blocked until added.

Run this from either Mac (with Azure CLI configured):
```bash
az network nsg rule update \
  --resource-group "$RG" \
  --nsg-name       "$NSG" \
  --name           "AllowOllama" \
  --source-address-prefixes "FIRST_MAC_IP/32" "SECOND_MAC_IP/32"

az network nsg rule update \
  --resource-group "$RG" \
  --nsg-name       "$NSG" \
  --name           "AllowSSH" \
  --source-address-prefixes "FIRST_MAC_IP/32" "SECOND_MAC_IP/32"
```

### Run Flask on second Mac
```bash
flask --app app run --port 5001
```

---

## 18. Cost Management — Stop and Start the VM

**Why:** Azure charges for compute by the hour only when the VM is running. "Stopping" from inside the OS (shutdown command) is a trap — Azure still charges because hardware remains reserved. You must **deallocate** through Azure CLI to stop compute billing. The disk (~$5–10/month) is the only charge when deallocated.

| VM State | How to achieve | Compute cost | Disk cost |
|---|---|---|---|
| Running | Normal | $0.192/hr | Yes |
| OS stopped | `sudo shutdown` | **Still charged** | Yes |
| Deallocated | `az vm deallocate` | **$0.00** | Yes (~$5/mo) |

### Deallocate after a demo
```bash
az vm deallocate \
  --resource-group "rg-shopiq-poc" \
  --name "vm-shopiq-llm"
```

### Confirm deallocated (compute billing stopped)
```bash
az vm show \
  --resource-group "rg-shopiq-poc" \
  --name "vm-shopiq-llm" \
  --show-details \
  --query "{state:powerState, ip:publicIps}" \
  -o table
```

Expected: `VM deallocated` with blank IP.

### Start before next demo
```bash
az vm start \
  --resource-group "rg-shopiq-poc" \
  --name "vm-shopiq-llm"
```

### Get the new public IP (it changes every time)
```bash
VM_IP=$(az vm show \
  --resource-group "rg-shopiq-poc" \
  --name "vm-shopiq-llm" \
  --show-details \
  --query publicIps -o tsv)

echo "New IP: $VM_IP"
```

### Update .env on each Mac with the new IP
```bash
sed -i '' "s|LLM_BASE_URL=http://.*:11434|LLM_BASE_URL=http://${VM_IP}:11434|" .env
grep LLM_BASE_URL .env
```

### Update NSG rules if your home IP also changed
```bash
MY_IP=$(curl -4 -s https://api.ipify.org)

az network nsg rule update \
  --resource-group "rg-shopiq-poc" \
  --nsg-name "nsg-shopiq" \
  --name "AllowSSH" \
  --source-address-prefixes "$MY_IP/32"

az network nsg rule update \
  --resource-group "rg-shopiq-poc" \
  --nsg-name "nsg-shopiq" \
  --name "AllowOllama" \
  --source-address-prefixes "$MY_IP/32"
```

---

## 19. Demo Day Scripts

**Why:** The startup sequence has 6 steps and easy to get wrong under pressure. These scripts automate everything so demo day is a single command.

### Create demo-start.sh
```bash
cat > ~/demo-start.sh << 'SCRIPT'
#!/bin/bash
set -e

RG="rg-shopiq-poc"
VM="vm-shopiq-llm"
NSG="nsg-shopiq"
APP_DIR="$HOME/Development/azure_custom_llm"
MAC1_IP="73.73.58.60"       # update if Mac 1 IP changes
MAC2_IP="165.1.205.72"      # update if Mac 2 IP changes

echo "==> Starting VM..."
az vm start --resource-group "$RG" --name "$VM"

echo "==> Getting new IP..."
VM_IP=$(az vm show --resource-group "$RG" --name "$VM" \
  --show-details --query publicIps -o tsv)
echo "VM IP: $VM_IP"

echo "==> Updating NSG rules..."
MY_IP=$(curl -4 -s https://api.ipify.org)
az network nsg rule update --resource-group "$RG" \
  --nsg-name "$NSG" --name "AllowSSH" \
  --source-address-prefixes "$MAC1_IP/32" "$MAC2_IP/32"
az network nsg rule update --resource-group "$RG" \
  --nsg-name "$NSG" --name "AllowOllama" \
  --source-address-prefixes "$MAC1_IP/32" "$MAC2_IP/32"

echo "==> Updating .env..."
sed -i '' "s|LLM_BASE_URL=http://.*:11434|LLM_BASE_URL=http://${VM_IP}:11434|" \
  "$APP_DIR/.env"
grep LLM_BASE_URL "$APP_DIR/.env"

echo "==> Warming up Ollama (loads model into RAM)..."
curl -s http://${VM_IP}:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{"model":"llama3.1:8b","messages":[{"role":"user","content":"hello"}],"stream":false}' \
  > /dev/null && echo "Ollama ready."

echo ""
echo "==> Done. Start the app with:"
echo "    cd $APP_DIR && source .venv/bin/activate && flask --app app run --port 5001"
SCRIPT

chmod +x ~/demo-start.sh
```

### Create demo-stop.sh
```bash
cat > ~/demo-stop.sh << 'SCRIPT'
#!/bin/bash
echo "==> Deallocating VM — compute billing stops in ~2 minutes..."
az vm deallocate \
  --resource-group "rg-shopiq-poc" \
  --name "vm-shopiq-llm"
echo "==> Done. Disk preserved. No compute charges until next start."
SCRIPT

chmod +x ~/demo-stop.sh
```

### Demo day workflow
```bash
~/demo-start.sh     # start VM, update IP, warm up Ollama (~3 min)

cd ~/Development/azure_custom_llm
source .venv/bin/activate
flask --app app run --port 5001

# ... run your demo ...

~/demo-stop.sh      # deallocate VM, stop billing
```

---

## 20. Troubleshooting Reference

| Symptom | Root Cause | Fix |
|---|---|---|
| NSG rule fails with `InvalidAddressPrefix` | IPv6 address returned by `ifconfig.me` | Use `curl -4 -s https://api.ipify.org` |
| `QuotaExceeded` on `az vm create` | Zero quota for that VM family | Run quota check, use `Standard_D4s_v3` instead |
| SSH hangs silently | `$VM_IP` variable is empty | Re-run `VM_IP=$(az vm show ... --query publicIps -o tsv)` |
| `Can't connect to MySQL on 'ng3MeStr0ng!@127.0.0.1'` | `@` in password breaks URL parsing | Use `quote_plus()` for DB password in `app.py`, or use a password without special characters |
| `TemplateNotFound: index.html` | `index.html` is in project root, not `templates/` | `mkdir -p templates && mv index.html templates/` |
| `Address already in use` on port 5000 | macOS AirPlay Receiver | Run on port 5001: `flask --app app run --port 5001` |
| LLM timeout (60s) | CPU inference is slow; model cold-loading | Increase timeout to 300s in `app.py`; warm up Ollama first |
| `AI service temporarily unavailable` | VM deallocated, wrong IP in `.env`, or NSG blocking | Start VM, get new IP, update `.env`, check NSG rules |
| `pip` hits system Python despite venv active | Shell alias `pip → pip3.x` | Always use `python3 -m pip install` instead of `pip` |
| Second Mac blocked from Ollama | NSG only allows first Mac's IP | Update AllowOllama rule to include both IPs |
| Variables empty after new terminal | Shell variables are session-scoped | Re-paste the variables block from section 1 |

---

## Cost Summary

| Scenario | Monthly Cost |
|---|---|
| PoC — 10 × 2hr demos | ~$72 compute + ~$10 disk = **~$82** |
| Development — 8hr/day weekdays | ~$576 compute + ~$10 disk = **~$586** |
| Left running 24/7 | ~$2,592 compute + ~$10 disk = **~$2,602** |
| Idle — deallocated between demos | $0 compute + ~$10 disk = **~$10** |

> **Always deallocate after demos.** Running `~/demo-stop.sh` immediately after each session keeps monthly costs under $100 for a PoC used weekly.

---

## Security Notes

- Port 11434 (Ollama) and port 22 (SSH) are locked to specific IP addresses via NSG rules — not open to the internet
- The `.env` file is gitignored — credentials never enter the repository
- `shopiq_app` DB user has no DDL rights — cannot drop or alter tables
- Ollama makes no outbound calls during inference — model weights are local files
- No customer data or prompts reach any public AI service