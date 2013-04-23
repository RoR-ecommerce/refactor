# Controllers

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
end

class PersonValidation < ActionController::Base
  # move this to it's own controller..  I LIKE REST
  def update
    @user = Person.find_by_slug(params[:slug])
    if @user.present?
      @user.set_validated!
    else
      flash[:alert] = 'Sorry we could not process'
      redirect_to sorry_email_validation_failed_url
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

  # Move to Model.  Still I'd have to ask someone why we have this code in the first place
  def team
    id.odd? ? "UnicornRainbows" : "LaserScorpions"
  end

  def set_validated!
    if !@user.validated
      @user.update_attribute(:validated,  true)
      # why is this here?
      Rails.logger.info "USER: User ##{@person.id} validated email successfully."
      Emails.admin_user_validated(@user.id)
      Emails.welcome(@user.id).deliver
    end
  end

  def self.admin_emails
    Person.admin.pluck(:email)
  end

  def self.admin
    where(:admin => true)
  end

  def self.unvalidated
    where(:validated => false)
  end

  def created_longer_than(days_ago )
    where('created_at < ?', Time.zone.now - days_ago.days)
  end

  private

  # welcome emails are set on creation
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

  # by default this is not and admin user
  def set_admin
    self.admin = false if admin.nil?
  end
end


# Mailer

# Next step move these all to a background job like resque
class Emails < ActionMailer::Base
  default :from => "foo@example.com"

  def welcome(person_id)
    @person = Person.find( person_id )
    mail to: @person.email
  end

  def validate_email(person_id)
    @person = Person.find( person_id )
    mail to: @person.email
  end

  def admin_user_validated(person_id)
    @admins = Person.admin_emails
    @user   = Person.find( person_id )
    mail to: @admins
  end

  def admin_new_user(person_id)
    @admins = Person.admin_emails
    @user   = Person.find(person_id)
    mail to: @admins
  end

  # best to move to a log file or something.  or even just inactivating the emails
  def admin_removing_unvalidated_users(user_emails)
    @admins = Person.admin_emails
    @user_emails  = user_emails
    mail to: @admins
  end

end


# Rake Task

namespace :accounts do
  # rake accounts:remove_unvalidated --trace
  desc "Remove accounts where the email was never validated and it is over 30 days old"
  task :remove_unvalidated do
    # this is memory intensive...  best to move to a log file or something other than emailing to someone
    @emails = Person.created_longer_than( 30 ).unvalidated.pluck(:email)
    # find in batches...  memory HOG
    Person.created_longer_than( 30 ).unvalidated.find_each do |person|
      Rails.logger.info "Removing unvalidated user #{person.email}"
      person.destroy # i don't like destroying...  inactive please.
    end
    Emails.admin_removing_unvalidated_users(@emails).deliver
  end
end
