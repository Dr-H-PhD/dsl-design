\newpage

# Chapter 3: Requirements and Domain Analysis

A common temptation when designing a domain-specific language is to start with syntax. You imagine what code should look like, sketch a few examples, and begin writing a parser. This is exactly backwards. Syntax is the *expression* of domain knowledge — it cannot precede that knowledge. Before you write a single grammar rule, you must deeply understand the domain your language will serve.

This chapter is about the work that comes before language design. We will explore how to analyse a target domain, extract its core concepts and relationships, understand the people who will use the language, and systematically map domain knowledge onto language constructs. The techniques here apply to any DSL, but we will illustrate them throughout with the MERISE database modelling domain — the domain that motivates the MSD language we design in Chapter 7.

---

## 3.1 Understanding the Target Domain

### Why Domain Analysis Must Precede Language Design

A DSL exists to serve a domain. If you misunderstand the domain, the language will be awkward at best and misleading at worst. Consider what happens when you skip domain analysis:

- You invent syntax that *looks nice* but does not map to real domain concepts.
- You omit constructs that practitioners need daily.

- You conflate distinct concepts because you did not realise they were different.

- You impose constraints that make no sense to domain experts.

The purpose of domain analysis is to build a **domain model** — a structured understanding of the concepts, relationships, and rules that govern the domain. This model becomes the blueprint for every design decision in your language.

### The Danger of Designing Syntax First

When you start with syntax, you anchor yourself to surface-level decisions before understanding the deep structure. Suppose you are designing a language for cooking recipes. You might write:

```
mix flour, sugar, eggs for 5 minutes
```

This looks reasonable. But a domain expert would tell you that mixing is not a single operation — there is folding, whisking, beating, and kneading, each with different mechanics. There are also implicit requirements: ingredients must be prepared (sifted flour, room-temperature eggs) before mixing. A syntax-first approach would have missed these distinctions entirely, and retrofitting them later would distort the language.

The rule is simple: **understand first, design second**.

### Working with Domain Experts vs Working Alone

If you have access to domain experts, involve them from the start. They will identify concepts you would miss, correct your misunderstandings, and validate your domain model. The collaboration typically follows this pattern:

1. **Interview**: Ask domain experts to describe their work, their vocabulary, and their pain points.

2. **Model**: Build a draft domain model and present it back to them.
3. **Refine**: Iterate until the model accurately reflects their understanding.

4. **Validate**: Show prototype syntax and ask whether it expresses their concepts naturally.

If you are working alone — perhaps because you *are* the domain expert — you must be especially disciplined. Document your assumptions explicitly. Search for edge cases. Study existing tools and standards in the domain. Your own familiarity can blind you to implicit knowledge that a language must make explicit.

### Domain Modelling as the Foundation for Language Constructs

A domain model captures three things:

- **Concepts**: The nouns of the domain — the things that exist and that users reason about.

- **Operations**: The verbs — the actions performed on or between concepts.

- **Constraints**: The rules that determine which combinations of concepts and operations are valid.

Every element of your eventual language — its keywords, its syntax patterns, its validation rules — will trace back to one of these three categories. The domain model is not a preliminary step you do once and forget; it is the reference document you consult throughout the design and implementation process.

---

## 3.2 Identifying Domain Concepts

The first step in domain analysis is to identify the **concepts** — the things that exist in the domain. A systematic way to do this is to extract nouns, verbs, and adjectives from domain descriptions, expert interviews, and existing documentation.

### Extracting Nouns (Entities and Objects)

Nouns correspond to the *things* in the domain — the objects, structures, and containers that users create, manipulate, and reason about. To find them, read through domain documentation and highlight every noun phrase.

For example, consider this description of MERISE conceptual modelling:

> *"A conceptual data model consists of **entities** that represent real-world objects. Each entity has **attributes** that describe its properties. **Associations** represent relationships between entities. Each association is connected to entities through **links**, and each link has a **cardinality** that specifies how many instances participate."*

The nouns are: entity, attribute, association, link, cardinality, model, instance. Not all nouns will become language constructs — "model" and "instance" are meta-level concepts rather than things the user defines — but this extraction gives you a starting vocabulary.

### Extracting Verbs (Operations and Relationships)

Verbs tell you what users *do* with the domain concepts. They may become language constructs (if the user expresses them in the DSL) or tooling operations (if they happen outside the language). Common verbs include:

- **Define** / **declare**: Creating new instances of concepts (defining an entity, declaring an attribute).

- **Connect** / **link**: Establishing relationships between concepts.
- **Transform**: Converting from one representation to another (MCD to MLD).
- **Validate**: Checking that a model satisfies domain rules.

In the MERISE domain, the key verbs are: define (entities, associations), connect (via links), assign (cardinalities, attributes), transform (MCD to MLD to SQL), and validate (structural rules).

### Extracting Adjectives (Properties, Attributes, and Constraints)

Adjectives describe the properties and qualifiers that distinguish instances of a concept. They often become attributes in your data model and parameters or modifiers in your language syntax.

For MERISE: an attribute can be a **primary key** (or not). A cardinality has a **minimum** and a **maximum**. An attribute has a **data type** and an optional **size**. An entity has a **name**. These adjectives tell you what information the user needs to specify when defining each concept.

### Creating a Domain Vocabulary

Once you have extracted nouns, verbs, and adjectives, organise them into a **domain vocabulary table**. This table becomes the authoritative reference for your language design.

| Category   | Term          | Description                                             |
|------------|---------------|---------------------------------------------------------|
| Noun       | Entity        | A named container representing a real-world object      |
| Noun       | Association   | A named relationship between two or more entities       |
| Noun       | Link          | A connection between one entity and one association     |
| Noun       | Attribute     | A named property with a data type                       |
| Noun       | Cardinality   | The participation constraint on a link                  |
| Verb       | Define        | Create a new entity or association                      |
| Verb       | Connect       | Establish a link between an entity and an association   |
| Verb       | Assign        | Give an attribute to an entity or association            |
| Adjective  | Primary key   | Marks an attribute as part of the entity's identifier   |
| Adjective  | Data type     | The type of data an attribute holds (INT, VARCHAR, etc.)|
| Adjective  | Size          | The length or precision of a data type                  |
| Adjective  | Minimum       | The lower bound of a cardinality (0 or 1)               |
| Adjective  | Maximum       | The upper bound of a cardinality (1 or N)               |

> **Tip:** Keep your domain vocabulary table alive throughout the project. As you learn more about the domain, add new terms. When you design syntax in later chapters, annotate each term with the language construct that expresses it. This table becomes the traceability link between the domain and the language.

> **Programmer:** Requirements gathering for a DSL closely mirrors API design in Go. When you design a Go package, you start by defining the types and method signatures that callers will use -- effectively building the user's mental model before writing any implementation. The same discipline applies to DSLs: write ten realistic example files in your proposed syntax before implementing the lexer. This is the DSL equivalent of dogfooding. Go's own standard library follows this pattern rigorously; the `io.Reader` and `io.Writer` interfaces were designed around how users think about I/O, not around how the kernel implements it. Your DSL's keywords and constructs should similarly mirror how domain experts already think, not how your parser will process them.

---

## 3.3 Relationships and Constraints

### How Domain Concepts Relate to Each Other

Concepts do not exist in isolation. The structure of a domain is defined as much by the *relationships* between concepts as by the concepts themselves. Understanding these relationships is critical because they determine the nesting, ordering, and grouping patterns in your language syntax.

In the MERISE domain, the key relationships are:

- An **entity** *contains* zero or more **attributes**.
- An **association** *contains* zero or more **carrying attributes**.
- A **link** *connects* exactly one **entity** to exactly one **association**.
- A **link** *has* exactly one **cardinality** (a minimum-maximum pair).
- An **attribute** *has* exactly one **data type**.

These relationships naturally suggest a hierarchical structure: entities and associations are top-level constructs, attributes are nested within them, and links express connections between the top-level constructs.

### Cardinality of Relationships

Each relationship between domain concepts has a cardinality — how many of one concept can relate to another. This matters for language design because it determines whether a syntax element appears once, optionally, or in a list.

| Relationship                          | Cardinality | Language implication                     |
|---------------------------------------|-------------|------------------------------------------|
| Entity contains attributes            | One-to-many | Attribute list within entity block        |
| Association contains attributes       | One-to-many | Attribute list within association block   |
| Link connects entity to association   | One-to-one on each side | Link references exactly one of each |
| Attribute has data type               | One-to-one  | Type annotation is required, not a list   |
| Cardinality has min and max           | One-to-one  | Single value pair, not a list             |

### Constraints That Restrict Valid Combinations

Beyond structure, every domain has **constraints** — rules about what constitutes a valid model. Some constraints are structural (enforced by the syntax itself), while others are semantic (enforced by validation logic after parsing).

For the MERISE domain, the key constraints include:

1. Every entity must have a unique name within the model.
2. Every entity must have at least one primary key attribute.
3. Every association must be connected to at least two entities (via links).
4. Cardinalities must come from the set {(0,1), (0,N), (1,1), (1,N)}.
5. Attribute names must be unique within their owning entity or association.
6. An entity that is not connected to any association is an orphan (warning).

### Which Constraints Belong in the Language vs in the Tooling?

Not every constraint should be enforced by the language grammar. There is a spectrum:

- **Lexical constraints** are enforced by the tokeniser. Example: an identifier must start with a letter.

- **Syntactic constraints** are enforced by the parser. Example: an entity block must contain braces.

- **Semantic constraints** are enforced by a post-parsing validation pass. Example: entity names must be unique.

- **Tooling constraints** are enforced by the environment. Example: a model should have at least one entity (but an empty file is still syntactically valid).

The general principle is: **push constraints as early as possible in the pipeline, but not earlier than they naturally belong**. Cardinalities being from a fixed set is naturally a lexical or syntactic constraint (the parser can reject invalid values). Entity name uniqueness is naturally a semantic constraint (the parser sees each entity independently). A model having no orphan entities is naturally a tooling-level warning.

> **Warning:** Encoding too many constraints into the grammar makes the language rigid and the parser complex. Encoding too few makes invalid models silently accepted. Strike a balance: use the grammar for structural rules, and use semantic analysis for cross-referencing rules.

> **Programmer:** Backward compatibility is a critical concern even for small DSLs, and Go's approach to compatibility offers a useful model. Go 1's compatibility promise guarantees that valid Go 1.0 code compiles with Go 1.22, and Go modules use explicit version declarations (`go 1.21` in `go.mod`) to manage feature availability. If your DSL gains adoption, users will have existing files that must continue to work when the tool is updated. Design your DSL with a version field from day one (as MSD does with its `project {}` block), and treat syntax changes as seriously as you would treat breaking API changes in a Go library. Adding a keyword is straightforward; removing or redefining one is a migration nightmare.

---

## 3.4 User Personas and Workflow Analysis

### Who Will Use the DSL?

A language is only as good as its fit for the people who use it. Before designing syntax, identify your **user personas** — the distinct categories of people who will interact with the language. For each persona, understand:

- Their technical background (programmer, domain expert, student, or mixed).

- Their familiarity with text-based languages (comfortable with code, or prefer GUIs).

- Their goals (authoring new models, reviewing existing ones, automating tasks).

- Their tolerance for complexity (will they learn a full syntax, or do they need simplicity?).

### What Tasks Will They Perform?

Users rarely interact with a DSL in only one way. Typical tasks include:

- **Authoring**: Writing new models from scratch.
- **Editing**: Modifying existing models.
- **Reviewing**: Reading and understanding models written by others.

- **Transforming**: Converting models to other formats (SQL, diagrams, documentation).

- **Validating**: Checking models for correctness.
- **Versioning**: Tracking changes to models over time (version control).

Each task places different demands on the language. Authoring favours conciseness. Reviewing favours readability. Versioning favours line-oriented syntax with clean diffs.

### What Tools Do They Already Use?

Your DSL does not exist in a vacuum. Users have existing workflows, editors, and tools. A DSL that integrates smoothly into these workflows will see adoption; one that demands a completely new environment will face resistance.

Consider: do your users work in text editors, IDEs, command-line terminals, or graphical applications? Do they use version control (Git)? Do they work in CI/CD pipelines? Each of these contexts influences language design decisions — a language intended for Git workflows should produce clean diffs; a language intended for CLI pipelines should support streaming input.

### Example: Merisio User Personas

For the MSD language, we identified three primary personas:

| Persona               | Background          | Primary task          | Tool preference       |
|------------------------|--------------------|-----------------------|-----------------------|
| CS student             | Learning databases  | Authoring MCD models  | Text editor, GUI app  |
| University teacher     | Database expert     | Reviewing student work| Text editor, CLI      |
| Software developer     | Programmer          | Automating model generation | CLI, scripts, CI/CD |

The **CS student** is learning MERISE as part of a database course. They need syntax that is easy to learn, with clear error messages that guide them when they make mistakes. They may use either the Merisio GUI or write MSD files directly.

The **university teacher** reviews dozens of student models. They need the language to be readable at a glance and to support batch validation. A CLI tool that validates a directory of `.msd` files and reports errors is essential for this persona.

The **software developer** wants to generate MERISE models programmatically — perhaps from an existing database schema or as part of a code generation pipeline. They need a machine-writable format that is also human-readable for debugging.

These three personas pull in different directions. The student wants simplicity; the developer wants precision; the teacher wants readability. A well-designed DSL finds the balance point that serves all three.

---

## 3.5 From Domain Model to Language Constructs

Once you have a domain model and an understanding of your users, you can systematically map domain concepts to language constructs. This mapping is the bridge between analysis and design.

### The Mapping Principles

The mapping follows a consistent pattern:

- **Each noun** in the domain vocabulary becomes a **keyword** or **construct type** in the language.

- **Each relationship** between concepts becomes a **syntax pattern** — typically nesting, referencing, or sequencing.

- **Each constraint** becomes a **validation rule** — enforced at the lexical, syntactic, or semantic level.

- **Each adjective** becomes a **modifier**, **annotation**, or **parameter** in the syntax.

### Design Table: Domain Concept to Language Construct

The most useful tool at this stage is a **design table** that traces each domain concept through to its language representation. Here is the design table for the MERISE MCD domain:

| Domain concept         | Language construct      | Proposed syntax                         | Validation rule                          |
|------------------------|------------------------|-----------------------------------------|------------------------------------------|
| Entity                 | `entity` keyword       | `entity Name { ... }`                   | Name must be unique across all entities  |
| Association            | `association` keyword  | `association Name { ... }`              | Name must be unique across all associations |
| Attribute              | Attribute declaration  | `name: TYPE` or `name: TYPE(size)`      | Name unique within owning block          |
| Primary key            | `*` prefix marker      | `*id: INT`                              | At least one per entity                  |
| Link                   | `link` statement       | `link Entity (0,N) Association`         | References must resolve to defined names |
| Cardinality            | Inline notation        | `(0,1)`, `(0,N)`, `(1,1)`, `(1,N)`     | Must be one of the four valid pairs      |
| Data type              | Type name              | `INT`, `VARCHAR(100)`, `DATE`           | Must be a recognised type name           |

This table serves multiple purposes. During design, it ensures that every domain concept has a corresponding language feature. During implementation, it tells the parser what to expect and the semantic analyser what to check. During testing, it defines what valid and invalid inputs look like.

### Resolving Design Tensions

The mapping is rarely one-to-one. You will encounter tensions:

- **A domain concept is too complex for a single construct.** Solution: decompose it. The "link" concept in MERISE combines a connection and a cardinality. In the language, we express this as a single statement with two parts: the entity-association reference and the cardinality annotation.

- **Two domain concepts are similar but not identical.** Solution: decide whether they share syntax or have distinct syntax. Entities and associations both contain attributes, but entities have primary keys and associations do not. We use a shared attribute syntax inside both, but only allow the `*` marker inside entity blocks.

- **A constraint spans multiple constructs.** Solution: handle it in semantic analysis, not in the grammar. "Every entity must be connected to at least one association" cannot be checked until all entities and links have been parsed.

> **Note:** The design table is a living document. You will revise it repeatedly as you work through lexical design (Chapter 4), syntactic design (Chapter 5), and semantic design (Chapter 6). Do not expect to get it right on the first pass.

---

## 3.6 Case Study: The MERISE Modelling Domain

### What Is MERISE?

MERISE is a systems analysis and design methodology that originated in France in the late 1970s. It remains widely taught in French-speaking universities and is used in practice for database design across Europe and North Africa. MERISE provides a structured approach to information system design, moving from abstract conceptual models down to concrete physical implementations.

### The Three Abstraction Levels

MERISE defines three levels of data modelling:

1. **MCD (Modele Conceptuel de Donnees)** — The conceptual data model. This is the most abstract level, describing *what* data exists and how it relates, without any concern for implementation. The MCD uses entities, associations, and links with cardinalities.

2. **MLD (Modele Logique de Donnees)** — The logical data model. This is derived mechanically from the MCD by applying transformation rules (e.g., a many-to-many association becomes a junction table). The MLD uses tables, columns, primary keys, and foreign keys.

3. **MPD (Modele Physique de Donnees)** — The physical data model. This is the MLD expressed as concrete SQL for a specific database engine (PostgreSQL, MySQL, etc.), including data types, indexes, and constraints.

The key insight for DSL design is that the MCD level is where human modelling decisions are made. The MLD and MPD levels are derived — they can be generated automatically from a well-specified MCD. This makes the MCD the natural target for a domain-specific language: capture the human decisions in text, then generate everything else.

### The MCD Level in Detail

An MCD consists of:

- **Entities**: Named containers representing real-world objects or concepts. Each entity has one or more attributes, at least one of which is marked as the primary key. Example: a `Student` entity with attributes `student_id` (primary key), `name`, and `date_of_birth`.

- **Associations**: Named relationships between entities. An association may carry its own attributes (called *carrying attributes*). Example: an `Enrol` association between `Student` and `Course`, carrying a `grade` attribute.

- **Links**: Connections between entities and associations, each annotated with a cardinality. A cardinality is a pair (min, max) drawn from the set {(0,1), (0,N), (1,1), (1,N)}. Example: `Student` is linked to `Enrol` with cardinality (0,N), meaning a student may be enrolled in zero or more courses.

### Why This Domain Is Well-Suited for a DSL

Several characteristics make MERISE an excellent candidate for a DSL:

- **Bounded complexity**: The domain has a small, well-defined set of concepts (entities, associations, links, attributes, cardinalities). A DSL can cover the entire domain without becoming sprawling.

- **Formal structure**: The MCD has precise rules about what constitutes a valid model. These rules map naturally to language constraints.

- **Repetitive patterns**: Every entity follows the same pattern (name, attributes, primary keys). Every link follows the same pattern (entity, cardinality, association). Repetitive structure is exactly what a DSL excels at expressing concisely.

- **Derivable outputs**: The MLD and SQL can be generated mechanically from the MCD. A text-based MCD format enables automation that a graphical-only tool cannot.

- **Version control need**: Graphical MERISE tools produce binary or complex JSON project files that are opaque to Git. A text-based DSL produces clean, diffable, reviewable files.

### Existing Tools

Before designing a new DSL, it is essential to survey existing tools — both to understand what works and to identify gaps:

- **AnalyseSI** (Java): A desktop application widely used in French computer science education. Provides a graphical MCD editor with MLD generation. No text-based input format. Project files are XML.

- **Mocodo** (Python): A text-based tool that uses a minimal DSL for defining MCDs. Mocodo's syntax is compact but limited — it lacks explicit data types, has no primary key markers, and provides minimal error messages. It is designed for diagram generation rather than full database modelling.

- **Merisio** (Python/Qt): A visual MCD editor with MLD generation and PostgreSQL SQL export. Merisio stores projects as `.merisio` JSON files. It provides the graphical editing experience but lacked a text-based authoring format.

### What Merisio Needed

The gap that motivated MSD was clear: Merisio needed a **text-based authoring format** that would enable:

- **Version control**: MCD models stored as plain text files in Git repositories, with meaningful diffs.

- **Code review**: Teachers and team leads reviewing model changes in pull requests.

- **Automation**: CI/CD pipelines that validate models, generate SQL, and export diagrams without launching the GUI.

- **Batch processing**: The `merisio-cli` tool processing multiple model files from the command line.

- **Round-trip fidelity**: A text file imported into Merisio's GUI, edited visually, and exported back to text should preserve the model faithfully.

This is the problem that MSD — the Merisio Schema Definition language — was designed to solve. In Chapter 7, we will design MSD in full, applying the lexical, syntactic, and semantic design principles from Chapters 4 through 6. The domain analysis in this chapter provides the foundation for that design.

---

## 3.7 Exercises

**Exercise 3.1 — Domain Vocabulary Extraction**

Choose a domain you know well — cooking recipes, board game rules, network configurations, knitting patterns, or music notation. Write a one-paragraph description of the domain as a domain expert would explain it. Then extract all nouns, verbs, and adjectives from your description and organise them into a domain vocabulary table with three columns: Category (noun/verb/adjective), Term, and Description.

**Exercise 3.2 — Relationship Analysis**

Using the domain you chose in Exercise 3.1, identify the relationships between concepts. For each relationship, state its cardinality (one-to-one, one-to-many, or many-to-many) and describe its language design implication (nesting, referencing, listing, or annotation).

**Exercise 3.3 — Constraint Classification**

List five constraints from the MERISE domain. For each one, classify it as lexical, syntactic, semantic, or tooling-level. Justify your classification by explaining *why* it belongs at that level rather than an adjacent one. If you disagree with the classification suggested in Section 3.3, argue your case.

**Exercise 3.4 — User Persona Design**

Imagine you are designing a DSL for defining REST API endpoints (routes, HTTP methods, request/response schemas). Identify three distinct user personas for this language. For each persona, describe their background, primary task, tool preferences, and what they would value most in the language (conciseness, readability, strictness, flexibility).

**Exercise 3.5 — Design Table**

Create a design table (as in Section 3.5) for a DSL that describes chess game positions. Your domain concepts should include at minimum: board, square, piece, colour, and position. Map each concept to a proposed language construct, syntax, and validation rule.

**Exercise 3.6 — Existing Tool Survey**

Choose an existing DSL you use regularly (SQL, CSS, Dockerfile, Makefile, or another). Identify three domain concepts that the language expresses well and one concept that it handles awkwardly or not at all. For the awkward concept, sketch an alternative syntax that would express it more naturally, and explain what trade-off the original language designers likely faced.
