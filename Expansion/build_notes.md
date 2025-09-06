# Ghostpaw Dashboard & Solace Suite — Build Notes & Future Expansion

## Folder Purpose

This folder collects all expansion plans, prototypes, rough integrations, and future blueprints for the Ghostpaw Dashboard and Solace Suite.  
Use it for:
- UI feature roadmap and tab planning
- Semantic search (embeddinggemma/Ollama) integration notes
- RAG/Wikipedia ingest pipeline design
- Personality matrix and behavioral expansion
- Service orchestration and Builder/Orchestrator flow stubs
- Any plans, docs, or diagrams for next-gen features

---

## Current Sprint

- Build out core Ghostpaw Dashboard UI (tabs, spirit controls, registry, RBAC, health)
- Stub Orchestrator/Builder flows until backend is live
- Reference personality matrix and spirit lifecycle blueprints

---

## Future Expansion (Next Steps)

- **RAG & Knowledge Search Tab**
  - Add UI for semantic search over wiki/memory (Weaviate, embeddinggemma)
  - Batch/delta ingest job triggers (dashboard or cron)
  - Remote embedding node (Serene) support
  - Conversational agent with context retrieval from local knowledge

- **Personality Matrix Editor**
  - Expand editor to cover full trait, mood, relationship matrix (see docs/ghostpaw_personality_modification.md)
  - Behavioral style and lore-wrapped response logic (see blueprints/spiritMatrix.ts)

- **RBAC/Role Editor**
  - Full UI for role assignment, audit logging, and permission checks

- **Service Health & Observability**
  - Dashboard widgets for Registry, MCP, Orchestrator, Redis, Weaviate health
  - Live metrics, alerts, Prometheus/Grafana integration

- **Builder/Orchestrator Workflow**
  - UI for spirit creation/modification, spec upload, test results, tmux integration

---

## References

- [Project Expansion: Local Embedding Models & Semantic Search](../docs_Project_Expansion_Ideas_embeddinggemma_and_local_semantic_search_Version2.md)
- [Personality Matrix System](../docs/ghostpaw_personality_modification.md)
- [Spirit Lifecycle Blueprint](../spirits/templates/ghostpaw_spirit_lifecycle.py)
- [User Roles & RBAC](../docs/ghostpaw_user_roles.md)
