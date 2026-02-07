\newpage

# Appendix D: Glossary

## General DSL Terms

**Abstract Syntax Tree (AST)**
A tree representation of the syntactic structure of source code. Each node represents a construct in the language. In simpler DSLs, a flat intermediate representation may be used instead of a full tree.

**Ambiguity**
A property of a grammar where a single input can be parsed in more than one way, producing multiple valid parse trees. Ambiguous grammars should be avoided in DSL design.

**Backtracking**
A parsing technique where the parser tries one alternative, and if it fails, reverses its progress and tries another. LL(1) grammars do not require backtracking.

**Block Structure**
A syntactic pattern where related declarations are grouped inside delimiters, typically braces (`{ }`), keywords (`begin`/`end`), or indentation.

**Builder**
The semantic analysis component that transforms a parser's intermediate representation into the final output. It performs validation, name resolution, and object construction.

**Cascade Error**
A false error caused by the parser's recovery from a previous genuine error. Cascade errors are a common problem in multi-error reporting.

**Case Sensitivity**
Whether uppercase and lowercase letters are treated as distinct. A language may be case-sensitive for identifiers but case-insensitive for keywords.

**Comment**
Text in source code that is ignored by the lexer. Common styles include line comments (`#`, `//`) and block comments (`/* */`).

**Context-Free Grammar**
A grammar where every production rule can be applied regardless of context. Most programming languages and DSLs are defined by context-free grammars.

**Context-Sensitive Lexing**
A lexing technique where the tokenisation of a character sequence depends on the surrounding context. For example, a colon inside a project block may trigger a different token type than a colon elsewhere.

**Domain-Specific Language (DSL)**
A programming language designed for a specific application domain, as opposed to a general-purpose language. Examples: SQL (databases), CSS (styling), Make (build automation).

**EBNF (Extended Backus-Naur Form)**
A notation for defining context-free grammars. Extends BNF with repetition (`{ }`), optionality (`[ ]`), and grouping (`( )`).

**Error Recovery**
The ability of a parser to continue parsing after encountering a syntax error, enabling it to report multiple errors in a single pass.

**Exit Code**
A numeric value returned by a command-line program to indicate success (0) or failure (non-zero). Different exit codes can distinguish between different failure modes.

**External DSL**
A DSL with its own syntax, lexer, and parser, independent of any host language. MSD is an external DSL. Contrast with *internal DSL*.

**Forward Reference**
A reference to a name that is declared later in the source. Some DSLs support forward references; others require declaration before use.

**General-Purpose Language (GPL)**
A programming language designed for a wide variety of tasks, such as Python, Java, Go, or C. Contrast with *domain-specific language*.

**Identifier**
A name given by the user to a concept in the language — such as an entity name, attribute name, or association name. Typically matches the pattern `[a-zA-Z_][a-zA-Z0-9_]*`.

**Intermediate Representation (IR)**
A data structure produced by the parser that captures the syntactic content of the input. The builder transforms the IR into the final output. Using an IR decouples parsing from semantic analysis.

**Internal DSL**
A DSL implemented within a host language, using the host's syntax. Ruby's Rake and Kotlin's Gradle scripts are internal DSLs. Contrast with *external DSL*.

**Keyword**
A reserved word in a language with a predefined meaning. In MSD, the keywords are `project`, `entity`, `association`, and `link`.

**Levenshtein Distance**
A measure of the difference between two strings, defined as the minimum number of single-character insertions, deletions, or substitutions needed to transform one string into the other. Used for "did you mean?" suggestions.

**Lexer (Tokeniser)**
The component that reads source text and produces a sequence of tokens. The lexer handles whitespace, comments, keywords, identifiers, literals, and symbols.

**LL(1)**
A class of grammars that can be parsed by reading input left-to-right, producing a leftmost derivation, with one token of lookahead. LL(1) grammars are ideal for recursive descent parsers.

**Lookahead**
The number of tokens a parser examines ahead of the current position to decide which grammar rule to apply. LL(1) parsers use a single token of lookahead.

**Multi-Error Reporting**
The ability to report all errors in a single pass, rather than stopping at the first error. Requires error recovery in the parser.

**Newline Significance**
A design choice where newline characters carry syntactic meaning — for example, separating statements or attributes. Contrast with languages where newlines are mere whitespace.

**Panic Mode**
An error recovery strategy where the parser, upon encountering an unexpected token, skips tokens until it reaches a synchronisation point, then resumes normal parsing.

**Parse Result**
The intermediate representation produced by the parser. Contains the parsed declarations (entities, associations, links) and any errors or warnings accumulated during parsing.

**Parser**
The component that reads a token stream and produces a structured representation (AST or IR) according to the grammar rules.

**Production Rule**
A rule in a grammar that defines how a non-terminal can be expanded into a sequence of terminals and non-terminals. For example: `entity_block = "entity" IDENTIFIER "{" { attribute } "}"`.

**Recursive Descent Parser**
A top-down parsing technique where each non-terminal in the grammar is implemented as a function. The function calls other functions corresponding to the non-terminals in its production rule.

**Semantic Analysis**
The phase after parsing that checks meaning-level constraints: name resolution, type checking, uniqueness validation, and reference integrity.

**Severity**
The classification of a diagnostic message. Common levels: *error* (fatal — the tool cannot produce correct output) and *warning* (informational — the tool can proceed).

**Synchronisation Point**
A token or set of tokens used by panic-mode recovery to determine where normal parsing can resume. Typical synchronisation points include keywords, closing braces, and statement delimiters.

**Token**
The smallest meaningful unit produced by the lexer. Each token has a type (e.g., `IDENTIFIER`, `LBRACE`), a value (e.g., `"Tourist"`, `"{"`), and a position (line and column).

**Tokeniser**
See *Lexer*.

## MSD-Specific Terms

**Association**
A named relationship between two or more entities in a MERISE conceptual data model. Declared with the `association` keyword. May carry its own attributes.

**Attribute**
A named property of an entity or association, with a data type. Declared as `name: TYPE` or `*name: TYPE` (for primary keys).

**Cardinality**
The constraint on how many instances of one entity can participate in an association. Expressed as a pair `(min, max)` where min is `0` or `1` and max is `1` or `N`.

**Entity**
A named concept in a MERISE conceptual data model, representing a distinct class of objects. Declared with the `entity` keyword. Contains attributes, at least one of which should be a primary key.

**Link**
A statement connecting an entity to an association with a cardinality constraint. Declared as `link EntityName (min,max) AssociationName`.

**MCD (Modele Conceptuel de Donnees)**
The Conceptual Data Model in the MERISE methodology. Consists of entities, associations, and links with cardinalities. MSD describes MCDs in text form.

**MERISE**
A French information systems design methodology developed in the late 1970s. Widely used in French-speaking countries for database design. Distinguishes conceptual (MCD), logical (MLD), and physical models.

**Merisio**
A visual MERISE modelling tool. MSD is the text-based input format for Merisio. The tool provides both a GUI (visual editor) and a CLI (`merisio-cli`) for headless processing.

**MLD (Modele Logique de Donnees)**
The Logical Data Model in the MERISE methodology. Derived from the MCD by applying transformation rules (e.g., resolving many-to-many relationships into junction tables).

**MSD (Merisio Schema Definition)**
A domain-specific language for describing MERISE conceptual data models in plain text. Features 4 keywords, 13 data types, and an LL(1) grammar.

**`.merisio` File**
The JSON project file format used by Merisio. Contains the complete model (entities, associations, links, layout positions, metadata). Produced by the MSD pipeline or by saving from the GUI.

**`.msd` File**
A plain text file containing MSD source code. Processed by the MSD pipeline (lexer → parser → builder) to produce a `.merisio` project file.

**Primary Key**
An attribute (or set of attributes) that uniquely identifies an instance of an entity. Marked with the `*` prefix in MSD. An entity without a primary key triggers a warning.

**Project Block**
An optional metadata section in an MSD file, declared with the `project` keyword. Contains key-value pairs such as `name`, `author`, and `description`.

**`STRING_VALUE`**
A context-sensitive token type used inside project blocks. Captures the rest of the line after a colon, allowing unquoted text values (e.g., `name: Tourism System`).
