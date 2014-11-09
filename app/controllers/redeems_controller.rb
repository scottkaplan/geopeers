class RedeemsController < ApplicationController
  before_action :set_redeem, only: [:show, :edit, :update, :destroy]

  # GET /redeems
  # GET /redeems.json
  def index
    @redeems = Redeem.all
  end

  # GET /redeems/1
  # GET /redeems/1.json
  def show
  end

  # GET /redeems/new
  def new
    @redeem = Redeem.new
  end

  # GET /redeems/1/edit
  def edit
  end

  # POST /redeems
  # POST /redeems.json
  def create
    @redeem = Redeem.new(redeem_params)

    respond_to do |format|
      if @redeem.save
        format.html { redirect_to @redeem, notice: 'Redeem was successfully created.' }
        format.json { render action: 'show', status: :created, location: @redeem }
      else
        format.html { render action: 'new' }
        format.json { render json: @redeem.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /redeems/1
  # PATCH/PUT /redeems/1.json
  def update
    respond_to do |format|
      if @redeem.update(redeem_params)
        format.html { redirect_to @redeem, notice: 'Redeem was successfully updated.' }
        format.json { head :no_content }
      else
        format.html { render action: 'edit' }
        format.json { render json: @redeem.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /redeems/1
  # DELETE /redeems/1.json
  def destroy
    @redeem.destroy
    respond_to do |format|
      format.html { redirect_to redeems_url }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_redeem
      @redeem = Redeem.find(params[:id])
    end

    # Never trust parameters from the scary internet, only allow the white list through.
    def redeem_params
      params.require(:redeem).permit(:share_id, :device_id)
    end
end
