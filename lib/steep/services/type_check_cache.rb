require "digest"
require "fileutils"

module Steep
  module Services
    # On-disk cache for `bin/steep check`. Layout:
    #
    #   .steep_cache/
    #     meta.bin                              # format/version guard
    #     env/<hash>.bin                        # env-constituent file snapshots
    #     signatures/<target>/<relative>.bin    # project signature validation results
    #     sources/<target>/<relative>.bin       # source type-check results
    #
    # All files are Marshal-serialized Hashes. Each entry begins with a Meta
    # struct so individual files can be invalidated even when no top-level
    # meta.bin exists (defensive on partial writes).
    class TypeCheckCache
      ENV_DIR = "env".freeze
      SIGNATURES_DIR = "signatures".freeze
      SOURCES_DIR = "sources".freeze
      META_FILE = "meta.bin".freeze

      attr_reader :cache_dir

      def initialize(cache_dir:)
        @cache_dir = Pathname(cache_dir)
      end

      # --- meta -------------------------------------------------------------

      def meta_path
        cache_dir + META_FILE
      end

      def load_meta
        return nil unless meta_path.exist?
        data = read_marshal(meta_path)
        return nil unless data.is_a?(Hash)
        Meta.from_h(data)
      rescue StandardError
        nil
      end

      def write_meta(meta = Meta.current)
        ensure_dir(cache_dir)
        write_marshal(meta_path, meta.to_h)
      end

      # Returns true if the on-disk meta is compatible with the current Steep/RBS
      # version. When false, callers should #clear the cache before continuing.
      def meta_compatible?
        existing = load_meta or return false
        existing.compatible_with?(Meta.current)
      end

      # --- env entries ------------------------------------------------------

      def env_dir
        cache_dir + ENV_DIR
      end

      def env_entry_path(path)
        env_dir + "#{Digest::SHA256.hexdigest(path.to_s)}.bin"
      end

      def load_env_entry(path)
        file = env_entry_path(path)
        return nil unless file.exist?
        data = read_marshal(file)
        return nil unless data.is_a?(Hash)
        EnvEntry.from_h(data)
      rescue StandardError
        nil
      end

      def write_env_entry(entry)
        ensure_dir(env_dir)
        write_marshal(env_entry_path(entry.path), entry.to_h)
      end

      def each_env_entry(&block)
        return enum_for(:each_env_entry) unless block
        return unless env_dir.directory?
        env_dir.each_child do |file|
          next unless file.file? && file.extname == ".bin"
          data =
            begin
              read_marshal(file)
            rescue StandardError
              next
            end
          next unless data.is_a?(Hash)
          yield EnvEntry.from_h(data)
        end
      end

      # --- signature entries -----------------------------------------------

      def signature_entry_path(target_name, path)
        cache_dir + SIGNATURES_DIR + target_name.to_s + relative_bin_path(path)
      end

      def load_signature_entry(target_name, path)
        file = signature_entry_path(target_name, path)
        return nil unless file.exist?
        data = read_marshal(file)
        return nil unless data.is_a?(Hash)
        SignatureEntry.from_h(data)
      rescue StandardError
        nil
      end

      def write_signature_entry(entry)
        file = signature_entry_path(entry.target_name, entry.path)
        ensure_dir(file.parent)
        write_marshal(file, entry.to_h)
      end

      # --- source entries --------------------------------------------------

      def source_entry_path(target_name, path)
        cache_dir + SOURCES_DIR + target_name.to_s + relative_bin_path(path)
      end

      def load_source_entry(target_name, path)
        file = source_entry_path(target_name, path)
        return nil unless file.exist?
        data = read_marshal(file)
        return nil unless data.is_a?(Hash)
        SourceEntry.from_h(data)
      rescue StandardError
        nil
      end

      def write_source_entry(entry)
        file = source_entry_path(entry.target_name, entry.path)
        ensure_dir(file.parent)
        write_marshal(file, entry.to_h)
      end

      # --- bulk ops --------------------------------------------------------

      def clear
        return unless cache_dir.directory?
        cache_dir.each_child do |child|
          FileUtils.rm_rf(child.to_s)
        end
      end

      def self.digest_content(content)
        Digest::SHA256.hexdigest(content)
      end

      private

      def read_marshal(file)
        Marshal.load(file.binread)
      end

      # Atomic write: dump to a sibling tempfile then rename, so a crashed
      # process cannot leave a half-written entry that later reads will trust.
      def write_marshal(file, data)
        tmp = file.sub_ext(".bin.tmp.#{Process.pid}.#{rand(1_000_000)}")
        tmp.binwrite(Marshal.dump(data))
        File.rename(tmp.to_s, file.to_s)
      end

      def ensure_dir(dir)
        FileUtils.mkdir_p(dir.to_s)
      end

      # Mirror the project layout under <target>/ so cache files are easy to
      # find and to clean up by path.
      def relative_bin_path(path)
        path = Pathname(path)
        rel =
          if path.absolute?
            digest = Digest::SHA256.hexdigest(path.to_s)
            "#{digest}_#{path.basename}"
          else
            path.to_s
          end
        Pathname("#{rel}.bin")
      end
    end
  end
end
