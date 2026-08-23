# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module LmlAdmin
  # Anything the API refused. `details` carries the per field errors from a 422,
  # so a caller can point at the field that was actually wrong.
  class ApiError < StandardError
    attr_reader :status, :details, :body

    def initialize(status:, message:, details: nil, body: {})
      @status = status
      @details = details
      @body = body
      super(message)
    end
  end

  class InsecureUrlError < StandardError; end

  # A thin wrapper over the admin API. Deliberately stdlib only - anyone with
  # ruby can read this file and see exactly what the API expects.
  class Client
    USER_AGENT = "lml-admin-cli"

    def initialize(base_url:, token:, allow_insecure: false)
      @base_url = base_url.to_s.chomp("/")
      @token = token
      return if @base_url.start_with?("https://") || allow_insecure

      raise InsecureUrlError,
            "Refusing to send a token to #{@base_url} over plain http. " \
            "Set LML_ALLOW_INSECURE=1 if this is a local development server."
    end

    def get(path, params = {})
      send_request(get_request(path, params))
    end

    # The response body untouched. /v1/admin/gigs/clipper answers with clipper
    # text rather than JSON, and parsing it would throw the whole thing away.
    #
    # A separate method rather than a `raw:` keyword on #get, because callers
    # pass their params as a bare trailing hash - `get(path, "q" => "x")` - and
    # ruby would hand that to a keyword parameter instead.
    def get_text(path, params = {})
      send_request(get_request(path, params), raw: true)
    end

    def post(path, body)
      send_request(Net::HTTP::Post.new(uri_for(path)), body)
    end

    def patch(path, body)
      send_request(Net::HTTP::Patch.new(uri_for(path)), body)
    end

    private

    def uri_for(path)
      URI.parse("#{@base_url}#{path}")
    end

    def get_request(path, params)
      uri = uri_for(path)
      present = params.reject { |_, value| value.nil? || value.to_s.empty? }
      uri.query = URI.encode_www_form(present) if present.any?

      Net::HTTP::Get.new(uri)
    end

    def send_request(request, body = nil, raw: false)
      # The token goes in a header and never in the query string. Query strings
      # end up in router logs, proxy logs, referrers and shell history - which
      # is the whole reason the API refuses a token presented that way.
      request["Authorization"] = "Bearer #{@token}"
      request["Accept"] = raw ? "text/plain, */*" : "application/json"
      request["User-Agent"] = USER_AGENT

      if body
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body)
      end

      uri = request.uri
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end

      interpret(response, raw: raw)
    end

    # An error is JSON whatever the request asked for, so raw only changes what
    # a success looks like.
    def interpret(response, raw: false)
      return response.body.to_s if raw && response.is_a?(Net::HTTPSuccess)

      parsed = parse(response.body)
      return parsed if response.is_a?(Net::HTTPSuccess)

      raise ApiError.new(
        status: response.code.to_i,
        message: parsed["error"] || "The API returned HTTP #{response.code}.",
        details: parsed["details"],
        body: parsed,
      )
    end

    def parse(body)
      return {} if body.to_s.strip.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      {}
    end
  end
end
