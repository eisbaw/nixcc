# Two layers, both small, and the file says which is which because they belong
# in different places in the long run:
#
#   * CONSTRUCTORS for poc/04-assembler's item vocabulary. These are a second
#     declaration of a format asm.nix's `measure' already declares, and their
#     eventual home is beside it -- when task-026 makes poc/03-matcher emit
#     items, a compiler stage will want them and importing them out of a demo
#     would be the wrong direction. They are here rather than there today
#     because task-004 is not the task that reshapes the assembler's surface.
#
#   * THE RV32/LINUX SYSCALL ABI. Target knowledge, the same knowledge
#     hello.c's header says a C program cannot express. It stays in this PoC.
#
# Shared by driver.nix and cases.nix so that the demo and the fault programs
# are built out of the same pieces: a fault case assembled by a different
# route would say nothing about the assembler the demo goes through.
let
  b = builtins;

  # A string literal has to become bytes somewhere: `.data' is a byte list and
  # Nix has no ord(). The table is built once from the printable range plus the
  # three control characters a Nix string can hold, and a character outside it
  # is a throw rather than a zero -- a message that silently lost a character
  # would still assemble, run, and print something plausible.
  #
  # This is the inverse of rv32.nix's own `printable' and `byteText', and the
  # two strings are byte-identical. Nothing enforces that. check.nix pins
  # `stdoutBytes', which does not go through either table, so the two agreeing
  # is a convenience rather than load-bearing -- but the `stdout' STRING
  # comparison beside it does ride on it.
  printable = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
  codeOf = b.listToAttrs (b.genList
    (i: {
      name = b.substring i 1 printable;
      value = i + 32;
    })
    (b.stringLength printable)) // { "\t" = 9; "\n" = 10; "\r" = 13; };

  # For the diagnostic below: a raw control character interpolated into a
  # thrown message breaks the line it is reported on.
  visible = c: b.replaceStrings [ "\n" "\t" "\r" ] [ "\\n" "\\t" "\\r" ] c;
in
rec {
  inherit codeOf;

  asciiBytes = where: s: b.genList
    (i:
      let c = b.substring i 1 s; in
      codeOf.${c}
        or (throw "items: ${where}: `${visible c}' is not a character this .data table has a byte value for -- extend the table rather than letting it become a zero"))
    (b.stringLength s);

  # --- the item vocabulary (see the header: this belongs beside asm.nix) ----
  insn = mnemonic: args: { kind = "insn"; inherit mnemonic args; };
  label = name: { kind = "label"; inherit name; };
  global = name: { kind = "global"; inherit name; };
  section = name: { kind = "section"; inherit name; };
  align = pow: { kind = "align"; inherit pow; };
  words = values: { kind = "bytes"; width = 4; inherit values; };
  bytes = values: { kind = "bytes"; width = 1; inherit values; };
  chars = where: s: { kind = "bytes"; width = 1; values = asciiBytes where s; };

  # --- the RV32/Linux syscall ABI ------------------------------------------
  # The two syscalls nix-riscv's rv32.nix implements, and nothing else.
  sysWrite = 64;
  sysExit = 93;

  # Every program here is entered at its first .text byte, so `_start' comes
  # first or the entry point is not the entry point.
  program = body: [ (section ".text") (global "_start") (label "_start") ] ++ body;

  # exit(status), the only way a program stops cleanly.
  exitWith = status: [
    (insn "li" [ "a0" status ])
    (insn "li" [ "a7" sysExit ])
    (insn "ecall" [ ])
  ];

  # write(fd, buf, count), leaving the byte count (or the negative errno) in
  # a0 -- which exitWith would then overwrite, so the callers that want to see
  # it use `exitWithA0' instead.
  writeCall = fd: sym: count: [
    (insn "li" [ "a0" fd ])
    (insn "la" [ "a1" sym ])
    (insn "li" [ "a2" count ])
    (insn "li" [ "a7" sysWrite ])
    (insn "ecall" [ ])
  ];

  exitWithA0 = [
    (insn "li" [ "a7" sysExit ])
    (insn "ecall" [ ])
  ];
}
