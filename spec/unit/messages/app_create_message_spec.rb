require 'spec_helper'
require 'messages/app_create_message'

module VCAP::CloudController
  describe AppCreateMessage do
    describe '.create_from_http_request' do
      let(:body) {
        {
          'name'                  => 'some-name',
          'environment_variables' => {
            'ENVVAR' => 'env-val'
          },
          'relationships'         => {
            'space' => { 'guid' => 'some-guid' }
          },
          'lifecycle' => {
              'type'  => 'buildpack',
              'data'  => {
                'buildpack' => 'some-buildpack',
                'stack'     => 'some-stack'
              }
          }
        }
      }

      it 'returns the correct AppCreateMessage' do
        message = AppCreateMessage.create_from_http_request(body)

        expect(message).to be_a(AppCreateMessage)
        expect(message.name).to eq('some-name')
        expect(message.space_guid).to eq('some-guid')
        expect(message.environment_variables).to eq({ 'ENVVAR' => 'env-val' })
        expect(message.relationships).to eq({ 'space' => { 'guid' => 'some-guid' } })
        expect(message.lifecycle).to eq(
            { 'type'  => 'buildpack',
              'data'  => {
                'buildpack' => 'some-buildpack',
                'stack'     => 'some-stack'
              }
            })
      end

      it 'converts requested keys to symbols' do
        message = AppCreateMessage.create_from_http_request(body)

        expect(message.requested?(:name)).to be_truthy
        expect(message.requested?(:relationships)).to be_truthy
        expect(message.requested?(:environment_variables)).to be_truthy
        expect(message.requested?(:lifecycle)).to be_truthy
      end
    end

    describe 'validations' do
      context 'when unexpected keys are requested' do
        let(:params) do
          {
            unexpected: 'foo',
            lifecycle: {
              type: 'buildpack',
              data: {
                buildpack: 'nil',
                stack: Stack.default.name
              }
            }
          }
        end
        it 'is not valid' do
          message = AppCreateMessage.new(params)

          expect(message).not_to be_valid
          expect(message.errors[:base]).to include("Unknown field(s): 'unexpected'")
        end
      end

      context 'when name is not a string' do
        let(:params) do
          {
            name: 32.77,
            lifecycle: {
              type: 'buildpack',
              data: {
                buildpack: 'nil',
                stack: Stack.default.name
              }
            }
          }
        end

        it 'is not valid' do
          message = AppCreateMessage.new(params)

          expect(message).not_to be_valid
          expect(message.errors_on(:name)).to include('must be a string')
        end
      end

      context 'when environment_variables is not a hash' do
        let(:params) do
          {
            name:                  'name',
            environment_variables: 'potato',
            relationships:         { space: { guid: 'guid' } },
            lifecycle: {
              type: 'buildpack',
              data: {
                buildpack: 'nil',
                stack: Stack.default.name
              }
            }
          }
        end

        it 'is not valid' do
          message = AppCreateMessage.new(params)

          expect(message).not_to be_valid
          expect(message.errors_on(:environment_variables)[0]).to include('must be a hash')
        end
      end

      describe 'relationships' do
        context 'when relationships is malformed' do
          let(:params) do
            {
              name: 'name',
              relationships: 'malformed shizzle',
              lifecycle: {
                type: 'buildpack',
                data: {
                  buildpack: 'nil',
                  stack: Stack.default.name
                }
              }
            }
          end

          it 'is not valid' do
            message = AppCreateMessage.new(params)

            expect(message).not_to be_valid
            expect(message.errors_on(:relationships)).to include('must be a hash')
          end
        end

        context 'when relationships is missing' do
          let(:params) do
            {
              name: 'name',
              relationships: {},
              lifecycle: {
                type: 'buildpack',
                data: {
                  buildpack: 'nil',
                  stack: Stack.default.name
                }
              }
            }
          end

          it 'is not valid' do
            message = AppCreateMessage.new(params)

            expect(message).not_to be_valid
            expect(message.errors_on(:relationships)).to include("can't be blank")
          end
        end

        context 'when space is missing' do
          let(:params) do
            {
              name: 'name',
              relationships: {},
              lifecycle: {
                type: 'buildpack',
                data: {
                  buildpack: 'nil',
                  stack: Stack.default.name
                }
              }
            }
          end

          it 'is not valid' do
            message = AppCreateMessage.new(params)

            expect(message).not_to be_valid
            expect(message.errors_on(:relationships)).to include("can't be blank")
          end
        end

        context 'when space has an invalid guid' do
          let(:params) do
            {
              name:          'name',
              relationships: { space: { guid: 32 } },
              lifecycle: {
                type: 'buildpack',
                data: {
                  buildpack: nil,
                  stack: Stack.default.name
                }
              }
            }
          end

          it 'is not valid' do
            message = AppCreateMessage.new(params)

            expect(message).not_to be_valid
            expect(message.errors_on(:relationships).any? { |e| e.include?('Space guid') }).to be(true)
          end
        end

        context 'when space is malformed' do
          let(:params) do
            {
              name:          'name',
              relationships: { space: 'asdf' },
              lifecycle: {
                type: 'buildpack',
                data: {
                  buildpack: nil,
                  stack: Stack.default.name
                }
              }
            }
          end

          it 'is not valid' do
            message = AppCreateMessage.new(params)

            expect(message).not_to be_valid
            expect(message.errors_on(:relationships).any? { |e| e.include?('Space must be structured like') }).to be(true)
          end
        end

        context 'when additional keys are present' do
          let(:params) do
            {
              name:          'name',
              relationships: {
                space: { guid: 'guid' },
                other: 'stuff'
              },
              lifecycle: {
                type: 'buildpack',
                data: {
                  buildpack: nil,
                  stack: Stack.default.name
                }
              }
            }
          end

          it 'is not valid' do
            message = AppCreateMessage.new(params)

            expect(message).not_to be_valid
            expect(message.errors[:relationships]).to include("Unknown field(s): 'other'")
          end
        end
      end

      describe 'lifecycle' do
        context 'when lifecycle data is provided' do
          context 'both a valid stack and buildpack are provided' do
            let(:valid_stack) { Stack.make(name: 'some-other-valid-stack') }
            let(:params) do
              {
                name: 'some_name',
                relationships: { space: { guid: 'some-guid' } },
                lifecycle: {
                  type: 'buildpack',
                  data: {
                    buildpack: 'java',
                    stack: valid_stack.name
                  }
                }
              }
            end

            it 'uses the specified values' do
              message = AppCreateMessage.new(params)
              expect(message).to be_valid
              expect(message.buildpack).to eq('java')
              expect(message.stack).to eq(valid_stack.name)
            end
          end

          context 'invalid stack and buildpack' do
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
              message = AppCreateMessage.new(params)
              expect(message).not_to be_valid
              expect(message.errors_on(:lifecycle)).to include('Buildpack must be a string')
            end

            it 'must provide a valid stack name' do
              message = AppCreateMessage.new(params)
              expect(message).not_to be_valid
              expect(message.errors_on(:lifecycle)).to include('Stack is invalid')
            end
          end
        end

        describe 'lifecycle type validations' do
          context 'when lifecycle type is not a valid type' do
            let(:params) do
              { lifecycle: { data: {}, type: { subhash: 'woah!' } } }
            end

            it 'is not valid' do
              message = AppCreateMessage.new(params)

              expect(message).not_to be_valid
              expect(message.errors_on(:lifecycle_type)).to include('is invalid')
            end
          end

          context 'when lifecycle type is not provided' do
            let(:params) do
              { lifecycle: { data: {} } }
            end

            it 'is not valid' do
              message = AppCreateMessage.new(params)

              expect(message).not_to be_valid
              expect(message.errors_on(:lifecycle_type)).to include("can't be blank")
            end
          end
        end
      end
    end
  end
end
