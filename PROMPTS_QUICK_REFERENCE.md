# Pre-Creation Planning Prompts - Quick Reference

## At a Glance

### Stage 1: Complexity Detection
- **File:** `app/services/list_complexity_detector_service.rb` (lines 53-181)
- **Model:** `gpt-5-nano`
- **Input:** User message (e.g., "I need organize a roadshow")
- **Output:** `{ is_complex: true/false, planning_domain: "event|travel|...", reasoning: "..." }`
- **Decision:** Complex? → Generate questions : Create list directly

**Key Phrase in Prompt:**
> "Your job is to determine if a list creation request is COMPLEX (needs upfront planning questions)."

**Complexity Indicators Detected:**
- `multi_location` - Multiple cities/regions
- `time_bound` - Timeline with phases
- `hierarchical` - Multi-level organization
- `large_scope` - Comprehensive planning
- `coordination` - Multiple people/teams

---

### Stage 2: Question Generation
- **File:** `app/services/list_refinement_service.rb` (lines 102-211)
- **Model:** `gpt-4-turbo`
- **Input:** List title, category (professional/personal), domain, initial items
- **Output:** 3 clarifying questions in JSON format
- **Key Logic:** "Check CATEGORY first → Match questions to PROFESSIONAL or PERSONAL"

**Critical Prompt Rule:**
> "CRITICAL RULE: You are NOT creating the list yet. You are asking questions to UNDERSTAND THE TASK COMPLETELY."

**Question Types by Category & Domain:**

| Category | Domain | Question Focus |
|----------|--------|-----------------|
| **PROFESSIONAL** | event | Business objective, locations/duration, activities/formats |
| **PROFESSIONAL** | project | Business goal/metrics, timeline/phases, stakeholders/team |
| **PROFESSIONAL** | travel | Business purpose, locations/dates, people/resources |
| **PERSONAL** | event | Celebration type, guests/preferences, budget/venue |
| **PERSONAL** | travel | Trip purpose, destinations/duration, companions/constraints |
| **PERSONAL** | learning | Learning goal, experience level, time commitment/deadline |

**Example Template (Professional Event):**
```
Q1: "What is the main business objective of this ROADSHOW?"
Q2: "Which cities or regions will you visit, and how long?"
Q3: "What activities or formats will you use at each stop?"
```

---

### Stage 3: Form Rendering
- **File:** `app/views/message_templates/_pre_creation_planning.html.erb`
- **Type:** Templated message with Stimulus controller
- **Controller:** `app/javascript/controllers/pre_creation_planning_controller.js`
- **Action:** Collects answers, validates, submits as message

**Form Structure:**
```
❓ Before I create "{list_title}", I have a few questions

1. [Question 1]
   💡 [Context/why this matters]
   [Textarea for answer]

2. [Question 2]
   💡 [Context/why this matters]
   [Textarea for answer]

3. [Question 3]
   💡 [Context/why this matters]
   [Textarea for answer]

[Submit Answers]  [Cancel]
```

---

### Stage 4: Parameter Extraction
- **File:** `app/services/chat_completion_service.rb` (lines 779-831)
- **Method:** `extract_planning_parameters_from_answers`
- **Model:** `gpt-5-nano`
- **Input:** User's answers text, list context
- **Output:** Structured JSON with extracted parameters

**Extracted Fields:**
```json
{
  "duration": "4 weeks",
  "budget": "$50,000",
  "locations": ["San Francisco", "Chicago", "Boston", "New York"],
  "start_date": "June 2026",
  "timeline": "4-week tour",
  "team_size": "5-10 people",
  "phases": ["Setup", "Tour", "Wrap-up"],
  "preferences": "Focus on enterprise customers",
  "other_details": "Product demonstrations and networking"
}
```

**Prompt Instructions:**
> "Extract only information actually mentioned"
> "Be specific and preserve units (e.g., '3 days', '$2000')"
> "If locations mentioned, extract as array"
> "If phases/stages mentioned, extract as array"

---

### Stage 5: Structure Enrichment
- **File:** `app/services/chat_completion_service.rb` (lines 834-886)
- **Method:** `enrich_list_structure_with_planning`
- **Model:** None (pure logic)
- **Input:** Base parameters + Planning parameters
- **Output:** Enriched list structure with nested lists

**Transformations:**

1. **Description Enrichment:**
   ```
   BEFORE: "A plan to organize a roadshow starting in June this year."
   AFTER:  "A plan to organize a roadshow starting in June this year. |
            Duration: 4 weeks | Start: June 2026"
   ```

2. **Location-Based Nesting:**
   ```
   IF locations mentioned:
   - Create nested list for each location
   - Distribute items to each location
   - Append location context to item descriptions
   ```

3. **Phase-Based Nesting:**
   ```
   IF phases mentioned:
   - Create nested list for each phase
   - Each phase becomes a sequential stage
   ```

---

## Quick Prompt Lookup

### Need to see the Complexity Detection prompt?
→ `app/services/list_complexity_detector_service.rb` line 53-181

### Need to see the Question Generation prompt?
→ `app/services/list_refinement_service.rb` line 102-211
→ Key instruction: "Check CATEGORY first" (line 127)
→ Professional templates: lines 143-157
→ Personal templates: lines 166-179

### Need to see the Parameter Extraction prompt?
→ `app/services/chat_completion_service.rb` line 783-812

### Need to modify professional event questions?
→ `app/services/list_refinement_service.rb` line 143-146

### Need to modify personal event questions?
→ `app/services/list_refinement_service.rb` line 166-169

---

## Testing Different Flows

### Test COMPLEX LIST (triggers planning)
```
User Message: "I need organize a roadshow starting in June this year"
Expected: Complexity detection → Generate questions → Form rendered
```

### Test SIMPLE LIST (skips planning)
```
User Message: "Create a grocery shopping list"
Expected: Complexity detection → is_complex: false → Create list directly
```

### Test PROFESSIONAL CATEGORY
```
User Request: "Roadshow" with business context
Expected: Professional questions (business objective, metrics, ROI)
```

### Test PERSONAL CATEGORY
```
User Request: "Birthday party" with personal context
Expected: Personal questions (guests, preferences, budget)
```

### Test LOCATION ENRICHMENT
```
User Answers mention locations: "San Francisco, Chicago, Boston"
Expected: Creates nested list for each city
```

### Test PHASE ENRICHMENT
```
User Answers mention phases: "Planning phase, Execution phase, Wrap-up phase"
Expected: Creates nested list for each phase
```

---

## Configuration Changes

### To change number of questions generated:
1. File: `app/services/list_refinement_service.rb` line 74
2. Change: `"Generate exactly 3 clarifying questions..."`
3. Also update prompt line 195: `4. ✅ EXACTLY 3 QUESTIONS: No more, no less`

### To change model for complexity detection:
1. File: `app/services/list_complexity_detector_service.rb` line 26
2. Change: `model: "gpt-5-nano"` to preferred model
3. Cost implications: Consider temperature setting (line 27)

### To change model for question generation:
1. File: `app/services/list_refinement_service.rb` line 63
2. Change: `model: "gpt-4-turbo"` to preferred model
3. Note: GPT-4 preferred for domain-aware logic

### To change model for parameter extraction:
1. File: `app/services/chat_completion_service.rb` line 781
2. Change: `model: "gpt-5-nano"` to preferred model
3. Trade-off: Speed vs. accuracy of extraction

### To add new planning domain:
1. File: `app/services/list_refinement_service.rb` line 111-189
2. Add new domain section with IF/ELSE block
3. Follow template: domain name → 3 question examples
4. Update ListComplexityDetectorService examples

### To add new question templates:
1. File: `app/services/list_refinement_service.rb` line 143-179
2. Add under appropriate category (PROFESSIONAL or PERSONAL)
3. Add under appropriate domain section
4. Include context/why-it-matters for each question

---

## Files to Review

For a complete understanding, review in this order:

1. **`PRE_CREATION_PLANNING_PROMPTS.md`** (this directory)
   - Full prompt text for each stage
   - Examples and expected outputs
   - Design decisions and rationale

2. **`PROMPT_FLOW_DIAGRAM.md`** (this directory)
   - Visual flow of the entire process
   - State transitions and error handling
   - Model selection summary

3. **Source Code:**
   - `app/services/list_complexity_detector_service.rb` - Stage 1
   - `app/services/list_refinement_service.rb` - Stage 2
   - `app/views/message_templates/_pre_creation_planning.html.erb` - Stage 3
   - `app/javascript/controllers/pre_creation_planning_controller.js` - Stage 3
   - `app/services/chat_completion_service.rb` - Stages 4, 5, 6

---

## Common Issues & Solutions

### Issue: Wrong questions for category
**Solution:** Check ListRefinementService line 127 - ensure category is being passed correctly
**Debug:** Add logging in build_refinement_prompt (line 109)

### Issue: Questions not appearing in form
**Solution:** Check if is_complex returned false (complexity detection too strict)
**Debug:** Review ListComplexityDetectorService confidence level

### Issue: Parameters not extracted from answers
**Solution:** Check if LLM is returning valid JSON
**Debug:** Add Rails.logger to extract_planning_parameters_from_answers line 820

### Issue: Nested lists not created
**Solution:** Check if locations/phases array is properly populated
**Debug:** Review enrich_list_structure_with_planning line 855

### Issue: Questions are too generic
**Solution:** Refine question templates with domain-specific examples
**Action:** Update ListRefinementService lines 143-179

---

## Performance Tips

1. **Use gpt-5-nano for simple tasks** (complexity, extraction)
   - Faster response times
   - Lower cost
   - Sufficient for structured tasks

2. **Use gpt-4-turbo for reasoning** (question generation)
   - Better at understanding context
   - Handles domain-specific logic
   - Worth the extra cost for quality

3. **Cache category/domain detection**
   - Reuse complexity result across request
   - Avoid re-detecting in parameter extraction

4. **Batch parameter extraction**
   - Extract all parameters in one call
   - Reduces LLM roundtrips

5. **Pre-populate expected fields**
   - Helps LLM know what to extract
   - Reduces hallucination

---

## Monitoring & Logging

Key log messages to monitor:

```ruby
# Complexity detection
Rails.logger.info("ListComplexityDetectorService: #{is_complex} | #{reasoning}")

# Question generation
Rails.logger.warn("BUILD_REFINEMENT_PROMPT - @category: #{@category}, domain: #{@planning_domain}")
Rails.logger.warn("ListRefinementService#generate_refinement_questions - PARSED QUESTIONS")

# Parameter extraction
Rails.logger.info("extract_planning_parameters_from_answers called")

# Structure enrichment
Rails.logger.info("enrich_list_structure_with_planning creating nested lists")

# Creation
Rails.logger.info("ChatCompletionService - CALLING handle_pre_creation_planning")
```

Grep these in production to understand flow:
```bash
grep "ListComplexityDetectorService" log/production.log
grep "BUILD_REFINEMENT_PROMPT" log/production.log
grep "handle_pre_creation_planning" log/production.log
```
