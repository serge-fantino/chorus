class SchemasController < GpdbController
  def show
    schema = GpdbSchema.find_and_verify_in_source(params[:id], current_user)
    authorize_gpdb_data_source_access(schema)
    present schema
  end
end
