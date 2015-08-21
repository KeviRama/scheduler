# Xronos Scheduler - structured scheduling program.
# Copyright (C) 2009-2014 John Winters
# See COPYING and LICENCE in the root directory of the application
# for more information.

class Location < ActiveRecord::Base

  validates :name, presence: true

  has_many :locationaliases, :dependent => :nullify

  include Elemental

  self.per_page = 15

  scope :active, -> { where(active: true) }
  scope :current, -> { where(current: true) }

  def element_name
    #
    #  A constructed name to pass to our element record.
    #
    #  We use the name which we have (should be a short name), plus any
    #  aliases flagged as of type "display", with any flagged as "friendly"
    #  last.
    #
    displayaliases = locationaliases.where(display: true).sort
    if displayaliases.size > 0
      ([self.name] + displayaliases.collect {|da| da.name}).join(" / ")
    else
      self.name
    end
  end

  def display_name
    self.element_name
  end

  def friendly_name
    friendly_alias = locationaliases.detect {|la| la.friendly}
    if friendly_alias
      friendly_alias.name
    else
      self.name
    end
  end

  def <=>(other)
    self.name <=> other.name
  end

  #
  #  A maintenance method (although one might make it available through
  #  the web interface) to merge two locations.  The one on which it is
  #  called absorbs the other, which means it takes over the other's:
  #
  #  * Aliases
  #  * Commitments
  #
  #  And then the other one is deleted.  You can pass either a location,
  #  or the name of a location.
  #
  def absorb(other)
    if other.instance_of?(String)
      other_location = Location.find_by(name: other)
      if other_location
        other = other_location
      else
        puts "Can't find location #{other}."
      end
    end
    if other.instance_of?(Location)
      if other.id == self.id
        puts "A location can't absorb itself."
      else
        #
        #  Go for it.
        #
        other_element = other.element
        own_element   = self.element
        commitments_taken = 0
        aliases_taken     = 0
        other_element.commitments.each do |commitment|
          #
          #  It's just possible that both locations are committed to the
          #  same event.
          #
          if own_element.commitments.detect {|c| c.event_id == commitment.event_id}
            puts "Both committed to same event.  Dropping other commitment."
            commitment.destroy
          else
            commitment.element = self.element
            commitment.save!
            commitments_taken += 1
          end
        end
        other.locationaliases.each do |la|
          la.location = self
          la.save!
          aliases_taken += 1
        end
        puts "Absorbed #{commitments_taken} commitments and #{aliases_taken} aliases."
        other.reload
        if other.locationaliases.size == 0 &&
           other.element.commitments.size == 0
           puts "Deleting #{other.name}"
          other_location.destroy
        else
          puts "Odd - #{other.name} still has #{other.locationaliases.size} location aliases, and #{other.element.commitments.size} commitments."
        end
      end
    else
      puts "Must pass another location to absorb."
    end
  end

end
