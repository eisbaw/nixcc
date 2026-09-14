# Must-fail suite. The token table can only compare inputs that lex
# successfully, so the reject paths need their own checks: if the unterminated-
# literal test were inverted, or `numberKind` returned "ICON" instead of
# throwing, every case in cases.nix would still pass.
#
# Each reject is paired with a control that MUST still lex, so a lexer that
# threw on everything could not pass this file either. Controls sit right next
# to their reject (07 against 08, 0x0 against 0x), so a control passing is
# evidence that the specific rule fired rather than a blanket rejection.
#
# Counts are taken from the result lists, never from the source tables: a
# harness that filtered `[ ]` instead of `rejects` would then report zero and
# trip the floor, rather than passing while testing nothing.
#
# `expect` is a fragment that must appear in the thrown message. It cannot be
# checked here -- builtins.tryEval returns only success and value, never the
# message -- so run.sh re-evaluates each reject and greps. Without that, a
# lexer whose diagnostics all said "error" would pass a file whose stated job
# is to make failures verbose.
let
  b = builtins;
  l = import ./lex.nix;

  minRejects = 16;
  minAccepts = 12;

  rejects = [
    { what = "unterminated string at end of input"; src = "\"abc"; expect = "unterminated string literal"; }
    { what = "newline inside a string"; src = "\"ab\ncd\""; expect = "newline inside string literal"; }
    { what = "unterminated character constant"; src = "'a"; expect = "unterminated character literal"; }
    { what = "newline inside a character constant"; src = "'a\nb'"; expect = "newline inside character literal"; }
    { what = "empty character constant"; src = "''"; expect = "empty character constant"; }
    { what = "empty wide character constant"; src = "L''"; expect = "empty character constant"; }
    { what = "unclosed block comment"; src = "a\n/* b"; expect = "unclosed comment opened on line 2"; }
    { what = "block comment closed only by a slash"; src = "a /*/"; expect = "unclosed comment"; }
    { what = "invalid octal digit"; src = "08"; expect = "invalid numeric constant `08'"; }
    { what = "hexadecimal prefix with no digits"; src = "0x"; expect = "invalid numeric constant `0x'"; }
    { what = "two decimal points"; src = "1.2.3"; expect = "invalid numeric constant `1.2.3'"; }
    { what = "exponent with no digits"; src = "1e"; expect = "invalid numeric constant `1e'"; }
    { what = "exponent sign with no digits"; src = "1e+"; expect = "invalid numeric constant `1e+'"; }
    { what = "digits running into an identifier"; src = "123abc"; expect = "invalid numeric constant `123abc'"; }
    # lcc's icon() takes at most one u and one l; ppnumber() rejects the rest.
    { what = "repeated unsigned suffix"; src = "1uu"; expect = "invalid numeric constant `1uu'"; }
    { what = "long long suffix, which C89 has not got"; src = "1ll"; expect = "invalid numeric constant `1ll'"; }
    { what = "at sign"; src = "a @ b"; expect = "unexpected character `@'"; }
    { what = "dollar sign"; src = "a $ b"; expect = "unexpected character `$'"; }
    { what = "backtick"; src = "a ` b"; expect = "unexpected character ``'"; }
    { what = "stray backslash not before a newline"; src = "a\n\nb \\ c"; expect = "unexpected character `\\' on line 3"; }
  ];

  accepts = [
    { what = "closed string"; src = "\"abc\""; }
    { what = "string with an escaped newline continuation"; src = "\"ab\\\ncd\""; }
    { what = "empty string, which IS legal"; src = "\"\""; }
    { what = "closed character constant"; src = "'a'"; }
    { what = "one-character constant"; src = "'x'"; }
    { what = "closed block comment"; src = "a /* b */ c"; }
    { what = "block comment closed properly after a slash"; src = "a /*/ */ c"; }
    { what = "largest legal octal digit"; src = "07"; }
    { what = "shortest hexadecimal constant"; src = "0x0"; }
    { what = "one decimal point"; src = "1.2"; }
    { what = "exponent with digits"; src = "1e5"; }
    { what = "one unsigned suffix"; src = "1u"; }
    { what = "unsigned and long, once each"; src = "1ul"; }
    { what = "identifier that starts with a letter"; src = "abc123"; }
    { what = "backslash before a newline"; src = "a \\\nb"; }
  ];

  # deepSeq, because lex is lazy: `tryEval (lex src)` alone reports success for
  # an input whose error is still an unforced thunk.
  lexes = src: (b.tryEval (b.deepSeq (l.lex src) true)).success;
  roundTrips = src: (b.tryEval (let t = l.lex src; in b.deepSeq t (l.render t == src))).value;

  rejectResults = map (c: { inherit (c) what; accepted = lexes c.src; }) rejects;
  acceptResults = map (c: { inherit (c) what; lexed = lexes c.src; rendered = roundTrips c.src; })
    accepts;

  wronglyAccepted = b.filter (r: r.accepted) rejectResults;
  wronglyRejected = b.filter (r: !r.lexed) acceptResults;
  wronglyRendered = b.filter (r: r.lexed && !r.rendered) acceptResults;
  names = rs: b.concatStringsSep ", " (map (r: r.what) rs);
in
{
  # run.sh reads this to check the thrown messages, which Nix cannot see.
  inherit rejects;

  summary =
    if b.length rejectResults < minRejects || b.length acceptResults < minAccepts then
      throw "HARNESS FAULT: must-fail tables shrank to ${toString (b.length rejectResults)} rejects and ${
        toString (b.length acceptResults)} controls"
    else if wronglyAccepted != [ ] then
      throw "must-fail: these should have been rejected but lexed fine: ${names wronglyAccepted}"
    else if wronglyRejected != [ ] then
      throw "must-fail: these should have lexed but threw: ${names wronglyRejected}"
    else if wronglyRendered != [ ] then
      throw "must-fail: these lexed but did not round-trip: ${names wronglyRendered}"
    else
      "must-fail: ${toString (b.length rejectResults)} reject cases, ${
        toString (b.length acceptResults)} control cases\n";
}
