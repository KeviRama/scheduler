class CommitmentsController < ApplicationController
  before_action :set_commitment, only: [:approve, :reject, :destroy, :view]

  class ElementWithRequests

    attr_reader :element, :pending_commitments, :rejected_commitments

    def initialize(element)
      @element = element
      @pending_commitments = Array.new
      @rejected_commitments = Array.new
    end

    def note(commitment)
      if commitment.rejected
        @rejected_commitments << commitment
      else
        @pending_commitments << commitment
      end
    end

    def anything_outstanding?
      @rejected_commitments.size > 0 ||
      @pending_commitments.size > 0
    end

    def to_partial_path
      "request_set"
    end

  end

  #
  #  Slightly unusually, doesn't give a list of all the commitments
  #  (which would be vast), but lists those in the future over which
  #  we have approval authority.
  #
  def index
    if current_user.element_owner
      @requests = Array.new
      current_user.concerns.owned.each do |concern|
        Rails.logger.debug("Processing concern with #{concern.element.name}")
        requests = ElementWithRequests.new(concern.element)
        concern.element.commitments.tentative.each do |commitment|
          Rails.logger.debug("Event ends at #{commitment.event.ends_at}")
          Rails.logger.debug("Currently #{Date.today}")
          if commitment.event.ends_at >= Date.today
            requests.note(commitment)
          end
        end
        @requests << requests
      end
      Rails.logger.debug("Got #{@requests.size} owned elements.")
    else
      #
      #  Shouldn't be able to get here, but if someone is playing at
      #  silly buggers then kick them out.
      #
      redirect_to '/'
    end
  end

  # POST /commitments
  # POST /commitments.json
  def create
    Rails.logger.debug("Creating a commitment.")
    @commitment = Commitment.new(commitment_params)
    Rails.logger.debug("@commitment.element.owned = #{@commitment.element.owned}")
    Rails.logger.debug("current_user.owns?(@commitment.element) = #{current_user.owns?(@commitment.element)}")
    if @commitment.element.owned &&
       !current_user.owns?(@commitment.element)
      @commitment.tentative = true
      Rails.logger.debug("Set tentative to true.")
    end
    #
    #  Not currently checking the result of this, because regardless
    #  of whether it succeeds or fails, we just display the list of
    #  committed resources again.
    #
    @commitment.save!
    @commitment.reload
    Rails.logger.debug("Commitment.tentative = #{@commitment.tentative}")
    @event = @commitment.event
    respond_to do |format|
      format.js
    end
  end

  # DELETE /commitments/1.js
  def destroy
    @event = @commitment.event
    @commitment.destroy
    respond_to do |format|
      format.js
    end
  end

  #
  #  View the event for a specific commitment in context.
  #
  def view
  end

  # PUT /commitments/1/approve.js
  #
  #  Must check first whether the user has appropriate permissions to
  #  approve this commitment.  Theoretically, this has already been
  #  taken care of in the JavaScript front end, but it's always possible
  #  that someone will attempt to circumvent that.
  #
  #  If an unauthorised attempt is made, we don't actually comment on
  #  it (since that would give additional information to the attempted
  #  malefactor) but just re-display the event's commitments, meaning
  #  that he should lost any hand-crafted approve button which he
  #  previously created.
  #
  def approve
    @event = @commitment.event
    @editing = current_user.can_edit?(@event)
    if current_user.can_approve?(@commitment) && @commitment.tentative
      @commitment.approve_and_save!(current_user)
      @event.reload
    end
    respond_to do |format|
      format.js
    end
  end

  # PUT /commitments/1/reject.js
  def reject
    @event = @commitment.event
    @editing = current_user.can_edit?(@event)
    if current_user.can_approve?(@commitment) &&
      (@commitment.tentative || @commitment.constraining)
      @commitment.reject_and_save!(current_user, params[:reason])
      @event.reload
    end
    respond_to do |format|
      format.js
    end
  end

  private
    def authorized?(action = action_name, resource = nil)
      logged_in? && current_user.create_events?
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_commitment
      @commitment = Commitment.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def commitment_params
      params.require(:commitment).permit(:event_id, :element_id, :element_name)
    end
end
