class UsersController < ApplicationController
  def index
    @users = User.where(name: params[:q])  # correct: bound parameter, no interpolation
  end
end
