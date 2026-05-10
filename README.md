# ShopIQ — Private LLM Customer Service Chatbot

> **A production-quality PoC that acid-tests private AI on Azure infrastructure.**  
> All LLM inference happens inside your Azure VNET. No customer data reaches any public cloud AI service.

---

## What This Is

ShopIQ is a customer service chatbot for an e-commerce platform where the AI model runs **entirely on a VM you control inside a private Azure VNET**. It demonstrates that an enterprise can deliver a meaningful GenAI customer experience without surrendering data sovereignty to a public LLM API.

The stack deliberately avoids over-engineering: plain Python Flask, standard MySQL 8, and Ollama running Llama 3.1 — no LangChain, no vector stores, no managed AI services.

---

## Architecture

```
Browser / Internal Client
        │
        ▼  HTTP (port 80, VNET-internal only)
    ┌────────┐
    │ Nginx  │   Reverse proxy
    └───┬────┘
        │  127.0.0.1:5000
        ▼
  ┌──────────────┐
  │  Flask App   │   Session + context assembly
  └──┬──────┬────┘
     │      │
     │      │  127.0.0.1:11434 (Ollama)
     │      ▼  or 127.0.0.1:8000 (vLLM)
     │  ┌────────────┐
     │  │  LLM Model │   Llama 3.1 8B (CPU) or larger (GPU)
     │  └────────────┘
     │
     │  127.0.0.1:3306
     ▼
 ┌───────────┐
 │  MySQL 8  │   Customers · Orders · Products · Chat audit log
 └───────────┘

All components run on the same Azure VM inside a private subnet.
NSG rules block all traffic except SSH (your IP) and HTTP (VNET CIDR).
```

---

## Repository Structure

```
shopiq-chatbot/
├── app/
│   ├── app.py                  # Flask routes, DB helpers, LLM client
│   ├── requirements.txt        # Pinned Python dependencies
│   ├── .env.example            # Copy to .env and fill in secrets
│   ├── templates/
│   │   └── index.html          # Bootstrap 5 dark-mode chat UI
│   └── static/css/
│       └── chat.css            # Chat bubble + typing indicator styles
├── db/
│   ├── 01_schema.sql           # DBA-owned DDL (no app-level schema privs)
│   └── 02_seed.sql             # 5 customers, 10 products, 7 orders, returns
└── docs/
    ├── GUIDE.md                # Full step-by-step build guide
    └── shopiq.service          # systemd unit for Gunicorn
```

---

## Quick Start (full steps in `docs/GUIDE.md`)

```bash
# 1. Azure infra
az group create --name rg-shopiq-poc --location eastus
# (see GUIDE.md §2 for VNET + NSG + VM creation)

# 2. On the VM — install dependencies
sudo apt update && sudo apt install -y mysql-server nginx python3.11-venv

# 3. MySQL — run as DBA user
mysql -u shopiq_dba -p shopiq_db < db/01_schema.sql
mysql -u shopiq_dba -p shopiq_db < db/02_seed.sql

# 4. Install Ollama + pull model
curl -fsSL https://ollama.com/install.sh | sh
ollama pull llama3.1:8b

# 5. Deploy Flask app
python3.11 -m venv venv && venv/bin/pip install -r app/requirements.txt
cp app/.env.example app/.env   # edit with your credentials

# 6. Register & start services
sudo cp docs/shopiq.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now shopiq

# 7. Test
curl http://localhost/health
```

---

## Database Schema (Summary)

| Table | Purpose |
|---|---|
| `customers` | Email, loyalty tier (BRONZE → PLATINUM) |
| `categories` | Self-referencing category tree |
| `products` | SKU, price, stock qty, active flag |
| `orders` | Status enum, totals, tracking info |
| `order_items` | Line items with captured unit price |
| `returns` | Return lifecycle + refund tracking |
| `chat_sessions` | Session-to-customer binding |
| `chat_messages` | Full audit log of every turn |

The app user (`shopiq_app`) has `SELECT, INSERT, UPDATE` only — **no DDL**.  
All schema changes go through the DBA user (`shopiq_dba`).

---

## Chatbot Capabilities

| User Intent | How It Works |
|---|---|
| "Where is my order?" | DB query → orders for identified customer → context injected into LLM prompt |
| "What laptops are in stock?" | Keyword detection → product search → LLM summarises results |
| "How do I return something?" | No DB lookup needed — LLM answers from system prompt policy |
| "I want a refund" | LLM guides through return process; agents can escalate manually |

The app uses **retrieval-augmented prompting** (not RAG with embeddings). Live DB rows are serialised to JSON and injected as context alongside the user's message. Simple, deterministic, auditable.

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `FLASK_SECRET_KEY` | *(required)* | Flask session signing key |
| `DB_HOST` | `127.0.0.1` | MySQL host |
| `DB_PORT` | `3306` | MySQL port |
| `DB_NAME` | `shopiq_db` | Database name |
| `DB_USER` | `shopiq_app` | App DB user |
| `DB_PASSWORD` | *(required)* | App DB password |
| `LLM_BASE_URL` | `http://localhost:11434/api/chat` | Ollama or vLLM endpoint |
| `LLM_MODEL` | `llama3.1:8b` | Model identifier |

---

## Switching to vLLM (GPU)

If you provision `Standard_NC24ads_A100_v4`:

```bash
docker run -d --gpus all -p 8000:8000 \
  vllm/vllm-openai:latest \
  --model meta-llama/Meta-Llama-3.1-8B-Instruct

# Update .env
LLM_BASE_URL=http://localhost:8000/v1/chat/completions
LLM_MODEL=meta-llama/Meta-Llama-3.1-8B-Instruct
```

vLLM delivers 5–10× higher throughput under concurrent load vs Ollama.  
See `docs/GUIDE.md §12` for the full GPU setup walkthrough.

---

## Sample Seed Data

| Customer | Email | Tier | Notable Orders |
|---|---|---|---|
| Alice Walker | alice.walker@example.com | GOLD | ProBook Laptop (delivered), Headphones (shipped) |
| Bob Martinez | bob.martinez@example.com | SILVER | Galaxy S25 (processing) |
| Carol Johnson | carol.johnson@example.com | PLATINUM | Air Fryer (delivered), UltraSlim (cancelled+refunded) |
| David Lee | david.lee@example.com | BRONZE | ErgoDesk (pending) |
| Eve Chen | eve.chen@example.com | SILVER | Shirt + Earbuds + Sweater (delivered) |

Use these emails in the "Identify" panel to test order-aware responses.

---

## Security Design

- **No public AI APIs** — LLM endpoint is `localhost` only
- **NSG-controlled access** — port 80 open to VNET CIDR only; port 22 to your IP only
- **Principle of least privilege** — app DB user has no DDL rights
- **Session isolation** — each browser session gets a UUID; history limited to last 5 turns in LLM context
- **Audit trail** — every message persisted to `chat_messages` with timestamp

---

## PoC Limitations (Honest Assessment)

- **No authentication** — any user in the VNET can access the chatbot UI
- **No HTTPS** — add Azure Application Gateway or certbot before any real use
- **Single VM** — no HA; VM restart = service interruption
- **Naive intent detection** — keyword matching, not a proper NLU pipeline
- **CPU inference** — Llama 3.1 8B on `Standard_D8s_v5` yields ~6–10 tokens/sec; acceptable for PoC, not production volume

---

## License

MIT — use freely for internal PoC and evaluation purposes.
