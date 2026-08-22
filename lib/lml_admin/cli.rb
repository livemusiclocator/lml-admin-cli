# frozen_string_literal: true

require "optparse"

module LmlAdmin
  # Argument parsing and dispatch. Every command ends up as one HTTP call, so
  # this file doubles as a map of the API.
  class CLI
    ACTIONS = %w[list show create update].freeze

    def initialize(argv, output: nil, client: nil)
      @argv = argv.dup
      @output = output
      @client = client
    end

    # Returns the process exit status.
    def run
      return usage_error("Nothing to do.") if @argv.empty?
      return help if %w[-h --help help].include?(@argv.first)
      return version if %w[-v --version version].include?(@argv.first)

      json = extract_json_flag
      resource_name = @argv.shift
      return check(json) if resource_name == "check"
      return Uploads.new(self, @argv, output(json: json)).run if resource_name == "uploads"

      dispatch(resource_name, json)
    rescue Config::MissingToken, InsecureUrlError, ArgumentError => e
      output(json: false).error(e.message)
      2
    rescue Errno::ENOENT => e
      output(json: false).error(e.message)
      2
    rescue ApiError => e
      report(e, json)
      failure_status(e)
    rescue Interrupt
      130
    end

    def client
      @client ||= Client.new(
        base_url: Config.base_url,
        token: Config.token,
        allow_insecure: Config.allow_insecure?,
      )
    end

    private

    def dispatch(resource_name, json)
      resource = Resource.find(resource_name)
      action = @argv.shift
      return usage_error("Expected one of #{ACTIONS.join(', ')} after #{resource_name}.") unless ACTIONS.include?(action)

      send(action, resource, output(json: json))
    end

    def list(resource, out)
      options = parse_list_options
      payload = client.get(resource.collection_path, options)

      out.collection(payload.fetch(resource.plural), payload.fetch("meta"), resource.columns)
      0
    end

    def show(resource, out)
      id = @argv.shift
      return usage_error("Which #{resource.singular}? Pass its id.") if id.nil?

      out.record(client.get(resource.member_path(id)).fetch(resource.singular))
      0
    end

    def create(resource, out)
      attributes, unset = parse_attributes(resource)
      return usage_error("Nothing to create - pass at least #{resource.flag_for(:name)}.") if attributes.empty?

      payload = client.post(resource.collection_path, resource.singular => attributes.merge(unset))
      out.puts("Created #{resource.singular} #{payload.fetch(resource.singular)['id']}") unless out.json?
      out.record(payload.fetch(resource.singular))
      0
    end

    def update(resource, out)
      id = @argv.shift
      return usage_error("Which #{resource.singular}? Pass its id.") if id.nil?

      attributes, unset = parse_attributes(resource)
      return usage_error("Nothing to change. Pass a field to set, or --unset FIELD.") if attributes.empty? && unset.empty?

      payload = client.patch(resource.member_path(id), resource.singular => attributes.merge(unset))
      out.record(payload.fetch(resource.singular))
      0
    end

    # Confirms the token works and says who it belongs to, without changing
    # anything - the first thing to run when an integration misbehaves.
    def check(json)
      out = output(json: json)
      client.get("/v1/admin/acts", "per_page" => 1)
      out.puts("Token accepted by #{Config.base_url}.")
      0
    end

    def parse_list_options
      options = {}
      OptionParser.new do |parser|
        parser.on("--q QUERY") { |value| options["q"] = value }
        parser.on("--page PAGE") { |value| options["page"] = value }
        parser.on("--per-page COUNT") { |value| options["per_page"] = value }
      end.parse!(@argv)
      options
    end

    # Builds the attribute hash from --field value flags, plus --unset field for
    # the fields the API clears when given null.
    def parse_attributes(resource)
      attributes = {}
      unset = {}

      parser = OptionParser.new do |opts|
        resource.fields.each_key do |field|
          opts.on("#{resource.flag_for(field)} VALUE") do |value|
            attributes[field.to_s] = resource.coerce(field, value)
          end
        end
        opts.on("--unset FIELD") do |name|
          field = resource.field_for("--#{name.tr('_', '-')}")
          raise ArgumentError, "#{resource.plural} have no #{name} to unset." if field.nil?

          unset[field.to_s] = nil
        end
      end
      parser.parse!(@argv)

      [attributes, unset]
    end

    def extract_json_flag
      json = @argv.delete("--json")
      !json.nil?
    end

    def report(error, json)
      out = output(json: json)
      out.error("#{error.status}: #{error.message}", error.details)
      upload = error.body["upload"] if error.body.is_a?(Hash)
      out.puts("Upload #{upload['id']} was kept - fix the content and send it again.") if upload
      return unless error.status == 401

      out.puts("Issue or check your token at https://www.livemusiclocator.com.au/backstage/api_tokens")
    end

    # 401 and 403 get their own status so a wrapper script can tell "my token is
    # wrong" apart from "my request was wrong".
    def failure_status(error)
      case error.status
      when 401, 403 then 3
      else 1
      end
    end

    def usage_error(message)
      output(json: false).error(message)
      output(json: false).puts("Run `lml help` for the full list.")
      2
    end

    def output(json:)
      @output || Output.new(json: json)
    end

    def version
      output(json: false).puts("lml-admin-cli #{LmlAdmin::VERSION}")
      0
    end

    def help
      output(json: false).puts(HELP)
      0
    end

    HELP = <<~TEXT
      lml - a command line client for the Live Music Locator admin API

      Usage:
        lml check
        lml uploads create --file PATH [--venue-id ID] [--source NAME] [--json]
        lml uploads list   [--source NAME] [--page N] [--per-page N] [--json]
        lml uploads show   <id> [--json]
        lml <venues|acts> list   [--q QUERY] [--page N] [--per-page N] [--json]
        lml <venues|acts> show   <id> [--json]
        lml <venues|acts> create --name NAME [--field value ...] [--json]
        lml <venues|acts> update <id> [--field value ...] [--unset FIELD] [--json]

      Examples:
        lml venues list --q tote
        lml venues show 0a1b2c3d-...
        lml venues create --name "The Curtin" --time-zone Australia/Melbourne --capacity 200
        lml venues update 0a1b2c3d-... --capacity 350 --tags "band room,late"
        lml acts create --name "Cash Savage" --country Australia --genres "blues,country"
        lml acts update 0a1b2c3d-... --instagram https://www.instagram.com/cashsavage
        lml acts update 0a1b2c3d-... --unset instagram

        lml uploads create --file friday.clipper --venue-id 0a1b2c3d-... --source cli
        cat friday.clipper | lml uploads create --file - --venue-id 0a1b2c3d-...

      Venue fields:
        #{Resource.find('venues').fields.keys.map { |f| "--#{f.to_s.tr('_', '-')}" }.join(' ')}

      Act fields:
        #{Resource.find('acts').fields.keys.map { |f| "--#{f.to_s.tr('_', '-')}" }.join(' ')}

      Authentication:
        LML_ADMIN_TOKEN=lml_admin_...   or ~/.config/lml/credentials (chmod 600)

        There is no --token flag on purpose: arguments show up in `ps` output and
        in your shell history. Issue and revoke tokens in backstage:
        https://www.livemusiclocator.com.au/backstage/api_tokens

      Environment:
        LML_ADMIN_TOKEN     the bearer token to authenticate with
        LML_API_URL         defaults to https://api.lml.live
        LML_ALLOW_INSECURE  set to 1 to allow a plain http base url, for local dev

      Uploads:
        Clipper content, the same format the admin upload form takes. Entries are
        separated by a line of ---, and each entry is `key: value` lines. A gig is
        matched on name, date and venue, so resending a corrected file is safe.

        --venue-id sets the venue for entries that do not name their own with a
        `venue_id:` line. --file - reads standard input.

      Exit status:
        0 fine   1 request rejected   2 bad usage   3 token refused
    TEXT
  end
end
