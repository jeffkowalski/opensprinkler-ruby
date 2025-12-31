# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.2.0'

# Web framework
gem 'puma', '~> 6.5'
gem 'roda', '~> 3.85'

# GPIO control for Raspberry Pi (only on Pi hardware)
# Install with: bundle install --with=pi
group :pi do
  gem 'lgpio', '~> 0.1'
end

# HTTP client for InfluxDB, weather, etc.
gem 'net-http'

# YAML is stdlib but explicit is good
gem 'yaml'

group :development, :test do
  gem 'rack-test', '~> 2.1'
  gem 'rspec', '~> 3.13'
  gem 'rubocop', '~> 1.69', require: false
  gem 'rubocop-rspec', require: false
end
