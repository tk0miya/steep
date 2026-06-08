# @type var a: Object
a = (_ = nil)

if a.integer?
  a + 1
else
  a.succ
end

# @type var b: Object
b = (_ = nil)

if b.int_array?
  b.sum
else
  b.length
end

cls = Object
if cls.string_class?
  cls.new + ""
else
  cls.new.succ
end
