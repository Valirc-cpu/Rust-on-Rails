ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
ENV["VIPS_WARNING"] ||= "0"
ENV["G_MESSAGES_DEBUG"] ||= "none"

$stdout.sync = true
$stderr.sync = true

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
