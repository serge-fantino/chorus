class OracleSchema < Schema
  attr_accessible :data_source

  belongs_to :data_source, {
      :polymorphic => true,
      :foreign_key => 'parent_id',
      :foreign_type => 'parent_type',
      :class_name => 'OracleDataSource'
  }

  validates :data_source, :presence => true
  validates :name, :presence => true, :uniqueness => { :scope => [:parent_id, :parent_type] }
end