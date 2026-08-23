# frozen_string_literal: true

require "stringio"

describe LmlAdmin::CLI do
  before do
    @io = StringIO.new
  end

  # Runs the CLI the way a shell would, capturing what it printed.
  def run(*argv, json: false)
    status = described_class.new(argv, output: LmlAdmin::Output.new(io: @io, json: json)).run
    [status, @io.string]
  end

  describe "help and version" do
    it "prints usage" do
      status, printed = run("help")

      expect(status).to eq(0)
      expect(printed).to include("lml <venues|acts> list")
    end

    it "documents every writable venue field, so the help cannot drift from the api" do
      _, printed = run("help")

      LmlAdmin::Resource.find("venues").fields.each_key do |field|
        expect(printed).to include("--#{field.to_s.tr('_', '-')}")
      end
    end

    it "prints the version" do
      status, printed = run("--version")

      expect(status).to eq(0)
      expect(printed).to include(LmlAdmin::VERSION)
    end
  end

  describe "usage errors" do
    it "rejects an unknown resource without making a request" do
      status, printed = run("promoters", "list")

      expect(status).to eq(2)
      expect(printed).to include("Unknown resource promoters")
    end

    # Gigs are read only, and saying so up front beats a puzzling 404 from a
    # route that does not exist.
    it "refuses to update a gig, which the api will not do" do
      status, printed = run("gigs", "update", "g1", "--name", "Nope")

      expect(status).to eq(2)
      expect(printed).to include("Expected one of list, show, clipper")
    end

    it "rejects an unknown action" do
      status, printed = run("venues", "destroy")

      expect(status).to eq(2)
      expect(printed).to include("Expected one of list, show, create, update")
    end

    it "asks for an id when showing" do
      status, printed = run("venues", "show")

      expect(status).to eq(2)
      expect(printed).to include("Pass its id")
    end

    it "refuses an update with nothing to change" do
      status, printed = run("venues", "update", "abc")

      expect(status).to eq(2)
      expect(printed).to include("Nothing to change")
    end

    it "refuses to unset a field the resource does not have" do
      status, printed = run("venues", "update", "abc", "--unset", "vibes")

      expect(status).to eq(2)
      expect(printed).to include("no vibes to unset")
    end
  end

  describe "listing" do
    before do
      @body = {
        venues: [{ id: "v1", name: "The Tote", location: "melbourne", capacity: 400 }],
        meta: { page: 1, per_page: 50, total: 1 },
      }.to_json
    end

    it "prints a table with the totals" do
      stub_request(:get, "https://api.example.test/v1/admin/venues")
        .to_return(body: @body, headers: { "Content-Type" => "application/json" })

      status, printed = run("venues", "list")

      expect(status).to eq(0)
      expect(printed).to include("The Tote")
      expect(printed).to include("1 in total")
    end

    it "passes the search and paging options through" do
      request = stub_request(:get, "https://api.example.test/v1/admin/venues?q=tote&page=2&per_page=10")
                .to_return(body: @body, headers: { "Content-Type" => "application/json" })

      run("venues", "list", "--q", "tote", "--page", "2", "--per-page", "10")

      expect(request).to have_been_requested
    end

    it "prints raw json when asked" do
      stub_request(:get, "https://api.example.test/v1/admin/venues")
        .to_return(body: @body, headers: { "Content-Type" => "application/json" })

      _, printed = run("venues", "list", json: true)

      expect(JSON.parse(printed)["records"].first["name"]).to eq("The Tote")
    end
  end

  describe "listing gigs" do
    before do
      @body = {
        gigs: [{
          id: "g1", name: "Andrew Swift", date: "2026-09-18", start_time: "20:00",
          status: "confirmed", venue: { id: "v1", name: "Golden Vine Hotel" }
        }],
        meta: { page: 1, per_page: 50, total: 1 },
      }.to_json
    end

    it "shows the venue name from the nested venue object" do
      stub_request(:get, "https://api.example.test/v1/admin/gigs")
        .to_return(body: @body, headers: { "Content-Type" => "application/json" })

      status, printed = run("gigs", "list")

      expect(status).to eq(0)
      expect(printed).to include("Golden Vine Hotel")
      expect(printed).to include("VENUE")
    end

    it "passes the venue and date filters through" do
      request = stub_request(
        :get,
        "https://api.example.test/v1/admin/gigs?venue_id=v1&date_from=2026-08-24&date_to=2026-12-31",
      ).to_return(body: @body, headers: { "Content-Type" => "application/json" })

      run("gigs", "list", "--venue-id", "v1", "--date-from", "2026-08-24", "--date-to", "2026-12-31")

      expect(request).to have_been_requested
    end

    it "has no --q, because the endpoint has none" do
      status, printed = run("gigs", "list", "--q", "swift")

      expect(status).to eq(2)
      expect(printed).to include("invalid option: --q")
    end

    # A mistyped flag used to print a ruby backtrace, which said nothing about
    # which flag was wrong.
    it "reports a mistyped flag as a usage error rather than a backtrace" do
      status, printed = run("venues", "list", "--locatoin", "melbourne")

      expect(status).to eq(2)
      expect(printed).to include("invalid option: --locatoin")
      expect(printed).to include("lml help")
    end
  end

  describe "gigs clipper" do
    it "prints the clipper text untouched, so it can be redirected to a file" do
      clipper = "---\nname: Andrew Swift\ndate: 2026-09-18\n"
      stub_request(:get, "https://api.example.test/v1/admin/gigs/clipper?venue_id=v1")
        .to_return(body: clipper, headers: { "Content-Type" => "text/plain" })

      status, printed = run("gigs", "clipper", "--venue-id", "v1")

      expect(status).to eq(0)
      expect(printed).to eq(clipper)
    end

    it "asks for text rather than json, and never sends the token in the query" do
      request = stub_request(:get, "https://api.example.test/v1/admin/gigs/clipper")
                .with(headers: { "Accept" => "text/plain, */*" })
                .to_return(body: "", headers: { "Content-Type" => "text/plain" })

      run("gigs", "clipper")

      expect(request).to have_been_requested
    end

    it "still reports a refused token as a token problem" do
      stub_request(:get, "https://api.example.test/v1/admin/gigs/clipper")
        .to_return(status: 401, body: '{"error":"Provide an admin API token."}',
                   headers: { "Content-Type" => "application/json" })

      status, printed = run("gigs", "clipper")

      expect(status).to eq(3)
      expect(printed).to include("backstage/api_tokens")
    end
  end

  describe "creating" do
    it "sends the typed attributes under the singular key" do
      request = stub_request(:post, "https://api.example.test/v1/admin/venues")
                .with(body: {
                        venue: {
                          name: "The Curtin", time_zone: "Australia/Melbourne",
                          capacity: 200, tags: ["band room", "late"]
                        },
                      })
                .to_return(status: 201, body: { venue: { id: "v9", name: "The Curtin" } }.to_json,
                           headers: { "Content-Type" => "application/json" })

      status, = run("venues", "create", "--name", "The Curtin", "--time-zone", "Australia/Melbourne",
                    "--capacity", "200", "--tags", "band room, late",)

      expect(status).to eq(0)
      expect(request).to have_been_requested
    end

    it "splits a comma separated list into an array" do
      request = stub_request(:post, "https://api.example.test/v1/admin/acts")
                .with(body: { act: { name: "Cash Savage", genres: ["blues", "country"] } })
                .to_return(status: 201, body: { act: { id: "a1" } }.to_json,
                           headers: { "Content-Type" => "application/json" })

      run("acts", "create", "--name", "Cash Savage", "--genres", "blues,country")

      expect(request).to have_been_requested
    end
  end

  describe "updating" do
    it "sends only the fields it was given" do
      request = stub_request(:patch, "https://api.example.test/v1/admin/venues/v1")
                .with(body: { venue: { capacity: 350 } })
                .to_return(body: { venue: { id: "v1", capacity: 350 } }.to_json,
                           headers: { "Content-Type" => "application/json" })

      status, = run("venues", "update", "v1", "--capacity", "350")

      expect(status).to eq(0)
      expect(request).to have_been_requested
    end

    it "sends null for an unset field, which is how the api clears one" do
      request = stub_request(:patch, "https://api.example.test/v1/admin/acts/a1")
                .with(body: { act: { instagram: nil } })
                .to_return(body: { act: { id: "a1" } }.to_json, headers: { "Content-Type" => "application/json" })

      run("acts", "update", "a1", "--unset", "instagram")

      expect(request).to have_been_requested
    end
  end

  describe "when the api refuses" do
    it "reports a rejected token with its own exit status" do
      stub_request(:get, "https://api.example.test/v1/admin/venues")
        .to_return(status: 401, body: '{"error":"Provide an admin API token."}',
                   headers: { "Content-Type" => "application/json" })

      status, printed = run("venues", "list")

      expect(status).to eq(3)
      expect(printed).to include("backstage/api_tokens")
    end

    it "reports a forbidden token as a token problem too" do
      stub_request(:get, "https://api.example.test/v1/admin/venues")
        .to_return(status: 403, body: '{"error":"That token\'s owner is not an admin."}',
                   headers: { "Content-Type" => "application/json" })

      status, = run("venues", "list")

      expect(status).to eq(3)
    end

    it "prints the per field errors from a validation failure" do
      stub_request(:post, "https://api.example.test/v1/admin/venues")
        .to_return(status: 422,
                   body: '{"error":"That record is not valid.","details":{"time_zone":["invalid time zone"]}}',
                   headers: { "Content-Type" => "application/json" })

      status, printed = run("venues", "create", "--name", "Nowhere", "--time-zone", "Mars/Olympus_Mons")

      expect(status).to eq(1)
      expect(printed).to include("time_zone: invalid time zone")
    end
  end

  describe "check" do
    it "confirms a working token without changing anything" do
      request = stub_request(:get, "https://api.example.test/v1/admin/acts?per_page=1")
                .to_return(body: '{"acts":[],"meta":{}}', headers: { "Content-Type" => "application/json" })

      status, printed = run("check")

      expect(status).to eq(0)
      expect(printed).to include("Token accepted")
      expect(request).to have_been_requested
    end
  end

  describe "configuration" do
    it "explains how to get a token when there is none" do
      ENV.delete("LML_ADMIN_TOKEN")
      allow(File).to receive(:exist?).with(LmlAdmin::Config::CREDENTIALS_PATH).and_return(false)

      status, printed = run("venues", "list")

      expect(status).to eq(2)
      expect(printed).to include("No admin API token found")
    end
  end
end
