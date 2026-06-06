module Steep
  module Services
    class TypeCheckCache
      # Per-file type-check result for a Ruby source file.
      #
      # has_unresolved_references mirrors the runtime field on
      # TypeCheckService::SourceFile: an incomplete refs set means we can't
      # trust the intersection with changed_names, so we must re-check until
      # the unresolved reference is resolved.
      class SourceEntry
        attr_reader :path,
                    :target_name,
                    :content_digest,
                    :referenced_type_names,
                    :has_unresolved_references,
                    :diagnostics

        def initialize(path:, target_name:, content_digest:, referenced_type_names:, has_unresolved_references:, diagnostics:)
          @path = path
          @target_name = target_name
          @content_digest = content_digest
          @referenced_type_names = referenced_type_names
          @has_unresolved_references = has_unresolved_references
          @diagnostics = diagnostics
        end

        def to_h
          {
            path: path.to_s,
            target_name: target_name,
            content_digest: content_digest,
            referenced_type_names: referenced_type_names,
            has_unresolved_references: has_unresolved_references,
            diagnostics: diagnostics
          }
        end

        def self.from_h(hash)
          new(
            path: Pathname(hash.fetch(:path)),
            target_name: hash.fetch(:target_name),
            content_digest: hash.fetch(:content_digest),
            referenced_type_names: hash.fetch(:referenced_type_names),
            has_unresolved_references: hash.fetch(:has_unresolved_references),
            diagnostics: hash.fetch(:diagnostics)
          )
        end
      end
    end
  end
end
