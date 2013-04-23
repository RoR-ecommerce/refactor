# Controller

class People < ActionController::Base

  # ... Other REST actions

  def create
    @person = Person.new(params[:person])
    if @person.save
      redirect_to @person, :notice => "Account added!"
    else
      render :new
    end
  end

  def validateEmail
    @user = Person.find_by_slug(params[:slug])
    if @user.present?
      @user.validated = true
      @user.save
      Rails.logger.info "USER: User ##{@person.id} validated email successfully."
      @admins = Person.where(:admin => true)
      Emails.admin_user_validated(@admins, user)
      Emails.welcome(@user).deliver!
    end
  end

end


# Model

class Person < ActiveRecord::Base
  # Looks like :handle, :team are not needed
  attr_accessible :first_name, :last_name, :email, :admin, :validated

  validates :first_name,  :presence => true
  validates :last_name,  :presence => true
  validates :email,  :presence => true
  # validates :admin,  :presence => true # default this to false in the migration
  validates :slug,  :presence => true

  before_validation :set_defaults, :on => :create
  after_create :send_welcome_emails

  def handle
    "#{team}#{id}"
  end

  def team
    id.odd? ? "UnicornRainbows" : "LaserScorpions"
  end

  def self.admin_emails
    Person.admin.pluck(:email)
  end

  def self.admin
    where(:admin => true)
  end

  private

  def send_welcome_emails
    Emails.validate_email(self.id).deliver
    Emails.admin_new_user(self.id).deliver
  end

  def set_defaults
    set_slug
    set_admin
  end
  # I don't like this slug.  Why do we need it?
  def set_slug
    self.slug = "ABC123#{Time.now.to_i.to_s}1239827#{rand(10000)}"
  end
  def set_admin
    self.admin = false if admin.nil?
  end
end


# Mailer

class Emails < ActionMailer::Base

  def welcome(person)
    @person = person
    mail to: @person, from: 'foo@example.com'
  end

  def validate_email(person_id)
    @person = Person.find( person_id )
    mail to: @person.email, from: 'foo@example.com'
  end

  def admin_user_validated(admins, user)
    @admins = Person.admin_emails
    @user = user
    mail to: @admins, from: 'foo@example.com'
  end

  def admin_new_user(person_id)
    @admins = Person.admin_emails
    @user = Person.find(person_id)
    mail to: @admins, from: 'foo@example.com'
  end

  def admin_removing_unvalidated_users(admins, users)
    @admins = Person.admin_emails
    @users = users
    mail to: @admins, from: 'foo@example.com'
  end

end


# Rake Task

namespace :accounts do

  desc "Remove accounts where the email was never validated and it is over 30 days old"
  task :remove_unvalidated do
    @people = Person.where('created_at < ?', Time.now - 30.days).where(:validated => false)
    @people.each do |person|
      Rails.logger.info "Removing unvalidated user #{person.email}"
      person.destroy
    end
    Emails.admin_removing_unvalidated_users(Person.where(:admin => true), @people).deliver
  end

end
