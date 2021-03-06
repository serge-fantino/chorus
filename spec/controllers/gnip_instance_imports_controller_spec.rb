require 'spec_helper'

describe GnipInstanceImportsController do

  let(:user) { users(:owner) }
  let(:gnip_csv_result_mock) { GnipCsvResult.new("a,b,c\n1,2,3") }
  let(:gnip_instance) { gnip_instances(:default) }
  let(:workspace) { workspaces(:public) }

  let(:gnip_instance_import_params) { {
      :gnip_instance_id => gnip_instance.id,
      :import => {
          :to_table => 'foobar',
          :workspace_id => workspace.id
      }
  } }

  describe "#create" do
    before do
      log_in user
    end

    context "table name doesn't exist already" do
      context "when success" do
        before do
          mock(QC.default_queue).enqueue_if_not_queued("GnipImporter.import_to_table", 'foobar',
                                                       gnip_instance.id, workspace.id, user.id, anything)

          any_instance_of(GnipImporter) { |importer| stub(importer).valid? { true } }
        end

        it "uses authentication" do
          mock(subject).authorize! :can_edit_sub_objects, workspace
          post :create, gnip_instance_import_params
          response.code.should == '200'
        end

        it "leaves the job to handle the CSVFile" do
          expect {
            post :create, gnip_instance_import_params
          }.to change(CsvFile, :count).by(0)
        end

        it "creates an event before it is run" do
          expect {
            post :create, gnip_instance_import_params
          }.to change(Events::GnipStreamImportCreated, :count).by(1)

          created_event = Events::GnipStreamImportCreated.last
          created_event.destination_table.should == 'foobar'
          created_event.dataset.should_not be_present
        end
      end

      it "renders errors if the GnipImporter is not valid" do
        any_instance_of(GnipImporter) { |importer| stub(importer).valid? { false } }
        expect {
          post :create, gnip_instance_import_params
        }.to_not change(Events::GnipStreamImportCreated, :count)
        response.code.should == "422"
      end
    end
  end
end
