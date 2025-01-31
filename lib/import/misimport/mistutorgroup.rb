class MIS_Tutorgroup < MIS_Group

  DB_CLASS = Tutorgroup
  add_fields(:FIELDS_TO_CREATE, [:staff_id, :house, :start_year])
  add_fields(:FIELDS_TO_UPDATE, [:staff_id, :house, :start_year])

  attr_reader :staff, :pupils

  def add_pupil(pupil)
    @pupils << pupil
  end

  def members
    @pupils
  end

  def note_tutor(staff)
    @staff = staff
  end

  def staff_id
    if @staff.dbrecord
      @staff.dbrecord.id
    else
      nil
    end
  end

  def size
    @pupils.count
  end

  #
  #  Methods to be provided by MIS-specific code modules.
  #
  def self.construct(loader, mis_data)
    #
    #  Note that an MIS-specific version should also call super,
    #  which calls not this method, but the one in MIS_Group.
    #
    super
  end

  #
  #  Finish off setting ourselves up.  Can only do this after discovering
  #  who our members are.
  #
  def finalize
  end

end
