# Must-fail suite. cases.nix can only compare inputs that evaluate
# successfully, so the refusal paths need their own checks: if evalFCON
# returned a number instead of throwing, or a byte outside ASCII quietly
# evaluated to 0, every case in cases.nix would still pass.
#
# Each reject is paired with a CONTROL that must still evaluate, so an
# evaluator that threw on everything could not pass this file either. The
# controls sit next to their rejects -- `1.5' against `15', `'\xg'' against
# `'\x41'' -- so a control passing is evidence that the specific rule fired
# rather than a blanket refusal.
#
# WHY EVERY THROW IS A `throw' AND NEVER AN ATTRIBUTE MISS. builtins.tryEval
# does NOT catch an attribute-missing error; it propagates straight through
# and takes this whole file down with it, so a refusal implemented as
# `table.${x}' would escape every check here (task-037). const.nix writes
# `or (throw ...)' on every lookup for exactly this reason, and the
# non-ASCII and bad-suffix cases below are the ones that would otherwise be
# attribute misses.
#
# `expect' is a fragment that must appear in the thrown message. It cannot be
# checked here -- builtins.tryEval returns only success and value, never the
# message -- so messages.sh re-evaluates each reject and greps. Without that,
# an evaluator whose every diagnostic said "error" would pass a file whose
# stated job is to make failures verbose.
let
  b = builtins;
  c = import ./const.nix;

  # DECLARED counts, checked for EQUALITY rather than floors. A floor with
  # slack in it can be spent downward in silence -- review demonstrated
  # exactly that on this PoC's sibling table, deleting ten diagnosed forms
  # from the oracle and watching it stay green against a floor of 80. The
  # argument is poc/lib/mutant.sh's, made there about mutation counts and just
  # as true here: `-eq' catches both directions, and the edit it forces when a
  # case is added is the edit that was wanted anyway.
  declaredRejects = 20;
  declaredControls = 16;

  # A byte outside ASCII, built rather than typed: a Nix string literal
  # cannot carry one portably, and fromJSON of a non-ASCII code point yields
  # its UTF-8 bytes, the first of which is what const.nix has no entry for.
  highByte = b.fromJSON "\"\\u00e9\"";

  # Each reject names the entry point it goes through, so that the refusals
  # are tested at the surface task-027 will actually call.
  #
  # A MISTYPED `fn' USED TO READ AS A CORRECT REFUSAL. `apply' ended in a
  # HARNESS FAULT throw, `evaluates' wraps `apply' in tryEval, and tryEval
  # catches a throw -- so `fn = "IOCN"' scored as "the evaluator rejected it"
  # and the suite printed its cleanest line. Review demonstrated it. The
  # entry-point name is therefore validated at TABLE level, outside the
  # tryEval, where a fault can still be one.
  entryPoints = [ "ICON" "SCON" "FCON" "token" "tokenNoKind" "tokenNoText" ];
  badEntryPoints = b.filter (r: !(b.elem r.fn entryPoints)) (rejects ++ controls);

  apply = r:
    if r.fn == "ICON" then c.evalICON r.arg
    else if r.fn == "SCON" then c.evalSCON r.arg
    else if r.fn == "FCON" then c.evalFCON r.arg
    else if r.fn == "tokenNoKind" then c.evalToken { text = r.arg; }
    else if r.fn == "tokenNoText" then c.evalToken { kind = r.arg; }
    else c.evalToken { kind = r.arg; text = r.text or "x"; };

  rejects = [
    # Float is deferred, and the refusal has to NAME the decision, because a
    # bare "unsupported" tells the next reader nothing about whether it is a
    # gap or a choice.
    { what = "a floating constant"; fn = "FCON"; arg = "1.5"; expect = "decision-006"; }
    { what = "a floating constant names the rejection task too"; fn = "FCON"; arg = "1e5"; expect = "task-015"; }
    { what = "an FCON token through the general entry point"; fn = "token"; arg = "FCON"; text = "1.5"; expect = "decision-006"; }

    # The general entry point must refuse a token that is not a constant at
    # all rather than guessing.
    { what = "an identifier token"; fn = "token"; arg = "ID"; expect = "is not a constant"; }
    { what = "a keyword token"; fn = "token"; arg = "INT"; expect = "is not a constant"; }

    # Escapes with no value to continue from. lcc errors on this one too.
    { what = "a hexadecimal escape with no digits"; fn = "ICON"; arg = "'\\xg'"; expect = "ill-formed hexadecimal escape sequence `\\xg'"; }
    { what = "a hexadecimal escape with no digits in a string"; fn = "SCON"; arg = "\"\\xz\""; expect = "ill-formed hexadecimal escape sequence"; }
    { what = "a literal ending in a bare backslash"; fn = "SCON"; arg = "\"a\\\""; expect = "ends in a backslash"; }
    { what = "an empty character constant"; fn = "ICON"; arg = "''"; expect = "empty character constant"; }
    # builtins.substring reads a negative length as "to the end", so an
    # unclosed lexeme would otherwise decode as an empty literal rather than
    # fail.
    { what = "a string lexeme with no closing quote"; fn = "SCON"; arg = "\""; expect = "is not a string literal"; }
    { what = "a wide lexeme with nothing after the prefix"; fn = "SCON"; arg = "L\""; expect = "is not a string literal"; }
    # A version of the quote check that merely required the first and last
    # characters to MATCH accepted both of these.
    { what = "a character lexeme handed to the string entry point"; fn = "SCON"; arg = "'a'"; expect = "is not a string literal"; }
    { what = "a lexeme quoted with neither quote character"; fn = "SCON"; arg = "xax"; expect = "is not a string literal"; }

    # The documented ASCII limit. It must refuse, loudly and by name, rather
    # than invent a value -- and it must be a throw, not an attribute miss.
    { what = "a byte outside ASCII in a string"; fn = "SCON"; arg = "\"${highByte}\""; expect = "task-046"; }
    { what = "a byte outside ASCII in a character constant"; fn = "ICON"; arg = "'${highByte}'"; expect = "outside ASCII"; }

    # Lexemes the lexer would never produce, reaching the evaluator by hand.
    # A frontend stage that trusts its caller silently is a frontend stage
    # that miscompiles when the caller changes.
    { what = "a suffix lcc's icon() would not read"; fn = "ICON"; arg = "1lul"; expect = "is not a C89 integer suffix"; }
    { what = "a lexeme that is not an integer at all"; fn = "ICON"; arg = "abc"; expect = "is not an integer constant"; }
    { what = "an empty lexeme"; fn = "ICON"; arg = ""; expect = "is not an integer constant"; }

    # The general entry point reads `kind' and `text' through `or (throw ...)'
    # like every other lookup in const.nix. A bare `tok.text' here would be an
    # attribute miss, which tryEval does not catch (task-037), at the one
    # entry point task-027 is told to call.
    { what = "a token with no kind field"; fn = "tokenNoKind"; arg = "42"; expect = "has no `kind' field"; }
    { what = "a token with no text field"; fn = "tokenNoText"; arg = "ICON"; expect = "has no `text' field"; }
  ];

  controls = [
    { what = "a decimal constant, against the float case"; fn = "ICON"; arg = "15"; }
    { what = "an integer that looks like the start of a float"; fn = "ICON"; arg = "1"; }
    { what = "a character constant, against the empty one"; fn = "ICON"; arg = "'a'"; }
    { what = "a well-formed hexadecimal escape"; fn = "ICON"; arg = "'\\x41'"; }
    { what = "a well-formed hexadecimal escape in a string"; fn = "SCON"; arg = "\"\\x41\""; }
    { what = "a string with a backslash escape that is complete"; fn = "SCON"; arg = "\"a\\\\\""; }
    # Deliberately NOT named "every ASCII character": this is a control for
    # the non-ASCII reject above and nothing more. The whole printable range
    # is checked unit by unit in cases.nix, where a wrong answer is visible
    # rather than merely a thrown one.
    { what = "ordinary printable characters, against the non-ASCII case"; fn = "SCON"; arg = "\"abc XYZ 0189 ~!@#\""; }
    { what = "the suffixes lcc's icon() does read"; fn = "ICON"; arg = "1ul"; }
    { what = "an identifier-shaped lexeme that IS a valid hex constant"; fn = "ICON"; arg = "0xabc"; }
    { what = "an ICON token through the general entry point"; fn = "token"; arg = "ICON"; text = "42"; }
    { what = "an SCON token through the general entry point"; fn = "token"; arg = "SCON"; text = "\"hi\""; }
    { what = "a wide character constant"; fn = "ICON"; arg = "L'a'"; }
    { what = "the shortest closed string, against the unclosed one"; fn = "SCON"; arg = "\"\""; }
    { what = "the shortest closed wide string"; fn = "SCON"; arg = "L\"\""; }
    { what = "a character lexeme through the entry point it belongs to"; fn = "ICON"; arg = "'z'"; }
    { what = "a wide string lexeme through the entry point it belongs to"; fn = "SCON"; arg = "L\"a\""; }
  ];

  # deepSeq, because the evaluator is lazy: `tryEval (evalICON x)` alone
  # reports success for an input whose error is still an unforced thunk.
  evaluates = r: (b.tryEval (b.deepSeq (apply r) true)).success;

  rejectResults = map (r: { inherit (r) what; accepted = evaluates r; }) rejects;
  controlResults = map (r: { inherit (r) what; evaluated = evaluates r; }) controls;

  wronglyAccepted = b.filter (r: r.accepted) rejectResults;
  wronglyRejected = b.filter (r: !r.evaluated) controlResults;
  names = rs: b.concatStringsSep ", " (map (r: r.what) rs);
in
{
  # messages.sh reads these to check the thrown text, which Nix cannot see,
  # and reads the declared count rather than restating a floor of its own.
  inherit rejects declaredRejects;
  forceReject = i: b.deepSeq (apply (b.elemAt rejects i)) 1;

  summary =
    if badEntryPoints != [ ] then
      throw "HARNESS FAULT: these cases name an entry point this file has not got: ${names badEntryPoints}"
    else if b.length rejectResults != declaredRejects || b.length controlResults != declaredControls then
      throw "HARNESS FAULT: must-fail tables hold ${toString (b.length rejectResults)} rejects and ${
        toString (b.length controlResults)} controls, against the ${toString declaredRejects} and ${
        toString declaredControls} this file declares. Raise the declared numbers with the tables."
    else if wronglyAccepted != [ ] then
      throw "must-fail: these should have been rejected but evaluated fine: ${names wronglyAccepted}"
    else if wronglyRejected != [ ] then
      throw "must-fail: these should have evaluated but threw: ${names wronglyRejected}"
    else
      "must-fail: ${toString (b.length rejectResults)} reject cases, ${
        toString (b.length controlResults)} control cases\n";
}
