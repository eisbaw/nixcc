---
id: TASK-056
title: Five rules the corpus labels and never reduces
status: To Do
assignee: []
created_date: '2026-09-16 02:03'
updated_date: '2026-09-16 03:03'
labels:
  - backend
  - rules
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-053's census measures two populations and the gap between them is this task.

  LABELLED  the rule WON some nonterminal at some corpus node -- it was the
            cheapest way to produce that nonterminal there. 104 of 107 rules
            when task-053 landed.
  REDUCED   its template was actually expanded into emitted assembly, so some
            byte of what it says came out. 99 of 107 at the same moment.

Five rules sit in between -- labelled, never reduced -- and a labelling-only census would have called every one of them covered:

  reg_addrfp          taking the ADDRESS of an incoming parameter. Every
                      ADDRFP4 in the corpus is under a load or a store, where
                      addr_addrfp folds it into the displacement for nothing,
                      so nothing ever asks for the register form.
  addr_addi           reg+const as an addressing mode on the INTEGER add. lcc
                      types address arithmetic as ADDP4, so every folded
                      displacement goes through addr_addp; this row wins
                      "addr" at the ADDI4 nodes whose kids fit it, and no load
                      or store in the corpus ever asks for an "addr" there.
  reg_addp_imm        pointer + constant materialised into a register rather
                      than folded into a displacement, which is cost 1 against
                      addr_addp's 0 at every one in the corpus.
  reg_calli_indirect  an int-returning call through a function pointer. This
                      one has a witness of a sort: cases.nix's duel raises
                      reg_calli_direct's cost, watches this row take the node
                      and checks that "jalr" reaches the body it then emits.
                      That is weaker than the corpus selecting it.
  stmt_from_reg       "stmt: reg", lcc's evaluate-and-drop. THE ONE THE MARKER
                      CANNOT SPEAK FOR: its template is empty, so expanding it
                      emits nothing. The census settles it by ablation instead
                      -- take the row out of the table and all fourteen corpus
                      functions emit BYTE-IDENTICAL assembly, so nothing needs
                      it at all. Every discarded value in ir/ is a call, and
                      task-025's stmt_calli_direct and stmt_callu_direct take
                      those.

Each is reachable C: "&param"; "*(p + 1)" in a context that wants the address in a register; a call through a function pointer whose result is used. Whether they are worth corpus cases is a judgement, not an oversight -- which is why the declarations in cases.nix say what each one is rather than promising a fix.

THE ONE THAT IS NOT A JUDGEMENT CALL is stmt_from_reg. It is dead weight: droppable with no effect on a single byte the corpus compiles to. It should be either reached or removed, and removing it means checking first what refuses instead when a discarded value is not a call -- task-025 is the history there. Without the stmt rows for CALLI4, the "stmt: reg" chain took the node and handed a null destination to a template saying "mv %c,a0", and the refusal named the template rather than the discarded return value.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each of the five is either reduced by a case in poc/03-matcher/ir/, or its declaration in cases.nix says why it stays and the reason is a judgement someone made rather than a gap nobody looked at
- [ ] #2 stmt_from_reg is resolved one way or the other: reached by a corpus case, or removed with the refusal that replaces it checked
<!-- AC:END -->
