#
# Xronos Scheduler - structured scheduling program.
# Copyright (C) 2009-2018 John Winters
# See COPYING and LICENCE in the root directory of the application
# for more information.

class Concern < ApplicationRecord

  FLAGS = [
    :visible,
    :equality,
    :owns,
    :auto_add,
    :edit_any,
    :subedit_any,
    :skip_permissions,
    :seek_permission,
    :list_teachers,
    :list_rooms,
    :assistant_to
  ]
  TITLES = {
    visible:          "Currently visible",
    equality:         "Equality",
    owns:             "Controller",
    auto_add:         "Auto add",
    edit_any:         "Edit any",
    subedit_any:      "Sub-edit any",
    skip_permissions: "Skip permissions",
    seek_permission:  "Seek permission",
    list_teachers:    "List teachers",
    list_rooms:       "List rooms",
    assistant_to:     "See confidential"
  }
  EXPLANATIONS = {
    visible:          "Are events for this resource currently visible?",
    equality:         "Is this user identical with the resource?",
    owns:             "Does this user approve use of the resource?",
    auto_add:         "Should this resource be auto-added to new events?",
    edit_any:         "Can this user edit any event involving this resource?",
    subedit_any:      "Can this user sub-edit any event involving this resource?",
    skip_permissions: "Can this user skip the permissions process for this resource?",
    seek_permission:  "Set to put requests through the permissions process regardless.",
    list_teachers:    "When viewing events for this resource, should teachers be listed?",
    list_rooms:       "When viewing events for this resource, should rooms be listed?",
    assistant_to:     "When viewing events for this resource, can the user see the body text of the event even when it is confidential?"
  }
  belongs_to :user
  belongs_to :element
  belongs_to :concern_set, optional: true       # May be nil
  has_one    :itemreport, :dependent => :destroy

  validates_presence_of :colour
  validates_uniqueness_of :element_id, scope: [:user_id, :concern_set_id]

  scope :me, -> {where(equality: true)}
  scope :not_me, -> {where.not(equality: true)}
  scope :owned, -> {where(owns: true)}
  scope :not_owned, -> {where.not(owns: true)}
  scope :skip_permissions, -> {where(skip_permissions: true)}
  scope :seek_permission, -> {where(seek_permission: true)}
  scope :edit_any, -> {where(edit_any: true)}
  scope :subedit_any, -> {where(subedit_any: true)}
  scope :default_view, -> { where(concern_set_id: nil) }
  #
  #  If we were on Rails 5 then we could combine the above two with an OR
  #  but for now we need to do it manually.
  #
  scope :either_edit_flag, -> {where("edit_any = ? OR subedit_any = ?", true, true)}
  #
  #  ActiveRecord scopes are not good at OR conditions, so resort to SQL.
  #
  #  Note that the following is used to check whether the user
  #  can currently shove a commitment straight in.  The user may
  #  have opted to go through the permissions process by way
  #  of setting the seek_permission bit.
  #
  scope :can_commit, -> {where("(owns = ? OR skip_permissions = ?) AND seek_permission = ?", true, true, false)}
  #
  #  And this next one tests whether the user *could* commit.  I.e.
  #  does he or she have the necessary permission, regardless of whether
  #  it's currently turned off.
  #
  scope :could_commit, -> {where("owns = ? OR skip_permissions = ?", true, true)}

  scope :visible, -> { where(visible: true) }

  scope :between, ->(user, element) {where(user_id: user.id, element_id: element.id)}

  scope :concerned_with, ->(element) { where(element_id: element.id) }
  scope :auto_add, -> { where(auto_add: true) }

  after_save :update_after_save
  after_destroy :update_after_destroy

  #
  #  This isn't a real field in the d/b.  It exists to allow a name
  #  to be typed in the dialogue for creating a concern record,
  #  expressing interest in an element.
  #
  attr_accessor :name

  #
  #  Likewise, this isn't in the database either.  It is used for
  #  displaying faked concerns to non-logged-in users.
  #
  attr_accessor :fake_id

  def id_or_fake
    @fake_id ? @fake_id : self.id
  end

  #
  #  Concerns are sorted so that identities come first, then ownerships,
  #  then the rest.
  #
  def <=>(other)
    if self.equality
      if other.equality
        if self.owns
          if other.owns
            self.element <=> other.element
          else
            -1
          end
        else
          if other.owns
            1
          else
            self.element <=> other.element
          end
        end
      else
        -1
      end
    else
      if other.equality
        1
      else
        if self.owns
          if other.owns
            self.element <=> other.element
          else
            -1
          end
        else
          if other.owns
            1
          else
            self.element <=> other.element
          end
        end
      end
    end
  end

  #
  #  Can the relevant user (as opposed to an admin) delete this concern?
  #
  def user_can_delete?
    !(self.equality? ||
      self.owns? ||
      self.edit_any? ||
      self.subedit_any? ||
      self.skip_permissions?)
  end

  #
  #  How many permissions are pending for the element pointed to by
  #  this concern?
  #
  def permissions_pending
    unless @permissions_pending
      if self.owns
        @permissions_pending = self.element.permissions_pending
      else
        @permissions_pending = 0
      end
    end
    @permissions_pending
  end

  protected

  def update_after_destroy
    if self.element
      self.element.update_ownedness(false)
    end
    if self.user
      self.user.concern_changed(true, self)
    end
  end

  def update_after_save
    if self.element
      self.element.update_ownedness(self.owns)
    end
    if self.user
      self.user.concern_changed(false, self)
    end
  end

end
