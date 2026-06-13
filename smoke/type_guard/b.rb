o = Object.new
# @type var v: untyped
v = nil

if o.int_arg?(v)
  v + 1
  v.reverse
end

# @type var s: String?
s = (_ = nil)

if s.present?
  s.upcase
else
  s.upcase
end

# @type var w: Integer?
w = nil
if o.given?(w)
  w + 1
else
  w + 1
end
