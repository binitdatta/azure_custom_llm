"""
ShopIQ Customer Service Chatbot
Flask app backed by a private LLM (Ollama/vLLM) + MySQL
"""

import os
import uuid
import json
import logging
from datetime import datetime

import requests
from flask import Flask, render_template, request, jsonify, session
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

load_dotenv()

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

# ── Flask app ─────────────────────────────────────────────────────────────────
app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "change-me-in-production")

# ── Database ──────────────────────────────────────────────────────────────────
DB_URL = (
    f"mysql+pymysql://{os.getenv('DB_USER','shopiq_app')}:"
    f"{os.getenv('DB_PASSWORD','shopiq_pass')}@"
    f"{os.getenv('DB_HOST','127.0.0.1')}:{os.getenv('DB_PORT','3306')}/"
    f"{os.getenv('DB_NAME','shopiq_db')}"
)
engine = create_engine(DB_URL, pool_pre_ping=True, pool_size=5)

# ── LLM endpoint ──────────────────────────────────────────────────────────────
LLM_URL   = os.getenv("LLM_BASE_URL", "http://localhost:11434/api/chat")
LLM_MODEL = os.getenv("LLM_MODEL", "llama3.1:8b")

# ─────────────────────────────────────────────────────────────────────────────
# Database helpers
# ─────────────────────────────────────────────────────────────────────────────

def get_customer_by_email(email: str) -> dict | None:
    with engine.connect() as conn:
        row = conn.execute(
            text("SELECT customer_id, first_name, last_name, email, loyalty_tier "
                 "FROM customers WHERE email = :email"),
            {"email": email}
        ).mappings().first()
    return dict(row) if row else None


def get_orders_for_customer(customer_id: int) -> list[dict]:
    with engine.connect() as conn:
        rows = conn.execute(
            text("""
                SELECT o.order_id, o.status, o.total_amount,
                       o.tracking_number, o.carrier,
                       o.ordered_at, o.shipped_at, o.delivered_at
                FROM orders o
                WHERE o.customer_id = :cid
                ORDER BY o.ordered_at DESC
                LIMIT 10
            """),
            {"cid": customer_id}
        ).mappings().all()
    return [dict(r) for r in rows]


def get_order_detail(order_id: int, customer_id: int) -> dict | None:
    with engine.connect() as conn:
        order = conn.execute(
            text("""
                SELECT o.order_id, o.status, o.subtotal, o.shipping_cost,
                       o.tax_amount, o.total_amount, o.shipping_address,
                       o.tracking_number, o.carrier,
                       o.ordered_at, o.shipped_at, o.delivered_at
                FROM orders o
                WHERE o.order_id = :oid AND o.customer_id = :cid
            """),
            {"oid": order_id, "cid": customer_id}
        ).mappings().first()
        if not order:
            return None

        items = conn.execute(
            text("""
                SELECT p.name, oi.quantity, oi.unit_price, oi.line_total
                FROM order_items oi
                JOIN products p ON p.product_id = oi.product_id
                WHERE oi.order_id = :oid
            """),
            {"oid": order_id}
        ).mappings().all()

    return {"order": dict(order), "items": [dict(i) for i in items]}


def get_product_info(search_term: str) -> list[dict]:
    with engine.connect() as conn:
        rows = conn.execute(
            text("""
                SELECT p.sku, p.name, p.description, p.unit_price, p.stock_qty,
                       c.name AS category
                FROM products p
                LEFT JOIN categories c ON c.category_id = p.category_id
                WHERE p.is_active = 1
                  AND (p.name LIKE :q OR p.description LIKE :q OR c.name LIKE :q)
                LIMIT 5
            """),
            {"q": f"%{search_term}%"}
        ).mappings().all()
    return [dict(r) for r in rows]


def save_chat_message(session_id: str, role: str, content: str,
                      customer_id: int | None = None):
    with engine.begin() as conn:
        conn.execute(
            text("""
                INSERT IGNORE INTO chat_sessions (session_id, customer_id)
                VALUES (:sid, :cid)
            """),
            {"sid": session_id, "cid": customer_id}
        )
        conn.execute(
            text("""
                INSERT INTO chat_messages (session_id, role, content)
                VALUES (:sid, :role, :content)
            """),
            {"sid": session_id, "role": role, "content": content}
        )


# ─────────────────────────────────────────────────────────────────────────────
# LLM interaction
# ─────────────────────────────────────────────────────────────────────────────

SYSTEM_PROMPT = """You are ShopIQ Assistant, a helpful customer service agent
for an e-commerce platform. You help customers with:
- Order status and tracking
- Product information and availability
- Return and refund inquiries
- General shopping questions

When you receive structured data from the database, use it to give precise,
accurate answers. Be friendly, concise, and professional. If you cannot find
the requested information, say so politely and suggest alternatives.

Never fabricate order numbers, tracking numbers, or prices.
Always address the customer by name if you know it."""


def build_context_message(user_message: str, customer: dict | None) -> str:
    """Augment the user message with live DB context."""
    context_parts = []
    msg_lower = user_message.lower()

    if customer:
        context_parts.append(
            f"[Customer on file: {customer['first_name']} {customer['last_name']}, "
            f"tier={customer['loyalty_tier']}]"
        )
        if any(k in msg_lower for k in ("order", "track", "ship", "deliver", "status")):
            orders = get_orders_for_customer(customer["customer_id"])
            if orders:
                context_parts.append(f"[Recent orders: {json.dumps(orders, default=str)}]")

    if any(k in msg_lower for k in ("product", "price", "stock", "available", "buy", "cost")):
        words = [w for w in user_message.split() if len(w) > 3]
        for word in words:
            products = get_product_info(word)
            if products:
                context_parts.append(f"[Product matches: {json.dumps(products, default=str)}]")
                break

    if context_parts:
        return "\n".join(context_parts) + "\n\nCustomer says: " + user_message
    return user_message


def call_llm(messages: list[dict]) -> str:
    """Call Ollama chat API (non-streaming)."""
    payload = {
        "model": LLM_MODEL,
        "messages": messages,
        "stream": False
    }
    try:
        resp = requests.post(LLM_URL, json=payload, timeout=300)
        resp.raise_for_status()
        data = resp.json()
        return data["message"]["content"]
    except requests.exceptions.ConnectionError:
        return ("I'm sorry, the AI service is temporarily unavailable. "
                "Please try again in a moment or contact support@shopiq.com.")
    except requests.exceptions.Timeout:
        log.error("LLM call timed out after 300s")
        return ("I'm sorry, the AI is taking longer than expected. "
                "Please try again — the model may still be warming up.")
    except Exception as exc:
        log.error("LLM call failed: %s", exc)
        return "I encountered an issue processing your request. Please try again."


# ─────────────────────────────────────────────────────────────────────────────
# Routes
# ─────────────────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    if "session_id" not in session:
        session["session_id"] = str(uuid.uuid4())
        session["history"] = []
        session["customer"] = None
    return render_template("index.html")


@app.route("/api/identify", methods=["POST"])
def identify():
    email = request.json.get("email", "").strip().lower()
    customer = get_customer_by_email(email)
    if customer:
        session["customer"] = customer
        return jsonify({
            "found": True,
            "name": f"{customer['first_name']} {customer['last_name']}",
            "tier": customer["loyalty_tier"]
        })
    return jsonify({"found": False})


@app.route("/api/chat", methods=["POST"])
def chat():
    user_message = request.json.get("message", "").strip()
    if not user_message:
        return jsonify({"error": "Empty message"}), 400

    session_id = session.get("session_id", str(uuid.uuid4()))
    customer   = session.get("customer")
    history    = session.get("history", [])

    save_chat_message(session_id, "user", user_message,
                      customer["customer_id"] if customer else None)

    augmented = build_context_message(user_message, customer)

    llm_messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    llm_messages += history[-10:]
    llm_messages.append({"role": "user", "content": augmented})

    reply = call_llm(llm_messages)

    history.append({"role": "user",      "content": user_message})
    history.append({"role": "assistant", "content": reply})
    session["history"] = history

    save_chat_message(session_id, "assistant", reply,
                      customer["customer_id"] if customer else None)

    return jsonify({"reply": reply, "session_id": session_id})


@app.route("/api/reset", methods=["POST"])
def reset():
    session.clear()
    session["session_id"] = str(uuid.uuid4())
    session["history"]    = []
    session["customer"]   = None
    return jsonify({"status": "ok"})


@app.route("/health")
def health():
    return jsonify({"status": "ok", "model": LLM_MODEL,
                    "timestamp": datetime.utcnow().isoformat()})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)