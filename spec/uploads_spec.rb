# frozen_string_literal: true

require "stringio"
require "tmpdir"

describe LmlAdmin::Uploads do
  before do
    @io = StringIO.new
    @dir = Dir.mktmpdir
    @file = File.join(@dir, "friday.clipper")
    File.write(@file, "name: Sniffers Live\ndate: 2026-09-01\n")

    @created = {
      upload: {
        id: "u1", source: "cli", format: "clipper", status: "Succeeded",
        error_description: nil, venue_id: "v1",
        gigs: [{ id: "g1", name: "Sniffers Live", date: "2026-09-01", start_time: "20:00", status: "confirmed" }],
      },
    }.to_json
  end

  after { FileUtils.remove_entry(@dir) }

  def run(*argv, json: false)
    status = LmlAdmin::CLI.new(argv, output: LmlAdmin::Output.new(io: @io, json: json)).run
    [status, @io.string]
  end

  describe "create" do
    it "posts the file's content" do
      request = stub_request(:post, "https://api.example.test/v1/admin/uploads")
                .with(body: {
                        upload: {
                          content: "name: Sniffers Live\ndate: 2026-09-01\n",
                          source: "cli", venue_id: "v1"
                        },
                      })
                .to_return(status: 201, body: @created, headers: { "Content-Type" => "application/json" })

      status, = run("uploads", "create", "--file", @file, "--venue-id", "v1")

      expect(status).to eq(0)
      expect(request).to have_been_requested
    end

    it "prints the gigs the upload created" do
      stub_request(:post, "https://api.example.test/v1/admin/uploads")
        .to_return(status: 201, body: @created, headers: { "Content-Type" => "application/json" })

      _, printed = run("uploads", "create", "--file", @file, "--venue-id", "v1")

      expect(printed).to include("1 gig:")
      expect(printed).to include("Sniffers Live")
    end

    it "leaves venue_id out when the file names its own venues" do
      request = stub_request(:post, "https://api.example.test/v1/admin/uploads")
                .with(body: { upload: { content: File.read(@file), source: "cli" } })
                .to_return(status: 201, body: @created, headers: { "Content-Type" => "application/json" })

      run("uploads", "create", "--file", @file)

      expect(request).to have_been_requested
    end

    it "uses a source when given one" do
      request = stub_request(:post, "https://api.example.test/v1/admin/uploads")
                .with(body: { upload: { content: File.read(@file), source: "friday-sheet" } })
                .to_return(status: 201, body: @created, headers: { "Content-Type" => "application/json" })

      run("uploads", "create", "--file", @file, "--source", "friday-sheet")

      expect(request).to have_been_requested
    end

    it "reads standard input when the file is -" do
      request = stub_request(:post, "https://api.example.test/v1/admin/uploads")
                .with(body: { upload: { content: "name: Piped\ndate: 2026-09-01\n", source: "cli" } })
                .to_return(status: 201, body: @created, headers: { "Content-Type" => "application/json" })

      original = $stdin
      $stdin = StringIO.new("name: Piped\ndate: 2026-09-01\n")
      run("uploads", "create", "--file", "-")
      $stdin = original

      expect(request).to have_been_requested
    end

    it "asks for a file rather than posting nothing" do
      status, printed = run("uploads", "create")

      expect(status).to eq(2)
      expect(printed).to include("Which file?")
    end

    it "says which file it could not find, without making a request" do
      status, printed = run("uploads", "create", "--file", File.join(@dir, "nope.clipper"))

      expect(status).to eq(2)
      expect(printed).to include("nope.clipper")
      expect(a_request(:post, //)).not_to have_been_made
    end

    it "refuses an empty file" do
      File.write(@file, "   \n")

      status, printed = run("uploads", "create", "--file", @file)

      expect(status).to eq(2)
      expect(printed).to include("is empty")
    end

    it "reports a rejected entry and keeps the upload id in view" do
      stub_request(:post, "https://api.example.test/v1/admin/uploads")
        .to_return(status: 422,
                   body: { error: "1: 'not a date' is not a valid date", upload: { id: "u9" } }.to_json,
                   headers: { "Content-Type" => "application/json" })

      status, printed = run("uploads", "create", "--file", @file)

      expect(status).to eq(1)
      expect(printed).to include("not a valid date")
      expect(printed).to include("Upload u9 was kept")
    end

    it "reports an upload too big to process" do
      stub_request(:post, "https://api.example.test/v1/admin/uploads")
        .to_return(status: 422, body: '{"error":"That upload has 150 entries and the limit is 100."}',
                   headers: { "Content-Type" => "application/json" })

      status, printed = run("uploads", "create", "--file", @file)

      expect(status).to eq(1)
      expect(printed).to include("the limit is 100")
    end
  end

  describe "list and show" do
    it "lists uploads" do
      stub_request(:get, "https://api.example.test/v1/admin/uploads")
        .to_return(body: {
          uploads: [{ id: "u1", created_at: "2026-08-23T10:00:00Z", source: "cli", status: "Succeeded" }],
          meta: { page: 1, per_page: 50, total: 1 },
        }.to_json, headers: { "Content-Type" => "application/json" })

      status, printed = run("uploads", "list")

      expect(status).to eq(0)
      expect(printed).to include("Succeeded")
    end

    it "filters by source" do
      request = stub_request(:get, "https://api.example.test/v1/admin/uploads?source=cli")
                .to_return(body: '{"uploads":[],"meta":{"page":1,"per_page":50,"total":0}}',
                           headers: { "Content-Type" => "application/json" })

      run("uploads", "list", "--source", "cli")

      expect(request).to have_been_requested
    end

    it "shows one upload with its gigs" do
      stub_request(:get, "https://api.example.test/v1/admin/uploads/u1")
        .to_return(body: @created, headers: { "Content-Type" => "application/json" })

      _, printed = run("uploads", "show", "u1")

      expect(printed).to include("Sniffers Live")
    end

    it "asks for an id when showing" do
      status, printed = run("uploads", "show")

      expect(status).to eq(2)
      expect(printed).to include("Which upload?")
    end
  end
end
