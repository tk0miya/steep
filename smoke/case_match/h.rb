# Step 7: const_pattern uses the class's deconstruct / deconstruct_keys.

# --- MatchData#deconstruct_keys returns Hash[Symbol, String?] ---
# @type var md: MatchData
md = /(\d+)/.match("abc 123") || raise

case md
in { foo: v }
  # v comes from MatchData#deconstruct_keys: String?
  v.upcase   # error: String? has no #upcase
end

# --- Array#deconstruct returns self ---
# @type var ints: Array[Integer]
ints = [1, 2, 3]

# Through deconstruct elaboration the inner pattern still sees Array[Integer].
case ints
in Array(a, *rest)
  a.upcase            # error: Integer
  rest.first.upcase   # error: rest is Array[Integer], first returns Integer?
end
