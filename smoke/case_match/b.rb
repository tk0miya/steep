# Verify that variables bound by patterns receive the scrutinee type.

# @type var x: Integer
x = 0

case x
in n
  # n is bound to Integer (scrutinee type). Calling String#upcase on it should fail.
  n.upcase
end

# match_as: variable bound to scrutinee type
case x
in Integer => i
  i.upcase
end
