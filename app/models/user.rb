# Xronos Scheduler - structured scheduling program.
# Copyright (C) 2009-2014 John Winters
# See COPYING and LICENCE in the root directory of the application
# for more information.

class User < ActiveRecord::Base

  DWI = Struct.new(:id, :name)
  DaysOfWeek = [DWI.new(0, "Sunday"),
                DWI.new(1, "Monday"),
                DWI.new(2, "Tuesday"),
                DWI.new(3, "Wednesday"),
                DWI.new(4, "Thursday"),
                DWI.new(5, "Friday"),
                DWI.new(6, "Saturday")]

  DECENT_COLOURS = [
                    "#483D8B",      # DarkSlateBlue
                    "#CD5C5C",      # IndianRed
                    "#B8860B",      # DarkGoldenRed (brown)
                    "#7B68EE",      # MediumSlateBlue
                    "#808000",      # Olive
                    "#6B8E23",      # OliveDrab
                    "#DB7093",      # PaleVioletRed
                    "#2E8B57",      # SeaGreen
                    "#A0522D",      # Sienna
                    "#008080",      # Teal
                    "#3CB371",      # MediumSeaGreen
                    "#2F4F4F",      # DarkSlateGray
                    "#556B2F",      # DarkOliveGreen
                    "#FF6347"]      # Tomato

  has_many :concerns,   :dependent => :destroy

  has_many :events, foreign_key: :owner_id, dependent: :nullify

  has_many :controlled_commitments,
           class_name: "Commitment",
           foreign_key: "by_whom_id",
           dependent: :nullify

  belongs_to :preferred_event_category, class_name: Eventcategory

  #
  #  The only elements we can actually own currently are groups.  By creating
  #  a group with us as the owner, its corresponding element will also be
  #  marked as having us as the owner.  Should this user ever be deleted
  #  the owned groups will also be deleted, and thus the elements will go
  #  too.
  #
  has_many :elements, foreign_key: :owner_id
  has_many :groups,   foreign_key: :owner_id, :dependent => :destroy

  validates :firstday, :presence => true
  validates :firstday, :numericality => true

  scope :arranges_cover, lambda { where("arranges_cover = true") }
  scope :element_owner, lambda { where(:element_owner => true) }
  scope :editors, lambda { where(editor: true) }
  scope :administrators, lambda { where(admin: true) }

  before_destroy :being_destroyed
  after_save :find_matching_resources

  def known?
    @known ||= (self.own_element != nil)
  end

  def staff?
    @staff ||= (self.own_element != nil &&
                self.own_element.entity.class == Staff)
  end

  def pupil?
    @pupil ||= (self.own_element != nil &&
                self.own_element.entity.class == Pupil)
  end

  def own_element
    unless @own_element
      my_own_concern = self.concerns.me[0]
      if my_own_concern
        @own_element = my_own_concern.element
      end
    end
    @own_element
  end

  def concern_with(element)
    possibles = Concern.between(self, element)
    if possibles.size == 1
      possibles[0]
    else
      nil
    end
  end

  #
  #  Could be made more efficient with an explicit d/b hit, but probably
  #  not worth it as each user is likely to own only a small number
  #  of elements.
  #
  #  item can be an element or an event.
  #
  def owns?(item)
    if item.instance_of?(Element)
      !!concerns.owned.detect {|c| (c.element_id == item.id)}
    elsif item.instance_of?(Event)
      item.owner_id == self.id
    else
      false
    end
  end

  #
  #  Can this user meaninfully see the menu in the top bar?
  #
  def sees_menu?
    self.admin ||
    self.editor ||
    self.can_has_groups ||
    self.can_find_free ||
    self.element_owner
  end

  #
  #  The hint tells us whether the invoking concern is an owning
  #  concern.  If it is, then we are definitely owned.  If it is
  #  not then we might not be owned any more.
  #
  def update_owningness(hint)
    unless @being_destroyed || self.destroyed?
      if hint
        unless self.element_owner
          self.element_owner = true
          self.save!
        end
      else
        if self.element_owner
          #
          #  It's possible our last remaining ownership just went away.
          #  This is the most expensive case to check.
          #
          if self.concerns.owned.count == 0
            self.element_owner = false
            self.save!
          end
        end
      end
    end
  end

  def free_colour
    available = DECENT_COLOURS - self.concerns.collect {|i| i.colour}
    if available.size > 0
      available[0]
    else
      "Gray"
    end
  end

  def list_days
    DaysOfWeek
  end

  def create_events?
    self.editor || self.admin
  end

  def create_groups?
    self.staff? || self.admin
  end

  def can_trigger_cover_check?
    self.arranges_cover
  end

  #
  #  What elements do we control?  This information is cached because
  #  we may need it many times during the course of rendering one page.
  #
  def controlled_elements
    unless @controlled_elements
      @controlled_elements = self.concerns.controlling.collect {|c| c.element}
    end
    @controlled_elements
  end

  #
  #  Can this user edit the indicated item?
  #
  def can_edit?(item)
    if item.instance_of?(Event)
      self.admin ||
      (self.create_events? && item.owner_id == self.id) ||
      (self.create_events? && item.involves_any?(self.controlled_elements, true))
    elsif item.instance_of?(Group)
      self.admin ||
      (self.create_groups? &&
       item.owner_id == self.id &&
       item.user_editable?)
    else
      false
    end
  end

  #
  #  Can this user delete the indicated item?
  #  We can only delete our own, and sometimes not even then.
  #
  def can_delete?(item)
    if item.instance_of?(Concern)
      #
      #  If you can't add concerns, then you can't delete them either.
      #  You get what you're given.
      #
      item.user_id == self.id && self.can_add_concerns && item.user_can_delete?
    else
      false
    end
  end

  #
  #  And specifically for events, can the user re-time the event?
  #  Sometimes users can edit, but not re-time.
  #
  #  Returns two values - edit and retime.
  #
  def can_retime?(event)
    if event.id == nil
      can_retime = true
    elsif self.admin ||
       (self.element_owner &&
        self.create_events? &&
        event.involves_any?(self.controlled_elements, true))
      can_retime = true
    elsif self.create_events? && event.owner_id == self.id
      can_retime = !event.constrained
    else
      can_retime = false
    end
    can_retime
  end

  #
  #  Does this user have appropriate permissions to approve/decline
  #  the indicated commitment?
  #
  def can_approve?(commitment)
    self.owns?(commitment.element)
  end

  #
  #  Can this user create a firm commitment for this element?  Note
  #  that this is slightly different from being able to approve a
  #  commitment.  Some users can bypass permissions, but don't actually
  #  have authority for approvals.
  #
  def can_commit?(element)
    !!concerns.can_commit.detect {|c| (c.element_id == element.id)}
  end

  #
  #  Does this user need permission to create a commitment for this
  #  element?
  #
  def needs_permission_for?(element)
    Setting.enforce_permissions? && element.owned && !self.can_commit?(element)
  end

  def permissions_pending
    self.concerns.owned.inject(0) do |total, concern|
      total + concern.permissions_pending
    end
  end

  def events_on(start_date = nil,
                end_date = nil,
                eventcategory = nil,
                eventsource = nil,
                include_nonexistent = false)
    Event.events_on(start_date,
                    end_date,
                    eventcategory,
                    eventsource,
                    nil,
                    self,
                    include_nonexistent)
  end
  #
  #  Create a new user record to match an omniauth authentication.
  #
  #  Anyone can have a user record, but only people with known Abingdon
  #  school e-mail addresses get any further than that.
  #
  def self.create_from_omniauth(auth)
    create! do |user|
      user.provider = auth["provider"]
      user.uid      = auth["uid"]
      user.name     = auth["info"]["name"]
      user.email    = auth["info"]["email"].downcase
    end
  end

  def find_matching_resources
    if self.email && !self.known?
      got_something = false
      staff = Staff.active.find_by_email(self.email)
      if staff
        got_something = true
        concern = self.concern_with(staff.element)
        if concern
          unless concern.equality
            concern.equality = true
            concern.save!
          end
        else
          Concern.create! do |concern|
            concern.user_id    = self.id
            concern.element_id = staff.element.id
            concern.equality   = true
            concern.owns       = false
            concern.visible    = true
            concern.colour     = "#225599"
          end
        end
      end
      pupil = Pupil.find_by_email(self.email)
      if pupil
        got_something = true
        concern = self.concern_with(pupil.element)
        if concern
          unless concern.equality
            concern.equality = true
            concern.save!
          end
        else
          Concern.create! do |concern|
            concern.user_id    = self.id
            concern.element_id = pupil.element.id
            concern.equality   = true
            concern.owns       = false
            concern.visible    = true
            concern.colour     = "#225599"
          end
        end
      end
      if got_something
        calendar_element = Element.find_by(name: "Calendar")
        if calendar_element
          unless self.concern_with(calendar_element)
            Concern.create! do |concern|
              concern.user_id    = self.id
              concern.element_id = calendar_element.id
              concern.equality   = false
              concern.owns       = false
              concern.visible    = true
              concern.colour     = calendar_element.preferred_colour || "green"
            end
          end
        end
      end
    end
  end

  def corresponding_staff
    if self.email
      Staff.find_by_email(self.email)
    else
      nil
    end
  end

  def initials
    if self.corresponding_staff
      self.corresponding_staff.initials
    else
      "UNK"
    end
  end

  #
  #  Retrieve our firstday value, coercing it to be meaningful.
  #
  def safe_firstday
    if self.firstday >=0 && self.firstday <= 6
      self.firstday
    else
      0
    end
  end

  #
  #  Maintenance method.  Set up a new concern record giving this user
  #  control of the indicated element.
  #
  def to_control(element_or_name, auto_add = false)
    if element_or_name.instance_of?(Element)
      element = element_or_name
    else
      element = Element.find_by(name: element_or_name)
    end
    if element
      concern = self.concern_with(element)
      if concern
        if concern.owns &&
           concern.controls &&
           concern.auto_add == auto_add
          "User #{self.name} already controlling #{element.name}."
        else
          concern.owns     = true
          concern.controls = true
          concern.auto_add = auto_add
          concern.save!
          "User #{self.name} promoted to controlling #{element.name}."
        end
      else
        concern = Concern.new
        concern.user    = self
        concern.element = element
        concern.equality = false
        concern.owns     = true
        concern.visible  = true
        concern.colour   = element.preferred_colour || self.free_colour
        concern.auto_add = auto_add
        concern.controls = true
        concern.save!
        "User #{self.name} now controlling #{element.name}."
      end
    else
      "Can't find element #{element_or_name} for #{self.name} to control."
    end
  end

  #
  #  Similar, but only a general interest.
  #
  def to_view(element_or_name, visible = false)
    if element_or_name.instance_of?(Element)
      element = element_or_name
    else
      element = Element.find_by(name: element_or_name)
    end
    if element
      concern = self.concern_with(element)
      if concern
        #
        #  Already has a concern.  Just make sure the colour is right.
        #
        if element.preferred_colour &&
           concern.colour != element.preferred_colour
          concern.colour = element.preferred_colour
          concern.save!
          "Adjusted colour of #{element.name} for #{self.name}."
        else
          ""
        end
      else
        concern = Concern.new
        concern.user    = self
        concern.element = element
        concern.equality = false
        concern.owns     = false
        concern.visible  = visible
        concern.colour   = element.preferred_colour || self.free_colour
        concern.auto_add = false
        concern.controls = false
        concern.save!
        "User #{self.name} now viewing #{element.name}."
      end
    else
      "Can't find element #{element_or_name} for #{self.name} to view."
    end
  end

  #
  #  Fix all users who are students so that they have a concern with
  #  themselves and the calendar, and no others.
  #
  def self.fix_students
    results = Array.new
    calendar_element = Element.find_by(name: "Calendar")
    if calendar_element
      User.all.each do |u|
        e = u.own_element
        if e && e.entity.class == Pupil
          results << "Processing #{e.name}"
          u.concerns.each do |c|
            if c.element != e
              results << "Removing concern with #{c.element.name}"
              c.destroy
            end
          end
          u.to_view(calendar_element, true)
        end
      end
    else
      results << "Unable to find Calendar element."
    end
    results.each do |text|
      puts text
    end
    nil
  end

  #
  #  After the addition of finer-grained permission flags, give them
  #  some initial values.
  #
  def set_initial_permissions
    if self.staff?
      self.can_has_groups   = true
      self.can_find_free    = true
      self.can_add_concerns = true
      self.save!
      "#{self.name} with email #{self.email} gets staff permissions."
    elsif self.pupil?
      "#{self.name} is a pupil."
    else
      "#{self.name} with email #{self.email} is unknown."
    end
  end

  def self.set_initial_permissions
    results = Array.new
    User.all.each do |u|
      results << u.set_initial_permissions
    end
    results.each do |text|
      puts text
    end
    nil
  end

  protected

  def being_destroyed
    @being_destroyed = true
  end

end
