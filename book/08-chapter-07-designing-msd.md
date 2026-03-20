\newpage

# Chapter 7: Designing MSD

The previous four chapters gave us a systematic framework for designing domain-specific languages: domain analysis to identify what concepts the language must express, lexical design to choose tokens, syntactic design to arrange tokens into structures, and semantic design to give those structures meaning. Each chapter explored one layer in isolation.

Now we bring all four layers together. This chapter applies the entire design process to a single, real problem: creating **MSD** (Merisio Schema Definition), a text-based language for MERISE conceptual data models. By the end, we will have a complete language specification — every keyword chosen, every grammar rule written, every semantic constraint defined — ready to be implemented in Part III.

## 7.1 Applying the Design Process

Chapters 3 through 6 established a four-stage design process:

1. **Domain analysis** (Chapter 3): Identify the concepts, relationships, and constraints in the target domain. Produce a domain vocabulary table mapping concepts to language constructs.

2. **Lexical design** (Chapter 4): Choose keywords, identifier rules, comment syntax, and symbolic tokens. Decide on case sensitivity. Handle context-sensitive scanning where necessary.

3. **Syntactic design** (Chapter 5): Arrange tokens into grammatical structures. Write the grammar in EBNF. Ensure the grammar is unambiguous and parseable by a recursive descent parser.

4. **Semantic design** (Chapter 6): Define what the syntactic structures mean. Establish type systems, naming rules, reference resolution, and validation constraints. Design error messages.

These stages are not strictly sequential. Design decisions at one layer influence the others — a choice of keyword at the lexical layer shapes the grammar, and a semantic constraint may require syntactic support. In practice, the designer iterates between layers, refining each as the language takes shape.

For MSD, our goal is specific: design a DSL that Merisio can **parse** into an intermediate representation, **validate** against MERISE modelling rules, **lay out** as a visual diagram, and **import** into a graphical project. The language must be human-writable in a text editor, machine-parseable without ambiguity, and expressive enough to capture any valid MERISE conceptual data model.

## 7.2 Domain Analysis: MERISE Conceptual Data Modelling

### The Domain

MERISE is a database design methodology widely used in French computer science education and industry. Its first artefact is the **MCD** (Modele Conceptuel de Donnees) — a conceptual data model that describes the information structure of a system without reference to any particular database technology.

An MCD contains three kinds of elements:

- **Entities**: real-world objects or concepts with attributes. Each entity has a name and one or more attributes, at least one of which is a primary key. For example, a `Student` entity might have attributes `student_id` (primary key), `first_name`, `last_name`, and `date_of_birth`.

- **Associations**: named relationships between entities. An association may carry its own attributes — data that belongs to the relationship itself rather than to either entity. For example, an `enrolled_in` association between `Student` and `Course` might carry a `grade` attribute.

- **Links**: connections between entities and associations, annotated with **cardinalities**. A cardinality is a pair (min, max) that specifies how many times an entity can participate in an association. The four valid cardinalities in MERISE are (0,1), (0,N), (1,1), and (1,N).

### Domain Vocabulary Table

The first concrete output of domain analysis is a mapping from domain concepts to language constructs. For MSD:

| Domain Concept | Language Construct | Example |
|---|---|---|
| Entity | `entity` block | `entity Student { ... }` |
| Association | `association` block | `association enrolled_in { ... }` |
| Link with cardinality | `link` statement | `link Student (0,N) enrolled_in` |
| Attribute | Name-type pair inside a block | `first_name: VARCHAR(100)` |
| Primary key | `*` prefix on attribute | `*student_id: INT` |
| Data type | Type name after `:` | `VARCHAR`, `INT`, `DATE` |
| Project metadata | `project` block | `project { name: My Project }` |

This table is the bridge between the domain expert's vocabulary and the language designer's constructs. Every domain concept has exactly one corresponding language construct, and every language construct maps back to a domain concept. There is no construct without a purpose.

### Domain Constraints

Beyond the vocabulary, the domain imposes constraints that the language must enforce:

- **Unique names**: No two entities may share a name. No two associations may share a name. No entity and association may share a name.

- **Valid cardinalities**: The minimum must be 0 or 1. The maximum must be 1 or N. This gives exactly four valid cardinalities: (0,1), (0,N), (1,1), (1,N).

- **Valid data types**: Attributes must have types drawn from a fixed set of database-oriented types.

- **Entity completeness**: Every entity must have at least one attribute (an entity with no attributes has no reason to exist).

- **Link validity**: Every link must reference an existing entity and an existing association.

> **Note:** The domain analysis does not prescribe *how* these constraints are enforced — only *what* they are. Whether a missing primary key is an error or a warning, for instance, is a semantic design decision made later.

## 7.3 Lexical Choices

With the domain analysis complete, we turn to the lexical layer: what tokens will MSD use, and what rules govern them?

### Keywords

MSD has exactly four keywords, one for each top-level domain concept:

- `project` — introduces a metadata block
- `entity` — introduces an entity definition
- `association` — introduces an association definition
- `link` — introduces a link statement

Four keywords is remarkably few. SQL has over a hundred. Even Dockerfile has seventeen. A small keyword count is a sign that the language is well-scoped — each keyword carries significant weight.

### Case-Insensitive Keywords

MSD keywords are **case-insensitive**: `entity`, `Entity`, `ENTITY`, and `eNtItY` are all recognised as the entity keyword. This was a deliberate decision influenced by the domain.

Database professionals are the primary audience for MSD. They are accustomed to SQL, where `SELECT`, `select`, and `Select` are equivalent. Making keywords case-insensitive respects this expectation. A user who habitually writes `ENTITY` or `Entity` should not receive an error.

The alternative — case-sensitive keywords like most programming languages — was considered and rejected. Programming language conventions (lowercase keywords) conflict with SQL conventions (uppercase keywords), and choosing one would frustrate users accustomed to the other.

### Case-Sensitive Identifiers

While keywords are case-insensitive, **identifiers are case-sensitive**: `Student` and `student` are different names. This follows programming language convention rather than SQL convention, and the reasoning is practical.

Entity and association names in MSD flow directly into SQL table names during code generation. If the user writes `Student`, the generated table should be `Student`, not `student` or `STUDENT`. Preserving the original casing requires case-sensitive identifiers.

> **Tip:** When a DSL bridges two domains with conflicting conventions (SQL's case-insensitivity and programming's case-sensitivity), apply each convention where it makes the most sense: case-insensitive for the part that resembles one domain (keywords), case-sensitive for the part that resembles the other (identifiers).

### The `*` Prefix for Primary Keys

Primary key attributes are marked with a `*` prefix: `*student_id: INT`. This notation was borrowed from entity-relationship diagram conventions, where primary key attributes are traditionally underlined or marked with a special symbol.

The asterisk was chosen over alternatives for several reasons:

- **Brevity**: A single character, versus a keyword like `primary` or `pk`

- **Visual distinctiveness**: The `*` stands out at the beginning of a line, making primary keys easy to spot when scanning a file

- **Convention**: ER diagrams and many database design tools use `*` or a similar marker

- **Composability**: Multiple attributes can be marked as primary key for composite keys — simply prefix each with `*`

The alternative of a `primary key` keyword was rejected because it would require either a keyword pair (complicating the grammar) or a special attribute modifier syntax. The `*` prefix keeps the grammar simple: an attribute is optionally preceded by `*`, and that is all.

### Comment Syntax

MSD supports two comment styles:

- `#` — single-line comment (everything after `#` to end of line is ignored)
- `//` — single-line comment (everything after `//` to end of line is ignored)

Supporting both styles was a deliberate choice. The `#` comment is standard in data-oriented formats (YAML, TOML, shell scripts, Python) and will feel natural to users working with configuration files. The `//` comment is standard in C-family programming languages and will feel natural to developers. Since MSD's audience includes both database designers and software developers, supporting both styles avoids forcing either group to adopt an unfamiliar convention.

Block comments (`/* ... */`) were considered and rejected. MSD files are typically short (tens to low hundreds of lines), and single-line comments suffice. Block comments introduce lexical complexity (nesting, unterminated comments) with little practical benefit.

### Context-Sensitive Colon

The colon `:` serves different roles in different contexts. Inside an `entity` or `association` block, it separates an attribute name from its type:

```
first_name: VARCHAR(100)
```

Inside a `project` block, it separates a metadata key from a free-form value:

```
name: School Management System
```

In the second case, the value `School Management System` contains spaces and is not a single identifier. Rather than requiring quotation marks — which would be unfamiliar to users and add lexical complexity — MSD uses **context-sensitive lexing**: when the lexer encounters a `:` inside a `project` block, it captures the entire remainder of the line (stripped of leading whitespace and trailing comments) as a single string value token.

This means the following works without any quoting:

```
project {
    name: My Database Project with Spaces
    author: Dr. H
    description: A model for the university registration system
}
```

The lexer tracks brace depth and a flag (`in_project_block`) to know when to apply this rule. This is a small amount of lexer state, but it eliminates the need for string literal syntax — a significant simplification for both the grammar and the user experience.

### Token Summary

The complete set of token types in MSD:

| Category | Tokens |
|---|---|
| Keywords | `PROJECT`, `ENTITY`, `ASSOCIATION`, `LINK` |
| Symbols | `{`, `}`, `(`, `)`, `:`, `,`, `*` |
| Literals | `IDENTIFIER`, `INTEGER`, `STRING_VALUE` |
| Structural | `NEWLINE`, `EOF` |

Fourteen token types in total. For comparison, a typical programming language lexer handles 40–60 token types. MSD's small token vocabulary is a direct consequence of its narrow domain scope.

## 7.4 Syntactic Choices

### Block Structure

MSD uses a block structure with curly braces to group related declarations:

```
entity Student {
    *student_id: INT
    first_name: VARCHAR(100)
}
```

Braces were chosen over indentation-based grouping (Python-style) for a practical reason: indentation sensitivity is fragile in copy-paste scenarios. A user pasting an entity definition from a web page or an email may lose its indentation, turning valid MSD into a parse error. Braces are explicit and survive formatting changes.

The block keyword (`entity`, `association`, `project`) appears before the opening brace, followed by the block name (for entities and associations) or nothing (for project). This follows the pattern established by C, Java, Go, and CSS — a familiar structure that requires no explanation.

### Attribute Syntax

Attributes use a name-colon-type pattern:

```
[*]name: TYPE[(size)]
```

This reads like a type annotation in TypeScript, Python, or Kotlin: the name comes first, then a colon, then the type. It is more natural for reading than the C-style alternative (`TYPE name`) because the eye finds the attribute name first — which is what users scan for most often.

The optional `*` prefix for primary keys appears before the name, making it the very first character on the line. This placement ensures that primary keys are immediately visible when scanning a list of attributes.

The optional size parameter — `VARCHAR(100)`, `DECIMAL(10)` — uses parentheses after the type name, matching SQL's syntax exactly. A database professional reading `VARCHAR(100)` will immediately understand its meaning.

### Link Syntax

Links use a sentence-like syntax:

```
link Entity (min,max) Association
```

This was deliberately designed to read as a natural-language statement: "link Student (zero, many) enrolled_in" — meaning "the Student entity participates in the enrolled_in association with a cardinality of zero to many." The cardinality appears between the entity and the association, visually situated on the connection between them, much as it appears on an MCD diagram.

The alternative of placing cardinalities inside a block was considered:

```
# Rejected alternative
link {
    entity: Student
    association: enrolled_in
    cardinality: (0,N)
}
```

This is more verbose, requires four lines instead of one, and does not read as naturally. Since links carry no additional data beyond entity, association, and cardinality, a single-line syntax is both sufficient and preferred.

### No Commas, No Semicolons

Within blocks, attributes are separated by newlines — no commas or semicolons are needed:

```
entity Student {
    *student_id: INT
    first_name: VARCHAR(100)
    last_name: VARCHAR(100)
}
```

This follows the precedent of Go (struct fields), TOML (key-value pairs), and HCL (block contents). Each attribute occupies exactly one line, making the newline a natural separator. Commas and semicolons would be visual noise without adding information.

The parser emits `NEWLINE` tokens to track line boundaries, but these tokens serve only as optional separators — consecutive newlines and blank lines are harmlessly skipped.

### The Project Block

The `project` block uses a key-value format without quoting:

```
project {
    name: School Management System
    author: Achraf SOLTANI
    description: A school database model
}
```

The `project` block is optional. When present, it must appear at most once. Its keys are a fixed set: `name`, `author`, and `description`. Unknown keys produce a warning rather than an error, allowing forward compatibility if new metadata fields are added in future versions.

### Complete Grammar in EBNF

The complete MSD grammar can be expressed in six productions:

```ebnf
program       = { project_block | entity_block | assoc_block | link_stmt } ;

project_block = "project" "{" { IDENTIFIER ":" STRING_VALUE } "}" ;

entity_block  = "entity" IDENTIFIER "{" { attribute } "}" ;

assoc_block   = "association" IDENTIFIER "{" { attribute } "}" ;

attribute     = [ "*" ] IDENTIFIER ":" type_expr ;

type_expr     = IDENTIFIER [ "(" INTEGER ")" ] ;

link_stmt     = "link" IDENTIFIER "(" INTEGER|IDENTIFIER "," INTEGER|IDENTIFIER ")" IDENTIFIER ;
```

Six productions for an entire language. The grammar is LL(1) — at every decision point, a single token of lookahead suffices to determine which production to apply. This makes it straightforward to implement with recursive descent parsing, which we will do in Chapter 9.

> **Warning:** The EBNF above is a design-level specification, not a formal parser specification. It omits newline handling, comment stripping, and context-sensitive lexing — all of which are handled at the lexer level before the parser sees the token stream.

## 7.5 Semantic Choices

The lexical and syntactic layers define the *form* of MSD. The semantic layer defines its *meaning* — what is legal, what is illegal, and what the structures represent.

### Data Types

MSD supports 13 data types, chosen to match the types in Merisio's data dictionary and to cover the most common PostgreSQL column types:

| Category | Types |
|---|---|
| Integer | `INT`, `BIGINT`, `SMALLINT` |
| String | `VARCHAR`, `CHAR`, `TEXT` |
| Boolean | `BOOLEAN` |
| Date/Time | `DATE`, `TIME`, `TIMESTAMP` |
| Numeric | `DECIMAL`, `FLOAT`, `DOUBLE` |

Three of these types accept a size parameter in parentheses:

- `VARCHAR(n)` — variable-length string with maximum length *n*
- `CHAR(n)` — fixed-length string of length *n*
- `DECIMAL(p)` — decimal number with precision *p*

All other types used with a size parameter produce a warning. The type name is case-insensitive during parsing (internally normalised to uppercase), so `varchar(100)`, `VARCHAR(100)`, and `Varchar(100)` are all equivalent.

Thirteen types is a carefully chosen set. It is large enough to model any realistic database schema, but small enough to memorise. Types like `SERIAL`, `UUID`, `JSON`, and `ARRAY` were deliberately excluded — they are PostgreSQL-specific extensions that do not belong in a conceptual model. MSD models the *logical* structure of data, not its physical storage.

### Cardinality Constraints

Cardinalities in link statements are constrained to four valid combinations:

- `(0,1)` — zero or one (optional, singular)
- `(0,N)` — zero or more (optional, multiple)
- `(1,1)` — exactly one (mandatory, singular)
- `(1,N)` — one or more (mandatory, multiple)

The minimum must be `0` or `1`. The maximum must be `1` or `N` (where `N` is case-insensitive — both `n` and `N` are accepted). Any other value is a parse error.

This constraint set matches MERISE's definition exactly. Some ER modelling tools allow arbitrary numeric cardinalities like `(2,5)`, but MERISE does not. MSD enforces the domain's rules, not a superset of them.

### Uniqueness Rules

MSD enforces three uniqueness rules:

1. **Entity names must be unique**: Defining two entities named `Student` is an error.

2. **Association names must be unique**: Defining two associations named `enrolled_in` is an error.

3. **No entity-association name conflicts**: An entity and an association cannot share a name. If entity `Course` exists, association `Course` is an error.

These rules exist because names serve as identifiers in link statements. If two entities shared the name `Student`, a link referencing `Student` would be ambiguous. The cross-category uniqueness rule (rule 3) exists for the same reason and also because entity and association names both become table names in the generated SQL.

### Forward References

Link statements may reference entities and associations that are defined later in the file:

```
# Links come first — this is valid
link Student (0,N) enrolled_in
link Course (1,N) enrolled_in

entity Student {
    *student_id: INT
    name: VARCHAR(100)
}

entity Course {
    *course_id: INT
    title: VARCHAR(200)
}

association enrolled_in {
    grade: DECIMAL(10)
}
```

Forward references are supported because the parser and the semantic analyser are separate stages. The parser collects all declarations first; the semantic analyser resolves references afterward, when all names are known. This two-pass approach allows declarations to appear in any order, which is a significant usability benefit — users can organise their files by logical grouping rather than being forced into declaration-before-use ordering.

### Primary Key Enforcement

An entity without a primary key attribute produces a **warning**, not an error:

```
entity Temporary {
    data: TEXT    # Warning: entity 'Temporary' has no primary key
}
```

This is a deliberate choice. A missing primary key is almost certainly unintentional, but it does not prevent the model from being valid at the conceptual level. Treating it as a warning allows the user to import an incomplete model and fix it in the graphical editor, rather than being blocked entirely. The severity distinction between errors (which may block import) and warnings (which allow it) is a usability decision informed by the workflow: text files are often used for rapid prototyping, and prototypes are intentionally incomplete.

### Error Suggestions via Levenshtein Distance

When a link references an unknown entity or association name, MSD computes the Levenshtein distance between the unknown name and all known names. If a close match is found (distance of 3 or less), the error message includes a suggestion:

```
school.msd:15: error: unknown entity: 'Studnet' (did you mean 'Student'?)
```

This is a semantic design decision, not merely an implementation detail. The language specification declares that error messages *should* include typo suggestions when possible. This commitment at the design level ensures that any conforming implementation provides this feature, rather than leaving it as an optional nicety.

> **Info:** Levenshtein distance measures the minimum number of single-character edits (insertions, deletions, substitutions) needed to transform one string into another. A maximum distance of 3 means MSD will suggest corrections for common typos — transposed letters, missing letters, or wrong letters — without suggesting unrelated names.

## 7.6 The Complete MSD Specification

We now have all the pieces. Here is a complete, working MSD file that demonstrates every language construct:

```
# School Management System
# MSD file for the university registration database

project {
    name: School Management System
    author: Achraf SOLTANI
    description: A school database model
}

// Entities

entity Student {
    *student_id: INT
    first_name: VARCHAR(100)
    last_name: VARCHAR(100)
    date_of_birth: DATE
    email: VARCHAR(255)
}

entity Course {
    *course_id: INT
    title: VARCHAR(200)
    credits: INT
}

// Associations

association enrolled_in {
    grade: DECIMAL(10)
    enrollment_date: DATE
}

// Links

link Student (0,N) enrolled_in
link Course (1,N) enrolled_in
```

Let us walk through this file, line by line, observing how each design decision manifests.

**Lines 1–2**: Comments using the `#` style. These are stripped by the lexer and never reach the parser. They serve as documentation for the human reader.

**Lines 4–8**: The `project` block. The keyword `project` opens a brace-delimited block. Inside, each line is a key-value pair separated by `:`. The values — `School Management System`, `Achraf SOLTANI`, `A school database model` — contain spaces but require no quoting, thanks to context-sensitive lexing. The lexer recognises that it is inside a project block and captures the remainder of each line after `:` as a single `STRING_VALUE` token.

**Line 10**: A comment using the `//` style. Both comment styles work anywhere in the file.

**Lines 12–18**: The `Student` entity. The keyword `entity` followed by the identifier `Student` and an opening brace. Inside, five attributes are listed, one per line. The first attribute — `*student_id: INT` — is marked as a primary key by the `*` prefix. The remaining attributes use `VARCHAR(100)`, `VARCHAR(255)`, and `DATE` types. No commas separate the attributes; newlines suffice.

**Lines 20–24**: The `Course` entity. Same structure, different attributes. The `credits` attribute uses the unsized type `INT`.

**Lines 28–31**: The `enrolled_in` association. Uses the `association` keyword instead of `entity`, but the internal syntax is identical — attributes with name-colon-type notation. The `grade` attribute uses `DECIMAL(10)`, a sized type. Note that association attributes are never primary keys (associations do not have primary keys in MERISE).

**Lines 35–36**: Two link statements. Each reads as a sentence: "link Student (zero, many) enrolled_in" and "link Course (one, many) enrolled_in." The cardinalities `(0,N)` and `(1,N)` specify that a student may be enrolled in zero or more courses, and a course must have at least one enrolled student. The link syntax places the cardinality between the entity and the association, mirroring its position on an MCD diagram.

The entire file is 36 lines, including comments and blank lines. It fully specifies a two-entity, one-association conceptual data model with typed attributes, explicit primary keys, and cardinalities. Merisio can parse this file, validate it, generate a visual layout, and import it as a complete project — all from plain text.

## 7.7 Comparison with Mocodo

MSD is not the first DSL for MERISE modelling. **Mocodo** is an existing tool that uses its own text-based format to describe MCDs. Comparing MSD with Mocodo's syntax illuminates the design trade-offs and explains why MSD made different choices.

### Syntax Comparison

A simple model in Mocodo's format:

```
ENROLLED_IN, 0N STUDENT, 1N COURSE
STUDENT: student_id, first_name, last_name
COURSE: course_id, title, credits
```

The same model in MSD:

```
entity Student {
    *student_id: INT
    first_name: VARCHAR(100)
    last_name: VARCHAR(100)
}

entity Course {
    *course_id: INT
    title: VARCHAR(200)
    credits: INT
}

association enrolled_in {
    grade: DECIMAL(10)
}

link Student (0,N) enrolled_in
link Course (1,N) enrolled_in
```

### Feature Comparison

| Feature | Mocodo | MSD |
|---|---|---|
| Primary keys | Implicit (first attribute) | Explicit (`*` prefix) |
| Composite primary keys | Not supported | Multiple `*` attributes |
| Data types | None | Mandatory, 13 types |
| Type sizes | None | `VARCHAR(n)`, `CHAR(n)`, `DECIMAL(p)` |
| Syntax style | Single-line, comma-separated | Block-structured, one attribute per line |
| Comments | None | `#` and `//` |
| Project metadata | None | `project { ... }` block |
| Error messages | Minimal | Line numbers, column numbers, suggestions |
| Layout information | Embedded in syntax (line/column position) | Automatically computed |
| Carrying attributes | On the association line | In the `association` block |

### Why MSD Made Different Choices

**Explicit primary keys over implicit ones.** In Mocodo, the first attribute listed for an entity is implicitly the primary key. This is concise but fragile — reordering attributes silently changes the primary key. MSD requires the `*` prefix, making primary keys explicit and immune to reordering. The principle at work: **explicit is better than implicit**, especially for structural information.

**Mandatory data types.** Mocodo does not require data types for attributes. This keeps the syntax minimal but means that Mocodo cannot generate SQL DDL without additional information. MSD requires types because one of its primary use cases is SQL generation. Requiring types at the modelling stage catches type mismatches early and produces complete SQL output without human intervention.

**Block structure over single-line syntax.** Mocodo fits an entire entity on one line: `STUDENT: student_id, first_name, last_name`. This is compact for small models but becomes unwieldy for entities with many attributes. A ten-attribute entity in Mocodo is a single line exceeding 100 characters. In MSD, the same entity is ten readable lines. Block structure scales better with model complexity.

**Separate link statements.** In Mocodo, cardinalities are embedded in the association line: `ENROLLED_IN, 0N STUDENT, 1N COURSE`. This couples the association definition with its links. In MSD, the association and its links are independent constructs. This separation allows an association to be defined once and linked to any number of entities without repeating the association's attributes — a cleaner decomposition that mirrors the MERISE domain model itself, where associations and links are distinct concepts.

**Comments and metadata.** Mocodo has no comment syntax and no metadata format. MSD supports both because real-world files benefit from documentation and machine-readable metadata. Comments explain design decisions; metadata enables tooling (e.g., displaying the project name in a window title bar).

## 7.8 Exercises

**Exercise 7.1: Domain Analysis for a New DSL**

Design a DSL for network topology definitions. A topology consists of nodes (with names and types such as `router`, `switch`, `host`), connections (between pairs of nodes with bandwidth and latency attributes), and subnets (grouping nodes under a CIDR block). Apply the domain analysis process from Section 7.2: list the domain concepts, create a domain vocabulary table mapping each concept to a language construct, and enumerate the domain constraints.

**Exercise 7.2: Alternative Primary Key Syntax**

MSD uses the `*` prefix for primary keys. Consider three alternative designs: (a) a `@pk` annotation before the attribute, (b) a separate `primary key(attr1, attr2)` statement after the attribute list, (c) a `key` keyword used as a modifier (`key student_id: INT`). For each alternative, write example syntax, assess its impact on the grammar, and evaluate its readability compared to the `*` prefix. Which would you choose, and why?

**Exercise 7.3: Block Syntax vs Single-Line Syntax**

Rewrite the complete MSD example from Section 7.6 using a hypothetical single-line syntax where each entity, association, and link occupies exactly one line (similar to Mocodo). Compare the two versions for readability at three scales: a model with 2 entities, a model with 10 entities (5 attributes each), and a model with 50 entities. At what point does block syntax become clearly superior? Is there a model size where single-line syntax is preferable?

**Exercise 7.4: Adding Inheritance**

MSD does not support inheritance between entities (e.g., `Person` as a parent of `Student` and `Teacher`). Design syntax and semantic rules for an inheritance feature. Consider: What keyword would you use? How would inherited attributes be represented? Would the child entity repeat the parent's primary key or inherit it implicitly? Write the EBNF productions for your design. Then evaluate: does the added complexity justify the feature, given that MERISE itself has limited support for inheritance?

**Exercise 7.5: Forward References and Ordering**

MSD supports forward references in link statements. Redesign MSD *without* forward references — link statements may only reference entities and associations defined earlier in the file. How does this restriction affect file organisation? Write two versions of the school management model: one ordered for the no-forward-reference version, and one ordered for maximum logical clarity. Which is more readable? What does this tell you about the value of forward references in DSL design?

**Exercise 7.6: Error Message Design**

Consider the following invalid MSD file:

```
entity Student {
    *student_id INT
    name: VARCAHR(100)
}

link Studnet (0,N) enrolled
```

There are three errors: a missing colon on line 2, a misspelled type on line 3, and misspelled names on line 6. For each error, write the ideal error message — including line number, column number, severity, and a helpful suggestion. Then explain which errors can be caught at the lexical stage, which at the syntactic stage, and which at the semantic stage.

---

This chapter has demonstrated the complete design process for a domain-specific language. Starting from MERISE conceptual data modelling as a domain, we systematically derived MSD's lexical tokens, syntactic grammar, and semantic rules. Each decision was grounded in a principle: brevity where possible, explicitness where it matters, familiarity drawn from both SQL and programming languages, and useful error messages as a first-class design concern.

The result is a six-production grammar, four keywords, thirteen data types, and a handful of semantic constraints — a complete language specification small enough to fit in this chapter, yet expressive enough to capture any MERISE conceptual data model.

In Part III, we turn from design to implementation. Chapter 8 will build a lexer that transforms MSD source text into the token stream described in Section 7.3. Chapter 9 will build a recursive descent parser for the grammar in Section 7.4. And Chapter 10 will implement the semantic rules from Section 7.5 — including the Levenshtein-based typo suggestions. The language is designed. Now we build it.
