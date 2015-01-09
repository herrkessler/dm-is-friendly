# Home baked self-referential :through relationship
module DataMapper
  module Is
    module Friendly
      
      def is_friendly(options = {})
        options = {:require_acceptance => true, :friendship_class => "Friendship" }.merge(options)
        
        list                 = self.name.split("::")
        list.shift if DataMapper::Ext.blank?(list.first)
        reference_model      = self
        reference_model_name = list.pop
        reference_model_key  = DataMapper::Inflector.underscore(reference_model_name).to_sym
        
        namespace = list.empty? ? ::Object : DataMapper::Ext::Object.full_const_get(list.join('::'))
        
        @friendly_config = FriendlyConfig.new(reference_model_name, "#{namespace}::#{options[:friendship_class]}", options[:require_acceptance])
        def self.friendly_config; @friendly_config; end

        DataMapper::Model.new(options[:friendship_class], namespace) do          
          if options[:require_acceptance]
            property :accepted_at, DateTime
          end

          property :created_at, DateTime
          property :update_at, DateTime
          
          belongs_to reference_model_key, reference_model, :key => true
          belongs_to :friend, :model => reference_model, :child_key => [:friend_id], :key => true
        end
        
        has n, :friendships, :model => options[:friendship_class]
        
        has n, :friends_by_me, self, :through => :friendships, :via => reference_model_key
        has n, :friended_by,   self, :through => :friendships, :via => reference_model_key
        
        include DataMapper::Is::Friendly::InstanceMethods
      end
      
      # This class holds the configuration options for the plugin.
      class FriendlyConfig
        attr_reader :reference_model_name, :friendship_foreign_key, :friend_foreign_key
        
        def initialize(ref_model_name, friendship_class, require_acceptance)
          @reference_model_name        = ref_model_name
          @friendship_class_name  = friendship_class
          @friendship_foreign_key = DataMapper::Inflector.foreign_key(@reference_model_name).to_sym
          @friend_foreign_key     = DataMapper::Inflector.foreign_key(@friendship_class_name).to_sym
          @require_acceptance     = require_acceptance
        end
        
        def friendship_class
          DataMapper::Ext::Object.full_const_get(@friendship_class_name)
        end
        
        def require_acceptance?
          @require_acceptance
        end   
      end
      
      module InstanceMethods
        
        # returns all of the friends this person has that are accepted
        # @return [DataMapper::Collection] All the person's friends
        def friends
          friendship_requests(nil,true) | friendships_to_accept(nil,true)
        end
                
        # returns all the people I have requested frienship from
        # @param friend (nil)
        # @param include_accepted (false)
        # @return [DataMapper::Collection] All the people that the person has sent friendship requests to
        def friendship_requests(friend = nil, include_accepted = false)
          conditions = {}
          friend_acceptance_condition(conditions, include_accepted)
          friend_scope_condition(conditions, friend)
          
          conditions[friendly_config.friendship_foreign_key] = self.id
          friendly_config.friendship_class.all(conditions).friend
        end
                
        # returns all the people that have requested my friendship
        # @param friend (nil)
        # @param include_accepted (false)
        # @return [DataMapper::Collection] All the people that have requested friendship
        def friendships_to_accept(friend = nil, include_accepted = false)
          conditions = {}
          friend_acceptance_condition(conditions, include_accepted)
          friend_scope_condition(conditions, friend, true)
          
          conditions[:friend_id] = self.id                      
          friendly_config.friendship_class.all(conditions).send(friendly_config.reference_model_name.downcase)
        end
        
        # see if there is a pending friendship request from this person to another
        # @param friend
        # @return [true, false]
        def friendship_requested?(friend)
          !friendship_requests(friend).empty?
        end
        
        # see if user has a friend request to accept from this person
        # @param friend
        # @return [true, false]
        def friendship_to_accept?(friend)
          return false unless friendly_config.require_acceptance?
          !friendships_to_accept(friend).empty?
        end

        # Accepts a user object and returns true if both users are
        # friends and the friendship has been accepted.
        # @param friend
        # @return [true, false]
        def is_friends_with?(friend)
          !self.friendship(friend).nil?
        end        
        
        # request friendship from "friend"
        # @param friend The friend who's friendship is being requested
        # @return The instance of the friendship_class
        def request_friendship(friend)
          return false if friendship(friend)
          self.friendships.create(:friend => friend)
        end
        
        # Accepts a user  and updates an existing friendship to be accepted.
        # @param friend The friend that needs to be confirmed
        # @return [self]
        def confirm_friendship_with(friend)
          self.friendship(friend,{:accepted_at => nil}).update({:accepted_at => Time.now})
          # reload so old relationship won't be lingering in the IdentityMap
          friend.reload
          self.reload
        end

        # Accepts a user and deletes a friendship between both users.
        # @param friend The friend who's friendship will now end
        # @return [true, false] Outcome of model.destroy
        def end_friendship_with(friend)
          self.friendship(friend).destroy if self.is_friends_with?(friend)
        end
        
        protected
        # Accepts a user and returns the friendship instance associated with both users.
        def friendship(friend, opts = {})
          friendly_config.friendship_class.first({:conditions => ["(#{friendly_config.friendship_foreign_key} = ? AND friend_id = ?) OR (friend_id = ? AND #{friendly_config.friendship_foreign_key} = ?)", self.id, friend.id, self.id, friend.id]}.merge(opts) )
        end
        
        def friendly_config; self.class.friendly_config; end                
        
        private
        def friend_acceptance_condition(conditions, accepted = false)
          accepted ? (conditions[:accepted_at.not] = nil) : (conditions[:accepted_at] = nil) if friendly_config.require_acceptance?
        end
        
        def friend_scope_condition(conditions, friend = nil, for_me = false)
          return unless friend
          key_name = for_me ? friendly_config.friendship_foreign_key : :friend_id
          conditions[key_name] = friend.id
          conditions[:limit] = 1
        end
      end
    end # Friendly
  end # Is
end # DataMapper
