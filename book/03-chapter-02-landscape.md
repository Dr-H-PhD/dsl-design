\newpage

# Chapter 2: The DSL Landscape

In Chapter 1, we defined what domain-specific languages are and drew the line between DSLs and general-purpose languages. Now we step back and survey the landscape. What external DSLs exist in the wild? How do they differ? What do they have in common? And what separates the wildly successful ones from the forgotten experiments?

This chapter examines six real-world DSLs in detail, then develops two classification schemes — by paradigm and by complexity — that will guide our design decisions throughout the rest of the book. We close by identifying the patterns that recur across nearly every successful DSL, and the anti-patterns that lead to failure.

---

## 2.1 A Survey of External DSLs

The best way to understand what makes a good DSL is to study the ones that have stood the test of time. Each of the following languages was designed to solve a specific problem, and each has become the dominant tool in its domain.

### SQL

SQL (Structured Query Language) is arguably the most successful domain-specific language ever created. Introduced in the 1970s and standardised in 1986, it allows users to express *what* data they want without specifying *how* to retrieve it.

```sql
SELECT name, email
FROM students
WHERE enrolled_year >= 2024
ORDER BY name;
```

SQL's genius lies in its declarative nature. The user describes the desired result — a filtered, sorted list of students — and the database engine decides the most efficient way to compute it. This separation of intent from implementation is a hallmark of great DSL design.

### GraphQL

GraphQL, developed at Facebook and open-sourced in 2015, tackles a different data problem: letting clients specify the exact shape of the data they need from an API. Rather than the server dictating the response structure, the client's query *is* the response shape.

```graphql
query {
  student(id: "42") {
    name
    courses {
      title
      credits
    }
  }
}
```

GraphQL is declarative for reads but introduces imperative elements through mutations — a hybrid approach we will revisit in Section 2.2.

### Terraform HCL

HashiCorp Configuration Language (HCL) is the DSL behind Terraform, the infrastructure-as-code tool. It describes cloud resources declaratively: what should exist, not how to create it.

```hcl
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"
  tags = { Name = "WebServer" }
}
```

Terraform reads HCL files, computes the difference between the declared state and the actual state, and applies only the necessary changes. The DSL user never writes provisioning logic — they describe the desired end state.

### Dockerfile

A Dockerfile describes how to build a container image, step by step. Unlike the declarative languages above, a Dockerfile is explicitly imperative — each instruction executes in sequence, and order matters.

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
```

The language is small (fewer than 20 instructions), easy to learn, and tightly coupled to its domain. Every line corresponds to a layer in the container image.

### Makefile

Make, dating from 1976, uses a DSL that blends declarative dependency tracking with imperative recipe execution. Targets declare their dependencies, and Make determines what needs rebuilding.

```makefile
app: main.o utils.o
	gcc -o app main.o utils.o

main.o: main.c
	gcc -c main.c
```

The dependency graph is declarative — Make computes the build order automatically. But the recipes (the indented lines) are imperative shell commands. This hybrid nature makes Make a fascinating case study.

### CSS Selectors

CSS (Cascading Style Sheets) uses a pattern-based declarative approach: selectors match elements, and declarations describe how those elements should appear.

```css
.student-card {
  background: #f5f5f5;
  border-radius: 8px;
  padding: 1rem;
}
```

CSS is purely declarative. There are no loops, no conditionals (ignoring media queries), and no variables in the original specification. The browser's rendering engine decides how to apply the rules efficiently.

> **Note:** Preprocessors like Sass and Less add variables, loops, and functions to CSS — effectively creating a *new* DSL on top of CSS. This is a common evolution: when a DSL lacks a needed feature, users build a meta-DSL rather than abandoning the original.

---

## 2.2 Classification by Paradigm

The six DSLs surveyed above fall into three broad paradigms, distinguished by how they express computation.

### Declarative DSLs

A declarative DSL describes *what* the desired outcome is, leaving the *how* to the language's runtime or engine. The user specifies constraints, relationships, or properties — not the steps to achieve them.

SQL is the canonical example. The query `SELECT name FROM students WHERE age > 20` says nothing about index scans, hash joins, or sort algorithms. The query optimiser makes those decisions. Similarly, Terraform HCL declares resource configurations without specifying API call sequences, and CSS declares styles without specifying rendering algorithms.

Declarative DSLs excel when the domain has a well-understood execution model that can be optimised automatically. They are harder to design — the language author must build the "intelligence" that translates declarations into actions — but far easier to use.

### Imperative DSLs

An imperative DSL describes a sequence of actions to perform, step by step. Order matters, and the user controls the flow of execution.

Dockerfiles are imperative: `FROM` sets the base image, `COPY` copies files, `RUN` executes commands, each building on the previous step. The Makefile recipe lines are also imperative — they are shell commands executed in order.

Imperative DSLs are simpler to implement (the runtime just executes instructions in sequence) and more intuitive for users with programming backgrounds. However, they are harder to optimise because the runtime has less freedom to reorder or skip steps.

### Hybrid DSLs

Many real-world DSLs combine declarative and imperative elements. GraphQL is declarative for queries but uses imperative mutations for writes. Make's dependency graph is declarative, but its recipes are imperative. Even SQL has procedural extensions (`PL/pgSQL`, `T-SQL`) that add imperative control flow.

Hybrid DSLs often emerge when a purely declarative approach cannot cover all use cases. The key design challenge is keeping the two paradigms coherent — users should understand when they are in "declarative mode" and when they are in "imperative mode".

### Paradigm Comparison

| Aspect | Declarative | Imperative | Hybrid |
|---|---|---|---|
| **Describes** | What the result should be | Steps to perform | Both |
| **Order matters?** | No (usually) | Yes | Depends on context |
| **Optimisable?** | Highly | Limited | Partially |
| **Ease of use** | Higher for domain experts | Higher for programmers | Varies |
| **Implementation** | Complex runtime | Simple runtime | Mixed |
| **Examples** | SQL, CSS, Terraform HCL | Dockerfile, Make recipes | GraphQL, Make (overall) |

**When to choose each paradigm.** Use a declarative paradigm when the domain has a well-defined notion of "desired state" and the runtime can determine the best execution strategy. Use an imperative paradigm when the domain is naturally sequential and order is semantically important. Use a hybrid approach when the domain has both aspects — but be deliberate about the boundary between them.

---

## 2.3 Classification by Complexity

Paradigm tells us *how* a DSL expresses computation. Complexity tells us *how much* it can express. We identify three tiers.

### Micro-DSLs

Micro-DSLs have tiny grammars — often expressible in a few lines of EBNF — and extremely limited expressiveness. They solve one narrow problem and nothing else.

- **Regular expressions**: pattern matching on text (`\d{4}-\d{2}-\d{2}`)
- **Cron expressions**: scheduling (`0 9 * * MON-FRI`)
- **Glob patterns**: file matching (`src/**/*.py`)

Micro-DSLs typically have no variables, no types, no blocks, and no abstraction mechanisms. They are learned in minutes and mastered in hours. Their limitation is also their strength: there is almost no way to write a confusing cron expression (though regular expressions famously push this boundary).

### Medium DSLs

Medium DSLs have richer grammars with multiple statement types, domain-specific types, and some form of structuring mechanism (blocks, nesting, or sections). Most of the DSLs surveyed in Section 2.1 fall into this category.

- **SQL**: multiple clauses, subqueries, joins, aggregate functions, data types
- **CSS**: selectors, properties, media queries, cascading rules
- **MSD**: entities, associations, links, attributes, types, cardinalities

Medium DSLs take hours to learn and weeks to master. They are expressive enough to model their domain completely but lack general-purpose features like arbitrary computation, user-defined functions, or module systems.

### Full DSLs

Full DSLs approach the power of general-purpose languages while remaining anchored in a specific domain. They often include variables, functions, control flow, and module systems.

- **TeX**: a complete typesetting language with macros and Turing-complete expansion
- **Emacs Lisp**: a Lisp dialect specialised for text editing
- **Vim script**: an editor scripting language with its own type system

Full DSLs take weeks to learn and months to master. They offer great power but risk crossing the line into general-purpose territory, which brings the complexity costs of a GPL without the ecosystem benefits.

### Complexity Comparison

| Aspect | Micro-DSL | Medium DSL | Full DSL |
|---|---|---|---|
| **Grammar size** | 5–15 rules | 20–80 rules | 100+ rules |
| **Learning time** | Minutes to hours | Hours to weeks | Weeks to months |
| **Abstraction** | None | Limited (blocks, names) | Functions, macros, modules |
| **Types** | None or implicit | Domain-specific | Rich type system |
| **Turing-complete?** | No | Usually no | Often yes |
| **Examples** | Regex, cron, glob | SQL, CSS, MSD | TeX, Emacs Lisp, Vim script |

> **Tip:** When designing a new DSL, start at the micro or medium level. It is far easier to add expressiveness later than to remove complexity from an overgrown language. Many successful DSLs began as micro-DSLs and grew into medium DSLs over decades (CSS is a prime example).

---

## 2.4 Common Patterns Across DSLs

Despite their diversity, DSLs share recurring structural patterns. Recognising these patterns accelerates design — you do not need to reinvent them for each new language.

### Block Structure

Nearly every medium or full DSL groups related declarations into blocks. The delimiters vary, but the concept is universal.

**Curly braces** (SQL subqueries, Terraform, MSD):

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}
```

**Indentation** (Python, YAML, Makefile recipes):

```makefile
app: main.o
	gcc -o app main.o
```

**Keywords** (`BEGIN`/`END` in PL/SQL, `do`/`end` in Ruby DSLs):

```sql
BEGIN
    INSERT INTO log VALUES (NOW(), 'started');
END;
```

Block structure creates visual hierarchy and defines scoping boundaries. When designing a DSL, choose a block style that matches your users' expectations — web developers expect braces; data analysts expect indentation or keywords.

### References

DSLs that define multiple entities need a way to refer from one to another. This requires naming things and resolving those names later.

In **SQL**, table and column names are references:

```sql
SELECT s.name FROM students s
JOIN enrolments e ON s.id = e.student_id;
```

In **Terraform**, resources reference each other by path:

```hcl
subnet_id = aws_subnet.main.id
```

In **MSD**, associations reference entities by name:

```
association Enrol [Student, Course]
```

Reference resolution is one of the most important (and error-prone) aspects of DSL implementation. Chapter 6 covers semantic design for references, and Chapter 10 implements resolution with typo suggestions.

### Types

Even DSLs that are not "typed" in the programming-language sense often have a basic type system for validation. SQL has `INT`, `VARCHAR`, `DATE`. MSD has `INT`, `VARCHAR(n)`, `DATE`, and ten others. CSS has length units (`px`, `em`, `%`), colour values, and keywords.

Types serve two purposes in DSLs: they constrain what users can write (catching errors early) and they carry information that downstream tools need (a `VARCHAR(100)` column requires different storage from an `INT` column).

### Constraints

Constraints are rules that restrict valid programs beyond what syntax alone can enforce. They are part of the *semantic* layer.

- **SQL**: foreign key constraints, `NOT NULL`, `UNIQUE`
- **MSD**: cardinality rules (a link must specify exactly one of `(0,1)`, `(0,N)`, `(1,1)`, `(1,N)`)
- **Terraform**: required attributes, valid values for `instance_type`

Constraints are what make a DSL *safe*. Without them, syntactically valid programs can produce nonsensical results.

### Comments

Every DSL should allow human-readable annotations. Comment styles vary:

- **SQL**: `-- single line` and `/* multi-line */`
- **Terraform**: `#` and `//` for single-line, `/* */` for multi-line
- **MSD**: `// single line`

Comments seem trivial, but omitting them is a serious design mistake. Users *will* need to annotate their files, and without comments they will resort to ugly workarounds.

### Metadata

Many DSLs include a mechanism for project-level or file-level information that does not directly affect the domain model but is needed by tools.

In **MSD**, a `project` block carries metadata:

```
project {
    name: "University Database"
    author: "Dr. Hamza"
}
```

In **Terraform**, the `terraform` block configures providers and backend settings. In **SQL**, `SET` commands configure session parameters.

Metadata is often the first thing users encounter in a file, so it should be easy to read and write.

---

## 2.5 What Makes a DSL Succeed?

Not every DSL thrives. For every SQL there are dozens of forgotten query languages. What separates the successes from the failures?

### Domain Fit

The language must model its domain naturally. SQL succeeds because its core abstractions — tables, rows, columns, joins, filters — map directly onto the relational model. Users think in domain terms, and the language lets them express those terms without translation.

When a language forces users to think in implementation terms rather than domain terms, adoption suffers. The CODASYL network database model required users to navigate record-by-record through pointer chains — a faithful representation of the implementation but a poor model of *what users wanted to express*. SQL's declarative approach won because it matched how people think about data, not how machines store it.

### Learnability

A well-designed DSL can be *read* before it can be *written*. A non-programmer should be able to look at a SQL `SELECT` statement or a Terraform resource block and grasp the intent, even without formal training.

This read-before-write property comes from choosing familiar vocabulary (`SELECT`, `FROM`, `WHERE`), consistent syntax, and meaningful defaults. It also comes from keeping the language small — the fewer concepts to learn, the faster the onboarding.

### Tool Support

A DSL without decent error messages, editor support, or documentation is a DSL that frustrates its users into abandoning it. SQL benefits from decades of tooling: syntax highlighting, query planners, `EXPLAIN` output, IDE autocompletion. Terraform has `terraform validate`, `terraform plan`, and VS Code extensions.

Error messages deserve special attention. A DSL's error messages are often the primary way users learn the language. Saying "syntax error on line 7" teaches nothing; saying "expected attribute type after ':' on line 7, got '{' — did you forget the type?" teaches the language while fixing the problem.

### Community Adoption

Languages benefit from network effects. Once SQL reached critical mass, every database had to support it, every programmer had to learn it, and every textbook had to teach it. This creates a virtuous cycle: more users produce more documentation, more tools, and more demand.

A new DSL faces a bootstrapping problem. It must be *significantly* better than the alternatives to overcome the switching cost. MSD, for instance, competes with graphical-only modelling tools by offering version control, diffability, and scriptability — advantages that a GUI cannot match.

### Interoperability

A DSL that exists in isolation will remain a curiosity. Successful DSLs integrate with existing tools and workflows. SQL results feed into applications. Terraform outputs are consumed by CI/CD pipelines. CSS is embedded in HTML. MSD generates `.merisio` project files that the Merisio GUI can open, and produces SQL that databases can execute.

**The CODASYL lesson.** CODASYL's Data Manipulation Language was the dominant database approach in the 1970s. It failed not because it was technically inferior in all respects, but because it violated several of the principles above: it required imperative navigation rather than declarative queries (poor domain fit for most users), it was difficult to learn (low learnability), and its programs were tightly coupled to the physical data structure (poor interoperability). SQL offered a simpler mental model and won the market despite initially being slower.

---

## 2.6 Common DSL Anti-Patterns

Just as there are patterns that lead to success, there are anti-patterns that lead to failure. Recognising these early can save months of misguided design work.

### The "Kitchen Sink"

**Symptom:** The DSL grows features until it becomes a general-purpose language, but without the tooling, documentation, or ecosystem of a real GPL.

This happens when designers respond to every user request by adding a new language feature. "We need conditionals." "We need loops." "We need user-defined functions." Each addition seems reasonable in isolation, but cumulatively they transform a focused DSL into a clumsy programming language.

**Prevention:** Before adding a feature, ask: "Is this a domain concept, or a general computation concept?" If it is the latter, consider providing an escape hatch to a GPL rather than implementing it in the DSL.

### The "One Weird Trick"

**Symptom:** The syntax is so clever or unconventional that only the original author can read it fluently.

Regular expressions are sometimes cited here — the syntax is compact and powerful but notoriously difficult to read. APL-family languages take this further with symbolic operators that require specialised keyboards.

**Prevention:** Optimise for readability over conciseness. Remember that code is read far more often than it is written. A slightly more verbose syntax that reads like prose will always beat a terse syntax that reads like line noise.

### The "Island Language"

**Symptom:** The DSL has no way to integrate with other tools, export its data, or compose with other languages.

An island language traps its users. If the only way to use a diagram DSL is through its proprietary GUI, users cannot version-control their models, cannot generate documentation automatically, and cannot incorporate the DSL into CI/CD pipelines.

**Prevention:** Design for interoperability from the start. Support standard file formats for input and output. Provide a CLI tool alongside any GUI. Make the language's files plain text so that `diff`, `grep`, and version control work naturally.

### The "Error Desert"

**Symptom:** When users make mistakes, the language produces unhelpful, cryptic, or misleading error messages.

This is perhaps the most common anti-pattern and the most damaging. Users learn a DSL primarily through its error messages — every error is a teaching moment. An error message that says "parse error" with no location, no context, and no suggestion is a missed opportunity that drives users to frustration.

**Prevention:** Invest heavily in error messages. Include the file location (line and column). Describe what was expected and what was found. Suggest corrections where possible. Chapter 13 covers error handling in depth.

> **Warning:** The "error desert" anti-pattern is particularly insidious because it often does not emerge until the language has real users making real mistakes. Designers who test only with correct inputs will never encounter their own bad error messages. Always test your DSL with *incorrect* inputs, deliberately introducing every kind of mistake you can imagine.

---

## 2.7 Exercises

**Exercise 2.1 — Classify by Paradigm.**
Classify each of the following DSLs as declarative, imperative, or hybrid. Justify each classification in one or two sentences.

(a) JSON Schema — defines the structure that a JSON document must conform to.
(b) Ansible playbooks — describe a sequence of tasks to configure servers.
(c) HTML — describes the structure of a web page.
(d) CMake — orchestrates C/C++ build processes.
(e) PlantUML — generates UML diagrams from text descriptions.

**Exercise 2.2 — Classify by Complexity.**
For each DSL below, determine whether it is a micro-DSL, medium DSL, or full DSL. Explain what features push it into (or keep it out of) the next complexity tier.

(a) `.gitignore` patterns
(b) YAML
(c) Lua (as embedded in game engines)
(d) CSS (including modern features like custom properties and `calc()`)
(e) MSD

**Exercise 2.3 — Identify Patterns.**
Consider the following fragment of an imaginary DSL for defining REST APIs:

```
api UserService {
    // User management endpoints
    model User {
        id: UUID
        name: String
        email: Email
    }

    GET /users -> List<User>
    GET /users/{id} -> User
    POST /users (body: User) -> User
}
```

Identify which of the six common patterns from Section 2.4 (block structure, references, types, constraints, comments, metadata) are present in this fragment. For each pattern you identify, point to the specific syntax that implements it.

**Exercise 2.4 — Success Factors.**
Choose a DSL you use regularly (it can be any of those mentioned in this chapter or another). Evaluate it against the five success factors from Section 2.5. Where does it excel? Where does it fall short? What one change would most improve its weakest area?

**Exercise 2.5 — Anti-Pattern Detection.**
The following MSD fragment contains a hypothetical extension that introduces an anti-pattern. Identify the anti-pattern and explain why it is problematic.

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
    status: VARCHAR(20)

    computed average_grade {
        grades = SELECT avg(grade) FROM enrolments
                 WHERE student_id = self.student_id;
        if grades > 15 { return "excellent" }
        else { return "standard" }
    }
}
```

**Exercise 2.6 — Design a Micro-DSL.**
Design a micro-DSL for expressing email filter rules. A rule should be able to match on sender, subject, or body content and specify an action (move to folder, mark as read, delete, or forward to an address). Write at least three example rules in your syntax, then classify your design by paradigm and argue why that paradigm is appropriate.

---

## Summary

This chapter surveyed the landscape of external domain-specific languages, examining six influential examples — SQL, GraphQL, Terraform HCL, Dockerfile, Makefile, and CSS — and extracting general principles from their designs.

We developed two classification schemes. The **paradigm** classification distinguishes declarative DSLs (describing *what*), imperative DSLs (describing *how*), and hybrid DSLs (combining both). The **complexity** classification distinguishes micro-DSLs (tiny grammars), medium DSLs (richer structure and types), and full DSLs (approaching general-purpose power).

We identified six **common patterns** — block structure, references, types, constraints, comments, and metadata — that recur across successful DSLs. We examined five **success factors** that determine whether a DSL thrives: domain fit, learnability, tool support, community adoption, and interoperability. And we catalogued four **anti-patterns** — the kitchen sink, the one weird trick, the island language, and the error desert — that lead to DSL failure.

In the next chapter, we narrow our focus to a specific domain. Chapter 3 introduces MERISE conceptual data modelling, analyses its requirements, and sets the stage for designing MSD — the DSL that we will build throughout the rest of this book.
