IMPORT_DIR = 'import'
ISAMS_IMPORT_DIR = 'import/isams/Current'

class MIS_Loader

  class ISAMS_Data < Hash
    attr_reader :xml, :loader

    #
    #  The order of these is perhaps slightly surprising.  At present
    #  I'm using the Event => Group link from the iSAMS d/b, but there
    #  is also a Group => Event link.  I may well switch to the latter,
    #  in which case events will need to be loaded before groups.
    #
    TO_SLURP = [
      ISAMS_ActivityGroup,
      ISAMS_ActivityGroupPupilLink,
      ISAMS_ActivityEvent,
      ISAMS_ActivityEventOccurrence,
      ISAMS_ActivityEventTeacherLink,
      ISAMS_Cover
    ]

    def initialize(loader)
      super()
      @loader = loader
      full_dir_path = Rails.root.join(ISAMS_IMPORT_DIR)
      @xml =
        Nokogiri::XML(File.open(File.expand_path("data.xml", full_dir_path)))
      TO_SLURP.each do |is_type|
        unless is_type.construct(self, full_dir_path)
          puts "Failed to load #{is_type}"
        end
      end
      if loader.options.verbose
        self.each do |key, data|
          puts "Got #{data.count} records with index #{key}."
        end
      end
    end

  end

  attr_reader :secondary_staff_hash,
              :secondary_location_hash,
              :tegs_by_name_hash,
              :tugs_by_name_hash,
              :pupils_by_school_id_hash,
              :subjects_by_name_hash

  def prepare(options)
    ISAMS_Data.new(self)
  end

  def mis_specific_preparation
    @pupils_by_school_id_hash = Hash.new
    @pupils.each do |pupil|
      @pupils_by_school_id_hash[pupil.school_id] = pupil
    end
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
    @secondary_location_hash = Hash.new
    @locations.each do |location|
      @secondary_location_hash[location.name] = location
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
    @subjects_by_name_hash = Hash.new
    @subjects.each do |subject|
      @subjects_by_name_hash[subject.name] = subject
    end
    #
    #  Only now can we populate the other half groups.
    #
    MIS_Otherhalfgroup.populate(self)
    #
    #  Here we should really have finished, but we need to cope with
    #  iSAMS's broken API.  There are more groups which are simply
    #  missing from their data.
    #
    #  Now it gets messy.
    #
    proposed_extra_group_names =
      @timetable.list_missing_teaching_groups(self)
    proposed_extra_group_names.each do |name|
      tg = @tugs_by_name_hash[name.split[0]]
      if tg
        extra_group =
          ISAMS_FakeTeachinggroup.new(name, tg, @subjects_by_name_hash)
        @teachinggroups << extra_group
        @tegs_by_name_hash[extra_group.name] = extra_group
      end
    end
  end
end
