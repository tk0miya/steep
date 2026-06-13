# @type var value: Integer | String | Array[Integer]

value = 1

# Basic match_var binds the subject type
result = case value
         in x
           x
         end

# pin pattern: type-checks pinned expression
threshold = 10
case value
in ^threshold
  :hit
else
  :miss
end

# literal patterns + else
label = case value
        in 0
          "zero"
        in 1
          "one"
        else
          "other"
        end

# guard expression is type-checked
case value
in x if x.is_a?(Integer)
  x
in y
  y
end

# array_pattern recognized; rest binds to Array[any]
case value
in [first, *rest]
  rest
in []
  nil
end

# hash_pattern shorthand binds variable
case({a: 1})
in { a:, **rest }
  a
in { a: 1 }
  nil
end

# match_as binds to subject type
case value
in Integer => n
  n
in String => s
  s
end

# match_alt: literal alternatives
case value
in 1 | 2
  :small
else
  :other
end

# const_pattern
case value
in Integer
  :int
in String
  :str
else
  :other
end

# match_nil_pattern (**nil)
empty_hash = {} #: Hash[Symbol, Integer]
case empty_hash
in { **nil }
  :empty
else
  :nonempty
end
