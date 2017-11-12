class UserFormResponse < ActiveRecord::Base

  enum status: [
    :empty,
    :partial,
    :complete
  ]

  belongs_to :user_form
  belongs_to :parent, polymorphic: true
  belongs_to :user

  validates :user_form, presence: true

  scope :incomplete, -> { where.not("user_form_responses.status = ?",
                                    UserFormResponse.statuses[:complete]) }
  #
  #  The following are helper methods intended to make life easier for
  #  the view.  They could go in a helper, but it seems more logical
  #  to be able to ask the model for this information.
  #
  #
  def definition
    user_form ? user_form.definition : ""
  end

  def updated_at_text
    self.updated_at.strftime(
      "%H:%M:%S #{self.updated_at.day.ordinalize} %b, %Y")
  end

  def corresponding_event
    if self.parent
      if self.parent.instance_of?(Event)
        self.parent
      elsif self.parent.instance_of?(Commitment)
        self.parent.event
      else
        nil
      end
    else
      nil
    end
  end

  def event_text
    event = corresponding_event
    if event
      event.body
    else
      ""
    end
  end

  def event_time_text
    event = corresponding_event
    if event
      event.starts_at.interval_str(event.ends_at)
    else
      ""
    end
  end

  def event_date_text
    event = corresponding_event
    if event
      event.starts_at.strftime("%d/%m/%Y")
    else
      ""
    end
  end

  def user_text
    self.user ? self.user.name : ""
  end

  #
  #  Note that this method expects a symbol.  The underlying Rails
  #  method expects an integer.
  #
  def status=(new_status)
    self[:status] = UserFormResponse.statuses[new_status]
  end

  #
  #  A couple of maintenance methods to populate the new status field.
  #
  def populate_status
    if self.was_complete?
      self.status = :complete
    else
      self.status = :empty
    end
    self.save!
  end

  def self.populate_statuses
    self.find_each do |ufr|
      ufr.populate_status
    end
    nil
  end
end
