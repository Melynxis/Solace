# Solace Core Suite — Operational Reference

This README provides a quick operational guide for the Solace Core stack, covering registry, MCP, orchestrator, and monitoring/exporter services.  
For full implementation and executive notes, see:  
- [`Executive_Implementation_Solace_Core.md`](Executive_Implementation_Solace_Core.md)
- [`Executive_Implementation_Weaviate_Fix.md`](Executive_Implementation_Weaviate_Fix.md)
- [`solace_environment.md`](solace_environment.md)

---

## Service Overview

- **Registry**: FastAPI (MySQL-backed) API for spirits, events, and registry services.
- **Orchestrator**: Controls multi-service startup/lifecycle.
- **MCP**: Master Control Program — orchestrates runtime and state.
- **Weaviate**: Semantic memory, API-key protected.
- **Redis**: State and rate-limiting.
- **MySQL**: Core DB.
- **Monitoring**: Prometheus exporters for MySQL, Redis, system.

---

## Quick Start

### 1. Environment

Edit your hardened `.env`:

```bash
nano /home/melynxis/solace/.env
```

See sample in [`Executive_Implementation_Solace_Core.md`](Executive_Implementation_Solace_Core.md).

---

### 2. Docker Compose

Bring up the core stack (MySQL, Redis, Weaviate):

```bash
cd /home/melynxis/solace/infra
docker compose --env-file /home/melynxis/solace/.env -f compose.core.yml up -d
```

Monitor health:

```bash
docker ps
docker logs solace_mysql
docker logs solace_redis
docker logs solace_weaviate
```

---

### 3. Registry API

**Dev script:**  
```bash
nano /home/melynxis/solace/services/registry/dev.sh
```
**Start via systemd:**  
```bash
sudo systemctl restart ghostpaw-registry
sudo systemctl status ghostpaw-registry
```
**Manual run:**  
```bash
cd /home/melynxis/solace/services/registry
bash dev.sh
```

**Test API:**  
```bash
curl http://127.0.0.1:8081/health
curl http://127.0.0.1:8081/spirits
```

---

### 4. Orchestrator & MCP

**Dev scripts:**  
```bash
nano /home/melynxis/solace/services/orchestrator/dev.sh
nano /home/melynxis/solace/services/orchestrator/dev-mcp.sh
```

**Systemd units:**  
```bash
sudo nano /etc/systemd/system/ghostpaw-orchestrator.service
sudo nano /etc/systemd/system/ghostpaw-mcp.service
```

**Restart + status:**  
```bash
sudo systemctl daemon-reload
sudo systemctl restart ghostpaw-orchestrator
sudo systemctl restart ghostpaw-mcp
sudo systemctl status ghostpaw-orchestrator
sudo systemctl status ghostpaw-mcp
```

**Test endpoints:**  
```bash
curl http://127.0.0.1:8082/v1/registry/health
curl http://127.0.0.1:8083/v1/mcp/health
```

---

### 5. Monitoring Exporters

**Compose file:**  
```bash
nano /home/melynxis/solace/infra/exporters.compose.yml
```

**Start exporters:**  
```bash
docker compose --env-file /home/melynxis/solace/.env -f exporters.compose.yml up -d
```

---

### 6. Snapshots & Recovery

- Snapshots of `.env` and `compose.core.yml` stored at `/home/melynxis/run/snapshots/`
- For Weaviate raft recovery, see `weaviate-autofix.service` and referenced script in [`Executive_Implementation_Solace_Core.md`](Executive_Implementation_Solace_Core.md).

---

## File Reference & Quick Access

Edit key files with nano:

```bash
nano /home/melynxis/solace/services/registry/dev.sh
nano /home/melynxis/solace/services/orchestrator/dev.sh
nano /home/melynxis/solace/services/orchestrator/dev-mcp.sh
sudo nano /etc/systemd/system/ghostpaw-registry.service
sudo nano /etc/systemd/system/ghostpaw-orchestrator.service
sudo nano /etc/systemd/system/ghostpaw-mcp.service
nano /home/melynxis/solace/.env
nano /home/melynxis/solace/infra/compose.core.yml
nano /home/melynxis/solace/infra/exporters.compose.yml
nano /home/melynxis/solace/infra/mysqld_exporter.my.cnf
```

---

## Troubleshooting

- Check logs:
  ```bash
  sudo journalctl -u ghostpaw-registry -f
  sudo journalctl -u ghostpaw-orchestrator -f
  sudo journalctl -u ghostpaw-mcp -f
  ```
- Inspect Docker health:
  ```bash
  docker ps
  docker logs <container>
  ```
- Common issues:
  - Missing shebang in dev scripts (`#!/usr/bin/env bash`)
  - Systemd unit syntax errors (must start with `[Unit]`)
  - Permissions (scripts must be executable: `chmod +x <script>`)
  - Environment variables not loaded

---

## Documentation

- [Executive_Implementation_Solace_Core.md](Executive_Implementation_Solace_Core.md)
- [Executive_Implementation_Weaviate_Fix.md](Executive_Implementation_Weaviate_Fix.md)
- [solace_environment.md](solace_environment.md)
- All Section docs (`Section_*.txt`) for architecture, governance, abilities, etc.

---

## Contact

For architecture or operational questions, see the appropriate Section doc or consult the executive implementation files.
