# frozen_string_literal: true

module LmlAdmin
  # What the API will accept for each resource, and how to turn a command line
  # flag into the right JSON type.
  #
  # These lists mirror the WRITABLE allowlists in the API's controllers. If the
  # API grows a field, add it here - anything not listed is dropped by the API
  # anyway, so a stale list here fails quietly rather than dangerously.
  class Resource
    FIELD_TYPES = {
      venues: {
        name: :string, location: :string, address: :string, time_zone: :string,
        capacity: :integer, vibe: :string, notes: :string, lga: :string, email: :string,
        phone: :string, postcode: :string, website: :string, location_url: :string,
        facebook_url: :string, instagram_url: :string,
        latitude: :float, longitude: :float, tags: :list
      }.freeze,
      acts: {
        name: :string, country: :string, location: :string, email: :string,
        website: :string, genres: :list, aliases: :list,
        bandcamp: :string, facebook: :string, instagram: :string, linktree: :string,
        musicbrainz: :string, rym: :string, spotify: :string, wikipedia: :string,
        youtube: :string
      }.freeze,
      # Gigs have no writable fields because the API will not write one. They are
      # created by posting clipper content to uploads, which is the only path
      # that knows how to match an entry against a gig we already hold.
      gigs: {}.freeze,
    }.freeze

    # What each resource will answer to. Anything not listed here is a usage
    # error before a request is made, so `lml gigs update` cannot get as far as
    # a confusing 404.
    ACTIONS = {
      venues: %w[list show create update].freeze,
      acts: %w[list show create update].freeze,
      gigs: %w[list show clipper].freeze,
    }.freeze

    # The filters `list` understands on top of --page and --per-page. Gigs are
    # filtered rather than searched: the endpoint deliberately has no `q`,
    # because Gig.search forces `visible` and this endpoint must show drafts.
    LIST_FILTERS = {
      venues: %i[q].freeze,
      acts: %i[q].freeze,
      gigs: %i[venue_id date_from date_to].freeze,
    }.freeze

    # The columns a `list` prints. Everything is in --json if you want the rest.
    # A dotted column reaches into a nested object - see Output#table.
    COLUMNS = {
      venues: %i[id name location capacity],
      acts: %i[id name country location],
      gigs: ["date", "start_time", "name", "status", "venue.name", "id"].freeze,
    }.freeze

    NAMES = FIELD_TYPES.keys.map(&:to_s).freeze

    def self.find(name)
      raise ArgumentError, "Unknown resource #{name}. Try one of: #{NAMES.join(', ')}" unless NAMES.include?(name)

      new(name)
    end

    attr_reader :plural

    def initialize(plural)
      @plural = plural
    end

    def singular
      plural.chomp("s")
    end

    def fields
      FIELD_TYPES.fetch(plural.to_sym)
    end

    def columns
      COLUMNS.fetch(plural.to_sym)
    end

    def actions
      ACTIONS.fetch(plural.to_sym)
    end

    def list_filters
      LIST_FILTERS.fetch(plural.to_sym)
    end

    def clipper_path
      "#{collection_path}/clipper"
    end

    def collection_path
      "/v1/admin/#{plural}"
    end

    def member_path(id)
      "#{collection_path}/#{id}"
    end

    # `--capacity 350` arrives as the string "350"; the API wants a number.
    def coerce(field, value)
      case fields.fetch(field)
      when :integer then Integer(value, exception: false)
      when :float then Float(value, exception: false)
      when :list then value.to_s.split(",").map(&:strip).reject(&:empty?)
      else value
      end
    end

    def flag_for(field)
      "--#{field.to_s.tr('_', '-')}"
    end

    def field_for(flag)
      fields.keys.find { |field| flag_for(field) == flag }
    end
  end
end
