class Change < ActiveRecord::Base
  STATE_SUGGESTED = 'suggested'
  STATE_SAVED = 'saved'
  STATE_EXECUTED = 'executed'
  
  belongs_to :activity
  
  validates_associated :activity
  validates_presence_of :sql
  
  before_save :check_correct_state, :mark_activity_updated
  
  def self.activity_sql(activity_id)
    sql = ''
    Change.find_all_by_activity_id(activity_id, :order => 'created_at').each do |change|
      sql += "#{change.sql}\n"
    end
    sql
  end
  
  def use_sql(sql, db_username, db_password)
    case state
    when STATE_EXECUTED
      begin
        db_instance_dev.execute_sql(sql, db_username, db_password, activity.schema)
      rescue Brazil::DBException => exception
        errors.add(:sql, "not executed: #{exception.to_s}")
        return false
      end
    when STATE_SAVED
      unless db_instance_dev.check_db_credentials(db_username, db_password, activity.schema)
        errors.add_to_base("You don't have the Database credentials to save this change")
        return false
      end
    else
      raise UnknowStateException, "Unknown state for Change when trying to execute SQL, #{self}"
    end
    
    return true
  end
  
  def to_s
    id.to_s
  end
  
  def suggested?
    (state == STATE_SUGGESTED)
  end
  
  def suggested!
    self.state = STATE_SUGGESTED
  end
  
  def saved!
    self.state = STATE_SAVED
  end
  
  def executed!
    self.state = STATE_EXECUTED
  end
      
  def valid_email?(email)
    TMail::Address.parse(email) && /@/.match(email)
  rescue
    false
  end
  
  validates_each :developer do |record, attr, value|
    record.errors.add("#{attr} entry must be a valid email and") unless record.valid_email?(value)    
  end

  validates_each :dba do |record, attr, value|
    if !record.suggested? && !record.valid_email?(value)
      record.errors.add("#{attr} entry must be a valid email and")
    end
  end
  
  private
  
  def db_instance_dev
    activity.db_instances.each do |db_instance|
      return db_instance if db_instance.dev?
    end
    
    raise Brazil::NoDbInstanceException, "#{activity} has no #{DbInstance::ENV_DEV} database instance set. Use Edit Activity to set one."
  end
  
  def check_correct_state
    unless activity.development?
      errors.add_to_base("You can only add or update a change when its activity is in state development")
      false
    end
  end
  
  def mark_activity_updated
    activity.updated_at = Time.now
    activity.save
  end
end
