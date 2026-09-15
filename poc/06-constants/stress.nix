# The three loops in const.nix, run at a size where the ways a Nix traversal
# dies are visible. Not a timing ladder and deliberately not one -- there is
# nothing here whose cost is worth a linearity verdict, and a ladder would
# bring a contention self-test and a NO VERDICT path for no gain. What this
# asks is whether these loops SURVIVE, which is a different question from how
# fast they are and has a yes-or-no answer on any machine.
#
# The three failures it is looking for, all of them measured properties of
# this evaluator rather than opinions (decision-001):
#
#   * A recursion whose depth tracks the input dies at the max-call-depth cap,
#     around 3000-5000 iterations of a loop doing real work. scanUnits is a
#     genericClosure and scanWhile's windows double, so neither should -- but
#     "should" is what a test is for.
#
#   * A `++' accumulator is quadratic. 60000 units decoded through one would
#     not finish inside this gate.
#
#   * INTEGER OVERFLOW THROWS. A 5000-digit constant is the case that would
#     take the whole evaluation down with a message about Nix rather than
#     reporting an overflow in the user's program, and it is the reason
#     `accumulate' tests before the multiply instead of after. A constant this
#     long is absurd C, which is the point: the guard has to hold at the
#     absurd end or it is not a guard.
#
# Counts are computed from the decoded lists, never from the parameters that
# built the input, so a decoder that returned nothing cannot report success.
let
  b = builtins;
  c = import ./const.nix;

  # 20000 repetitions of `a\x41\101' -- a plain character, a hexadecimal
  # escape and an octal one, so all three arms of unitAt run 20000 times.
  repeats = 20000;
  unitsPerRepeat = 3;
  longString = "\"" + b.concatStringsSep "" (b.genList (_: "a\\x41\\101") repeats) + "\"";
  decoded = c.evalSCON longString;

  # A decimal constant with 5000 digits. lcc's icon() would see host overflow
  # here; ours must see target overflow, clamp, warn, and NOT throw.
  digits = 5000;
  longInt = b.concatStringsSep "" (b.genList (_: "9") digits);
  huge = c.evalICON longInt;

  # A hexadecimal escape with 4000 digits, which is what forces the 32-bit
  # bitAnd inside hexEscape: lcc's `c' is an unsigned int and wraps, and an
  # unmasked accumulation here would throw long before the escape ended.
  hexDigits = 4000;
  longEscape = c.evalICON ("'\\x" + b.concatStringsSep "" (b.genList (_: "f") hexDigits) + "'");

  fault = msg: throw "HARNESS FAULT: ${msg}";
in
if repeats < 10000 || digits < 1000 || hexDigits < 1000 then
  fault "the stress sizes were shrunk to ${toString repeats}/${toString digits}/${
    toString hexDigits}, which is below the point where any of these failures appears"
else if b.length decoded.units != repeats * unitsPerRepeat then
  throw "constants: a ${toString repeats}-escape literal decoded to ${
    toString (b.length decoded.units)} units, not the ${
    toString (repeats * unitsPerRepeat)} it contains"
else if decoded.warnings != [ ] then
  throw "constants: a literal of plain and well-formed escapes was diagnosed: ${
    b.concatStringsSep ", " decoded.warnings}"
else if b.elemAt decoded.units 0 != 97 || b.elemAt decoded.units 1 != 65 || b.elemAt decoded.units 2 != 65 then
  throw "constants: the first three units of the long literal are ${
    toString (b.elemAt decoded.units 0)} ${toString (b.elemAt decoded.units 1)} ${
    toString (b.elemAt decoded.units 2)}, not a, \\x41, \\101"
else if b.elemAt decoded.units (repeats * unitsPerRepeat - 1) != 65 then
  throw "constants: the last unit of the long literal is ${
    toString (b.elemAt decoded.units (repeats * unitsPerRepeat - 1))}, not \\101 -- the tail of the literal was not decoded"
else if huge != { value = 4294967295; type = "unsigned long"; warnings = [ "overflow in constant `${longInt}'" ]; } then
  throw "constants: a ${toString digits}-digit constant came back as ${
    huge.type} ${toString huge.value} with ${toString (b.length huge.warnings)} warning(s); it must clamp and be diagnosed, not throw and not wrap"
else if longEscape.value != (-1) then
  throw "constants: a ${toString hexDigits}-digit hexadecimal escape came back as ${
    toString longEscape.value}, not the low byte of its 16-bit truncation"
else
  "stress: ${toString (b.length decoded.units)} units decoded from one literal, a ${
    toString digits}-digit constant clamped with a diagnostic rather than thrown, and a ${
    toString hexDigits}-digit escape truncated without overflowing the evaluator\n"
