IMPORT_DIR = 'import'
ISAMS_IMPORT_DIR = 'import/isams'

class MIS_Loader

  class ISAMS_Data < Hash
    attr_reader :xml

    TO_SLURP = [
      ISAMS_ActivityEvent,
      ISAMS_ActivityEventOccurrence,
      ISAMS_ActivityEventTeacherLink
    ]

    def initialize
      super
      full_dir_path = Rails.root.join(ISAMS_IMPORT_DIR)
      @xml =
        Nokogiri::XML(File.open(File.expand_path("data.xml", full_dir_path)))
      TO_SLURP.each do |is_type|
        unless is_type.construct(self, full_dir_path)
          puts "Failed to load #{is_type}"
        end
      end
      self.each do |key, data|
        puts "Got #{data.count} records with index #{key}."
      end
    end

  end

  attr_reader :secondary_staff_hash,
              :tegs_by_name_hash,
              :tugs_by_name_hash

  def prepare(options)
    ISAMS_Data.new
  end

  def mis_specific_preparation
    @secondary_staff_hash = Hash.new
    @staff.each do |staff|
      #
      #  iSAMS's API is a bit brain-dead, in that sometimes they refer
      #  to staff by their ID, and sometimes by what they call a UserCode
      #
      #  The UserCode seems to be being phased out (marked as legacy on
      #  form records), but on lessons at least it is currently the
      #  only way to find the relevant staff member.
      #
      @secondary_staff_hash[staff.secondary_key] = staff
    end
    #
    #  Likewise, the schedule records are a bit broken, in that they
    #  provide no means to link the relevant sets.  For now we're
    #  frigging it a bit and using names.
    #
    @tegs_by_name_hash = Hash.new
    @teachinggroups.each do |teg|
      @tegs_by_name_hash[teg.name] = teg
    end
    @tugs_by_name_hash = Hash.new
    @tutorgroups.each do |tug|
      @tugs_by_name_hash[tug.name] = tug
    end
  end
end
