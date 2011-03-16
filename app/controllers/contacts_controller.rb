# Import contacts from user's external accounts.

class ContactsController < ApplicationController
  before_filter :login_required

  VALID_PROVIDERS = ["GMAIL", "YAHOO", "WINDOWSLIVE"]

  def import
    info = current_user.begin_contact_import(params[:provider])
    session["import_id"] = info[:import_id]
    @consent_url = info[:consent_url]

    redirect_to @consent_url
  end

  def import_callback
    redirect_to new_invitation_path(:wait => true)
  end

  def fetch
    begin
      success = current_user.import_contacts!(session["import_id"])
      session["import_id"] = nil
    rescue Shapado::ContactImportException => e
      success = false
    end

    respond_to do |format|
      format.js do
        render :json => {:success => success}.to_json
      end
    end
  end

  def search
    @contacts =
      Contact.filter(params[:q],
                     :fields => {
                       :user_id => current_user.id,
                       :corresponding_user_id => nil
                     },
                     :per_page => 7)

    respond_to do |format|
      format.js do
        render :json => @contacts.map{ |c|
          {:name => c.name, :email => c.email}
        }.to_json
      end
    end

  end

end
