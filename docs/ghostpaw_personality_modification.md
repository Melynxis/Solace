# Ghostpaw Personality Modification System (Admin Controls)

## 0) Purpose & Scope

Admins can observe, freeze, edit, simulate, and roll back a Spirit’s personality safely. All changes are RBAC-gated, audited, and reversible. Sub-Admins get a reduced subset; Users/Guests cannot modify.

---

## 1) Model Overview

A Spirit’s operational personality consists of:

- **Core Traits:** Stable; define identity
  - Big-Five style vector (openness, conscientiousness, extraversion, agreeableness, neuroticism)
  - Voice/style tokens (tone, pacing, formality, empathy, humor)
  - Values/constraints

- **Mood State:** Dynamic; short half-life
  - Transient weights (curiosity, urgency, caution, playfulness, warmth, focus, etc.)
  - Decays toward baseline with time/interaction

- **Relationship Matrix:** Contextual; per subject/resource
  - Affinity/rapport, trust,
