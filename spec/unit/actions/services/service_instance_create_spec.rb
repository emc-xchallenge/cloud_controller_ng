require 'spec_helper'
require 'actions/services/service_instance_create'

module VCAP::CloudController
  describe ServiceInstanceCreate do
    let(:event_repository) { double(:event_repository, record_service_instance_event: nil) }
    let(:logger) { double(:logger) }
    subject(:create_action) { ServiceInstanceCreate.new(event_repository, logger) }

    describe '#create' do
      let(:space) { Space.make }
      let(:service_plan) { ServicePlan.make }
      let(:request_attrs) do
        {
            'space_guid' => space.guid,
            'service_plan_guid' => service_plan.guid,
            'name' => 'my-instance',
            'dashboard_url' => 'test-dashboardurl.com'
        }
      end

      before do
        stub_provision(service_plan.service.service_broker)
      end

      it 'creates the service instance with the requested params' do
        expect {
          create_action.create(request_attrs, false)
        }.to change { ServiceInstance.count }.from(0).to(1)
        service_instance = ServiceInstance.where(name: 'my-instance').first
        expect(service_instance.credentials).to eq({})
        expect(service_instance.space.guid).to eq(space.guid)
        expect(service_instance.service_plan.guid).to eq(service_plan.guid)
      end

      it 'creates a new service instance operation' do
        create_action.create(request_attrs, false)
        expect(ManagedServiceInstance.last.last_operation).to eq(ServiceInstanceOperation.last)
      end

      it 'creates an audit event' do
        create_action.create(request_attrs, false)
        expect(event_repository).to have_received(:record_service_instance_event).with(:create, an_instance_of(ManagedServiceInstance), request_attrs)
      end

      context 'when the service instance create returns dashboard client credentials' do
        let(:body) do
          {
            dashboard_url: 'http://example-dashboard.com/9189kdfsk0vfnku',
            dashboard_client: {
              id: 'client-id-1',
              secret: 'secret-1',
              redirect_uri: 'https://dashboard.service.com'
            }
          }.to_json
        end
        let(:client_manager) { instance_double(VCAP::Services::SSO::DashboardClientManager) }

        before do
          stub_provision(service_plan.service.service_broker, body: body)
          allow(client_manager).to receive(:add_client_for_instance)
          allow(VCAP::Services::SSO::DashboardClientManager).to receive(:new).and_return(client_manager)
        end

        it 'creates a new UAA dashboard client' do
          create_action.create(request_attrs, false)

          expect(VCAP::Services::SSO::DashboardClientManager).to have_received(:new).with(
            anything,
            event_repository,
            VCAP::CloudController::ServiceInstanceDashboardClient
          )
          expect(client_manager).to have_received(:add_client_for_instance).with(hash_including({
            'id' => 'client-id-1',
            'secret' => 'secret-1',
            'redirect_uri' => 'https://dashboard.service.com'
          }))
        end
      end

      context 'when there are arbitrary params' do
        let(:parameters) { { 'some-param' => 'some-value' } }
        let(:request_attrs) do
          {
              'space_guid' => space.guid,
              'service_plan_guid' => service_plan.guid,
              'name' => 'my-instance',
              'parameters' => parameters
          }
        end

        it 'passes the params to the client' do
          create_action.create(request_attrs, false)
          expect(a_request(:put, /.*/).with(body: hash_including({ parameters: parameters }))).to have_been_made
        end
      end

      context 'with accepts_incomplete' do

        before do
          stub_provision(service_plan.service.service_broker, accepts_incomplete: true, status: 202)
        end

        it 'enqueues a fetch job' do
          expect {
            create_action.create(request_attrs, true)
          }.to change { Delayed::Job.count }.from(0).to(1)

          expect(Delayed::Job.first).to be_a_fully_wrapped_job_of Jobs::Services::ServiceInstanceStateFetch
        end

        it 'does not log an audit event' do
          create_action.create(request_attrs, true)
          expect(event_repository).not_to have_received(:record_service_instance_event)
        end

        context 'when the service instance create returns dashboard client credentials' do
          let(:body) do
            {
              dashboard_url: 'http://example-dashboard.com/9189kdfsk0vfnku',
              dashboard_client: {
                id: 'client-id-1',
                secret: 'secret-1',
                redirect_uri: 'https://dashboard.service.com'
              }
            }.to_json
          end
          let(:client_manager) { instance_double(VCAP::Services::SSO::DashboardClientManager) }

          before do
            stub_provision(service_plan.service.service_broker, body: body)
            allow(client_manager).to receive(:add_client_for_instance)
            allow(VCAP::Services::SSO::DashboardClientManager).to receive(:new).and_return(client_manager)
          end

          it 'creates a new UAA dashboard client' do
            create_action.create(request_attrs, false)

            expect(VCAP::Services::SSO::DashboardClientManager).to have_received(:new).with(
              anything,
              event_repository,
              VCAP::CloudController::ServiceInstanceDashboardClient
            )
            expect(client_manager).to have_received(:add_client_for_instance).with(hash_including({
              'id' => 'client-id-1',
              'secret' => 'secret-1',
              'redirect_uri' => 'https://dashboard.service.com'
            }))
          end
        end

      end

      context 'when the instance fails to save to the db' do
        let(:mock_orphan_mitigator) { double(:mock_orphan_mitigator, attempt_deprovision_instance: nil) }
        before do
          allow(SynchronousOrphanMitigate).to receive(:new).and_return(mock_orphan_mitigator)
          allow_any_instance_of(ManagedServiceInstance).to receive(:save).and_raise
          allow(logger).to receive(:error)
        end

        it 'attempts synchronous orphan mitigation' do
          expect {
            create_action.create(request_attrs, false)
          }.to raise_error
          expect(mock_orphan_mitigator).to have_received(:attempt_deprovision_instance)
        end

        it 'logs that it was unable to save' do
          create_action.create(request_attrs, false) rescue nil

          expect(logger).to have_received(:error).with /Failed to save/
        end
      end
    end
  end
end
