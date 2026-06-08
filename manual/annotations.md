# Annotations

## Core Annotations

### Variable type

Variable type annotation tells type of local variable.

#### Example

```
# @type var x: String
# @type var klass: Class
```

#### Syntax

* `@type` `var` *x* `:` *type*

### Self type

Self type annotation tells type of `self`.

#### Example

```
# @type self: Object
```

#### Syntax

* `@type` `self` `:` *type*

### Instance variable type

Instance variable type annotation tells type of instance variable.
This annotation applies to instance variable of current context.
If it's written in `module` declaration, it applies to instance variable of the module, not its instance.

#### Example

```
# @type ivar @owner: Person
```

#### Syntax

* `@type` `ivar` *ivar* `:` *type*

### Global variable type

Global variable type annotation tells type of global variable.

#### Example

```
# @type gvar $LOAD_PATH: Array<String>
```

#### Syntax

* `@type` `gvar` *gvar* `:` *type*

### Constant type

Constant type annotation tells type of constant.
Note that constant resolution is done syntactically.
Annotation on `File::Append` does not apply to `::File::Append`.

#### Example

```
# @type const File::Append : Integer
```

#### Syntax

* `@type` `const` *const* `:` *type*

### Method type annotation

Method type annotation tells type of method being implemented in current scope.

This annotation is used to tell types of method parameters and its body.
Union method type cannot be written.

#### Example

```
# @type method foo: (String) -> any
```

#### Syntax

* `@type` `method` *method* `:` *single method type*

## Module Annotations

Module annotations is about defining modules and classes in Ruby.
This kind of annotations should be written in module context.

### Instance type annotation

Instance type annotation tells type of instance of class or module which is being defined.

#### Example

```
# @type instance: Foo
```

#### Syntax

* `@type` `instance` `:` *type*

### Module type annotation

Module type annotation tells type of module of class or module which is being defined.

#### Example

```
# @type module: Foo.class
```

#### Syntax

* `@type` `module` `:` *type*

### Instance/module ivar type annotation

This annotation tells instance variable of instance.

#### Example

```
# @type instance ivar @x: String
# @type module ivar @klass: String.class
```

#### Syntax

* `@type` `instance` `ivar` *ivar* `:` *type*
* `@type` `module` `ivar` *ivar* `:` *type*

## Type assertion

Type assertion allows declaring type of an expression inline, without introducing new local variable with variable type annotation.

### Example

```
array = [] #: Array[String]

path = nil #: Pathname?
```

##### Syntax

* `#:` *type*

## Type application

Type application is for generic method calls.

### Example

```
table = accounts.each_with_object({}) do |account, table| #$ Hash[String, Account]
  table[account.email] = account
end
```

The `each_with_object` method has `[T] (T) { (Account, T) -> void } -> T`,
and the type application syntax directly specifies the type of `T`.

So the resulting type is `(Hash[String, Account]) { (Account, Hash[String, Account]) -> void } -> Hash[String, Account]`.

#### Syntax

* `#$` *type*

## RBS Annotations

The following annotations are written in RBS files (not Ruby source) using the `%a{...}` syntax,
and modify how Steep interprets the surrounding declaration.

### Type guard

A type guard annotation declares a user-defined method as a type guard: when the method
returns a truthy value, Steep narrows the receiver's type to the given type in that branch
(and removes it in the falsy branch when possible).

Steep already understands core type guards such as `#is_a?`, `#kind_of?`, and `#nil?`.
This annotation lets you declare your own predicate methods so the type checker can narrow
through them too.

The annotation is attached to the method declaration in RBS. The predicate
supports either `self is TYPE` (to narrow the receiver) or `arg is TYPE`
(to narrow a named parameter of the predicate method). `is not` is also
accepted for the negated form, useful for predicates like `present?` that
assert the subject is not nil.

#### Example

```rbs
class Object
  %a{guard:self is Integer}
  def integer?: () -> bool

  %a{guard:self is Array[Integer]}
  def int_array?: () -> bool

  %a{guard:self is singleton(String)}
  def self.string_class?: () -> bool

  %a{guard:x is Integer}
  def int_arg?: (untyped x) -> bool

  %a{guard:value is String}
  def str_kwarg?: (value: untyped) -> bool

  %a{guard:self is not nil}
  def present?: () -> bool
end
```

```ruby
# @type var a: Object
a = (_ = nil)

if a.integer?
  a + 1       # a is narrowed to Integer
else
  a.succ      # error: Object does not have `succ`
end

# @type var v: untyped
v = nil

if Object.new.int_arg?(v)
  v + 1       # v is narrowed to Integer
end
```

#### Syntax

* `%a{guard:` (`self` | *param-name*) (`is` | `is not`) *type* `}`

#### Notes

* The annotation also narrows `self` for predicates called on an implicit or
  explicit `self` receiver:

  ```ruby
  class Object
    def m
      if integer?   # self is narrowed to Integer here
        self + 1
      end
    end
  end
  ```

* With `is`, the truthy branch is always narrowed to the annotated type. This
  is useful when the guard type is a module or interface: even if the receiver
  is already a subtype of the guard type (for example `Integer` is
  `Comparable`), the truthy branch sees the guard type so only methods
  declared on it are available. The falsy branch keeps the receiver's static
  type, because a user-defined predicate may return false for arbitrary
  reasons.
* With `is not`, both branches are narrowed: the truthy branch sees the
  receiver minus the guard type (for example `String?` minus `nil` is
  `String`), and the falsy branch sees the intersection (typically the guard
  type itself).
* Narrowing with `is` requires that the guard type and the receiver's static
  type have a subtype relationship in either direction. When they do not (for
  example guarding an `Integer` receiver to `String`), Steep reports
  `Ruby::InsufficientTypeGuard`. `is not` does not require such a relation.
* Validation errors on the annotation itself are reported as
  `RBS::Signature::TypeGuardSyntaxError` (syntactic) or
  `RBS::Signature::InvalidTypeGuardType` (the type cannot be parsed or resolved).
