# Azure AI Foundry — Llama 3.3 70B Setup Guide
### Step-by-Step with Every Click Documented

> **What this guide does:** Walks you through creating an Azure AI Foundry project,
> deploying Llama 3.3 70B as a serverless API endpoint (pay-per-token, no GPU quota needed),
> and wiring it into your ShopIQ Flask chatbot.
>
> **Cost:** $0 to set up. $0 idle. You only pay when tokens are processed (~$0.005 per chat turn).
>
> **Time:** ~10 minutes end to end.

---

## Table of Contents

1. [Navigate to Azure AI Foundry](#1-navigate-to-azure-ai-foundry)
2. [Sign In](#2-sign-in)
3. [Create a Project](#3-create-a-project)
4. [Close the Welcome Tour](#4-close-the-welcome-tour)
5. [Navigate to the Model Catalog](#5-navigate-to-the-model-catalog)
6. [Filter by Meta Models](#6-filter-by-meta-models)
7. [Select Llama 3.3 70B Instruct](#7-select-llama-33-70b-instruct)
8. [Deploy the Model](#8-deploy-the-model)
9. [Copy Your Endpoint and API Key](#9-copy-your-endpoint-and-api-key)
10. [Update Your .env File](#10-update-your-env-file)
11. [Update app.py for SSL and Foundry Format](#11-update-apppy-for-ssl-and-foundry-format)
12. [Verify the Connection](#12-verify-the-connection)
13. [Restart Flask and Test End-to-End](#13-restart-flask-and-test-end-to-end)
14. [Switching Between Providers](#14-switching-between-providers)
15. [Cost Monitoring](#15-cost-monitoring)
16. [Troubleshooting](#16-troubleshooting)

---

## 1. Navigate to Azure AI Foundry

**Why:** Azure AI Foundry is Microsoft's unified platform for deploying and managing
AI models. The Llama 3.3 70B serverless endpoint lives here — no GPU quota required,
no VM to manage.

Open your browser and go to:
```
https://ai.azure.com
```

You will land on the Microsoft Foundry home page showing:
- "Create smarter agents with Microsoft Foundry" headline
- A model deployment preview panel on the right
- "Start building →" button top right
- Top navigation: **Home | Discover | Build | Operate | Docs**

---

## 2. Sign In

**Why:** You must be signed in with the same Azure account that holds your
subscription (`Azure subscription 1`) — the same one used to create the VM.

**Where to click:**
- If not signed in, a sign-in prompt appears automatically
- Use your Microsoft/Azure account credentials
- Complete MFA if prompted

**Confirm you are signed in:**
- Your account avatar/initials appear in the top-right corner of the page
- The URL changes to include your tenant ID:
  `https://ai.azure.com/?tid=ac914e49-0b67-4d0a-9860-031216abd11c`

---

## 3. Create a Project

**Why:** A Foundry Project is the container for your model deployments, API keys,
and endpoints. All resources — including the Llama 3.3 70B endpoint — live inside
a project. Creating a project also provisions the underlying Azure resource group
and Foundry resource automatically.

**Where to click:**
- Click **"Start building →"** (purple button, top right of the home page)
  OR
- Click **"Create an agent"** (blue button, centre of the home page)

**The "Create a project" dialog appears:**

| Field | What to enter | Why |
|---|---|---|
| **Project** | `shopiq-llm-poc` | Name your project — lowercase, hyphens only |
| **Microsoft Foundry resource** | `shopiq-llm-poc-resource` | Auto-filled — the Azure resource name |
| **Subscription** | `Azure subscription 1` | Your existing subscription |
| **Resource group** | `(new) rg-shopiq-llm-poc` | New RG separate from your VM's RG |
| **Region** | `East US 2` | **Important:** Llama 3.3 70B serverless is available here |
| **Public network access** | `Enabled` | Required for your Mac to call the endpoint |

> **Region matters:** Llama 3.3 70B serverless API is available in East US 2.
> Do not change this to match your VM region if the VM is in East US — East US 2
> is the correct region for this deployment.

**Click the blue "Create" button** (bottom right of the dialog).

**What happens next:**
- A provisioning spinner appears for ~90 seconds
- Azure creates: resource group, Foundry hub, Foundry project, storage account
- You are automatically redirected into the project dashboard

---

## 4. Close the Welcome Tour

**Why:** The new Microsoft Foundry UI shows a three-step welcome tour on first
entry. Close it to reach the project dashboard.

**Where to click:**
- A dialog titled **"Welcome to the new Microsoft Foundry"** appears over the dashboard
- Click the **X circle button** in the top-right corner of the dialog box
- The dialog closes revealing the project home page

**You are now on the project dashboard showing:**
- Your project name `shopiq-llm-poc` in the breadcrumb (top left)
- Top navigation: **Home | Discover | Build | Operate | Docs**
- Three cards: **Create agents | Explore playgrounds | Find models**
- **API key** (masked) and **Project endpoint** URL already shown at the top

> **Save these for later:** The API key and Project endpoint shown on this home
> page are your project-level credentials. You will get model-specific credentials
> from the deployment details page in step 9.

---

## 5. Navigate to the Model Catalog

**Why:** The model catalog is where you find, evaluate, and deploy all available
models including Llama 3.3 70B. It is under the Discover tab in the new Foundry UI.

**Option A — Click "Find models" card:**
- On the project home page, click the **"Find models"** card (rightmost of the three cards)
- Subtitle: "Explore a rich set of models to find the right fit for your work."

**Option B — Click Discover in top nav:**
- Click **"Discover"** in the top navigation bar
- In the left sidebar that appears, click **"Models"**

**You land on the Models page showing:**
- `Models (42)` heading (number may vary)
- A search box
- Filter options on the left: Collections, Fine-tuning methods, Source, Capabilities, Inference tasks, Industry
- Featured model cards including GPT-4o, Claude models, etc.
- **"Explore models from popular providers"** section with logos: Azure OpenAI, Anthropic, Microsoft, **Meta**, Mistral AI, DeepSeek

---

## 6. Filter by Meta Models

**Why:** Filtering by Meta shows only Meta's Llama family, making it easy to find
Llama 3.3 70B without scrolling through 42+ models.

**Where to click:**
- In the **"Explore models from popular providers"** section, click the **"Meta"** logo/button
- The URL changes to: `...discover/models?source=meta`
- The model list filters to show `Models (42)` all from Meta
- You can see `Llama-3.3-70B-Instruct` in the second column, second row

---

## 7. Select Llama 3.3 70B Instruct

**Why:** Llama 3.3 70B Instruct is the instruction-tuned version — optimised for
dialogue and Q&A tasks. It significantly outperforms Llama 3.1 8B on reasoning,
instruction following, and multilingual tasks. It is "Direct from Azure" meaning
Microsoft manages and supports it directly with no third-party dependencies.

**Where to click:**
- Find **"Llama-3.3-70B-Instruct"** in the model grid
  - It shows: `Chat completion` underneath, Meta logo, **no external link icon**
  - The absence of the external link icon (↗) confirms it is natively hosted by Azure
- Click the model card

**The model detail page opens showing:**
- **Title:** `Llama-3.3-70B-Instruct`
- **Badge:** `Meta` · `Direct from Azure` · `Version: 9`
- **Lifecycle:** Preview
- **Context:** 128k input / 8192 output tokens
- **Pricing:** "View pricing" link
- **Benchmark table** comparing Llama 3.1 8B vs 3.1 70B vs **3.3 70B** vs 3.1 405B
  - Note: Llama 3.3 70B matches 405B on MMLU (86.0) — strong reasoning at lower cost
- **Purple "Deploy" button** and "Fine-tune" button — top right
- **"Others who deployed this model also used"** section at the bottom right

> **Verify you have the right model:** The URL should contain `Llama-3.3-70B-Instruct`
> and the page should show `Direct from Azure` badge. If you see an external link
> icon on the model card it means it's hosted by a third party — go back and find
> the native Azure version.

---

## 8. Deploy the Model

**Why:** Deploying creates a live serverless API endpoint backed by Microsoft's GPU
infrastructure. You pay per token only when the endpoint receives requests. No GPU
quota is required in your subscription — Microsoft manages capacity.

**Where to click:**
- Click the purple **"Deploy"** button (top right of the model detail page)
- A small dropdown appears with two options:
  - **"Default settings"** — Global standard, default quota, pay-as-you-go
  - **"Custom settings"** — Set your own SKU, quota, PTU, spillover, guardrails

**Click "Default settings"**

**What happens:**
- Azure provisions the serverless endpoint (~2 minutes)
- You are automatically redirected to the **Playground** tab of your new deployment
- The URL changes to: `.../build/models/deployments/Llama-3.3-70B-Instruct/playground`
- The playground shows:
  - Model: `Llama-3.3-70B-Instruct` selected in dropdown
  - Instructions text area with "You are an AI assistant..."
  - Chat panel on the right with "What do you want to chat about?"
  - Left sidebar now shows: Agents, Models, Fine-tune, Tools, Knowledge, Data, Evaluations, Guardrails

**The deployment is live.** You can test it directly in the playground — type a
message in the chat box and Llama 3.3 70B will respond.

---

## 9. Copy Your Endpoint and API Key

**Why:** Your Flask app needs the Target URI (the HTTPS endpoint URL) and the API
Key to authenticate and call the model. These are unique to your deployment.

**Where to click:**
- Click the **"Details"** tab (second tab, next to "Playground" at the top of the page)
- The URL changes to: `.../build/models/deployments/Llama-3.3-70B-Instruct/details`

**The Details page shows:**

| Field | Location | What it looks like |
|---|---|---|
| **Target URI** | Top left, full-width field | `https://shopiq-llm-poc-resource.services.ai.azure.com` |
| **Key** | Top right, masked with dots | `••••••••••••••••••••••••••••••••••••••` |
| **Deployment info** | Below | Name, type, provisioning state |
| **Provisioning state** | Green dot | `Succeeded` |
| **Tokens per Minute Rate Limit** | Bottom section | `20000` |
| **Requests per Minute Rate Limit** | Bottom section | `20` |

**Copy the Target URI:**
- Click the **copy icon** (two overlapping squares) to the right of the Target URI field
- The full URL is copied: `https://shopiq-llm-poc-resource.services.ai.azure.com`

**Copy the Key:**
- Click the **eye icon** (👁) to reveal the key first
- Then click the **copy icon** to copy it
- The key is ~84 characters long

> **Important — append the path to the Target URI:**
> The Target URI from the portal is the base URL only. You must append
> `/models/chat/completions` to form the complete endpoint URL for your Flask app:
> ```
> https://shopiq-llm-poc-resource.services.ai.azure.com/models/chat/completions
> ```

**Save both values** — you will need them in the next step.

---

## 10. Update Your .env File

**Why:** The `.env` file controls which LLM provider Flask uses and holds the
credentials for both providers. The `LLM_PROVIDER` variable is the single switch
that controls routing. Changing it to `foundry` routes all LLM calls to Azure AI
Foundry instead of the Ollama VM.

**Stop Flask** (`Ctrl+C`) then open `.env` in PyCharm and replace its contents
entirely with:

```dotenv
# ── Flask ────────────────────────────────────────────────────────────────────
FLASK_SECRET_KEY=dev-secret-change-me

# ── MySQL ────────────────────────────────────────────────────────────────────
DB_HOST=127.0.0.1
DB_PORT=3306
DB_NAME=shopiq_db
DB_USER=shopiq_app
DB_PASSWORD=Ch@ng3MeStr0ng!

# ── LLM Provider Switch ───────────────────────────────────────────────────────
# Set to "foundry" for Azure AI Foundry (Llama 3.3 70B, fast, always on)
# Set to "ollama"  for Azure VM Ollama  (Llama 3.1 8B, start VM first)
LLM_PROVIDER=foundry

# ── Ollama — Azure VM ─────────────────────────────────────────────────────────
OLLAMA_BASE_URL=http://52.188.2.39:11434/api/chat
OLLAMA_MODEL=llama3.1:8b

# ── Azure AI Foundry ──────────────────────────────────────────────────────────
FOUNDRY_BASE_URL=https://shopiq-llm-poc-resource.services.ai.azure.com/models/chat/completions
FOUNDRY_MODEL=Llama-3.3-70B-Instruct
FOUNDRY_API_KEY=YOUR_84_CHARACTER_KEY_HERE
```

**Replace `YOUR_84_CHARACTER_KEY_HERE`** with the key copied from the Details page.

**Verify the file:**
```bash
cat .env | grep FOUNDRY
```

Expected output — three clean lines, no wrapping:
```
FOUNDRY_BASE_URL=https://shopiq-llm-poc-resource.services.ai.azure.com/models/chat/completions
FOUNDRY_MODEL=Llama-3.3-70B-Instruct
FOUNDRY_API_KEY=79qjb8cG....(your key)
```

---

## 11. Update app.py for SSL and Foundry Format

**Why:** Two code changes are required:
>
> 1. **SSL verification:** Corporate network proxies and some ISP configurations
>    intercept HTTPS traffic and inject their own certificates. Python's `requests`
>    library rejects these with `CERTIFICATE_VERIFY_FAILED`. Adding `verify=False`
>    bypasses certificate chain validation — the connection remains encrypted, only
>    the certificate authority check is skipped. This is acceptable for a PoC.
>
> 2. **Response format:** The Foundry endpoint uses OpenAI-compatible format
>    (`choices[0].message.content`) while Ollama uses its own format
>    (`message.content`). The two separate provider functions handle this.

Open `app.py` in PyCharm and make these two changes:

**Change 1 — Add urllib3 import** at the top of the file with the other imports:
```python
import urllib3
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
```

**Change 2 — Add `verify=False`** inside `_call_foundry()`:

Find:
```python
resp = requests.post(FOUNDRY_URL, json=payload,
                     headers=headers, timeout=60)
```

Replace with:
```python
resp = requests.post(FOUNDRY_URL, json=payload,
                     headers=headers, timeout=60,
                     verify=False)
```

Save the file.

---

## 12. Verify the Connection

**Why:** Before starting Flask, confirm Python's `requests` library can reach the
Foundry endpoint correctly. This catches any remaining issues before they appear
as cryptic Flask errors.

```bash
python3 -c "
from dotenv import load_dotenv
import os, requests, urllib3
urllib3.disable_warnings()
load_dotenv()
url   = os.getenv('FOUNDRY_BASE_URL')
key   = os.getenv('FOUNDRY_API_KEY')
model = os.getenv('FOUNDRY_MODEL')
print('Calling:', url)
resp = requests.post(url,
    headers={'Content-Type':'application/json','Authorization':f'Bearer {key}'},
    json={'model':model,'messages':[{'role':'user','content':'ping'}],'max_tokens':50},
    timeout=60, verify=False
)
print('HTTP Status:', resp.status_code)
print('Response:', resp.json()['choices'][0]['message']['content'])
"
```

**Expected output:**
```
Calling: https://shopiq-llm-poc-resource.services.ai.azure.com/models/chat/completions
HTTP Status: 200
Response: pong
```

If you see `HTTP Status: 200` and a response — the endpoint is working correctly.

**Common errors at this stage:**

| Error | Cause | Fix |
|---|---|---|
| `401 Unauthorized` | Wrong API key | Re-copy key from Foundry Details page |
| `404 Not Found` | Missing `/models/chat/completions` in URL | Check FOUNDRY_BASE_URL in .env |
| `SSLError` without verify=False | Corporate proxy | Ensure verify=False is in the request |
| `ConnectionError` | URL is wrong or network blocked | Check URL has no typos |

---

## 13. Restart Flask and Test End-to-End

**Why:** Flask reads `.env` only at startup. After updating `.env` and `app.py`,
a fresh start is required to pick up all changes.

```bash
source .venv/bin/activate
flask --app app run --port 5001
```

**Confirm the startup log shows:**
```
2026-05-10 11:53:01,435 [INFO] LLM provider: foundry | model: Llama-3.3-70B-Instruct
 * Running on http://127.0.0.1:5001
```

**Open `http://localhost:5001` in your browser.**

**Run the full end-to-end test sequence:**

**Test 1 — Customer identification (MySQL):**
- Enter `alice.walker@example.com` in the Identify panel
- Click **"Look Up"**
- Expected: Alice Walker card appears with **GOLD** tier badge
- Confirms: MySQL connection working on this Mac

**Test 2 — Order-aware query (MySQL + Foundry LLM):**
- Click **"My latest order"** quick button or type "Where is my latest order?"
- Expected within 2–5 seconds: Llama 3.3 70B reads Alice's FedEx shipment
  from MySQL and narrates the order status with real tracking number
- Confirms: Full stack working — MySQL → Flask → Foundry → response

**Test 3 — Product query:**
- Click **"Laptops in stock"**
- Expected: ProBook 15 and UltraSlim X1 details from the products table
- Confirms: Product DB queries working with Foundry LLM narration

**Test 4 — General question (LLM only, no DB):**
- Click **"Refund policy"**
- Expected: Llama answers from the system prompt — no DB query needed
- Confirms: LLM responding independently of MySQL

**Test 5 — Health endpoint:**
```bash
curl -s http://localhost:5001/health | python3 -m json.tool
```
Expected:
```json
{
    "model": "Llama-3.3-70B-Instruct",
    "provider": "foundry",
    "status": "ok",
    "timestamp": "2026-05-10T..."
}
```

---

## 14. Switching Between Providers

**Why:** You may want to compare response quality between Llama 3.1 8B (VM) and
Llama 3.3 70B (Foundry), or fall back to Ollama if Foundry is unavailable.
The `LLM_PROVIDER` variable in `.env` is the single switch.

**Switch to Ollama (Azure VM):**
```bash
# 1. Start the VM first
~/demo-start.sh

# 2. Update .env
sed -i '' 's/LLM_PROVIDER=.*/LLM_PROVIDER=ollama/' .env

# 3. Restart Flask
flask --app app run --port 5001
```

Startup log confirms: `LLM provider: ollama | model: llama3.1:8b`

**Switch to Foundry (Azure AI):**
```bash
# No VM needed — Foundry is always on

# 1. Update .env
sed -i '' 's/LLM_PROVIDER=.*/LLM_PROVIDER=foundry/' .env

# 2. Restart Flask
flask --app app run --port 5001
```

Startup log confirms: `LLM provider: foundry | model: Llama-3.3-70B-Instruct`

**Side-by-side comparison:**

| Attribute | Ollama (VM) | Foundry (MaaS) |
|---|---|---|
| Model | Llama 3.1 8B | Llama 3.3 70B |
| Response time | 20–60 seconds (CPU) | 2–5 seconds (GPU) |
| Cost per turn | ~$0 (VM disk only) | ~$0.005 |
| Always available | No (start VM first) | Yes (serverless) |
| Data sovereignty | Full (stays in VM) | Azure tenant only |
| Idle cost | VM disk ~$10/mo | $0.00 |

---

## 15. Cost Monitoring

**Why:** Foundry charges per token. Monitoring prevents surprises.

**View usage in Azure Portal:**
1. Go to `https://portal.azure.com`
2. Click **"Cost Management + Billing"** in the left panel
3. Click **"Cost Management"**
4. Click **"Cost Analysis"** under Reporting + analytics
5. Filter by resource group `rg-shopiq-llm-poc`
6. For Foundry specifically: filter `Type = microsoft.saas/resources`

**Pricing reference:**
- Input tokens: ~$2.68 per million
- Output tokens: ~$3.54 per million
- **Idle cost: $0.00** — no charges when no requests are made

**Estimated costs:**

| Activity | Tokens | Cost |
|---|---|---|
| 1 chat turn (identify + order) | ~1,800 total | ~$0.005 |
| Full 30-turn demo session | ~54,000 total | ~$0.15 |
| 10 demos/month | ~540,000 total | ~$1.50 |
| Leaving idle all month | 0 | **$0.00** |

> **There is no hourly charge for the Foundry endpoint.** Unlike the VM which
> charges $0.192/hr whether or not you use it, Foundry charges nothing for
> idle time. You can deploy it today, not use it for 3 months, and owe $0 for
> those 3 months.

---

## 16. Troubleshooting

| Symptom | Root cause | Fix |
|---|---|---|
| `Foundry connection failed` in Flask log | SSL cert verification failing | Add `verify=False` to `_call_foundry()` and `import urllib3; urllib3.disable_warnings()` |
| `CERTIFICATE_VERIFY_FAILED` | Corporate/ISP SSL proxy | Use `verify=False` — connection is still encrypted |
| `401 Unauthorized` | Wrong or expired API key | Re-copy key from Foundry Details page |
| `404 Not Found` | URL missing `/models/chat/completions` | Append path to FOUNDRY_BASE_URL in .env |
| `Model not found` | Wrong model name | Must be exactly `Llama-3.3-70B-Instruct` (case-sensitive) |
| `Too Many Requests` | Rate limit hit (20 req/min) | Add retry logic or click "Request quota" in Foundry |
| Flask reads old provider | .env not reloaded | Restart Flask after every .env change |
| Foundry works in curl, not Python | Different cert stores | Use `verify=False` in Python requests |
| `AI service temporarily unavailable` in chat | Foundry URL/key wrong | Run the verification curl from step 12 |
| Project not visible | Wrong Azure tenant | Confirm you are signed into the correct account |

**Quick diagnostic command — run this any time to check what Flask will read:**
```bash
python3 -c "
from dotenv import load_dotenv; import os; load_dotenv()
print('Provider:', os.getenv('LLM_PROVIDER'))
print('Foundry URL:', os.getenv('FOUNDRY_BASE_URL'))
print('Key length:', len(os.getenv('FOUNDRY_API_KEY', '')))
print('DB Host:', os.getenv('DB_HOST'))
"
```

All four lines must print valid values before starting Flask.