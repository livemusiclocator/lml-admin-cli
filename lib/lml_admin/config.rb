# frozen_string_literal: true

module LmlAdmin
  # Where the token and the base URL come from.
  #
  # There is deliberately no --token flag. Command line arguments are visible in
  # `ps` output and land in shell history, and a token that leaks that way is a
  # token somebody has to go and revoke.
  module Config
    DEFAULT_BASE_URL = "https://api.lml.live"
    CREDENTIALS_PATH = File.join(Dir.home, ".config", "lml", "credentials")

    class MissingToken < StandardError; end

    def self.token
      from_env = ENV.fetch("LML_ADMIN_TOKEN", nil)
      return from_env unless from_env.to_s.strip.empty?

      from_file = token_from_file
      return from_file unless from_file.to_s.strip.empty?

      raise MissingToken, <<~MESSAGE
        No admin API token found. Either:

          export LML_ADMIN_TOKEN=lml_admin_...

        or put it in #{CREDENTIALS_PATH}:

          mkdir -p #{File.dirname(CREDENTIALS_PATH)}
          printf 'lml_admin_...' > #{CREDENTIALS_PATH}
          chmod 600 #{CREDENTIALS_PATH}

        Issue a token at https://www.livemusiclocator.com.au/backstage/api_tokens
      MESSAGE
    end

    def self.token_from_file
      return nil unless File.exist?(CREDENTIALS_PATH)

      warn_if_readable_by_others
      File.read(CREDENTIALS_PATH).strip
    end

    def self.warn_if_readable_by_others
      mode = File.stat(CREDENTIALS_PATH).mode & 0o077
      return if mode.zero?

      warn "warning: #{CREDENTIALS_PATH} is readable by other users - chmod 600 it."
    end

    def self.base_url
      ENV.fetch("LML_API_URL", DEFAULT_BASE_URL)
    end

    def self.allow_insecure?
      ENV.fetch("LML_ALLOW_INSECURE", "") == "1"
    end
  end
end
