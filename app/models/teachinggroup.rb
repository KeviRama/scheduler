# Xronos Scheduler - structured scheduling program.
# Copyright (C) 2009-2014 John Winters
# See COPYING and LICENCE in the root directory of the application
# for more information.


#
#  Note that this isn't a real Rails model - it doesn't inherit from
#  ActiveRecord at all.
#
class Teachinggroup

  def self.new
    g = Group.new
    g.persona_class = Teachinggrouppersona
    g
  end

  def self.current
    Group.current.where("persona_type = ?", "Teachinggrouppersona")
  end

  def self.where(given_hash)
    #
    #  Does anything need re-directing to a join?
    #
    if given_hash[:source_id]
      #
      #  Need to split this up.
      #
      outer_hash = Hash.new
      inner_hash = Hash.new
      given_hash.each do |key, value|
        if key == :source_id
          inner_hash[key] = value
        else
          outer_hash[key] = value
        end
      end
      outer_hash[:teachinggrouppersonae] = inner_hash
      Group.joins(:teachinggrouppersona).where(outer_hash)
    else
      given_hash[:persona_type] = "Teachinggrouppersona"
      Group.where(given_hash)
    end
  end

  #
  #  Typically called with: { :source_id => 1234 }
  #
  def self.find_by(given_hash)
    self.where(given_hash).take
  end

end
