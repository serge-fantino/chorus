require "spec_helper"
require 'timecop'

describe Workspace do
  describe "associations" do
    it { should have_many(:members) }
    it { should have_many(:activities) }
    it { should have_many(:events) }
    it { should belong_to(:sandbox) }
    it { should have_many(:owned_notes).class_name('Events::Base').conditions("events.action ILIKE 'Events::Note%'") }
    it { should have_many(:owned_events).class_name('Events::Base') }
    it { should have_many(:comments).through(:owned_events) }
  end

  before do
    [Import, ImportSchedule].each do |stuff|
      any_instance_of(stuff) do |import|
        stub(import).tables_have_consistent_schema { true }
        stub(import).table_exists? { true }
      end
    end
  end

  describe "create" do
    it "creates a membership for the owner" do
      owner = users(:no_collaborators)
      workspace = owner.owned_workspaces.create!(:name => 'new workspace!')
      workspace.members.should include(owner)
    end
  end

  describe "validations" do
    let(:workspace) { workspaces(:public_with_no_collaborators) }
    let(:max_workspace_icon_size) { ChorusConfig.instance['file_sizes_mb']['workspace_icon'] }

    it { should validate_presence_of :name }
    it { should validate_uniqueness_of(:name).case_insensitive }
    it { should validate_attachment_size(:image).less_than(max_workspace_icon_size.megabytes) }
  end

  describe ".active" do
    let(:active_workspace) { workspaces(:public_with_no_collaborators) }
    let(:archived_workspace) { workspaces(:archived) }

    it "returns only active workspaces" do
      workspaces = Workspace.active
      workspaces.should include(active_workspace)
      workspaces.should_not include(archived_workspace)
    end
  end

  describe ".workspaces_for" do
    context "user is admin" do
      let(:admin) { users(:admin) }
      it "returns unscoped workspaces" do
        mock(Workspace).scoped

        described_class.workspaces_for(admin)
      end
    end

    context "user is not admin" do
      let(:user) { users(:owner) }
      it "returns limited workspaces" do
        mock(Workspace).accessible_to(user)

        described_class.workspaces_for(user)
      end
    end
  end

  describe ".accessible_to" do
    let(:public_workspace) { workspaces(:public) }
    let(:owned_workspace) { workspaces(:private_with_no_collaborators) }
    let(:private_workspace) { workspaces(:private) }
    let(:private_workspace_with_membership) { workspaces(:private_with_no_collaborators) }
    let(:user) { users(:no_collaborators) }

    it "returns public workspaces" do
      Workspace.accessible_to(user).should include public_workspace
    end

    it "returns private workspaces with membership" do
      Workspace.accessible_to(user).should include private_workspace_with_membership
    end

    it "returns private owned workspaces" do
      Workspace.accessible_to(user).should include owned_workspace
    end

    it "does not return private workspaces" do
      Workspace.accessible_to(user).should_not include private_workspace
    end
  end

  describe "#members_accessible_to" do
    let(:private_workspace) { workspaces(:private_with_no_collaborators) }
    let(:workspace) { workspaces(:public_with_no_collaborators) }

    let(:owner) { users(:owner) }
    let(:user) { users(:no_collaborators) }
    let(:admin) { users(:admin) }

    context "public workspace" do
      it "returns all members" do
        workspace.members << owner

        members = workspace.members_accessible_to(user)
        members.should include(owner, user)
      end
    end

    context "user is a member of a private workspace" do
      it "returns all members" do
        private_workspace.members << owner

        members = private_workspace.members_accessible_to(owner)
        members.should include(owner, user)
      end
    end

    context "user is not a member of a private workspace" do
      it "returns nothing" do
        private_workspace.members_accessible_to(owner).should be_empty
      end
    end
  end

  describe "#datasets and #dataset_count" do
    let!(:schema) { FactoryGirl.create(:gpdb_schema) }
    let!(:other_schema) { FactoryGirl.create(:gpdb_schema) }
    let!(:sandbox_table) { FactoryGirl.create(:gpdb_table, :schema => schema) }
    let!(:sandbox_view) { FactoryGirl.create(:gpdb_view, :schema => schema) }
    let!(:source_table) { FactoryGirl.create(:gpdb_table, :schema => other_schema) }
    let!(:other_table) { FactoryGirl.create(:gpdb_table, :schema => other_schema) }
    let!(:chorus_view) {
      FactoryGirl.create(:chorus_view, :name => "chorus_view", :schema => schema, :query => "select * from a_table", :workspace => workspace)
    }
    let!(:chorus_view_from_source) {
      FactoryGirl.create(:chorus_view, :name => "chorus_view_from_source", :schema => other_schema, :query => "select 1", :workspace => workspace)
    }
    let(:user) { users(:the_collaborator) }

    context "when the workspace has a sandbox" do
      let!(:workspace) { FactoryGirl.create(:workspace, :sandbox => schema) }

      before do
        workspace.bound_datasets << source_table
      end

      context "when the user does not have an instance account" do
        it "lets them see associated datasets and chorus views only" do
          workspace.datasets(user).to_a.should =~ [source_table, chorus_view, chorus_view_from_source]
          workspace.dataset_count(user).should == 3
        end
      end

      context "when the user has an instance account" do
        let!(:account) { FactoryGirl.build(:instance_account, :instance => schema.database.gpdb_data_source, :owner => user).tap { |a| a.save(:validate => false)} }

        context "when the sandbox has tables" do
          before do
            stub(Dataset).refresh(account, schema, anything) { [sandbox_table, sandbox_view] }
            stub(Dataset).total_entries(account, schema, anything) { 142 }
          end

          it "includes datasets in the workspace's sandbox and all of its bound datasets" do
            workspace.datasets(user).to_a.should =~ [sandbox_table, source_table, chorus_view, sandbox_view, chorus_view_from_source]
            workspace.dataset_count(user).should == 1 + 2 + 142
          end

          it "filters by type" do
            workspace.datasets(user, { :type => "SANDBOX_DATASET" }).to_a.should =~ [sandbox_table, sandbox_view]
            workspace.dataset_count(user, { :type => "SANDBOX_DATASET" }).should == 142
            workspace.datasets(user, { :type => "CHORUS_VIEW" }).to_a.should =~ [chorus_view, chorus_view_from_source]
            workspace.dataset_count(user, { :type => "CHORUS_VIEW" }).should == 2
            workspace.datasets(user, { :type => "SOURCE_TABLE" }).to_a.should =~ [source_table]
            workspace.datasets(user, { :type => "NON_CHORUS_VIEW" }).to_a.should =~ [sandbox_table, sandbox_view, source_table]
            workspace.dataset_count(user, { :type => "SOURCE_TABLE" }).should == 1
          end

          describe "filtering by sandbox table" do
            before do
              options ={:type => "SANDBOX_TABLE",
                        :tables_only => true }
              mock(Dataset).refresh(account, schema, options) {
                [sandbox_table]
              }
              mock(Dataset).total_entries(account, schema, options) { 141 }

            end

            it "filters out views" do
              workspace.datasets(user, { :type => "SANDBOX_TABLE" }).to_a.should =~ [sandbox_table]
              workspace.dataset_count(user, { :type => "SANDBOX_TABLE" }).should == 141
            end
          end
        end

        context "when there are no datasets for this workspace" do
          before do
            stub(Dataset).refresh(account, schema, anything) { [] }
            stub(Dataset).total_entries(account, schema, anything) { 0 }
          end

          it "returns no results" do
            workspace.datasets(user, { :type => "SANDBOX_TABLE" }).should =~ []
            workspace.datasets(user, { :type => "SANDBOX_DATASET" }).should =~ []
            workspace.dataset_count(user, { :type => "SANDBOX_DATASET" }).should == 0
          end
        end
      end

      context "with associated datasets and options contain a database id" do
        let!(:chorus_view) { FactoryGirl.create(:chorus_view, :workspace => workspace, :schema => dataset1.schema) }
        let(:dataset1) { datasets(:table) }
        let(:dataset2) { datasets(:searchquery_table) }

        before do
          workspace.bound_datasets << dataset1
          workspace.bound_datasets << dataset2
        end

        it "filters the datasets to specified database" do
          workspace_datasets = workspace.datasets(user, {:database_id => dataset1.schema.database.id})
          workspace_datasets.should include(dataset1)
          workspace_datasets.should include(chorus_view)
          workspace_datasets.should_not include(dataset2)
        end
      end
    end

    context "when the workspace does not have a sandbox" do
      let!(:workspace) { FactoryGirl.create(:workspace, :sandbox => nil) }
      let!(:chorus_view) {
        FactoryGirl.create(:chorus_view,
                           :name => "chorus_view",
                           :query => "select 1",
                           :schema => schema,
                           :workspace => workspace)
      }

      before do
        workspace.bound_datasets << source_table
      end

      it "includes the workspace's bound datasets" do
        workspace.datasets(user).to_a.should include(source_table)
      end

      it "includes the workspace's chorus views" do
        workspace.datasets(user).to_a.should include(chorus_view)
      end

      context "when the workspace has associated datasets and a database_id is given" do
        let!(:chorus_view) { FactoryGirl.create(:chorus_view, :workspace => workspace, :schema => dataset1.schema) }
        let(:dataset1) { datasets(:table) }
        let(:dataset2) { datasets(:searchquery_table) }

        before do
          workspace.bound_datasets << dataset1
          workspace.bound_datasets << dataset2
        end

        it "filters for given database" do
          workspace.datasets(user, { :database_id => dataset1.schema.database.id }).should =~ [dataset1, chorus_view]
        end
      end
    end

    context "when the workspace has no sandbox and no associated datasets" do
      let!(:workspace) { FactoryGirl.create(:workspace, :sandbox => nil) }

      before do
        workspace.associated_datasets.destroy_all
        workspace.chorus_views.destroy_all
      end

      it "returns an empty relation" do
        workspace.reload.datasets(user).should == []
      end
    end
  end

  describe "#image" do
    it "should have a nil image instead of a default missing image" do
      workspace = workspaces(:public_with_no_collaborators)
      workspace.update_attributes!(:image => nil)
      workspace.image.url.should == ""
    end
  end

  it { should have_attached_file(:image) }

  describe "permissions_for" do
    it "should have the correct permissions per user" do
      owner = users(:no_collaborators)
      private_workspace = workspaces(:private_with_no_collaborators)
      public_workspace = workspaces(:public_with_no_collaborators)
      member = users(:the_collaborator)
      admin = users(:admin)
      anon = users(:owner)

      [
          [private_workspace, owner, [:admin]],
          [private_workspace, member, [:read, :commenting, :update]],
          [private_workspace, admin, [:admin]],
          [private_workspace, anon, []],
          [public_workspace, anon, [:read, :commenting]]
      ].each do |workspace, user, list|
        workspace.permissions_for(user).should == list
      end
    end
  end

  describe "#archived?" do
    let(:active_workspace) { workspaces(:public_with_no_collaborators) }
    let(:archived_workspace) { workspaces(:archived) }

    it "says that active workspace is not archived" do
      active_workspace.should_not be_archived
    end

    it "says active workspace is not archived" do
      archived_workspace.should be_archived
    end
  end

  describe "#destroy" do
    let(:workspace) { workspaces(:public) }
    let(:workfile) { workfiles(:public) }

    it "should not delete the database entry" do
      workspace.destroy
      expect {
        workspace.reload
      }.to_not raise_error(Exception)
    end

    it "should update the deleted_at field" do
      workspace.destroy
      workspace.reload.deleted_at.should_not be_nil
    end

    it "should be hidden from subsequent #find calls" do
      workspace.destroy
      Workspace.find_by_id(workspace.id).should be_nil
    end

    it "does not reindex the workspace for each member" do
      any_instance_of(Workspace) do |instance|
        mock(instance).solr_reindex.with_any_args.times(0)
      end
      workspace.destroy
    end

    it "soft-deletes the associated workfiles" do
      workspace.workfiles << workfile
      workspace.save!

      workspace.destroy
      workfile.reload
      workfile.deleted_at.should_not be_nil
    end

    it "soft deletes associated chorus views" do
      chorus_views = workspace.chorus_views
      chorus_views.length.should > 0

      workspace.destroy
      chorus_views.each do |cv|
        cv.reload.deleted_at.should_not be_nil
      end
    end

    it "soft deletes the associated source tables" do
      tables =  workspace.bound_datasets.tables

      expect {
        workspace.destroy
        tables.map(&:reload)
      }.to change{ tables.select { |table| table.deleted_at != nil }.size }.by_at_least(1)
    end

    it "soft deletes dataset associations" do
      expect {
        workspace.destroy
      }.to change{ workspace.associated_datasets.select { |ad| ad.deleted_at != nil }.size }.by_at_least(1)
    end

    it "soft deletes import schedules" do
      [Import, ImportSchedule].each do |stuff|
        any_instance_of(stuff) do |import|
          stub(import).valid? { true }
        end
      end

      import_schedule = FactoryGirl.create(:import_schedule, :workspace_id => workspace.id)
      workspace.destroy
      import_schedule.reload
      import_schedule.deleted_at.should_not be_nil
    end
  end

  describe "#reindex_workspace" do
    let(:workspace) { workspaces(:public) }

    before do
      stub(Sunspot).index.with_any_args
    end

    it "reindexes itself" do
      mock(Sunspot).index(workspace)
      Workspace.reindex_workspace(workspace.id)
    end

    it "reindexes the workfiles" do
      mock(Sunspot).index(is_a(Workfile)).times(workspace.workfiles.count)
      Workspace.reindex_workspace(workspace.id)
    end

    it "should reindex notes in the workspace" do
      mock(Sunspot).index(is_a(Events::Note)).times(workspace.owned_notes.count)
      Workspace.reindex_workspace(workspace.id)
    end

    it "should reindex comments in the workspace" do
      mock(Sunspot).index(is_a(Comment)).times(workspace.comments.count)
      Workspace.reindex_workspace(workspace.id)
    end
  end

  describe "#solr_reindex_later" do
    let(:workspace) { workspaces(:public) }
    it "should enqueue a job" do
      mock(QC.default_queue).enqueue_if_not_queued("Workspace.reindex_workspace", workspace.id)
      workspace.solr_reindex_later
    end
  end

  describe "#has_dataset" do
    let(:workspace) { workspaces(:public_with_no_collaborators) }
    let(:dataset) { FactoryGirl.create(:gpdb_table) }

    it "returns true if the dataset is in the workspace's sandbox" do
      workspace.sandbox = dataset.schema
      workspace.has_dataset?(dataset).should be_true
    end

    it "returns true if the dataset has already been associated with the workspace" do
      workspace.bound_datasets << dataset
      workspace.has_dataset?(dataset).should be_true
    end

    it "returns false otherwise" do
      workspace.has_dataset?(dataset).should be_false
    end
  end

  describe "search fields" do
    it "indexes text fields" do
      Workspace.should have_searchable_field :name
      Workspace.should have_searchable_field :summary
    end
  end

  describe "#member?" do
    it "is true for members" do
      workspaces(:public).member?(users(:owner)).should be_true
    end

    it "is false for non members" do
      workspaces(:public).member?(users(:no_collaborators)).should be_false
    end
  end

  describe "#archived=" do
    context "when setting to 'true'" do
      let(:workspace) { workspaces(:public) }
      let(:archiver) { users(:owner) }
      it "sets the archived_at timestamp" do
        workspace.update_attributes!(:archiver => archiver, :archived => 'true')
        workspace.archived_at.should be_within(1.minute).of(Time.current)
      end

      it "has a validation error when archiver is not set" do
        workspace.update_attributes(:archived => 'true')
        workspace.should have(1).error_on(:archived)
      end
    end

    context "when setting to 'false'" do
      let(:workspace) { workspaces(:archived) }
      it "clears the archived_at timestamp and archiver" do
        workspace.update_attributes(:archived => 'false')
        workspace.archived_at.should be_nil
        workspace.archiver.should be_nil
      end
    end
  end

  describe "callbacks" do
    let(:workspace) { workspaces(:public_with_no_collaborators) }
    let(:sandbox) { schemas(:default) }

    describe "before_save" do
      describe "update_has_added_sandbox" do
        it "sets if passed a valid sandbox_id" do
          workspace.sandbox_id = sandbox.id
          workspace.save!
          workspace.should have_added_sandbox
        end

        it "does not set it if passed an invalid sandbox_id" do
          workspace.sandbox_id = 8675309
          workspace.save
          workspace.should_not have_added_sandbox
        end

        it "does not unset it if sandbox is removed" do
          workspace = workspaces(:public)
          workspace.sandbox_id = nil
          workspace.save!
          workspace.should have_added_sandbox
        end
      end
    end

    describe "before_update" do
      describe "clear_assigned_datasets_on_sandbox_assignment" do
        let(:sandbox_dataset) { sandbox.datasets.first }
        let(:other_dataset) { datasets(:other_table) }

        before do
          workspace.bound_datasets << sandbox_dataset
          workspace.bound_datasets << other_dataset
          workspace.sandbox_id = sandbox.id
          workspace.save!
        end

        it "removes duplicate datasets" do
          workspace.bound_datasets.should_not include(sandbox_dataset)
          sandbox_dataset.reload.should_not be_nil
        end

        it "does not remove datasets from other schemas" do
          workspace.bound_datasets.should include(other_dataset)
        end
      end
    end

    describe "after_update" do
      let(:owner) { users(:no_collaborators) }

      before do
        set_current_user(owner)
      end

      context 'its import schedules' do
        let(:workspace) { workspaces(:public) }

        it "are unscheduled after archiving" do
          [Import, ImportSchedule].each do |stuff|
            any_instance_of(stuff) do |import|
              stub(import).valid? { true }
            end
          end

          expect {
            workspace.archiver = owner
            workspace.archived = 'true'
            workspace.save
          }.to change(workspace.import_schedules, :count).by(-1)
        end

        it "are not unscheduled unless it is archived" do
          expect {
            workspace.name = 'notArchived'
            workspace.save
          }.to_not change(workspace.import_schedules, :count)
        end
      end

      it "creates an event if the workspace name was changed" do
        old_name = workspace.name
        expect {
          workspace.name = "new_workspace_name"
          workspace.save
        }.to change { Events::WorkspaceChangeName.count }.by(1)
        workspace.reload.name.should == 'new_workspace_name'
        Events::WorkspaceChangeName.last.additional_data.should == {'workspace_old_name' => old_name}
      end

      it "does not create an event if the workspace name was not changed" do
        expect {
          workspace.name = workspace.name
          workspace.save
        }.not_to change { Events::WorkspaceChangeName.count }
      end

      it "should not reindex" do
        dont_allow(workspace).solr_reindex_later
        workspace.update_attributes(:name => "foo")
      end

      describe "making the workspace private" do
        it "should reindex" do
          mock(workspace).solr_reindex_later
          workspace.update_attributes(:public => false)
        end
      end

      describe "making the workspace public" do
        let(:workspace) { workspaces(:private_with_no_collaborators) }
        it "should reindex" do
          mock(workspace).solr_reindex_later
          workspace.update_attributes(:public => true)
        end
      end
    end
  end
end
