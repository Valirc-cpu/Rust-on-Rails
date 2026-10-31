ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
ENV["VIPS_WARNING"] ||= "0"
ENV["G_MESSAGES_DEBUG"] ||= "none"

# Ensure user gems and cargo are available in PATH
user_gem_bin = "#{ENV['HOME']}/.local/share/gem/ruby/3.4.0/bin"
ENV["PATH"] = "#{user_gem_bin}:#{ENV['HOME']}/.local/bin:#{ENV['HOME']}/.cargo/bin:#{ENV['PATH']}"

$stdout.sync = true
$stderr.sync = true

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
