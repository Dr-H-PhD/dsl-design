# Preface

## Why Domain-Specific Languages?

Every programmer uses domain-specific languages daily. SQL queries databases. CSS styles web pages. Regular expressions match text patterns. Makefiles orchestrate builds. Dockerfiles describe containers. These are not general-purpose programming languages — they are **domain-specific languages** (DSLs), each designed to excel at one particular task.

Yet while we all *use* DSLs, very few of us *design* them. The craft of creating a new language — choosing its syntax, defining its semantics, building its toolchain — remains something of a dark art, scattered across compiler textbooks, academic papers, and tribal knowledge. This book aims to change that.

## What You'll Learn

By the end of this book, you will:

- Understand the spectrum from configuration files to general-purpose languages, and where DSLs fit
- Know how to analyse a domain and extract the concepts that a language should express
- Design lexical, syntactic, and semantic rules for a new DSL
- Implement a complete language toolchain: lexer, parser, semantic analyser, and output generator
- Build automatic graph layout for visual output
- Design robust error handling with multi-error reporting and recovery
- Write comprehensive tests for every stage of the pipeline
- Integrate a DSL into both command-line and graphical tools

## The Case Study: MSD and Merisio

Theory without practice is incomplete. Throughout this book, we use a real DSL as our primary case study: **MSD** (Merisio Schema Definition), a language for defining MERISE conceptual data models as plain text. MSD is part of the Merisio project — a visual database modelling tool.

MSD is small enough to understand completely in one book, yet complex enough to illustrate every important DSL design decision: context-sensitive lexing, recursive descent parsing, name resolution with typo suggestions, force-directed graph layout, and multi-error recovery. Every code example in the implementation chapters is drawn from MSD's production codebase.

## Prerequisites

This book assumes you have:

- **Programming experience**: Comfort with at least one language; implementation examples use Python, but the concepts are language-agnostic
- **Basic data structures**: Familiarity with lists, dictionaries, trees, and graphs
- **Curiosity about languages**: An interest in how programming languages work beneath the surface

No prior compiler construction or formal language theory experience is required — we build everything from first principles.

## How to Use This Book

The book is organised into four parts:

1. **Foundations** (Chapters 1–3) introduces domain-specific languages, surveys the DSL landscape, and walks through domain analysis using the MERISE modelling domain as a case study.

2. **Language Design** (Chapters 4–7) covers the three layers of language design — lexical, syntactic, and semantic — then applies all three to design MSD from scratch.

3. **Implementation** (Chapters 8–12) builds a complete DSL toolchain: lexer, recursive descent parser, semantic analyser, output generator, and automatic graph layout engine.

4. **Quality and Integration** (Chapters 13–15) addresses error handling and recovery, testing strategies for DSL implementations, and integrating a DSL into CLI and GUI tools.

Each chapter follows a consistent structure:

- **Concepts**: The general theory, applicable to any DSL
- **Case Study**: How MSD applies the theory
- **Code Walkthrough**: Annotated implementation (in the implementation chapters)
- **Exercises**: 6–7 per chapter, progressing from comprehension to design challenges

The exercises are an essential part of the book. Many ask you to design syntax for hypothetical DSLs or extend MSD — these design exercises develop intuition that cannot be gained from reading alone.

## Conventions

Code examples use Python syntax highlighting:

```python
class MSDLexer:
    def tokenize(self, source: str) -> list:
        ...
```

MSD examples use a dedicated syntax:

```
entity Student {
    *student_id: INT
    name: VARCHAR(100)
}
```

Callout boxes highlight important information:

> **Tip:** Tips provide helpful shortcuts or best practices.

> **Warning:** Warnings alert you to common pitfalls or design traps.

> **Note:** Notes offer additional context or background information.

> **Info:** Info boxes provide supplementary technical details.

## Acknowledgements

MSD was designed as an improvement over the Mocodo DSL for MERISE modelling, addressing its limitations in explicit primary keys, data types, and error reporting. The Merisio project itself was inspired by AnalyseSI, a Java-based MERISE tool widely used in French computer science education.

The general principles in this book draw on decades of research in programming language design, from Backus-Naur Form to modern language workbenches. The specific techniques — recursive descent parsing, panic-mode error recovery, Fruchterman-Reingold layout — are established methods refined through practical application.

## Let's Begin

Designing a domain-specific language is one of the most rewarding tasks in software engineering. You are not just writing code — you are creating a new way for people to express ideas. A well-designed DSL can turn a complex, error-prone task into something elegant and intuitive.

Turn the page, and let's design a language.

---

*Achraf SOLTANI*
*www.achrafsoltani.com*
