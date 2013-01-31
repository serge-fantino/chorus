require 'spec_helper'

describe GpdbDataSourceWorkspaceDetailPresenter, :type => :view do
  let(:gpdb_data_source) { data_sources(:owners) }
  let(:user) { gpdb_data_source.owner }
  let(:presenter) { GpdbDataSourceWorkspaceDetailPresenter.new(gpdb_data_source, view, {}) }
  let(:config_instance) { { 'kaggle.enabled' => true } }

  before do
    stub(ChorusConfig.instance).[]('sandbox_recommended_size_in_gb') { 1 }
    set_current_user(user)
  end

  describe "#to_hash" do
    let(:size) { 10 }
    before do
      any_instance_of(GpdbSchema) do |schema|
        stub(schema).disk_space_used { size }
      end
    end
    let(:hash) { presenter.to_hash }

    it "includes the right keys" do
      hash.should have_key(:workspaces)
      hash.should have_key(:sandboxes_size_in_bytes)
    end

    context "with several workspaces using the same sandbox" do
      let(:sandbox) { schemas(:default) }
      let(:duplicate_sandbox_workspace1) { FactoryGirl.create(:workspace, :sandbox => sandbox) }
      let(:duplicate_sandbox_workspace2) { FactoryGirl.create(:workspace, :sandbox => sandbox) }

      it "doesn't add up the sandbox size of the duplicate sandboxes" do
        sandbox_ids = Workspace.where(:sandbox_id => gpdb_data_source.schema_ids).collect(&:sandbox_id).uniq
        hash[:sandboxes_size_in_bytes].should == sandbox_ids.length * size
      end
    end

    context "for the workspaces" do
      let(:workspaces) { hash[:workspaces] }
      let(:workspace_hash) { workspaces.first }

      it "has the right keys" do
        workspace_hash.should have_key(:id)
        workspace_hash.should have_key(:name)
        workspace_hash.should have_key(:size_in_bytes)
        workspace_hash.should have_key(:percentage_used)
        workspace_hash.should have_key(:schema_name)
        workspace_hash.should have_key(:database_name)
        workspace_hash.should have_key(:owner_full_name)
      end

      it "uses recommended sandbox size to calculate percentage_used" do
        workspace_hash[:percentage_used].should == (10 / (1 * 1024 * 1024 * 1024).to_f * 100).round
      end

      context "when size cannot be calculated" do
        let(:size) { nil }

        it "returns nil for size_in_bytes and percentage" do
          hash[:size_in_bytes].should == nil
          hash[:percentage_used].should == nil
        end
      end
    end

    context "when the current_user doesn't have access to the instance" do
      let(:user) { users(:not_a_member) }

      it "should have nil for values" do
        hash[:workspaces].should be_nil
        hash[:sandboxes_size_in_bytes].should be_nil
      end
    end

    context "when disk space for a schema can't be retrieved" do
      it "skips those schemas" do
        any_instance_of(GpdbSchema) {|schema| stub(schema).disk_space_used(anything) {nil} }
        hash[:sandboxes_size_in_bytes].should == 0
      end
    end
  end
end