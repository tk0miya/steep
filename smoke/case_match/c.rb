# Step 2: composite patterns extract precise element types from the subject.

# --- array_pattern against Array[T] ---
# @type var ints: Array[Integer]
ints = [1, 2, 3]

case ints
in [first, *rest, last]
  # first/last bound to Integer; rest to Array[Integer]
  first.upcase   # error: Integer has no #upcase
  last.upcase    # error
  rest.first.upcase # error: rest is Array[Integer], #first returns Integer?
end

# --- array_pattern against Tuple [Integer, String, Symbol] ---
# @type var triple: [Integer, String, Symbol]
triple = [1, "x", :y]

case triple
in [n, s, sym]
  # n: Integer, s: String, sym: Symbol — precise tuple element types
  n.upcase      # error: Integer
  s.even?       # error: String
  sym.even?     # error: Symbol
end

case triple
in [a, *rest]
  # a: Integer, rest: [String, Symbol]
  a.upcase             # error
  rest.first.length    # error: rest is [String, Symbol], #first returns String, #length is fine
  rest.first.upcase    # ok
end

# --- hash_pattern against record ---
# @type var rec: { name: String, age: Integer }
rec = { name: "alice", age: 30 }

case rec
in { name:, age: }
  # name: String, age: Integer
  name.even? # error: String
  age.upcase # error: Integer
end

case rec
in { name: String => n, age: Integer => a }
  n.even?    # error: String
  a.upcase   # error: Integer
end

# --- hash_pattern against Hash[Symbol, Integer] ---
# @type var dict: Hash[Symbol, Integer]
dict = { a: 1 }

case dict
in { foo: v, **rest }
  v.upcase           # error: Integer
  rest.size.upcase   # error: Integer#size... actually rest is Hash[Symbol, Integer], size is Integer
end

# --- find_pattern against Array[Integer] ---
case ints
in [*, n, *]
  n.upcase   # error: Integer
end

# --- find_pattern against Tuple element-union ---
case triple
in [*, m, *]
  # m is union Integer | String | Symbol
  m.itself   # ok
end
