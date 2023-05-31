# Capistrano Auto Scaling Group rolling deployments

[![Gem Version](https://badge.fury.io/rb/capistrano-asg-rolling.svg)](https://badge.fury.io/rb/capistrano-asg-rolling)
[![Build Status](https://github.com/KentaaNL/capistrano-asg-rolling/actions/workflows/test.yml/badge.svg)](https://github.com/KentaaNL/capistrano-asg-rolling/actions)
[![Code Climate](https://codeclimate.com/github/KentaaNL/capistrano-asg-rolling/badges/gpa.svg)](https://codeclimate.com/github/KentaaNL/capistrano-asg-rolling)

Capistrano plugin for performing rolling updates to AWS Auto Scaling Groups using the [instance refresh feature](https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html).

Instead of deploying to live servers, capistrano-asg-rolling will create a temporary instance for deployment and then trigger an instance refresh to perform a rolling update of the Auto Scaling Group(s). In more detail, during deployment it will:

- Launch an instance from the AMI defined in the Launch Template of the Auto Scaling Group(s).
- Deploy your application to the launched instances.
- After deployment, stop the instances and create an AMI for each instance.
- Create new Launch Template versions for the new AMIs.
- Trigger Instance Refresh on the Auto Scaling Group(s) to perform a rolling update.
- Delete any outdated Launch Template versions, AMIs and snapshots created by previous deployments.
- Terminate the no longer needed instances.

## Caveats

#### Instance refresh limitations

Please be aware of the limitations of using instance refresh, in particular "Instances terminated before launch": https://docs.aws.amazon.com/autoscaling/ec2/userguide/asg-instance-refresh.html#instance-refresh-limitations

#### Launch Templates

This gem depends on Auto Scaling Groups with Launch Templates. Using an Auto Scaling Group with a Launch Configuration is not supported, and will raise an `Capistrano::ASG::Rolling::NoLaunchTemplate`.

Instance refresh uses the desired configuration to update the Launch Template version of the Auto Scaling Group after a succesful deployment. Setting the Launch Template version to `Latest` on the Auto Scaling Group is not needed.

#### Experimental

This gem is experimental, it works for our configuration / use case, but might not for yours.

The configuration options are not considered stable and might be changed or removed in future releases.

The gem could have a better / fancier name.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'capistrano-asg-rolling'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-asg-rolling

Add the plugin to Capistrano's Capfile:

```ruby
# Capfile
require 'capistrano/asg/rolling'
install_plugin Capistrano::ASG::Rolling::Plugin
```

## Configuration

Below are the Capistrano configuration options:

Setup AWS credentials:

```ruby
# config/deploy.rb
set :aws_access_key_id,     ENV['AWS_ACCESS_KEY_ID']
set :aws_secret_access_key, ENV['AWS_SECRET_ACCESS_KEY']
set :aws_region,            ENV['AWS_REGION']
```

After deployment, any outdated Launch Template versions, AMIs and snapshots will be deleted. By default, the number of `keep_releases` will be kept. Change this with:

```ruby
# config/deploy.rb
set :asg_rolling_keep_versions, 10
```

Servers are added using their private IP address by default. Set to false to use the public IP address instead:

```ruby
# config/deploy.rb
set :asg_rolling_use_private_ip_address, false
```

Verbose logging is enabled by default, set to false for less verbose logging:

```ruby
# config/deploy.rb
set :asg_rolling_verbose, false
```

When launching an Instance, you can override any settings defined in the Launch Template with:

```ruby
# config/deploy.rb
set :asg_rolling_instance_overrides, { instance_type: 'c5.large' }
```

## Usage

Specify the Auto Scaling Groups with the keyword `autoscale` instead of using the `server` keyword in Capistrano's stage configuration. Provide the name of the Auto Scaling Group and any properties you want to pass to the server:

```ruby
# config/deploy/<stage>.rb
autoscale 'app-autoscale-group', user: 'deployer', roles: %w[db assets]
autoscale 'web-autoscale-group', user: 'deployer'
```

Now start a deployment with `cap <stage> deploy` and enjoy.

### Deploy without rolling update

There might be cases where you just want to deploy your code to the servers in the Auto Scaling Group(s) without a rolling update.

You can configure rolling updates per autoscaling group by using the `rolling` option:

```ruby
# config/deploy/<stage>.rb
autoscale 'app-autoscale-group', rolling: true    # default: use rolling deployment
autoscale 'web-autoscale-group', rolling: false   # override: use normal deployment
```

### Deploy with a custom percentage of minimum healthy instances during the instance refresh

The instance refresh is triggered by default with a requirement of 100% minimum healthy instances. ie. One instance is replaced at a time, and must be healthy and in-service before the next is replaced. This can mean that instance refreshes take a long time to complete, especially with larger numbers of instances with large warmup values. Reducing this value allows more instances to be terminated and new instances to be brought up at once during the instance refresh. eg. a value of 0 would terminate all instances in the autoscaling group and replace them at once.

You can configure the minimum healthy percentage per autoscaling group using the `healthy_percentage` option:

```ruby
# config/deploy/<stage>.rb
autoscale 'app-autoscale-group', user: 'deployer'                           # default: use standard deployment with 100% minimum healthy instances
autoscale 'web-autoscale-group', user: 'deployer', healthy_percentage: 75   # override: allow 25% of instances to be terminated and replaced at once
```

### Custom stage

The rolling configuration of the stage has a side-effect: any Capistrano tasks you run, will also launch instances per Auto Scaling Group.

For example the command: `cap production rails:console`, will launch a new instance and run `rails:console` and that instance. While that can be useful, you often just want to run the task on the primary server. A solution is to create two stages with different rolling configurations, for example:

```ruby
# config/deploy/production.rb
set :stage, :production

autoscale 'app-autoscale-group', rolling: false, user: 'deployer', roles: %w[db assets]
autoscale 'web-autoscale-group', rolling: false, user: 'deployer'
```

and:

```ruby
# config/deploy/production_rolling.rb
set :stage, :production_rolling
set :rails_env, :production

autoscale 'app-autoscale-group', rolling: true, user: 'deployer', roles: %w[db assets]
autoscale 'web-autoscale-group', rolling: true, user: 'deployer'
```

With these two stages, you can run any tasks with `cap production <task name>` and rolling deployments with `cap production_rolling deploy`.

## IAM policy

The following IAM permissions are required:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:EnterStandby",
                "autoscaling:ExitStandby",
                "autoscaling:StartInstanceRefresh",
                "ec2:CreateImage",
                "ec2:CreateLaunchTemplateVersion",
                "ec2:CreateTags",
                "ec2:DeleteLaunchTemplateVersions",
                "ec2:DeleteSnapshot",
                "ec2:DeregisterImage",
                "ec2:DescribeImages",
                "ec2:DescribeInstances",
                "ec2:DescribeLaunchTemplateVersions",
                "ec2:RunInstances",
                "ec2:StopInstances",
                "ec2:TerminateInstances"
            ],
            "Resource": "*"
        }
    ]
}
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/KentaaNL/capistrano-asg-rolling. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Capistrano::ASG::Rolling project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/KentaaNL/capistrano-asg-rolling/blob/master/CODE_OF_CONDUCT.md).
