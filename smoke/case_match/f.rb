# Step 5: one-liner pattern matching.

# --- =>  (match_pattern: raises NoMatchingPatternError on failure) ---
# @type var pair: [Integer, String]
pair = [1, "x"]

pair => [n, s]
# n: Integer, s: String — bound after =>
n.upcase   # error: Integer
s.even?    # error: String

# --- in  (match_pattern_p: returns true/false) ---
# @type var v: Integer | String
v = 1 #: Integer | String

if v in Integer => x
  # x is bound here. Step 6 will narrow control flow, but binding is already correct.
  x.upcase # error: Integer
end

ok = v in [Integer, *]
ok.itself # ok: Boolean

# --- match_pattern with const + var ---
# @type var triple: [Integer, String, Symbol]
triple = [1, "x", :y]

triple => [Integer => i, String => s, Symbol => sym]
i.upcase    # error: Integer
s.even?     # error: String
sym.even?   # error: Symbol
