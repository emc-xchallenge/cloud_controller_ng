require 'messages/base_message'
require 'messages/buildpack_lifecycle_data_message'

module VCAP::CloudController
  class AppUpdateMessage < BaseMessage
    ALLOWED_KEYS = [:name, :environment_variables, :lifecycle]

    attr_accessor(*ALLOWED_KEYS)

    validates_with NoAdditionalKeysValidator, LifecycleDataValidator
    BUILDPACK_LIFECYCLE = 'buildpack'
    LIFECYCLE_TYPES = [BUILDPACK_LIFECYCLE].map(&:freeze).freeze

    def self.lifecycle_requested?
      @lifecycle_requested ||= proc { |a| a.requested?(:lifecycle) }
    end

    validates :name, string: true, allow_nil: true
    validates :environment_variables, hash: true, allow_nil: true

    validates :lifecycle_type,
      inclusion: { in: LIFECYCLE_TYPES },
      presence: true,
      if: lifecycle_requested?,
      allow_nil: true

    validates :lifecycle_data,
      hash: true,
      allow_nil: false,
      if: lifecycle_requested?

    def initialize(*attrs)
      super
      @lifecycle ||= default_lifecycle
    end

    def requested_buildpack?
      requested?(:lifecycle) && lifecycle_type == BUILDPACK_LIFECYCLE
    end

    def data_validation_config
      OpenStruct.new(
        data_class: 'BuildpackLifecycleDataMessage',
        allow_nil: false,
        data: lifecycle_data,
      )
    end

    def self.create_from_http_request(body)
      AppUpdateMessage.new(body.symbolize_keys)
    end

    delegate :buildpack, to: :buildpack_data

    private

    def allowed_keys
      ALLOWED_KEYS
    end

    def buildpack_data
      @buildpack_data ||= BuildpackLifecycleDataMessage.new(lifecycle_data.symbolize_keys)
    end

    def lifecycle_type
      lifecycle['type'] || lifecycle[:type]
    end

    def lifecycle_data
      lifecycle['data'] || lifecycle[:data]
    end

    def default_lifecycle
      {
        type: 'buildpack',
        data: {
          stack: Stack.default.name,
          buildpack: nil
        }
      }
    end
  end
end
