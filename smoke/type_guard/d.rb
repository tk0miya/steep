# assert with self subject
# @type var n: Numeric
n = (_ = nil)
n.must_be_int!
n + 1
n.reverse

# assert with arg subject
o = Object.new
# @type var v: untyped
v = nil
o.assert_int!(v)
v + 1
v.upcase

# assert + is not
# @type var w: String?
w = nil
o.reject_nil!(w)
w.upcase
w + 1
