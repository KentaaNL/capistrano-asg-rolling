# frozen_string_literal: true

module Capistrano
  module ASG
    module Rolling
      # AWS EC2 EBS snapshot.
      class Snapshot
        include AWS

        attr_reader :id

        def initialize(id)
          @id = id
        end

        def delete
          aws_ec2_client.delete_snapshot(snapshot_id: id)
        end
      end
    end
  end
end
