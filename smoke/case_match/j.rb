# Extra: unless_guard, range pattern (irange), pin with expression, nested patterns.

# @type var v: Integer | String
v = 1 #: Integer | String

# unless_guard
case v
in Integer => n unless n < 0
  n.upcase    # error: Integer
in m
  # m: Integer | String (Integer subtraction skipped due to guard)
  m.even?    # error: (Integer | String) doesn't have #even?
end

# Range pattern (irange) - matches via === but doesn't narrow.
case 5
in 1..10
  :small
in 11..100
  :big
else
  :huge
end

# Nested array_pattern inside hash_pattern
# @type var nested: { items: Array[Integer], name: String }
nested = { items: [1, 2, 3], name: "x" }

case nested
in { items: [first, *], name: }
  first.upcase   # error: Integer
  name.even?     # error: String
end

# Pin with expression
threshold = 42
case v
in ^(threshold + 1)
  :match
else
  :nope
end
