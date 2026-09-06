source 'https://rubygems.org'

# Ruby CLIs required at runtime by the convertor's dependency fetchers:
#   - chef-cli / berks (berkshelf): Chef cookbook dependency resolution
#   - r10k: Puppet module/dependency resolution
# Fetched hermetically via Hermeto's bundler prefetch (Gemfile.lock), then
# exposed on PATH as bare executables via `bundle binstubs ... --path /usr/local/bin`.
gem 'chef-cli'
gem 'berkshelf'
gem 'r10k'
