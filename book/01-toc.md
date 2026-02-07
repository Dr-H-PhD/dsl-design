\newpage

# Table of Contents

## Part I: Foundations

1. **Introduction to Domain-Specific Languages** — What is a DSL? General-purpose vs domain-specific. Internal vs external DSLs. The spectrum from configuration files to full languages. When to build a DSL and when not to.

2. **The DSL Landscape** — Survey of real-world external DSLs: SQL, GraphQL, Terraform HCL, Dockerfile, Makefile, CSS. Classification by paradigm and complexity. Common patterns across DSLs.

3. **Requirements and Domain Analysis** — Understanding the target domain. Identifying concepts, relationships, and constraints. User personas and workflow analysis. Case study introduction: MERISE modelling and Merisio.

## Part II: Language Design

4. **Lexical Design** — Tokens as atoms. Keywords, identifiers, literals, symbols. Comment styles. Case sensitivity. Context-sensitive lexing. Design trade-offs: familiarity vs precision.

5. **Syntactic Design** — From tokens to structure. EBNF notation. LL(1) grammars. Block-structured vs line-oriented syntax. Ambiguity and how to avoid it. Designing for readability vs parseability.

6. **Semantic Design** — Beyond syntax: meaning. Type systems for DSLs. Name binding and scoping. Reference resolution and forward references. Validation rules. Error messages as a design concern.

7. **Designing MSD** — Applying Chapters 3–6 to MERISE modelling. Domain analysis. Lexical, syntactic, and semantic choices. The complete MSD specification. Comparison with Mocodo.

## Part III: Implementation

8. **Building a Lexer** — Lexer architecture. Token representation. Line-by-line scanning. Keyword recognition. Context sensitivity. Error detection. MSD lexer walkthrough.

9. **Building a Recursive Descent Parser** — The recursive descent technique. Intermediate representations. Token stream navigation. Parsing blocks, attributes, types, statements. MSD parser walkthrough.

10. **Semantic Analysis** — From syntax tree to meaning. Name-to-ID resolution. Duplicate detection. "Did you mean?" suggestions via Levenshtein distance. Warning vs error severity. MSD builder walkthrough.

11. **Output Generation** — Transforming intermediate representations. UUID generation. Metadata application. JSON serialisation. Round-trip fidelity. MSD output walkthrough.

12. **Automatic Graph Layout** — The graph drawing problem. Force-directed algorithms. Fruchterman-Reingold: repulsion, attraction, cooling. Overlap removal. Determinism. MSD layout walkthrough.

## Part IV: Quality and Integration

13. **Error Handling and Recovery** — Error representation. Error vs warning. Error flow through multi-stage pipelines. Panic-mode recovery. Multi-error reporting. Error message quality. MSD error handling walkthrough.

14. **Testing DSL Implementations** — Testing philosophy. Lexer tests. Parser tests. Semantic tests. Integration tests. Test fixtures. MSD test suite walkthrough.

15. **Tool Integration** — CLI integration: subcommands, exit codes, error output. GUI integration: file dialogs, import workflows. Man pages. Batch processing. The library-CLI-GUI pattern.

## Appendices

A. **MSD Formal Grammar** — Complete EBNF specification, lexical rules, semantic constraints, and token summary.

B. **MSD Data Type Reference** — All 13 supported data types with descriptions, size rules, and usage guidance.

C. **DSL Design Checklist** — Step-by-step checklist for designing a new DSL from scratch.

D. **Glossary** — General DSL terms and MSD-specific definitions.
