# Archived Documentation

This directory contains historical documentation and implementation notes that have been consolidated into the primary reference guides.

## Files in This Archive

### Chat System Documentation

**CHAT_ARCHITECTURE_PROPOSAL.md** (64 KB)
- Original comprehensive 18-part architectural proposal
- Includes design decisions, UI mockups, and implementation roadmap
- Most features described here have been implemented
- Reference: See [CLAUDE.md - Chat System Architecture](../../CLAUDE.md#chat-system-architecture) and [CHAT_FEATURES.md](../../CHAT_FEATURES.md) for current implementation

**CHAT_IMPLEMENTATION_SUMMARY.md** (11 KB)
- Summary of implemented services (routing, tools, executor)
- Documents the tool-calling pattern and service architecture
- Status snapshot from initial implementation phase
- Reference: See [CHAT_FEATURES.md - Architecture Overview](../../CHAT_FEATURES.md#architecture-overview)

**UNIFIED_CHAT_IMPLEMENTATION.md** (11 KB)
- Phase 1 completion report for unified chat system
- Documents ChatContext class, models, views, and stimulus controllers
- Lists what was built in the unified chat foundation
- Reference: See [CHAT_FEATURES.md - Services](../../CHAT_FEATURES.md#core-services)

**CHAT_INTEGRATION_COMPLETE.md** (14 KB)
- Details about chat system integration with existing features
- Documents how chat connects to other Listopia components
- Reference: See [CLAUDE.md - Chat System Architecture](../../CLAUDE.md#chat-system-architecture)

### RAG & Search Documentation

**RAG_SEARCH_IMPLEMENTATION_STATUS.md** (11 KB)
- Status report on RAG and semantic search implementation phases
- Phase 1-3 complete, Phase 4 in progress
- Documents embedding generation, search service, RAG service
- Reference: See [RAG_SEMANTIC_SEARCH.md](../../RAG_SEMANTIC_SEARCH.md)

**API_ENDPOINTS_RAG_SEARCH.md** (11 KB)
- API endpoint documentation for search functionality
- Documents REST endpoints and internal service APIs
- Reference: See [RAG_SEMANTIC_SEARCH.md - API Endpoints](../../RAG_SEMANTIC_SEARCH.md#api-endpoints)

---

## Why These Files Were Archived

These files are comprehensive but contain:
1. **Implementation details** that have been superseded by actual working code
2. **Proposal content** that mixes architectural vision with implementation specifics
3. **Status reports** that are point-in-time snapshots no longer current
4. **Duplicate content** with primary reference guides

They are kept for **historical reference only** - to understand the evolution of the chat system and track which features were planned vs. implemented.

---

## Where to Find Information Now

### Primary Reference Documents (Project Root)

**[CLAUDE.md](../../CLAUDE.md)**
- Master development guide for Listopia
- Chat System Architecture section (350+ lines)
- Covers: command system, intent detection, resource creation, UI patterns, security
- **Start here for system overview**

**[CHAT_FEATURES.md](../../CHAT_FEATURES.md)**
- Implementation guide for chat features
- How to add commands, tools, message templates
- Testing scenarios and troubleshooting
- **Use this to implement new chat features**

**[RAG_SEMANTIC_SEARCH.md](../../RAG_SEMANTIC_SEARCH.md)**
- Complete guide to embeddings and semantic search
- Integration with chat via RAG context
- Database setup and performance optimization
- **Use this for search-related work**

---

## Development Workflow

1. **Starting a task?** → Read [CLAUDE.md](../../CLAUDE.md)
2. **Implementing chat feature?** → Read [CHAT_FEATURES.md](../../CHAT_FEATURES.md)
3. **Working with search/RAG?** → Read [RAG_SEMANTIC_SEARCH.md](../../RAG_SEMANTIC_SEARCH.md)
4. **Need historical context?** → Check archived files in this directory

---

## File Consolidation History

| Original Files | Consolidated Into | Date |
|---|---|---|
| CHAT_QUICK_START.md, CHAT_SYSTEM.md | CHAT_FEATURES.md | 2025-12-10 |
| QUICK_START_RAG_SEARCH.md, RAG_SEARCH_INDEX.md | RAG_SEMANTIC_SEARCH.md | 2025-12-10 |
| CHAT_ARCHITECTURE_PROPOSAL.md, UNIFIED_CHAT_IMPLEMENTATION.md, etc. | CLAUDE.md + CHAT_FEATURES.md | 2025-12-10 |

---

## Questions?

For questions about:
- **System architecture** → See CLAUDE.md Chat System Architecture section
- **Implementing features** → See CHAT_FEATURES.md How to Add Features section
- **Search/RAG details** → See RAG_SEMANTIC_SEARCH.md
- **Historical decisions** → See relevant archived file

If you need to understand why a decision was made, these archived files are great context!
