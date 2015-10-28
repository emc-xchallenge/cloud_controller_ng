require 'spec_helper'
require 'actions/app_update'

module VCAP::CloudController
  describe AppUpdate do
    let(:app_model) { AppModel.make(name: app_name, environment_variables: environment_variables) }
    let!(:buildpack_lifecycle_model) { BuildpackLifecycleDataModel.make(buildpack: buildpack, stack: Stack.default.name, app: app_model) }
    let(:user) { double(:user, guid: '1337') }
    let(:user_email) { 'cool_dude@hoopy_frood.com' }
    let(:app_update) { AppUpdate.new(user, user_email) }
    let(:buildpack) { 'http://original.com' }
    let(:app_name) { 'original name' }
    let(:environment_variables) { { 'original' => 'value' } }

    describe '#update' do
      let(:message) do
        AppUpdateMessage.new({
            name:                  'new name',
            environment_variables: { 'MYVAL' => 'new-val' },
          })
      end

      it 'creates an audit event' do
        expect_any_instance_of(Repositories::Runtime::AppEventRepository).to receive(:record_app_update).with(
            app_model,
            app_model.space,
            user.guid,
            user_email,
            {
              'name'                  => 'new name',
              'environment_variables' => { 'MYVAL' => 'new-val' },
            })

        app_update.update(app_model, message)
      end

      it 'updates the apps name' do
        message = AppUpdateMessage.new({ name: 'new name' })

        expect(app_model.name).to eq('original name')
        expect(app_model.environment_variables).to eq({ 'original' => 'value' })
        expect(app_model.lifecycle_data.buildpack).to eq('http://original.com')

        app_update.update(app_model, message)
        app_model.reload

        expect(app_model.name).to eq('new name')
        expect(app_model.environment_variables).to eq({ 'original' => 'value' })
        expect(app_model.lifecycle_data.buildpack).to eq('http://original.com')
      end

      it 'updates the apps environment_variables' do
        message = AppUpdateMessage.new({ environment_variables: { 'MYVAL' => 'new-val' } })

        expect(app_model.name).to eq('original name')
        expect(app_model.environment_variables).to eq({ 'original' => 'value' })
        expect(app_model.lifecycle_data.buildpack).to eq('http://original.com')

        app_update.update(app_model, message)
        app_model.reload

        expect(app_model.name).to eq('original name')
        expect(app_model.environment_variables).to eq({ 'MYVAL' => 'new-val' })
        expect(app_model.lifecycle_data.buildpack).to eq('http://original.com')
      end

      it 'updates the apps lifecycle' do
        message = AppUpdateMessage.new(
          { lifecycle: { type: 'buildpack', data: { buildpack: 'http://new-buildpack.url', stack: 'redhat' } } })

        expect(app_model.name).to eq('original name')
        expect(app_model.environment_variables).to eq({ 'original' => 'value' })
        expect(app_model.lifecycle_data.buildpack).to eq('http://original.com')
        expect(app_model.lifecycle_data.stack).to eq(Stack.default.name)

        app_update.update(app_model, message)
        app_model.reload

        expect(app_model.name).to eq('original name')
        expect(app_model.environment_variables).to eq({ 'original' => 'value' })
        expect(app_model.lifecycle_data.buildpack).to eq('http://new-buildpack.url')
        expect(app_model.lifecycle_data.stack).to eq('redhat')
      end

      context 'when the app is invalid' do
        before do
          allow(app_model).to receive(:save).and_raise(Sequel::ValidationFailed.new('something'))
        end

        it 'raises an invalid app error' do
          expect { app_update.update(app_model, message) }.to raise_error(AppUpdate::InvalidApp)
        end
      end
    end
  end
end
