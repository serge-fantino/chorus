require 'spec_helper'

describe WorkfilesController do
  let(:user) { users(:owner) }
  let(:admin) { users(:admin) }
  let(:member) { users(:the_collaborator) }
  let(:non_member) { users(:no_collaborators) }
  let(:workspace) { workspaces(:public) }
  let(:private_workspace) { workspaces(:private) }
  let(:private_workfile) { workfiles(:private) }
  let(:public_workfile) { workfiles(:public) }
  let(:file) { test_file("workfile.sql", "text/sql") }

  before do
    log_in user
  end

  describe "#index" do
    it "responds with a success" do
      get :index, :workspace_id => workspace.id
      response.code.should == "200"
    end

    it "sorts by file name by default" do
      get :index, :workspace_id => workspace.id
      names = decoded_response.map { |file| file.name }
      names.should == names.sort
    end

    it "sorts by last updated " do
      get :index, :workspace_id => workspace.id, :order => "date"
      timestamps = decoded_response.map { |file| file.updated_at }
      timestamps.should == timestamps.sort
    end

    it "sorts by Workfile name " do
      get :index, :workspace_id => workspace.id, :order => "file_name"
      names = decoded_response.map { |file| file.name }
      names.should == names.sort
    end

    context "with file types" do
      it "filters by file type: sql" do
        get :index, :workspace_id => workspace.id, :order => "file_name", :file_type => "sql"
        response.code.should == "200"
        decoded_response.length.should == 3
      end

      it "filters by file type: code" do
        get :index, :workspace_id => workspace.id, :order => "file_name", :file_type => "code"
        response.code.should == "200"
        decoded_response.length.should == 1
      end
    end

    describe "pagination" do
      let(:sorted_workfiles) { workspace.workfiles.sort_by!{|wf| wf.file_name.downcase } }

      it "defaults the per_page to fifty" do
        get :index, :workspace_id => workspace.id
        decoded_response.length.should == sorted_workfiles.length
        request.params[:per_page].should == 50
      end

      it "paginates the collection" do
        get :index, :workspace_id => workspace.id, :page => 1, :per_page => 2
        decoded_response.length.should == 2
      end

      it "defaults to page one" do
        get :index, :workspace_id => workspace.id, :per_page => 2
        decoded_response.length.should == 2
        decoded_response.first.id.should == sorted_workfiles.first.id
      end

      it "accepts a page parameter" do
        get :index, :workspace_id => workspace.id, :page => 2, :per_page => 2
        decoded_response.length.should == 2
        decoded_response.first.id.should == sorted_workfiles[2].id
        decoded_response.last.id.should == sorted_workfiles[3].id
      end
    end

    generate_fixture "workfileSet.json" do
      get :index, :workspace_id => workspace.id
    end
  end

  describe "#show" do
    context "for a private workspace" do
      context "as a workspace member" do
        before do
          private_workspace.members << member
          log_in member
        end

        it "responds with a success" do
          get :show, {:id => private_workfile}
          response.should be_success
        end

        it "presents the latest version of a workfile" do
          mock_present do |model, _, options|
            model.should == private_workfile
            options[:contents].should be_present
            options[:workfile_as_latest_version].should be_true
          end

          get :show, {:id => private_workfile}
        end
      end

      context "as a non-member" do
        it "responds with unsuccessful" do
          log_in non_member
          get :show, {:id => private_workfile}
          response.should_not be_success
        end
      end
    end

    context "for a public workspace" do
      before do
        log_in non_member
      end

      it "responds with a success" do
        get :show, {:id => public_workfile}
        response.should be_success
      end
    end

    describe "jasmine fixtures" do
      before do
        log_in admin
      end

      def self.generate_workfile_fixture(fixture_name, json_filename)
        generate_fixture "workfile/#{json_filename}" do
          fixture = workfiles(fixture_name)
          get :show, :id => fixture.id
        end
      end

      generate_workfile_fixture(:"sql.sql", "sql.json")
      generate_workfile_fixture(:"text.txt", "text.json")
      generate_workfile_fixture(:"image.png", "image.json")
      generate_workfile_fixture(:"binary.tar.gz", "binary.json")
      generate_workfile_fixture(:"tableau", "tableau.json")
      generate_workfile_fixture(:"alpine.afm", "alpine.json")
    end
  end

  describe "#create" do
    let(:params) { {
      :workspace_id => workspace.to_param,
      :description => "Nice workfile, good workfile, I've always wanted a workfile like you",
          :versions_attributes => [{:contents => file}]
    } }

    it_behaves_like "an action that requires authentication", :post, :create, :workspace_id => '-1'

    it 'creates a workfile' do
      post :create, params
      Workfile.last.file_name.should == 'workfile.sql'
    end

    it 'sets has_added_workfile on the workspace to true' do
      post :create, params
      workspace.reload.has_added_workfile.should be_true
    end

    it 'makes a WorkfileCreated event' do
      expect {
        post :create, params
      }.to change(Events::WorkfileCreated, :count).by(1)
      event = Events::WorkfileCreated.by(user).last
      event.workfile.description.should == params[:description]
      event.additional_data['commit_message'].should == params[:description]
      event.workspace.should == workspace
    end

    it 'creates a workfile from an svg document' do
      expect {
        post :create, :workspace_id => workspace.to_param, :file_name => 'some_vis.png', :svg_data => '<svg xmlns="http://www.w3.org/2000/svg"></svg>'
      }.to change(Workfile, :count).by(1)
      Workfile.last.file_name.should == 'some_vis.png'
    end

    context 'when creating a new workfile with an invalid name' do
      it 'returns an unprocessable entity response code' do
        post :create, :workspace_id => workspace.to_param, :file_name => 'a/file.sql'
        response.code.should == "422"
      end
    end

    context 'when uploading a workfile with an invalid name' do
      let(:file) { test_file '@invalid' }

      it 'returns 422' do
        post :create, params
        response.code.should == '422'
      end
    end

    context 'when type is alpine' do
      let(:params) do
        {
            :type => 'alpine',
            :workspace_id => workspace.to_param,
            :file_name => 'something',
            :alpine_id => '42'
        }
      end

      it 'creates an AlpineWorkfile' do
        mock_present do |model|
          model.should be_a AlpineWorkfile
          model.file_name.should == 'something'
          model.additional_data['alpine_id'].should == '42'
          model.workspace.should == workspace
        end
        post :create, params
      end
    end
  end

  describe "#update" do
    let(:schema) { schemas(:default) }
    let(:options) do
      {
          :id => public_workfile.to_param,
          :execution_schema => { :id => schema.to_param }
      }
    end

    it "uses authorization" do
      mock(controller).authorize!(:can_edit_sub_objects, public_workfile.workspace)
      put :update, options
    end

    it "updates the schema of workfile" do
      put :update, options
      response.should be_success
      decoded_response[:execution_schema][:id].should == schema.id
      public_workfile.reload.execution_schema.should == schema
    end

    context "when no execution schema has been set" do
      let(:options) do
        {
            :id => public_workfile.to_param
        }
      end

      it "does not throw an error" do
        put :update, options
        response.should be_success
      end
    end

    context "as a user who is not a workspace member" do
      let(:user) { users(:not_a_member) }
      let(:schema) { schemas(:other_schema) }
      let(:options) do
        {
            :id => private_workfile.to_param,
            :execution_schema_id => schema.to_param
        }
      end

      it "does not allow updating the workfile" do
        put :update, options
        response.should be_forbidden
        private_workfile.reload.execution_schema.should_not == schema
      end
    end
  end

  describe "#destroy" do
    before do
      workspace.members << member
      log_in member
    end

    it "uses authorization" do
      mock(subject).authorize! :can_edit_sub_objects, workspace
      delete :destroy, :id => public_workfile.id
    end

    describe "deleting" do
      before do
        delete :destroy, :id => public_workfile.id
      end

      it "should soft delete the workfile" do
        workfile = Workfile.find_with_destroyed(public_workfile.id)
        workfile.deleted_at.should_not be_nil
      end

      it "should respond with success" do
        response.should be_success
      end
    end
  end
end
