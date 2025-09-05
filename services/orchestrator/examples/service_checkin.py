import requests

def checkin_with_ghostpaw():
    payload = {
        "name": "solace_registry",
        "service_type": "registry",
        "api_url": "http://solace_registry:8081",
        "meta": {"version": "0.2.2"}
    }
    r = requests.post("http://ghostpaw_orchestrator:8082/v1/registry/checkin", json=payload)
    r.raise_for_status()
    print("Registered with Ghostpaw:", r.json())