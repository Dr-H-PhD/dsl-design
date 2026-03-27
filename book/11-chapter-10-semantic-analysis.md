\newpage

# Chapter 10: Semantic Analysis

The parser, as we built it in Chapter 9, produces an intermediate representation — a collection of `ParsedEntity`, `ParsedAssociation`, and `ParsedLink` objects. This representation is *syntactically* valid: every brace is matched, every cardinality is well-formed, every data type is recognised. But syntactic validity is not enough. A file can be perfectly structured and still meaningless: an entity named `Student` might be declared twice, a link might reference an association called `enrolment` that does not exist, or an association might share its name with an entity. These are not syntax errors — they are *semantic* errors, and catching them is the job of the semantic analyser.

This chapter covers the design and implementation of MSD's semantic analyser, which we call the **builder**. The builder takes the parser's intermediate representation and transforms it into the final `Project` model — resolving names to identifiers, detecting duplicates and conflicts, and producing helpful error messages when something goes wrong.

---

## 10.1 From Syntax Tree to Meaning

### The gap between syntax and semantics

A parser answers the question: *is this text structurally valid?* A semantic analyser answers a different question: *does this text mean something coherent?* The distinction is fundamental. Consider the following MSD fragment:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}

entity Student {
    *id: INT
    email: VARCHAR(255)
}
```

The parser will happily produce two `ParsedEntity` objects, both named `Student`. The syntax is perfectly valid — each entity block has a name, braces, and well-formed attributes. But the *meaning* is incoherent: which `Student` should a link refer to? The parser does not know and does not care. Detecting this conflict is the semantic analyser's responsibility.

### The builder's role

In MSD's architecture, the semantic analyser is called the **builder** because its primary job is to *build* the final `Project` model from the parser's intermediate representation. The builder is not merely a validator — it is a transformer. It takes `ParsedEntity` objects (which carry names, line numbers, and raw attribute data) and produces `Entity` objects (which carry UUIDs, attribute objects, and layout coordinates). It takes `ParsedLink` objects (which reference entities and associations by name) and produces `Link` objects (which reference them by UUID).

The builder's signature captures this transformation:

```python
class MSDProjectBuilder:
    def build(self, parse_result: ParseResult) -> Tuple[Optional[Project], List[MSDError]]:
        ...
```

It accepts a `ParseResult` — the parser's output — and returns a tuple of the constructed `Project` and a list of errors. Crucially, the builder always returns a project, even when errors are present. Partial results are useful: a GUI can display the entities and associations that *were* valid, even if some links failed to resolve.

### Three phases of semantic analysis

The builder's work falls into three phases, each addressing a distinct class of semantic problem:

1. **Name resolution.** The parser records that a link connects entity `"Student"` to association `"enrolment"`. The builder must find the actual `Entity` and `Association` objects that those names refer to, then replace the names with UUIDs.

2. **Duplicate and conflict detection.** Two entities with the same name, two associations with the same name, or an association that shares its name with an entity — all must be detected and reported.

3. **Constraint checking.** Domain-specific rules that span multiple constructs: does every entity have a primary key? Are the references in links valid?

These three phases are not implemented as separate passes over the data. Instead, they are interleaved within a single traversal — but understanding them as conceptually distinct phases clarifies the design.

---

## 10.2 Name-to-ID Resolution and Symbol Tables

### The problem

In an MSD file, links reference entities and associations by **name**:

```
link Student (0,N) enrolment
link Course (1,N) enrolment
```

But in the final `Project` model, links reference them by **UUID**:

```python
@dataclass
class Link:
    entity_id: str       # UUID, e.g. "a3f8c1d2-..."
    association_id: str   # UUID, e.g. "7b9e4f01-..."
    cardinality_min: str
    cardinality_max: str
    id: str = field(default_factory=lambda: str(uuid.uuid4()))
```

The builder must bridge this gap. It must take the name `"Student"` and find the `Entity` object whose `.name` is `"Student"`, then use that object's `.id` (a UUID generated automatically by the dataclass default factory) when constructing the `Link`.

### Symbol tables

The classical solution is a **symbol table** — a dictionary that maps names to the objects they denote. The builder maintains two symbol tables:

```python
entity_names: Dict[str, Entity] = {}
assoc_names: Dict[str, Association] = {}
```

As the builder processes each entity, it registers the entity's name in `entity_names`. As it processes each association, it registers the name in `assoc_names`. When it later processes links, it looks up names in these tables to find the corresponding objects and their UUIDs.

### Build order enables forward references

The builder processes constructs in a fixed order: entities first, then associations, then links. This ordering is deliberate. Because links are processed last, *all* entity and association names are already registered by the time any link is resolved. This means the MSD file can place constructs in any order:

```
# Links appear before entities — still works
link Student (0,N) enrolment
link Course (1,N) enrolment

entity Student {
    *student_id: INT
    name: VARCHAR(100)
}

entity Course {
    *course_id: INT
    title: VARCHAR(200)
}

association enrolment {
    grade: DECIMAL(4)
}
```

The parser collects all constructs into separate lists (`parse_result.entities`, `parse_result.associations`, `parse_result.links`). The builder then processes these lists in the correct order, regardless of the order they appeared in the source file. Forward references are thus supported without any additional complexity.

### The resolution code

When resolving a link's entity reference, the builder performs a simple dictionary lookup:

```python
entity = entity_names.get(pl.entity_name)
if entity is None:
    msg = f"unknown entity: '{pl.entity_name}'"
    suggestion = _suggest(pl.entity_name, all_entity_names)
    if suggestion:
        msg += f" (did you mean '{suggestion}'?)"
    errors.append(MSDError(
        message=msg,
        line=pl.line,
        column=pl.column,
        filename=filename,
        severity="error",
    ))
    continue
```

If the lookup succeeds, the builder has the `Entity` object and can use `entity.id` to construct the link. If it fails, the builder reports an error — and, as we shall see in Section 10.4, attempts to suggest the correct name.

> **Note:** The `continue` statement after reporting an unresolved name is important. The builder does not attempt to create a `Link` with a missing entity or association — doing so would produce a malformed `Link` object with a `None` ID, which would cause errors downstream. Skipping the link entirely is the safer choice.

> **Programmer:** The visitor pattern and Go's `ast.Walk` function offer two contrasting approaches to walking a parsed tree for validation. The visitor pattern (used in Java and Python AST libraries) defines an interface with a `Visit` method for each node type, and the tree drives the traversal. Go's `ast.Walk` takes the opposite approach: a single `func(ast.Node) bool` callback visits every node, and the walker handles the traversal. For small DSLs like MSD, a simple loop over slices (entities, then associations, then links) is more straightforward than either pattern. For larger DSLs with deeply nested ASTs, implementing Go's `ast.Inspect` pattern -- where a visitor function returns `true` to descend into children or `false` to skip them -- gives you clean, composable validation passes without the boilerplate of a full visitor interface.

---

## 10.3 Duplicate Detection and Conflict Checking

### Duplicate entity names

When the builder encounters an entity whose name already exists in the `entity_names` symbol table, it reports an error and skips the duplicate:

```python
for pe in parse_result.entities:
    if pe.name in entity_names:
        errors.append(MSDError(
            message=f"duplicate entity name: '{pe.name}'",
            line=pe.line,
            column=pe.column,
            filename=filename,
            severity="error",
        ))
        continue

    entity = Entity(name=pe.name)
    # ... build attributes ...
    entity_names[pe.name] = entity
    project.add_entity(entity)
```

The first entity with a given name wins. The duplicate is discarded entirely — it is not added to the project, and its name is not registered in the symbol table. This "first wins" policy is simple and predictable. An alternative would be to discard *both* and require the user to resolve the ambiguity, but in practice, the first-wins approach produces clearer error messages and fewer cascading errors.

### Duplicate association names

The same logic applies to associations. If two associations share a name, the second is reported as a duplicate and skipped:

```python
for pa in parse_result.associations:
    if pa.name in assoc_names:
        errors.append(MSDError(
            message=f"duplicate association name: '{pa.name}'",
            line=pa.line,
            column=pa.column,
            filename=filename,
            severity="error",
        ))
        continue
```

### Cross-namespace conflicts

MSD also checks for a subtler problem: an association whose name matches an existing entity name:

```python
if pa.name in entity_names:
    errors.append(MSDError(
        message=f"association name '{pa.name}' conflicts with an entity of the same name",
        line=pa.line,
        column=pa.column,
        filename=filename,
        severity="error",
    ))
    continue
```

Why does this matter? Consider a link statement:

```
link Booking (1,1) Booking
```

If `Booking` is both an entity and an association, the link's entity reference and association reference are both `"Booking"`. In our current builder, these resolve against separate symbol tables, so there would be no ambiguity at the implementation level. However, from the user's perspective, having an entity and an association with the same name is deeply confusing and almost certainly a mistake. The cross-namespace conflict check catches this.

> **Warning:** Cross-namespace conflicts are an error, not a warning. Although the builder *could* resolve the names unambiguously (entity names and association names live in separate dictionaries), allowing the same name in both namespaces would make the MSD file confusing for human readers and error-prone for future maintenance.

Because the builder processes entities before associations, all entity names are already in `entity_names` when associations are checked. This ordering makes the conflict check trivial — a single dictionary lookup.

---

## 10.4 "Did You Mean?" Suggestions via Levenshtein Distance

### The problem of near-misses

When a name cannot be resolved, the raw error message — `unknown entity: 'Tourits'` — is accurate but unhelpful. The user stares at the error, checks their file, and eventually realises they meant `Tourist`. A good semantic analyser should make this connection for them:

```
Error: unknown entity: 'Tourits' (did you mean 'Tourist'?)
```

This "did you mean?" feature turns a frustrating debugging session into an instant fix. It is one of the highest-value-to-effort-ratio improvements you can make to a DSL's error reporting.

### The Levenshtein edit distance

The **Levenshtein distance** between two strings is the minimum number of single-character operations — insertions, deletions, or substitutions — needed to transform one string into the other.

For example, transforming `"Tourits"` into `"Tourist"`:

```
Tourits
     ^   — the 'i' and 't' are swapped compared to 'Tourist'

Step 1: Tourits → Tourists  (insert 's'? No, let's think differently)

Actually:
  T o u r i t s     (source, length 7)
  T o u r i s t     (target, length 7)

Position:  1 2 3 4 5 6 7
Source:    T o u r i t s
Target:    T o u r i s t

Positions 1–5 match. Position 6: 't' vs 's' — substitution.
Position 7: 's' vs 't' — substitution.

Levenshtein distance = 2
```

Two substitutions. The distance is 2, which is close enough to suggest `"Tourist"` as a correction.

### The dynamic programming algorithm

The classic algorithm computes the Levenshtein distance using a dynamic programming matrix. For strings `a` of length `m` and `b` of length `n`, we build an `(m+1) x (n+1)` matrix where cell `(i, j)` holds the edit distance between the first `i` characters of `a` and the first `j` characters of `b`.

MSD uses a space-optimised variant that keeps only two rows of the matrix at a time, reducing space complexity from O(m*n) to O(min(m, n)):

```python
def _levenshtein(a: str, b: str) -> int:
    """Compute Levenshtein edit distance between two strings."""
    if len(a) < len(b):
        return _levenshtein(b, a)
    if not b:
        return len(a)

    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a):
        curr = [i + 1]
        for j, cb in enumerate(b):
            cost = 0 if ca == cb else 1
            curr.append(min(curr[j] + 1, prev[j + 1] + 1, prev[j] + cost))
        prev = curr
    return prev[-1]
```

The algorithm works as follows:

- `prev` holds the previous row of the DP matrix. Initially, `prev = [0, 1, 2, ..., len(b)]`, representing the cost of transforming an empty prefix of `a` into each prefix of `b` (all insertions).

- For each character `ca` in `a`, we build a new row `curr`. The first element is `i + 1` (deleting `i + 1` characters from `a` to get an empty string).

- For each character `cb` in `b`, we compute the minimum of three operations:
  - `curr[j] + 1`: insert `cb` (cost from the cell to the left, plus one)
  - `prev[j + 1] + 1`: delete `ca` (cost from the cell above, plus one)
  - `prev[j] + cost`: substitute (cost from the diagonal, plus 0 if characters match or 1 if they differ)
- After processing all characters of `a`, `prev[-1]` holds the final distance.

The swap `if len(a) < len(b): return _levenshtein(b, a)` ensures that `a` is always the longer string, so `prev` and `curr` are as short as possible.

### The suggestion function

The builder compares the unresolved name against all candidates in the relevant symbol table, returning the closest match within a maximum distance:

```python
def _suggest(name: str, candidates: list, max_distance: int = 3) -> Optional[str]:
    """Find the closest match by Levenshtein distance."""
    best = None
    best_dist = max_distance + 1
    for c in candidates:
        d = _levenshtein(name.lower(), c.lower())
        if d < best_dist:
            best_dist = d
            best = c
    return best if best_dist <= max_distance else None
```

Several design decisions are worth noting:

- **Case-insensitive comparison.** The function compares `name.lower()` against `c.lower()`. This catches cases where the user wrote `student` instead of `Student` — a distance of 0 in case-insensitive mode, but distance 1 in case-sensitive mode.

- **Maximum distance of 3.** Beyond 3 edits, the suggestion is unlikely to be helpful. A distance of 4 between two short names (say, `"Foo"` and `"Barr"`) is meaningless. The threshold of 3 is a practical compromise: it catches common typos (transpositions, missing letters, extra letters) without suggesting wildly different names.

- **Returns the original casing.** Although comparison is case-insensitive, the function returns `c` (the candidate as it was registered), not the lowercased version. The suggestion shows the correct name exactly as it was defined.

### Worked example

Suppose the file contains:

```
entity Tourist {
    *tourist_id: INT
    name: VARCHAR(100)
}

association guided_tour {
}

link Tourits (1,N) guided_tour
```

The builder processes the link, looks up `"Tourits"` in `entity_names`, and finds no match. It then calls `_suggest("Tourits", ["Tourist"])`:

- `_levenshtein("tourits", "tourist")` = 2 (two substitutions at positions 6 and 7)

- 2 <= 3 (the maximum distance), so `"Tourist"` is returned

The error message becomes:

```
schema.msd:9: error: unknown entity: 'Tourits' (did you mean 'Tourist'?)
```

> **Tip:** The Levenshtein distance algorithm is useful far beyond DSL error messages. It appears in spell checkers, DNA sequence alignment, plagiarism detection, and fuzzy search. If you implement it once as a utility function, you will find uses for it throughout your codebase.

> **Programmer:** Go's `go/types.Config.Check()` is the model semantic analyser to study when building your own. It takes a parsed `*ast.Package`, resolves all identifiers to their declarations, type-checks every expression, and returns a `*types.Info` struct populated with the resolved type of every node. The errors it produces are collected into a slice rather than halting at the first failure -- exactly the continue-and-collect pattern MSD uses. For "did you mean?" suggestions, Go's `gopls` language server computes edit distances between unresolved identifiers and in-scope names, surfacing quick-fix suggestions in the IDE. If you implement your DSL's semantic analyser in Go, storing errors in a `[]error` slice (or a custom diagnostic type with position and severity) and collecting all of them before returning gives callers maximum flexibility in how they present the results.

---

## 10.5 Warning vs Error Severity Decisions

### The severity spectrum

Not all problems are equal. Some make the model definitively broken — a link referencing a non-existent entity cannot be resolved, period. Others indicate that something is suspicious but not necessarily wrong — an entity without a primary key might be intentional (perhaps the user plans to add one later).

MSD distinguishes between two severity levels:

- **Error**: the model is definitively wrong. The problem must be fixed before the model can be considered valid. Examples: duplicate names, unknown references, cross-namespace conflicts.

- **Warning**: the model is suspicious but not broken. The user should review the issue but may choose to ignore it. Example: an entity without a primary key.

### Where to draw the line

The decision of whether something is an error or a warning is a design judgement, not a technical one. Here is MSD's classification:

| Problem | Severity | Rationale |
|---------|----------|-----------|
| Duplicate entity name | Error | Link resolution would be ambiguous |
| Duplicate association name | Error | Link resolution would be ambiguous |
| Association name conflicts with entity | Error | Confusing and likely a mistake |
| Unknown entity in link | Error | Cannot create a valid link |
| Unknown association in link | Error | Cannot create a valid link |
| Entity without primary key | Warning | Legal in some modelling scenarios |

The error types correspond to situations where the builder cannot produce a correct result. The warning type corresponds to a situation where the builder *can* produce a result (an entity without a primary key is still a valid `Entity` object) but the result is likely incomplete.

### The design principle

When you are unsure whether something should be an error or a warning, **make it a warning**. Users can always configure their tooling to treat warnings as errors (a common `-Werror` pattern), but they cannot downgrade an error to a warning. Starting strict and relaxing is far harder than starting lenient and tightening — users grow to depend on the lenient behaviour, and promoting a warning to an error becomes a breaking change.

That said, do not make everything a warning out of timidity. If the builder genuinely cannot produce a correct result — if the link would reference a non-existent entity, if two entities would collide — that must be an error. Reserve warnings for cases where the output is technically valid but likely incomplete or surprising.

---

## 10.6 MSD Builder: Complete Walkthrough

Let us trace the builder's execution on a complete MSD file. Consider the following input:

```
project {
    name: University Enrolment
    author: Dr. H
}

entity Student {
    *student_id: INT
    name: VARCHAR(100)
    email: VARCHAR(255)
}

entity Course {
    *course_id: INT
    title: VARCHAR(200)
    credits: SMALLINT
}

association enrolment {
    enrolled_on: DATE
    grade: DECIMAL(4)
}

link Student (0,N) enrolment
link Course (0,N) enrolment
```

The parser produces a `ParseResult` containing two `ParsedEntity` objects, one `ParsedAssociation`, two `ParsedLink` objects, and a `ParsedMetadata`. Assuming no parse errors, `parse_result.errors` is empty.

### Step 1: Collect existing errors

```python
errors: List[MSDError] = list(parse_result.errors)
```

The builder starts by copying the parser's errors into its own list. This is important: the parser may have emitted warnings (for example, about an unknown project property), and those should propagate through to the final error list. By starting with the parser's errors, the builder ensures that the returned error list is comprehensive — it contains issues from *every* stage of processing.

### Step 2: Apply metadata

```python
if parse_result.metadata:
    m = parse_result.metadata
    if m.name:
        project.name = m.name
    if m.author:
        project.author = m.author
    if m.description:
        project.description = m.description
```

The builder applies the project metadata. Each field is only overwritten if the parsed value is non-empty, preserving the `Project` class's defaults (`"Untitled Project"`, etc.) for missing fields.

### Step 3: Build entities

The builder iterates over `parse_result.entities`:

1. **`Student`**: not in `entity_names`, so proceed. Create an `Entity(name="Student")` — this automatically generates a UUID via the dataclass default factory. Build each `ParsedAttribute` into an `Attribute` object and add it to the entity. Check for a primary key: `student_id` is marked as primary, so `has_pk` is `True`. Register `"Student"` in `entity_names`. Add the entity to the project.

2. **`Course`**: not in `entity_names`, so proceed. Same process. UUID generated, attributes built, primary key found. Registered and added.

After this step:
- `entity_names = {"Student": Entity(...), "Course": Entity(...)}`
- No errors or warnings produced.

### Step 4: Build associations

The builder iterates over `parse_result.associations`:

1. **`enrolment`**: not in `assoc_names` (no duplicate). Not in `entity_names` (no cross-namespace conflict). Create an `Association(name="enrolment")` with a fresh UUID. Build the carrying attributes (`enrolled_on`, `grade`). Register in `assoc_names`. Add to the project.

After this step:
- `assoc_names = {"enrolment": Association(...)}`
- No errors produced.

### Step 5: Build links

The builder prepares candidate lists for suggestions:

```python
all_entity_names = list(entity_names.keys())   # ["Student", "Course"]
all_assoc_names = list(assoc_names.keys())      # ["enrolment"]
```

Then it iterates over `parse_result.links`:

1. **`link Student (0,N) enrolment`**: look up `"Student"` in `entity_names` — found. Look up `"enrolment"` in `assoc_names` — found. Create a `Link` with `entity_id=student_entity.id`, `association_id=enrolment_assoc.id`, `cardinality_min="0"`, `cardinality_max="N"`. Add to the project.

2. **`link Course (0,N) enrolment`**: look up `"Course"` — found. Look up `"enrolment"` — found. Create and add the link.

Both links resolve successfully. No errors.

### Step 6: Auto-layout

Finally, the builder runs the automatic layout algorithm on all entities and associations, positioning them on the canvas:

```python
if all_entities or all_associations:
    auto_layout(all_entities, all_associations, layout_links)
```

The layout algorithm (covered in Chapter 12) assigns `x` and `y` coordinates to each entity and association, producing a visually sensible initial arrangement. The builder then marks the project as unmodified (`project.modified = False`) and returns it along with the (empty) error list.

### The complete return

```python
return project, errors
```

The caller receives a fully populated `Project` containing two entities, one association, and two links — all connected by UUIDs, all with layout coordinates, and all validated. The error list is empty, indicating a clean build.

Had there been errors — say, a duplicate entity or an unresolved link — the project would still be returned with whatever could be built successfully. The error list would contain the problems, and the caller (whether CLI or GUI) would decide how to present them.

> **Info:** The builder's "always return a project" policy is a deliberate design choice. In a GUI context, showing a partially valid model with errors highlighted is far more useful than showing nothing. In a CLI context, the caller can check `len(errors) > 0` and exit with a non-zero status code if strict validation is required.

---

## 10.7 Exercises

**Exercise 10.1 — Levenshtein distance by hand.** Compute the Levenshtein distance between `"Tourist"` and `"Tourits"` by hand. Draw the full (8 x 8) dynamic programming matrix, filling in each cell with the minimum cost. Verify that the final cell contains the value 2. Identify which two operations (insertion, deletion, or substitution) are performed along the optimal path.

**Exercise 10.2 — "Did you mean?" for data types.** Implement a "did you mean?" system for data type names in the parser. If a user writes `entity Foo { name: STRIG }`, the error message should suggest `VARCHAR` or `TEXT` or whichever valid type is closest. What maximum Levenshtein distance would you use for data type names, given that most type names are short (3--9 characters)? Justify your choice.

**Exercise 10.3 — Single-pass semantic analysis.** MSD allows forward references because the builder processes entities and associations before links, regardless of source order. Design a semantic analyser that does *not* allow forward references — one that processes constructs in the order they appear in the file, in a single pass. What new error messages would you need? How would the user documentation change? Give an example of an MSD file that is valid under the current builder but would be rejected by your single-pass analyser.

**Exercise 10.4 — Association connectivity rule.** Add a new semantic rule to the builder: every association must be connected by at least two links. After all links have been built, iterate over the associations and check that each one has at least two links referencing it. Should this be an error or a warning? Implement the validation and write three test cases: one that passes, one that fails with zero links, and one that fails with exactly one link.

**Exercise 10.5 — Duplicate attribute detection.** MSD currently does not check for duplicate attribute names within an entity or association. Add this check to the builder. When a duplicate is found, report an error including the name of the owning entity or association, the duplicate attribute name, and the line number. Should the builder skip the duplicate attribute or keep both? Argue your design choice.

**Exercise 10.6 — Orphan entity detection.** An orphan entity is one that is not connected to any association via a link. Add a post-build check that reports orphan entities. Should this be an error or a warning? Consider the user experience: a student building a model incrementally will often have orphan entities during development. How does this affect your severity choice?

**Exercise 10.7 — Bidirectional conflict detection.** MSD currently checks whether an association name conflicts with an entity name, but not the reverse — if an entity is defined *after* an association with the same name, the entity would be registered first (because entities are processed before associations) and the association would be caught by the cross-namespace check. Convince yourself that this is correct by tracing the builder's execution with a file where both `entity Booking { ... }` and `association Booking { }` are defined. Then consider: what would happen if the builder processed associations before entities? Would the conflict still be detected? Why or why not?
