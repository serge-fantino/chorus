require 'spec_helper'

resource "Workfiles" do
  let(:owner) { users(:owner) }
  let!(:workspace) { workspaces(:public) }
  let!(:workfile) { workfiles("sql.sql") }
  let!(:file) { test_file("workfile.sql", "text/sql") }
  let!(:workfile_id) { workfile.to_param }
  let(:result) { }

  before do
    log_in owner
    stub(SqlExecutor).execute_sql.with_any_args { result }
    stub(SqlExecutor).cancel_query.with_any_args { }
  end

  get "/workfiles/:id" do
    parameter :id, "Id of a workfile"

    required_parameters :id

    let(:id) { workfile.to_param }

    example_request "Get workfile details" do
      status.should == 200
    end
  end

  put "/workfiles/:id" do
    parameter :id, "Id of a workfile"
    parameter :"execution_schema[id]", "Id of the execution schema"

    required_parameters :id

    let(:id) { workfile.to_param }
    let(:"execution_schema[id]") { schemas(:default).to_param }

    example_request "Update a workfile" do
      status.should == 200
    end
  end

  get "/workfiles/:workfile_id/download" do
    before do
      workfile_versions(:public).tap { |v| v.contents = file; v.save! }
    end

    parameter :workfile_id, "Id of a workfile to download"

    required_parameters :workfile_id

    let(:workspace_id) { workspace.to_param }

    example_request "Download the current version of the file" do
      status.should == 200
    end
  end

  post "/workfiles/:workfile_id/copy" do
    before do
      workfile_versions(:public).tap { |v| v.contents = file; v.save! }
    end

    parameter :workfile_id, "Id of a workfile to copy"
    parameter :workspace_id, "Id of workspace to copy to"

    required_parameters :workfile_id, :workspace_id

    let(:workspace_id) { workspace.to_param }

    example_request "Copy a workfile to a workspace" do
      status.should == 201
    end
  end

  delete "/workfiles/:id" do
    let(:id) { workfile.to_param }
    parameter :id, "Id of the workfile to delete"
    required_parameters :id

    example_request "Delete a workfile" do
      status.should == 200
    end
  end

  get "/workspaces/:workspace_id/workfiles" do
    parameter :workspace_id, "Workspace Id"

    required_parameters :workspace_id

    let(:workspace_id) { workspace.to_param }
    pagination

    example_request "Get a list of workfiles in a workspace" do
      status.should == 200
    end
  end

  post "/workspaces/:workspace_id/workfiles" do
    let(:workspace_id) { workspace.to_param }

    parameter :type, ""
    parameter :alpine_id, "1"
    parameter :workspace_id, "Workspace Id"
    parameter :description, "Workfile description"
    parameter :file_name, "Filename"

    required_parameters :file_name, :workspace_id

    let(:description) { "Get off my lawn, you darn kids!" }
    let(:file_name) { workfile.file_name }

    example_request "Create a new workfile in a workspace" do
      status.should == 201
    end
  end

  post "/workfiles/:workfile_id/executions" do
    parameter :workfile_id, "Workfile Id"
    parameter :check_id, "A client-generated identifier which can be used to cancel this execution later"
    parameter :sql, "SQL to execute"

    required_parameters :workfile_id, :check_id

    let(:check_id) { "12345" }

    let(:result) do
      SqlResult.new.tap do |r|
        r.add_column("results_of", "your_sql")
      end
    end

    example_request "Execute a workfile" do
      status.should == 200
    end
  end

  delete "/workfiles/:workfile_id/executions/:id" do
    parameter :workfile_id, "Workfile Id"
    parameter :id, "A client-generated identifier, previously passed as 'check_id' to workfile execution method to identify a query"

    required_parameters :id, :workfile_id

    let(:id) { 0 }

    example_request "Cancel execution of a workfile" do
      status.should == 200
    end
  end
end
