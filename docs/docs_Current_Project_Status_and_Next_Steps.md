# Solace Core Suite — Project Status & Next Steps

**Date:** 2025-09-05  
**Maintainer:** Melynxis  
**Host:** `solace` (Ubuntu 24.04 LTS)  
**Repo:** [Solace](https://github.com/Melynxis/Solace)  
**Location:** `/home/melynxis/solace`  

---

## 1. Current Project Status

### **Core Infrastructure**

- **MySQL:**  
  - Containerized, healthy.  
  - Primary DB: `solace`  
  - App user: `solace_app` with full GRANTs.
- **Redis:**  
  - Containerized, healthy.  
  - Password protected.  
  - Used for ephemeral state and rate-limiting.
- **Weaviate:**  
  - Version: `1.32.5`  
  - Single node, API key auth (Bearer, not X-API-KEY).  
  - Raft state clean; join-loop autofix enabled.
- **Compose Files:**  
  - `infra/compose.core.yml` (core services)  
  - `infra/exporters.compose.yml` (monitoring exporters)  
  - Bind mounts and named volumes mapped and rebased as needed.

### **Service Stack**

- **Registry API:**  
  - FastAPI, MySQL-backed.  
  - CRUD for spirits, registry tools, RBAC endpoints.  
  - Metrics exposed for Prometheus.
- **Orchestrator & MCP:**  
  - FastAPI services for spirit creation/modification workflows.  
  - Tmux used **only** for spirit creation/modification (per executive decision).
  - Service check-in and registry endpoints functional.
- **Ghostpaw Dashboard:**  
  - UI scaffold present (`apps/ghostpaw-dashboard/`).  
  - RBAC and spirit controls to be expanded.
- **Hooks:**  
  - Stubbed for future Vigil, Mica, and related spirit modules.

### **Monitoring & Observability**

- **Exporters:**  
  - Node, MySQL, Redis, Blackbox exporters running.  
  - Prometheus/Grafana live on separate Observability host.
- **Metrics exposed:**  
  - Service endpoints (health, metrics) available for scraping.

### **Security & Auth**

- **Env file hardened:**  
  - `.env` with all required secrets (MySQL, Redis, Weaviate API key).
- **Weaviate:**  
  - Anonymous access **disabled**.  
  - API-key authentication **enabled** (Bearer header required).

### **Recovery & Maintenance**

- **Autofix scripts:**  
  - `/tools/weaviate_autofix_on_boot.sh`  
  - Systemd unit: `weaviate-autofix.service`
- **Backup/Snapshot:**  
  - Snapshots for compose files and env stored at `/home/melynxis/run/snapshots/`.

---

## 2. Next Steps

### **A. Core Service Expansion**

- **Spirit Ecosystem**
  - Finalize canonical spirit templates and registry schema.
  - Automate spirit creation/birth flows via MCP and orchestrator (tmux integration).
  - Begin integration of first spirits: Springer, Vigil, Brume, Cantrelle, Mica.

- **Memory Pipeline**
  - Connect Weaviate ingest to registry and dashboard.
  - Implement delta ingestion and semantic search endpoints.

- **RBAC & Security**
  - Expand RBAC enforcement to all API endpoints.
  - Add JWT support for broader integration.

### **B. Ghostpaw Dashboard**

- **WebUI Migration**
  - Move dashboard code into `/apps/ghostpaw-dashboard/`.
  - Integrate registry, RBAC, and spirit controls.
  - Surface health/status of core services.

- **User & Roles**
  - Implement user management, role assignment, and audit logging.

### **C. Monitoring & Observability**

- **Prometheus Integration**
  - Confirm exporters scrape correctly.
  - Add alerting for join-loop, health degradations, and auth failures.

### **D. Documentation & Governance**

- **Update Core Docs**
  - Add runbook for service recovery and snapshot restoration.
  - Expand Section 2 (Architecture), Section 7 (Technical Implementation), and Section 10 (Governance) with current fixes.

- **Executive Decisions**
  - Review and bind latest changes to Executive Decision log.
  - Confirm all changes are reflected in Section docs.

### **E. Maintenance & Automation**

- **Script Cleanup**
  - Remove superseded or duplicate scripts.
  - Document all scripts in `/tools/` for future reference.

- **Systemd Templates**
  - Maintain reference unit files in `/services/orchestrator/systemd_template/`.

- **WebUI Migration**
  - Plan and execute migration of Ghostpaw WebUI into main repo tree.

---

## 3. Open Issues / Action Items

- [ ] Automate snapshot rotation and recovery.
- [ ] Finalize spirit birth/modify workflow (tmux orchestration).
- [ ] Harden RBAC and API key enforcement.
- [ ] Integrate dashboard controls for real-time spirit and service health.
- [ ] Document recovery steps for raft join-loop and schema/auth failures.
- [ ] Complete migration of WebUI into `/apps/ghostpaw-dashboard/`.

---

## 4. Reference Docs

- `Executive_Implementation_Solace_Core.md`
- `Executive_Implementation_Weaviate_Fix.md`
- `Section_2_System_Architecture.txt`
- `Section_3_MCP.txt`
- `Section_5_Spirit_Ecosystem.txt`
- `Section_6_Core_Abilities.txt`
- `Section_7_Technical_Implementation.txt`
- `Section_8_Development_Roadmap.txt`
- `Section_9_Appendices.txt`
- `Section_10_Governance_Operations.txt`
- `solace_environment.md`

---

**Contact:**  
For architecture or operational questions, see the docs above or contact Melynxis.
