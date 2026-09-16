---
id: TASK-056
title: Five rules the corpus labels and never reduces
status: To Do
assignee: []
created_date: '2026-09-16 02:03'
labels:
  - backend
  - rules
dependencies: []
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-053's census measures two populations and the gap between them is this task.

  LABELLED  the rule won some nonterminal at some corpus node: the opcode and
            the kid shapes exist somewhere in ir/. 104 of 107 rules.
  REDUCED   its template was actually expanded into emitted assembly, so some
            byte of what it says came out. 99 of 107.

Five rules sit in between -- labelled, never reduced -- and a labelling-only census would have called every one of them covered:

  reg_addrfp          taking the ADDRESS of an incoming parameter. Every
                      ADDRFP4 in the corpus is under a load or a store, where
                      addr_addrfp folds it into the displacement for nothing.
  addr_addi           reg+const as an addressing mode on the INTEGER add. lcc
                      types address arithmetic as ADDP4, so every folded
                      displacement goes through addr_addp; the ADDI4 nodes
                      that exist are arithmetic and are never asked for an
                      `addr'.
  reg_addp_imm        pointer + constant materialised into a register rather
                      than folded into a displacement.
  reg_calli_indirect  an int-returning call through a function pointer. This
                      one has a witness of a sort: cases.nix's duel raises
                      reg_calli_direct's cost, watches this row take the node
                      and checks `jalr' reaches the body. That is weaker than
                      the corpus selecting it.
  stmt_from_reg       `stmt: reg', lcc's evaluate-and-drop. Its template is
                      EMPTY, so the census cannot see it either way -- it has
                      its own status, "textless". Settled separately instead:
                      with the row taken out of the table the whole corpus
                      still compiles, so nothing needs it. Every discarded
                      value in ir/ is a call, and task-025's stmt_calli_direct
                      and stmt_callu_direct take those.

Each is reachable C: `&param', `int q; q = *(p + 1)' in a context that wants the address in a register, `(*fp)()' with the result used. Whether they are worth corpus cases is a judgement, not an oversight -- which is why the declarations in cases.nix say what each one is rather than promising a fix.

THE ONE THAT IS NOT A JUDGEMENT CALL is stmt_from_reg. It is currently dead weight: droppable with no effect. It should be either reached or removed, and removing it means checking first what refuses instead when a discarded value is not a call (task-025 is the history there -- without the stmt call rows, `stmt: reg' took the node and handed a null destination to a template saying `mv %c,a0').
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each of the five is either reduced by a case in poc/03-matcher/ir/, or its declaration in cases.nix says why it stays and the reason is a judgement someone made rather than a gap nobody looked at
- [ ] #2 stmt_from_reg is resolved one way or the other: reached by a corpus case, or removed with the refusal that replaces it checked
<!-- AC:END -->
