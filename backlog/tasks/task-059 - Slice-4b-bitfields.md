---
id: TASK-059
title: 'Slice 4b: bitfields'
status: To Do
assignee: []
created_date: '2026-09-16 08:21'
labels:
  - frontend
  - slice
  - compound-types
dependencies:
  - TASK-058
priority: high
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Split from slice 4a deliberately, because this is where the defect density is. Also zero new backend rules -- a bitfield read-modify-write through a pointer lowers entirely in the frontend to INDIRU4/BANDU4/RSHU4/LSHU4/BORU4/CNSTU4/CVUI4/CVIU4/ASGNU4, all delivered by task-051. Max tree depth of the store is 3 against depthRegs of 6, so task-016 is not a prerequisite either.

The sharp edge is that the lsb computation is little_endian-dependent. decision-004 rests on exactly this example: `unsigned b:5` produces shift constant 24 at little_endian=0 and 3 at 1. Get it wrong and the oracle catches it only if the wrapper is right.

THE BITE: a bitfield whose value survives a round trip is not a test. Store a value, read it back, AND read back a NEIGHBOURING field in the same word -- a shift constant off by one changes the neighbour, not the field you stored.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Bitfield declaration, read and write parse and diff against rcc-rv32 through the little_endian=1 wrapper
- [ ] #2 A program stores a bitfield, reads it back, AND reads back a neighbouring field in the same word; an off-by-one shift constant changes the neighbour
- [ ] #3 Signed and unsigned bitfields both covered, since their extension differs
<!-- AC:END -->
