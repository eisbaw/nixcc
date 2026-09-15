# What the closed loop is expected to do, as tables.
#
# Two kinds of expectation live here and they are not the same kind of claim:
#
#   * THE DEMO. One number and one byte string, both of which come out of a C
#     program that was compiled, assembled and executed inside one evaluation.
#     If either is wrong, something between lcc's IR and the emulator is
#     wrong, and the point of running the program rather than inspecting it is
#     that it does not matter which.
#
#   * THE FAULTS. Deliberately broken programs, each pinned to the exact
#     `reason' rv32.nix reports for it. This is the table that proves the
#     emulator stage can FAIL: without it, "the demo exited 0" is consistent
#     with an emulator that exits 0 for everything.
#
# Every fault is paired with a CONTROL that must still run to a clean exit
# with a pinned status AND a pinned stdout -- every control, not only the ones
# that write, because a control that spuriously printed something is exactly
# what a control table exists to notice. Without the controls an emulator that faulted at
# everything would pass the fault table outright, and the controls are chosen
# to sit one step away from their fault -- an address that is a multiple of
# four beside one that is not, the last word of RAM beside the first word past
# it -- so that a control passing is evidence the specific check fired.
let
  it = import ./items.nix;

  # The address every program here is assembled and loaded at. Written down
  # once: the fault cases jump to literal addresses, which is the only way to
  # aim at a misaligned one.
  base = 65536;
  ramSize = 1048576;

  # A .data buffer for the write cases, four bytes so the count is exact.
  bufferText = "ok!\n";
  buffer = [
    (it.section ".data")
    (it.align 2)
    (it.label "buf")
    (it.chars "write buffer" bufferText)
  ];
in
rec {
  inherit base ramSize;

  # --- the demo -------------------------------------------------------------
  # Addresses of the hand-built driver, which is the part of .text whose size
  # does not depend on what the matcher emitted. `hello' is the first thing
  # after the driver, so it pins the driver's total size too.
  demo = {
    exitCode = 0;
    reason = "exit";
    # The compiled function is ~90 instructions and the two libcalls iterate
    # 32 times each; a run that did far less than this did not execute the
    # program.
    minSteps = 400;
    # Written as offsets from the load address, because that is what they
    # measure: the driver's own size. `_start' is the entry point, `wr' is 36
    # bytes of driver later, and `hello' is the first thing after the whole
    # 48-byte driver -- so this table pins the hand-built half of .text and
    # says nothing about what the matcher emitted.
    symbols = { _start = base; wr = base + 36; hello = base + 48; };
    # Every label in the compiled function, so that "a branch was resolved
    # from the symbol table" is checked against a function that still HAS
    # branches after a change to emit.nix.
    labelPrefix = ".Lhello_";
    minCompiledBranches = 3;
  };

  # Symbols the demo's image must define, which is how the runtime being
  # linked in is CHECKED rather than inferred from an item count. Drop
  # poc/03-matcher/runtime.s from the item list and this is what says so;
  # without it the first thing to notice is a floor on the number of items,
  # which sends the reader to the wrong file.
  # The last three are in poc/03-matcher/runtime.s and NOTHING in the demo
  # references them, which is the point: a runtime trimmed to what this demo
  # happens to call would still assemble and still run, and this is what would
  # notice. The referenced ones are here too, but the assembler's own refusal
  # reaches those first.
  requiredSymbols = [
    "_start" "wr" "hello" "vec" "msg"
    "__divsi3" "__modsi3"
    "__mulsi3" "h" "g"
  ];

  # How long a fault or control program is given before the machine reports
  # `budget'. Generous: every one of them either halts in under twenty
  # instructions or is the spin loop, which declares its own much shorter
  # budget so that "it did not stop" is measured rather than waited out.
  faultLimit = 2000;

  # --- programs that must not run to a clean exit ---------------------------
  faults = [
    {
      what = "a word in .text that decodes to no instruction";
      reason = "illegal-instruction";
      items = it.program [ (it.insn "nop" [ ]) (it.words [ 0 ]) ];
    }
    {
      what = "a jump to the first address past the end of RAM";
      reason = "instruction-access-fault";
      items = it.program [ (it.insn "li" [ "t0" ramSize ]) (it.insn "jr" [ "t0" ]) ];
    }
    {
      what = "a jump to an address that is not a multiple of four";
      reason = "instruction-address-misaligned";
      items = it.program [ (it.insn "li" [ "t0" (base + 2) ]) (it.insn "jr" [ "t0" ]) ];
    }
    {
      what = "a word load from an address that is not a multiple of four";
      reason = "load-address-misaligned";
      items = it.program [
        (it.insn "li" [ "t0" (base + 1) ])
        (it.insn "lw" [ "t1" { base = "t0"; disp = 0; } ])
      ];
    }
    {
      what = "a word load from past the end of RAM";
      reason = "load-access-fault";
      items = it.program [
        (it.insn "li" [ "t0" (ramSize + 4) ])
        (it.insn "lw" [ "t1" { base = "t0"; disp = 0; } ])
      ];
    }
    {
      what = "a word store to past the end of RAM";
      reason = "store-access-fault";
      items = it.program [
        (it.insn "li" [ "t0" (ramSize + 4) ])
        (it.insn "sw" [ "zero" { base = "t0"; disp = 0; } ])
      ];
    }
    {
      what = "a syscall number this machine does not implement";
      reason = "unsupported-syscall";
      items = it.program [ (it.insn "li" [ "a7" 1234 ]) (it.insn "ecall" [ ]) ];
    }
    {
      what = "a word store to an address that is not a multiple of four";
      reason = "store-address-misaligned";
      items = it.program [
        (it.insn "li" [ "t0" (ramSize - 6) ])
        (it.insn "sw" [ "zero" { base = "t0"; disp = 0; } ])
      ];
    }
    {
      # Not a malformed program so much as a deliberately trapping one, and it
      # belongs here for the same reason: it does not reach `exit'. rv32.nix
      # reports `breakpoint' and stops, and a suite that never took this path
      # would not notice if it stopped stopping.
      what = "a program that executes ebreak instead of exiting";
      reason = "breakpoint";
      items = it.program [ (it.insn "ebreak" [ ]) ];
    }
    {
      # The one that would otherwise HANG, which is the failure mode the
      # negative test exists to rule out: the emulator stops at the budget and
      # says so, and "budget" is not "exit".
      what = "a program that never stops";
      reason = "budget";
      limit = 50;
      items = it.program [ (it.label "spin") (it.insn "j" [ "spin" ]) ];
    }
  ];

  controls = [
    {
      what = "a word in .text that decodes to a real instruction";
      exitCode = 1;
      stdoutBytes = [ ];
      items = it.program ([ (it.insn "nop" [ ]) (it.words [ 19 ]) ] ++ it.exitWith 1);
    }
    {
      what = "a jump to a label inside the image";
      exitCode = 2;
      stdoutBytes = [ ];
      items = it.program ([ (it.insn "la" [ "t0" "cont" ]) (it.insn "jr" [ "t0" ]) (it.label "cont") ] ++ it.exitWith 2);
    }
    {
      # The same literal-address jump as the misaligned fault, four bytes on:
      # `li' is two instructions and `jr' one, so the next multiple of four
      # after them is base+16, and `nop' fills the gap.
      what = "a jump to a literal address that is a multiple of four";
      exitCode = 3;
      stdoutBytes = [ ];
      items = it.program ([
        (it.insn "li" [ "t0" (base + 16) ])
        (it.insn "jr" [ "t0" ])
        (it.insn "nop" [ ])
      ] ++ it.exitWith 3);
    }
    {
      what = "a word load from an address that is a multiple of four";
      exitCode = 4;
      stdoutBytes = [ ];
      items = it.program ([
        (it.insn "li" [ "t0" base ])
        (it.insn "lw" [ "t1" { base = "t0"; disp = 0; } ])
      ] ++ it.exitWith 4);
    }
    {
      what = "a word load from the last word of RAM";
      exitCode = 5;
      stdoutBytes = [ ];
      items = it.program ([
        (it.insn "li" [ "t0" (ramSize - 4) ])
        (it.insn "lw" [ "t1" { base = "t0"; disp = 0; } ])
      ] ++ it.exitWith 5);
    }
    {
      what = "a word store to the last word of RAM";
      exitCode = 6;
      stdoutBytes = [ ];
      items = it.program ([
        (it.insn "li" [ "t0" (ramSize - 4) ])
        (it.insn "sw" [ "zero" { base = "t0"; disp = 0; } ])
      ] ++ it.exitWith 6);
    }
    {
      # Two bytes from the misaligned store above, and in range, so only the
      # alignment distinguishes them.
      what = "a word store to an address that is a multiple of four";
      exitCode = 9;
      stdoutBytes = [ ];
      items = it.program ([
        (it.insn "li" [ "t0" (ramSize - 8) ])
        (it.insn "sw" [ "zero" { base = "t0"; disp = 0; } ])
      ] ++ it.exitWith 9);
    }
    {
      what = "a syscall number this machine does implement";
      exitCode = 7;
      stdoutBytes = [ ];
      items = it.program (it.exitWith 7);
    }
    {
      what = "a loop that does stop, under the same budget the spin runs out of";
      exitCode = 8;
      stdoutBytes = [ ];
      limit = 50;
      items = it.program ([
        (it.insn "li" [ "t0" 5 ])
        (it.label "again")
        (it.insn "addi" [ "t0" "t0" (-1) ])
        (it.insn "bnez" [ "t0" "again" ])
      ] ++ it.exitWith 8);
    }

    # --- the write syscall, from a hand-built program ----------------------
    # The demo drives write() from compiled C. These three drive it from
    # items, which is the only way to reach its two error returns: a C program
    # cannot ask for a bad file descriptor without the runtime handing one on.
    {
      what = "write to stdout from a hand-built item program";
      exitCode = 4;
      stdoutBytes = it.asciiBytes "write control" bufferText;
      items = it.program ((it.writeCall 1 "buf" 4) ++ it.exitWithA0) ++ buffer;
    }
    {
      what = "write to a file descriptor that is not stdout";
      # -EBADF, as an unsigned 32-bit exit status.
      exitCode = 4294967287;
      stdoutBytes = [ ];
      items = it.program ((it.writeCall 7 "buf" 4) ++ it.exitWithA0) ++ buffer;
    }
    {
      what = "write from a buffer that is not in RAM";
      # -EFAULT.
      exitCode = 4294967282;
      stdoutBytes = [ ];
      items = it.program ([
        (it.insn "li" [ "a0" 1 ])
        (it.insn "li" [ "a1" (ramSize + 4) ])
        (it.insn "li" [ "a2" 4 ])
        (it.insn "li" [ "a7" it.sysWrite ])
        (it.insn "ecall" [ ])
      ] ++ it.exitWithA0);
    }
  ];

  # The distinct fault classifications the table must keep covering. Named
  # rather than counted: a table that lost `budget' and gained a second
  # load fault would keep the count and lose the case that matters most.
  requiredReasons = [
    "illegal-instruction"
    "instruction-access-fault"
    "instruction-address-misaligned"
    "load-address-misaligned"
    "load-access-fault"
    "store-access-fault"
    "unsupported-syscall"
    "store-address-misaligned"
    "breakpoint"
    "budget"
  ];
}
