# Ghostpaw User Roles & Permissions

## 1. Overview

Ghostpaw manages user accounts and enforces role-based access (RBAC) for all Suite operations. Four tiers are planned:

- **Admin (Full Control / Owner)**
- **Sub-Admin (Maintainer / Operator)**
- **User (Contributor / Consumer)**
- **Guest (Read-Only / Limited) [optional]**

---

## 2. Role Matrix

### **Admin**
- **Infrastructure:** Start/stop/restart any service (DBs, orchestrator, spirits); run migrations, backups, restore; manage config and secrets (with Brume).
- **RBAC:** Create/modify/delete roles; assign permissions; override or lock moods/relationships; full RBAC editor.
- **Data:** Full CRUD on Spirits, Memory, Registry, State; purge/archive datasets.
- **Observability:** View all logs, metrics, dashboards; configure alerts/thresholds.
- **Special:** Access “Executive Decision” layer; freeze/unfreeze spirits.

### **Sub-Admin**
- **Infrastructure:** Restart spirits/submodules; scale/reconfigure within quotas.
- **RBAC:** Assign Users; request new roles; cannot edit Admin roles.
- **Data:** Create/edit Spirits, Memory, Registry; soft-delete/archive (no hard delete); tag/curate Memory (Mica approval).
- **Observability:** View logs/metrics (read-only).
- **Special:** Adjust mood/relationship weights (assigned Spirits); approve/deny User submissions.

### **User**
- **Spirits:** Create draft Spirits; interact with assigned Spirits; submit Memory (pending review).
- **Memory:** Search/query allowed Spirits; add notes; cannot delete ingested Memory.
- **Registry:** Discover tools/services; suggest new registrations (pending).
- **State:** Read/write own ephemeral state (Redis); cannot modify others.
- **General:** View project metrics.

### **Guest** *(optional)*
- **Spirits:** Browse public/whitelisted Spirits.
- **Memory:** Read-only curated Memory.
- **Registry:** View services; no interaction.
- **State:** No access.
- **General:** Health endpoints only.

---

## 3. Ghostpaw Dashboard Mapping

- **Admin View:** All tabs unlocked (RBAC editor, infra, secrets).
- **Sub-Admin View:** Most tabs; RBAC limited to user/project assignment.
- **User View:** “My Spirits,” “My Memory,” “Registry Explorer.”
- **Guest View:** Read-only “Public Spirits.”

---

## 4. API Alignment

- `/v1/rbac/roles` — Returns current roles.
- `/v1/rbac/check` — Enforces at request time.

---

## 5. Implementation Notes

- RBAC enforced at API gateway and dashboard layer.
- Brume handles secrets; Vigil gates sensitive actions.
- All changes logged for audit (see Section_10_Governance_Operations.txt).
