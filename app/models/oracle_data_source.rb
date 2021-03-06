class OracleDataSource < DataSource
  validates :host, :presence => true
  validates :port, :presence => true
  validates_associated :owner_account, :if => :validate_owner?
  attr_accessor :db_username, :db_password

  before_validation :build_instance_account_for_owner, :on => :create

  has_many :schemas, :as => :parent, :class_name => 'OracleSchema'

  def self.create_for_user(user, data_source_hash)
    unless ChorusConfig.instance.oracle_configured?
      raise ApiValidationError.new(:oracle, :not_configured)
    end

    data_source = user.oracle_data_sources.new(data_source_hash)
    data_source.shared = true
    data_source.save!
    data_source
  end

  def connect_with(account)
    OracleConnection.new(
        :username => account.db_username,
        :password => account.db_password,
        :host => host,
        :port => port,
        :database => db_name
    )
  end

  def refresh_databases_later

  end

  def refresh_schemas
    actual_schema_names = connect_with(owner_account).schemas

    schemas.each do |schema|
      unless actual_schema_names.delete schema.name
        schema.mark_stale!
      end
    end

    actual_schema_names.each do |name|
      schemas.create(:name => name)
    end

    schemas.not_stale
  end

  private

  def validate_owner?
    self.changed.include?('host') || self.changed.include?('port') || self.changed.include?('db_name')
  end

  def build_instance_account_for_owner
    build_owner_account(:owner => owner, :db_username => db_username, :db_password => db_password)
  end
end