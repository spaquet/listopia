# Listopia Documentation Map

Quick reference for finding the right documentation for your task.

---

## 🚀 Quick Start by Task

### I want to understand the project architecture
→ Start with [CLAUDE.md](CLAUDE.md)
- Stack overview
- Architecture patterns
- Key models and conventions
- Frontend approach
- **Chat System Architecture section** (350+ lines)

### I'm implementing a chat feature
→ Read [CHAT_FEATURES.md](CHAT_FEATURES.md)
- Quick start examples
- How to add commands
- How to add LLM tools
- How to create message templates
- Authorization patterns
- Testing scenarios
- Troubleshooting guide

### I'm working with search or RAG
→ Read [RAG_SEMANTIC_SEARCH.md](RAG_SEMANTIC_SEARCH.md)
- How embeddings work
- Hybrid search (vector + keyword)
- RAG context building
- Database setup with pgvector
- Performance optimization
- Integration with chat

### I'm debugging a problem
→ Use [CHAT_FEATURES.md - Debugging & Troubleshooting](CHAT_FEATURES.md#debugging--troubleshooting)
→ Or [RAG_SEMANTIC_SEARCH.md - Troubleshooting](RAG_SEMANTIC_SEARCH.md#troubleshooting)

### I'm writing tests
→ See [CHAT_FEATURES.md - Testing Scenarios](CHAT_FEATURES.md#testing-scenarios)

### I need API endpoint documentation
→ See [RAG_SEMANTIC_SEARCH.md - API Endpoints](RAG_SEMANTIC_SEARCH.md#api-endpoints)

### I want historical context
→ See [docs/archived/README.md](docs/archived/README.md)
- Why decisions were made
- Original architectural proposals
- Implementation history

---

## 📚 Complete Documentation Structure

```
CLAUDE.md (Master Reference)
├── Stack Overview
├── Architecture Patterns
├── Key Models
├── Organizations & Teams Architecture ✅
├── Chat System Architecture ✅ (NEW - 350+ lines)
│   ├── Overview
│   ├── Command System
│   ├── Intent Detection
│   ├── Resource Creation Flow
│   ├── Message Types & Templates
│   ├── Authorization & Data Boundaries
│   ├── Services & Components
│   ├── UI/UX Patterns
│   └── Example Flows
├── Frontend Approach
│   └── Chat UI Patterns ✅ (NEW)
├── Common Tasks
└── Development Standards

CHAT_FEATURES.md (Implementation Guide)
├── Quick Start
├── Architecture Overview
├── How to Add Features
│   ├── Add a Command
│   ├── Add an LLM Tool
│   ├── Add a Message Template
│   └── Add a Navigation Route
├── Available Tools Reference
├── Message Templates
├── Authorization & Security
├── Testing Scenarios
├── Debugging & Troubleshooting
├── Common Issues & Solutions
├── File Locations
└── Performance Optimization

RAG_SEMANTIC_SEARCH.md (Search & RAG Guide)
├── Overview
├── Core Concepts
│   ├── Embeddings
│   ├── Vector Similarity Search
│   ├── Full-Text Search
│   └── Relevance Scoring
├── Architecture
├── Database Setup
├── Embedding Generation
├── Hybrid Search
├── RAG Integration
├── Search vs. Navigation Decision Tree
├── API Endpoints
├── Internal Services
├── Integration with Chat
├── Performance & Optimization
├── Troubleshooting
└── Future Enhancements

docs/archived/README.md (Historical Reference)
├── CHAT_ARCHITECTURE_PROPOSAL.md
├── CHAT_IMPLEMENTATION_SUMMARY.md
├── UNIFIED_CHAT_IMPLEMENTATION.md
├── CHAT_INTEGRATION_COMPLETE.md
├── RAG_SEARCH_IMPLEMENTATION_STATUS.md
└── API_ENDPOINTS_RAG_SEARCH.md
```

---

## 🎯 By Developer Role

### Backend Developer (Ruby/Rails)

**Essential Reading:**
1. [CLAUDE.md](CLAUDE.md) - Project overview
2. [CHAT_FEATURES.md](CHAT_FEATURES.md) - How to add features
3. [RAG_SEMANTIC_SEARCH.md](RAG_SEMANTIC_SEARCH.md) - Search implementation

**Key Sections:**
- Architecture patterns (models, services)
- Authorization & security
- Testing scenarios
- File locations

### Frontend Developer (JavaScript/Stimulus)

**Essential Reading:**
1. [CLAUDE.md - Chat UI Patterns](CLAUDE.md#chat-ui-patterns)
2. [CHAT_FEATURES.md - Message Templates](CHAT_FEATURES.md#message-templates)
3. [RAG_SEMANTIC_SEARCH.md - API Endpoints](RAG_SEMANTIC_SEARCH.md#api-endpoints)

**Key Sections:**
- Form handling and input clearing
- Message rendering
- Turbo Stream integration
- Stimulus controllers

### AI Agent (Claude Code)

**Recommended Starting Point:**
1. [CLAUDE.md](CLAUDE.md) - Comprehensive reference
2. [CHAT_FEATURES.md](CHAT_FEATURES.md) - Implementation patterns
3. [RAG_SEMANTIC_SEARCH.md](RAG_SEMANTIC_SEARCH.md) - Search details

**Key Sections:**
- Development standards
- Authorization patterns
- File locations
- Testing checklist

---

## 🔍 By Topic

### Chat System
- Architecture: [CLAUDE.md - Chat System Architecture](CLAUDE.md#chat-system-architecture)
- Implementation: [CHAT_FEATURES.md](CHAT_FEATURES.md)
- Commands: [CHAT_FEATURES.md - How to Add Features](CHAT_FEATURES.md#how-to-add-features)
- Tools: [CHAT_FEATURES.md - Available Tools Reference](CHAT_FEATURES.md#available-tools-reference)
- Messages: [CHAT_FEATURES.md - Message Templates](CHAT_FEATURES.md#message-templates)
- Testing: [CHAT_FEATURES.md - Testing Scenarios](CHAT_FEATURES.md#testing-scenarios)

### Search & RAG
- Embeddings: [RAG_SEMANTIC_SEARCH.md - Core Concepts](RAG_SEMANTIC_SEARCH.md#core-concepts)
- Hybrid Search: [RAG_SEMANTIC_SEARCH.md - Hybrid Search](RAG_SEMANTIC_SEARCH.md#hybrid-search)
- RAG Context: [RAG_SEMANTIC_SEARCH.md - RAG Integration](RAG_SEMANTIC_SEARCH.md#rag-integration)
- Database: [RAG_SEMANTIC_SEARCH.md - Database Setup](RAG_SEMANTIC_SEARCH.md#database-setup)
- API: [RAG_SEMANTIC_SEARCH.md - API Endpoints](RAG_SEMANTIC_SEARCH.md#api-endpoints)

### Authentication & Authorization
- Overview: [CLAUDE.md - Authentication & Authorization](CLAUDE.md#authentication--authorization)
- Chat Security: [CLAUDE.md - Chat System Architecture - Authorization & Data Boundaries](CLAUDE.md#authorization--data-boundaries)
- Patterns: [CHAT_FEATURES.md - Authorization & Security](CHAT_FEATURES.md#authorization--security)

### Models & Database
- Key Models: [CLAUDE.md - Key Models](CLAUDE.md#key-models)
- Organizations: [CLAUDE.md - Organization Models](CLAUDE.md#organization-models)
- Database Conventions: [CLAUDE.md - Database Conventions](CLAUDE.md#database-conventions)
- Embeddings DB: [RAG_SEMANTIC_SEARCH.md - Database Setup](RAG_SEMANTIC_SEARCH.md#database-setup)

### Frontend & UI
- Philosophy: [CLAUDE.md - Frontend Approach](CLAUDE.md#frontend-approach)
- Chat UI: [CLAUDE.md - Chat UI Patterns](CLAUDE.md#chat-ui-patterns)
- Templates: [CHAT_FEATURES.md - Message Templates](CHAT_FEATURES.md#message-templates)
- Forms: [CLAUDE.md - Form Submission](CLAUDE.md#form-submission)

### Testing
- Standards: [CLAUDE.md - Testing](CLAUDE.md#testing)
- Chat: [CHAT_FEATURES.md - Testing Scenarios](CHAT_FEATURES.md#testing-scenarios)
- Authorization: [CHAT_FEATURES.md - Test Organization Boundary](CHAT_FEATURES.md#testing-scenarios)

---

## 📋 File Organization

### In Project Root (Active)

| File | Purpose | Lines | When to Use |
|------|---------|-------|------------|
| **CLAUDE.md** | Master development reference | 750+ | First resource for any question |
| **CHAT_FEATURES.md** | Chat implementation guide | 850+ | Building chat features |
| **RAG_SEMANTIC_SEARCH.md** | Search & RAG guide | 800+ | Working with search/embeddings |
| **DOCUMENTATION_MAP.md** | This file | - | Finding the right doc |

### In docs/archived/ (Reference Only)

| File | Historical Content | Why Archived |
|------|-------------------|--------------|
| CHAT_ARCHITECTURE_PROPOSAL.md | Original 18-part proposal | Superseded by CLAUDE.md + CHAT_FEATURES.md |
| CHAT_IMPLEMENTATION_SUMMARY.md | Implementation snapshot | Status report from implementation phase |
| UNIFIED_CHAT_IMPLEMENTATION.md | Phase 1 completion | Status report (features now in CHAT_FEATURES.md) |
| CHAT_INTEGRATION_COMPLETE.md | Integration details | Details now in CLAUDE.md Chat section |
| RAG_SEARCH_IMPLEMENTATION_STATUS.md | RAG phase status | Consolidated into RAG_SEMANTIC_SEARCH.md |
| API_ENDPOINTS_RAG_SEARCH.md | Search API docs | Content moved to RAG_SEMANTIC_SEARCH.md |

**Deleted (Content Consolidated):**
- CHAT_QUICK_START.md → CHAT_FEATURES.md
- CHAT_SYSTEM.md → CHAT_FEATURES.md
- QUICK_START_RAG_SEARCH.md → RAG_SEMANTIC_SEARCH.md
- RAG_SEARCH_INDEX.md → RAG_SEMANTIC_SEARCH.md

---

## 🚦 Documentation Quality Standards

All active documentation follows these standards:

✅ **Current** - Updated with latest implementation details
✅ **Accurate** - Reflects actual code in repository
✅ **Complete** - Covers all essential information
✅ **Clear** - Written for developers and AI agents
✅ **Actionable** - Includes examples and code samples
✅ **Organized** - Clear structure with table of contents
✅ **Cross-Referenced** - Links to related documents
✅ **Non-Duplicated** - No significant content overlap

---

## 📞 Finding Help

**Need architecture overview?**
→ [CLAUDE.md](CLAUDE.md)

**Can't find what you're looking for?**
→ Check the table of contents in each doc
→ Use Ctrl+F to search

**Implementing a new feature?**
→ [CHAT_FEATURES.md - How to Add Features](CHAT_FEATURES.md#how-to-add-features)

**Debugging something?**
→ Check "Troubleshooting" section in relevant doc

**Want historical context?**
→ [docs/archived/README.md](docs/archived/README.md)

---

## 🎓 Learning Path

### New to Listopia?
1. Read [CLAUDE.md](CLAUDE.md) overview sections
2. Read [CLAUDE.md - Stack Overview](CLAUDE.md#stack-overview)
3. Read [CLAUDE.md - Architecture Patterns](CLAUDE.md#architecture-patterns)
4. Read relevant feature docs (CHAT_FEATURES.md or RAG_SEMANTIC_SEARCH.md)

### New to Chat Features?
1. [CHAT_FEATURES.md - Quick Start](CHAT_FEATURES.md#quick-start)
2. [CHAT_FEATURES.md - Architecture Overview](CHAT_FEATURES.md#architecture-overview)
3. [CHAT_FEATURES.md - How to Add Features](CHAT_FEATURES.md#how-to-add-features)
4. Practice: Add a simple command

### New to Search/RAG?
1. [RAG_SEMANTIC_SEARCH.md - Overview](RAG_SEMANTIC_SEARCH.md#overview)
2. [RAG_SEMANTIC_SEARCH.md - Core Concepts](RAG_SEMANTIC_SEARCH.md#core-concepts)
3. [RAG_SEMANTIC_SEARCH.md - Architecture](RAG_SEMANTIC_SEARCH.md#architecture)
4. Practice: Test SearchService with real data

---

Last Updated: 2025-12-10
Documentation Version: 3.0 (Consolidated & Reorganized)
