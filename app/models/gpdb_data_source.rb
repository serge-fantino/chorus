class GpdbDataSource < DataSource
  attr_accessor :db_username, :db_password

  validates_associated :owner_account, :error_field => :instance_account, :unless => proc { |instance| (instance.changes.keys & ['host', 'port', 'db_name']).empty? }

  validates_with DataSourceNameValidator
  
  has_many :databases, :class_name => 'GpdbDatabase', :dependent => :destroy
  has_many :schemas, :through => :databases, :class_name => 'GpdbSchema'
  has_many :datasets, :through => :schemas
  has_many :workspaces, :through => :schemas, :foreign_key => 'sandbox_id'
  has_many :events_where_target1, :class_name => "Events::Base", :as => :target1, :dependent => :destroy

  before_validation :build_instance_account_for_owner, :on => :create
  after_update :solr_reindex_later, :if => :shared_changed?
  after_create :create_instance_created_event, :if => :current_user
  after_update :create_instance_name_changed_event, :if => :current_user

  attr_accessor :highlighted_attributes, :search_result_notes
  searchable do
    text :name, :stored => true, :boost => SOLR_PRIMARY_FIELD_BOOST
    text :description, :stored => true, :boost => SOLR_SECONDARY_FIELD_BOOST
    string :grouping_id
    string :type_name
    string :security_type_name, :multiple => true
  end

  def self.unshared
    where("data_sources.shared = false OR data_sources.shared IS NULL")
  end

  def self.reindex_instance instance_id
    instance = GpdbDataSource.find(instance_id)
    instance.solr_index
    instance.datasets(:reload => true).each(&:solr_index)
  end

  def solr_reindex_later
    QC.enqueue_if_not_queued('GpdbDataSource.reindex_instance', id)
  end

  def refresh_databases_later
    QC.enqueue_if_not_queued('GpdbDataSource.refresh_databases', id)
  end

  def self.owned_by(user)
    if user.admin?
      scoped
    else
      where(:owner_id => user.id)
    end
  end

  def used_by_workspaces(viewing_user)
    workspaces.workspaces_for(viewing_user).order("lower(workspaces.name)")
  end

  def accessible_to(user)
    GpdbDataSource.accessible_to(user).include?(self)
  end

  def connect_with(account)
    GreenplumConnection.new(
        :username => account.db_username,
        :password => account.db_password,
        :host => host,
        :port => port,
        :database => db_name,
        :logger => Rails.logger
    )
  end

  def refresh_databases(options ={})
    found_databases = []
    rows = Gpdb::ConnectionBuilder.connect!(self, owner_account, db_name) { |conn| conn.select_all(database_and_role_sql) }
    database_account_groups = rows.inject({}) do |groups, row|
      groups[row["database_name"]] ||= []
      groups[row["database_name"]] << row["db_username"]
      groups
    end

    database_account_groups.each do |database_name, db_usernames|
      database = databases.find_or_initialize_by_name(database_name)

      # TODO: [#40454327] Don't just skip refreshing the database. Actually do something useful.
      if database.invalid?
        databases.delete(database)
        next
      end

      database.update_attributes!({:stale_at => nil}, :without_protection => true)
      database_accounts = accounts.where(:db_username => db_usernames)
      if database.instance_accounts.sort != database_accounts.sort
        database.instance_accounts = database_accounts
        QC.enqueue_if_not_queued("GpdbDatabase.reindex_dataset_permissions", database.id) if database.datasets.count > 0
      end
      found_databases << database
    end
  rescue ActiveRecord::JDBCError => e
    Chorus.log_error "Could not refresh database: #{e.message} on #{e.backtrace[0]}"
  ensure
    if options[:mark_stale]
      (databases.not_stale - found_databases).each do |database|
        database.mark_stale!
      end
    end
  end

  def create_database(name, current_user)
    new_db = databases.build(:name => name)
    raise ActiveRecord::RecordInvalid.new(new_db) unless new_db.valid?

    create_database_in_instance(name, current_user)
    refresh_databases
    databases.find_by_name!(name)
  end

  def account_names
    accounts.pluck(:db_username)
  end

  def account_for_user(user)
    if shared?
      owner_account
    else
      account_owned_by(user)
    end
  end

  def account_for_user!(user)
    account_for_user(user) || (raise ActiveRecord::RecordNotFound.new)
  end

  def gpdb_data_source
    self
  end

  def self.refresh(id, options={})
    symbolized_options = options.symbolize_keys
    symbolized_options[:new] = symbolized_options[:new].to_s == "true" if symbolized_options[:new]
    find(id).refresh symbolized_options
  end

  def refresh(options={})
    refresh_databases options
    refresh_all options

    # would do this in a separate job, but QC doesn't seem to guarantee the order and development only uses one worker
    if options[:new]
      refresh_all options.except(:new).merge(:force_index => true)
    end
  end

  def refresh_all(options={})
    databases.each do |database|
      begin
        GpdbSchema.refresh(owner_account, database, options.reverse_merge(:refresh_all => true))
      rescue GreenplumConnection::DatabaseError => e
        Chorus.log_error "Could not refresh database #{database.name}: #{e.message} #{e.backtrace.to_s}"
      end
    end
  end

  def entity_type_name
    'gpdb_data_source'
  end

  def instance_provider
    "Greenplum Database"
  end

  def self.type_name
    'Instance'
  end

  private

  def create_database_in_instance(name, current_user)
    Gpdb::ConnectionBuilder.connect!(self, account_for_user!(current_user)) do |conn|
      sql = "CREATE DATABASE #{conn.quote_column_name(name)}"
      conn.exec_query(sql)
    end
  end

  def database_and_role_sql
    roles = Arel::Table.new("pg_catalog.pg_roles", :as => "r")
    databases = Arel::Table.new("pg_catalog.pg_database", :as => "d")

    roles.join(databases).
        on(Arel.sql("has_database_privilege(r.oid, d.oid, 'CONNECT')")).
        where(
        databases[:datname].not_eq("postgres").
            and(databases[:datistemplate].eq(false)).
            and(databases[:datallowconn].eq(true)).
            and(roles[:rolname].in(account_names))
    ).project(
        roles[:rolname].as("db_username"),
        databases[:datname].as("database_name")
    ).to_sql
  end

  def build_instance_account_for_owner
    build_owner_account(:owner => owner, :db_username => db_username, :db_password => db_password)
  end

  def create_instance_name_changed_event
    if name_changed?
      Events::GreenplumInstanceChangedName.by(current_user).add(
          :gpdb_data_source => self,
          :old_name => name_was,
          :new_name => name
      )
    end
  end
end
