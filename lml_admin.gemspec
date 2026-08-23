# frozen_string_literal: true

require_relative "lib/lml_admin/version"

Gem::Specification.new do |spec|
  spec.name = "lml_admin"
  spec.version = LmlAdmin::VERSION
  spec.authors = ["Mark Ryall"]
  spec.email = ["mark@ryall.name"]

  spec.summary = "Command line client for the Live Music Locator admin API"
  spec.description = <<~DESCRIPTION
    A command line client for the Live Music Locator admin API - list, show,
    create and update venues and acts, and upload gigs in clipper format.
    Stdlib only at runtime, so it also serves as a worked example of what the
    API expects from an integration.
  DESCRIPTION
  spec.homepage = "https://github.com/livemusiclocator/lml-admin-cli"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ spec/ .git .rspec Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
