require 'spec_helper'
require 'messages/app_update_message'

module VCAP::CloudController
  describe AppUpdateMessage do
    let(:app) do
      instance_double(VCAP::CloudController::AppModel,
        lifecycle_type: BuildpackLifecycleDataModel::LIFECYCLE_TYPE)
    end

    let(:params_with_app) { params.merge(app: app) }

    describe '.create_from_http_request' do
      let(:body) {
        {
          'name' => 'some-name',
          'lifecycle' => {
            'type' => 'buildpack',
            'data' => {
              'buildpack' => 'some-buildpack',
              'stack' => 'some-stack'
            }
          },
          'environment_variables' => {
            'ENVVAR' => 'env-val'
          }
        }
      }

      it 'returns the correct AppUpdateMessage' do
        message = AppUpdateMessage.create_from_http_request(body, app)

        expect(message).to be_a(AppUpdateMessage)
        expect(message.name).to eq('some-name')
        expect(message.lifecycle['data']['buildpack']).to eq('some-buildpack')
        expect(message.lifecycle['data']['stack']).to eq('some-stack')
        expect(message.environment_variables).to eq({ 'ENVVAR' => 'env-val' })
      end

      it 'converts requested keys to symbols' do
        message = AppUpdateMessage.create_from_http_request(body, app)

        expect(message.requested?(:name)).to be_truthy
        expect(message.requested?(:lifecycle)).to be_truthy
        expect(message.requested?(:environment_variables)).to be_truthy
      end
    end

    describe 'validations' do
      context 'when unexpected keys are requested' do
        let(:params) { { unexpected: 'foo' } }

        it 'is not valid' do
          message = AppUpdateMessage.new(params_with_app)

          expect(message).not_to be_valid
          expect(message.errors[:base]).to include("Unknown field(s): 'unexpected'")
        end
      end

      context 'when name is not a string' do
        let(:params) { { name: 32.77 } }

        it 'is not valid' do
          message = AppUpdateMessage.new(params_with_app)

          expect(message).not_to be_valid
          expect(message.errors_on(:name)).to include('must be a string')
        end
      end

      context 'when environment_variables is not a hash' do
        let(:params) { { environment_variables: 'potato' } }

        it 'is not valid' do
          message = AppUpdateMessage.new(params_with_app)

          expect(message).not_to be_valid
          expect(message.errors_on(:environment_variables)[0]).to include('must be a hash')
        end
      end

      describe 'lifecycle' do
        context 'when lifecycle is provided' do
          let(:params) do
            {
              name: 'some_name',
              lifecycle: {
                type: 'buildpack',
                data: {
                  buildpack: 'java',
                  stack: 'cflinuxfs2'
                }
              }
            }
          end

          it 'is valid' do
            message = AppUpdateMessage.new(params_with_app)
            expect(message).to be_valid
          end
        end

        context 'when lifecycle data is provided' do
          let(:params) do
            {
              lifecycle: {
                type: 'buildpack',
                data: {
                  buildpack: 123,
                  stack: 'fake-stack'
                }
              }
            }
          end

          it 'must provide a valid buildpack value' do
            message = AppUpdateMessage.new(params_with_app)
            expect(message).not_to be_valid
            expect(message.errors_on(:lifecycle)).to include('Buildpack must be a string')
          end

          it 'must provide a valid stack name' do
            message = AppUpdateMessage.new(params_with_app)
            expect(message).not_to be_valid
            expect(message.errors_on(:lifecycle)).to include('Stack must exist in our DB')
          end
        end

        context 'when data is not provided' do
          let(:params) do { lifecycle: { type: 'buildpack' } } end

          it 'is not valid' do
            message = AppUpdateMessage.new(params_with_app)
            expect(message).not_to be_valid
            expect(message.errors_on(:lifecycle_data)).to include('must be a hash')
            expect(message.errors[:lifecycle]).to include('data must be present')
          end
        end

        context 'when lifecycle is not provided' do
          let(:params) do
            {
              name: 'some_name',
            }
          end

          it 'does not supply defaults' do
            message = AppUpdateMessage.new(params_with_app)
            expect(message).to be_valid
            expect(message.lifecycle).to eq(nil)
          end
        end

        context 'when provided lifecycle type differs from app lifecycle type'do
          let(:params) do
            {
              lifecycle: {
                type: 'not-buildpack',
                data: {}
              }
            }
          end

          it 'raises an error' do
            message = AppUpdateMessage.new(params_with_app)
            expect(message).to_not be_valid

            expect(message.errors_on(:lifecycle_type)).to include('type cannot be changed')
          end
        end

        context 'when lifecycle type is not provided' do
          let(:params) do
            {
              lifecycle: {
                data: {}
              }
            }
          end

          it 'raises an error' do
            message = AppUpdateMessage.new(params_with_app)
            expect(message).to_not be_valid

            expect(message.errors_on(:lifecycle_type)).to include("can't be blank")
          end
        end
      end
    end
  end
end
