# Manage synchronization between our models and the search index.

require 'net/http'
require 'builder'

module Support::Search
  @@enabled = true

  def self.disable
    @@enabled = false
  end

  def self.enable
    @@enabled = true
  end

  def self.enabled?
    @@enabled
  end

  # Send a command via a post request to the server. The command must
  # be in XML form.
  def self.send_command_to_search_server(data)
    return unless Support::Search.enabled?
    Net::HTTP.start(AppConfig.search["host"],
                    AppConfig.search["port"]) do |http|
      req = Net::HTTP::Post.new("/solr/update?commit=true")
      req.basic_auth AppConfig.search["user"], AppConfig.search["password"]
      req.content_type = "app/xml"
      response = http.request(req, data)
    end
  end

  # Look for terms matching the given query in the search server and
  # return them. Use the keys :topics, :users and :questions to access
  # each class of results.
  def self.query(q)
    resp = Net::HTTP.get(AppConfig.search["host"],
                         "/solr/select?wt=json&q=#{q}",
                         AppConfig.search["port"])
    resp = JSON.parse(resp)["response"]["docs"].
      group_by{ |result| result["entry_type"] }

    {}.tap{ |found|
      resp.each do |k, results|
        found[k.underscore.pluralize.to_sym] =
          k.constantize.query(:id.in => results.map{ |r| r["id"] })
      end
    }
  end

  # This module expects the following methods to be implemented by the
  # including class:
  #
  #  - search_entry : returns a hash with the fields that should go into
  #    the search server.
  #
  module Searchable
    def self.included(klass)
      klass.class_eval do
        include InstanceMethods
        after_save :update_search_index

        before_destroy :will_be_removed_from_search_index!
        after_destroy :remove_from_search_index
      end
    end

    module InstanceMethods

      def search_entry
        raise NotImplementedError
      end

      # Convert the hash representation of the object returned by
      # #search_entry into the format understood by Solr.
      def serialize_for_search_server
        data = Builder::XmlMarkup.new
        data.add {
          data.doc {
            self.search_entry.each do |k, v|
              data.field(v.to_s, :name => k.to_s)
            end
          }
        }
        data.target!
      end

      # after_save callback that propagates changes to the object to
      # the search index when needed. If called with true, forces the
      # update.
      def update_search_index(force = false)
        return unless Support::Search.enabled?
        if !@will_be_removed_from_search_index &&
            (force || self.needs_to_update_search_index?)
          Support::Search.delay.
            send_command_to_search_server self.serialize_for_search_server
        end
        @needs_to_update_search_index = false
      end

      # Removes entry from search index.
      def remove_from_search_index
        return unless Support::Search.enabled?
        command = Builder::XmlMarkup.new
        command.delete {
          command.query "id:#{self.id}"
        }
        Support::Search.delay.send_command_to_search_server(command.target!)
      end

      # We mark this to avoid unnecessary updates from being sent when
      # e.g. a destroyed external account tries to update the search
      # index for its user.
      def will_be_removed_from_search_index!
        @will_be_removed_from_search_index = true
      end

      def needs_to_update_search_index
        @needs_to_update_search_index = true
      end

      def needs_to_update_search_index?
        @needs_to_update_search_index
      end
    end
  end
end
