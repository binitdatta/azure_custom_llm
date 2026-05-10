# ShopIQ Private LLM Chatbot — Step-by-Step Build Guide

> **Audience:** Enterprise developers building an air-gapped AI chatbot PoC  
> **Stack:** Azure VM · Ubuntu 22.04 · MySQL 8 · Ollama (Llama 3.1) · Python Flask  
> **Goal:** A working customer-service chatbot where no data leaves your Azure VNET

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Azure Infrastructure — Resource Group & VNET](#2-azure-infrastructure--resource-group--vnet)
3. [Create the Linux VM](#3-create-the-linux-vm)
4. [Connect & Secure the VM](#4-connect--secure-the-vm)
5. [Install System Dependencies](#5-install-system-dependencies)
6. [Install MySQL 8 & Create the Database](#6-install-mysql-8--create-the-database)
7. [Install Ollama & Pull the LLM](#7-install-ollama--pull-the-llm)
8. [Deploy the Flask Application](#8-deploy-the-flask-application)
9. [Configure Nginx as a Reverse Proxy](#9-configure-nginx-as-a-reverse-proxy)
10. [Register as a systemd Service](#10-register-as-a-systemd-service)
11. [Smoke Test the Full Stack](#11-smoke-test-the-full-stack)
12. [vLLM Alternative (GPU VM)](#12-vllm-alternative-gpu-vm)
13. [Troubleshooting](#13-troubleshooting)
14. [Project File Reference](#14-project-file-reference)

---

## 1. Prerequisites

| Item | Detail |
|---|---|
| Azure subscription | Contributor rights on target subscription |
| Azure CLI | `az --version` ≥ 2.60 installed locally |
| SSH key pair | `~/.ssh/id_rsa` + `id_rsa.pub` present |
| MySQL Workbench | Optional but helpful for DBA verification |
| Git | To clone/transfer project files |

**Install Azure CLI on macOS (if needed):**
```bash
brew update && brew install azure-cli
az login
```

---

## 2. Azure Infrastructure — Resource Group & VNET

All commands run from your **local Mac terminal** unless noted.

### 2.1 Set variables (edit these to match your context)
```bash
RESOURCE_GROUP="rg-shopiq-poc"
LOCATION="eastus"
VNET_NAME="vnet-shopiq"
SUBNET_NAME="snet-shopiq"
NSG_NAME="nsg-shopiq"
VM_NAME="vm-shopiq-llm"
VM_SIZE="Standard_D8s_v5"        # 8 vCPU, 32 GB RAM — CPU-only Ollama
# VM_SIZE="Standard_NC24ads_A100_v4"  # uncomment for GPU / vLLM
ADMIN_USER="azureuser"
SSH_KEY_PATH="~/.ssh/id_rsa.pub"
```

### 2.2 Create Resource Group
```bash
az group create \
  --name  "$RESOURCE_GROUP" \
  --location "$LOCATION"
```

### 2.3 Create VNET + Subnet
```bash
az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --name           "$VNET_NAME" \
  --address-prefix 10.10.0.0/16 \
  --subnet-name    "$SUBNET_NAME" \
  --subnet-prefix  10.10.1.0/24
```

### 2.4 Create Network Security Group
```bash
az network nsg create \
  --resource-group "$RESOURCE_GROUP" \
  --name           "$NSG_NAME"
```

**Allow SSH (port 22) — from your IP only:**
```bash
MY_IP=$(curl -s https://ifconfig.me)

az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name       "$NSG_NAME" \
  --name           "AllowSSH" \
  --priority       100 \
  --protocol       Tcp \
  --destination-port-ranges 22 \
  --source-address-prefixes "$MY_IP/32" \
  --access          Allow \
  --direction       Inbound
```

**Allow HTTP on port 80 (within VNET only):**
```bash
az network nsg rule create \
  --resource-group "$RESOURCE_GROUP" \
  --nsg-name       "$NSG_NAME" \
  --name           "AllowHTTPInternalOnly" \
  --priority       110 \
  --protocol       Tcp \
  --destination-port-ranges 80 \
  --source-address-prefixes 10.10.0.0/16 \
  --access          Allow \
  --direction       Inbound
```

> **Note:** Port 80 is VNET-internal only. Ollama (11434) and Flask (5000) are  
> never exposed directly — they sit behind Nginx and NSG rules.

### 2.5 Associate NSG with subnet
```bash
az network vnet subnet update \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name      "$VNET_NAME" \
  --name           "$SUBNET_NAME" \
  --network-security-group "$NSG_NAME"
```

---

## 3. Create the Linux VM

```bash
az vm create \
  --resource-group        "$RESOURCE_GROUP" \
  --name                  "$VM_NAME" \
  --size                  "$VM_SIZE" \
  --image                 Ubuntu2204 \
  --vnet-name             "$VNET_NAME" \
  --subnet                "$SUBNET_NAME" \
  --nsg                   "$NSG_NAME" \
  --admin-username        "$ADMIN_USER" \
  --ssh-key-values        "$SSH_KEY_PATH" \
  --public-ip-sku         Standard \
  --os-disk-size-gb       128 \
  --storage-sku           Premium_LRS
```

**Capture the public IP output:**
```bash
VM_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name           "$VM_NAME" \
  --show-details   \
  --query publicIps -o tsv)

echo "VM IP: $VM_IP"
```

> **PoC note:** A public IP is used here for SSH access during the PoC.  
> In production, replace with Azure Bastion and remove the public IP entirely.

---

## 4. Connect & Secure the VM

```bash
ssh -i ~/.ssh/id_rsa "$ADMIN_USER@$VM_IP"
```

All remaining commands run **inside the VM** unless noted.

### 4.1 Update the system
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl wget git unzip net-tools
```

### 4.2 Create an application user
```bash
sudo useradd -m -s /bin/bash shopiq
sudo usermod -aG sudo shopiq
```

### 4.3 Configure UFW firewall
```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw enable
sudo ufw status
```

---

## 5. Install System Dependencies

### 5.1 Python 3.11
```bash
sudo apt install -y python3.11 python3.11-venv python3-pip
python3.11 --version    # should print 3.11.x
```

### 5.2 Nginx
```bash
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

---

## 6. Install MySQL 8 & Create the Database

### 6.1 Install MySQL Server
```bash
sudo apt install -y mysql-server
sudo systemctl enable mysql
sudo systemctl start mysql
```

### 6.2 Secure the installation
```bash
sudo mysql_secure_installation
# Accept: validate password plugin → STRONG
# Set root password → save it securely
# Remove anonymous users → Y
# Disallow root remote login → Y
# Remove test database → Y
# Reload privilege tables → Y
```

### 6.3 Create database, DBA user, and app user
```bash
sudo mysql -u root -p
```

Inside MySQL shell:
```sql
-- Create database
CREATE DATABASE shopiq_db
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Application user (SELECT + INSERT + UPDATE only — no DDL)
CREATE USER 'shopiq_app'@'127.0.0.1'
  IDENTIFIED BY 'Ch@ng3MeStr0ng!';

GRANT SELECT, INSERT, UPDATE
  ON shopiq_db.*
  TO 'shopiq_app'@'127.0.0.1';

-- Optional: separate DBA user for schema work
CREATE USER 'shopiq_dba'@'127.0.0.1'
  IDENTIFIED BY 'DB@AdminP@ss!';

GRANT ALL PRIVILEGES ON shopiq_db.*
  TO 'shopiq_dba'@'127.0.0.1';

FLUSH PRIVILEGES;
EXIT;
```

### 6.4 Run schema DDL (as DBA user)
Copy `db/01_schema.sql` and `db/02_seed.sql` to the VM, then:
```bash
mysql -u shopiq_dba -p shopiq_db < /tmp/01_schema.sql
mysql -u shopiq_dba -p shopiq_db < /tmp/02_seed.sql
```

**Verify:**
```bash
mysql -u shopiq_app -p -h 127.0.0.1 shopiq_db \
  -e "SELECT customer_id, first_name, loyalty_tier FROM customers;"
```

Expected output — 5 rows with Alice, Bob, Carol, David, Eve.

---

## 7. Install Ollama & Pull the LLM

### 7.1 Install Ollama
```bash
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl enable ollama
sudo systemctl start ollama
```

### 7.2 Pull Llama 3.1 8B (quantized — fits in 8–10 GB RAM)
```bash
ollama pull llama3.1:8b
```

> This downloads ~4.7 GB. On a freshly provisioned VM with decent network,  
> expect 3–8 minutes. Coffee time.

### 7.3 Verify the model
```bash
ollama run llama3.1:8b "Say hello in one sentence."
```

You should see a response within a few seconds. Press `Ctrl+D` to exit.

### 7.4 Test the REST API
```bash
curl http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "messages": [{"role":"user","content":"What is 2+2?"}],
    "stream": false
  }'
```

Expected: JSON with `message.content` containing "4".

> **Ollama is bound to localhost only.** It is not reachable from outside the VM.  
> The Flask app calls it over `127.0.0.1:11434` — never via a public interface.

---

## 8. Deploy the Flask Application

### 8.1 Copy project files to the VM
From your **local Mac**:
```bash
scp -r ./shopiq-chatbot "$ADMIN_USER@$VM_IP:/tmp/"
```

Back **inside the VM**:
```bash
sudo mv /tmp/shopiq-chatbot /opt/shopiq-chatbot
sudo chown -R shopiq:shopiq /opt/shopiq-chatbot
```

### 8.2 Create Python virtual environment
```bash
sudo -u shopiq bash -c "
  python3.11 -m venv /opt/shopiq-chatbot/venv &&
  /opt/shopiq-chatbot/venv/bin/pip install --upgrade pip &&
  /opt/shopiq-chatbot/venv/bin/pip install \
    -r /opt/shopiq-chatbot/app/requirements.txt
"
```

### 8.3 Configure environment variables
```bash
sudo cp /opt/shopiq-chatbot/app/.env.example \
        /opt/shopiq-chatbot/app/.env

sudo nano /opt/shopiq-chatbot/app/.env
```

Edit these values:
```dotenv
FLASK_SECRET_KEY=<generate with: python3 -c "import secrets; print(secrets.token_hex(32))">
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=shopiq_db
DB_USER=shopiq_app
DB_PASSWORD=Ch@ng3MeStr0ng!
LLM_BASE_URL=http://localhost:11434/api/chat
LLM_MODEL=llama3.1:8b
```

```bash
sudo chown shopiq:shopiq /opt/shopiq-chatbot/app/.env
sudo chmod 600           /opt/shopiq-chatbot/app/.env
```

### 8.4 Quick smoke test (run as shopiq user)
```bash
sudo -u shopiq bash -c "
  cd /opt/shopiq-chatbot/app &&
  source /opt/shopiq-chatbot/venv/bin/activate &&
  python app.py &
"
sleep 3
curl http://localhost:5000/health
# Expected: {"model":"llama3.1:8b","status":"ok","timestamp":"..."}
kill %1   # stop the test process
```

---

## 9. Configure Nginx as a Reverse Proxy

```bash
sudo nano /etc/nginx/sites-available/shopiq
```

Paste:
```nginx
server {
    listen 80;
    server_name _;          # Matches any hostname; use VM IP or hostname

    client_max_body_size 4M;

    location / {
        proxy_pass          http://127.0.0.1:5000;
        proxy_set_header    Host              $host;
        proxy_set_header    X-Real-IP         $remote_addr;
        proxy_set_header    X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_read_timeout  120s;
        proxy_send_timeout  120s;
    }

    # Static files served directly by Nginx (faster)
    location /static/ {
        alias /opt/shopiq-chatbot/app/static/;
        expires 1d;
    }
}
```

Enable and reload:
```bash
sudo ln -s /etc/nginx/sites-available/shopiq \
           /etc/nginx/sites-enabled/shopiq
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t       # must say "syntax is ok"
sudo systemctl reload nginx
```

---

## 10. Register as a systemd Service

### 10.1 Create log directory
```bash
sudo mkdir -p /var/log/shopiq
sudo chown shopiq:shopiq /var/log/shopiq
```

### 10.2 Install the service unit
```bash
sudo cp /opt/shopiq-chatbot/docs/shopiq.service \
        /etc/systemd/system/shopiq.service

sudo systemctl daemon-reload
sudo systemctl enable shopiq
sudo systemctl start shopiq
sudo systemctl status shopiq
```

Expected output: `Active: active (running)`.

### 10.3 Verify logs
```bash
sudo journalctl -u shopiq -f --no-pager
# Ctrl+C to exit
```

---

## 11. Smoke Test the Full Stack

### 11.1 Health endpoint
```bash
curl http://localhost/health
```

### 11.2 Chat API
```bash
curl -X POST http://localhost/api/chat \
  -H "Content-Type: application/json" \
  -c cookies.txt -b cookies.txt \
  -d '{"message": "What laptops do you have in stock?"}'
```

Expected: JSON with `reply` containing laptop product details from the DB.

### 11.3 Customer identification
```bash
curl -X POST http://localhost/api/identify \
  -H "Content-Type: application/json" \
  -c cookies.txt -b cookies.txt \
  -d '{"email": "alice.walker@example.com"}'
```

Expected: `{"found": true, "name": "Alice Walker", "tier": "GOLD"}`

### 11.4 Order-aware query (after identify)
```bash
curl -X POST http://localhost/api/chat \
  -H "Content-Type: application/json" \
  -c cookies.txt -b cookies.txt \
  -d '{"message": "Where is my latest order?"}'
```

Expected: The assistant should reference Alice's most recent shipped order  
with the FedEx tracking number from the seed data.

### 11.5 Browser test
From a machine inside the VNET (or via SSH tunnel):
```bash
# SSH tunnel from local Mac:
ssh -L 8080:localhost:80 "$ADMIN_USER@$VM_IP"
```
Then open: `http://localhost:8080` in your browser.

---

## 12. vLLM Alternative (GPU VM)

Use this section if you provisioned `Standard_NC24ads_A100_v4`.

### 12.1 Install NVIDIA drivers
```bash
sudo apt install -y ubuntu-drivers-common
sudo ubuntu-drivers autoinstall
sudo reboot
# Wait ~2 min, then reconnect
nvidia-smi   # verify GPU is visible
```

### 12.2 Install Docker
```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
newgrp docker
```

### 12.3 Install NVIDIA Container Toolkit
```bash
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update && sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### 12.4 Run vLLM
```bash
docker run -d \
  --gpus all \
  --name vllm-server \
  -p 8000:8000 \
  -v ~/.cache/huggingface:/root/.cache/huggingface \
  -e HF_TOKEN="<your_huggingface_token>" \
  vllm/vllm-openai:latest \
  --model meta-llama/Meta-Llama-3.1-8B-Instruct \
  --host 0.0.0.0 \
  --port 8000

# Tail startup logs (model load takes ~60 sec)
docker logs -f vllm-server
```

### 12.5 Switch Flask to vLLM endpoint
Edit `/opt/shopiq-chatbot/app/.env`:
```dotenv
LLM_BASE_URL=http://localhost:8000/v1/chat/completions
LLM_MODEL=meta-llama/Meta-Llama-3.1-8B-Instruct
```

**Also update `app.py`** — vLLM uses the OpenAI API format, so the payload
changes slightly. Replace the `call_llm` function body:
```python
payload = {
    "model": LLM_MODEL,
    "messages": messages,
    "max_tokens": 512,
    "temperature": 0.7
}
resp = requests.post(LLM_URL, json=payload, timeout=60)
resp.raise_for_status()
data = resp.json()
return data["choices"][0]["message"]["content"]
```

Then restart:
```bash
sudo systemctl restart shopiq
```

---

## 13. Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `curl: (7) Failed to connect to localhost:11434` | Ollama not running | `sudo systemctl start ollama` |
| `OperationalError: (pymysql.err.OperationalError)` | Wrong DB creds in `.env` | Re-check `DB_PASSWORD` matches MySQL grant |
| LLM response times > 30s | Insufficient RAM; model swapping to disk | Upgrade VM size or use a smaller model (`llama3.2:3b`) |
| `502 Bad Gateway` from Nginx | Flask/Gunicorn not running | `sudo systemctl status shopiq`, check `/var/log/shopiq/error.log` |
| Chat returns generic error | LLM API timeout | Increase `proxy_read_timeout` in Nginx config |
| GPU not visible in vLLM | Drivers not loaded after reboot | `nvidia-smi`; if blank, reinstall drivers |
| `ModuleNotFoundError` on startup | venv not activated in service | Confirm `ExecStart` path points to venv Python |

---

## 14. Project File Reference

```
shopiq-chatbot/
├── app/
│   ├── app.py                  # Flask application
│   ├── requirements.txt        # Python dependencies
│   ├── .env.example            # Environment variable template
│   ├── templates/
│   │   └── index.html          # Bootstrap 5 dark chat UI
│   └── static/
│       └── css/
│           └── chat.css        # Chat bubble styles
├── db/
│   ├── 01_schema.sql           # DBA DDL — tables, constraints, indexes
│   └── 02_seed.sql             # Sample customers, products, orders
└── docs/
    ├── shopiq.service          # systemd unit file
    └── GUIDE.md                # This document
```

---

## Security Notes for PoC → Production Promotion

Before moving beyond PoC:

1. **Remove the public IP** — use Azure Bastion for SSH access.
2. **Enable HTTPS** — use Azure Application Gateway or cert-bot + Let's Encrypt if accessible.
3. **Secrets management** — move `.env` secrets to Azure Key Vault.
4. **DB hardening** — restrict `shopiq_app` to specific stored procedures; audit the `chat_messages` table regularly.
5. **Ollama binding** — Ollama listens on all interfaces by default after recent versions; confirm `OLLAMA_HOST=127.0.0.1` is set.
6. **Model updates** — treat model weight files like patches; establish a pull + test + restart workflow.
7. **Rate limiting** — add Nginx `limit_req_zone` to prevent abuse of the chat endpoint.
