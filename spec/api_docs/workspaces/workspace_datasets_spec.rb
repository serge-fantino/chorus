require 'spec_helper'

resource "Workspaces" do
  let(:user) { users(:owner) }
  let(:gpdb_table) { datasets(:source_table) }
  let(:workspace) { workspaces(:public) }
  let(:workspace_id) { workspace.id }
  let(:id) { gpdb_table.id }

  before do
    log_in user
    stub(Dataset).refresh.with_any_args { |account, schema, options| schema.datasets }
    stub(Dataset).total_entries.with_any_args { |account, schema, options| schema.datasets.count }
  end

  get "/workspaces/:workspace_id/datasets" do
    parameter :workspace_id, "Id of a workspace"
    parameter :type, "Specific type of datasets (SANDBOX_TABLE, SANDBOX_DATASET, CHORUS_VIEW, SOURCE_TABLE, NON_CHORUS_VIEW)"
    parameter :database_id, "Id of a database (Results will be scoped to this database)"

    required_parameters :workspace_id
    pagination

    example_request "Get a list of datasets associated with a workspace" do
      status.should == 200
    end
  end

  get "/workspaces/:workspace_id/datasets/:id" do
    before do
      any_instance_of(GpdbTable) do |table|
        stub(table).verify_in_source { true }
      end
      any_instance_of(GpdbSchema) do |schema|
        stub(schema).verify_in_source { true }
      end
    end

    parameter :workspace_id, "Id of a workspace"
    parameter :id, "Id of a dataset"

    required_parameters :workspace_id, :id

    let(:id) { datasets(:table).id }

    example_request "Get details for a dataset" do
      status.should == 200
    end
  end

  post "/workspaces/:workspace_id/datasets" do
    parameter :workspace_id, "Id of the workspace with which to associate the datasets"
    parameter :'dataset_ids[]', "Dataset Id to associate with the workspace, can be specified multiple times"

    required_parameters :workspace_id, :'dataset_ids[]'

    before do
      workspace.sandbox = schemas(:searchquery_schema)
      workspace.save
    end

    let(:view) { datasets(:view) }
    let(:table) { datasets(:table) }

    example "Associate a list of non-sandbox datasets with the workspace" do
      do_request(:dataset_ids => [table.to_param, view.to_param])
      status.should == 201
    end
  end

  delete "/workspaces/:workspace_id/datasets/:id" do
    parameter :workspace_id, "Id of a workspace"
    parameter :id, "Id of a dataset to be disassociated with the workspace"

    required_parameters :workspace_id, :id
    example_request "Disassociate a non-sandbox dataset from a workspace" do
      status.should == 200
    end
  end
end
