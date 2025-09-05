# /home/melynxis/solace/services/ingest/wiki_ingest.py

import requests, json, os
from datetime import datetime

WIKI_API = "https://en.wikipedia.org/w/api.php"
WEAVIATE_URL = os.getenv("WEAVIATE_URL", "http://localhost:8080")
WEAVIATE_APIKEY = os.getenv("WEAVIATE_APIKEY", "changeme")
MYSQL_URL = os.getenv("MYSQL_URL", "mysql+pymysql://...")

def fetch_wiki_page(title):
    params = {
        "action": "query",
        "prop": "extracts",
        "explaintext": True,
        "titles": title,
        "format": "json"
    }
    r = requests.get(WIKI_API, params=params)
    r.raise_for_status()
    return r.json()

def push_to_weaviate(page_title, content, metadata):
    headers = {"Authorization": f"Bearer {WEAVIATE_APIKEY}"}
    obj = {
        "class": "Memory",
        "properties": {
            "title": page_title,
            "text": content,
            "metadata": metadata,
            "createdAt": datetime.utcnow().isoformat()
        }
    }
    r = requests.post(f"{WEAVIATE_URL}/v1/objects", headers=headers, json=obj)
    r.raise_for_status()
    return r.json()

def record_ingest_mysql(title, meta):
    # Logic to connect to MySQL and store ingest event/version
    pass

def ingest_wiki_page(title):
    data = fetch_wiki_page(title)
    # Extract page content
    page = next(iter(data["query"]["pages"].values()))
    content = page.get("extract", "")
    metadata = {"source": "wikipedia", "pageid": page.get("pageid")}
    # Push to Weaviate
    push_to_weaviate(title, content, metadata)
    # Record event in MySQL
    record_ingest_mysql(title, metadata)

def ingest_delta(title):
    # Compare current content with last ingested version from MySQL
    # Only push updates if changed
    pass

# Cron or dashboard trigger to run ingest_wiki_page / ingest_delta