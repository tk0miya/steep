# Step 8: unreachable in-clauses are flagged.

# @type var v: Integer | String
v = 1 #: Integer | String

case v
in Integer
  :int
in String
  :str
in Symbol
  # After Integer and String matched, remaining is Bot. This clause is unreachable.
  :sym
end

# Match-all match_var then anything afterwards is unreachable.
case v
in n
  n.itself
in Integer
  :unreachable
end
