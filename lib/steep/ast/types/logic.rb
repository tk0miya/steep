module Steep
  module AST
    module Types
      module Logic
        class Base
          extend SharedInstance

          def subst(s)
            self
          end

          include Helper::NoFreeVariables

          include Helper::NoChild

          def hash
            self.class.hash
          end

          def ==(other)
            other.class == self.class
          end

          alias eql? ==

          def to_s
            "<% #{self.class} %>"
          end

          def level
            [0]
          end
        end

        class Not < Base
        end

        class ReceiverIsNil < Base
        end

        class ReceiverIsNotNil < Base
        end

        class ReceiverIsArg < Base
        end

        class ArgEqualsReceiver < Base
        end

        class ArgIsAncestor < Base
        end

        class Guard < Base
          PATTERN = /\Aguard:\s*(\w+)\s+(is\s+not|is)\s+(.*?)\s*\Z/

          # Normalize operator into either "is" or "is not".
          def self.normalize_operator(op)
            op.match?(/\Ais\s+not\z/) ? "is not" : "is"
          end

          attr_reader :subject
          attr_reader :operator
          attr_reader :type

          def initialize(subject:, operator:, type:)
            @subject = subject
            @operator = operator
            @type = type
          end

          def ==(other)
            super && subject == other.subject && operator == other.operator && type == other.type
          end

          def hash
            self.class.hash ^ subject.hash ^ operator.hash ^ type.hash
          end

          def free_variables
            type.free_variables
          end

          def subst(s)
            new_type = type.subst(s)
            return self if new_type.equal?(type)
            Guard.new(subject: subject, operator: operator, type: new_type)
          end

          def each_child(&block)
            return enum_for(:each_child) unless block
            yield type
          end

          def map_type(&block)
            Guard.new(subject: subject, operator: operator, type: yield(type))
          end
        end

        # A type for `is_a`-style guard: narrowing target is determined by the
        # static type of another argument (typically a `Module`/`singleton(...)`
        # value). Lets users wrap `Object#is_a?`-like predicates while keeping
        # narrowing tied to the call-site argument.
        class IsAGuard < Base
          PATTERN = /\Aguard:\s*(\w+)\s+is_a\s+(\w+)\s*\Z/

          attr_reader :subject
          attr_reader :arg

          def initialize(subject:, arg:)
            @subject = subject
            @arg = arg
          end

          def ==(other)
            super && subject == other.subject && arg == other.arg
          end

          def hash
            self.class.hash ^ subject.hash ^ arg.hash
          end
        end

        # A type for assertion-style guard: methods that narrow the subject in
        # the caller's scope after returning normally (e.g. raise on mismatch).
        class Assert < Base
          PATTERN = /\Aassert:\s*(\w+)\s+(is\s+not|is)\s+(.*?)\s*\Z/

          attr_reader :subject
          attr_reader :operator
          attr_reader :type

          def initialize(subject:, operator:, type:)
            @subject = subject
            @operator = operator
            @type = type
          end

          def ==(other)
            super && subject == other.subject && operator == other.operator && type == other.type
          end

          def hash
            self.class.hash ^ subject.hash ^ operator.hash ^ type.hash
          end

          def free_variables
            type.free_variables
          end

          def subst(s)
            new_type = type.subst(s)
            return self if new_type.equal?(type)
            Assert.new(subject: subject, operator: operator, type: new_type)
          end

          def each_child(&block)
            return enum_for(:each_child) unless block
            yield type
          end

          def map_type(&block)
            Assert.new(subject: subject, operator: operator, type: yield(type))
          end
        end

        class Env < Base
          attr_reader :truthy, :falsy, :type

          def initialize(truthy:, falsy:, type:)
            @truthy = truthy
            @falsy = falsy
            @type = type
          end

          def ==(other)
            other.is_a?(Env) && other.truthy == truthy && other.falsy == falsy && other.type == type
          end

          alias eql? ==

          def hash
            self.class.hash ^ truthy.hash ^ falsy.hash
          end

          def inspect
            "#<Steep::AST::Types::Env @type=#{type}, @truthy=..., @falsy=...>"
          end

          alias to_s inspect
        end
      end
    end
  end
end
