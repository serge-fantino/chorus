class GpdbDataSourcePresenter < Presenter

  def to_hash
    {
      :name => model.name,
      :host => model.host,
      :port => model.port,
      :id => model.id,
      :shared => model.shared,
      :online => model.state == "online",
      :db_name => model.db_name,
      :description => model.description,
      :instance_provider => model.instance_provider,
      :version => model.version,
      :entity_type => model.entity_type_name,
      :is_deleted => !model.deleted_at.nil?
    }.merge(owner_hash)
  end

  def complete_json?
    !rendering_activities?
  end

  private

  def owner_hash
    if rendering_activities?
      {}
    else
      {:owner => present(model.owner)}
    end
  end
end
