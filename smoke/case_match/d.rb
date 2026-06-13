# Step 3: const_pattern narrows the scrutinee type.

# --- const_pattern narrowing for inner pattern members ---
# @type var data: [Integer, String] | [Symbol, Symbol]
data = [1, "x"] #: [Integer, String] | [Symbol, Symbol]

case data
in [Integer => i, s]
  # i: Integer (narrowed by const)
  # s: String | Symbol (precise via tuple decomposition after no const narrowing)
  i.upcase   # error: Integer has no #upcase
  s.itself
end

# --- const_pattern array form: Foo(...) ---
# const_pattern just narrows the scrutinee for the inner pattern.
# We don't have deconstruct yet, so the inner element types come from
# the narrowed scrutinee (if it's a tuple/array).

# @type var maybe_tuple: [Integer, String] | nil
maybe_tuple = [1, "x"] #: [Integer, String] | nil

case maybe_tuple
in Array(a, b)
  # narrowed to [Integer, String]
  a.upcase   # error: Integer
  b.even?    # error: String
end

# --- match_as with const narrows the variable ---
# @type var mixed: Integer | String | Symbol
mixed = 1 #: Integer | String | Symbol

case mixed
in Integer => n
  n.upcase   # error: Integer narrowed
in String => s
  s.even?    # error: String narrowed
end

# --- match_as with nil narrows to nil ---
# @type var maybe: Integer | nil
maybe = 1 #: Integer | nil

case maybe
in nil => x
  x.itself   # x narrowed to nil; .itself ok
in n
  n.upcase   # n: Integer
end
