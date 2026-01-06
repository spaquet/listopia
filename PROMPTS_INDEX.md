# Pre-Creation Planning Flow - Prompts Documentation Index

## Quick Navigation

### 🎯 Start Here
- **New to the flow?** → Read [PROMPTS_QUICK_REFERENCE.md](#quick-reference)
- **Want the full prompts?** → Read [PRE_CREATION_PLANNING_PROMPTS.md](#full-prompts)
- **Need a visual?** → Read [PROMPT_FLOW_DIAGRAM.md](#flow-diagram)
- **Need to modify prompts?** → Jump to [Configuration Guide](#configuration)

---

## Documentation Files

### 📋 Full Prompts
**File:** `PRE_CREATION_PLANNING_PROMPTS.md`

Complete reference including:
- Full text of all 4 prompts
- Model selection & configuration
- Input/output specifications
- Real-world examples
- Design rationale
- Future enhancements

**Read this when:**
- Reviewing prompt quality
- Understanding design decisions
- Implementing improvements
- Training new team members

**Key sections:**
1. Complexity Detection Prompt (lines 29-181)
2. Question Generation Prompt (lines 226-405)
3. Parameter Extraction Prompt (lines 447-530)
4. Structure Enrichment Logic (lines 572-620)

---

### 🔄 Flow Diagrams
**File:** `PROMPT_FLOW_DIAGRAM.md`

Visual documentation including:
- ASCII flow diagram (all 6 stages)
- State transitions
- Error handling flows
- Model selection guide
- Temperature settings
- Configuration summary

**Read this when:**
- Understanding the flow visually
- Debugging state issues
- Planning modifications
- Explaining to non-technical stakeholders

**Key diagrams:**
1. Complete end-to-end flow
2. Stage-by-stage detail
3. State flow with branching
4. Error handling paths

---

### ⚡ Quick Reference
**File:** `PROMPTS_QUICK_REFERENCE.md`

Developer quick-lookup including:
- File locations & line numbers
- Key phrases from each prompt
- Question templates by category
- Configuration instructions
- Testing scenarios
- Troubleshooting guide

**Read this when:**
- Finding a specific prompt
- Modifying configuration
- Testing different flows
- Debugging issues
- Performance optimization

**Key sections:**
- At a Glance (each stage)
- Quick Prompt Lookup
- Configuration Changes
- Testing Different Flows
- Common Issues & Solutions

---

## The 6-Stage Flow

### Stage 1: Complexity Detection
**Service:** `ListComplexityDetectorService`
**File:** `app/services/list_complexity_detector_service.rb` (lines 53-181)
**Model:** `gpt-5-nano`

Determines if a request needs planning questions.

**Detects:**
- Multi-location (roadshow, tour, visits)
- Time-bound phases (timeline, milestones)
- Hierarchical structure (nested organization)
- Large scope (comprehensive planning)
- Coordination complexity (multiple people/teams)

**Output:** `{is_complex, planning_domain, confidence, reasoning}`

---

### Stage 2: Question Generation
**Service:** `ListRefinementService`
**File:** `app/services/list_refinement_service.rb` (lines 102-211)
**Model:** `gpt-4-turbo`

Generates 3 context-aware clarifying questions.

**Key Logic:**
- Checks CATEGORY first (professional vs personal)
- Matches DOMAIN (event, travel, learning, etc.)
- Uses template questions
- Prevents category mismatches

**Output:** `{questions: [{question, context, field}]}`

---

### Stage 3: Form Rendering
**Template:** `_pre_creation_planning.html.erb`
**Controller:** `pre_creation_planning_controller.js`

Displays interactive form with questions.

**Features:**
- Textarea for each answer
- Context/reasoning for each question
- Validation (all fields required)
- Submit & Cancel buttons

---

### Stage 4: Parameter Extraction
**Service:** `ChatCompletionService`
**File:** `app/services/chat_completion_service.rb` (lines 779-831)
**Model:** `gpt-5-nano`

Extracts structured parameters from free-form answers.

**Extracts:**
- duration, budget, locations, start_date
- timeline, team_size, phases, preferences

**Output:** JSON with extracted fields

---

### Stage 5: Structure Enrichment
**Service:** `ChatCompletionService`
**File:** `app/services/chat_completion_service.rb` (lines 834-886)
**Model:** None (pure logic)

Transforms flat structure into nested lists.

**Creates:**
- Nested lists by location OR phase
- Distributes items to each location/phase
- Enriches descriptions with parameters

---

### Stage 6: List Creation
**Service:** `ChatCompletionService`
**File:** `app/services/chat_completion_service.rb`
**Model:** gpt-4-turbo (optional)

Creates final list with enriched structure.

**Creates:**
- Parent list with enriched description
- Nested lists with location/phase tasks
- List items with context

---

## Key Prompt Features

### Complexity Detection Prompt
```
✓ Detects 5 complexity indicators
✓ Returns planning domain for routing
✓ Includes 8+ classification examples
✓ Uses temperature 0.3 (consistent)
✓ Fallback handles errors gracefully
```

### Question Generation Prompt
```
✓ Category-aware (professional vs personal)
✓ Domain-specific (event, travel, learning, etc.)
✓ Enforces exactly 3 questions
✓ Prevents question type mixing
✓ Includes context for each question
```

### Parameter Extraction Prompt
```
✓ Structured extraction (8 fields)
✓ Preserves units (3 days, $2000)
✓ Type conversion (arrays, etc.)
✓ Only extracts mentioned info (no guessing)
✓ Handles arrays correctly
```

---

## Configuration Guide

### Change Models
```
Complexity Detection:  app/services/list_complexity_detector_service.rb:26
Question Generation:   app/services/list_refinement_service.rb:63
Parameter Extraction:  app/services/chat_completion_service.rb:781
```

### Change Questions Per Prompt
```
Lines 74 & 195 in app/services/list_refinement_service.rb
Currently: "exactly 3 clarifying questions"
```

### Add New Domain
```
1. Add to ListComplexityDetectorService examples
2. Add to ListRefinementService templates (lines 143-189)
3. Update planning_domain enum
```

### Add New Questions
```
File: app/services/list_refinement_service.rb
Professional questions: lines 143-157
Personal questions: lines 166-179
```

---

## Testing Scenarios

### Simple Request (No Planning)
```
Input: "Grocery shopping list"
Expected: is_complex=false → Create list directly
```

### Complex Professional Event
```
Input: "I need organize a roadshow starting in June"
Expected: Generate professional event questions
```

### Complex Personal Event
```
Input: "Plan my daughter's birthday party"
Expected: Generate personal event questions
```

### Location-Based Enrichment
```
Answer: "San Francisco, Chicago, Boston"
Expected: Creates nested list per city
```

### Phase-Based Enrichment
```
Answer: "Planning, Execution, Wrap-up phases"
Expected: Creates nested list per phase
```

---

## Debugging Checklist

- [ ] Check if is_complex detection working correctly
- [ ] Verify category being passed to question generator
- [ ] Confirm domain routing matches templates
- [ ] Check if questions appear in form
- [ ] Validate form submission triggers parameter extraction
- [ ] Verify nested lists created per locations/phases
- [ ] Check final list structure matches enrichment logic
- [ ] Review logs for LLM response parsing errors

---

## File Locations Summary

| Component | File | Lines |
|-----------|------|-------|
| Complexity Detection | `list_complexity_detector_service.rb` | 53-181 |
| Question Generation | `list_refinement_service.rb` | 102-211 |
| Form Template | `_pre_creation_planning.html.erb` | 1-75 |
| Form Controller | `pre_creation_planning_controller.js` | 1-107 |
| Parameter Extraction | `chat_completion_service.rb` | 779-831 |
| Structure Enrichment | `chat_completion_service.rb` | 834-886 |

---

## Performance Tips

1. **Use gpt-5-nano for simple tasks** (faster, cheaper)
2. **Use gpt-4-turbo for reasoning** (better quality)
3. **Cache domain detection** across requests
4. **Batch operations** where possible
5. **Monitor LLM parsing** in logs

---

## Monitoring & Logs

Key log lines to grep:
```bash
# Complexity detection
grep "ListComplexityDetectorService" log/production.log

# Question generation  
grep "BUILD_REFINEMENT_PROMPT" log/production.log

# Parameter extraction
grep "extract_planning_parameters" log/production.log

# Structure enrichment
grep "enrich_list_structure" log/production.log

# Final creation
grep "handle_pre_creation_planning" log/production.log
```

---

## Related Documentation

- [Rails Service Pattern](https://guides.rubyonrails.org)
- [RubyLLM Documentation](https://github.com/ruby-llm)
- [Prompt Engineering Best Practices](https://openai.com/research)
- [List Creation System](#) (TBD)

---

## Questions?

For clarifications:
1. Check the relevant documentation file above
2. Search for file:line in documentation
3. Review source code with line numbers
4. Check logs for error messages

---

**Last Updated:** 2026-01-04
**Documentation Version:** 1.0
**Status:** Complete
