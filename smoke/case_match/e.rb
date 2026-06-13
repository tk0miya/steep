# Step 4: match_alt narrows each arm and joins the variable types.

# @type var mixed: Integer | String | Symbol | nil
mixed = 1 #: Integer | String | Symbol | nil

# Each alt arm narrows independently; binding type is the union of arms.
case mixed
in Integer | String => n
  # n: Integer | String (narrowed by alt union)
  n.even? # error: String#even? doesn't exist (Integer#even? does)
end

# Pure const alternatives
case mixed
in Integer | nil
  :int_or_nil
in String
  :str
in Symbol
  :sym
end

# match_alt with literal alternatives still type-checks the body.
case mixed
in nil | Integer => x
  x.upcase   # error: x narrowed to (nil | Integer)
end
