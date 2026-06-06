module Steep
  module Services
    class TypeCheckCache
      # Top-level header for `.steep_cache/`. Mismatch on any field means the
      # serialized format may have changed in incompatible ways, so we discard
      # everything. Fine-grained invalidation (Steepfile edits, library/Ruby
      # updates) is handled by per-file digest diff in EnvEntry — not here.
      class Meta
        CURRENT_CACHE_VERSION = 1

        attr_reader :cache_version, :steep_version, :rbs_version

        def initialize(cache_version:, steep_version:, rbs_version:)
          @cache_version = cache_version
          @steep_version = steep_version
          @rbs_version = rbs_version
        end

        def self.current
          new(
            cache_version: CURRENT_CACHE_VERSION,
            steep_version: Steep::VERSION,
            rbs_version: RBS::VERSION
          )
        end

        def compatible_with?(other)
          cache_version == other.cache_version &&
            steep_version == other.steep_version &&
            rbs_version == other.rbs_version
        end

        def to_h
          {
            cache_version: cache_version,
            steep_version: steep_version,
            rbs_version: rbs_version
          }
        end

        def self.from_h(hash)
          new(
            cache_version: hash.fetch(:cache_version),
            steep_version: hash.fetch(:steep_version),
            rbs_version: hash.fetch(:rbs_version)
          )
        end
      end
    end
  end
end
