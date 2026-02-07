# Designing Domain-Specific Languages

**From Theory to Implementation**

A comprehensive guide to designing and implementing domain-specific languages, using MSD (Merisio Schema Definition) as the primary case study throughout.

## Overview

This book covers the complete lifecycle of DSL creation — from domain analysis and language design through lexer, parser, semantic analyser, and output generator implementation, to testing and tool integration.

## Structure

- **Part I: Foundations** (Chapters 1–3) — What DSLs are, the DSL landscape, requirements analysis
- **Part II: Language Design** (Chapters 4–7) — Lexical, syntactic, and semantic design principles; designing MSD
- **Part III: Implementation** (Chapters 8–12) — Building a lexer, parser, semantic analyser, output generator, and layout engine
- **Part IV: Quality and Integration** (Chapters 13–15) — Error handling, testing, tool integration
- **Appendices** — MSD formal grammar, type reference, DSL design checklist, glossary

## Building the PDF

```bash
cd book
pandoc --pdf-engine=xelatex --highlight-style=pygments \
  -H header.tex --lua-filter=callouts.lua \
  -o "../dsl-design-book.pdf" metadata.yaml *.md
```

## Case Study

The book uses **MSD** (Merisio Schema Definition) as its primary running example — a DSL for defining MERISE conceptual data models. MSD is part of the [Merisio](https://github.com/achrafsoltani/Merisio) project.

## Author

Achraf SOLTANI — [www.achrafsoltani.com](https://www.achrafsoltani.com)
