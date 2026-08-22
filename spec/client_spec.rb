# frozen_string_literal: true

describe LmlAdmin::Client do
  before do
    @client = described_class.new(base_url: "https://api.example.test", token: "lml_admin_secret")
  end

  describe "authentication" do
    it "sends the token as a bearer header" do
      request = stub_request(:get, "https://api.example.test/v1/admin/acts")
                .with(headers: { "Authorization" => "Bearer lml_admin_secret" })
                .to_return(body: "{}", headers: { "Content-Type" => "application/json" })

      @client.get("/v1/admin/acts")

      expect(request).to have_been_requested
    end

    it "never puts the token in the query string, where logs would keep it" do
      stub_request(:get, "https://api.example.test/v1/admin/acts?q=tote")
        .to_return(body: "{}", headers: { "Content-Type" => "application/json" })

      @client.get("/v1/admin/acts", "q" => "tote")

      expect(a_request(:get, %r{/v1/admin/acts\?.*token})).not_to have_been_made
    end

    it "refuses to send a token over plain http" do
      expect { described_class.new(base_url: "http://api.example.test", token: "lml_admin_secret") }
        .to raise_error(LmlAdmin::InsecureUrlError, /plain http/)
    end

    it "allows plain http when explicitly told to, for a local server" do
      expect { described_class.new(base_url: "http://localhost:3000", token: "x", allow_insecure: true) }
        .not_to raise_error
    end
  end

  describe "requests" do
    it "drops empty query parameters rather than sending blanks" do
      request = stub_request(:get, "https://api.example.test/v1/admin/venues?page=2")
                .to_return(body: "{}", headers: { "Content-Type" => "application/json" })

      @client.get("/v1/admin/venues", "q" => "", "page" => "2", "per_page" => nil)

      expect(request).to have_been_requested
    end

    it "sends a json body on create" do
      request = stub_request(:post, "https://api.example.test/v1/admin/acts")
                .with(body: { act: { name: "Cash Savage" } }, headers: { "Content-Type" => "application/json" })
                .to_return(status: 201, body: "{}", headers: { "Content-Type" => "application/json" })

      @client.post("/v1/admin/acts", "act" => { "name" => "Cash Savage" })

      expect(request).to have_been_requested
    end

    it "returns the parsed body" do
      stub_request(:get, "https://api.example.test/v1/admin/acts/1")
        .to_return(body: '{"act":{"name":"Cable Ties"}}', headers: { "Content-Type" => "application/json" })

      expect(@client.get("/v1/admin/acts/1")).to eq({ "act" => { "name" => "Cable Ties" } })
    end
  end

  describe "errors" do
    it "raises with the api's message" do
      stub_request(:get, "https://api.example.test/v1/admin/acts")
        .to_return(status: 401, body: '{"error":"Provide an admin API token."}',
                   headers: { "Content-Type" => "application/json" })

      expect { @client.get("/v1/admin/acts") }
        .to raise_error(LmlAdmin::ApiError, "Provide an admin API token.")
    end

    it "keeps the status and the per field details from a 422" do
      stub_request(:post, "https://api.example.test/v1/admin/venues")
        .to_return(status: 422, body: '{"error":"That record is not valid.","details":{"time_zone":["invalid time zone"]}}',
                   headers: { "Content-Type" => "application/json" })

      @client.post("/v1/admin/venues", {})
    rescue LmlAdmin::ApiError => e
      expect(e.status).to eq(422)
      expect(e.details).to eq({ "time_zone" => ["invalid time zone"] })
    end

    it "copes with an error response that is not json" do
      stub_request(:get, "https://api.example.test/v1/admin/acts")
        .to_return(status: 502, body: "<html>bad gateway</html>")

      expect { @client.get("/v1/admin/acts") }.to raise_error(LmlAdmin::ApiError, /HTTP 502/)
    end
  end
end
