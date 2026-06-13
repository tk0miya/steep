# Step 6: subject is narrowed across in-clauses by subtracting matched const types.

# @type var v: Integer | String | Symbol | nil
v = 1 #: Integer | String | Symbol | nil

case v
in Integer
  :int
in String
  :str
in nil
  :nil
in s
  # s is what's left: Symbol
  s.upcase   # error: Symbol has no #upcase
end

# Match-all match_var sweeps the rest. else-branch sees the (Bot) remainder.
case v
in Integer | String
  :a
in y
  # y narrowed to Symbol | nil
  y.upcase   # error: Symbol | nil has no #upcase
end

# Guards suppress subtraction.
case v
in Integer if true
  :int_with_guard
in n
  # n still has Integer, since the previous clause may bail.
  n.upcase  # error: (Integer | String | Symbol | nil)
end

# else clause sees the remaining type (Symbol | nil) via the original variable.
case v
in Integer
  :int
in String
  :str
else
  v.upcase  # error: (Symbol | nil)
end
