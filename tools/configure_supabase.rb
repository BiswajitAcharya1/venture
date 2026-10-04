#!/usr/bin/env ruby

require "base64"
require "json"
require "uri"
require "xcodeproj"

abort "usage: ruby tools/configure_supabase.rb PROJECT_URL PUBLISHABLE_ANON_KEY" unless ARGV.length == 2

project_url = ARGV[0].strip
anon_key = ARGV[1].strip
uri = URI.parse(project_url)
abort "Supabase project URL must use HTTPS." unless uri.is_a?(URI::HTTPS) && uri.host
abort "Supabase publishable anon key is required." if anon_key.empty?
abort "Never put a Supabase service-role key in the iOS project." if anon_key.downcase.include?("service_role")

if anon_key.count(".") == 2
  payload_segment = anon_key.split(".")[1]
  padding = "=" * ((4 - payload_segment.length % 4) % 4)
  payload = JSON.parse(Base64.urlsafe_decode64(payload_segment + padding))
  abort "Never put a Supabase service-role key in the iOS project." if payload["role"] == "service_role"
end

root = File.expand_path("..", __dir__)
project_path = File.join(root, "Venture.xcodeproj")
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |candidate| candidate.name == "Venture" }
abort "Venture application target was not found." unless target

target.build_configurations.each do |configuration|
  configuration.build_settings["VENTURE_SUPABASE_URL"] = project_url
  configuration.build_settings["VENTURE_SUPABASE_ANON_KEY"] = anon_key
end

project.save
puts "Configured Supabase Auth for the Venture target."
puts "The publishable anon key is embedded in the app by design. Keep the service-role key only in Supabase."
