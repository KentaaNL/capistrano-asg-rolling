# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # Helper for creating tags from Capistrano specific variables.
      module Tags
        module_function

        # The tags to add to an AMI.
        def ami_tags
          application_tags.merge(deployment_tags).merge(gem_tags)
        end

        # Tags related to the current application / stage.
        def application_tags
          {
            application: fetch(:application),
            stage: fetch(:stage)
          }.compact.transform_keys { |tag| "capistrano-asg-rolling:#{tag}" }
        end

        # Tags related to the current deployment, such as git revisions.
        def deployment_tags
          {
            branch: fetch(:branch),
            user: fetch(:local_user),
            revision: fetch(:current_revision),
            release: fetch(:release_timestamp)
          }.compact.transform_keys { |tag| "capistrano-asg-rolling:deployment-#{tag}" }
        end

        # Tags related to the current gem version.
        def gem_tags
          {
            'capistrano-asg-rolling:gem-version' => Capistrano::ASG::Rolling::VERSION
          }
        end
      end
    end
  end
end
