source 'https://www.rubygems.org'

gem 'sinatra'
gem 'tilt', '~> 1.4.1'
gem 'tilt-jbuilder', require: 'sinatra/jbuilder'

gem 'jbuilder', '2.0.6'
gem 'endpoint_base', github: 'spree/endpoint_base'

#gem 'netsuite', github: 'huoxito/netsuite', branch: 'fix-customer-field-refs'
gem 'netsuite', path: '/home/ruby_user/SoftwareDev/railsdog/netsuite'

gem 'honeybadger'


group :development do
  gem "rake"
  gem "pry"
end

group :test do
  gem 'vcr'
  gem 'rspec', '~> 2.14'
  gem 'rack-test'
  gem 'webmock'
  gem 'teamcity-ruby-client'
  gem 'dotenv'
end

group :production do
  gem 'foreman'
  gem 'unicorn'
end
