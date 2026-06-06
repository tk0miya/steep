module Steep
  module Services
    class TypeCheckCache
      # Per-file validation result for a project signature file (RBS owned by a
      # target). Lets us reuse last run's diagnostics when neither the file nor
      # anything it references has changed.
      #
      # content_digest is also stored in EnvEntry for the same path; the copy
      # here makes the signatures cache self-contained for cache-hit checks
      # without cross-referencing env entries.
      class SignatureEntry
        attr_reader :path,
                    :target_name,
                    :content_digest,
                    :referenced_type_names,
                    :diagnostics

        def initialize(path:, target_name:, content_digest:, referenced_type_names:, diagnostics:)
          @path = path
          @target_name = target_name
          @content_digest = content_digest
          @referenced_type_names = referenced_type_names
          @diagnostics = diagnostics
        end

        def to_h
          {
            path: path.to_s,
            target_name: target_name,
            content_digest: content_digest,
            referenced_type_names: referenced_type_names,
            diagnostics: diagnostics
          }
        end

        def self.from_h(hash)
          new(
            path: Pathname(hash.fetch(:path)),
            target_name: hash.fetch(:target_name),
            content_digest: hash.fetch(:content_digest),
            referenced_type_names: hash.fetch(:referenced_type_names),
            diagnostics: hash.fetch(:diagnostics)
          )
        end
      end
    end
  end
end
