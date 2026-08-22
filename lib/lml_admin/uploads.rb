# frozen_string_literal: true

module LmlAdmin
  # Uploads do not take field flags the way venues and acts do - the payload is a
  # file of clipper content - so they get their own command rather than being
  # bent into Resource's shape.
  class Uploads
    PATH = "/v1/admin/uploads"
    GIG_COLUMNS = %i[id name date start_time status].freeze

    def initialize(cli, argv, out)
      @cli = cli
      @argv = argv
      @out = out
    end

    def run
      case @argv.shift
      when "create" then create
      when "list" then list
      when "show" then show
      else usage_error("Expected one of create, list, show after uploads.")
      end
    end

    private

    def create
      options = parse_create_options
      return usage_error("Which file? Pass --file PATH, or --file - to read stdin.") if options[:file].nil?

      payload = @cli.client.post(PATH, "upload" => {
        "content" => read_content(options[:file]),
        "source" => options[:source] || "cli",
        "venue_id" => options[:venue_id],
      }.compact,)

      report(payload.fetch("upload"))
      0
    end

    def list
      options = {}
      OptionParser.new do |parser|
        parser.on("--source SOURCE") { |value| options["source"] = value }
        parser.on("--page PAGE") { |value| options["page"] = value }
        parser.on("--per-page COUNT") { |value| options["per_page"] = value }
      end.parse!(@argv)

      payload = @cli.client.get(PATH, options)
      @out.collection(payload.fetch("uploads"), payload.fetch("meta"), %i[id created_at source status])
      0
    end

    def show
      id = @argv.shift
      return usage_error("Which upload? Pass its id.") if id.nil?

      report(@cli.client.get("#{PATH}/#{id}").fetch("upload"))
      0
    end

    # The gigs are the point of an upload, so they get printed rather than left
    # nested in --json only.
    def report(upload)
      return @out.record(upload) if @out.json?

      @out.record(upload.except("gigs", "content"))
      gigs = upload["gigs"] || []
      return @out.puts("\nNo gigs.") if gigs.empty?

      @out.puts("\n#{gigs.length} #{gigs.length == 1 ? 'gig' : 'gigs'}:")
      @out.collection(gigs, { "page" => 1, "per_page" => gigs.length, "total" => gigs.length }, GIG_COLUMNS)
    end

    # `-` means stdin, so content can be piped in without a temporary file.
    def read_content(path)
      content = path == "-" ? $stdin.read : File.read(path)
      raise ArgumentError, "#{path} is empty - there is nothing to upload." if content.strip.empty?

      content
    end

    def parse_create_options
      options = {}
      OptionParser.new do |parser|
        parser.on("--file PATH") { |value| options[:file] = value }
        parser.on("--venue-id ID") { |value| options[:venue_id] = value }
        parser.on("--source SOURCE") { |value| options[:source] = value }
      end.parse!(@argv)
      options
    end

    def usage_error(message)
      @out.error(message)
      @out.puts("Run `lml help` for the full list.")
      2
    end
  end
end
