require "spec_helper"

describe OracleImportsController do
  let(:user) { users(:owner) }

  describe "#create" do
    before do
      log_in user

      stub(ChorusConfig.instance).public_url { host_url }
      stub(ChorusConfig.instance).server_port { server_port }
    end

    let(:schema) { schemas(:default) }
    let(:table_name) { "foo" }
    let(:executor) { Object.new }
    let(:host_url) { "test.example.com"}
    let(:server_port) { 1234 }

    let(:exec_options) { {
      :user => user,
      :schema => schema,
      :url => "http://#{host_url}:#{server_port}/oracle_pipes",
      :table_name => table_name
    } }

    it "runs an oracle executor" do
      @request.host = host_url
      mock(OracleImportExecutor).new(exec_options) { executor }
      mock(executor).run
      post :create, :schema_id => schema.id, :table_name => table_name
    end
  end
end

