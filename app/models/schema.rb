class Schema < ActiveRecord::Base
  attr_accessible :name, :type
  belongs_to :parent, :polymorphic => true
end