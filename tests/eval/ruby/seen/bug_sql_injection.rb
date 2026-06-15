class UsersController < ApplicationController
  def index
    @users = User.where("name = '#{params[:q]}'")  # cat#3: interpolated SQL (SQLi)
  end
end
