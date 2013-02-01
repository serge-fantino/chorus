class OracleSchemaPresenter < Presenter
  def to_hash
    {
      :id => model.id,
      :name => model.name
    }
  end
end