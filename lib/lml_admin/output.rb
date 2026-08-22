# frozen_string_literal: true

require "json"

module LmlAdmin
  # Human readable by default, --json when something else is going to read it.
  class Output
    def initialize(io: $stdout, json: false)
      @io = io
      @json = json
    end

    def json?
      @json
    end

    def collection(records, meta, columns)
      return dump({ records: records, meta: meta }) if json?

      table(records, columns)
      @io.puts
      @io.puts "page #{meta['page']} of #{pages(meta)} - #{meta['total']} in total"
    end

    def record(record)
      return dump(record) if json?

      width = record.keys.map(&:length).max
      record.each do |key, value|
        @io.puts "#{key.to_s.ljust(width)}  #{present(value)}"
      end
    end

    def error(message, details = nil)
      @io.puts message
      return if details.nil? || details.empty?

      details.each { |field, messages| @io.puts "  #{field}: #{Array(messages).join(', ')}" }
    end

    def puts(message)
      @io.puts message
    end

    private

    def dump(payload)
      @io.puts JSON.pretty_generate(payload)
    end

    def pages(meta)
      per_page = meta["per_page"].to_i
      return 1 if per_page.zero?

      [(meta["total"].to_f / per_page).ceil, 1].max
    end

    def table(records, columns)
      rows = records.map { |record| columns.map { |column| present(record[column.to_s]) } }
      headers = columns.map { |column| column.to_s.upcase }
      widths = headers.each_with_index.map do |header, index|
        ([header.length] + rows.map { |row| row[index].length }).max
      end

      @io.puts format_row(headers, widths)
      rows.each { |row| @io.puts format_row(row, widths) }
    end

    def format_row(cells, widths)
      cells.each_with_index.map { |cell, index| cell.ljust(widths[index]) }.join("  ").rstrip
    end

    def present(value)
      case value
      when nil then "-"
      when Array then value.empty? ? "-" : value.join(", ")
      when Hash then value.reject { |_, v| v.nil? }.map { |k, v| "#{k}=#{v}" }.join(" ").then { |s| s.empty? ? "-" : s }
      else value.to_s
      end
    end
  end
end
