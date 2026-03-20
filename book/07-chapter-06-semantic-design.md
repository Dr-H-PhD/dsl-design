\newpage

# Chapter 6: Semantic Design

Chapters 4 and 5 addressed how a DSL's input is broken into tokens and assembled into structure. A lexer can tell you that `VARCHAR` is a valid identifier. A parser can tell you that `name: VARCHAR(100)` is a well-formed attribute declaration. But neither can tell you whether `VARCHAR` is a legitimate data type, whether `100` is a sensible size for it, or whether the entity containing this attribute has already been declared under the same name. These questions belong to the **semantic** layer — the layer that assigns *meaning* to syntactically valid programs.

This chapter examines the design decisions that shape a DSL's semantics: type systems, name binding, reference resolution, uniqueness rules, validation constraints, and error message quality. We continue to use MSD as our primary case study, drawing comparisons with SQL, Terraform, and other DSLs where they illuminate a general principle.

## 6.1 Beyond Syntax: What Makes a Program Meaningful

A grammar defines what *shapes* are legal. Semantics defines what those shapes *mean*. The distinction is easy to state in the abstract, but its practical consequences are profound. Consider this MSD fragment:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}

link Student (0,N) Studnt
```

The parser will accept this without complaint. The `link` statement has the correct structure: an identifier, a cardinality in parentheses, and another identifier. Syntactically, it is flawless. Semantically, it is broken — there is no association called `Studnt`. The user almost certainly meant to write the name of an association that exists elsewhere in the file, but a parser that works purely on structure has no way to know this.

This is the fundamental job of the semantic layer: to bridge the gap between *what the user wrote* and *what the tool should do*. The parser produces an intermediate representation — a faithful record of the input's structure. The semantic analyser examines that structure and asks: does it make sense?

Semantic analysis typically involves several concerns:

1. **Type checking** — are values of the right kind?
2. **Name resolution** — do referenced names actually exist?
3. **Uniqueness enforcement** — are declarations distinct where they must be?
4. **Constraint validation** — are domain-specific rules satisfied?
5. **Error reporting** — when something is wrong, can we explain it clearly?

In a general-purpose language like Java, the semantic layer is vast: type inference, method overload resolution, generic type bounds, access control, definite assignment analysis. In a DSL, the semantic layer is smaller but no less important. A DSL that catches errors early and explains them well is a pleasure to use; one that silently produces wrong output is dangerous.

## 6.2 Type Systems for DSLs

### Why DSLs Need Types

Even the simplest DSLs have types, though they may not call them that. A Dockerfile's `EXPOSE` instruction expects a port number, not an arbitrary string. A Makefile's target name is a filename, not a shell command. Whenever a language restricts what values are valid in a given context, it has a type system — even if it is implicit.

Making types explicit in a DSL serves three purposes:

- **Validation**: the tool can reject invalid input before it causes downstream failures.

- **Documentation**: the type annotations tell the user what is expected, even without reading a manual.

- **Code generation**: the type information drives output. MSD translates `INT` into `INTEGER` in PostgreSQL DDL; it cannot do this without knowing the type.

### Simple Types

The most basic type system is a fixed enumeration of type names. MSD defines 13 data types:

```
INT, BIGINT, SMALLINT
VARCHAR, CHAR, TEXT
BOOLEAN
DATE, TIME, TIMESTAMP
DECIMAL, FLOAT, DOUBLE
```

This is a **closed set** — the user cannot define new types. Every attribute in an MSD file must use one of these names (case-insensitively). If the user writes `BLOB`, the parser rejects it immediately and lists the valid alternatives. This design is deliberate: MSD targets PostgreSQL, and supporting only types that map cleanly to PostgreSQL DDL avoids ambiguity in code generation.

Compare this with Terraform, which has a richer but still finite type system: `string`, `number`, `bool`, `list(type)`, `map(type)`, `set(type)`, and `object({...})`. Terraform's types are composable — you can nest them — but the base set is still closed.

### Enumerated Types

Some DSL values are not data types in the traditional sense but are drawn from a fixed set nonetheless. MSD cardinalities are an example. A cardinality minimum must be `0` or `1`; a cardinality maximum must be `1` or `N`. These are enumerated values, and MSD validates them during parsing:

```
link Student (3,N) Enrol
```

This is rejected with: `invalid minimum cardinality: '3' (expected 0 or 1)`. The parser does not need a type system in the academic sense to enforce this — a simple membership check suffices — but the principle is the same: values are constrained to a known set.

### Parameterised Types

Some types accept arguments that refine their meaning. In MSD, `VARCHAR` requires a size parameter, `CHAR` accepts one, and `DECIMAL` accepts a precision:

```
entity Product {
    *product_id: INT
    name: VARCHAR(255)
    sku: CHAR(12)
    price: DECIMAL(10)
}
```

MSD distinguishes between types that accept sizes (`VARCHAR`, `CHAR`, `DECIMAL`) and those that do not. Writing `INT(10)` triggers a warning: `data type 'INT' does not accept a size parameter`. This is a *parameterised type system* — not in the sense of Java generics, but in the sense that certain type constructors take arguments.

SQL follows the same pattern: `VARCHAR(n)`, `NUMERIC(p,s)`, `CHAR(n)`. The parallel is intentional — MSD's type system mirrors the subset of SQL that its users already know.

### When to Validate Types

A key design decision is *when* type validation occurs. There are two common strategies:

- **Parse-time validation**: check types as they are parsed. This is MSD's approach — an unknown type like `BLOB` causes an immediate error, and parsing of that attribute aborts via panic-mode recovery.

- **Build-time validation**: accept any identifier as a type during parsing and validate it later, during semantic analysis. This is more flexible — it allows type aliases or user-defined types — but delays error reporting.

MSD chose parse-time validation because its type set is closed and small. There is no benefit to deferring the check, and rejecting early means the error message can point precisely at the offending token.

> **Tip:** If your DSL has a fixed set of types, validate them during parsing. If users can define their own types, you must defer validation to a later pass, because the type definition may appear after its first use.

## 6.3 Name Binding and Scoping Rules

### Names Are the Glue

Every non-trivial language uses names to refer to things. In MSD, entities have names, associations have names, attributes have names, and links refer to entities and associations by name. The rules governing how names are declared, how they are looked up, and where they are visible constitute the language's **scoping rules**.

### Flat Scope

The simplest scoping model is **flat scope**: all names live in a single global namespace, and every name is visible everywhere. This is MSD's model. There is no nesting of entity definitions inside other entities, no modules, no imports. If you declare an entity called `Student`, that name is available throughout the entire file.

SQL tables follow the same model within a schema — all table names are globally visible, and any table can reference any other table in a foreign key constraint.

Flat scope has the virtue of simplicity. The user never needs to think about which names are "in scope" — everything is. The cost is that name collisions are more likely, because there is only one namespace to hold everything.

### Block Scope and Lexical Scope

For contrast, consider how other languages handle scope:

- **Block scope** (C, Java): names declared inside a `{ ... }` block are local to that block. A variable declared inside a `for` loop is invisible outside it.

- **Lexical scope** (Python, JavaScript): nested blocks can see names from their enclosing blocks, but not vice versa. An inner function can read variables from the outer function that defined it.

These models are more powerful but more complex. A DSL designer should adopt them only when the domain genuinely requires nested definitions. A configuration language for infrastructure (like Terraform's `resource` blocks) benefits from block scope because resources are naturally grouped. A data modelling language like MSD, where everything is inherently global, does not.

### MSD's Scoping Model

MSD uses three separate flat namespaces:

1. **Entity names** — each entity must have a unique name.

2. **Association names** — each association must have a unique name, and must not collide with any entity name.

3. **Attribute names** — attributes are scoped to their enclosing entity or association. Two different entities may each have an attribute called `name` without conflict, but a single entity may not have two attributes called `name`.

This is a pragmatic middle ground. The global namespaces for entities and associations ensure that link references are unambiguous. The entity-local namespace for attributes avoids needless uniqueness constraints on common attribute names like `id`, `name`, or `date`.

> **Note:** MSD's cross-namespace uniqueness rule (associations cannot share names with entities) is a deliberate design choice, not a technical necessity. It ensures that every identifier in a `link` statement can be resolved unambiguously without needing the parser to know whether the target is an entity or an association. We explore the trade-offs of this decision in Section 6.5.

## 6.4 Reference Resolution and Forward References

### What Is a Reference?

A **reference** is the use of a name that was defined elsewhere. In MSD, the `link` statement contains two references — one to an entity and one to an association:

```
link Student (0,N) Enrol
```

Here, `Student` refers to an entity defined in an `entity Student { ... }` block, and `Enrol` refers to an association defined in an `association Enrol { ... }` block. The semantic analyser must *resolve* these names — that is, it must find the actual entity and association objects that the names refer to.

### The Forward Reference Problem

Consider this MSD file:

```
link Student (0,N) Enrol

entity Student {
    *student_id: INT
    name: VARCHAR(100)
}

association Enrol {
    enrolment_date: DATE
}
```

The `link` statement appears *before* the `entity` and `association` declarations it references. This is a **forward reference** — a use of a name before its definition. Should the language allow this?

There are two common strategies:

- **Single-pass, reject forward references**: process the file top to bottom, and if a name is used before it is declared, report an error. This is simple to implement but forces the user to arrange declarations in dependency order, which can be tedious.

- **Multi-pass, collect then resolve**: first pass collects all declarations; second pass resolves all references. Forward references work naturally because all names are known before resolution begins.

MSD uses the multi-pass approach. The parser's job is to collect all declarations — entities, associations, links — into a `ParseResult` intermediate representation. The builder then processes this intermediate representation, first registering all entity and association names, then resolving link references against the complete set of known names. This is why the parser produces `ParsedEntity`, `ParsedAssociation`, and `ParsedLink` data classes rather than final model objects — the intermediate representation exists precisely to enable multi-pass processing.

The benefit is clear: the user can write MSD files in whatever order feels natural. The `link` statements can appear before, after, or interleaved with the entity and association declarations they reference.

> **Info:** The two-phase design (parse, then build) is a common pattern in language implementation. Compilers call it "declaration before use" vs "use before declaration." Languages like C require declaration before use (hence forward declarations for functions). Languages like Java and Python allow use before declaration within the same file. For DSLs, allowing forward references is almost always the friendlier choice — it avoids forcing users to think about declaration order.

### Resolution in Practice

MSD's builder resolves references with a straightforward dictionary lookup. After building all entities and associations, it maintains two dictionaries: `entity_names` mapping names to `Entity` objects, and `assoc_names` mapping names to `Association` objects. For each parsed link, it looks up the entity name in `entity_names` and the association name in `assoc_names`. If either lookup fails, it reports an error — and, as we shall see in Section 6.7, suggests a correction.

In SQL, reference resolution follows a similar pattern. A `FOREIGN KEY` clause references a table by name, and the database engine must verify that the referenced table exists. The difference is that SQL operates on a persistent catalogue of known tables, whereas MSD resolves everything within a single file.

## 6.5 Uniqueness and Conflict Rules

### Duplicate Declarations

What should happen when two declarations share the same name? In MSD, the answer is straightforward: it is an error.

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

The builder rejects this with `duplicate entity name: 'Student'`. The second declaration is skipped, and any links referencing `Student` will resolve to the first declaration. This is a **first-wins** strategy: the first declaration of a name "owns" it.

Alternative strategies exist:

- **Last-wins**: the second declaration silently replaces the first. CSS follows this model — later rules override earlier ones. This is useful for languages where overriding is a feature, but it can mask errors.

- **Merge**: the two declarations are combined. Protocol Buffers allows extending message types across files. This is powerful but complex.

- **Namespace**: allow duplicate names in different namespaces. Java allows a class and a package to share a name because they occupy different namespaces.

For MSD, strict uniqueness with an error on duplicates is the right choice. A data model with two entities named `Student` is almost certainly a mistake, not an intentional override.

### Cross-Namespace Conflicts

MSD goes further: an association may not have the same name as an entity.

```
entity Enrol {
    *id: INT
}

association Enrol {
    date: DATE
}
```

This produces: `association name 'Enrol' conflicts with an entity of the same name`. The rule exists to ensure that every name appearing in a `link` statement can be resolved unambiguously. Without this rule, the name `Enrol` in a link could refer to either the entity or the association, and the tool would need additional context (or syntax) to distinguish them.

This is a design trade-off. Terraform, for instance, allows a `resource` and a `data` source to share the same logical name because they are distinguished by their block type (`resource "aws_instance" "web"` vs `data "aws_instance" "web"`). MSD could have adopted a similar scheme — perhaps `link Student (0,N) association:Enrol` — but the added syntax complexity was not justified for the domain.

> **Warning:** Cross-namespace conflicts are easy to overlook during design. If your DSL has multiple kinds of named things (types, variables, functions, modules), decide early whether names must be globally unique or only unique within their kind. Ambiguous resolution rules will confuse users and complicate your implementation.

## 6.6 Validation Rules and Constraint Checking

### Beyond the Grammar

Many rules that a DSL must enforce cannot be expressed in a context-free grammar. Grammars describe structure; they cannot count, compare, or look things up in a symbol table. The rules that remain after parsing are **semantic constraints**, and they form the heart of the semantic layer.

### MSD's Semantic Validations

MSD enforces the following semantic rules, each checked in the builder:

| Rule | Severity | Stage |
|------|----------|-------|
| Duplicate entity name | Error | Build |
| Duplicate association name | Error | Build |
| Entity/association name conflict | Error | Build |
| Unknown entity in link | Error | Build |
| Unknown association in link | Error | Build |
| Entity without primary key | Warning | Build |
| Unknown data type | Error | Parse |
| Invalid cardinality value | Error | Parse |
| Size on non-sized type | Warning | Parse |

Notice that some validations occur during parsing (types, cardinalities) while others occur during building (names, references). The division follows a simple principle: validate *locally* during parsing (a type is valid or not, independent of anything else in the file) and validate *relationally* during building (a reference is valid only if the referenced name exists).

### Hard Constraints vs Soft Constraints

MSD distinguishes between **errors** and **warnings**:

- **Errors** indicate that the input is definitely wrong and the tool cannot produce correct output. A link referencing a non-existent entity is an error — the tool cannot generate SQL for a foreign key to a table that does not exist.

- **Warnings** indicate that the input is probably wrong but the tool can still proceed. An entity without a primary key is a warning — the tool can still generate a CREATE TABLE statement (though it will lack a PRIMARY KEY clause), and some modelling scenarios genuinely omit primary keys during early design.

The classification matters for tooling. MSD's CLI uses exit code 1 for errors and exit code 0 for warnings, allowing CI pipelines to distinguish between fatal problems and advisory notices. The GUI displays errors in red and warnings in amber.

### The Error Budget

How many validations should a DSL enforce? There is no universal answer, but a useful heuristic is the **error budget**: each validation you add has a cost (implementation complexity, maintenance burden, potential for false positives) and a benefit (catching user mistakes). Add validations where the benefit clearly outweighs the cost.

MSD's builder enforces nine validations — a modest number, but each one catches a common and consequential mistake. A more complex DSL might enforce dozens. Terraform, for example, validates resource types against provider schemas, checks variable type constraints, detects dependency cycles, and warns about deprecated features — easily hundreds of distinct checks.

The key is to prioritise. Start with the validations that catch the most common mistakes and the most dangerous ones (those that produce silently wrong output). Add more as users report confusion or bugs.

## 6.7 Error Messages as a Design Concern

### Error Messages Are User Interface

If your DSL's error messages are an afterthought, your DSL's user experience is an afterthought. For many users, error messages are the primary way they learn the language. A clear error message that explains what went wrong and how to fix it is worth more than a page of documentation.

### Principles of Good Error Messages

A well-designed error message is:

1. **Specific**: it identifies exactly what is wrong. Not "invalid input" but "unknown data type: 'BLOB'."

2. **Located**: it points to where the problem is. MSD errors include the filename, line number, and column number — enough for any editor to jump to the exact location.

3. **Actionable**: it tells the user what to do. Listing valid types after rejecting an unknown one gives the user everything they need to fix the problem without consulting a reference manual.

4. **Contextual**: it shows what was expected alongside what was found. "Expected IDENTIFIER, got RBRACE ('}')" tells the user that a closing brace appeared where a name was expected — suggesting a missing attribute or an extra brace.

### Anti-Patterns

Common error message anti-patterns include:

- **"Syntax error"** — tells the user nothing about what is actually wrong.
- **"Error at line 7"** — locates the problem but does not describe it.

- **"E0042"** — error codes without explanations require the user to look up the code in a separate document.

- **"Invalid token"** — too vague. Which token? Why is it invalid? What should it be?

### MSD's Error Message Design

MSD's error messages follow a consistent pattern: `<location>: <severity>: <description>`. For example:

```
schema.msd:12: error: unknown data type: 'BLOB' (valid types: BIGINT, BOOLEAN,
    CHAR, DATE, DECIMAL, DOUBLE, FLOAT, INT, SMALLINT, TEXT, TIME, TIMESTAMP,
    VARCHAR)
```

This message is specific (it names the offending type), located (file and line), and actionable (it lists every valid alternative). The user can fix the problem without leaving their editor.

For reference resolution failures, MSD goes a step further:

```
schema.msd:24: error: unknown entity: 'Tourits' (did you mean 'Tourist'?)
```

The suggestion is computed using **Levenshtein distance** — the minimum number of single-character edits (insertions, deletions, substitutions) needed to transform one string into another. MSD's implementation compares the unknown name against all known entity names (case-insensitively) and suggests the closest match, provided the distance is at most 3.

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

The threshold of 3 is a pragmatic choice. A distance of 1 catches single-character typos (the most common case). A distance of 2 catches transpositions and double typos. A distance of 3 extends to slightly more garbled names. Beyond 3, suggestions become unreliable — the "closest" match may bear little resemblance to the intended name, and a misleading suggestion is worse than no suggestion at all.

### When to Stop Processing

A final error message design question: when an error is detected, should the tool stop immediately or continue and report additional errors?

MSD takes a **continue-and-collect** approach. The parser uses panic-mode recovery to skip past errors and resume parsing at the next well-defined boundary (a top-level keyword or a closing brace). The builder processes all declarations even when some fail. The result is that a single invocation can report multiple errors:

```
schema.msd:5: error: duplicate entity name: 'Student'
schema.msd:12: error: unknown entity: 'Tourits' (did you mean 'Tourist'?)
schema.msd:15: warning: entity 'Module' has no primary key
```

This is far more useful than stopping at the first error. A user fixing a file with three problems would otherwise need three separate edit-run cycles to discover them all. Multi-error reporting respects the user's time.

The trade-off is complexity. After an error, the tool's state may be partially invalid, and subsequent errors may be *cascading* — caused not by real problems in the input but by the incomplete state left by the first error. MSD mitigates this by skipping the offending declaration entirely (using `continue` after recording a duplicate name error, for instance), so that subsequent processing does not attempt to use the broken declaration.

> **Tip:** Design your error messages before you implement your semantic analyser. Write down the exact text you want users to see for each kind of mistake. This forces you to think about what information you need to include and ensures consistency across all your error paths.

## 6.8 Exercises

**Exercise 6.1** — Consider the following MSD fragment:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
    name: VARCHAR(200)
}
```

Should MSD reject duplicate attribute names within the same entity? What are the arguments for treating this as an error vs a warning? If it is an error, should the first or second declaration win?

**Exercise 6.2** — MSD uses Levenshtein distance with a maximum of 3 to suggest corrections for unknown names. What are the trade-offs of this threshold? Give an example where a maximum distance of 3 produces a misleading suggestion. Give an example where a maximum distance of 1 would fail to suggest a useful correction.

**Exercise 6.3** — Should MSD allow an entity and an association to have the same name? Argue *for* this change (what flexibility does it add?) and argue *against* it (what problems does it create?). If you allowed it, how would the `link` statement syntax need to change to remain unambiguous?

**Exercise 6.4** — Design the semantic rules for a DSL that describes board game rules. The language allows defining **spaces** (with names and types like "property", "chance", "tax"), **cards** (with effects like "move to space X" or "pay Y"), and **rules** (like "if a player lands on an unowned property, they may buy it"). What names need to be unique? What cross-references need to be resolved? What should be an error vs a warning?

**Exercise 6.5** — Terraform allows forward references: a resource can refer to another resource that is defined later in the file. Terraform resolves this by building a dependency graph and processing resources in topological order. Compare this approach to MSD's two-pass strategy (parse, then build). What are the advantages and disadvantages of each? In what situations would topological ordering be necessary but two-pass resolution would not suffice?

**Exercise 6.6** — Consider adding an `import` statement to MSD that allows one `.merisio` file to reference entities defined in another file:

```
import "shared_types.msd"

link Student (0,N) Enrol
```

What new semantic rules would this feature require? How would it affect name resolution, duplicate detection, and error reporting? What scoping model would you choose — all imported names are global, or imported names must be qualified (e.g., `shared_types.Student`)?

**Exercise 6.7** — Rewrite the following error messages to follow the principles described in Section 6.7. For each, explain what information was missing and what you added.

1. `Error: bad type`
2. `Line 14: syntax error`
3. `E0017: validation failed`
4. `Unknown reference on line 9`

---
