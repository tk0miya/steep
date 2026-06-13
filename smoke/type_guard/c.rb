# Class type param via guard
# @type var con: Container[Integer]
con = (_ = nil)
# @type var x: untyped
x = nil
if con.includes?(x)
  x + 1
  x.reverse
end

# Generic === with case/when
# @type var m: TypedMatcher[String]
m = (_ = nil)
# @type var y: untyped
y = nil
case y
when m
  y.upcase
  y + 1
end

# is_a from runtime arg
h = Helper.new
# @type var z: untyped
z = nil
if h.of_type?(Integer, z)
  z + 1
  z.reverse
end
