# frozen_string_literal: true

require "webmock/rspec"
require "lml_admin"

RSpec.configure do |config|
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }

  # Nothing in here should read the developer's real token or hit the real API.
  config.before do
    ENV["LML_ADMIN_TOKEN"] = "lml_admin_testtoken"
    ENV["LML_API_URL"] = "https://api.example.test"
    ENV.delete("LML_ALLOW_INSECURE")
  end
end
