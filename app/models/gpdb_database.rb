require 'greenplum_connection'

class GpdbDatabase < ActiveRecord::Base
  include Stale

  attr_accessible :name

  validates :name,
            :format => /^[^\/?&]*$/,
            :presence => true,
            :uniqueness => { :scope => :gpdb_data_source_id }

  belongs_to :gpdb_data_source
  has_many :schemas, :class_name => 'GpdbSchema', :as => :parent, :dependent => :destroy
  has_many :datasets, :through => :schemas
  has_and_belongs_to_many :instance_accounts


  before_save :mark_schemas_as_stale
  delegate :account_for_user!, :account_for_user, :to => :gpdb_data_source

  DATABASE_NAMES_SQL = <<-SQL
  SELECT
    datname
  FROM
    pg_database
  WHERE
    datallowconn IS TRUE AND datname NOT IN ('postgres', 'template1')
    ORDER BY lower(datname) ASC
  SQL

  def self.refresh(account)
    gpdb_data_source = account.instance
    results = []
    gpdb_data_source.connect_with(account).databases.map do |name|
      next if new(:name => name).invalid?

      db = gpdb_data_source.databases.find_or_create_by_name!(name)
      results << db
      db.update_attributes!({:stale_at => nil}, :without_protection => true)
    end

    results
  end

  def self.reindex_dataset_permissions(database_id)
    GpdbDatabase.find(database_id).datasets.not_stale.each do |dataset|
      begin
        dataset.solr_index
      rescue => e
        Chorus.log_error "Error in GpdbDataset.reindex_dataset_permissions: #{e.message}"
      end
    end
    Sunspot.commit
  end

  def self.visible_to(*args)
    refresh(*args)
  end

  def create_schema(name, current_user)
    new_schema = schemas.build(:name => name)
    raise ActiveRecord::RecordInvalid.new(new_schema) if new_schema.invalid?

    connect_as(current_user).create_schema(name)
    GpdbSchema.refresh(account_for_user!(current_user), self)
    schemas.find_by_name!(name)
  end

  def with_gpdb_connection(account, &block)
    Gpdb::ConnectionBuilder.connect!(account.instance, account, name, &block)
  rescue ActiveRecord::JDBCError => e
    if e.message =~ /database.*does not exist/
      raise GreenplumConnection::ObjectNotFound, "The query could not be completed. Error: #{e.message}"
    else
      raise e
    end
  end

  def find_dataset_in_schema(dataset_name, schema_name)
    schemas.find_by_name(schema_name).datasets.find_by_name(dataset_name)
  end

  def connect_as(user)
    connect_with(gpdb_data_source.account_for_user!(user))
  end

  def connect_with(account)
    options = {
        :host => gpdb_data_source.host,
        :port => gpdb_data_source.port,
        :username => account.db_username,
        :password => account.db_password,
        :database => name,
        :logger => Rails.logger
    }
    GreenplumConnection.new(options)
  end

  private

  def mark_schemas_as_stale
    if stale? && stale_at_changed?
      schemas.each do |schema|
        schema.mark_stale!
      end
    end
  end
end
