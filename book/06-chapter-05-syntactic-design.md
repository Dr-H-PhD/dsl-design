\newpage

# Chapter 5: Syntactic Design

The previous chapter established the lexical layer — the vocabulary of a language. Tokens are the words, but words alone do not make sentences. *Syntax* is the grammar that arranges tokens into meaningful structures. It is the difference between a bag of words and a well-formed program.

This chapter explores the principles and techniques of syntactic design for domain-specific languages. We shall formalise grammars using EBNF notation, understand why LL(1) grammars are particularly well suited to hand-written parsers, and examine the design decisions that shape how users experience a language: block structure, line orientation, nesting depth, and delimiter choice. Throughout, we use MSD as our running case study, but the principles apply to any DSL you might design.

---

## 5.1 From Tokens to Structure

A lexer produces a flat stream of tokens. The parser's job is to impose *structure* on that stream — to recognise which tokens belong together, how they nest, and what they mean in relation to one another.

Consider the following MSD fragment:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}
```

The lexer produces tokens: `ENTITY`, `IDENTIFIER("Student")`, `LBRACE`, `STAR`, `IDENTIFIER("student_id")`, `COLON`, `IDENTIFIER("INT")`, `IDENTIFIER("name")`, `COLON`, `IDENTIFIER("VARCHAR")`, `LPAREN`, `INTEGER("100")`, `RPAREN`, `RBRACE`. But this flat list tells us nothing about which attributes belong to which entity, or which identifier is a name and which is a type. The parser discovers that structure.

**Why syntax matters beyond correctness.** Syntax is not merely a technical concern — it determines how users *think* about the language. A language with deeply nested, bracket-heavy syntax feels different from one with clean, line-oriented declarations. The syntax of SQL (`SELECT ... FROM ... WHERE ...`) encourages users to think in terms of data queries. The syntax of CSS (`selector { property: value; }`) encourages users to think in terms of styling rules applied to elements. Your syntactic choices shape the mental model that users build.

**The relationship between grammar and parser.** A grammar is a *specification* — a precise description of which token sequences are valid. A parser is an *implementation* — a program that checks whether a given token sequence conforms to the grammar and, if so, builds a structured representation. The grammar comes first; the parser follows. In practice, the two influence each other: certain grammar styles are easier to parse than others, and practical parsing constraints may feed back into grammar design.

---

## 5.2 EBNF Notation

To specify a grammar precisely, we need a notation. The standard choice is **Extended Backus-Naur Form** (EBNF), a notation developed from the original BNF used to define ALGOL 60. EBNF adds constructs for optional elements, repetition, and grouping, making grammars more concise and readable.

### Notation Reference

| Symbol      | Meaning                        | Example                          |
|-------------|--------------------------------|----------------------------------|
| `=`         | Definition (is defined as)     | `entity_block = ...`             |
| `\|`        | Alternative (or)               | `"0" \| "1"`                     |
| `[ ]`       | Optional (zero or one)         | `[ "*" ]`                        |
| `{ }`       | Repetition (zero or more)      | `{ attribute }`                  |
| `( )`       | Grouping                       | `( "0" \| "1" )`                |
| `" "`       | Terminal (literal token)       | `"entity"`                       |
| `;`         | End of production              | `entity_block = ... ;`           |

Non-terminals (rule names) are written in lowercase with underscores. Terminals are quoted strings representing literal tokens or token types.

### Example: An Entity Block in MSD

Let us write the EBNF grammar for an MSD entity block:

```
entity_block = "entity" IDENTIFIER "{" { attribute } "}" ;

attribute    = [ "*" ] IDENTIFIER ":" type_expr ;

type_expr    = TYPE_NAME [ "(" INTEGER ")" ] ;
```

Reading these productions aloud:

- An **entity block** is the keyword `entity`, followed by an identifier (the entity name), followed by a left brace, followed by zero or more attributes, followed by a right brace.

- An **attribute** is an optional asterisk (marking a primary key), followed by an identifier (the attribute name), followed by a colon, followed by a type expression.

- A **type expression** is a type name, optionally followed by a size in parentheses.

### Writing EBNF Productions

When writing EBNF, follow these guidelines:

1. **Start with the top-level rule.** What is the outermost structure of a valid file?

2. **Break complex rules into sub-rules.** If a production is growing unwieldy, extract a named sub-rule.

3. **Use repetition `{ }` for lists.** Avoid recursive definitions when iteration suffices.

4. **Use alternatives `|` for choices.** Each alternative should begin with a distinct token to aid parsing.

5. **Name rules after what they represent**, not how they are parsed.

### Why Formal Grammars Matter

An informal specification such as "an entity has a name and some attributes inside braces" is ambiguous. Are braces required? Can an entity have zero attributes? Can the name be omitted? A formal EBNF grammar answers all of these questions unambiguously. It serves as a contract between the language designer and the parser implementer — and when you are both, it serves as a contract between your design self and your implementation self.

> **Tip:** Write your EBNF grammar *before* you write your parser. The grammar is your blueprint. Changing a grammar rule is far cheaper than refactoring a parser.

> **Programmer:** EBNF notation is to parser implementation what an interface definition is to Go code. Just as a Go `interface` specifies the contract a type must satisfy without dictating the implementation, an EBNF grammar specifies which token sequences are valid without dictating how the parser processes them. Go's own grammar is published formally in the language specification, and the `go/parser` package is a direct translation of that grammar into recursive descent code. When you design your DSL, write the EBNF first and treat it as a binding contract: every production rule becomes a function, every alternative becomes a `switch` or `if` block, and every repetition becomes a `for` loop. This mechanical correspondence is what makes recursive descent parsers so maintainable.

---

## 5.3 LL(1) Grammars and Why They Matter

### What LL(1) Means

The notation **LL(1)** stands for:

- **L** — Left-to-right scanning of the input (we read tokens from left to right)

- **L** — Leftmost derivation (we always expand the leftmost non-terminal first)

- **1** — One token of lookahead (we decide which production to apply by examining only the next token)

An LL(1) grammar is one where, at every point in parsing, looking at the single next token is sufficient to determine which production rule to apply. There is never any ambiguity or backtracking required.

### Why LL(1) Is Ideal for Hand-Written Parsers

When you write a recursive descent parser — a parser where each grammar rule becomes a function — the LL(1) property is invaluable. Each parsing function can inspect the next token and immediately decide what to do:

```python
def _parse_top_level(self):
    tok = self._peek()
    if tok.type == TokenType.ENTITY:
        self._parse_entity_block()
    elif tok.type == TokenType.ASSOCIATION:
        self._parse_association_block()
    elif tok.type == TokenType.LINK:
        self._parse_link_statement()
    elif tok.type == TokenType.PROJECT:
        self._parse_project_block()
```

One token of lookahead. No backtracking. No ambiguity. This is the direct consequence of MSD having an LL(1) grammar.

### Checking LL(1): FIRST and FOLLOW Sets

To verify that a grammar is LL(1), compiler theory defines two functions:

- **FIRST(A)**: the set of tokens that can appear at the beginning of any string derived from rule A.

- **FOLLOW(A)**: the set of tokens that can appear immediately after a string derived from A.

A grammar is LL(1) if, for every rule with alternatives `A = B | C`, the FIRST sets of B and C are disjoint. Intuitively: if two alternatives can both start with the same token, the parser cannot tell them apart with one token of lookahead.

For MSD's top-level rule:

```
program      = { top_level } ;
top_level    = project_block | entity_block | association_block | link_stmt ;
```

The FIRST sets are:

- FIRST(project_block) = { `"project"` }
- FIRST(entity_block) = { `"entity"` }
- FIRST(association_block) = { `"association"` }
- FIRST(link_stmt) = { `"link"` }

These four sets are completely disjoint — each alternative starts with a unique keyword. The grammar is LL(1) at the top level.

### When a Grammar Is Not LL(1)

Two common problems prevent a grammar from being LL(1):

**Left recursion.** A rule that refers to itself as its first element:

```
expr = expr "+" term | term ;
```

This is left-recursive because `expr` appears as the first symbol on the right-hand side of its own definition. A recursive descent parser would call `_parse_expr()`, which would immediately call `_parse_expr()` again, creating infinite recursion.

**Common prefixes.** Two alternatives that begin with the same tokens:

```
stmt = "if" expr "then" stmt ;
     | "if" expr "then" stmt "else" stmt ;
```

Both alternatives start with `"if"`, so looking at the next token (`if`) does not tell the parser which rule to apply.

### Transforming Non-LL(1) Grammars

**Removing left recursion.** The left-recursive rule:

```
expr = expr "+" term | term ;
```

is transformed into:

```
expr      = term { "+" term } ;
```

The recursive call is replaced by iteration, which a hand-written parser handles with a `while` loop.

**Left factoring.** The common-prefix rule:

```
stmt = "if" expr "then" stmt [ "else" stmt ] ;
```

The shared prefix `"if" expr "then" stmt` is factored out, and the `"else"` clause becomes optional. The parser consumes the common prefix, then checks whether an `"else"` follows.

> **Note:** MSD's grammar is naturally LL(1) without any transformations. Each top-level construct starts with a unique keyword (`project`, `entity`, `association`, `link`), and within blocks, the structure is regular enough that one token of lookahead always suffices. This is not an accident — it is a deliberate design choice that simplifies the parser enormously.

> **Programmer:** Go's grammar is deliberately LL(1) for the same reason MSD's is: fast, predictable parsing with no backtracking. This is why Go compiles faster than almost any other compiled language at scale. The Go specification explicitly avoids ambiguous constructs -- there is no ternary operator, no implicit type conversions, and statement-ending semicolons are inserted automatically by the lexer so that the parser never has to guess where a statement ends. If you are designing a DSL in Go, you can leverage Go's own parsing infrastructure directly: the `go/scanner` package handles LL(1) token scanning with automatic semicolon insertion, and its source code is a concise, readable example of how to build a production-quality lexer for an LL(1) grammar.

---

## 5.4 Block-Structured Syntax

Nearly every language groups related declarations into *blocks*. The question is: how are those blocks delimited?

### Curly-Brace Blocks

Used by: C, C++, Java, Go, JavaScript, CSS, Terraform HCL, MSD.

```
// MSD
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}
```

```
// Terraform HCL
resource "aws_instance" "web" {
    ami           = "ami-0c55b159cbfafe1f0"
    instance_type = "t2.micro"
}
```

**Advantages:** Explicit scope boundaries. The parser can always identify where a block begins and ends. Indentation is for humans, not the machine — misindented code still parses correctly.

**Disadvantages:** Visual noise from brace characters. Debates about brace placement style (same line vs next line).

### Indentation-Based Blocks

Used by: Python, YAML, Haskell (layout rule), Nim, CoffeeScript.

```yaml
# YAML
student:
    id: 1
    name: "Alice"
    enrolled_in:
        - "Mathematics"
        - "Physics"
```

**Advantages:** Clean visual appearance. What you see is what the compiler sees — indentation is the structure.

**Disadvantages:** Whitespace sensitivity creates subtle bugs (tabs vs spaces, inconsistent indentation). Copy-pasting code can break structure. Parsing is more complex because the lexer must track indentation levels and emit synthetic INDENT/DEDENT tokens.

### Keyword-Based Blocks

Used by: Pascal (`begin`/`end`), Ruby (`do`/`end`), SQL (`BEGIN`/`END`), Ada, VHDL.

```pascal
// Pascal
procedure Greet;
begin
    WriteLn('Hello');
end;
```

**Advantages:** Very explicit. Good for languages where blocks are infrequent.

**Disadvantages:** Verbose. The keywords `begin` and `end` consume visual space without adding information beyond what braces provide more concisely.

### MSD's Choice: Curly Braces

MSD uses curly braces for blocks:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}

association enrolled_in {
    enrollment_date: DATE
}
```

The reasons are:

1. **Familiarity.** Most MSD users will have encountered C-family languages, JSON, or CSS. Curly braces are immediately understood.

2. **Explicit structure.** The parser can unambiguously find block boundaries without tracking whitespace.

3. **Easy parsing.** `LBRACE` and `RBRACE` are single-character tokens. No indentation tracking required.

4. **Error recovery.** When the parser encounters an error inside a block, it can skip forward to the closing brace and resume parsing the next construct.

---

## 5.5 Line-Oriented vs Expression-Based Syntax

### Line-Oriented Syntax

In a line-oriented language, each line is a self-contained statement. The newline character acts as an implicit statement terminator.

MSD attributes are line-oriented:

```
*student_id: INT
name: VARCHAR(100)
date_of_birth: DATE
```

Each attribute occupies exactly one line. There is no mechanism for an attribute to span multiple lines, and no need for one — attributes are simple enough that a single line always suffices.

Other line-oriented DSLs include:

```makefile
# Makefile
build: main.o utils.o
	gcc -o program main.o utils.o
```

```ini
# .ini file
[database]
host = localhost
port = 5432
```

**Advantages:** Simple mental model. Users can reason about each line independently. Parsing is straightforward — the lexer emits NEWLINE tokens that act as statement boundaries.

**Disadvantages:** Long declarations must be broken awkwardly. Not suitable for deeply nested or compositional structures.

### Expression-Based Syntax

In expression-based languages, constructs can nest arbitrarily and span multiple lines:

```lisp
;; Lisp
(define (factorial n)
  (if (<= n 1)
      1
      (* n (factorial (- n 1)))))
```

```haskell
-- Haskell
factorial n
  | n <= 1    = 1
  | otherwise = n * factorial (n - 1)
```

**Advantages:** Highly compositional. Complex structures emerge naturally from nesting simple ones.

**Disadvantages:** Can become difficult to read without careful formatting. Parsing is more involved.

### MSD's Approach

MSD is primarily line-oriented within blocks, but flexible between constructs:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}

link Student (0,N) enrolled_in
link Student (1,1) belongs_to
```

Attributes within a block are one-per-line. Link statements are one-per-line. But the blank lines between top-level constructs are optional — the parser skips newlines between constructs freely. This gives users the freedom to organise their files visually without the parser being rigid about layout.

> **Info:** MSD's parser uses `_skip_newlines()` liberally between constructs. Inside blocks, NEWLINE tokens separate attributes. Between blocks, they are ignored. This two-level treatment — significant newlines inside blocks, insignificant newlines between blocks — gives users formatting freedom while keeping the grammar simple.

---

## 5.6 Nesting, Grouping, and Delimiters

### Nesting Depth

Every language has a maximum practical nesting depth. In general-purpose languages, nesting can be arbitrarily deep (functions within classes within modules within packages). In DSLs, nesting is typically shallow by design.

MSD has exactly two levels of nesting:

```
file
  └── entity/association/project block
        └── attribute
```

A file contains blocks. Blocks contain attributes. Attributes do not contain further blocks. This flat structure is intentional — a conceptual data model does not require deep nesting, and limiting depth keeps the grammar and parser simple.

Compare with a more deeply nested DSL like Terraform:

```hcl
resource "aws_instance" "web" {
    provisioner "remote-exec" {
        inline = [
            "echo 'Hello'"
        ]
    }
}
```

Here we have file, resource block, provisioner block, and list literal — four levels. The additional depth is justified by the domain's complexity, but it comes at a cost in grammar and parser complexity.

**Guideline:** Choose the minimum nesting depth that your domain requires. Every additional level adds grammar rules, parser complexity, and cognitive load for users.

### Grouping with Parentheses

Parentheses serve two distinct purposes in MSD:

1. **Cardinalities in links:** `(0,N)`, `(1,1)`
2. **Type sizes:** `VARCHAR(255)`, `DECIMAL(10)`

These two uses are unambiguous because they appear in different syntactic contexts. In a link statement, parentheses follow an entity name; in a type expression, they follow a type name. The parser always knows which interpretation applies.

### Delimiter Choices

When a block contains multiple items, how are they separated?

| Strategy          | Example                                | Used By                  |
|-------------------|----------------------------------------|--------------------------|
| Commas            | `[1, 2, 3]`                           | JSON, Python lists       |
| Semicolons        | `int x; int y;`                        | C, Java, CSS             |
| Newlines          | `name: TEXT` (next line) `age: INT`    | MSD, YAML, .ini          |
| Nothing (juxtaposition) | `(+ 1 2)`                        | Lisp, Haskell            |

MSD uses **newlines** as delimiters between attributes. No commas or semicolons are required:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
    email: VARCHAR(255)
}
```

This choice reduces visual noise. In a DSL where each item fits on one line, newlines are the natural separator — they are already there for readability. Adding commas or semicolons would be redundant punctuation that serves no purpose beyond satisfying the parser, and a well-designed parser should not require them.

---

## 5.7 Ambiguity and How to Avoid It

### What Syntactic Ambiguity Means

A grammar is **ambiguous** if there exists at least one input string that can be parsed in two or more structurally different ways. Ambiguity is a property of the grammar, not the input. An ambiguous grammar is problematic because the parser cannot determine which interpretation the user intended.

### The Classic Example: Dangling Else

Consider this grammar fragment:

```
stmt = "if" expr "then" stmt
     | "if" expr "then" stmt "else" stmt
     | other_stmt ;
```

Given the input `if a then if b then s1 else s2`, there are two valid parse trees:

1. `if a then (if b then s1 else s2)` — the `else` belongs to the inner `if`
2. `if a then (if b then s1) else s2` — the `else` belongs to the outer `if`

Both are valid according to the grammar. Most languages resolve this by convention (the `else` binds to the nearest `if`), but the grammar itself is ambiguous.

### How Ambiguity Arises in DSLs

Common sources of ambiguity in DSL design:

- **Overloaded keywords.** If the same keyword introduces two different constructs, the parser may not be able to distinguish them.

- **Optional clauses.** When multiple optional elements can be omitted, the parser may not know which ones are present.

- **Shared prefixes.** Two constructs that begin identically force the parser to look ahead further to disambiguate.

### Strategies for Avoiding Ambiguity

1. **Unique keywords for each construct.** MSD uses `entity`, `association`, `link`, and `project` — four distinct keywords for four distinct constructs. No ambiguity is possible at the top level.

2. **Explicit delimiters.** Curly braces mark block boundaries unambiguously. There is no question about where a block ends.

3. **Fixed structure within constructs.** MSD link statements follow a rigid pattern — `link EntityName (min,max) AssociationName` — with no optional parts that could shift the meaning of subsequent tokens.

4. **Context-free alternatives.** Where alternatives exist (e.g., an attribute may or may not be a primary key), the distinguishing token (`*`) appears first, before any shared structure.

### MSD's Ambiguity-Free Design

The complete MSD grammar has no ambiguity. Every valid MSD file has exactly one parse tree. This is achieved through the combination of unique top-level keywords, brace-delimited blocks, and fixed-structure statements:

```
program     = { top_level } ;
top_level   = project_block | entity_block | assoc_block | link_stmt ;

project_block = "project" "{" { project_prop } "}" ;
project_prop  = IDENTIFIER ":" STRING_VALUE ;

entity_block  = "entity" IDENTIFIER "{" { attribute } "}" ;
assoc_block   = "association" IDENTIFIER "{" { attribute } "}" ;

attribute     = [ "*" ] IDENTIFIER ":" type_expr ;
type_expr     = TYPE_NAME [ "(" INTEGER ")" ] ;

link_stmt     = "link" IDENTIFIER "(" card_min "," card_max ")" IDENTIFIER ;
card_min      = "0" | "1" ;
card_max      = "1" | "N" ;
```

Each rule begins with a unique token. Each block has explicit delimiters. Each statement has a fixed structure. Ambiguity simply has no room to enter.

---

## 5.8 Designing for Readability vs Parseability

### The Tension

The most readable syntax is not always the easiest to parse, and the easiest syntax to parse is not always the most readable. Language design involves navigating this tension.

A perfectly parseable syntax might look like:

```
ENTITY Student LBRACE ATTR PK student_id COLON INT ATTR name COLON VARCHAR LPAREN 100 RPAREN RBRACE
```

Every token type is explicit. Parsing is trivial. But no human would want to write this.

A perfectly readable syntax might look like:

```
Student has attributes:
    student_id (primary key, integer)
    name (text, up to 100 characters)
```

This reads like natural English. But parsing natural language is one of the hardest problems in computer science.

MSD navigates between these extremes:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}
```

It borrows familiar conventions (curly braces from C, `key: value` from YAML, `*` for special marking) while maintaining a structure that is straightforward to parse.

### Case Study: MSD Cardinalities

MSD's link syntax illustrates the readability-parseability tension well:

```
link Student (0,N) enrolled_in
```

This reads naturally: "link Student, with cardinality zero to many, to enrolled_in." But the cardinality `(0,N)` presents a parsing subtlety: the minimum is always an INTEGER token (`0` or `1`), whilst the maximum can be either an INTEGER (`1`) or an IDENTIFIER (`N`). The parser must accept both token types in the maximum position:

```python
max_tok = self._expect(TokenType.INTEGER, TokenType.IDENTIFIER)
```

A more parseable design might have been `(0,*)` (using a symbol instead of a letter) or `0..N` (using a range operator). But `(0,N)` was chosen because it is the standard MERISE notation that every user of the language already knows. The small parsing complication is worth the domain familiarity.

### The 80/20 Rule

Optimise your syntax for the 80% case — the constructs that users will write most often. Make those constructs as clean and readable as possible, even if it means slightly more complex parsing. For the 20% of less common constructs, ensure they are *possible* but accept that they may be slightly more verbose.

In MSD, entities and attributes are the 80% case. They are clean and minimal. Link statements are slightly more complex (the cardinality syntax), but links are written less frequently than attributes — you write one link per relationship, but multiple attributes per entity.

### Trade-offs in MSD

| Design Decision            | Readability                            | Parseability                     |
|----------------------------|----------------------------------------|----------------------------------|
| `entity Name { ... }`     | Familiar, clear block structure        | Simple: keyword, name, braces   |
| `*attr: TYPE`             | Concise primary key marker             | Simple: optional star prefix    |
| `link E (0,N) A`          | Reads like MERISE notation             | Mixed token types in cardinality|
| Newlines as separators     | No visual noise from commas            | Must handle flexible whitespace |
| No semicolons              | Cleaner appearance                     | Newlines carry structural weight|

> **Warning:** Do not sacrifice readability for parsing convenience. You write the parser once; users write in the language every day. A few extra lines in the parser are always preferable to a syntax that frustrates users.

---

## 5.9 Exercises

**Exercise 5.1** — Write an EBNF grammar for a DSL that describes REST API endpoints. Support path parameters (`/users/{id}`), HTTP methods (`GET`, `POST`, `PUT`, `DELETE`), and request/response type annotations. For example:

```
endpoint GET /users/{id} {
    response: User
}

endpoint POST /users {
    request: CreateUserInput
    response: User
}
```

Your grammar should handle the path segment syntax, including parameters with optional type constraints (e.g., `{id:int}`).

---

**Exercise 5.2** — The MSD grammar uses `{ }` for blocks. Redesign the syntax using Python-style indentation. Write the EBNF grammar for your indentation-based version. What additional token types must the lexer produce? What parsing challenges does this create that the brace-based grammar avoids?

---

**Exercise 5.3** — Is the following grammar LL(1)? If not, identify the problem and transform it into an equivalent LL(1) grammar.

```
stmt = "if" expr "then" stmt
     | "if" expr "then" stmt "else" stmt
     | IDENTIFIER "=" expr ;
```

Show the FIRST sets for each alternative of the original grammar to demonstrate the conflict, then write the transformed grammar.

---

**Exercise 5.4** — Consider a DSL for defining state machines:

```
state Idle {
    on Click -> Active
    on Timeout -> Idle
}

state Active {
    on Release -> Idle
    on Error -> Failed
}
```

Write the complete EBNF grammar. Verify that it is LL(1) by examining the FIRST sets of each alternative at every decision point.

---

**Exercise 5.5** — MSD uses newlines to separate attributes within blocks. Redesign the attribute syntax to use commas instead:

```
entity Student {
    *student_id: INT, name: VARCHAR(100), email: VARCHAR(255)
}
```

Write the EBNF for this variant. What are the trade-offs? Does this change affect the LL(1) property? Consider the impact on error recovery when a user makes a syntax error in the middle of a comma-separated list versus a newline-separated list.

---

**Exercise 5.6** — Remove the left recursion from the following grammar and rewrite it using EBNF repetition:

```
expr   = expr "+" term | expr "-" term | term ;
term   = term "*" factor | term "/" factor | factor ;
factor = INTEGER | "(" expr ")" ;
```

Verify that your transformed grammar is LL(1).

---

**Exercise 5.7** — Design the syntax for a DSL that describes database migration steps. It should support creating tables, adding columns, dropping columns, and renaming columns. For each operation, the user should specify the table name, column details, and data types. Write the EBNF grammar and explain three design decisions you made, justifying each in terms of readability and parseability.

---

## Summary

Syntactic design is where a language takes shape. The choices you make — block delimiters, statement structure, nesting depth, delimiter style — determine not only how easy the language is to parse, but how users think about and interact with it.

Key principles from this chapter:

- **Formalise your grammar in EBNF before writing a parser.** The grammar is the specification; the parser is the implementation.

- **Aim for LL(1).** A grammar where one token of lookahead suffices is a grammar that yields a clean, simple, maintainable recursive descent parser.

- **Choose block structure deliberately.** Curly braces, indentation, and keywords each have trade-offs. Pick the style that best serves your domain and your users.

- **Prefer shallow nesting.** Every level of nesting adds complexity. Use the minimum depth your domain requires.

- **Eliminate ambiguity by design.** Unique keywords, explicit delimiters, and fixed-structure statements prevent ambiguity from arising in the first place.

- **Optimise for readability.** The parser is written once; the language is used daily. When readability and parseability conflict, favour the user.

In the next chapter, we move beyond syntax to *semantics* — the meaning of well-formed programs. A syntactically valid MSD file can still contain errors: references to entities that do not exist, duplicate attribute names, or cardinalities that make no sense. Semantic analysis catches what syntax cannot.
