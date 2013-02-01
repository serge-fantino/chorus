require 'factory_girl'

FactoryGirl.define do
  factory :data_source do
    sequence(:name) { |n| "data_source#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    sequence(:host) { |n| "data_source#{n + FACTORY_GIRL_SEQUENCE_OFFSET}.emc.com" }
    sequence(:port) { |n| 5000+n }
    db_name "db_name"
    owner
  end

  factory :gpdb_data_source do
    sequence(:name) { |n| "gpdb_data_source#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    sequence(:host) { |n| "gpdb_host#{n + FACTORY_GIRL_SEQUENCE_OFFSET}.emc.com" }
    sequence(:port) { |n| 5000+n }
    db_name "postgres"
    owner
    version "9.1.2 - FactoryVersion"
    db_username 'username'
    db_password 'secret'
    after(:build) do |instance|
      def instance.valid_db_credentials?(account)
        true
      end
    end

    after(:create) do |instance|
      instance.singleton_class.send :remove_method, :valid_db_credentials?
    end
  end

  factory :oracle_data_source do
    sequence(:name) { |n| "oracle_data_source#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    sequence(:host) { |n| "oracle_host#{n + FACTORY_GIRL_SEQUENCE_OFFSET}.emc.com" }
    sequence(:port) { |n| 5000+n }
    db_name "db_name"
    owner
    db_username 'username'
    db_password 'secret'
    after(:build) do |instance|
      def instance.valid_db_credentials?(account)
        true
      end
    end

    after(:create) do |instance|
      instance.singleton_class.send :remove_method, :valid_db_credentials?
    end
  end

  factory :hadoop_instance do
    sequence(:name) { |n| "hadoop_instance#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    sequence(:host) { |n| "host#{n + FACTORY_GIRL_SEQUENCE_OFFSET}.emc.com" }
    sequence(:port) { |n| 5000+n }
    owner
  end

  factory :gnip_instance do
    sequence(:name) { |n| "gnip_instance#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    sequence(:stream_url) { |n| "https://historical.gnip.com/stream_url#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    sequence(:username) { |n| "user#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    password "secret"
    owner
  end

  factory :instance_account do
    sequence(:db_username) { |n| "username#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    db_password "secret"
    owner
    association :instance, :factory => :gpdb_data_source
  end

  factory :gpdb_database do
    sequence(:name) { |n| "database#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    gpdb_data_source
  end

  factory :gpdb_schema do
    sequence(:name) { |n| "schema#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    association :database, :factory => :gpdb_database
    refreshed_at Time.current
  end

  factory :oracle_schema do
    sequence(:name) { |n| "oracle_schema#{n+FACTORY_GIRL_SEQUENCE_OFFSET}"}
    association :data_source, :factory => :oracle_data_source
  end

  factory :gpdb_table do
    sequence(:name) { |n| "table#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    association :schema, :factory => :gpdb_schema
  end

  factory :gpdb_view do
    sequence(:name) { |n| "view#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    association :schema, :factory => :gpdb_schema
  end

  factory :chorus_view do
    sequence(:name) { |n| "chorus_view#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    association :schema, :factory => :gpdb_schema
    association :workspace
    query "select 1;"
    after(:build) do |chorus_view|
      chorus_view.instance_variable_get(:@changed_attributes).delete("query")
    end
  end

  factory :gpdb_column do
    sequence(:name) { |n| "column#{n}" }
    data_type "text"
    description "A nice description"
    sequence(:ordinal_position)
  end

  factory :dataset_statistics do
    initialize_with do
      new({
            'table_type' => 'BASE_TABLE',
            'row_count' => '1000',
            'column_count' => '5',
            'description' => 'This is a nice table.',
            'last_analyzed' => '2012-06-06 23:02:42.40264+00',
            'disk_size' => 2097152,
            'partition_count' => '0',
            'definition' => "SELECT * FROM foo"
          })
    end
  end

  factory :workspace do
    sequence(:name) { |n| "workspace#{n + FACTORY_GIRL_SEQUENCE_OFFSET}" }
    owner
    after(:create) do |workspace|
      FactoryGirl.create(:membership, :workspace => workspace, :user => workspace.owner)
    end
  end

  factory :membership do
    user
    workspace
  end

  factory :visualization_frequency, :class => Visualization::Frequency do
    bins 20
    category "title"
    filters ["\"1000_songs_test_1\".year > '1980'"]
    association :dataset, :factory => :gpdb_table
    association :schema, :factory => :gpdb_schema
  end

  factory :visualization_histogram, :class => Visualization::Histogram do
    bins 20
    category "airport_cleanliness"
    filters ["\"2009_sfo_customer_survey\".terminal > 5"]
    association :dataset, :factory => :gpdb_table
    association :schema, :factory => :gpdb_schema
  end

  factory :visualization_heatmap, :class => Visualization::Heatmap do
    x_bins 3
    y_bins 3
    x_axis "theme"
    y_axis "artist"
    association :dataset, :factory => :gpdb_table
    association :schema, :factory => :gpdb_schema
  end

  factory :visualization_timeseries, :class => Visualization::Timeseries do
    time "time_value"
    value "column1"
    time_interval "month"
    aggregation "sum"
    association :dataset, :factory => :gpdb_table
    association :schema, :factory => :gpdb_schema
  end

  factory :visualization_boxplot, :class => Visualization::Boxplot do
    bins 10
    category "category"
    values "column1"
    association :dataset, :factory => :gpdb_table
    association :schema, :factory => :gpdb_schema
  end

  factory :associated_dataset do
    association :dataset, :factory => :gpdb_table
    workspace
  end

  factory :tableau_workbook_publication do
    sequence(:name) { |n| "workbook#{n}" }
    project_name "Default"
    association :dataset, :factory => :gpdb_table
    workspace
  end

  factory :hdfs_entry do
    hadoop_instance
    is_directory false
    path "/folder/subfolder/file.csv"
    modified_at 1.year.ago
  end

  factory :import_schedule do
    start_datetime Time.current
    end_date Time.current + 1.year
    frequency 'monthly'
    truncate false
    new_table true
    sample_count 1
    association :workspace
    association :user
    sequence(:to_table) { |n| "factoried_import_schedule_table#{n}" }
    association :source_dataset, :factory => :gpdb_table
  end

  factory :import do
    created_at Time.current
    association :workspace, :factory => :workspace
    association :source_dataset, :factory => :gpdb_table
    user
    sequence(:to_table) { |n| "factoried_import_table#{n}" }
    truncate false
    new_table true
    sample_count 10
    file_name nil
  end

  factory :import_with_schedule, :parent => :import do
    association :import_schedule
  end

  factory :csv_import, :class => Import do
    created_at Time.current
    association :workspace, :factory => :workspace
    association :destination_dataset, :factory => :gpdb_table
    user
    file_name "import.csv"
    sequence(:to_table) { |n| "factoried_import_table#{n}" }
    truncate false
    new_table true
    sample_count 10
  end
end

