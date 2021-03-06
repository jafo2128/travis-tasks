$:.unshift(File.expand_path('..', File.dirname(__FILE__)))

require 'bundler/setup'
require 'gh'
require 'roadie'
require 'roadie/action_mailer_extensions'
require 'ostruct'
require 'metriks/librato_metrics_reporter'
require 'travis/tasks/error_handler'
require 'travis/support'
require 'travis/tasks/config'
require 'travis/task'
require 'travis/addons'
require 'travis/tasks/middleware/metriks'
require 'travis/tasks/middleware/logging'
require 'unlimited-jce-policy-jdk7'

$stdout.sync = true

if Travis.config.sentry.dsn
  require 'raven'
  Raven.configure do |config|
    config.dsn = Travis.config.sentry.dsn

    config.current_environment = Travis.env
    config.environments = ["staging", "production"]
  end
end

Sidekiq.configure_server do |config|
  config.redis = {
    :url       => Travis.config.redis.url,
    :namespace => Travis.config.sidekiq.namespace
  }
  config.server_middleware do |chain|
    chain.add Travis::Tasks::Middleware::Metriks
    chain.add Travis::Tasks::Middleware::Logging

    if defined?(::Raven::Sidekiq)
      chain.remove(::Raven::Sidekiq)
    end

    chain.remove(Sidekiq::Middleware::Server::Logging)
    chain.add(Travis::Tasks::ErrorHandler)
  end
end

GH.set(
  client_id:      Travis.config.oauth2.try(:client_id),
  client_secret:  Travis.config.oauth2.try(:client_secret),
  origin:         Travis.config.host,
  api_url:        Travis.config.github.api_url,
  ssl:            Travis.config.ssl.merge(Travis.config.github.ssl || {}).to_hash.compact,
  user_agent:     "Travis-CI GH/#{GH::VERSION}"
)

module Roadie
  def self.app
    @_config ||= OpenStruct.new(roadie: OpenStruct.new(enabled: true, provider: nil, after_inlining: nil))
    @_application ||= OpenStruct.new(config: @_config, root: Pathname.new(Dir.pwd))
  end
end

ActiveSupport.on_load(:action_mailer) do
  include Roadie::ActionMailerExtensions
end

if Travis.config.sentry
  Travis::Exceptions::Reporter.start
end

Travis::Metrics.setup
Travis::Addons::Email.setup


%w(AES DES RC2 RSA).each do |cipher|
  puts "Maximum allowed key length for #{cipher}: #{javax.crypto::Cipher.getMaxAllowedKeyLength(cipher)}"
end
